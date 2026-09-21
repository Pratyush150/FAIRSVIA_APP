import 'dart:async';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_models/shared_models.dart';

import 'features/trip/destination_search_page.dart';
import 'features/trip/location_banner.dart';
import 'features/trip/location_service.dart';
import 'features/trip/map_picker_page.dart';
import 'features/trip/map_utils.dart';
import 'features/trip/price_comparison_card.dart';
import 'features/trip/trip_cubit.dart';

/// Rider home: full-screen map with a bottom sheet that changes with the
/// request phase (where-to → choose ride → finding driver).
/// Share of the screen the ride-options sheet may take, so the route stays
/// visible above it (also drives the map's bottom fit padding).
const double kRideOptionsSheetFraction = 0.58;

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
      setState(() {
        _myLocation = loc;
        _hasRealLocation = true;
        _locationIssue = null;
        if (_myLocationAddr == DestinationSearchPage.unsetPickupLabel) {
          _myLocationAddr = 'Current location';
        }
        if (!_snappedToMe) {
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
      _resumeSocket();
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
  }

  Future<void> _loadLocation() async {
    final result = await _location.resolve();
    if (!mounted) return;
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
      _recenter = MapUtils.toLatLng(result.point);
      _recenterSeq++;
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
      final place = await sl<TripRepository>()
          .reverseGeocode(result.point.lat, result.point.lng);
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
        LocationIssue.denied || LocationIssue.error || null =>
          LocationBannerAction.retry,
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
    // again did nothing because the bounds had not changed.
    if (_isLiveTracking(state)) {
      setState(() {
        _recenter = MapUtils.toLatLng(state.driverLocation!);
        _recenterSeq++;
        _followedPhase = state.phase; // resume following after the snap
      });
      return;
    }
    final bounds = _fitBounds(state);
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

  List<AppMapMarker> _markers(TripState state) {
    final markers = <AppMapMarker>[];
    // Pins sit on the routed road ends (not the raw geocode, which can land
    // in water or inside a block) whenever a route is known.
    final tripRoute = MapUtils.decodePolyline(
      state.estimate?.polyline ?? state.trip?.routePolyline ?? '',
    );
    if (state.pickup != null) {
      markers.add(AppMapMarker(
        point: tripRoute.length >= 2
            ? tripRoute.first
            : MapUtils.toLatLng(state.pickup!),
        kind: MapMarkerKind.pickup,
        label: 'Pickup',
      ));
    }
    if (state.dropoff != null) {
      markers.add(AppMapMarker(
        point: tripRoute.length >= 2
            ? tripRoute.last
            : MapUtils.toLatLng(state.dropoff!),
        kind: MapMarkerKind.dropoff,
        label: 'Destination',
      ));
    }
    if (state.driverLocation != null) {
      markers.add(AppMapMarker(
        point: MapUtils.toLatLng(state.driverLocation!),
        kind: MapMarkerKind.driver,
        label: 'Driver',
        // Last reported compass heading, so the car keeps pointing the way
        // it was going even while pings pause (AppMap otherwise derives it
        // from movement and a stale/parked car would spin to 0°).
        heading: state.driverHeading,
      ));
    }
    // "You are here": before a driver is assigned the rider's own position is
    // the anchor of the map (Uber's blue dot). Once on the way it would only
    // clutter the pickup pin, so it is dropped for the live-tracking phases.
    if (state.phase.index <= TripPhase.searching.index ||
        state.phase == TripPhase.error) {
      markers.add(AppMapMarker(
        point: MapUtils.toLatLng(_myLocation),
        kind: MapMarkerKind.me,
      ));
    }
    return markers;
  }

  /// The active leg for re-routing: 'approach' (driver→pickup) while the driver
  /// is on the way, 'trip' (→destination) once moving, else null (no live line).
  String? _legKey(TripState state) {
    if (state.phase == TripPhase.driverEnRoute ||
        state.phase == TripPhase.driverArrived) {
      return 'approach';
    }
    if (state.phase == TripPhase.onTrip) return 'trip';
    return null;
  }

  /// The planned (or freshly re-routed) line for the current leg, untrimmed.
  List<LatLng> _plannedRoute(TripState state) {
    final leg = _legKey(state);
    // Prefer a freshly re-routed line for the current leg — the road the driver
    // actually took — over the route planned at booking/accept. The server's
    // own recompute wins: it is also what its live ETA is measured against, so
    // taking it keeps the drawn line and the "N min" agreeing, and spares us a
    // duplicate routing call.
    if (leg != null && state.liveRouteLeg == leg) {
      final pushed = state.liveRoutePolyline;
      if (pushed != null && pushed.isNotEmpty) {
        final live = MapUtils.decodePolyline(pushed);
        if (live.length >= 2) return live;
      }
    }
    if (leg != null && _liveRoutePolyline != null && _liveRouteLeg == leg) {
      final live = MapUtils.decodePolyline(_liveRoutePolyline!);
      if (live.length >= 2) return live;
    }
    // While the driver is on the way, draw THEIR route to the pickup (the
    // approach leg) so the line matches where the car is actually going; once
    // the trip starts, fall back to the pickup→destination trip route.
    final approaching = leg == 'approach';
    final approachRoute = state.driverRoutePolyline;
    // After a cold-start restore there is no estimate; the trip carries its own
    // route polyline, so fall back to that rather than drawing nothing.
    final encoded = (approaching &&
            approachRoute != null &&
            approachRoute.isNotEmpty)
        ? approachRoute
        : (state.estimate?.polyline ?? state.trip?.routePolyline);
    if (encoded == null || encoded.isEmpty) return const [];
    return MapUtils.decodePolyline(encoded);
  }

  /// If the driver has left the drawn route, re-fetch the optimal road route
  /// from the car's live position to its current target (pickup, then dropoff).
  /// Throttled by [_rerouteGate]; best-effort (a failure keeps the current line).
  Future<void> _maybeReroute(TripState state) async {
    final driver = state.driverLocation;
    final leg = _legKey(state);
    if (driver == null || leg == null) return;
    final target = leg == 'approach' ? state.pickup : state.dropoff;
    if (target == null) return;

    final route = _plannedRoute(state);
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

  List<LatLng> _route(TripState state) {
    final approaching = _legKey(state) == 'approach';
    final route = _plannedRoute(state);
    if (route.isEmpty) return route;
    // Trim the line behind the car so it "eats" the route as it drives; once
    // the driver has arrived the approach line has nothing left to show.
    if (state.phase == TripPhase.driverArrived && approaching) return const [];
    final car = state.driverLocation;
    if (car != null &&
        (state.phase == TripPhase.driverEnRoute ||
            state.phase == TripPhase.onTrip)) {
      return routeRemainingPath(route, MapUtils.toLatLng(car));
    }
    return route;
  }

  /// Below this car↔pickup span the two points are effectively on top of
  /// each other and a bounds fit would zoom the map to its maximum; frame a
  /// fixed [kArrivalBoxHalfSpanM]-radius box around the pickup instead.
  static const double kMinFitSpanM = 60;
  static const double kArrivalBoxHalfSpanM = 125; // ~250 m box

  /// What the camera frames. During the approach we fit the driver→pickup leg
  /// (using the approach polyline's endpoints, which stay fixed for the whole
  /// approach — so the camera frames the leg once instead of chasing the car
  /// on every GPS tick). Once the driver has arrived we frame the car and the
  /// pickup, or a fixed ~250 m box around the pickup when they're (nearly) the
  /// same point. Otherwise we fit pickup→dropoff.
  /// Phases where a driver is on the map and the rider is watching them move.
  /// The camera follows the car in these, instead of holding a static frame
  /// that the driver eventually drives out of.
  static bool _isLiveTracking(TripState state) =>
      state.driverLocation != null &&
      (state.phase == TripPhase.driverEnRoute ||
          state.phase == TripPhase.driverArrived ||
          state.phase == TripPhase.onTrip);

  /// The camera frames the ride once when a phase begins, then hands over to
  /// follow mode. Re-fitting on every driver ping would re-zoom the map a
  /// second at a time; not fitting at all would leave the rider looking at the
  /// wrong part of the city when the phase changes.
  List<LatLng>? _fitBoundsForCamera(TripState state) {
    if (_fitSuppressed) return null;
    if (_isLiveTracking(state) && _followedPhase == state.phase) return null;
    return _fitBounds(state);
  }

  List<LatLng>? _fitBounds(TripState state) {
    // Prefer the estimate's endpoints; after a cold-start restore there is no
    // estimate, so frame the restored trip's pickup/dropoff instead.
    final pickup = state.estimate?.pickup ?? state.pickup;
    final dropoff = state.estimate?.dropoff ?? state.dropoff;
    if (pickup == null || dropoff == null) return null;
    final pickupLL = MapUtils.toLatLng(pickup);
    final approaching = state.phase == TripPhase.driverEnRoute ||
        state.phase == TripPhase.driverArrived;
    List<LatLng> bounds;
    final approachRoute = state.driverRoutePolyline;
    final approachPts = (approaching && approachRoute != null)
        ? MapUtils.decodePolyline(approachRoute)
        : const <LatLng>[];
    if (state.phase == TripPhase.driverArrived) {
      final car = state.driverLocation != null
          ? MapUtils.toLatLng(state.driverLocation!)
          : (approachPts.isNotEmpty ? approachPts.first : pickupLL);
      bounds = [car, pickupLL];
    } else if (approaching && approachPts.length >= 2) {
      bounds = [approachPts.first, approachPts.last];
    } else {
      bounds = [pickupLL, MapUtils.toLatLng(dropoff)];
    }
    if (MapUtils.spanMeters(bounds) < kMinFitSpanM) {
      bounds = MapUtils.boxAround(pickupLL, kArrivalBoxHalfSpanM);
    }
    return bounds;
  }

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
            prev.driverLocation != curr.driverLocation ||
            (curr.phase == TripPhase.idle && prev.error != curr.error),
        listener: (context, state) {
          final cubit = context.read<TripCubit>();
          // One-shot server notices (payment warnings) as a snackbar.
          final notice = state.notice;
          if (notice != null) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(notice)));
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
          final leg = _legKey(state);
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
          return Scaffold(
            body: Stack(
              children: [
                // Google Maps SDK via the shared AppMap (native on mobile, JS
                // on web) — the basemap is styled per theme inside AppMap.
                AppMap(
                  initialCenter: MapUtils.toLatLng(_myLocation),
                  initialZoom: 16, // street level on the rider, like Uber
                  markers: _markers(state),
                  route: _route(state),
                  fitBounds: _fitBoundsForCamera(state),
                  recenter: _recenter,
                  recenterSeq: _recenterSeq,
                  cameraMode: _isLiveTracking(state)
                      ? MapCameraMode.followDriverEdge
                      : MapCameraMode.fit,
                  // Keep pickup/dropoff/driver markers framed above the bottom
                  // sheet (which covers ~40% of the screen) rather than behind it.
                  boundsPadding: EdgeInsets.fromLTRB(
                    40,
                    96,
                    40,
                    // Match the sheet actually on screen in this phase so the
                    // fitted route lands in the visible strip of map.
                    state.phase == TripPhase.choosingRide
                        ? MediaQuery.sizeOf(context).height *
                                kRideOptionsSheetFraction +
                            24
                        : 300,
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
                        top: state.connected &&
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
                                  icon: Icons.menu_rounded,
                                  tooltip: 'Account menu',
                                  onPressed: () async {
                                    await Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => const AccountMenuPage(
                                            isDriver: false),
                                      ),
                                    );
                                    // Saved places may have changed in the
                                    // account pages; refresh the quick-picks.
                                    _loadSavedPlaces();
                                  },
                                ),
                                const SizedBox(height: AppSpacing.sm),
                                AppCircleButton(
                                  icon: Icons.my_location_rounded,
                                  tooltip: 'Recenter on my location',
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
                  child: _BottomSheetForPhase(
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
          );
        },
    );
  }
}

class _BottomSheetForPhase extends StatelessWidget {
  const _BottomSheetForPhase({
    required this.state,
    required this.onSearch,
    this.savedPlaces = const [],
    required this.onPickSaved,
    this.locationIssue,
    this.onFixLocation,
  });

  final TripState state;
  final VoidCallback onSearch;
  final List<SavedPlace> savedPlaces;
  final ValueChanged<SavedPlace> onPickSaved;

  /// Non-null when no real position is known: the idle sheet then shows a
  /// blocking "Location required" gate instead of the destination search.
  final LocationIssue? locationIssue;
  final VoidCallback? onFixLocation;

  @override
  Widget build(BuildContext context) {
    final child = switch (state.phase) {
      TripPhase.idle => _WhereToCard(
          onTap: onSearch,
          locationIssue: locationIssue,
          onFixLocation: onFixLocation,
          savedPlaces: savedPlaces,
          onPickSaved: onPickSaved,
        ),
      TripPhase.loadingEstimate =>
        const _InfoCard(child: _Busy(label: 'Finding the best route…')),
      TripPhase.choosingRide => _RideOptions(state: state),
      TripPhase.requesting =>
        const _InfoCard(child: _Busy(label: 'Requesting your ride…')),
      TripPhase.scheduled => _ScheduledConfirmation(state: state),
      TripPhase.searching => _FindingDriver(state: state),
      TripPhase.driverEnRoute => DriverInfoSheet(state: state, arrived: false),
      TripPhase.driverArrived => DriverInfoSheet(state: state, arrived: true),
      TripPhase.onTrip => _OnTripSheet(state: state),
      TripPhase.completed => CompletedSheet(state: state),
      TripPhase.error => _ErrorCard(
          message: state.error ?? 'Something went wrong',
          onRetry: onSearch,
        ),
    };
    // Cross-fade + slide between phases, and smoothly resize the sheet as each
    // phase's content changes height — so the flow feels like one continuous
    // surface rather than a stack of hard-swapped cards.
    return AppSheet(
      // Keep the routed map visible while choosing a ride: the options sheet
      // is otherwise tall enough to hide the route and both markers.
      maxHeightFraction:
          state.phase == TripPhase.choosingRide ? kRideOptionsSheetFraction : null,
      footer: state.phase == TripPhase.choosingRide && state.estimate != null
          ? _RideConfirmFooter(state: state)
          : null,
      child: AnimatedSize(
        duration: AppMotion.normal,
        curve: AppMotion.standard,
        alignment: Alignment.bottomCenter,
        child: AnimatedSwitcher(
          duration: AppMotion.normal,
          switchInCurve: AppMotion.emphasized,
          switchOutCurve: AppMotion.exit,
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: SlideTransition(
              position: Tween(
                begin: const Offset(0, 0.06),
                end: Offset.zero,
              ).animate(anim),
              child: child,
            ),
          ),
          layoutBuilder: (currentChild, previousChildren) => Stack(
            alignment: Alignment.bottomCenter,
            children: [
              ...previousChildren,
              ?currentChild,
            ],
          ),
          child: KeyedSubtree(key: ValueKey(state.phase), child: child),
        ),
      ),
    );
  }
}

class _WhereToCard extends StatelessWidget {
  const _WhereToCard({
    required this.onTap,
    this.savedPlaces = const [],
    required this.onPickSaved,
    this.locationIssue,
    this.onFixLocation,
  });

  final VoidCallback onTap;
  final List<SavedPlace> savedPlaces;
  final ValueChanged<SavedPlace> onPickSaved;
  final LocationIssue? locationIssue;
  final VoidCallback? onFixLocation;

  IconData _iconFor(String label) {
    final l = label.toLowerCase();
    if (l == 'home') return Icons.home_outlined;
    if (l == 'work') return Icons.work_outline;
    return Icons.place_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final issue = locationIssue;
    if (issue != null) {
      return _LocationRequiredGate(issue: issue, onFix: onFixLocation);
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Where to?', style: theme.textTheme.headlineMedium),
        const SizedBox(height: AppSpacing.lg),
        // Search pill.
        Material(
          color: Colors.transparent,
          child: Ink(
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.surfaceMutedDark
                  : AppColors.surfaceMutedLight,
              borderRadius: BorderRadius.circular(AppSpacing.radius),
              border: Border.all(
                color: isDark ? AppColors.borderDark : AppColors.borderLight,
              ),
            ),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(AppSpacing.radius),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.lg,
                ),
                child: Row(
                  children: [
                    const Icon(Icons.search_rounded,
                        color: AppColors.accent, size: 22),
                    const SizedBox(width: AppSpacing.md),
                    Text('Enter your destination',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onSurface,
                        )),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (savedPlaces.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          for (final place in savedPlaces) ...[
            _QuickDestination(
              icon: _iconFor(place.label),
              label: place.label,
              subtitle: place.address,
              onTap: () => onPickSaved(place),
            ),
            if (place != savedPlaces.last)
              Divider(height: 1, color: theme.dividerColor),
          ],
        ],
      ],
    );
  }
}

/// Booking gate shown in place of the destination search when no real
/// position is known. Without a real fix the pickup would be the city-centre
/// fallback, which sends the driver to the wrong place — so booking is
/// blocked outright rather than allowed to go wrong quietly.
class _LocationRequiredGate extends StatelessWidget {
  const _LocationRequiredGate({required this.issue, this.onFix});

  final LocationIssue issue;
  final VoidCallback? onFix;

  String get _message => switch (issue) {
        LocationIssue.servicesOff =>
          'Location Services are off, so we can\'t tell where to pick you '
              'up. Turn them on to book a ride.',
        LocationIssue.denied =>
          'We need your location to set your pickup point and send a driver '
              'to the right place.',
        LocationIssue.deniedForever =>
          'Location access is turned off for this app. Enable it in Settings '
              'to book a ride.',
        LocationIssue.error =>
          "We couldn't read your location. Try again to book a ride.",
      };

  String get _action => switch (issue) {
        LocationIssue.servicesOff => 'Turn on Location Services',
        LocationIssue.denied => 'Allow location',
        LocationIssue.deniedForever => 'Open Settings',
        LocationIssue.error => 'Try again',
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.location_off_rounded,
                color: AppColors.warning, size: 24),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text('Location required',
                  style: theme.textTheme.headlineMedium),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(_message, style: theme.textTheme.bodyMedium),
        const SizedBox(height: AppSpacing.lg),
        PrimaryButton(label: _action, onPressed: onFix),
      ],
    );
  }
}

