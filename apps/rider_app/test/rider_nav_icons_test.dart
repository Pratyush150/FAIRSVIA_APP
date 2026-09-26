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

  testWidgets('every tab is a colourful animated icon of the same size that '
      'plays a couple of times, never loops', (tester) async {
    await tester.pumpWidget(host(RiderTab.home));
    await tester.pumpAndSettle();
    final home = moment(tester, 'nav-home-selected');
    expect(home.asset, 'nav_home');
    for (final k in [
      'nav-home-selected',
      'nav-trips-idle',
      'nav-account-idle',
    ]) {
      final m = moment(tester, k);
      expect(m.tint, isNull, reason: k); // own palette, like the gift
      expect(m.repeat, isFalse, reason: k);
      expect(m.plays, LottieMoment.navPlays, reason: k);
      expect(m.plays, RiderOffersGift.plays, reason: k);
      expect(m.size, LottieMoment.navSize, reason: k);
    }
    expect(home.size, RiderOffersGift.navSize);
    expect(find.byType(LottieMoment), findsNWidgets(4));
    // Unselected tabs are dimmed, the selected one is full colour.
    final idle = tester.widget<Opacity>(
      find
          .ancestor(
            of: find.byKey(const ValueKey('nav-trips-idle')),
            matching: find.byType(Opacity),
          )
          .first,
    );
    expect(idle.opacity, RiderBottomNav.idleOpacity);
    expect(
      find.ancestor(
        of: find.byKey(const ValueKey('nav-home-selected')),
        matching: find.byWidgetPredicate(
          (w) => w is Opacity && w.opacity == RiderBottomNav.idleOpacity,
        ),
      ),
      findsNothing,
    );
  });

  testWidgets('selecting a tab swaps in its selected icon and settles', (
    tester,
  ) async {
    await tester.pumpWidget(host(RiderTab.home));
    await tester.pumpAndSettle();
    await tester.pumpWidget(host(RiderTab.account));
    // The selected account icon pops in: small at first, then settles.
    await tester.pump(const Duration(milliseconds: 20));
    Transform scaleOf() => tester.widget<Transform>(
      find
          .descendant(
            of: find.byKey(const ValueKey('pop-account-selected')),
            matching: find.byType(Transform),
          )
          .at(1),
    );
    expect(scaleOf().transform.entry(0, 0), lessThan(0.9));
    await tester.pumpAndSettle(); // pop and Lottie are one-shots, never loop
    expect(scaleOf().transform.entry(0, 0), closeTo(1.0, 0.001));
    expect(moment(tester, 'nav-account-selected').asset, 'nav_account');
    expect(find.byKey(const ValueKey('nav-home-idle')), findsOneWidget);
  });

  testWidgets('reduce motion still shows every nav icon', (tester) async {
    await tester.pumpWidget(host(RiderTab.trips, reduce: true));
    await tester.pump();
    // No pop under Reduce Motion: already full size on the first frame.
    final t = tester.widget<Transform>(
      find
          .descendant(
            of: find.byKey(const ValueKey('pop-trips-selected')),
            matching: find.byType(Transform),
          )
          .at(1),
    );
    expect(t.transform.entry(0, 0), closeTo(1.0, 0.001));
    await tester.pumpAndSettle();
    expect(find.byType(LottieMoment), findsNWidgets(4));
  });

  test('nav icon files are small, minified and image-free', () {
    for (final n in ['nav_home', 'nav_trips', 'nav_account']) {
      final f = File('../../packages/design_system/assets/lottie/$n.json');
      final s = f.readAsStringSync();
      expect(s.length, lessThan(60 * 1024), reason: n);
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

  testWidgets('render nav frames strip PNG', (tester) async {
    final out = Platform.environment['NAV_FRAMES_PNG'];
    if (out == null) return;
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final keys = List.generate(6, (_) => GlobalKey());
    final rows = <List<ui.Image>>[];
    Widget col() => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 4; i++)
          RepaintBoundary(
            key: keys[i],
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.all(4),
              child: [
                NavPop(child: LottieMoment.navHome()),
                NavPop(slideIn: true, child: LottieMoment.navTrips()),
                const RiderOffersGift(),
                NavPop(child: LottieMoment.navAccount()),
              ][i],
            ),
          ),
      ],
    );
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: col())));
    // Let the Lottie files load (real async) without advancing the pop.
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future.delayed(const Duration(milliseconds: 50)),
      );
    }
    await tester.pump();
    for (var f = 0; f < 6; f++) {
      final row = <ui.Image>[];
      await tester.runAsync(() async {
        for (var i = 0; i < 4; i++) {
          final b =
              keys[i].currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          row.add(await b.toImage(pixelRatio: 3));
        }
      });
      rows.add(row);
      await tester.pump(const Duration(milliseconds: 110));
    }
    await tester.runAsync(() async {
      final rec = ui.PictureRecorder();
      final c = Canvas(rec);
      const cell = 120.0;
      c.drawRect(
        const Rect.fromLTWH(0, 0, cell * 6, cell * 4),
        Paint()..color = Colors.white,
      );
      for (var f = 0; f < 6; f++) {
        for (var i = 0; i < 4; i++) {
          c.drawImage(rows[f][i], Offset(f * cell, i * cell), Paint());
        }
      }
      final img = await rec.endRecording().toImage(
        (cell * 6).toInt(),
        (cell * 4).toInt(),
      );
      final png = await img.toByteData(format: ui.ImageByteFormat.png);
      File(out).writeAsBytesSync(png!.buffer.asUint8List());
    });
  });
}
