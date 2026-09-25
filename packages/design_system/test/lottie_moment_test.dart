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

  group('ride moments', () {
    testWidgets('one-shots hold on their last frame', (tester) async {
      for (final m in const [
        LottieMoment.arrived(),
        LottieMoment.success(),
        LottieMoment.thanks(),
        LottieMoment.sos(),
      ]) {
        final l = await pumpMoment(tester, m);
        expect(l.controller!.value, 1.0, reason: m.asset);
        expect(l.controller!.isAnimating, isFalse, reason: m.asset);
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('waiting states loop', (tester) async {
      for (final m in const [
        LottieMoment.searching(),
        LottieMoment.noCars(),
        LottieMoment.location(),
        LottieMoment.offline(),
      ]) {
        final l = await pumpMoment(tester, m);
        expect(l.controller!.isAnimating, isTrue, reason: m.asset);
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('reduce motion shows a still frame, in a fixed box',
        (tester) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: Center(child: LottieMoment.offline(size: 40)),
          ),
        ));
        for (var i = 0; i < 20; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          await tester.pump();
        }
      });
      await tester.pump(const Duration(seconds: 2));
      final l = tester.widget<LottieBuilder>(find.byType(LottieBuilder));
      expect(l.controller!.value,
          closeTo(LottieMoment.offlineStillAt, 1e-6));
      expect(l.controller!.isAnimating, isFalse);
      expect(tester.getSize(find.byType(LottieMoment)), const Size(40, 40));
    });

    testWidgets('every moment file loads', (tester) async {
      for (final name in const [
        'searching', 'arrived', 'no_cars', 'success',
        'thanks', 'location', 'offline', 'sos',
      ]) {
        final comp = await tester.runAsync(() => AssetLottie(
                'packages/design_system/assets/lottie/$name.json')
            .load());
        expect(comp, isNotNull, reason: name);
        expect(comp!.duration, greaterThan(Duration.zero), reason: name);
      }
    });
  });
}
