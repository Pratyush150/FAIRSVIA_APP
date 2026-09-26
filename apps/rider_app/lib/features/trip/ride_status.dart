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
    String? moment,
    this.momentDetail,
  }) : moment = moment ?? title;

  /// The main line: what is happening ("Your driver is on the way").
  final String title;

  /// The supporting line: the number or the instruction ("Arriving in 4 min").
  final String? subtitle;

  final RideStatusTone tone;

  /// The headline without its ticking number, for screen readers: what they
  /// announce when it changes. "Bekzod is on the way" while the headline
  /// counts "Bekzod arriving in 4 min … 3 min" — so a reader hears each
  /// real change of moment (on the way → arriving now → has arrived), not
  /// every minute. Same as [title] when the title has no number in it.
  final String moment;

  /// The number [moment] leaves out ("arriving in 4 min"), read after it when
  /// the headline is focused, so nothing on screen is hidden from a reader.
  final String? momentDetail;

  /// [title] as drawn: the ticking part ([momentDetail], "arriving in 9 min")
  /// joined with non-breaking spaces so a narrow screen or a large text size
  /// can only wrap *before* it — "Amit / arriving in 9 min" — and never
  /// orphan "min" on a line of its own ("Amit arriving in 9 / min", audit
  /// 2026-09-25 A.21). [title] keeps plain spaces for readers and tests.
  String get displayTitle {
    final detail = momentDetail;
    if (detail == null || !title.contains(detail)) return title;
    return title.replaceFirst(detail, detail.replaceAll(' ', nbsp));
  }

  /// The non-breaking space [displayTitle] glues the ETA phrase with.
  static const String nbsp = '\u00A0';

  /// At or below this ETA the driver counts as "almost here" — close enough
  /// that the rider should start walking out, not keep watching the map.
  static const int almostHereSec = 150; // 2.5 min → rounds to "2 min"

  /// At or below this remaining trip time the ride is "arriving soon", so the
  /// rider can get their things together.
  static const int arrivingSoonSec = 120;

  /// Under this much road left the ride is "arriving soon" (audit 3.10). The
  /// distance wins over [arrivingSoonSec] whenever the live leg carries it:
  /// two minutes in Pune traffic can still be a kilometre away.
  static const int arrivingSoonM = 500;

  /// Under this much road left there is no point offering "Add a stop" — the
  /// ride is all but over (audit 3.10).
  static const int addStopCutoffM = 1000;

  /// How long "Finding your driver" can run before the sheet admits it is
  /// taking a while (audit 3.8).
  static const Duration stillLookingAfter = Duration(seconds: 45);

  /// How long the server keeps searching for a driver before it gives up
  /// (its SEARCH_WINDOW_SEC default). Only a fallback: the `trip:matching`
  /// event carries the server's real deadline ([TripState.searchEndsAt]).
  static const Duration searchWindow = Duration(seconds: 180);

  /// The finding sheet's time line: "Still looking… up to 3 min", then
  /// seconds in the last minute. The search is bounded, and the rider should
  /// see that rather than an open-ended spinner.
  static String searchTimeLeft(Duration left) {
    final s = left.inSeconds;
    if (s <= 0) return 'Finishing the search…';
    if (s > 60) return 'Still looking… up to ${(s / 60).ceil()} min';
    return 'Still looking… up to $s s';
  }

  /// Road left on the trip leg, or null when no live number is known. Only
  /// during the trip itself: while the driver is on the way the live figure
  /// is the approach leg, not the rider's journey.
  static int? tripRemainingM(TripState state) =>
      state.phase == TripPhase.onTrip ? state.liveRemainingM : null;

  /// True once the ride is close enough to its end that adding a stop would
  /// only confuse the driver. False when the distance left is unknown.
  static bool nearlyThere(TripState state) {
    final left = tripRemainingM(state);
    return left != null && left < addStopCutoffM;
  }

  /// The destination as a rider names it: the first part of the address
  /// ("Pune Railway Station" from "Pune Railway Station, Agarkar Nagar, Pune…"),
  /// or null when there is none.
  static String? placeName(TripState state) {
    final addr = (state.dropoffAddr ?? state.trip?.dropoff.address)?.trim();
    if (addr == null || addr.isEmpty) return null;
    final first = addr.split(',').first.trim();
    return first.isEmpty ? addr : first;
  }

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
  ///
  /// [stillLooking] is true once the search has run past [stillLookingAfter];
  /// the sheet owns that clock, so this stays a pure function of its inputs.
  static RideStatus of(TripState state, {bool stillLooking = false}) {
    switch (state.phase) {
      case TripPhase.searching:
        return RideStatus(
          title: 'Finding your driver',
          subtitle: stillLooking
              ? 'Still looking…'
              : 'Looking for nearby drivers…',
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
          moment: almost ? null : '$who is on the way',
          momentDetail: almost ? null : 'arriving in ${minuteLabel(eta)}',
          subtitle: almost
              ? 'Head to your pickup spot'
              : 'Meet at your pickup spot',
          tone: almost ? RideStatusTone.success : RideStatusTone.accent,
        );

      case TripPhase.driverArrived:
        return RideStatus(
          title: '${driverName(state)} has arrived',
          subtitle: 'Meet them at the pickup',
          tone: RideStatusTone.success,
        );

      case TripPhase.onTrip:
        // The destination appears exactly once: in the headline while the
        // ride is under way, in the sub-line once it is arriving.
        final left = state.liveEtaSec ?? state.estimate?.durationS;
        final metres = tripRemainingM(state);
        final place = placeName(state);
        final soon = metres != null
            ? metres < arrivingSoonM
            : (left != null && left <= arrivingSoonSec);
        if (soon) {
          return RideStatus(
            title: 'Arriving soon',
            subtitle: place,
            tone: RideStatusTone.success,
          );
        }
        return RideStatus(
          title: 'On the way to ${place ?? 'your destination'}',
          subtitle: left == null ? null : '${minuteLabel(left)} to destination',
          tone: RideStatusTone.accent,
        );

      case TripPhase.completed:
        final fare = state.displayFare;
        return RideStatus(
          title: 'Ride completed',
          subtitle: fare == null
              ? null
              : Fmt.money(
                  fare,
                  state.receipt?.currency ?? Market.current.currency,
                ),
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
