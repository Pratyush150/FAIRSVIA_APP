import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

/// How a one-shot [LottieMoment] finishes.
enum LottieEnd {
  /// Stop and hold on [LottieMoment.holdAt] (a frame worth keeping).
  hold,

  /// Play to the end, then fade the whole animation away, leaving nothing.
  vanish,
}

/// A one-shot Lottie animation for a moment worth celebrating: confetti when
/// a ride completes, banknotes for cash and earnings. Plays once, is hidden
/// from screen readers (decoration), and is skipped entirely under Reduce
/// Motion. Assets: assets/lottie/ (see CREDITS.md there).
///
/// A one-shot never rests on the animation's own last frame. The money file
/// ends with its notes shrunk to nothing over a grey ground shadow, and that
/// shadow alone read as a stray dash beside "Pay ₹… in cash" (audit
/// 2026-09-25 #3). So money plays in and holds on the stack of notes, and
/// confetti fades out after its burst instead of leaving debris.
class LottieMoment extends StatefulWidget {
  const LottieMoment.confetti({super.key, this.size = 220, this.repeat = false})
      : asset = 'confetti',
        holdAt = 1.0,
        end = LottieEnd.vanish;

  /// Holds at frame ~60 of 121: all notes stacked (they land by frame 22
  /// and only start to fly off at 104).
  const LottieMoment.money({super.key, this.size = 48, this.repeat = false})
      : asset = 'money',
        holdAt = moneyHoldAt,
        end = LottieEnd.hold;

  /// Looping loader ("Sandy Loading") for waits like "Requesting your ride".
  const LottieMoment.loading({super.key, this.size = 56, this.repeat = true})
      : asset = 'loading',
        holdAt = 1.0,
        end = LottieEnd.hold;

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
    // animateTo scales the time by the distance, so this is the real pace.
    _c.animateTo(widget.holdAt);
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      return SizedBox(width: size, height: size);
    }
    return ExcludeSemantics(
      child: IgnorePointer(
        child: AnimatedOpacity(
          opacity: _gone ? 0 : 1,
          duration: LottieMoment.vanishFade,
          child: Lottie.asset(
            'packages/design_system/assets/lottie/${widget.asset}.json',
            controller: _c,
            onLoaded: _start,
            width: size,
            height: size,
            fit: BoxFit.contain,
            // A missing/corrupt file must never break the screen.
            errorBuilder: (_, _, _) => SizedBox(width: size, height: size),
          ),
        ),
      ),
    );
  }
}
