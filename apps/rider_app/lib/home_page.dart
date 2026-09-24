import 'dart:async';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_models/shared_models.dart';

import 'features/trip/destination_search_page.dart';
import 'features/trip/location_banner.dart';
import 'features/trip/location_service.dart';
import 'features/trip/map_picker_page.dart';
import 'features/trip/map_utils.dart';
import 'features/trip/ride_camera.dart';
import 'features/trip/ride_map_layer.dart';
import 'features/trip/sheets/ride_sheets.dart';
import 'features/trip/trip_cubit.dart';

// The sheets live in their own library; re-exported so the page and its tests
// keep one import.
export 'features/trip/sheets/ride_sheets.dart';

/// Rider home: full-screen map with a bottom sheet that changes with the
/// request phase (where-to → choose ride → finding driver).

class RiderHomePage extends StatelessWidget {
  const RiderHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => TripCubit(
        sl<TripRepository>(),
        sl<RealtimeClient>(),
        sl<PaymentsRemoteDataSource>(),
        sl<RatingsRemoteDataSource>(),
      ),
      child: const _RiderHomeView(),
    );
  }
}

class _RiderHomeView extends StatefulWidget {
  const _RiderHomeView();

  @override
  State<_RiderHomeView> createState() => _RiderHomeViewState();
}

