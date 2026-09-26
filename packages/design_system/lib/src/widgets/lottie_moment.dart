import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

/// How a one-shot [LottieMoment] finishes.
enum LottieEnd {
  /// Stop and hold on [LottieMoment.holdAt] (a frame worth keeping).
  hold,

  /// Play to the end, then fade the whole animation away, leaving nothing.
  vanish,
}

/// A Lottie animation for a moment in the ride: confetti when a ride
/// completes, banknotes for cash and earnings, a radar while finding a
/// driver, a pin when the driver arrives, a check when a payment or tip goes
/// through, and quiet status art (no cars, location off, offline, SOS sent).
/// Hidden from screen readers (decoration: the text beside it says it).
///
/// Reduce Motion: celebrations (confetti, money, loading) draw nothing; the
/// status moments show one still frame ([stillAt]) instead, because there the
/// picture carries meaning. Either way the box keeps its [size], so layouts do
/// not jump. Assets: assets/lottie/ (see CREDITS.md there).
///
/// A one-shot never rests on the animation's own last frame. The money file
/// ends with its notes shrunk to nothing over a grey ground shadow, and that
/// shadow alone read as a stray dash beside "Pay ₹… in cash" (audit
/// 2026-09-25 #3). So money plays in and holds on the stack of notes, and
/// confetti fades out after its burst instead of leaving debris.
class LottieMoment extends StatefulWidget {
  const LottieMoment.confetti({super.key, this.size = 220, this.repeat = false})
    : asset = 'confetti',
      artScale = 1.0,
      holdAt = 1.0,
      end = LottieEnd.vanish,
      stillAt = null,
      tint = null,
      plays = 1;

  /// Holds at frame ~60 of 121: all notes stacked (they land by frame 22
  /// and only start to fly off at 104).
  const LottieMoment.money({super.key, this.size = 48, this.repeat = false})
    : asset = 'money',
      artScale = 1.0,
      holdAt = moneyHoldAt,
      end = LottieEnd.hold,
      stillAt = null,
      tint = null,
      plays = 1;

  /// Looping loader ("Sandy Loading") for waits like "Requesting your ride".
  const LottieMoment.loading({super.key, this.size = 56, this.repeat = true})
    : asset = 'loading',
      artScale = 1.0,
      holdAt = 1.0,
      end = LottieEnd.hold,
      stillAt = null,
      tint = null,
      plays = 1;

  /// Looping radar sweep around a pin: "Finding your driver".
  const LottieMoment.searching({super.key, this.size = 96, this.repeat = true})
    : asset = 'searching',
      artScale = 1.0,
      holdAt = 1.0,
      end = LottieEnd.hold,
      stillAt = 0.3,
      tint = null,
      plays = 1;

  /// A pin drops and lands with a ripple: the driver has arrived. Plays once
  /// and holds on the landed pin.
  const LottieMoment.arrived({super.key, this.size = 72, this.repeat = false})
    : asset = 'arrived',
      artScale = 1.0,
      holdAt = 1.0,
      end = LottieEnd.hold,
      stillAt = 1.0,
      tint = null,
      plays = 1;

  /// A magnifier looking around: no cars nearby. Loops gently.
  const LottieMoment.noCars({super.key, this.size = 96, this.repeat = true})
    : asset = 'no_cars',
      artScale = 1.0,
      holdAt = 1.0,
      end = LottieEnd.hold,
      stillAt = 0.3,
      tint = null,
      plays = 1;

  /// A teal check with a small burst: payment or tip went through. Plays
  /// once and holds on the check.
  const LottieMoment.success({super.key, this.size = 64, this.repeat = false})
    : asset = 'success',
      artScale = 1.0,
      holdAt = 1.0,
      end = LottieEnd.hold,
      stillAt = 1.0,
      tint = null,
      plays = 1;

  /// A star fills with a little sparkle: thanks for rating. Plays once and
  /// holds on the gold star.
  const LottieMoment.thanks({super.key, this.size = 48, this.repeat = false})
    : asset = 'thanks',
      artScale = 1.0,
      holdAt = 1.0,
      end = LottieEnd.hold,
      stillAt = 1.0,
      tint = null,
      plays = 1;

