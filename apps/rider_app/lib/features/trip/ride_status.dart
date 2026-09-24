import 'package:core/core.dart';

import 'trip_cubit.dart';
import 'package:shared_models/shared_models.dart';

/// How urgent a ride state is, so the sheet can tint its status chip without
/// each sheet re-deciding what "arrived" looks like.
enum RideStatusTone { neutral, accent, success }

/// The headline and sub-line the ride sheet shows for one moment of a ride.
///
/// This is the single source of the ride's micro-copy. Every sheet reads it
/// instead of assembling its own sentence, which is what let "Arriving in 4
/// min" end up as the *headline* on one screen and a detail line on the next.
/// It is a pure value derived from [TripState], so the wording — including the
/// thresholds that switch it — is unit-testable without pumping a widget.
class RideStatus {
  const RideStatus({
    required this.title,
    this.subtitle,
    this.tone = RideStatusTone.neutral,
  });

  /// The main line: what is happening ("Your driver is on the way").
  final String title;

  /// The supporting line: the number or the instruction ("Arriving in 4 min").
  final String? subtitle;

  final RideStatusTone tone;

  /// At or below this ETA the driver counts as "almost here" — close enough
  /// that the rider should start walking out, not keep watching the map.
  static const int almostHereSec = 150; // 2.5 min → rounds to "2 min"

  /// At or below this remaining trip time the ride is "arriving soon", so the
  /// rider can get their things together.
  static const int arrivingSoonSec = 120;

  /// Minutes, rounded up and floored at 1 — a live ETA that reads "0 min" is
  /// worse than one that reads "1 min", because zero implies "already there".
  static int minutesFrom(int seconds) => (seconds / 60).ceil().clamp(1, 999);

  /// "4 min", "1 min".
  static String minuteLabel(int seconds) {
    final m = minutesFrom(seconds);
    return '$m min';
  }

  /// "Bekzod" from "Bekzod Karimov"; the generic phrase when the payload has
  /// no real name (restored trip, older backend).
  static String driverName(TripState state) {
    final n = state.driver?.name.trim() ?? '';
    if (n.isEmpty || n == 'Your driver') return 'Your driver';
    return n.split(RegExp(r'\s+')).first;
  }

  /// The copy for [state]'s current moment.
  ///
  /// [currency] formats the completed-ride total; it defaults to the receipt's
  /// own currency so a trip priced in another market reads correctly.
  static RideStatus of(TripState state) {
    switch (state.phase) {
      case TripPhase.searching:
        return const RideStatus(
          title: 'Finding your driver',
          subtitle: 'Looking for nearby drivers…',
          tone: RideStatusTone.accent,
        );

      case TripPhase.driverEnRoute:
        // The live ETA recomputed from each driver ping, falling back to the
        // one quoted when the driver accepted — that is all we have between
        // the accept and the first ping, and dropping it left the sheet
        // saying nothing about timing for the first few seconds of every ride.
        final eta = state.liveEtaSec ?? state.driver?.etaSec;
        // Neither is known (or a stale stream): promise a time we cannot back
        // up and the rider watches a countdown that never moves. Say what we
        // actually know instead.
        final who = driverName(state);
        if (eta == null || eta <= 0) {
          return RideStatus(
            title: '$who is on the way',
            subtitle: null,
            tone: RideStatusTone.accent,
          );
        }
        final almost = eta <= almostHereSec;
        // Name and time in the headline, the way riders scan it ("Rahul
        // arriving in 3 min"); the line under it says what to do.
        return RideStatus(
          title: almost
              ? '$who is arriving now'
              : '$who arriving in ${minuteLabel(eta)}',
          subtitle: almost ? 'Head to your pickup spot' : 'Meet at your pickup spot',
          tone: almost ? RideStatusTone.success : RideStatusTone.accent,
        );

      case TripPhase.driverArrived:
        return RideStatus(
          title: '${driverName(state)} has arrived',
          subtitle: 'Meet them at the pickup',
          tone: RideStatusTone.success,
        );

      case TripPhase.onTrip:
        final left = state.liveEtaSec ?? state.estimate?.durationS;
        if (left != null && left <= arrivingSoonSec) {
          return RideStatus(
            title: 'Arriving soon',
            subtitle: state.dropoffAddr,
            tone: RideStatusTone.success,
          );
        }
        return RideStatus(
          title: 'Ride in progress',
          subtitle:
              left == null ? state.dropoffAddr : '${minuteLabel(left)} to destination',
          tone: RideStatusTone.accent,
        );

      case TripPhase.completed:
        final fare = state.displayFare;
        return RideStatus(
          title: 'Ride completed',
          subtitle: fare == null
              ? null
              : Fmt.money(fare, state.receipt?.currency ?? Market.current.currency),
          tone: RideStatusTone.success,
        );

      case TripPhase.idle:
      case TripPhase.loadingEstimate:
      case TripPhase.choosingRide:
      case TripPhase.requesting:
      case TripPhase.scheduled:
      case TripPhase.error:
        return const RideStatus(title: '');
    }
  }
}
