// Rider Home poster carousel: paging, auto-advance, dots, taps, reduced
// motion, and the poster photos it ships with.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

List<PromoBannerData> _posters(List<String> tapped) => [
  for (final (i, img) in PromoPhoto.posters.indexed)
    PromoBannerData(
      id: 'p$i',
      headline: 'Poster $i',
      image: img,
      onTap: () => tapped.add('p$i'),
    ),
];

Widget _app(Widget child, {bool reduceMotion = false}) => MaterialApp(
  theme: AppTheme.light,
  home: Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
      child: Scaffold(
        body: Align(alignment: Alignment.topCenter, child: child),
      ),
    ),
  ),
);

double _dotWidth(WidgetTester tester, int i) =>
    tester.getSize(find.byKey(ValueKey('promo-dot-$i'))).width -
    6; // minus margins

void main() {
  testWidgets('one 16:10 poster at a time, dots, swipe and tap', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final tapped = <String>[];
    await tester.pumpWidget(
      _app(PromoCarousel(_posters(tapped), autoAdvance: false)),
    );
    final size = tester.getSize(find.byType(PageView));
    expect(size.width, 328);
    expect(size.height, closeTo(328 * 10 / 16, 0.01));
    expect(find.text('Poster 0'), findsOneWidget);
    for (var i = 0; i < PromoPhoto.posters.length; i++) {
      expect(find.byKey(ValueKey('promo-dot-$i')), findsOneWidget);
    }
    expect(_dotWidth(tester, 0), PromoCarousel.dotActiveW);
    expect(_dotWidth(tester, 1), PromoCarousel.dotSize);

    await tester.tap(find.byType(PromoBanner).first);
    expect(tapped, ['p0']);

    await tester.drag(find.byType(PageView), const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(find.text('Poster 1'), findsOneWidget);
    expect(_dotWidth(tester, 1), PromoCarousel.dotActiveW);
    await tester.tap(find.widgetWithText(PromoBanner, 'Poster 1'));
    expect(tapped, ['p0', 'p1']);
  });

  testWidgets('auto-advances every interval and loops to the first', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final posters = _posters([]);
    await tester.pumpWidget(_app(PromoCarousel(posters)));
    for (var i = 1; i <= posters.length; i++) {
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      final want = i % posters.length;
      expect(find.text('Poster $want'), findsOneWidget, reason: 'step $i');
    }
  });

  testWidgets('reduced motion: no auto-advance', (tester) async {
    tester.view.physicalSize = const Size(360, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _app(PromoCarousel(_posters([])), reduceMotion: true),
    );
    await tester.pump(const Duration(seconds: 12));
    await tester.pumpAndSettle();
    expect(find.text('Poster 0'), findsOneWidget);
  });

  testWidgets('a single poster has no dots', (tester) async {
    await tester.pumpWidget(_app(PromoCarousel(_posters([]).sublist(0, 1))));
    expect(find.byKey(const ValueKey('promo-dot-0')), findsNothing);
    expect(find.text('Poster 0'), findsOneWidget);
  });

  test('every poster photo ships: 16:10 webp, ≤120 KB', () async {
    for (final path in PromoPhoto.posters) {
      expect(path, endsWith('.webp'));
      final f = File(path.replaceFirst('packages/design_system/', ''));
      expect(f.existsSync(), isTrue, reason: path);
      final bytes = f.readAsBytesSync();
      expect(bytes.length, lessThanOrEqualTo(120 * 1024), reason: path);
      final codec = await ui.instantiateImageCodec(bytes);
      final img = (await codec.getNextFrame()).image;
      expect(img.width / img.height, closeTo(16 / 10, 0.01), reason: path);
    }
  });
}
