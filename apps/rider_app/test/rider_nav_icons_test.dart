import 'dart:io';
import 'dart:ui' as ui;

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rider_app/features/home/rider_bottom_nav.dart';

/// All four rider tabs use animated (Lottie) icons of one size; Home, Trips
/// and Account are tinted with the nav's selected / muted colours.
void main() {
  Widget host(RiderTab tab, {bool reduce = false, bool dark = false}) =>
      MaterialApp(
        theme: dark ? AppTheme.dark : AppTheme.light,
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduce),
          child: Scaffold(
            body: const SizedBox.expand(),
            bottomNavigationBar: RiderBottomNav(current: tab, onSelect: (_) {}),
          ),
        ),
      );

  LottieMoment moment(WidgetTester t, String key) =>
      t.widget<LottieMoment>(find.byKey(ValueKey(key)));

  testWidgets('every tab is an animated icon of the same size, tinted by '
      'the nav colours', (tester) async {
    await tester.pumpWidget(host(RiderTab.home));
    await tester.pumpAndSettle();
    final home = moment(tester, 'nav-home-selected');
    expect(home.asset, 'nav_home');
    expect(home.tint, AppColors.accent);
    expect(home.repeat, isFalse);
    for (final k in ['nav-trips-idle', 'nav-account-idle']) {
      final m = moment(tester, k);
      expect(m.tint, AppColors.iconNeutralFor(false));
      expect(m.repeat, isFalse);
      expect(m.size, LottieMoment.navSize);
    }
    expect(home.size, RiderOffersGift.navSize);
    expect(find.byType(LottieMoment), findsNWidgets(4));
  });

  testWidgets('selecting a tab swaps in its accent-tinted icon and settles', (
    tester,
  ) async {
    await tester.pumpWidget(host(RiderTab.home));
    await tester.pumpAndSettle();
    await tester.pumpWidget(host(RiderTab.account));
    await tester.pumpAndSettle(); // plays once, never loops
    expect(moment(tester, 'nav-account-selected').tint, AppColors.accent);
    expect(find.byKey(const ValueKey('nav-home-idle')), findsOneWidget);
  });

  testWidgets('reduce motion still shows every nav icon', (tester) async {
    await tester.pumpWidget(host(RiderTab.trips, reduce: true));
    await tester.pumpAndSettle();
    expect(find.byType(LottieMoment), findsNWidgets(4));
  });

  test('nav icon files are small, minified and image-free', () {
    for (final n in ['nav_home', 'nav_trips', 'nav_account']) {
      final f = File('../../packages/design_system/assets/lottie/$n.json');
      final s = f.readAsStringSync();
      expect(s.length, lessThan(40 * 1024), reason: n);
      expect(s.contains('\n'), isFalse, reason: n);
      expect(s.contains('data:image'), isFalse, reason: n);
    }
  });

  testWidgets('render nav PNG', (tester) async {
    final out = Platform.environment['NAV_PNG'];
    if (out == null) return;
    await tester.runAsync(() async {
      Future<void> load(String family, List<String> files) async {
        final loader = FontLoader(family);
        for (final f in files) {
          loader.addFont(
            File(
              '../../packages/design_system/fonts/$f',
            ).readAsBytes().then((b) => b.buffer.asByteData()),
          );
        }
        await loader.load();
      }

      await load('packages/design_system/Inter', [
        'Inter-Regular.ttf',
        'Inter-Medium.ttf',
        'Inter-SemiBold.ttf',
      ]);
    });
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    Widget bar(RiderTab t, bool dark) => Theme(
      data: dark ? AppTheme.dark : AppTheme.light,
      child: RiderBottomNav(current: t, onSelect: (_) {}),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: RepaintBoundary(
            key: key,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                bar(RiderTab.home, false),
                bar(RiderTab.trips, false),
                bar(RiderTab.account, true),
              ],
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump(const Duration(seconds: 3));
    }
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final b =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final img = await b.toImage(pixelRatio: 3);
      final png = await img.toByteData(format: ui.ImageByteFormat.png);
      File(out).writeAsBytesSync(png!.buffer.asUint8List());
    });
  });
}
