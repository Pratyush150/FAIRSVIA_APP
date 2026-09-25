// Rider Home building blocks: ServiceTile/ServicesRow, PromoBanner(List),
// ContextCard, BrandFooter.
//
// Review PNGs are opt-in so CI never touches docs/:
//
//   HOME_SHOTS=../../docs/brand/research/home-components \
//       flutter test test/home_components_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _loadFonts() async {
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      loader.addFont(
        File('fonts/$f').readAsBytes().then((b) => b.buffer.asByteData()),
      );
    }
    await loader.load();
  }

  await load('packages/design_system/PhosphorRegular', [
    'Phosphor-Regular.ttf',
  ]);
  await load('packages/design_system/Inter', [
    'Inter-Regular.ttf',
    'Inter-Medium.ttf',
    'Inter-SemiBold.ttf',
    'Inter-Bold.ttf',
    'Inter-ExtraBold.ttf',
  ]);
}

const _services = [
  ServiceItem('Ride', HomeArt.ride, null),
  ServiceItem('Pre-book', HomeArt.prebook, null),
  ServiceItem('Someone else', HomeArt.someoneElse, null, badge: 'New'),
  ServiceItem('Saved', HomeArt.saved, null),
];

Widget _app(
  Widget child, {
  ThemeData? theme,
  double textScale = 1,
  bool reduceMotion = false,
}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: theme ?? AppTheme.light,
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          disableAnimations: reduceMotion,
        ),
        child: Scaffold(body: child),
      ),
    ),
  );
}

/// Everything on one scrolling page, as the Home will stack it.
Widget _page() => ListView(
  padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
  children: [
    ServicesRow(
      items: [
        for (final s in _services)
          ServiceItem(s.label, s.art, () {}, badge: s.badge),
      ],
    ),
    const SizedBox(height: AppSpacing.lg),
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: ContextCard(
        leading: const HomeArtImage(HomeArt.star, size: 40),
        title: 'Rate your ride with Ravi',
        subtitle: 'Tuesday, Koregaon Park to Baner',
        trailing: Icon(PhosphorIconsRegular.caretRight, size: 20),
        onTap: () {},
      ),
    ),
    const SizedBox(height: AppSpacing.lg),
    PromoBannerList([for (final p in kMockPromos) p.copyWith(onTap: () {})]),
    const BrandFooter(),
  ],
);

