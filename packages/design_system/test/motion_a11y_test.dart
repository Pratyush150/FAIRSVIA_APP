import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Motion tokens (audit 4.1), Reduce Motion (4.2) and the shared a11y
/// helpers (4.3).
void main() {
  test('the duration scale is 100 / 200 / 350 / 500 ms', () {
    expect(AppMotion.fast, const Duration(milliseconds: 100));
    expect(AppMotion.normal, const Duration(milliseconds: 200));
    expect(AppMotion.slow, const Duration(milliseconds: 350));
    expect(AppMotion.slower, const Duration(milliseconds: 500));
    expect(AppMotion.enter, Easing.emphasizedDecelerate);
    expect(AppMotion.exit, Easing.emphasizedAccelerate);
  });

  test('plates and codes are spelled one character at a time', () {
    expect(AppA11y.spell('MH 12 AB 3456'), 'M H 1 2 A B 3 4 5 6');
    expect(AppA11y.spell('4827'), '4 8 2 7');
  });

  Widget host({required bool reduce, required Widget child}) => MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduce),
          child: Scaffold(body: Center(child: child)),
        ),
      );

  for (final reduce in const [false, true]) {
    testWidgets('reveal() ${reduce ? 'does not move' : 'rises into place'} '
        'under Reduce Motion ${reduce ? 'on' : 'off'}', (tester) async {
      await tester.pumpWidget(
          host(reduce: reduce, child: const Text('Hi').reveal()));
      await tester.pump(const Duration(milliseconds: 16));
      final early = tester.getTopLeft(find.text('Hi'));
      await tester.pumpAndSettle();
      final settled = tester.getTopLeft(find.text('Hi'));
      if (reduce) {
        expect(early, settled);
      } else {
        expect(early.dy, greaterThan(settled.dy));
      }
    });
  }

  testWidgets('AppMotion.of drops to zero under Reduce Motion', (tester) async {
    late Duration on, off;
    await tester.pumpWidget(host(
      reduce: true,
      child: Builder(builder: (c) {
        on = AppMotion.of(c, AppMotion.slow);
        return const SizedBox();
      }),
    ));
    await tester.pumpWidget(host(
      reduce: false,
      child: Builder(builder: (c) {
        off = AppMotion.of(c, AppMotion.slow);
        return const SizedBox();
      }),
    ));
    expect(on, Duration.zero);
    expect(off, AppMotion.slow);
  });

  testWidgets('a tappable star rating is labelled and 48 dp per star',
      (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(host(
      reduce: false,
      child: StarRating(value: 3, onRate: (_) {}),
    ));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Rate 1 star'), findsOneWidget);
    expect(find.byTooltip('Rate 5 stars'), findsOneWidget);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });

  testWidgets('a read-only rating is one phrase', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
        host(reduce: true, child: const StarRating(value: 4)));
    await tester.pump();
    expect(find.bySemanticsLabel('Rated 4 out of 5'), findsOneWidget);
    handle.dispose();
  });
}
