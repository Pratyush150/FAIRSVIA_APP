import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rider_app/features/trip/location_banner.dart';
import 'package:rider_app/features/trip/location_service.dart';

void main() {
  Future<List<LocationBannerAction>> pump(
    WidgetTester tester, {
    LocationIssue? issue,
    bool reduced = false,
  }) async {
    final actions = <LocationBannerAction>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LocationBanner(
            issue: issue,
            reducedAccuracy: reduced,
            onAction: actions.add,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return actions;
  }

  testWidgets('hidden when there is nothing to report', (tester) async {
    await pump(tester);
    expect(find.byType(InkWell), findsNothing);
    expect(find.textContaining('Location'), findsNothing);
  });

  testWidgets('services off: persistent banner, tap opens location settings', (
    tester,
  ) async {
    final actions = await pump(tester, issue: LocationIssue.servicesOff);
    expect(find.text('Location is off — tap to enable'), findsOneWidget);
    await tester.tap(find.text('Location is off — tap to enable'));
    expect(actions, [LocationBannerAction.openLocationSettings]);
  });

  testWidgets('denied forever: tap opens the app settings', (tester) async {
    final actions = await pump(tester, issue: LocationIssue.deniedForever);
    expect(
      find.text('Location access denied — tap to open Settings'),
      findsOneWidget,
    );
    await tester.tap(find.byType(InkWell));
    expect(actions, [LocationBannerAction.openAppSettings]);
  });

  testWidgets('soft denial / error: tap retries the permission flow', (
    tester,
  ) async {
    var actions = await pump(tester, issue: LocationIssue.denied);
    await tester.tap(find.byType(InkWell));
    expect(actions, [LocationBannerAction.retry]);

    actions = await pump(tester, issue: LocationIssue.error);
    expect(
      find.text("Couldn't get your location — tap to retry"),
      findsOneWidget,
    );
    await tester.tap(find.byType(InkWell));
    expect(actions, [LocationBannerAction.retry]);
  });

  testWidgets('precise location off (iOS): Settings hint', (tester) async {
    final actions = await pump(tester, reduced: true);
    expect(
      find.text(
        'Precise Location is off — turn it on in Settings for an '
        'accurate pickup',
      ),
      findsOneWidget,
    );
    await tester.tap(find.byType(InkWell));
    expect(actions, [LocationBannerAction.openAppSettings]);
  });

  testWidgets('a hard issue outranks the precise-location hint', (
    tester,
  ) async {
    await pump(tester, issue: LocationIssue.servicesOff, reduced: true);
    expect(find.text('Location is off — tap to enable'), findsOneWidget);
    expect(find.textContaining('Precise Location'), findsNothing);
  });
}