  /// A finger flips a location toggle on and the pin rises: turn location
  /// on. Loops; the still frame is the "on" state.
  const LottieMoment.location({super.key, this.size = 96, this.repeat = true})
    : asset = 'location',
      artScale = 1.0,
      holdAt = 1.0,
      end = LottieEnd.hold,
      stillAt = 1.0,
      tint = null,
      plays = 1;

  /// Wi-Fi bars that drop and cross out: offline. Loops; the still frame is
  /// the crossed-out signal.
  const LottieMoment.offline({
    super.key,
    this.size = 56,
    this.repeat = true,
    this.tint,
  }) : asset = 'offline',
       artScale = 1.0,
       holdAt = 1.0,
       end = LottieEnd.hold,
       stillAt = offlineStillAt,
       plays = 1;

  /// A shield draws itself and fills with a check: SOS sent, help is on the
  /// way. Calm, not an alarm. Plays once and holds on the filled shield.
  const LottieMoment.sos({super.key, this.size = 88, this.repeat = false})
    : asset = 'sos',
      artScale = 1.0,
      holdAt = 1.0,
      end = LottieEnd.hold,
      stillAt = 1.0,
      tint = null,
      plays = 1;

  /// The brand loader: a teal arc that sweeps round and closes. Replaces the
  /// stock CircularProgressIndicator in waits (see [BrandLoader]). Under
  /// Reduce Motion it holds on the near-full arc.
  const LottieMoment.spinner({
    super.key,
    this.size = 40,
    this.repeat = true,
    this.tint,
  }) : asset = 'spinner',
       artScale = 1.0,
       holdAt = 1.0,
       end = LottieEnd.hold,
       stillAt = 0.55,
       plays = 1;

  /// An open, empty box with a moth drifting out: nothing here yet (no
  /// trips, no earnings). Plays once and holds on the moth in flight: an
  /// empty state that loops forever is noise (and never lets a test settle).
  const LottieMoment.emptyBox({super.key, this.size = 120, this.repeat = false})
    : asset = 'empty_box',
      artScale = 1.0,
      holdAt = 1.0,
      end = LottieEnd.hold,
      stillAt = 1.0,
      tint = null,
      plays = 1;

  /// A sad magnifier: a search that found nothing. Plays once and holds.
  const LottieMoment.noResults({super.key, this.size = 96, this.repeat = false})
    : asset = 'no_results',
      artScale = 1.0,
      holdAt = 1.0,
      end = LottieEnd.hold,
      stillAt = 1.0,
      tint = null,
      plays = 1;

  /// A gift box drops, its lid lands and a bow pops out: offers. Plays once
  /// and holds on the wrapped gift.
  ///
  /// [plays] > 1 replays the drop that many times before holding (e.g. the
  /// Offers tab: noticeable, but bounded — never a loop).
  const LottieMoment.gift({
    super.key,
    this.size = 112,
    this.repeat = false,
    this.plays = 1,
  }) : asset = 'gift',
       artScale = 1.0,
       holdAt = 1.0,
       end = LottieEnd.hold,
       stillAt = 1.0,
       tint = null;

  /// Bottom-nav house: the roof draws on and the door settles. Plays once
  /// and holds on the finished house. Pass the nav's [tint] (selected /
  /// unselected colour) so the line art follows any theme colour.
  const LottieMoment.navHome({
    super.key,
    this.size = navSize,
    this.tint,
    this.repeat = false,
  }) : asset = 'nav_home',
       artScale = 0.92,
       holdAt = 1.0,
       end = LottieEnd.hold,
       stillAt = 1.0,
       plays = 1;

  /// Bottom-nav receipt (Trips): the slip unrolls line by line. Plays once
  /// and holds on the full receipt; [tint] as for [LottieMoment.navHome].
  const LottieMoment.navTrips({
    super.key,
    this.size = navSize,
    this.tint,
    this.repeat = false,
  }) : asset = 'nav_trips',
       artScale = 1.55,
       holdAt = 1.0,
       end = LottieEnd.hold,
       stillAt = 1.0,
       plays = 1;

  /// Bottom-nav user (Account): head and shoulders draw on. Plays once and
  /// holds on the figure; [tint] as for [LottieMoment.navHome].
  const LottieMoment.navAccount({
    super.key,
    this.size = navSize,
    this.tint,
    this.repeat = false,
  }) : asset = 'nav_account',
       artScale = 0.92,
       holdAt = 1.0,
       end = LottieEnd.hold,
       stillAt = 1.0,
       plays = 1;