void main() {
  final out = Platform.environment['HOME_SHOTS'];

  test('every HomeArt key ships a light and a dark render', () {
    for (final k in HomeArt.keys) {
      for (final dark in [false, true]) {
        final rel = HomeArt.path(
          k,
          dark: dark,
        ).replaceFirst('packages/design_system/', '');
        expect(File(rel).existsSync(), isTrue, reason: rel);
      }
    }
  });

  group('ServiceTile', () {
    testWidgets('100×100, label + art, tap, a11y button label', (tester) async {
      var taps = 0;
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _app(
          Center(
            child: ServiceTile(
              label: 'Pre-book',
              art: HomeArt.prebook,
              onTap: () => taps++,
            ),
          ),
        ),
      );
      expect(tester.getSize(find.byType(ServiceTile)), const Size(100, 100));
      expect(find.text('Pre-book'), findsOneWidget);
      expect(find.byType(HomeArtImage), findsOneWidget);
      final data = tester
          .getSemantics(find.byType(ServiceTile))
          .getSemanticsData();
      expect(data.label, 'Pre-book');
      expect(data.flagsCollection.isButton, isTrue);
      expect(data.hasAction(SemanticsAction.tap), isTrue);
      await tester.tap(find.byType(ServiceTile));
      expect(taps, 1);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      handle.dispose();
    });

    testWidgets('badge is shown and spoken', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _app(
          Center(
            child: ServiceTile(
              label: 'Ride',
              art: HomeArt.ride,
              badge: 'New',
              onTap: () {},
            ),
          ),
        ),
      );
      expect(find.text('New'), findsOneWidget);
      expect(find.bySemanticsLabel('Ride, New'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('press scales to 0.96, not under Reduce Motion', (
      tester,
    ) async {
      double scaleNow() => tester
          .widget<AnimatedScale>(
            find.descendant(
              of: find.byType(ServiceTile),
              matching: find.byType(AnimatedScale),
            ),
          )
          .scale;
      for (final reduce in [false, true]) {
        await tester.pumpWidget(
          _app(
            Center(
              child: ServiceTile(
                label: 'Ride',
                art: HomeArt.ride,
                onTap: () {},
              ),
            ),
            reduceMotion: reduce,
          ),
        );
        final g = await tester.startGesture(
          tester.getCenter(find.byType(ServiceTile)),
        );
        await tester.pump();
        expect(scaleNow(), reduce ? 1 : 0.96);
        await g.up();
        await tester.pumpAndSettle();
        expect(scaleNow(), 1);
      }
    });

    testWidgets('grows with text scale instead of clipping', (tester) async {
      await tester.pumpWidget(
        _app(
          const Center(
            child: ServiceTile(label: 'Someone else', art: 'saved'),
          ),
          textScale: 1.3,
        ),
      );
      expect(tester.getSize(find.byType(ServiceTile)).height, greaterThan(100));
      expect(tester.takeException(), isNull);
    });
  });

  group('ServicesRow', () {
    testWidgets('16 dp side padding, 12 dp gaps, scrolls sideways', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_app(const ServicesRow(items: _services)));
      final first = tester.getTopLeft(find.byType(ServiceTile).at(0));
      final second = tester.getTopLeft(find.byType(ServiceTile).at(1));
      expect(first.dx, 16);
      expect(second.dx - first.dx, 100 + 12);
      expect(find.byType(ListView), findsOneWidget);
      expect(
        tester.widget<ListView>(find.byType(ListView)).scrollDirection,
        Axis.horizontal,
      );
    });
  });

  group('PromoBanner', () {
    testWidgets('16:10, headline + subline, CTA 48 dp, one a11y button', (
      tester,
    ) async {
      var taps = 0;
      final handle = tester.ensureSemantics();
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _app(
          Padding(
            padding: const EdgeInsets.all(16),
            child: Align(
              alignment: Alignment.topCenter,
              child: PromoBanner(
                headline: 'Pre-book your airport ride',
                subline: 'Choose your pickup time in advance.',
                art: HomeArt.prebook,
                onTap: () => taps++,
              ),
            ),
          ),
        ),
      );
      final size = tester.getSize(find.byType(PromoBanner));
      expect(size.width, 328);
      expect(size.height, closeTo(328 * 10 / 16, 0.01));
      final cta = find.byIcon(PhosphorIconsRegular.arrowRight);
      expect(cta, findsOneWidget);
      expect(
        tester.getSize(
          find.ancestor(of: cta, matching: find.byType(Container)).first,
        ),
        const Size(48, 48),
      );
      expect(
        find.bySemanticsLabel(
          'Pre-book your airport ride. Choose your pickup time in advance.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.byType(PromoBanner));
      expect(taps, 1);
      handle.dispose();
    });

    testWidgets('PromoBannerList: mocks, 12 dp gaps', (tester) async {
      tester.view.physicalSize = const Size(360, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _app(const SingleChildScrollView(child: PromoBannerList(kMockPromos))),
      );
      expect(find.byType(PromoBanner), findsNWidgets(kMockPromos.length));
      final a = tester.getRect(find.byType(PromoBanner).at(0));
      final b = tester.getRect(find.byType(PromoBanner).at(1));
      expect(b.top - a.bottom, 12);
      expect(kMockPromos.map((p) => p.id).toSet(), hasLength(3));
    });
  });

  group('ContextCard', () {
    testWidgets('title, subtitle, trailing, tap + label', (tester) async {
      var taps = 0;
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _app(
          Padding(
            padding: const EdgeInsets.all(16),
            child: ContextCard(
              leading: const HomeArtImage(HomeArt.star, size: 40),
              title: 'Rate your ride with Ravi',
              subtitle: 'Tuesday trip',
              trailing: const Text('Rate'),
              onTap: () => taps++,
            ),
          ),
        ),
      );
      expect(find.text('Rate your ride with Ravi'), findsOneWidget);
      expect(find.text('Tuesday trip'), findsOneWidget);
      expect(find.text('Rate'), findsOneWidget);
      await tester.tap(find.byType(ContextCard));
      expect(taps, 1);
      expect(
        tester.getSize(find.byType(ContextCard)).height,
        greaterThanOrEqualTo(48),
      );
      handle.dispose();
    });
  });

  group('BrandFooter', () {
    testWidgets('default copy, painter, one semantic node', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_app(const BrandFooter()));
      expect(find.text('#RideVela'), findsOneWidget);
      expect(find.text('Rides, the Pune way'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(BrandFooter),
          matching: find.byWidgetPredicate(
            (w) => w is CustomPaint && w.painter is BrandFooterPainter,
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('#RideVela. Rides, the Pune way'),
        findsOneWidget,
      );
      handle.dispose();
    });
  });

  group('whole stack at 360×640', () {
    for (final dark in [false, true]) {
      for (final scale in [1.0, 1.3]) {
        testWidgets('${dark ? 'dark' : 'light'} @ text ×$scale: no overflow', (
          tester,
        ) async {
          tester.view.physicalSize = const Size(360, 640);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(
            _app(
              _page(),
              theme: dark ? AppTheme.dark : AppTheme.light,
              textScale: scale,
            ),
          );
          // Scroll through the page so every piece lays out.
          for (var i = 0; i < 8; i++) {
            await tester.drag(
              find.byType(ListView).last,
              const Offset(0, -300),
            );
            await tester.pump();
          }
          expect(tester.takeException(), isNull);
          expect(find.byType(BrandFooter), findsOneWidget);
        });
      }
    }
  });

  testWidgets('shots: home components board', (tester) async {
    await tester.runAsync(_loadFonts);
    tester.view.physicalSize = const Size(360 * 2 + 24, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final keys = <String, GlobalKey>{};
    Widget panel(String id, ThemeData theme, double scale) {
      final key = keys[id] = GlobalKey();
      final dark = theme.brightness == Brightness.dark;
      return RepaintBoundary(
        key: key,
        child: SizedBox(
          width: 360,
          height: 1500,
          child: Theme(
            data: theme,
            child: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: ColoredBox(
                  color: dark
                      ? AppColors.backgroundDark
                      : AppColors.backgroundLight,
                  child: DefaultTextStyle(
                    style: theme.textTheme.bodyLarge!,
                    child: Material(
                      type: MaterialType.transparency,
                      child: _page(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    for (final scale in [1.0, 1.3]) {
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              panel('light', AppTheme.light, scale),
              const SizedBox(width: 24),
              panel('dark', AppTheme.dark, scale),
            ],
          ),
        ),
      );
      // Let the asset images decode.
      await tester.runAsync(() async {
        for (final e in find.byType(Image).evaluate()) {
          final img = e.widget as Image;
          await precacheImage(img.image, e);
        }
      });
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      if (out == null) continue;
      await tester.runAsync(() async {
        Directory(out).createSync(recursive: true);
        for (final e in keys.entries) {
          final boundary =
              e.value.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          File(
            '$out/home-${e.key}${scale == 1 ? '' : '-x1.3'}.png',
          ).writeAsBytesSync(bytes!.buffer.asUint8List());
        }
      });
    }
  });
}