/// A saved-place row (Home / Work / …) shown under the search pill.
class _QuickDestination extends StatelessWidget {
  const _QuickDestination({
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isDark
                    ? AppColors.surfaceMutedDark
                    : AppColors.surfaceMutedLight,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 20, color: theme.colorScheme.onSurface),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: theme.textTheme.titleSmall),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: theme.colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

class _RideOptions extends StatelessWidget {
  const _RideOptions({required this.state});
  final TripState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final estimate = state.estimate!;
    final cubit = context.read<TripCubit>();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('Choose a ride', style: theme.textTheme.headlineSmall),
            const Spacer(),
            Text(
              '${estimate.distanceMi.toStringAsFixed(1)} mi · '
              '${_minutes(estimate.durationS)} min',
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
        if (estimate.surge > 1.0)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Text(
              'Fares are higher due to demand (${estimate.surge.toStringAsFixed(1)}x)',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: AppColors.warning),
            ),
          ),
        // Surfaced when a request comes back with no drivers (or a create error);
        // the ride is kept so the rider can just re-tap Confirm.
        if (state.error != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded,
                    size: 16, color: AppColors.warning),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(state.error!,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: AppColors.warning)),
                ),
              ],
            ),
          ),
        const SizedBox(height: AppSpacing.sm),
        _StopsSection(state: state),
        const SizedBox(height: AppSpacing.sm),
        // The sheet body is the only scroll view: an inner scrollable here
        // swallowed swipes and hid the payment/schedule/promo rows behind a
        // nested-scroll trap.
        ListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              for (final (i, tier) in estimate.tiers.indexed)
                _RideTierTile(
                  tier: tier,
                  selected: tier.tier == state.selectedTier,
                  onTap: () {
                    AppHaptics.selection();
                    cubit.selectTier(tier.tier);
                  },
                ).animate().fadeIn(
                      delay: AppMotion.stagger * i,
                      duration: AppMotion.normal,
                    ).moveY(
                      begin: 8,
                      end: 0,
                      delay: AppMotion.stagger * i,
                      duration: AppMotion.normal,
                      curve: AppMotion.emphasized,
                    ),
            ],
          ),
        if (estimate.comparison != null) ...[
          const SizedBox(height: AppSpacing.sm),
          PriceComparisonCard(comparison: estimate.comparison!),
        ],
        const SizedBox(height: AppSpacing.sm),
        _PaymentModeToggle(state: state),
        const SizedBox(height: AppSpacing.sm),
        _ScheduleRow(state: state),
        const SizedBox(height: AppSpacing.sm),
        _PromoField(state: state),
        const SizedBox(height: AppSpacing.sm),
        _PickupNoteField(state: state),
        const SizedBox(height: AppSpacing.sm),
        _BookForSomeoneElseRow(state: state),
      ],
    );
  }
}

