import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:core/core.dart';
import 'package:equatable/equatable.dart';
import 'package:shared_models/shared_models.dart';

import 'location_stream.dart';

part 'driver_state.dart';

/// Drives the driver experience: connect → go online → receive/accept offers →
/// drive lifecycle. Location capture lives in the UI (geolocator) and is fed in
/// via [sendLocation] so this cubit stays testable.
class DriverCubit extends Cubit<DriverState> {
  DriverCubit(
    this._realtime,
    this._remote,
    this._ratings, {
    LocationAccessCheck? checkLocation,
    Duration acceptGrace = const Duration(seconds: 5),
    Duration presenceInterval = const Duration(seconds: 30),
  })  : _checkLocation = checkLocation ?? checkLocationAccess,
        _acceptGrace = acceptGrace, // ignore: prefer_initializing_formals
        _presenceInterval = presenceInterval, // ignore: prefer_initializing_formals
        super(const DriverState());

  final RealtimeClient _realtime;
  final DriverRemoteDataSource _remote;
  final RatingsRemoteDataSource _ratings;
  final List<StreamSubscription<dynamic>> _subs = [];

  /// Pre-online location gate (see [goOnline]); injectable for tests.
  final LocationAccessCheck _checkLocation;

  /// How long past the offer window we wait for `trip:assigned` after the
  /// driver tapped Accept before giving up on that offer (see [acceptOffer]).
  final Duration _acceptGrace;
  Timer? _acceptTimer;

  /// Presence re-sync (see [_pollPresence]); the interval is injectable for
  /// tests.
  final Duration _presenceInterval;
  Timer? _presenceTimer;
  int _offlineStrikes = 0;

  AccessTokenProvider? _tokenProvider;

  Future<void> _connectRealtime(String token) {
    final provider = _tokenProvider;
    return provider != null
        ? _realtime.connectWith(provider)
        : _realtime.connect(token);
  }

  /// Connects the socket. With [tokenProvider] the handshake fetches a fresh
  /// access token on every (re)connect; without it the given [token] is used.
  Future<void> init(String token, {AccessTokenProvider? tokenProvider}) async {
    _tokenProvider = tokenProvider;
    _myId = AuthInterceptor.jwtSubject(token);
    // Register every listener BEFORE connecting: a slow/failed first connect
    // used to throw out of here with nothing subscribed, leaving a session that
    // later reconnected fine at the socket level but never heard an offer,
    // assignment, cancellation or up/down edge.
    _subs
      ..add(_realtime.on('trip:offer').listen(
          (d) => _onOffer(RideOffer.fromJson(d))))
      ..add(_realtime.on('trip:offer_expired').listen(
          (d) => _onOfferExpired(tripId: d['tripId'] as String?)))
      ..add(_realtime.on('trip:assigned').listen((d) => _onAssigned(
            d['tripId'] as String,
            // Route from the driver's car to the pickup, so the map can show
            // exactly where they're collecting the rider from.
            approachPolyline: d['driverPolyline'] as String?,
          )))
      ..add(_realtime.on('trip:cancelled').listen((_) => _onCancelledByRider()))
      ..add(_realtime.on('trip:message').listen(_onMessage))
      // The server's view of our presence: sent on every connect and whenever
      // it takes us offline itself (socket drop, stale GPS, presence lost).
      ..add(_realtime.on('driver:status_changed').listen(_onServerStatus))
      // A rejected frame now carries the real message (`{status:'error',
      // code, message, event}`) instead of a masked 'Internal server error'.
      ..add(_realtime.on('exception').listen(_onServerException))
      // Reconnection resilience: re-announce presence and re-fetch the active
      // trip after a dropped socket so the driver's screen stays truthful.
      ..add(_realtime.reconnects.listen((_) => _onReconnect()))
      // Surface socket up/down edges so the UI can show a reconnecting banner.
      ..add(_realtime.connection.listen((up) {
        if (up != state.connected) emit(state.copyWith(connected: up));
      }));
    await _connectRealtime(token);
    // If this app was killed and reopened mid-trip, restore the live trip
    // screen instead of showing the idle "go online" home.
    await _restoreActiveTrip();
    // Today's total for the offline sheet — otherwise it read "Go online to
    // start earning" on every cold start, whatever the driver had made today.
    await _loadTodayEarnings();
  }

