import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie/lottie.dart';

/// Audit 2026-09-25 #3: the money animation ended on its bare ground shadow,
/// a stray grey dash beside "Pay ₹… in cash". One-shots must stop on a frame
/// worth keeping, or leave nothing behind.
void main() {
  Future<LottieBuilder> pumpMoment(WidgetTester tester, Widget moment) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(MaterialApp(home: Center(child: moment)));
      // Let the asset load and decode off the fake clock.
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
      }
    });
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(seconds: 1));
    return tester.widget<LottieBuilder>(find.byType(LottieBuilder));
  }

  testWidgets('money holds on the stacked notes, not the last frame',
      (tester) async {
    final lottie = await pumpMoment(tester, const LottieMoment.money());
    expect(lottie.controller, isNotNull);
    expect(lottie.controller!.value, closeTo(LottieMoment.moneyHoldAt, 1e-6));
    expect(lottie.controller!.isAnimating, isFalse);
  });

  testWidgets('confetti fades away after its burst', (tester) async {
    final l = await pumpMoment(tester, const LottieMoment.confetti());
    expect(l.controller!.value, 1.0);
    final fade = tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity));
    expect(fade.opacity, 0);
  });

  testWidgets('reduce motion draws nothing', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: LottieMoment.money(),
      ),
    ));
    expect(find.byType(LottieBuilder), findsNothing);
  });
}