/// "Riding yourself, or booking for someone else?" The booker still pays and
/// still tracks the ride; the passenger is who the driver collects, and who
/// gets the start code by text — they may not have the app at all.
class _BookForSomeoneElseRow extends StatelessWidget {
  const _BookForSomeoneElseRow({required this.state});
  final TripState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cubit = context.read<TripCubit>();
    final passenger = state.passenger;

    if (passenger == null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          icon: const Icon(Icons.person_add_alt_outlined, size: 18),
          label: const Text('Book for someone else'),
          onPressed: () async {
            final result = await _askPassenger(context, null);
            if (result != null) cubit.setPassenger(result);
          },
        ),
      );
    }

    return Row(
      children: [
        const Icon(Icons.person_pin_circle_outlined,
            size: 18, color: AppColors.accent),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Ride for ${passenger.displayName}',
                  style: theme.textTheme.bodyMedium),
              Text('They get the start code by text',
                  style: theme.textTheme.bodySmall),
            ],
          ),
        ),
        TextButton(
          onPressed: () async {
            final result = await _askPassenger(context, passenger);
            if (result != null) cubit.setPassenger(result);
          },
          child: const Text('Edit'),
        ),
        IconButton(
          tooltip: 'Ride it myself',
          icon: const Icon(Icons.close, size: 18),
          onPressed: () => cubit.setPassenger(null),
        ),
      ],
    );
  }
}

/// Collect the passenger's name and number. A number is required — the driver
/// calls it and the start code is texted to it — so the dialog refuses to
/// return without one. Returns null if the rider backs out.
Future<TripPassenger?> _askPassenger(
  BuildContext context,
  TripPassenger? existing,
) {
  final nameCtrl = TextEditingController(text: existing?.name ?? '');
  final phoneCtrl = TextEditingController(text: existing?.phone ?? '');
  return showDialog<TripPassenger>(
    context: context,
    builder: (dialogCtx) {
      String? error;
      return StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Who is riding?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Their name (optional)',
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: 'Their mobile number',
                  hintText: '+1 305 555 0123',
                  errorText: error,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'We text them the start code and let you know when the '
                'driver arrives. You still pay and can track the ride.',
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final phone = phoneCtrl.text.trim();
                if (phone.replaceAll(RegExp(r'[^0-9]'), '').length < 6) {
                  setLocal(() => error = 'Enter their mobile number');
                  return;
                }
                final name = nameCtrl.text.trim();
                Navigator.pop(
                  dialogCtx,
                  TripPassenger(
                    phone: phone,
                    name: name.isEmpty ? null : name,
                  ),
                );
              },
              child: const Text('Done'),
            ),
          ],
        ),
      );
    },
  );
}

/// Pinned footer for the ride-options sheet: the confirm CTA and the
/// "change destination" escape hatch stay visible even when the options
/// above (surge line, stops, comparison card, promo) overflow and scroll.
class _RideConfirmFooter extends StatelessWidget {
  const _RideConfirmFooter({required this.state});
  final TripState state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<TripCubit>();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PrimaryButton(
          label: _confirmLabel(state),
          onPressed:
              state.selectedTier != null ? () => cubit.confirmRide() : null,
        ),
        TextButton(
          onPressed: () => cubit.reset(),
          child: const Text('Change destination'),
        ),
      ],
    );
  }
}

/// Multi-stop editor: lists current stops with remove buttons and an "Add stop"
/// action (opens the destination search) up to the backend cap.
class _StopsSection extends StatelessWidget {
  const _StopsSection({required this.state});
  final TripState state;

  Future<void> _addStop(BuildContext context) async {
    final cubit = context.read<TripCubit>();
    final details = await Navigator.of(context).push<PlaceDetails>(
      MaterialPageRoute(
        builder: (_) => DestinationSearchPage(
          singleDestination: true,
          // Only used to bias/sort the suggestions in this mode.
          initialPickup: state.pickup,
        ),
      ),
    );
    if (details != null) {
      await cubit.addStop(
        TripStop(point: details.location, address: details.address),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cubit = context.read<TripCubit>();
    final canAdd = state.stops.length < TripCubit.maxStops;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < state.stops.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Row(
              children: [
                const Icon(Icons.trip_origin, size: 16),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    state.stops[i].address ?? 'Stop ${i + 1}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                InkWell(
                  onTap: () => cubit.removeStop(i),
                  child: const Icon(Icons.close, size: 16),
                ),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: canAdd ? () => _addStop(context) : null,
            icon: const Icon(Icons.add_location_alt_outlined, size: 18),
            label: Text(canAdd ? 'Add stop' : 'Max 3 stops'),
          ),
        ),
      ],
    );
  }
}

String _confirmLabel(TripState state) {
  final fare = state.selectedFare;
  if (fare == null) return 'Confirm';
  final net = state.discountedFare ?? fare.fare;
  final amount = (state.appliedPromo != null && net != fare.fare)
      ? net
      : fare.fare;
  final verb = state.scheduledAt != null ? 'Schedule' : 'Confirm';
  return '$verb ${fare.label} · \$${_money(amount)}';
}

String _formatSchedule(DateTime when) {
  final local = when.toLocal();
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final h = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final ampm = local.hour < 12 ? 'AM' : 'PM';
  final min = local.minute.toString().padLeft(2, '0');
  return '${months[local.month - 1]} ${local.day}, $h:$min $ampm';
}

/// The native wheel picker on Apple platforms (the Material calendar + clock
/// dial looked out of place on iOS). Returns null when dismissed.
Future<DateTime?> _pickCupertino(BuildContext context) async {
  final now = DateTime.now();
  // Backend rule: at least 5 min ahead; keep a minute of slack (see the
  // Material path). Start on the next 5-minute mark an hour from now.
  final floor = now.add(const Duration(minutes: 6));
  var initial = now.add(const Duration(hours: 1));
  initial = initial.subtract(Duration(
    minutes: initial.minute % 5,
    seconds: initial.second,
    milliseconds: initial.millisecond,
    microseconds: initial.microsecond,
  ));
  var picked = initial;
  final theme = Theme.of(context);
  final ok = await showCupertinoModalPopup<bool>(
    context: context,
    builder: (ctx) => Container(
      height: 340,
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      color: theme.colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            Row(
              children: [
                CupertinoButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Cancel'),
                ),
                const Spacer(),
                Text('Schedule for', style: theme.textTheme.titleMedium),
                const Spacer(),
                CupertinoButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('Done'),
                ),
              ],
            ),
            Expanded(
              child: CupertinoDatePicker(
                mode: CupertinoDatePickerMode.dateAndTime,
                initialDateTime: initial,
                minimumDate: floor,
                maximumDate: now.add(const Duration(days: 30)),
                minuteInterval: 5,
                onDateTimeChanged: (d) => picked = d,
              ),
            ),
          ],
        ),
      ),
    ),
  );
  if (ok != true) return null;
  return picked.isBefore(floor) ? floor : picked;
}