  /// Best-effort refresh of [DriverState.lastEarned] (today's total).
  Future<void> _loadTodayEarnings() async {
    try {
      final earnings = await _remote.earnings(range: 'today');
      if (!isClosed) emit(state.copyWith(lastEarned: earnings.total));
    } catch (_) {
      // Cosmetic; the figure refreshes after the next completed trip.
    }
  }

  /// Maps a server trip status to the driver's in-trip phase (null = not a
  /// driver-actionable phase, e.g. a rider-side requested/matching trip).
  static DriverPhase? _phaseForStatus(TripStatus status) {
    switch (status) {
      case TripStatus.accepted:
        return DriverPhase.enRoute;
      case TripStatus.arrived:
        return DriverPhase.arrived;
      case TripStatus.inProgress:
        return DriverPhase.onTrip;
      default:
        return null;
    }
  }

  /// In-flight [_restoreActiveTrip], so a connect-time `on_trip` sync arriving
  /// while [init]/[resumeFromBackground] is already restoring shares the one
  /// request instead of racing it.
  Future<void>? _restoring;

  Future<void> _restoreActiveTrip() =>
      _restoring ??= _doRestoreActiveTrip().whenComplete(() => _restoring = null);

  Future<void> _doRestoreActiveTrip() async {
    try {
      final trip = await _remote.getActiveTrip();
      if (trip == null) return;
      final phase = _phaseForStatus(trip.status);
      if (phase == null) return;
      // We have a live assigned trip → we're effectively online; re-announce
      // presence and restore the trip screen at the right phase.
      _realtime.emit('driver:status', {'status': 'online'});
      emit(state.copyWith(phase: phase, trip: trip));
    } catch (_) {
      // Best effort — offers/events will correct the screen if this fails.
    }
  }

  /// Re-establish the socket after the OS suspended the app. iOS tears the
  /// WebSocket down while backgrounded and socket.io's own retry can stay
  /// wedged — leaving a driver who looks "Online" but receives no offers.
  Future<void> resumeFromBackground(String token) async {
    // Don't trust `isConnected` alone: after a suspend the socket.io client can
    // still report `connected` while its transport is dead. Only skip the
    // reconnect when the live connection stream also says we're up.
    if (_realtime.isConnected && state.connected) {
      await _onReconnect();
      return;
    }
    try {
      await _connectRealtime(token);
      emit(state.copyWith(connected: true));
      await _restoreActiveTrip();
      await _onReconnect();
    } catch (_) {
      emit(state.copyWith(connected: false));
    }
  }

  Future<void> _onReconnect() async {
    if (state.isOnline) {
      _realtime.emit('driver:status', {'status': 'online'});
    }
    final trip = state.trip;
    if (trip == null) return;
    try {
      final fresh = await _remote.getTrip(trip.id);
      // If the rider cancelled while we were offline, drop back to online.
      if (fresh.status == TripStatus.cancelled ||
          fresh.status == TripStatus.completed) {
        emit(state.copyWith(phase: DriverPhase.online, trip: null, riderName: null));
      } else {
        emit(state.copyWith(trip: fresh));
      }
    } catch (_) {
      // Keep the last-known trip; the next event will correct us.
    }
  }

  Future<void> goOnline() async {
    emit(state.copyWith(busy: true, error: null, locationIssue: null));
    // Gate on location access BEFORE flipping the server-side status: an
    // online driver who can't stream GPS never enters the dispatch geo index,
    // so they'd sit "Online" forever without a single offer. Stay offline and
    // tell them what to fix instead.
    final access = await _checkLocation();
    if (access != LocationAccess.granted) {
      emit(state.copyWith(
        busy: false,
        error: locationAccessMessage(access),
        locationIssue: access,
      ));
      return;
    }
    try {
      await _remote.setStatus('online');
      _realtime.emit('driver:status', {'status': 'online'});
      emit(state.copyWith(phase: DriverPhase.online, busy: false));
      _startPresenceSync();
    } on ApiException catch (e) {
      final needsOnboarding = e.message.toLowerCase().contains('onboarding');
      emit(state.copyWith(
        busy: false,
        error: e.message,
        needsOnboarding: needsOnboarding,
      ));
    }
  }

  Future<void> goOffline() async {
    _cancelAcceptTimer();
    _stopPresenceSync();
    try {
      await _remote.setStatus('offline');
    } catch (_) {/* best effort */}
    _realtime.emit('driver:status', {'status': 'offline'});
    emit(state.copyWith(phase: DriverPhase.offline, offer: null));
  }

