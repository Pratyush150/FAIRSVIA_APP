import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rider_app/features/home/home_cards.dart';
import 'package:shared_models/shared_models.dart';

import 'support/fake_map.dart';

/// The Offers page redesign: a photo hero for the first offer, coupon
/// tickets for the rest, a "How offers work" footer, skeleton loading.
///
/// Screenshots: set OFFERS_SHOTS to a directory (only then are PNGs written):
///
///   OFFERS_SHOTS=../../docs/brand/research/offers \
///     flutter test test/offers_page_test.dart
void main() {
  final shots = Platform.environment['OFFERS_SHOTS'];
  setUp(() => Market.current = Market.india);
  tearDown(() => Market.current = Market.unitedStates);

  final now = DateTime.now();
  final welcome = AvailablePromo(
    code: 'WELCOME50',
    title: 'Welcome offer',
    description: 'Half price on a ride — one use per rider.',
    kind: 'percent',
    value: 50,
    maxDiscount: 100,
    expiresAt: now.add(const Duration(days: 3)),
  );
  const airport = AvailablePromo(
    code: 'AIRPORT100',
    title: 'Airport run',
    description: 'Flat off any ride to or from the airport.',
    kind: 'flat',
    value: 100,
    minFare: 400,
    usesLeftForMe: 2,
  );
  final weekend = AvailablePromo(
    code: 'WEEKEND20',
    title: 'Weekend saver',
    kind: 'percent',
    value: 20,
    maxDiscount: 60,
    usesLeftForMe: 4,
    expiresAt: DateTime(now.year + 1, 1, 12),
  );
  final night = AvailablePromo(
    code: 'NIGHTOWL',
    title: 'Late-night rides',
    kind: 'flat',
    value: 75,
    expiresAt: now.add(const Duration(hours: 1)),
  );

  Future<void> pump(
    WidgetTester tester, {
    required Future<List<AvailablePromo>> Function() load,
    String? selected,
    bool dark = false,
    double width = 411,
    double height = 1400,
    double textScale = 1,
    bool reduceMotion = false,
    GlobalKey? boundary,
    bool settle = true,
    void Function(AvailablePromo)? onApply,
  }) async {
    tester.view.physicalSize = Size(width * 3, height * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: dark ? AppTheme.dark : AppTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
              disableAnimations: reduceMotion,
            ),
            child: child!,
          ),
          home: OffersPage(
            load: load,
            selectedCode: selected,
            onApply: onApply ?? (_) {},
            onRemove: () {},
          ),
        ),
      ),
    );
    if (settle) await tester.pumpAndSettle();
  }

  group('offer labels', () {
    final today = DateTime(2026, 9, 25, 10);
    test('countdown within a week, null beyond', () {
      expect(offerCountdownLabel(null, now: today), isNull);
      expect(
        offerCountdownLabel(DateTime(2026, 9, 25, 23), now: today),
        'Ends today',
      );
      expect(
        offerCountdownLabel(DateTime(2026, 9, 26), now: today),
        'Ends tomorrow',
      );
      expect(
        offerCountdownLabel(DateTime(2026, 9, 28), now: today),
        'Ends in 3 days',
      );
      expect(offerCountdownLabel(DateTime(2026, 10, 3), now: today), isNull);
    });

    test('big value and the screen-reader sentence', () {
      expect(offerValueLabel(welcome), '50%');
      expect(offerValueLabel(airport), '₹100');
      expect(
        offerSemanticLabel(
          welcome.copyWithExpiry(DateTime(2026, 10, 3)),
          now: today,
        ),
        '50% off, up to ₹100, code WELCOME50, ends 3 Oct',
      );
      expect(
        offerSemanticLabel(airport, now: today),
        '₹100 off, code AIRPORT100, On fares over ₹400 · 2 uses left',
      );
    });
  });

  testWidgets('hero leads with the first offer; the rest are tickets', (
    tester,
  ) async {
    AvailablePromo? applied;
    await pump(
      tester,
      load: () async => [welcome, airport, weekend],
      onApply: (o) => applied = o,
    );
    expect(find.byType(OfferHero), findsOneWidget);
    expect(find.byType(OfferCard), findsNWidgets(2));
    expect(find.text('Featured'), findsOneWidget);
    expect(find.text('50%'), findsOneWidget);
    expect(find.text('Ends in 3 days'), findsOneWidget);
    expect(find.text('3 offers for your next ride'), findsOneWidget);
    expect(find.text('How offers work'), findsOneWidget);
    // Ticket stub shows the flat value in big type.
    expect(find.text('₹100'), findsOneWidget);
    await tester.tap(find.text('Apply').first);
    expect(applied, airport);
  });

  testWidgets('a ticket expands to its fine print on tap', (tester) async {
    await pump(tester, load: () async => [welcome, airport]);
    expect(find.textContaining('Flat off any ride'), findsNothing);
    await tester.tap(find.text('Airport run'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Flat off any ride'), findsOneWidget);
    expect(
      find.textContaining('One offer per ride. The discount'),
      findsOneWidget,
    );
  });

  testWidgets('applied ticket shows the check stripe instead of Apply', (
    tester,
  ) async {
    await pump(
      tester,
      load: () async => [welcome, airport],
      selected: 'AIRPORT100',
    );
    final card = find.byType(OfferCard);
    expect(
      find.descendant(
        of: card,
        matching: find.text('Applied — will be used on your next ride'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.text('Apply')),
      findsNothing,
    );
    expect(find.text('Apply to next ride'), findsOneWidget); // the hero
  });

  testWidgets('skeleton while loading, then the offers', (tester) async {
    final done = Completer<List<AvailablePromo>>();
    await pump(tester, load: () => done.future, settle: false);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.bySemanticsLabel('Loading offers'), findsOneWidget);
    done.complete([welcome]);
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Loading offers'), findsNothing);
    expect(find.text('Welcome offer'), findsOneWidget);
  });

  testWidgets('pull to refresh reloads', (tester) async {
    var calls = 0;
    await pump(
      tester,
      load: () async {
        calls++;
        return [welcome, airport];
      },
    );
    expect(calls, 1);
    await tester.fling(find.text('Offers'), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();
    expect(calls, 2);
  });

  testWidgets('cards carry a spoken summary', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester, load: () async => [welcome, airport]);
    expect(
      find.bySemanticsLabel(
        RegExp(
          r'^Featured offer: Welcome offer\. 50% off, up to ₹100, '
          r'code WELCOME50, ends in 3 days',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(
        RegExp(r'^Airport run\. ₹100 off, code AIRPORT100'),
      ),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Copy code AIRPORT100'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('360 dp at 1.3× text, light and dark: no overflow', (
    tester,
  ) async {
    for (final dark in [false, true]) {
      await pump(
        tester,
        load: () async => [welcome, airport, weekend, night],
        selected: 'WEEKEND20',
        dark: dark,
        width: 360,
        height: 2400,
        textScale: 1.3,
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('Reduce Motion: content is there without the stagger', (
    tester,
  ) async {
    await pump(
      tester,
      load: () async => [welcome, airport],
      reduceMotion: true,
      settle: false,
    );
    await tester.pump();
    await tester.pump(AppMotion.fast * 2);
    expect(find.text('Airport run'), findsOneWidget);
    await tester.pumpAndSettle();
  });

  group('screenshots', () {
    Future<void> shoot(WidgetTester tester, GlobalKey key, String name) async {
      await tester.runAsync(() async {
        // Decode the photo assets for real so the hero is not blank.
        for (final e in find.byType(Image).evaluate()) {
          final img = e.widget as Image;
          await precacheImage(img.image, e);
        }
      });
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        Directory(shots!).createSync(recursive: true);
        File('$shots/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    }

    final cases = <String, ({bool dark, double w, double scale, String? sel})>{
      'offers_light': (dark: false, w: 411, scale: 1, sel: null),
      'offers_dark': (dark: true, w: 411, scale: 1, sel: null),
      'offers_applied_light': (
        dark: false,
        w: 411,
        scale: 1,
        sel: 'AIRPORT100',
      ),
      'offers_360_text130': (dark: false, w: 360, scale: 1.3, sel: null),
    };
    for (final e in cases.entries) {
      testWidgets(e.key, (tester) async {
        await tester.runAsync(loadTestFonts);
        final key = GlobalKey();
        await pump(
          tester,
          load: () async => [welcome, airport, weekend, night],
          selected: e.value.sel,
          dark: e.value.dark,
          width: e.value.w,
          height: 1500,
          textScale: e.value.scale,
          boundary: key,
        );
        expect(tester.takeException(), isNull);
        await shoot(tester, key, e.key);
      });
    }
  }, skip: shots == null);
}

extension on AvailablePromo {
  AvailablePromo copyWithExpiry(DateTime when) => AvailablePromo(
    code: code,
    title: title,
    description: description,
    kind: kind,
    value: value,
    maxDiscount: maxDiscount,
    minFare: minFare,
    expiresAt: when,
    usesLeftForMe: usesLeftForMe,
  );
}