/// "Ride now" vs "Schedule for …" row with a date/time picker.
class _ScheduleRow extends StatelessWidget {
  const _ScheduleRow({required this.state});
  final TripState state;

  Future<void> _pick(BuildContext context) async {
    final cubit = context.read<TripCubit>();
    final platform = Theme.of(context).platform;
    if (platform == TargetPlatform.iOS || platform == TargetPlatform.macOS) {
      final when = await _pickCupertino(context);
      if (when != null) cubit.setScheduledAt(when);
      return;
    }
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      firstDate: now,
      lastDate: now.add(const Duration(days: 30)),
      initialDate: now.add(const Duration(hours: 1)),
    );
    if (date == null || !context.mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))),
    );
    if (time == null) return;
    final when = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    // Must be at least 5 minutes ahead (backend rule). Clamp with a minute of
    // slack: clamping to exactly now+5 and sending a few seconds later was
    // rejected by the backend with a 400.
    if (when.isBefore(now.add(const Duration(minutes: 6)))) {
      cubit.setScheduledAt(now.add(const Duration(minutes: 6)));
    } else {
      cubit.setScheduledAt(when);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cubit = context.read<TripCubit>();
    final when = state.scheduledAt;
    return InkWell(
      onTap: () => _pick(context),
      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          border: Border.all(color: theme.dividerColor),
        ),
        child: Row(
          children: [
            const Icon(Icons.schedule, size: 18),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                when == null ? 'Ride now' : 'For ${_formatSchedule(when)}',
                style: theme.textTheme.bodyMedium,
              ),
            ),
            if (when != null)
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                tooltip: 'Ride now instead',
                onPressed: () => cubit.setScheduledAt(null),
              )
            else
              Text('Schedule',
                  style: theme.textTheme.labelLarge
                      ?.copyWith(color: AppColors.accent)),
          ],
        ),
      ),
    );
  }
}

/// Shown after a future ride is booked.
class _ScheduledConfirmation extends StatelessWidget {
  const _ScheduledConfirmation({required this.state});
  final TripState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cubit = context.read<TripCubit>();
    final when = state.trip?.scheduledAt ?? state.scheduledAt;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.event_available, color: AppColors.accent, size: 48),
        const SizedBox(height: AppSpacing.sm),
        Center(
          child: Text('Ride scheduled', style: theme.textTheme.headlineSmall),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (when != null)
          Center(
            child: Text(
              'We’ll find you a driver around\n${_formatSchedule(when)}',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        const SizedBox(height: AppSpacing.lg),
        PrimaryButton(label: 'Done', onPressed: () => cubit.reset()),
      ],
    );
  }
}

/// Card / Cash selector for the ride-options sheet.
class _PaymentModeToggle extends StatelessWidget {
  const _PaymentModeToggle({required this.state});
  final TripState state;

  /// The saved card currently in effect: the explicitly chosen one, else the
  /// default, else the first. Null when there are no saved cards.
  Map<String, dynamic>? get _activeCard {
    final cards = state.paymentMethods;
    if (cards.isEmpty) return null;
    final id = state.selectedMethodId;
    if (id != null) {
      for (final c in cards) {
        if (c['id'] == id) return c;
      }
    }
    for (final c in cards) {
      if (c['isDefault'] == true) return c;
    }
    return cards.first;
  }

  static String _cardLabel(Map<String, dynamic> c) {
    final brand = (c['brand'] as String?)?.trim();
    final last4 = (c['last4'] as String?)?.trim();
    final b = (brand == null || brand.isEmpty) ? 'Card' : cardBrandName(brand);
    // Short form ("Mastercard ••5555") so long brands fit the half-width chip.
    return last4 == null || last4.isEmpty ? b : '$b ••$last4';
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<TripCubit>();
    final card = _activeCard;
    final cardSelected = state.paymentMode == 'card';
    final cardLabel = card == null ? 'Add card' : _cardLabel(card);
    // With >1 saved card, tapping Card opens a picker; otherwise it just
    // selects card mode (backend uses the default / mock method).
    final hasChoice = state.paymentMethods.length > 1;
    return Row(
      children: [
        Expanded(
          child: _PayChip(
            icon: Icons.credit_card,
            label: cardLabel,
            selected: cardSelected,
            trailing: hasChoice ? Icons.expand_more : null,
            onTap: () {
              if (card == null) {
                _addCard(context, cubit);
              } else if (hasChoice) {
                _showCardPicker(context, cubit);
              } else {
                cubit.setPaymentMode('card');
              }
            },
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _PayChip(
            icon: Icons.payments_outlined,
            label: 'Cash',
            selected: state.paymentMode == 'cash',
            onTap: () => cubit.setPaymentMode('cash'),
          ),
        ),
      ],
    );
  }

  /// No card on file: take the rider to Payment methods, then select the
  /// card they added (if any) for this ride.
  Future<void> _addCard(BuildContext context, TripCubit cubit) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PaymentMethodsPage(
          payments: sl<PaymentsRemoteDataSource>(),
          stripeCardAdder: sl.isRegistered<StripeCardAdder>()
              ? sl<StripeCardAdder>()
              : null,
        ),
      ),
    );
    await cubit.loadPaymentMethods();
    if (cubit.state.paymentMethods.isNotEmpty) cubit.setPaymentMode('card');
  }

  Future<void> _showCardPicker(BuildContext context, TripCubit cubit) async {
    final cards = state.paymentMethods;
    final activeId = _activeCard?['id'];
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetCtx) {
        final theme = Theme.of(sheetCtx);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.sm),
                child: Text('Pay with',
                    style: theme.textTheme.titleMedium),
              ),
              for (final c in cards)
                ListTile(
                  leading: const Icon(Icons.credit_card),
                  title: Text(_cardLabel(c)),
                  trailing: c['id'] == activeId
                      ? const Icon(Icons.check, color: AppColors.accent)
                      : null,
                  onTap: () {
                    AppHaptics.selection();
                    cubit.selectPaymentCard(c['id'] as String);
                    Navigator.of(sheetCtx).pop();
                  },
                ),
              const SizedBox(height: AppSpacing.sm),
            ],
          ),
        );
      },
    );
  }
}

class _PayChip extends StatelessWidget {
  const _PayChip({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () {
        AppHaptics.selection();
        onTap();
      },
      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      child: AnimatedContainer(
        duration: AppMotion.fast,
        curve: AppMotion.standard,
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: selected
              ? (theme.brightness == Brightness.dark
                  ? AppColors.accentSoftDark
                  : AppColors.accentSoft)
              : null,
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          border: Border.all(
            color: selected ? AppColors.accent : theme.dividerColor,
            width: 2,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: selected ? AppColors.accent : null),
            const SizedBox(width: AppSpacing.sm),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: selected ? AppColors.accent : null,
                ),
              ),
            ),
            if (trailing != null)
              Icon(trailing,
                  size: 18, color: selected ? AppColors.accent : null),
          ],
        ),
      ),
    );
  }
}

/// Promo-code entry for the ride-options sheet. Shows an input + Apply button
/// until a code is accepted, then a green applied-chip with a remove action.
class _PromoField extends StatefulWidget {
  const _PromoField({required this.state});
  final TripState state;

  @override
  State<_PromoField> createState() => _PromoFieldState();
}

class _PromoFieldState extends State<_PromoField> {
  final _controller = TextEditingController();

  @override
  void didUpdateWidget(covariant _PromoField old) {
    super.didUpdateWidget(old);
    // The field sits low in the scrolling sheet; an error or the "applied"
    // chip appearing below the fold went unseen. Bring it into view.
    final changed = old.state.promoError != widget.state.promoError ||
        old.state.appliedPromo != widget.state.appliedPromo;
    if (changed &&
        (widget.state.promoError != null ||
            widget.state.appliedPromo != null)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Scrollable.ensureVisible(
          context,
          alignment: 0.5,
          duration: const Duration(milliseconds: 250),
        );
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cubit = context.read<TripCubit>();
    final promo = widget.state.appliedPromo;

    if (promo != null) {
      return Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          color: AppColors.success.withValues(alpha: 0.12),
        ),
        child: Row(
          children: [
            const Icon(Icons.local_offer, size: 18, color: AppColors.success),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                '${promo.code} applied · −\$${promo.discount.toStringAsFixed(0)}',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: AppColors.success),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              tooltip: 'Remove promo',
              onPressed: cubit.removePromo,
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  hintText: 'Promo code',
                  prefixIcon: Icon(Icons.local_offer_outlined),
                  isDense: true,
                ),
                onSubmitted: (v) => cubit.applyPromo(v),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            TextButton(
              onPressed: widget.state.applyingPromo
                  ? null
                  : () => cubit.applyPromo(_controller.text),
              child: widget.state.applyingPromo
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Apply'),
            ),
          ],
        ),
        if (widget.state.promoError != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              widget.state.promoError!,
              style:
                  theme.textTheme.bodySmall?.copyWith(color: AppColors.error),
            ),
          ),
      ],
    );
  }
}

