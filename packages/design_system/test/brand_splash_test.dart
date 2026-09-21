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
}