  /// Saves the vehicle (`POST /drivers/onboarding`, also used to edit it
  /// later). Returns true when the server accepted it; the dialog stays open
  /// on failure so the driver sees why. With [goOnlineAfter] the driver is
  /// put online straight after a successful first-time setup.
  Future<bool> onboard({
    required String make,
    required String model,
    required String plate,
    required String tier,
    String? color,
    bool goOnlineAfter = true,
  }) async {
    // Clear needsOnboarding immediately: the dialog is already up, and any
    // interim emission that still carries needsOnboarding=true would make the
    // page listener open a second copy of it.
    emit(state.copyWith(busy: true, error: null, needsOnboarding: false));
    try {
      await _remote.onboarding(
        vehicleMake: make,
        vehicleModel: model,
        plateNumber: plate,
        vehicleTier: tier,
        vehicleColor: color,
      );
      emit(state.copyWith(busy: false, needsOnboarding: false));
      if (goOnlineAfter) await goOnline();
      return true;
    } on ApiException catch (e) {
      emit(state.copyWith(busy: false, error: e.message));
      return false;
    }
  }

  /// Every 30 s while online and idle, ask the server what it thinks our
  /// presence is. The socket tells us when the server drops us — except in
  /// the one case where our connection looks healthy but the server-side
  /// status was lost (evicted for stale GPS, Redis wiped, ops action). Two
  /// consecutive 'offline' answers flip the UI, so a single poll racing our
  /// own go-online can't kick us off.
  void _startPresenceSync() {
    _presenceTimer?.cancel();
    _offlineStrikes = 0;
    _presenceTimer = Timer.periodic(_presenceInterval, (_) => _pollPresence());
  }

  void _stopPresenceSync() {
    _presenceTimer?.cancel();
    _presenceTimer = null;
    _offlineStrikes = 0;
  }

  Future<void> _pollPresence() async {
    if (!state.isOnline || state.trip != null || state.offer != null) return;
    try {
      final me = await _remote.me();
      if (me.status != 'offline') {
        _offlineStrikes = 0;
        return;
      }
      if (++_offlineStrikes < 2) return;
      _stopPresenceSync();
      _cancelAcceptTimer();
      emit(state.copyWith(
        phase: DriverPhase.offline,
        offer: null,
        busy: false,
        error: 'The server no longer has you online. Go online again to '
            'keep receiving requests.',
      ));
    } catch (_) {
      // Transient network error: try again on the next tick.
    }
  }

  /// Feed a GPS fix in; forwarded to the backend when online/on a trip.
  void sendLocation(
    double lat,
    double lng, {
    double heading = 0,
    double speed = 0,
    double? accuracy,
    DateTime? at,
  }) {
    if (state.phase == DriverPhase.offline) return;
    _realtime.emit('driver:location', {
      'lat': lat,
      'lng': lng,
      'heading': heading,
      'speed': speed,
      // Lets the backend gate noisy fixes out of fare metering and lets the
      // rider detect stale positions.
      'accuracy': ?accuracy,
      'ts': (at ?? DateTime.now()).millisecondsSinceEpoch,
    });
  }

  void acceptOffer() {
    final offer = state.offer;
    if (offer == null) return;
    _realtime.emit('trip:accept', {'tripId': offer.tripId});
    emit(state.copyWith(busy: true));
    // Safety net: if neither `trip:assigned` nor `trip:offer_expired` arrives
    // within the offer window (+ grace), the accept was lost — the rider
    // cancelled mid-window, the socket dropped, or the server never answered.
    // Without this the driver stared at an infinite Accept spinner with
    // Decline disabled, and no new offer could reach them (phase stuck at
    // `offered`).
    _cancelAcceptTimer();
    _acceptTimer = Timer(
      Duration(seconds: offer.expiresInSec) + _acceptGrace,
      () {
        _acceptTimer = null;
        if (isClosed) return;
        if (state.phase != DriverPhase.offered ||
            state.offer?.tripId != offer.tripId) {
          return;
        }
        emit(state.copyWith(
          phase: DriverPhase.online,
          offer: null,
          busy: false,
          error: 'That ride was taken or cancelled',
        ));
      },
    );
  }

  String? _myId;
  bool _chatOpen = false;

  /// Rider messages while the chat page is closed feed the badge on the map
  /// sheet's chat button; our own echoes are ignored.
  void _onMessage(Map<String, dynamic> data) {
    if (_chatOpen) return;
    final from = data['from'] as String?;
    if (from == null || from == _myId) return;
    if (data['tripId'] != null && data['tripId'] != state.trip?.id) return;
    emit(state.copyWith(unreadMessages: state.unreadMessages + 1));
  }