class _RideTierTile extends StatelessWidget {
  const _RideTierTile({
    required this.tier,
    required this.selected,
    required this.onTap,
  });

  final FareTier tier;
  final bool selected;
  final VoidCallback onTap;

  IconData get _icon {
    switch (tier.tier) {
      case 'comfort':
        return Icons.local_taxi_rounded;
      case 'xl':
        return Icons.airport_shuttle_rounded;
      case 'premium':
        return Icons.auto_awesome_rounded;
      default:
        return Icons.directions_car_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        selected: selected,
        onTap: onTap,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        // Theme-aware selected fill: a light mint in light mode, a dark-green
        // tint in dark mode — otherwise the (light) on-surface text would sit on
        // a light mint fill in dark mode and wash out. Mirrors _PayChip.
        color: selected
            ? (isDark ? AppColors.accentSoftDark : AppColors.accentSoft)
            : null,
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: selected
                    ? AppColors.accent.withValues(alpha: 0.16)
                    : theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              ),
              child: Icon(_icon,
                  size: 26,
                  color: selected
                      ? AppColors.accent
                      : theme.colorScheme.onSurface),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tier.label, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 1),
                  Text(
                    tier.etaSeconds == null
                        ? '${tier.capacity} seats · no cars nearby'
                        : '${tier.capacity} seats · '
                            '${_minutes(tier.etaSeconds!)} min away',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  // Same rule as the confirm footer (Fmt.money): whole dollars
                  // stay whole, otherwise cents — so the list and the CTA agree.
                  '\$${_money(tier.fare)}',
                  style: theme.textTheme.titleLarge?.tabular(),
                ),
                // What that number is made of. Only offered when the backend
                // itemised the estimate — a "Details" button that opens an
                // empty sheet is worse than no button.
                if (tier.breakdown != null)
                  GestureDetector(
                    onTap: () => showFareDetailsSheet(context, tier),
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Details',
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: AppColors.accent)),
                          const Icon(Icons.keyboard_arrow_right_rounded,
                              size: 16, color: AppColors.accent),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The itemised fare behind a tier's "Details" control: exactly the lines the
/// receipt will show after the ride, so the price is never a bare number the
/// rider has to take on trust. The backend guarantees these sum to the fare.
Future<void> showFareDetailsSheet(BuildContext context, FareTier tier) {
  final breakdown = tier.breakdown;
  if (breakdown == null) return Future<void>.value();
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('${tier.label} fare', style: theme.textTheme.titleLarge),
              const SizedBox(height: AppSpacing.md),
              FareBreakdownRows(
                breakdown: breakdown,
                currency: tier.currency,
                showTip: false,
              ),
              Divider(height: AppSpacing.lg, color: theme.dividerColor),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Estimated total', style: theme.textTheme.titleMedium),
                  Text('\$${tier.fare.toStringAsFixed(2)}',
                      style: theme.textTheme.titleMedium?.tabular()),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'The final fare can differ if the route or traffic changes on '
                'the day. Tolls and waiting time are charged separately.',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// "Details" for the ride that is actually happening: what it costs, which car
/// is coming, and where it is going. Before this, the fare was visible only on
/// the tier picker and after arrival — a rider mid-ride had no way to check the
/// number they had agreed to, and the car's plate was only on the pickup sheet.
Future<void> showRideDetailsSheet(BuildContext context, TripState state) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetCtx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
        child: RideDetailsContent(state: state),
      ),
    ),
  );
}

/// Body of the live-ride details sheet (its own widget so it can be tested
/// without driving a whole booking flow).
class RideDetailsContent extends StatelessWidget {
  const RideDetailsContent({super.key, required this.state});

  final TripState state;

  /// Shown in place of an amount when no source has priced the ride yet.
  static const String unknownFare = 'Not priced yet';

  /// "White Toyota Camry", skipping whatever the payload didn't carry.
  static String? vehicleLine(AssignedDriver? driver) {
    if (driver == null) return null;
    final parts = [driver.vehicleColor, driver.vehicleMake, driver.vehicleModel]
        .whereType<String>()
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    return parts.isEmpty ? null : parts.join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trip = state.trip;
    final driver = state.driver;
    final fare = state.displayFare;
    final breakdown = state.fareBreakdown;
    final distanceM = trip?.distanceM ?? state.estimate?.distanceM;
    final surge = state.estimate?.surge ?? 1.0;
    final paymentMode = trip?.paymentMode ?? state.paymentMode;
    final vehicle = vehicleLine(driver);

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Ride details', style: theme.textTheme.titleLarge),
          const SizedBox(height: AppSpacing.lg),

          // --- Fare -------------------------------------------------------
          AppCard(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      state.fareIsFinal ? 'Total fare' : 'Estimated fare',
                      style: theme.textTheme.titleMedium,
                    ),
                    Text(
                      fare == null ? unknownFare : '\$${_money(fare)}',
                      style: theme.textTheme.titleMedium?.tabular(),
                    ),
                  ],
                ),
                if (!state.fareIsFinal) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'The final fare is metered on the distance actually '
                      'driven.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
                if (breakdown != null) ...[
                  Divider(height: AppSpacing.lg, color: theme.dividerColor),
                  FareBreakdownRows(
                    breakdown: breakdown,
                    currency: state.receipt?.currency ?? trip?.currency ?? 'USD',
                    showTip: false,
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ],
            ),
          ),

          // --- Car + driver -----------------------------------------------
          if (driver != null) ...[
            const SizedBox(height: AppSpacing.md),
            AppCard(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.md,
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      AppAvatar(name: driver.name, size: 44),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(driver.name,
                                style: theme.textTheme.titleMedium),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                const Icon(Icons.star_rounded,
                                    size: 15, color: AppColors.star),
                                const SizedBox(width: 3),
                                Text(driver.rating.toStringAsFixed(1),
                                    style: theme.textTheme.labelLarge),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (vehicle != null)
                    _RideDetailRow(
                      icon: Icons.directions_car_rounded,
                      label: 'Vehicle',
                      value: vehicle,
                    ),
                  if (driver.plate case final plate?
                      when plate.trim().isNotEmpty)
                    _RideDetailRow(
                      icon: Icons.confirmation_number_outlined,
                      label: 'Plate',
                      value: plate,
                    ),
                ],
              ),
            ),
          ],

          // --- Route + payment ---------------------------------------------
          const SizedBox(height: AppSpacing.md),
          AppCard(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            child: Column(
              children: [
                _RideDetailRow(
                  icon: Icons.trip_origin,
                  label: 'Pickup',
                  // After a cold start mid-ride the cubit's own addresses may
                  // not be populated; the trip row always has them.
                  value: state.pickupAddr ?? trip?.pickup.address ?? '—',
                ),
                _RideDetailRow(
                  icon: Icons.place_rounded,
                  label: 'Dropoff',
                  value: state.dropoffAddr ?? trip?.dropoff.address ?? '—',
                ),
                if (distanceM != null)
                  _RideDetailRow(
                    icon: Icons.straighten_rounded,
                    label: 'Distance',
                    value: Fmt.distance(distanceM),
                  ),
                if (_tripEtaLine(state) case final eta?)
                  _RideDetailRow(
                    icon: Icons.schedule_rounded,
                    label: 'Arrival',
                    value: eta,
                  ),
                _RideDetailRow(
                  icon: paymentMode == 'cash'
                      ? Icons.payments_outlined
                      : Icons.credit_card_rounded,
                  label: 'Payment',
                  value: paymentMode == 'cash'
                      ? 'Cash to your driver'
                      : (state.receipt?.cardLabel ?? 'Card'),
                ),
                if (surge > 1.0)
                  _RideDetailRow(
                    icon: Icons.trending_up_rounded,
                    label: 'Surge',
                    value: Fmt.surge(surge),
                  ),
                if (trip?.promoCode case final code? when code.isNotEmpty)
                  _RideDetailRow(
                    icon: Icons.local_offer_outlined,
                    label: 'Promo',
                    value: code,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RideDetailRow extends StatelessWidget {
  const _RideDetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.accent),
          const SizedBox(width: AppSpacing.sm),
          Text(label, style: theme.textTheme.bodyMedium),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// The "Details" affordance carried by the live-ride sheets.
class RideDetailsButton extends StatelessWidget {
  const RideDetailsButton({super.key, required this.state});

  final TripState state;

  @override
  Widget build(BuildContext context) {
    return SecondaryButton(
      label: 'Details',
      icon: Icons.receipt_long_rounded,
      onPressed: () => showRideDetailsSheet(context, state),
    );
  }
}

class _FindingDriver extends StatelessWidget {
  const _FindingDriver({required this.state});
  final TripState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            // Animated radar sweeping for a nearby driver — reads as the system
            // actively looking, not a generic spinner.
            const PulseRadar(
              size: 56,
              child: Icon(Icons.local_taxi_rounded,
                  size: 20, color: AppColors.accent),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Finding your driver',
                      style: theme.textTheme.titleLarge),
                  const SizedBox(height: 2),
                  Text(
                    'Trip to ${state.dropoffAddr ?? 'your destination'}',
                    style: theme.textTheme.bodyMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        if (state.error != null) ...[
          const SizedBox(height: AppSpacing.sm),
          _SheetWarning(message: state.error!),
        ],
        const SizedBox(height: AppSpacing.lg),
        SecondaryButton(
          label: 'Cancel ride',
          onPressed: () => _confirmCancel(context, feeWarning: false),
        ),
      ],
    );
  }
}

/// Inline warning line for the live-trip sheets (failed cancel, locked start
/// code) — the ride is still on, so it sits with the ride rather than
/// replacing it.
class _SheetWarning extends StatelessWidget {
  const _SheetWarning({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline_rounded,
            size: 16, color: AppColors.warning),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(message,
              style:
                  theme.textTheme.bodySmall?.copyWith(color: AppColors.warning)),
        ),
      ],
    );
  }
}

