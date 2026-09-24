import 'package:design_system/design_system.dart';
import 'package:driver_app/features/driver/location_priming_page.dart';
import 'package:driver_app/features/driver/location_stream.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // A phone-sized screen (the default test surface is 800×600 landscape).
  setUp(() {
    final view = TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(1080, 2340);
    view.devicePixelRatio = 2.75;
  });
  tearDown(() {
    final view = TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  late int requests;
  late List<LocationAccess> opened;
  late Object? popped;

  Future<void> pump(
    WidgetTester tester, {
    required LocationAccess answer,
    ThemeData? theme,
  }) async {
    requests = 0;
    opened = [];
    popped = 'not popped';
    await tester.pumpWidget(MaterialApp(
      theme: theme ?? AppTheme.light,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async {
                popped = await Navigator.of(context).push<LocationAccess?>(
                  MaterialPageRoute<LocationAccess?>(
                    builder: (_) => LocationPrimingPage(
                      request: () async {
                        requests++;
                        return answer;
                      },
                      recheck: () async => answer,
                      openFix: (a) async {
                        opened.add(a);
                        return true;
                      },
                    ),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('explains why before the OS dialog is requested',
      (tester) async {
    await pump(tester, answer: LocationAccess.granted);

    expect(find.text('Allow location to get ride offers'), findsOneWidget);
    expect(find.text('Ride offers near you'), findsOneWidget);
    expect(
      find.text('Only while you are online', skipOffstage: false),
      findsOneWidget,
    );
    // Nothing has been asked of the OS yet.
    expect(requests, 0);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(requests, 1);
    // Granted: the screen closes and reports it.
    expect(find.byType(LocationPrimingPage), findsNothing);
    expect(popped, LocationAccess.granted);
  });

  testWidgets('"Not now" leaves without asking the OS', (tester) async {
    await pump(tester, answer: LocationAccess.granted);
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(requests, 0);
    expect(popped, isNull);
  });

  testWidgets('denied → banner with Open Settings (app settings)',
      (tester) async {
    await pump(tester, answer: LocationAccess.denied);
    expect(find.byType(LocationAccessBanner), findsNothing);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.byType(LocationPrimingPage), findsOneWidget);
    expect(find.byType(LocationAccessBanner), findsOneWidget);
    expect(find.text('Location is not allowed for RideVela'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);

    await tester.tap(find.text('Open Settings'));
    await tester.pump();
    expect(opened, [LocationAccess.denied]);
  });

  testWidgets('denied forever → banner says the phone will not ask again',
      (tester) async {
    await pump(tester, answer: LocationAccess.deniedForever);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.textContaining('will not ask again'), findsOneWidget);
    await tester.tap(find.text('Open Settings'));
    await tester.pump();
    expect(opened, [LocationAccess.deniedForever]);

    // Leaving now reports the refusal so the home sheet keeps the banner.
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(popped, LocationAccess.deniedForever);
  });

  testWidgets('back from Settings with access granted closes the screen',
      (tester) async {
    var answer = LocationAccess.denied;
    requests = 0;
    popped = 'not popped';
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            popped = await Navigator.of(context).push<LocationAccess?>(
              MaterialPageRoute<LocationAccess?>(
                builder: (_) => LocationPrimingPage(
                  request: () async => answer,
                  recheck: () async => answer,
                  openFix: (_) async => true,
                ),
              ),
            );
          },
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.byType(LocationAccessBanner), findsOneWidget);

    answer = LocationAccess.granted; // fixed in Settings
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.byType(LocationPrimingPage), findsNothing);
    expect(popped, LocationAccess.granted);
  });

  testWidgets('location services off → banner opens location settings',
      (tester) async {
    await pump(tester, answer: LocationAccess.servicesOff, theme: AppTheme.dark);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Location is turned off on this phone'), findsOneWidget);
    await tester.tap(find.text('Open Settings'));
    await tester.pump();
    expect(opened, [LocationAccess.servicesOff]);
    expect(tester.takeException(), isNull);
  });
}