  void setChatOpen(bool open) {
    _chatOpen = open;
    if (open && state.unreadMessages != 0) {
      emit(state.copyWith(unreadMessages: 0));
    }
  }

  void _cancelAcceptTimer() {
    _acceptTimer?.cancel();
    _acceptTimer = null;
  }

  void declineOffer() {
    _cancelAcceptTimer();
    final offer = state.offer;
    if (offer != null) {
      _realtime.emit('trip:decline', {'tripId': offer.tripId});
    }
    emit(state.copyWith(phase: DriverPhase.online, offer: null, busy: false));
  }

  Future<void> markArrived() async {
    final trip = state.trip;
    if (trip == null) return;
    emit(state.copyWith(busy: true, error: null));
    try {
      await _remote.arrived(trip.id);
      emit(state.copyWith(phase: DriverPhase.arrived, busy: false));
    } on ApiException catch (e) {
      emit(state.copyWith(busy: false, error: e.message));
    }
  }

  Future<void> startTrip(String otp) async {
    final trip = state.trip;
    if (trip == null) return;
    emit(state.copyWith(busy: true, error: null));
    try {
      await _remote.start(trip.id, otp);
      emit(state.copyWith(phase: DriverPhase.onTrip, busy: false));
    } on ApiException catch (e) {
      emit(state.copyWith(busy: false, error: e.message));
    }
  }

  Future<void> completeTrip() async {
    final trip = state.trip;
    if (trip == null) return;
    emit(state.copyWith(busy: true, error: null));

    Map<String, dynamic> receipt;
    try {
      receipt = await _remote.complete(trip.id);
    } on ApiException catch (e) {
      emit(state.copyWith(busy: false, error: e.message));
      return;
    } catch (_) {
      emit(state.copyWith(
          busy: false, error: 'Could not complete the trip. Try again.'));
      return;
    }

    // The trip is completed server-side now — move to `completed` IMMEDIATELY so
    // a follow-up failure (e.g. loading earnings) can't leave the driver stranded
    // on the trip screen re-tapping "Complete" on an already-completed trip.
    final isCash = receipt['paymentMode'] == 'cash';
    final cash = isCash ? (receipt['fareFinal'] as num?)?.toDouble() : null;
    emit(state.copyWith(
      phase: DriverPhase.completed,
      trip: null,
      riderName: null,
      unreadMessages: 0,
      busy: false,
      lastTripId: trip.id,
      riderRating: null,
      cashToCollect: cash,
    ));

    // Earnings total is a nice-to-have on the completion sheet — load it
    // best-effort, never reverting the completion above.
    try {
      final earnings = await _remote.earnings(range: 'today');
      if (!isClosed) emit(state.copyWith(lastEarned: earnings.total));
    } catch (_) {
      // Leave lastEarned as-is; the driver is already on the completed sheet.
    }
  }

  /// Rate the rider (1–5) for the just-completed trip.
  Future<void> rateRider(int stars) async {
    final tripId = state.lastTripId;
    if (tripId == null || state.riderRating != null) return;
    try {
      await _ratings.rate(tripId, stars: stars);
      emit(state.copyWith(riderRating: stars));
    } on ApiException catch (e) {
      emit(state.copyWith(error: e.message));
    }
  }

  /// Dismiss the completion sheet and go back online.
  void dismissCompleted() {
    emit(state.copyWith(
      phase: DriverPhase.online,
      lastTripId: null,
      riderRating: null,
    ));
  }

  void _onOffer(RideOffer offer) {
    // Only surface offers while idle-online.
    if (state.phase != DriverPhase.online) return;
    // Drop any stale error (e.g. the previous "taken or cancelled" reset) so
    // the page listener doesn't re-toast it over the new card on this phase
    // change, and so a repeat of the same message can surface again later.
    emit(state.copyWith(phase: DriverPhase.offered, offer: offer, error: null));
  }

  /// The server withdrew an offer — the window elapsed, or the driver accepted
  /// but the trip couldn't be assigned to them (rider cancelled mid-window,
  /// taken by another driver). Clears the card even mid-Accept; a stale event
  /// for some other trip is ignored so it can't wipe a newer offer.
  void _onOfferExpired({String? tripId}) {
    if (state.phase != DriverPhase.offered) return;
    if (tripId != null && state.offer?.tripId != tripId) return;
    _cancelAcceptTimer();
    emit(state.copyWith(
      phase: DriverPhase.online,
      offer: null,
      busy: false,
      error: state.busy ? 'That ride was taken or cancelled' : null,
    ));
  }

