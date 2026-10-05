import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The launch signature: it shows the wordmark, it is not a loading screen,
/// and it always hands the screen over.
void main() {
  testWidgets('draws the wordmark and no spinner', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: BrandSplash(onDone: () {})),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text(AppBrand.name), findsOneWidget);
    // A progress indicator would make this a loader; it is a signature.
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.pumpAndSettle();
  });

  testWidgets('hands over exactly once, after the full run', (tester) async {
    var done = 0;
    await tester.pumpWidget(
      MaterialApp(home: BrandSplash(onDone: () => done++)),
    );

    // Still on screen partway through.
    await tester.pump(AppBrand.splashFadeIn);
    expect(done, 0);

    await tester.pump(AppBrand.splashTotal);
    expect(done, 1);

    // And it does not fire again.
    await tester.pump(const Duration(seconds: 2));
    expect(done, 1);
    await tester.pumpAndSettle();
  });

  testWidgets('the gate reveals the app once the splash is finished',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: BrandSplashGate(child: Text('home', textDirection: TextDirection.ltr)),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    // The app is built underneath from the first frame (so it is warm), but
    // the splash covers it.
    expect(find.text(AppBrand.name), findsOneWidget);

    await tester.pump(AppBrand.splashTotal);
    await tester.pumpAndSettle();
    expect(find.text(AppBrand.name), findsNothing);
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('the gate can be disabled, for tests that are not about it',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: BrandSplashGate(
          enabled: false,
          child: Text('home', textDirection: TextDirection.ltr),
        ),
      ),
    );
    await tester.pump();
    expect(find.text(AppBrand.name), findsNothing);
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('the driver lockup carries a Driver pill; the rider one does not',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: BrandSplash(onDone: () {}, driver: true)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(FairsviaDriverPill), findsOneWidget);
    expect(find.bySemanticsLabel('FAIRSVIA Driver'), findsOneWidget);
    await tester.pumpAndSettle();

    await tester.pumpWidget(MaterialApp(home: BrandSplash(onDone: () {})));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(FairsviaDriverPill), findsNothing);
    await tester.pumpAndSettle();
  });

  test('the splash hands over within the 2 s cap', () {
    expect(AppBrand.splashTotal.inMilliseconds, lessThanOrEqualTo(2000));
  });

  testWidgets('runs 1.2–2.0 s and fades itself out before handing over',
      (tester) async {
    final total = AppBrand.splashTotal.inMilliseconds;
    expect(total, inInclusiveRange(1200, 2000));
    await tester.pumpWidget(MaterialApp(home: BrandSplash(onDone: () {})));
    await tester.pump(AppBrand.splashFadeIn + AppBrand.splashSettle);
    await tester.pump(const Duration(milliseconds: 250));
    final op = tester.widget<Opacity>(find.byType(Opacity).first);
    expect(op.opacity, lessThan(0.5));
    await tester.pumpAndSettle();
  });

  testWidgets('Reduce Motion: a static lockup, still hands over',
      (tester) async {
    var done = 0;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: MaterialApp(home: BrandSplash(onDone: () => done++)),
      ),
    );
    await tester.pump();
    expect(find.text(AppBrand.name), findsOneWidget);
    expect(tester.hasRunningAnimations, isFalse);
    await tester.pump(AppBrand.splashTotal);
    expect(done, 1);
  });

  testWidgets('the hold frame keeps the lockup (and Driver pill) and loops',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: BrandLaunchHold(driver: true)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text(AppBrand.name), findsOneWidget);
    expect(find.byType(FairsviaDriverPill), findsOneWidget);
    expect(tester.hasRunningAnimations, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('renders in dark theme without errors', (tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: ThemeData.dark(), home: BrandSplash(onDone: () {})),
    );
    await tester.pump(const Duration(milliseconds: 900));
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
  });

  group('FAIRSVIA launch motion (glass build)', () {
    // Collects every CustomPaint painter in the tree (the route painter is
    // private, so it is found by its type name).
    List<String> painters(WidgetTester tester) => tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((c) => c.painter.runtimeType.toString())
        .toList();

    testWidgets('pops the mark, wipes the wordmark, draws the route, hands over',
        (tester) async {
      var done = 0;
      await tester.pumpWidget(
        MaterialApp(home: BrandSplash(onDone: () => done++)),
      );
      expect(painters(tester), contains('_RoutePainter'));
      expect(find.byType(FairsviaMark), findsOneWidget);
      // Mid-way: the wordmark is on screen (one Text, readable), the route is
      // drawing.
      await tester.pump(AppBrand.splashFadeIn + AppBrand.splashSettle ~/ 2);
      expect(find.text(AppBrand.name), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pump(AppBrand.splashTotal);
      expect(done, 1);
    }, skip: !AppColors.glass);

    testWidgets('Reduce Motion: the finished frame, still hands over',
        (tester) async {
      var done = 0;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: MaterialApp(home: BrandSplash(onDone: () => done++)),
        ),
      );
      expect(painters(tester), contains('_RoutePainter'));
      expect(tester.hasRunningAnimations, isFalse);
      await tester.pump(AppBrand.splashTotal);
      expect(done, 1);
    }, skip: !AppColors.glass);

    testWidgets('the hold frame runs a light along the finished route',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(home: BrandLaunchHold()));
      await tester.pump(const Duration(milliseconds: 100));
      expect(painters(tester), contains('_RoutePainter'));
      expect(tester.hasRunningAnimations, isTrue);
      await tester.pumpWidget(const SizedBox());
    }, skip: !AppColors.glass);
  });
}
