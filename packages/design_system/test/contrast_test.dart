import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// Audit 2026-09-25 #16: caution text was #C67C00 at ~3.2:1 and the
/// reconnect / location banners put white on ochre and green.
void main() {
  const aa = 4.5;

  test('the old warning ochre fails as text on white (why the token exists)',
      () {
    expect(contrast(AppColors.warning, Colors.white), lessThan(aa));
  });

  test('warning text passes AA on light surfaces, sheets and its own tint', () {
    for (final bg in [
      Colors.white,
      const Color(0xFFF2F2F2),
      const Color(0xFFEDEDED),
      // The 12% warning tint the dev-code / draft pills sit on.
      Color.alphaBlend(
          AppColors.warning.withValues(alpha: 0.12), Colors.white),
    ]) {
      expect(contrast(AppColors.warningTextFor(false), bg),
          greaterThanOrEqualTo(aa),
          reason: 'on $bg');
    }
  });

  test('warning text passes AA on dark surfaces', () {
    for (final bg in [
      Colors.black,
      const Color(0xFF121212),
      const Color(0xFF1E1F23),
      const Color(0xFF2C3238),
      const Color(0xFF333333),
      Color.alphaBlend(
          AppColors.warning.withValues(alpha: 0.12), const Color(0xFF121212)),
    ]) {
      expect(contrast(AppColors.warningTextFor(true), bg),
          greaterThanOrEqualTo(aa),
          reason: 'on $bg');
    }
  });

  test('banner ink passes AA on its fill', () {
    expect(contrast(AppColors.onWarning, AppColors.warning),
        greaterThanOrEqualTo(aa));
    expect(contrast(Colors.white, AppColors.successBanner),
        greaterThanOrEqualTo(aa));
  });

  testWidgets('warningTextOf follows the theme brightness', (tester) async {
    late Color light, dark;
    await tester.pumpWidget(Theme(
      data: ThemeData(brightness: Brightness.light),
      child: Builder(builder: (c) {
        light = AppColors.warningTextOf(c);
        return const SizedBox();
      }),
    ));
    await tester.pumpWidget(Theme(
      data: ThemeData(brightness: Brightness.dark),
      child: Builder(builder: (c) {
        dark = AppColors.warningTextOf(c);
        return const SizedBox();
      }),
    ));
    expect(light, AppColors.warningText);
    expect(dark, AppColors.warningTextDark);
  });
}
