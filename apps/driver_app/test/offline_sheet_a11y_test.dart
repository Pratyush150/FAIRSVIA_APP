import 'package:design_system/design_system.dart';
import 'package:driver_app/features/driver/location_stream.dart';
import 'package:driver_app/home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The driver's offline sheet against the platform accessibility guidelines
/// (audit 4.3): 48 dp targets, labelled tappables, WCAG text contrast in both
/// themes; its headline announced; nothing cut off at 2× text.
void main() {
  Future<void> pump(
    WidgetTester tester, {
    bool dark = false,
    double textScale = 1.0,
    Size size = const Size(411, 914),
    LocationAccess? issue,
    double? lastEarned = 1250,
  }) async {
    tester.view.physicalSize = size * 2.625;
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    AppColors.syncBrightness(dark ? Brightness.dark : Brightness.light);
    addTearDown(() => AppColors.syncBrightness(Brightness.light));
    await tester.pumpWidget(MaterialApp(
      theme: dark ? AppTheme.dark : AppTheme.light,
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: TextScaler.linear(textScale),
        ),
        child: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: AppSheet(
              child: DriverOfflineSheet(
                lastEarned: lastEarned,
                locationIssue: issue,
                onGoOnline: () {},
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 600));
  }

  for (final dark in const [false, true]) {
    for (final issue in const [null, LocationAccess.deniedForever]) {
      testWidgets(
          'meets the guidelines (${dark ? 'dark' : 'light'}, '
          '${issue == null ? 'no location issue' : 'location blocked'})',
          (tester) async {
        final handle = tester.ensureSemantics();
        await pump(tester, dark: dark, issue: issue);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        handle.dispose();
      });
    }
  }

  testWidgets('"You\'re offline" is an announced header', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester);
    expect(
      tester.getSemantics(find.text("You're offline")),
      isSemantics(isLiveRegion: true, isHeader: true),
    );
    handle.dispose();
  });

  for (final size in const [Size(411, 914), Size(360, 640)]) {
    testWidgets('nothing overflows at 2× text on $size', (tester) async {
      await pump(tester,
          textScale: 2.0,
          size: size,
          issue: LocationAccess.deniedForever);
      expect(tester.takeException(), isNull);
    });
  }
}