/// Confirms a ride cancellation before calling through. When a driver is already
/// on the way ([feeWarning]), warns that a cancellation fee may apply, then — if
/// one was charged — tells the rider the exact amount. Prevents a silent charge.
Future<void> _confirmCancel(BuildContext context, {required bool feeWarning}) async {
  final messenger = ScaffoldMessenger.of(context);
  final cubit = context.read<TripCubit>();
  final reason = await showDialog<String>(
    context: context,
    builder: (_) => CancelRideDialog(cubit: cubit, feeWarning: feeWarning),
  );
  if (reason == null) return;
  final fee = await cubit.cancelTrip(reason: reason);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(
          fee > 0
              ? 'Ride cancelled. A \$${fee.toStringAsFixed(2)} cancellation '
                  'fee was charged.'
              : 'Ride cancelled.',
        ),
      ),
    );
}

/// "$5.00" from the trip's configured cancellation fee, or a generic word
/// when an older backend didn't send one.
String _feeLabel(TripCubit cubit) {
  final fee = cubit.state.trip?.cancellationFee;
  return fee == null ? '' : '\$${fee.toStringAsFixed(2)}';
}

/// The cancellation reasons a rider can pick from (Uber-style), captured for
/// ops/analytics instead of a hardcoded label.
const List<String> cancelReasons = [
  'Driver is taking too long',
  'Wrong pickup location',
  'Booked by mistake',
  'Changed my plans',
  'Other',
];

/// "Cancel this ride?" prompt: pops with the chosen reason, or null to keep
/// the ride. If the trip ends underneath it (driver
/// cancelled, no-drivers timeout, trip completed) it closes itself instead
/// of leaving a stale prompt whose "Cancel ride" would reset a flow that
/// already moved on. The self-close is guarded so it never pops a dialog
/// the user already dismissed (that raced the navigator and crashed the
/// page with `!_debugLocked` when confirming a cancel).
class CancelRideDialog extends StatelessWidget {
  const CancelRideDialog({
    super.key,
    required this.cubit,
    required this.feeWarning,
  });

  final TripCubit cubit;
  final bool feeWarning;

  @override
  Widget build(BuildContext context) {
    return BlocListener<TripCubit, TripState>(
      bloc: cubit,
      listenWhen: (prev, curr) =>
          TripCubit.isCancellable(prev.phase) &&
          !TripCubit.isCancellable(curr.phase),
      listener: (ctx, _) {
        if (!ctx.mounted) return;
        final route = ModalRoute.of(ctx);
        // Already popped (or mid-pop) by a button: nothing to close.
        if (route == null || !route.isCurrent || !route.isActive) return;
        Navigator.of(ctx).pop();
      },
      child: AlertDialog(
        title: const Text('Cancel this ride?'),
        contentPadding: const EdgeInsets.fromLTRB(
            AppSpacing.lg, AppSpacing.md, AppSpacing.lg, 0),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                feeWarning
                    ? 'Your driver is already on the way. Cancelling is free '
                        'for 2 minutes after they accept; after that a '
                        '${_feeLabel(cubit)} cancellation fee applies. '
                        'Let us know why:'
                    : 'Let us know why:',
              ),
              const SizedBox(height: AppSpacing.sm),
              for (final r in cancelReasons)
                ListTile(
                  key: ValueKey('cancel-reason-$r'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(r),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.of(context).pop(r),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Keep ride'),
          ),
        ],
      ),
    );
  }
}

/// Matched / arrived sheet: status + live ETA, driver card, start code and
/// the Message / Call / Cancel actions. Public so it can be widget-tested
/// without the map. [dialer] launches the driver's number (`tel:`);
/// injectable for tests.
class DriverInfoSheet extends StatelessWidget {
  const DriverInfoSheet({
    super.key,
    required this.state,
    required this.arrived,
    this.dialer = dialPhone,
  });
  final TripState state;
  final bool arrived;
  final Future<bool> Function(String phone) dialer;

  static const String waitingForLocation =
      "Waiting for your driver's location…";

  Future<void> _call(BuildContext context, String phone) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await dialer(phone);
    if (!ok) {
      messenger.showSnackBar(
        SnackBar(content: Text("Couldn't open the dialler for $phone")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final driver = state.driver;
    final otp = state.trip?.startOtp;
    final phone = driver?.phone;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppStatusChip(
                    label: arrived ? 'Arrived' : 'On the way',
                    tone: arrived ? StatusTone.success : StatusTone.accent,
                    icon: arrived
                        ? Icons.check_circle_rounded
                        : Icons.directions_car_rounded,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    arrived
                        ? 'Your driver is here'
                        // Live "Arriving in N min" from the backend approach ETA
                        // when known, else a generic status.
                        : (_liveEtaLabel(state) ??
                            driver?.etaLabel ??
                            'Your driver is on the way'),
                    style: theme.textTheme.headlineSmall,
                  ),
                  // No ping for a while: the car on the map (and the ETA)
                  // may be stale — say so instead of pretending it's live.
                  if (state.driverStale) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 1.6),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Text(waitingForLocation,
                            style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            _sosButton(context, state),
          ],
        ),
        if (state.error != null) ...[
          const SizedBox(height: AppSpacing.sm),
          _SheetWarning(message: state.error!),
        ],
        const SizedBox(height: AppSpacing.lg),
        AppCard(
          child: Row(
            children: [
              AppAvatar(name: driver?.name, size: 52),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(driver?.name ?? 'Your driver',
                        style: theme.textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(Icons.star_rounded,
                            size: 15, color: AppColors.star),
                        const SizedBox(width: 3),
                        // No driver payload yet (e.g. restored after a cold
                        // start) — show "—" rather than inventing a 5.0.
                        Text(
                            driver == null
                                ? '—'
                                : driver.rating.toStringAsFixed(1),
                            style: theme.textTheme.labelLarge),
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(driver?.vehicleLabel ?? '',
                      style: theme.textTheme.bodyMedium),
                  if (driver?.plate != null) ...[
                    const SizedBox(height: 2),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm, vertical: 3),
                      decoration: BoxDecoration(
                        color: theme.brightness == Brightness.dark
                            ? AppColors.surfaceMutedDark
                            : AppColors.surfaceMutedLight,
                        borderRadius:
                            BorderRadius.circular(AppSpacing.radiusSm),
                        border: Border.all(
                            color: theme.brightness == Brightness.dark
                                ? AppColors.borderDark
                                : AppColors.borderLight),
                      ),
                      child: Text(driver!.plate!,
                          style: theme.textTheme.titleSmall
                              ?.copyWith(letterSpacing: 1)),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        if (otp != null) ...[
          const SizedBox(height: AppSpacing.md),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg, vertical: AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.accentSoft,
              borderRadius: BorderRadius.circular(AppSpacing.radius),
            ),
            child: Row(
              children: [
                const Icon(Icons.lock_rounded,
                    size: 18, color: AppColors.accent),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text('Share this start code with your driver',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: AppColors.accentPressed)),
                ),
                Text(otp,
                    style: theme.textTheme.headlineSmall?.copyWith(
                        letterSpacing: 6, color: AppColors.accentPressed)),
              ],
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        // The fare and the car, reachable while the rider waits — both used to
        // disappear from the app the moment a driver accepted.
        RideDetailsButton(state: state),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: SecondaryButton(
                label: state.unreadMessages > 0
                      ? 'Message (${state.unreadMessages})'
                      : 'Message',
                icon: Icons.chat_bubble_rounded,
                onPressed: () => _openTripChat(context, state),
              ),
            ),
            // Only when the payload carries a number — a dead Call button is
            // worse than none.
            if (phone != null) ...[
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: SecondaryButton(
                  label: 'Call',
                  icon: Icons.call_rounded,
                  onPressed: () => _call(context, phone),
                ),
              ),
            ],
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: SecondaryButton(
                label: 'Cancel',
                danger: true,
                onPressed: () => _confirmCancel(context, feeWarning: true),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _OnTripSheet extends StatelessWidget {
  const _OnTripSheet({required this.state});
  final TripState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.navigation, color: AppColors.accent),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text('On the way to your destination',
                  style: theme.textTheme.titleMedium),
            ),
            _sosButton(context, state),
            IconButton(
              tooltip: 'Message driver',
              icon: _ChatIcon(unread: state.unreadMessages),
              onPressed: () => _openTripChat(context, state),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(state.dropoffAddr ?? '', style: theme.textTheme.bodyMedium),
        if (_tripEtaLine(state) case final eta?) ...[
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              const Icon(Icons.schedule_rounded,
                  size: 18, color: AppColors.accent),
              const SizedBox(width: AppSpacing.xs),
              Text(eta, style: theme.textTheme.titleSmall),
            ],
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        // Mid-ride, this is the only way to see the fare and the car's details.
        RideDetailsButton(state: state),
      ],
    );
  }
}

