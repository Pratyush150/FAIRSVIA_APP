import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The audit's type scale (ui-10-audit-plan 3.2) and control sizes (3.3), as
/// the theme actually ships them.
void main() {
  // size, line height, weight
  void scale(TextStyle? s, double size, double line, FontWeight weight) {
    expect(s, isNotNull);
    expect(s!.fontSize, size);
    expect(s.fontSize! * s.height!, closeTo(line, 0.001));
    expect(s.fontWeight, weight);
  }

  for (final dark in [false, true]) {
    final t = (dark ? AppTheme.dark : AppTheme.light).textTheme;
    test('type scale, dark=$dark', () {
      scale(t.displaySmall, 28, 34, FontWeight.w700); // display
      scale(t.headlineLarge, 28, 34, FontWeight.w700);
      scale(t.headlineSmall, 22, 28, FontWeight.w600); // title
      scale(t.titleLarge, 22, 28, FontWeight.w600);
      scale(t.titleMedium, 17, 24, FontWeight.w600); // body.strong
      scale(t.bodyLarge, 15, 22, FontWeight.w400); // body
      scale(t.bodyMedium, 15, 22, FontWeight.w400);
      scale(t.bodySmall, 13, 18, FontWeight.w400); // caption
    });
  }

  test('every line height sits on the 2 pt half-grid', () {
    final t = AppTheme.light.textTheme;
    for (final s in [
      t.displaySmall, t.headlineLarge, t.headlineMedium, t.headlineSmall,
      t.titleLarge, t.titleMedium, t.titleSmall, t.bodyLarge, t.bodyMedium,
      t.bodySmall, t.labelLarge, t.labelMedium, t.labelSmall,
    ]) {
      final line = s!.fontSize! * s.height!;
      expect((line / 2 - (line / 2).roundToDouble()).abs(), lessThan(0.001),
          reason: '$s');
    }
  });

  test('plate: 22/28/700, tabular, +4 % tracking', () {
    const p = AppTypography.plate;
    scale(p, 22, 28, FontWeight.w700);
    expect(p.letterSpacing, closeTo(0.88, 0.0001));
    expect(p.fontFeatures, contains(const FontFeature.tabularFigures()));
  });

  testWidgets('buttons: primary and secondary 56 high, text at least 44',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Column(children: [
          PrimaryButton(label: 'Confirm', onPressed: () {}),
          SecondaryButton(label: 'Cancel', onPressed: () {}),
          Center(child: TextButton(onPressed: () {}, child: const Text('Skip'))),
        ]),
      ),
    ));
    expect(tester.getSize(find.byType(PrimaryButton)).height, 56);
    expect(tester.getSize(find.byType(SecondaryButton)).height, 56);
    final text = tester.getSize(find.widgetWithText(TextButton, 'Skip'));
    expect(text.height, greaterThanOrEqualTo(44));
    expect(AppSpacing.screenMargin, 16);
    expect(AppSpacing.buttonHeight % 4, 0);
    expect(AppSpacing.buttonHeightTertiary % 4, 0);
  });
}
