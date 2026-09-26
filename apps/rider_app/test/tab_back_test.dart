// Android back on the rider's bottom tabs: Trips / Offers / Account go to
// Home first; only Home closes the app. Pages pushed from a tab still pop
// first, and the Home's own back scope (booking flow) keeps working.
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rider_app/features/home/rider_bottom_nav.dart';

void main() {
  // The tab frame sits on a second route above ROOT, so "the app exits"
  // shows up as ROOT becoming visible (the frame's route popped).
  // [homeBusy] stands in for RiderHomeBackScope: while the booking flow is
  // not idle it blocks the pop and steps back instead.
  Future<ValueNotifier<bool>> pump(WidgetTester tester) async {
    final homeBusy = ValueNotifier(false);
    final steps = <String>[];
    addTearDown(homeBusy.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ValueListenableBuilder<bool>(
                      valueListenable: homeBusy,
                      builder: (context, busy, _) => PopScope(
                        canPop: !busy,
                        onPopInvokedWithResult: (didPop, _) {
                          if (didPop) return;
                          if (busy) {
                            steps.add('step');
                            homeBusy.value = false;
                          }
                        },
                        child: RiderTabScaffold(
                          showNav: !busy,
                          home: const Text('HOME'),
                          pages: {
                            RiderTab.trips: (_) => const Text('TRIPS'),
                            RiderTab.offers: (_) => const Text('OFFERS'),
                            RiderTab.account: (ctx) => TextButton(
                              onPressed: () => Navigator.of(ctx).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => const Scaffold(
                                    body: Text('SETTINGS'),
                                  ),
                                ),
                              ),
                              child: const Text('ACCOUNT'),
                            ),
                          },
                        ),
                      ),
                    ),
                  ),
                ),
                child: const Text('ROOT'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('ROOT'));
    await tester.pumpAndSettle();
    return homeBusy;
  }

  RiderTab selected(WidgetTester tester) => tester
      .widget<RiderBottomNav>(find.byType(RiderBottomNav))
      .current;

  Future<void> back(WidgetTester tester) async {
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
  }

  for (final (tab, label, body) in [
    (RiderTab.trips, 'Trips', 'TRIPS'),
    (RiderTab.offers, 'Offers', 'OFFERS'),
    (RiderTab.account, 'Account', 'ACCOUNT'),
  ]) {
    testWidgets('back on $label goes to Home, then back again exits', (
      tester,
    ) async {
      await pump(tester);
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(selected(tester), tab);
      expect(find.text(body), findsOneWidget);

      await back(tester);
      expect(find.byType(RiderTabScaffold), findsOneWidget); // not exited
      expect(selected(tester), RiderTab.home);
      expect(find.text('HOME'), findsOneWidget);

      await back(tester);
      expect(find.byType(RiderTabScaffold), findsNothing); // exited
      expect(find.text('ROOT'), findsOneWidget);
    });
  }

  testWidgets('back on the idle Home exits straight away', (tester) async {
    await pump(tester);
    expect(selected(tester), RiderTab.home);
    await back(tester);
    expect(find.byType(RiderTabScaffold), findsNothing);
    expect(find.text('ROOT'), findsOneWidget);
  });

  testWidgets('a page pushed from Account pops to Account, then Home, then '
      'exits', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ACCOUNT'));
    await tester.pumpAndSettle();
    expect(find.text('SETTINGS'), findsOneWidget);

    await back(tester);
    expect(find.text('SETTINGS'), findsNothing);
    expect(selected(tester), RiderTab.account);
    expect(find.text('ACCOUNT'), findsOneWidget);

    await back(tester);
    expect(selected(tester), RiderTab.home);

    await back(tester);
    expect(find.byType(RiderTabScaffold), findsNothing);
    expect(find.text('ROOT'), findsOneWidget);
  });

  testWidgets('Home booking flow still steps back before the app exits', (
    tester,
  ) async {
    final busy = await pump(tester);
    busy.value = true; // mid-booking: nav hidden, Home's scope blocks
    await tester.pumpAndSettle();
    expect(find.byType(RiderBottomNav), findsNothing);

    await back(tester);
    expect(busy.value, isFalse); // stepped back, not exited
    expect(find.byType(RiderTabScaffold), findsOneWidget);
    expect(selected(tester), RiderTab.home);

    await back(tester);
    expect(find.byType(RiderTabScaffold), findsNothing);
  });

  testWidgets('a ride starting on another tab snaps to Home; back still '
      'steps the flow, never exits', (tester) async {
    final busy = await pump(tester);
    await tester.tap(find.text('Trips'));
    await tester.pumpAndSettle();
    busy.value = true;
    await tester.pumpAndSettle();
    expect(find.text('HOME'), findsOneWidget);
    await back(tester);
    expect(find.byType(RiderTabScaffold), findsOneWidget);
    expect(selected(tester), RiderTab.home);
  });
}