/// "Arriving in N min" from the live leg progress (null until the first ping).
String? _liveEtaLabel(TripState state) {
  final s = state.liveEtaSec;
  if (s == null) return null;
  final mins = (s / 60).ceil();
  return mins <= 1 ? 'Arriving in 1 min' : 'Arriving in $mins min';
}

/// On-trip readout: "Arriving 3:42 PM · 12 min · 4.1 mi to go" built from the
/// live progress, or from the routed estimate before the first ping.
String? _tripEtaLine(TripState state) {
  final secs = state.liveEtaSec ?? state.estimate?.durationS;
  final metres =
      state.liveRemainingM ?? state.estimate?.distanceM;
  if (secs == null) return null;
  final arrival = DateTime.now().add(Duration(seconds: secs));
  final h = arrival.hour % 12 == 0 ? 12 : arrival.hour % 12;
  final clock =
      '$h:${arrival.minute.toString().padLeft(2, '0')} ${arrival.hour < 12 ? 'AM' : 'PM'}';
  final mins = (secs / 60).ceil().clamp(1, 999);
  final miles = metres == null ? null : (metres / 1609.344);
  final dist = miles == null
      ? ''
      : miles < 0.1
          ? ' · ${(metres! * 3.28084).round()} ft to go'
          : ' · ${miles.toStringAsFixed(1)} mi to go';
  return 'Arriving $clock · $mins min$dist';
}

/// Opens the safety toolkit (SOS) for the active trip.
void _openSafety(BuildContext context, TripState state) {
  final tripId = state.trip?.id;
  if (tripId == null) return;
  final share = 'FairsVia trip to ${state.dropoffAddr ?? 'my destination'}. '
      'Driver: ${state.driver?.name ?? 'assigned'}. Please track my ride.';
  showSafetySheet(
    context,
    tripId: tripId,
    safety: sl<SafetyRemoteDataSource>(),
    shareText: share,
  );
}

/// A small red SOS button for the active-trip sheets.
Widget _sosButton(BuildContext context, TripState state) {
  return IconButton(
    tooltip: 'Safety',
    icon: const Icon(Icons.shield_outlined, color: AppColors.error),
    onPressed: () => _openSafety(context, state),
  );
}

/// Opens the in-trip chat with the assigned driver.
void _openTripChat(BuildContext context, TripState state) {
  final cubit = context.read<TripCubit>();
  cubit.setChatOpen(true);
  final tripId = state.trip?.id;
  final userId = context.read<AuthBloc>().state.user?.id;
  if (tripId == null || userId == null) return;
  unawaited(Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ChatPage(
        tripId: tripId,
        currentUserId: userId,
        title: state.driver?.name ?? 'Driver',
        chat: sl<ChatRemoteDataSource>(),
        realtime: sl<RealtimeClient>(),
      ),
    ),
  ).then((_) => cubit.setChatOpen(false)));}

/// A toggle to add/remove the just-completed trip's driver as a favourite.
class _FavoriteDriverButton extends StatefulWidget {
  const _FavoriteDriverButton({required this.driverId, this.driverName});
  final String driverId;
  final String? driverName;

  @override
  State<_FavoriteDriverButton> createState() => _FavoriteDriverButtonState();
}

class _FavoriteDriverButtonState extends State<_FavoriteDriverButton> {
  final _favorites = sl<FavoritesRemoteDataSource>();
  bool _favorited = false;
  bool _busy = false;

  Future<void> _toggle() async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final next = !_favorited;
    try {
      if (next) {
        await _favorites.add(widget.driverId);
      } else {
        await _favorites.remove(widget.driverId);
      }
      if (mounted) setState(() => _favorited = next);
      messenger.showSnackBar(_completionSnackBar(next
          ? 'Added ${widget.driverName ?? 'driver'} to favourites'
          : 'Removed from favourites'));
    } on ApiException catch (e) {
      messenger.showSnackBar(_completionSnackBar(e.message));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: _busy ? null : _toggle,
      icon: Icon(
        _favorited ? Icons.favorite : Icons.favorite_border,
        color: _favorited ? AppColors.error : null,
        size: 18,
      ),
      label: Text(_favorited ? 'Favourited' : 'Add to favourites'),
    );
  }
}

/// Snackbar for the trip-complete sheet: floats above the pinned Done button
/// instead of sliding up over it (a fixed snackbar sits flush with the
/// bottom edge, exactly where the CTA is).
SnackBar _completionSnackBar(String text) => SnackBar(
      content: Text(text),
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        _kCompletionSnackBarLift,
      ),
    );

/// Bottom margin that clears the Done button (button + sheet padding).
const double _kCompletionSnackBarLift = 96;

/// The post-ride sheet: fare, rating, favourite-driver and the tip flow.
/// Public (like [DriverInfoSheet]) so it can be widget-tested on its own.
class CompletedSheet extends StatefulWidget {
  const CompletedSheet({super.key, required this.state});
  final TripState state;

  @override
  State<CompletedSheet> createState() => _CompletedSheetState();
}

class _CompletedSheetState extends State<CompletedSheet> {
  /// The amount the rider has picked but not yet confirmed. A tip can only be
  /// sent once (the backend rejects a second one with 409), so the choice has
  /// to stay changeable on this side of the send rather than firing on the
  /// first tap — which is what made a mis-tap permanent.
  double? _pendingTip;

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final theme = Theme.of(context);
    final cubit = context.read<TripCubit>();
    // Take the first source that actually states a fare. The receipt is the
    // richest, but a capture still settling (or a failed fetch on a weak
    // signal) can leave it at zero, and showing \$0.00 for a ride that just
    // happened reads as a broken app — or a free ride.
    final fare = [
      state.receipt?.fare,
      state.fareFinal,
      state.trip?.fareDisplay,
    ].firstWhere((v) => v != null && v > 0, orElse: () => null) ?? 0;
    final tip = state.tipAmount ?? state.receipt?.tip ?? 0;
    // A tip that has actually been sent — once this exists the choice is final,
    // because the server allows exactly one per trip.
    final double? sentTip = state.tipAmount ?? state.receipt?.tip;
    final double? chosenTip = sentTip ?? _pendingTip;
    final bool locked = sentTip != null || state.tipping;
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: AppColors.accentSoft,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_rounded,
                  color: AppColors.accent, size: 36),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Center(
            child: Text('Trip complete', style: theme.textTheme.headlineSmall),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppCard(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            child: Column(
              children: [
                _ReceiptRow(label: 'Fare', value: fare),
                if (tip > 0) _ReceiptRow(label: 'Tip', value: tip),
                Divider(height: AppSpacing.lg, color: theme.dividerColor),
                _ReceiptRow(label: 'Total', value: fare + tip, bold: true),
                // Itemised lines (base / distance / time / booking fee /
                // surge / promo) when the backend recorded them; older
                // trips keep the two-line total above.
                if (state.fareBreakdown != null)
                  _FareDetails(
                    breakdown: state.fareBreakdown!,
                    currency: state.receipt?.currency ?? 'USD',
                  ),
              ],
            ),
          ),
          if (state.receipt?.isCash ?? false)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.md),
              child: Row(
                children: [
                  const Icon(Icons.payments_outlined,
                      size: 16, color: AppColors.warning),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    'Pay \$${_money(fare + tip)} in cash to your driver',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AppColors.warning),
                  ),
                ],
              ),
            ),
          const SizedBox(height: AppSpacing.xl),
          // Rating
          Center(
              child: Text('Rate your driver',
                  style: theme.textTheme.titleMedium)),
          const SizedBox(height: AppSpacing.sm),
          // Always tappable: the backend stores one rating per trip and
          // recomputes the driver's average from it, so tapping again is a
          // correction, not a second vote. A mis-tapped star used to be
          // permanent — unfair to the driver and frustrating for the rider.
          StarRating(value: state.rating ?? 0, onRate: cubit.rateDriver),
          if (state.rating != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text(
                  'Thanks for your feedback! Tap a star to change it.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ),
          // Compliment tags — shown once a (positive) rating is given, so the
          // rider can say what went well (Uber-style). Persisted with the rating.
          if (state.rating != null && state.rating! >= 4) ...[
            const SizedBox(height: AppSpacing.md),
            _ComplimentTags(
              selected: state.ratingTags,
              onChanged: (tags) => cubit.updateRatingTags(tags),
            ),
          ],
          if (state.driver?.id != null) ...[
            const SizedBox(height: AppSpacing.md),
            _FavoriteDriverButton(
              driverId: state.driver!.id!,
              driverName: state.driver!.name,
            ),
          ],
          const SizedBox(height: AppSpacing.xl),
          // Tips
          Text('Add a tip', style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              for (final amt in const [2.0, 3.0, 5.0])
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.sm),
                    child: _TipChip(
                      amount: amt,
                      selected: sentTip == null
                          ? _pendingTip == amt
                          : sentTip == amt,
                      // Locked only once the tip has actually been sent.
                      onTap: locked
                          ? null
                          : () => setState(() => _pendingTip = amt),
                    ),
                  ),
                ),
              // Custom amount — a rider isn't limited to the presets.
              Expanded(
                child: _CustomTipChip(
                  // Highlight when the chosen tip isn't one of the presets.
                  selected: chosenTip != null &&
                      !const [2.0, 3.0, 5.0].contains(chosenTip),
                  onTap: locked
                      ? null
                      : () async {
                          final amount = await _askCustomTip(context);
                          if (amount != null && mounted) {
                            setState(() => _pendingTip = amount);
                          }
                        },
                ),
              ),
            ],
          ),
          if (sentTip != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Text('Tip of \$${_money(sentTip)} added.',
                  style: theme.textTheme.bodySmall),
            )
          else if (_pendingTip != null) ...[
            const SizedBox(height: AppSpacing.sm),
            PrimaryButton(
              label: state.tipping
                  ? 'Adding tip…'
                  : 'Add \$${_money(_pendingTip!)} tip',
              onPressed: state.tipping
                  ? null
                  : () => cubit.tipDriver(_pendingTip!),
            ),
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                'You can change this until you add it.',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.xl),
          PrimaryButton(
            label: 'Done',
            onPressed: () => context.read<TripCubit>().reset(),
          ),
        ],
      ),
    );
  }
}