  Future<void> _onAssigned(String tripId, {String? approachPolyline}) async {
    try {
      final trip = await _remote.getTrip(tripId);
      _cancelAcceptTimer();
      emit(state.copyWith(
        phase: DriverPhase.enRoute,
        trip: trip,
        offer: null,
        busy: false,
        approachPolyline: approachPolyline,
        // The Trip model carries no rider profile; keep the name from the
        // offer card so the chat header can address the rider by name.
        riderName: state.offer?.riderName,
      ));
    } on ApiException catch (e) {
      emit(state.copyWith(busy: false, error: e.message));
    }
  }

  /// `driver:status_changed` — the server's view of our presence, with why it
  /// changed. `reason: 'sync'` is the snapshot sent on every connect; the
  /// other reasons mean the server flipped us itself. The failure mode this
  /// closes: a socket drop took the driver offline server-side, the app came
  /// back still showing "Online", and riders saw "no drivers" while the driver
  /// sat waiting for offers that could never come.
  void _onServerStatus(Map<String, dynamic> data) {
    final status = data['status'] as String?;
    final reason = data['reason'] as String?;
    switch (status) {
      case 'offline':
        // Mid-trip the server never forces us offline (a brief drop must let
        // the driver resume), so a stray 'offline' with a live trip is stale.
        if (!state.isOnline || state.trip != null) return;
        // The connect-time snapshot can predate our own reconnect re-announce
        // (see [_onReconnect]), which is already on the wire — let it win. If
        // that re-announce is refused, the `exception` frame flips us below.
        if (reason == 'sync') return;
        _cancelAcceptTimer();
        _stopPresenceSync();
        // Make the server match the screen even if a reconnect re-announce
        // raced this event and put us back online without our knowledge.
        _realtime.emit('driver:status', {'status': 'offline'});
        emit(state.copyWith(
          phase: DriverPhase.offline,
          offer: null,
          busy: false,
          error: _forcedOfflineMessage(reason),
        ));
      case 'online':
        // Only the connect-time snapshot may put us online on its own: it
        // means the server still holds our presence from before a relaunch.
        if (state.isOnline || reason != 'sync') return;
        emit(state.copyWith(phase: DriverPhase.online));
      case 'on_trip':
        if (state.isOnline || reason != 'sync') return;
        unawaited(_restoreActiveTrip());
    }
  }

  static String _forcedOfflineMessage(String? reason) {
    switch (reason) {
      case 'stale_location':
      case 'presence_lost':
        return 'You were set offline — no location received for a while. '
            'Go online again.';
      default:
        return "Connection dropped — you're offline. Go online again.";
    }
  }

  /// `exception` — a server handler rejected one of our frames. Nest used to
  /// mask every such error as 'Internal server error'; the real, showable
  /// message now arrives (e.g. "Finish your current trip before going
  /// offline.").
  void _onServerException(Map<String, dynamic> data) {
    final message = data['message'] as String?;
    if (message == null || message.isEmpty) return;
    final code = (data['code'] as num?)?.toInt() ?? 500;
    // A refused `driver:status` (e.g. the reconnect re-announce hit "Documents
    // are not verified yet") means we are NOT online server-side — don't keep
    // showing "Online" with no offers ever coming.
    final refusedOnline = data['event'] == 'driver:status' &&
        code >= 400 &&
        code < 500 &&
        state.isOnline &&
        state.trip == null;
    if (refusedOnline) _cancelAcceptTimer();
    emit(state.copyWith(
      phase: refusedOnline ? DriverPhase.offline : null,
      offer: refusedOnline ? null : state.offer,
      busy: refusedOnline ? false : null,
      error: message,
    ));
  }

  void _onCancelledByRider() {
    _cancelAcceptTimer();
    emit(state.copyWith(
      phase: DriverPhase.online,
      trip: null,
      riderName: null,
      unreadMessages: 0,
      offer: null,
      busy: false,
      error: 'The rider cancelled the trip',
    ));
  }

  @override
  Future<void> close() {
    _cancelAcceptTimer();
    _stopPresenceSync();
    for (final s in _subs) {
      s.cancel();
    }
    // The driver home only unmounts on sign-out (or app teardown). Disconnect
    // so the dispatcher stops treating this driver as online — otherwise the
    // ghost identity keeps receiving offers, and the next sign-in could act
    // over the previous user's socket.
    _realtime.disconnect();
    return super.close();
  }
}