  /// Box size of the bottom-nav icons: a touch larger than a 24 px glyph
  /// because the art has air around it (matches the Offers gift).
  static const double navSize = 30;

  /// A gold trophy rises with laurels: a quest completed. Plays once and
  /// holds on the trophy.
  const LottieMoment.trophy({super.key, this.size = 72, this.repeat = false})
    : asset = 'trophy',
      artScale = 1.0,
      holdAt = 1.0,
      end = LottieEnd.hold,
      stillAt = 1.0,
      tint = null,
      plays = 1;

  /// Progress of the offline loop where the signal is crossed out.
  static const double offlineStillAt = 0.8;

  /// Progress (0..1) the money animation stops on.
  static const double moneyHoldAt = 0.5;

  /// How long a [LottieEnd.vanish] animation takes to fade after it ends.
  static const Duration vanishFade = Duration(milliseconds: 280);

  final String asset;
  final double size;
  final bool repeat;

  /// Progress (0..1) a one-shot stops at.
  final double holdAt;
  final LottieEnd end;

  /// The one frame (0..1) shown under Reduce Motion, or null to draw nothing.
  final double? stillAt;

  /// Paints every fill and stroke in one colour (e.g. the ink of a warning
  /// banner the art sits on); null keeps the file's own palette.
  final Color? tint;

  /// Scales the drawing inside its box (clipped to it), for art whose file
  /// leaves more or less air than its siblings (the nav receipt is drawn
  /// small in its canvas).
  final double artScale;

  /// How many times a one-shot plays before it holds on [holdAt] (1 = once).
  final int plays;

  @override
  State<LottieMoment> createState() => _LottieMomentState();
}

class _LottieMomentState extends State<LottieMoment>
    with SingleTickerProviderStateMixin {
  // Created up front, not lazily: a lazy controller first touched in
  // dispose() (Reduce Motion never builds the animation) looks up the
  // TickerMode of a deactivated element.
  late final AnimationController _c;
  bool _gone = false;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _start(LottieComposition comp) {
    _c.duration = comp.duration;
    if (_still) {
      _c.value = widget.stillAt!;
      return;
    }
    if (widget.repeat) {
      _c.repeat();
      return;
    }
    if (widget.end == LottieEnd.vanish) {
      _c.addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted && !_gone) {
          setState(() => _gone = true);
        }
      });
    }
    _play(widget.plays);
  }

  void _play(int left) {
    if (!mounted) return;
    if (left > 1) {
      _c.forward(from: 0).whenCompleteOrCancel(() {
        if (mounted && _c.status == AnimationStatus.completed) _play(left - 1);
      });
      return;
    }
    if (_c.value >= widget.holdAt) _c.value = 0;
    // animateTo scales the time by the distance, so this is the real pace.
    _c.animateTo(widget.holdAt);
  }

  // Reduce Motion with a still frame to show. Read in build; onLoaded runs
  // after it.
  bool _still = false;

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce && widget.stillAt == null) {
      return SizedBox(width: size, height: size);
    }
    _still = reduce;
    return ExcludeSemantics(
      child: IgnorePointer(
        child: AnimatedOpacity(
          opacity: _gone ? 0 : 1,
          duration: LottieMoment.vanishFade,
          child: _scaled(
            Lottie.asset(
              'packages/design_system/assets/lottie/${widget.asset}.json',
              controller: _c,
              onLoaded: _start,
              delegates: widget.tint == null
                  ? null
                  : LottieDelegates(
                      values: [
                        ValueDelegate.color(const ['**'], value: widget.tint),
                        ValueDelegate.strokeColor(const [
                          '**',
                        ], value: widget.tint),
                      ],
                    ),
              width: size,
              height: size,
              fit: BoxFit.contain,
              // A missing/corrupt file must never break the screen.
              errorBuilder: (_, _, _) => SizedBox(width: size, height: size),
            ),
          ),
        ),
      ),
    );
  }

  Widget _scaled(Widget art) => widget.artScale == 1.0
      ? art
      : ClipRect(
          child: Transform.scale(scale: widget.artScale, child: art),
        );
}
