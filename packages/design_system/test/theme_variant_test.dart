import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The Visual Direction v2 tokens, checked per build. CI runs this file once
/// per variant: `flutter test --dart-define=THEME=midnight|daylight|daynight`
/// (and plain, for the shipped turquoise palette).
void main() {
  double contrast(Color a, Color b) {
    final la = a.computeLuminance(), lb = b.computeLuminance();
    final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }

  test('the build carries its plan\'s tokens', () {
    switch (AppColors.variant) {
      case 'midnight':
        expect(AppColors.backgroundDark, const Color(0xFF0E0F11));
        expect(AppColors.surfaceDark, const Color(0xFF17181B));
        expect(AppColors.inkFor(true), const Color(0xFF2BC4C4));
        expect(AppColors.onInkFor(true), const Color(0xFF0E0F11));
      case 'daylight':
        expect(AppColors.backgroundLight, const Color(0xFFF5F6F7));
        expect(AppColors.inkFor(false), const Color(0xFF0A7C7C));
        expect(AppColors.highlightFor(false), const Color(0xFF2BC4C4));
        expect(AppColors.textPrimaryLight, const Color(0xFF111315));
      case 'daynight':
        // Day is Plan B, night is Plan A.
        expect(AppColors.inkFor(false), const Color(0xFF0A7C7C));
        expect(AppColors.inkFor(true), const Color(0xFF2BC4C4));
        expect(AppColors.backgroundDark, const Color(0xFF0E0F11));
        expect(AppColors.backgroundLight, const Color(0xFFF5F6F7));
      default:
        // The shipped palette is untouched by the variants.
        expect(AppColors.v2, isFalse);
        expect(AppColors.backgroundDark, const Color(0xFF000000));
        expect(AppSpacing.radius, 8);
    }
  });

  test('text and buttons stay readable in every variant (WCAG AA)', () {
    for (final dark in [false, true]) {
      final bg = dark ? AppColors.surfaceDark : AppColors.surfaceLight;
      final text = dark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
      final secondary =
          dark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
      expect(contrast(text, bg), greaterThan(7), reason: 'primary, dark=$dark');
      expect(contrast(secondary, bg), greaterThan(4.5),
          reason: 'secondary, dark=$dark');
      expect(contrast(AppColors.onInkFor(dark), AppColors.inkFor(dark)),
          greaterThan(4.5),
          reason: 'button label, dark=$dark');
    }
  });

  test('named tokens: icon.neutral, danger and warning (audit 3.1)', () {
    expect(AppColors.iconNeutralDark, const Color(0xFF9A9DA3));
    expect(AppColors.dangerDark, const Color(0xFFFF4D4F));
    expect(AppColors.warningDark, const Color(0xFFF5A623));
    for (final dark in [false, true]) {
      final surfaces = dark
          ? [AppColors.surfaceDark, AppColors.surfaceMutedDark,
              AppColors.backgroundDark]
          : [AppColors.surfaceLight, AppColors.surfaceMutedLight,
              AppColors.backgroundLight];
      for (final bg in surfaces) {
        // Icons need 3:1; the dark danger/warning are used for text too.
        expect(contrast(AppColors.iconNeutralFor(dark), bg), greaterThan(3),
            reason: 'icon.neutral on $bg');
        if (dark) {
          expect(contrast(AppColors.dangerFor(dark), bg), greaterThan(4.5),
              reason: 'danger on $bg');
          expect(contrast(AppColors.warningFor(dark), bg), greaterThan(4.5),
              reason: 'warning on $bg');
        }
      }
    }
    // Only the v2 builds switch the theme's dark error colour; the shipped
    // default keeps the red its screens were tuned with.
    expect(AppTheme.dark.colorScheme.error,
        AppColors.v2 ? AppColors.dangerDark : AppColors.error);
    expect(AppTheme.light.colorScheme.error, AppColors.error);
  });

  testWidgets('the Driver pill reads in light and dark', (tester) async {
    for (final theme in [AppTheme.light, AppTheme.dark]) {
      await tester.pumpWidget(MaterialApp(
        theme: theme,
        home: const Scaffold(body: Center(child: RideVelaDriverPill())),
      ));
      await tester.pumpAndSettle(); // MaterialApp animates theme changes
      final dark = theme.brightness == Brightness.dark;
      final text = tester.widget<Text>(find.text('Driver'));
      expect(contrast(text.style!.color!, AppColors.softFor(dark)),
          greaterThan(4.5),
          reason: 'dark=$dark');
    }
  });

  testWidgets('ride-type cars use the plan\'s own artwork', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Center(child: VehicleGlyph(tier: 'xl')),
    ));
    final set = VehicleGlyph.artSet(false);
    if (set == null) {
      expect(find.byType(Image), findsNothing);
      expect(find.byType(CustomPaint), findsWidgets);
    } else {
      final img = tester.widget<Image>(find.byType(Image));
      expect((img.image as AssetImage).assetName,
          'packages/design_system/assets/vehicles/$set/xl.png');
    }
  });
}