/// Collapsible "Fare details" disclosure under the receipt total. The tip
/// line is the sheet's own (it tracks the just-added tip live), so the
/// breakdown's tip is not repeated here.
class _FareDetails extends StatefulWidget {
  const _FareDetails({required this.breakdown, required this.currency});
  final FareBreakdown breakdown;
  final String currency;

  @override
  State<_FareDetails> createState() => _FareDetailsState();
}

class _FareDetailsState extends State<_FareDetails> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => _open = !_open),
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Row(
              children: [
                Text('Fare details',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: AppColors.accent)),
                const Spacer(),
                Icon(
                  _open
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 20,
                  color: AppColors.accent,
                ),
              ],
            ),
          ),
        ),
        if (_open)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: FareBreakdownRows(
              breakdown: widget.breakdown,
              currency: widget.currency,
              showTip: false,
              style: theme.textTheme.bodyMedium,
            ),
          ),
      ],
    );
  }
}

class _ReceiptRow extends StatelessWidget {
  const _ReceiptRow({required this.label, required this.value, this.bold = false});
  final String label;
  final double value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = bold
        ? theme.textTheme.titleMedium
        : theme.textTheme.bodyLarge;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          // Show cents so a custom tip like $7.50 sums correctly (whole amounts
          // still read cleanly as $7.00).
          Text('\$${value.toStringAsFixed(2)}', style: style?.tabular()),
        ],
      ),
    );
  }
}

class _TipChip extends StatelessWidget {
  const _TipChip({required this.amount, required this.selected, this.onTap});
  final double amount;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final enabled = onTap != null || selected;
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          color: selected
              ? (isDark ? AppColors.accentSoftDark : AppColors.accentSoft)
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppSpacing.radius),
          border: Border.all(
            color: selected ? AppColors.accent : theme.dividerColor,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: InkWell(
          onTap: onTap == null
              ? null
              : () {
                  AppHaptics.selection();
                  onTap!();
                },
          borderRadius: BorderRadius.circular(AppSpacing.radius),
          child: Container(
            height: 48,
            alignment: Alignment.center,
            child: Text(
              '\$${amount.toStringAsFixed(0)}',
              style: theme.textTheme.titleMedium?.copyWith(
                color: selected
                    ? AppColors.accent
                    : (enabled ? theme.colorScheme.onSurface : null),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A tip chip that lets the rider enter any amount, styled like [_TipChip].
class _CustomTipChip extends StatelessWidget {
  const _CustomTipChip({required this.selected, this.onTap});
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final enabled = onTap != null || selected;
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          color: selected
              ? (isDark ? AppColors.accentSoftDark : AppColors.accentSoft)
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppSpacing.radius),
          border: Border.all(
            color: selected ? AppColors.accent : theme.dividerColor,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSpacing.radius),
          child: Container(
            height: 48,
            alignment: Alignment.center,
            child: Text(
              'Custom',
              style: theme.textTheme.titleSmall?.copyWith(
                color: selected
                    ? AppColors.accent
                    : (enabled ? theme.colorScheme.onSurface : null),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Prompt for a custom tip amount and submit it.
/// Ask for a custom tip amount. Returns the amount, or null if the rider
/// backed out — sending it is the caller's job, so the choice stays
/// changeable until they confirm.
Future<double?> _askCustomTip(BuildContext context) async {
  final controller = TextEditingController();
  final amount = await showDialog<double>(
    context: context,
    builder: (dialogCtx) {
      String? error;
      return StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Add a tip'),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            decoration: InputDecoration(
              prefixText: '\$ ',
              hintText: '0.00',
              errorText: error,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final v = double.tryParse(controller.text.trim());
                if (v == null || v <= 0) {
                  setLocal(() => error = 'Enter an amount');
                  return;
                }
                if (v > 500) {
                  setLocal(() => error = 'Max \$500');
                  return;
                }
                Navigator.pop(dialogCtx, v);
              },
              child: const Text('Use amount'),
            ),
          ],
        ),
      );
    },
  );
  return amount;
}

/// Format a dollar amount without trailing `.00` (so `$4` not `$4.00`, but
/// `$4.50` keeps its cents).
String _money(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

class _Busy extends StatelessWidget {
  const _Busy({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(
          height: 22,
          width: 22,
          child: CircularProgressIndicator(strokeWidth: 2.4),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.titleMedium),
        ),
      ],
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(message, style: const TextStyle(color: AppColors.error)),
        const SizedBox(height: AppSpacing.md),
        PrimaryButton(label: 'Try again', onPressed: onRetry),
      ],
    );
  }
}

/// Chat bubble with an unread-count badge (Uber-style) for the sheet buttons.
class _ChatIcon extends StatelessWidget {
  const _ChatIcon({required this.unread});
  final int unread;

  @override
  Widget build(BuildContext context) {
    final icon = const Icon(Icons.chat_bubble_outline);
    if (unread <= 0) return icon;
    return Badge.count(count: unread, child: icon);
  }
}

/// Whole minutes for a duration, never showing "0 min" for a short hop.
int _minutes(num seconds) => (seconds / 60).ceil().clamp(1, 9999).toInt();

/// Free-text note for the driver ("meet at the lobby"), stored on the trip and
/// shown on the driver's offer card and en-route sheet.
class _PickupNoteField extends StatefulWidget {
  const _PickupNoteField({required this.state});
  final TripState state;

  @override
  State<_PickupNoteField> createState() => _PickupNoteFieldState();
}

class _PickupNoteFieldState extends State<_PickupNoteField> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.state.pickupNote ?? '');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      textCapitalization: TextCapitalization.sentences,
      maxLength: 200,
      minLines: 1,
      maxLines: 2,
      decoration: const InputDecoration(
        hintText: 'Note for driver (e.g. "meet at the lobby")',
        prefixIcon: Icon(Icons.sticky_note_2_outlined),
        isDense: true,
        counterText: '',
      ),
      onChanged: (v) => context.read<TripCubit>().setPickupNote(v),
    );
  }
}

/// Compliment chips shown after a positive rating (Uber-style). Multi-select;
/// every change re-submits the tag set with the existing star rating.
class _ComplimentTags extends StatefulWidget {
  const _ComplimentTags({required this.selected, required this.onChanged});
  final List<String> selected;
  final ValueChanged<List<String>> onChanged;

  static const List<String> options = [
    'Great conversation',
    'Clean car',
    'Safe driving',
    'Great navigation',
    'On time',
    'Cool music',
  ];

  @override
  State<_ComplimentTags> createState() => _ComplimentTagsState();
}

class _ComplimentTagsState extends State<_ComplimentTags> {
  late final Set<String> _selected = {...widget.selected};

  void _toggle(String tag) {
    setState(() {
      if (!_selected.add(tag)) _selected.remove(tag);
    });
    AppHaptics.selection();
    widget.onChanged(_selected.toList());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Text('What went well?', style: theme.textTheme.titleSmall),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          alignment: WrapAlignment.center,
          children: [
            for (final tag in _ComplimentTags.options)
              FilterChip(
                label: Text(tag),
                selected: _selected.contains(tag),
                onSelected: (_) => _toggle(tag),
                showCheckmark: false,
                selectedColor: AppColors.accentSoft,
                side: BorderSide(
                  color: _selected.contains(tag)
                      ? AppColors.accent
                      : theme.dividerColor,
                ),
              ),
          ],
        ),
      ],
    );
  }
}