class _RiderHomeViewState extends State<_RiderHomeView>
    with WidgetsBindingObserver {
  final _location = LocationService();
  GeoPoint _myLocation = LocationService.fallback;
  String _myLocationAddr = DestinationSearchPage.unsetPickupLabel;
  // Until GPS (or the dev mock) produces a fix, `_myLocation` is only the
  // city-centre fallback: fine to centre the map on, never a pickup.
  bool _hasRealLocation = false;
  LocationIssue? _locationIssue;
  bool _reducedAccuracy = false;
  List<SavedPlace> _savedPlaces = const [];
  // Set for one frame to hand AppMap a null `fitBounds` so that re-supplying
  // the same bounds on the next frame counts as a change and re-fits the
  // camera (AppMap keys fits on bounds *values*, and suppresses `recenter`
  // while a ≥2-point fit is active) — see _refitCurrentBounds.
  bool _fitSuppressed = false;
  TripPhase _lastPhase = TripPhase.idle;
  // Set when the rider taps "recenter": AppMap follows this to snap back to the
  // rider's live position after they've panned the map away. `_recenterSeq` is
  // bumped with every request because LatLng has value equality — re-storing
  // the same point (GPS hasn't moved, or MOCK_LOCATION) would otherwise be a
  // no-op and the button would feel dead.
  LatLng? _recenter;
  int _recenterSeq = 0;
  // Whether AppMap's camera is still following the car. Flipped false the
  // moment the rider pans the map away, which is what surfaces the "Recenter"
  // pill — the camera yields to them rather than fighting for it.
  bool _following = true;
  // Last seen socket state, so a reconnect (false → true) can be told apart
  // from a rebuild that merely happens to be connected.
  bool _wasConnected = true;

  // The bottom sheet's real height, measured after each frame.
  //
  // This drives the map's `padding`, which does two jobs at once: it keeps the
  // camera framing the strip of map the rider can actually SEE, and it is what
  // positions Google's logo and attribution. A guessed constant here is why the
  // "Google" watermark floated in the middle of the map instead of sitting just
  // above the sheet — the padding was bigger than the sheet it was meant to
  // describe. (The logo cannot be removed: the Maps Platform terms require it
  // to stay visible and unobscured. It can only be positioned.)
  final GlobalKey _sheetKey = GlobalKey();
  double _sheetHeight = 0;
  // The phase whose opening frame has already been shown. While it matches the
  // live phase the camera follows the car instead of re-fitting.
  TripPhase? _followedPhase;

  // Live position watch: keeps the pickup on the phone's real location and, on
  // the FIRST real GPS fix, snaps the camera to it — so the map self-corrects
  // off the fallback without the rider having to tap recenter.
  StreamSubscription<GeoPoint>? _posSub;
  bool _snappedToMe = false;

  // --- Live re-routing ---
  // When the driver's live position leaves the drawn route, we re-fetch the
  // optimal road route from where the car actually is, so the line follows the
  // road the driver took. [_rerouteGate] rate-limits it; [_liveRoutePolyline]
  // holds the freshest line for [_liveRouteLeg] ('approach' or 'trip').
  final RerouteGate _rerouteGate = RerouteGate();
  String? _liveRoutePolyline;
  String? _liveRouteLeg;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadLocation();
    _loadSavedPlaces();
    _connectSocket();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _posSub?.cancel();
    super.dispose();
  }

  /// Watch live GPS so the map lands on the phone's real location on its own.
  /// The first real fix snaps the camera (replacing the fallback); after that we
  /// keep [_myLocation] fresh for the pickup but leave the camera to the rider.
  void _startLocationWatch() {
    _posSub?.cancel();
    _posSub = _location.positionStream().listen((loc) {
      if (!mounted) return;
      // Whether this fix is allowed to move the camera. It is not, whenever a
      // ride owns the map: the person holding this phone is not necessarily
      // the passenger — a ride booked for someone else can have the booker in
      // one city and the car in another — and snapping the camera to the
      // booker's GPS rips them away from the car they are watching. Their
      // position still updates the pickup; it just stops steering the map.
      final mayMove = RideCamera.myLocationMayMoveCamera(
        context.read<TripCubit>().state,
      );
      setState(() {
        _myLocation = loc;
        _hasRealLocation = true;
        _locationIssue = null;
        if (_myLocationAddr == DestinationSearchPage.unsetPickupLabel) {
          _myLocationAddr = 'Current location';
        }
        if (!_snappedToMe && mayMove) {
          _snappedToMe = true;
          _recenter = MapUtils.toLatLng(loc);
          _recenterSeq++;
        }
      });
    }, onError: (_) {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // iOS kills the WebSocket while the app is suspended; re-establish it on
    // resume so live trip updates don't stay dead until a manual restart.
    if (state == AppLifecycleState.resumed) {
      unawaited(_resumeSocket());
      // Back from Settings (banner tap): re-read so the banner clears and
      // the pickup fills in once the rider has enabled location.
      if (_locationIssue != null || _reducedAccuracy) _loadLocation();
    }
  }

  Future<void> _resumeSocket() async {
    final token = await sl<TokenStorage>().readAccessToken();
    if (token != null && mounted) {
      await context.read<TripCubit>().resumeFromBackground(token);
    }
    // The cubit has now pulled the authoritative trip over REST and rebuilt the
    // socket, so the state holds the CURRENT driver position. Move the camera
    // onto it rather than leaving the rider looking at wherever the map was
    // when they locked their phone — including when they had panned away
    // before backgrounding, which used to leave following suspended and the
    // car off screen with no hint that anything had moved.
    if (!mounted) return;
    _resyncCameraToRide();
  }

  /// Read the sheet's height after the frame it was laid out in, and adopt it
  /// if it moved enough to matter.
  ///
  /// The 1px deadband is not cosmetic: calling setState for a sub-pixel
  /// difference would schedule another frame, measure again, and loop forever.
  void _measureSheet() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box = _sheetKey.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) return;
      final height = box.size.height;
      if ((height - _sheetHeight).abs() < 1) return;
      setState(() => _sheetHeight = height);
    });
  }

  /// Put the camera back on the live ride after a gap (resume, reconnect).
  /// Bumping [_recenterSeq] is what makes AppMap honour the request even when
  /// the coordinate is unchanged, and resuming follow mode is what makes the
  /// camera keep up from here on.
  void _resyncCameraToRide() {
    final state = context.read<TripCubit>().state;
    final car = RideCamera.recenterTarget(state);
    if (car == null) return;
    setState(() {
      _recenter = MapUtils.toLatLng(car);
      _recenterSeq++;
      _followedPhase = state.phase;
      _following = true;
    });
  }

  Future<void> _loadLocation() async {
    final result = await _location.resolve();
    if (!mounted) return;
    // See _startLocationWatch: a ride on screen owns the camera.
    final mayMove = RideCamera.myLocationMayMoveCamera(
      context.read<TripCubit>().state,
    );
    setState(() {
      _myLocation = result.point;
      _hasRealLocation = result.isReal;
      _locationIssue = result.issue;
      _reducedAccuracy = result.reducedAccuracy;
      if (!result.isReal) {
        _myLocationAddr = DestinationSearchPage.unsetPickupLabel;
      } else if (_myLocationAddr == DestinationSearchPage.unsetPickupLabel) {
        _myLocationAddr = 'Current location';
      }
      // Move the camera to the resolved location. GoogleMap's initialCenter is
      // one-shot, so without this the map stays on the fallback until the rider
      // taps recenter (seen when GPS/permission resolves after the first frame).
      if (mayMove) {
        _recenter = MapUtils.toLatLng(result.point);
        _recenterSeq++;
      }
      if (result.isReal) _snappedToMe = true;
    });
    // Keep watching GPS so the map self-corrects off the fallback the moment a
    // real fix arrives (indoors/cold start), without a manual recenter.
    _startLocationWatch();
    // The fallback is a city centre, not the rider: no address for it — the
    // pickup field keeps saying "Set pickup location" until they choose one.
    if (!result.isReal) return;
    // Resolve the GPS to a real address so the pickup shows where the rider
    // actually is (e.g. "Bhukum, Pune") instead of a generic label.
    try {
      final place = await sl<TripRepository>().reverseGeocode(
        result.point.lat,
        result.point.lng,
      );
      if (mounted && place.address.isNotEmpty) {
        setState(() => _myLocationAddr = place.address);
      }
    } catch (_) {
      // Non-fatal: keep the generic label if reverse-geocoding fails.
    }
  }

  /// Banner tap: open the relevant Settings page, or just try again.
  /// Which fix-it action a given location problem needs.
  static LocationBannerAction _bannerActionFor(LocationIssue? issue) =>
      switch (issue) {
        LocationIssue.servicesOff => LocationBannerAction.openLocationSettings,
        LocationIssue.deniedForever => LocationBannerAction.openAppSettings,
        LocationIssue.denied ||
        LocationIssue.error ||
        null => LocationBannerAction.retry,
      };

  Future<void> _onLocationBannerAction(LocationBannerAction action) async {
    switch (action) {
      case LocationBannerAction.retry:
        await _loadLocation();
      case LocationBannerAction.openAppSettings:
        await Geolocator.openAppSettings();
      case LocationBannerAction.openLocationSettings:
        await Geolocator.openLocationSettings();
    }
  }

  /// Recenter button. While the camera is framing a ride (route / approach
  /// leg / arrival box) it re-fits those bounds — that is "where the ride
  /// is" — otherwise it snaps back to the rider's live GPS position.
  Future<void> _recenterToMe() async {
    final state = context.read<TripCubit>().state;
    // While a driver is being tracked, "recenter" means the car — that is what
    // the rider is watching. Re-fitting the route here (what it used to do)
    // left them staring at a zoomed-out box with a stale camera, and tapping
    // again did nothing because the bounds had not changed. It is the LATEST
    // driver coordinate, not the previous camera position and not the rider's
    // own GPS, so it works after a pan, after a pinch and after the app comes
    // back from the background.
    final car = RideCamera.recenterTarget(state);
    if (car != null) {
      setState(() {
        _recenter = MapUtils.toLatLng(car);
        _recenterSeq++;
        _followedPhase = state.phase; // resume following after the snap
        _following = true;
      });
      return;
    }
    final bounds = _mapLayer(state).fitBounds;
    if (bounds != null && bounds.length >= 2) {
      _refitCurrentBounds();
      return;
    }
    final result = await _location.resolve();
    if (!mounted) return;
    setState(() {
      _myLocation = result.point;
      _hasRealLocation = result.isReal;
      _locationIssue = result.issue;
      _reducedAccuracy = result.reducedAccuracy;
      _recenter = MapUtils.toLatLng(result.point);
      _recenterSeq++;
    });
  }

  /// AppMap only re-fits when the bounds *values* change and ignores a
  /// recenter request while a fit is active, so a plain rebuild with the
  /// same bounds is a no-op. Clear the bounds for one frame and restore them
  /// on the next: AppMap sees null→bounds and animates the fit again.
  void _refitCurrentBounds() {
    if (_fitSuppressed) return;
    setState(() => _fitSuppressed = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _fitSuppressed = false);
    });
  }

  Future<void> _loadSavedPlaces() async {
    // Returning from the account menu after "Sign out" pops back here for a
    // frame; don't fire an authenticated call with the tokens already gone.
    if (context.read<AuthBloc>().state.status != AuthStatus.authenticated) {
      return;
    }
    try {
      final places = await sl<UsersRemoteDataSource>().listPlaces();
      if (mounted) setState(() => _savedPlaces = places);
    } catch (_) {
      // Quick-picks are a convenience; a load failure just hides them.
    }
  }

  /// Start a ride to a saved place directly from the home sheet. Without a
  /// real position the rider first drops a pickup pin on the map — the
  /// city-centre fallback is never used as a pickup on their behalf.
  Future<void> _pickSaved(SavedPlace place) async {
    var pickup = _myLocation;
    var pickupAddr = _myLocationAddr;
    if (!_hasRealLocation) {
      final chosen = await Navigator.of(context).push<PlaceDetails>(
        MaterialPageRoute(
          builder: (_) => MapPickerPage(
            initial: LocationService.fallback,
            title: 'Set pickup on map',
          ),
        ),
      );
      if (chosen == null || !mounted) return;
      pickup = chosen.location;
      pickupAddr = chosen.address;
    }
    await context.read<TripCubit>().chooseDestination(
      pickup: pickup,
      pickupAddr: pickupAddr,
      dropoff: place.point,
      dropoffAddr: place.address ?? place.label,
    );
  }

  Future<void> _connectSocket() async {
    try {
      final token = await sl<TokenStorage>().readAccessToken();
      if (token != null && mounted) {
        await context.read<TripCubit>().init(
          token,
          tokenProvider: sl<DioClient>().freshAccessToken,
        );
      }
    } catch (_) {
      // Connect can time out; the realtime client retries with backoff and the
      // connection banner reflects status. Swallow so a slow/failed initial
      // connect isn't an unhandled async error.
    }
  }

  Future<void> _openSearch() async {
    final choice = await Navigator.of(context).push<RouteChoice>(
      MaterialPageRoute(
        builder: (_) => DestinationSearchPage(
          // Null when only the fallback is known: the page then insists on
          // an explicit pickup instead of quietly using the city centre.
          initialPickup: _hasRealLocation ? _myLocation : null,
          initialPickupLabel: _myLocationAddr,
          savedPlaces: _savedPlaces,
        ),
      ),
    );
    if (choice != null && mounted) {
      await context.read<TripCubit>().chooseDestination(
        pickup: choice.pickup,
        pickupAddr: choice.pickupAddr,
        dropoff: choice.dropoff,
        dropoffAddr: choice.dropoffAddr,
      );
    }
  }

  /// If the driver has left the drawn route, re-fetch the optimal road route
  /// from the car's live position to its current target (pickup, then dropoff).
  /// Throttled by [_rerouteGate]; best-effort (a failure keeps the current line).
  Future<void> _maybeReroute(TripState state) async {
    final driver = state.driverLocation;
    final layer = _mapLayer(state);
    final leg = layer.legKey;
    if (driver == null || leg == null) return;
    final target = leg == 'approach' ? state.pickup : state.dropoff;
    if (target == null) return;

    final route = layer.plannedRoute;
    if (route.length < 2) return;
    final from = MapUtils.toLatLng(driver);
    final split = splitRouteAtPoint(route, from);
    if (!_rerouteGate.shouldReroute(
      from: from,
      offRouteMeters: split.offRouteMeters,
      leg: leg,
    )) {
      return;
    }
    _rerouteGate.begin();
    String? poly;
    try {
      poly = await sl<TripRepository>().route(
        fromLat: driver.lat,
        fromLng: driver.lng,
        toLat: target.lat,
        toLng: target.lng,
      );
    } catch (_) {
      poly = null;
    } finally {
      _rerouteGate.end(from);
    }
    if (!mounted || poly == null) return;
    setState(() {
      _liveRoutePolyline = poly;
      _liveRouteLeg = leg;
    });
  }

  /// Everything the map draws this frame. One object so the markers, the line
  /// and the camera box are always derived from the same snapshot.
  RideMapLayer _mapLayer(TripState state) => RideMapLayer(
    state: state,
    myLocation: _myLocation,
    liveRoutePolyline: _liveRoutePolyline,
    liveRouteLeg: _liveRouteLeg,
    fitSuppressed: _fitSuppressed,
    followedPhase: _followedPhase,
  );

  static bool _isLiveTracking(TripState state) =>
      RideCamera.tracksDriver(state);

  Future<void> _showTripEndedDialog(BuildContext context, String message) {
    AppHaptics.heavy();
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ride cancelled'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// A live-ride advisory. Informational only — there is one button, and the
  /// wording stays neutral: a driver who leaves the route or stops is usually
  /// dealing with traffic, roadworks or a queue, not doing anything wrong.
  /// Safety actions stay where riders already look for them (the SOS button).
  Future<void> _showRideAlert(BuildContext context, TripAlert alert) {
    AppHaptics.medium();
    final (title, message) = switch (alert.kind) {
      TripAlertKind.offRoute => (
        'Your driver left the route',
        'Your driver is taking a different road. The map has been updated to '
            'follow the route they are actually driving.',
      ),
      TripAlertKind.driverStopped => (
        'Your driver has stopped',
        '${_stoppedFor(alert.stoppedSec)} Message or call them if you need to.',
      ),
    };
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// "Your driver hasn't moved for about 3 minutes." — rounded, because the
  /// exact second is noise and a precise number invites false precision.
  static String _stoppedFor(int? seconds) {
    if (seconds == null || seconds < 60) {
      return "Your driver hasn't moved for a few minutes.";
    }
    final minutes = (seconds / 60).round();
    return "Your driver hasn't moved for about "
        '$minutes ${minutes == 1 ? 'minute' : 'minutes'}.';
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<TripCubit, TripState>(
      listenWhen: (prev, curr) =>
          prev.phase != curr.phase ||
          prev.notice != curr.notice ||
          prev.alert != curr.alert ||
          prev.connected != curr.connected ||
          prev.driverLocation != curr.driverLocation ||
          (curr.phase == TripPhase.idle && prev.error != curr.error),
      listener: (context, state) {
        final cubit = context.read<TripCubit>();
        // Socket came back: the cubit re-syncs the trip, and the map catches
        // up with it. Without this the rider watches "Connected" appear over
        // a car still frozen where the connection dropped.
        if (state.connected && !_wasConnected) _resyncCameraToRide();
        _wasConnected = state.connected;
        // One-shot server notices (payment warnings) as a snackbar.
        final notice = state.notice;
        if (notice != null) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(notice)));
          cubit.clearNotice();
        }
        // Live-ride advisories (driver off route / stopped) as a dialog: the
        // rider is watching a map that no longer matches what is happening,
        // and a snackbar that slides away after four seconds is too easy to
        // miss from the back seat.
        final alert = state.alert;
        if (alert != null) {
          cubit.clearAlert();
          unawaited(_showRideAlert(context, alert));
        }
        // Drop a stale re-routed line when the leg changes (approach → trip),
        // and keep the drawn line on the road the driver actually takes.
        final leg = _mapLayer(state).legKey;
        if (leg != _liveRouteLeg && _liveRoutePolyline != null) {
          _liveRoutePolyline = null;
        }
        unawaited(_maybeReroute(state));
        if (state.phase == _lastPhase) return;
        _lastPhase = state.phase;
        // Let this phase's opening frame land, then hand the camera to
        // follow mode for the rest of the phase.
        _followedPhase = null;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _followedPhase = state.phase);
        });
        // Back to idle (change destination / cancel / done): the camera was
        // fitted to the route bounds — bring it back to the rider instead of
        // leaving it zoomed out over the whole route.
        if (state.phase == TripPhase.idle) {
          _recenterToMe();
          // Ended from the server side (driver cancelled): the idle sheet
          // has nowhere to show it, so tell the rider explicitly.
          if (state.error != null) _showTripEndedDialog(context, state.error!);
        }
        // Tactile punctuation on the moments that matter in the ride flow.
        switch (state.phase) {
          case TripPhase.driverEnRoute:
            AppHaptics.success(); // a driver accepted — you're matched
          case TripPhase.driverArrived:
            AppHaptics.medium(); // your driver is here
          case TripPhase.completed:
            AppHaptics.success(); // trip done
          case TripPhase.error:
            AppHaptics.heavy();
          case _:
            break;
        }
      },
      builder: (context, state) {
        final layer = _mapLayer(state);
        // The sheet resizes as the ride moves through its phases; re-measure
        // every build so the map's inset follows it.
        _measureSheet();
        return Scaffold(
          body: Stack(
            children: [
              // Google Maps SDK via the shared AppMap (native on mobile, JS
              // on web) — the basemap is styled per theme inside AppMap.
              AppMap(
                initialCenter: MapUtils.toLatLng(_myLocation),
                initialZoom: 16, // street level on the rider, like Uber
                markers: layer.markers,
                route: layer.route,
                fitBounds: layer.cameraFitBounds,
                recenter: _recenter,
                recenterSeq: _recenterSeq,
                // A recenter also restores street-level zoom, so the button
                // works the same after a pinch, after a route fit and after
                // the app has been in the background.
                recenterZoom: RideCamera.recenterZoom,
                cameraMode: _isLiveTracking(state)
                    ? MapCameraMode.followDriverEdge
                    : MapCameraMode.fit,
                // The map tells us when it stops following (the rider
                // panned); that is what raises the Recenter pill.
                onFollowingChanged: (following) {
                  if (following != _following) {
                    setState(() => _following = following);
                  }
                },
                // Keep pickup/dropoff/driver markers framed above the bottom
                // sheet (which covers ~40% of the screen) rather than behind it.
                // Inset the map by what is actually covering it. Markers stay
                // framed in the visible strip, and Google's attribution sits
                // just above the sheet instead of floating mid-map. Falls back
                // to a proportion of the screen for the first frame, before the
                // sheet has been measured.
                boundsPadding: EdgeInsets.fromLTRB(
                  40,
                  96,
                  40,
                  (_sheetHeight > 0
                          ? _sheetHeight
                          : MediaQuery.sizeOf(context).height * 0.34) +
                      AppSpacing.sm,
                ),
              ),
              // Banner and top controls share one column so the
              // "Reconnecting…" bar pushes the buttons down instead of being
              // drawn underneath them. The banner pads for the status bar
              // itself, so the controls only take the inset while it's hidden.
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ConnectionBanner(connected: state.connected),
                    LocationBanner(
                      issue: _locationIssue,
                      reducedAccuracy: _reducedAccuracy,
                      onAction: _onLocationBannerAction,
                    ),
                    SafeArea(
                      top:
                          state.connected &&
                          _locationIssue == null &&
                          !_reducedAccuracy,
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        child: Align(
                          alignment: Alignment.topRight,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              AppCircleButton(
                                icon: PhosphorIconsRegular.list,
                                tooltip: 'Account menu',
                                onPressed: () async {
                                  await Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => const AccountMenuPage(
                                        isDriver: false,
                                      ),
                                    ),
                                  );
                                  // Saved places may have changed in the
                                  // account pages; refresh the quick-picks.
                                  _loadSavedPlaces();
                                },
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              // One control, two meanings — and it says
                              // which. During a ride it centres the CAR; at
                              // rest it centres the rider. A button labelled
                              // "my location" that quietly does neither is
                              // how riders learned not to trust it.
                              AppCircleButton(
                                icon: _isLiveTracking(state)
                                    ? PhosphorIconsRegular.gpsFix
                                    : PhosphorIconsRegular.gpsFix,
                                tooltip: _isLiveTracking(state)
                                    ? 'Recenter on your driver'
                                    : 'Recenter on my location',
                                onPressed: _recenterToMe,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Raised only while the camera is NOT following — the
                    // rider panned, so the car may now be off screen. It
                    // takes them back to the live position and resumes
                    // automatic tracking.
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: RecenterPill(
                        visible: _isLiveTracking(state) && !_following,
                        onPressed: _recenterToMe,
                      ),
                    ),
                    // Flexible: the sheet caps itself at the screen height,
                    // but the pill above takes room too — without this the
                    // pair overflowed by 14 px whenever the sheet reached its
                    // cap (seen mid-transition while booking).
                    Flexible(
                      child: RideSheetForPhase(
                        key: _sheetKey,
                        state: state,
                        onSearch: _openSearch,
                        savedPlaces: _savedPlaces,
                        onPickSaved: _pickSaved,
                        // Booking is gated while we have no real fix: a ride
                        // requested from the city-centre fallback would send the
                        // driver to the wrong place.
                        locationIssue: _hasRealLocation ? null : _locationIssue,
                        onFixLocation: () => _onLocationBannerAction(
                          _bannerActionFor(_locationIssue),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
