import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

/// A one-shot Lottie animation for a moment worth celebrating: confetti when
/// a ride completes, banknotes for cash and earnings. Plays once, is hidden
/// from screen readers (decoration), and is skipped entirely under Reduce
/// Motion. Assets: assets/lottie/ (see CREDITS.md there).
class LottieMoment extends StatelessWidget {
  const LottieMoment.confetti({super.key, this.size = 220, this.repeat = false})
      : asset = 'confetti';
  const LottieMoment.money({super.key, this.size = 48, this.repeat = false})
      : asset = 'money';

  /// Looping loader ("Sandy Loading") for waits like "Requesting your ride".
  const LottieMoment.loading({super.key, this.size = 56, this.repeat = true})
      : asset = 'loading';

  final String asset;
  final double size;
  final bool repeat;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      return SizedBox(width: size, height: size);
    }
    return ExcludeSemantics(
      child: IgnorePointer(
        child: Lottie.asset(
          'packages/design_system/assets/lottie/$asset.json',
          width: size,
          height: size,
          repeat: repeat,
          fit: BoxFit.contain,
          // A missing/corrupt file must never break the screen.
          errorBuilder: (_, _, _) => SizedBox(width: size, height: size),
        ),
      ),
    );
  }
}
