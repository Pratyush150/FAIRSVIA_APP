// Home poster carousel: every poster is a photo, names no city, and opens
// the feature it advertises; the Offers poster switches tabs.
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rider_app/features/home/home_posters.dart';
import 'package:rider_app/features/home/rider_bottom_nav.dart';

void main() {
  final cityName = RegExp(
    r'pune|india|maharashtra|mumbai|delhi|tashkent|dubai|riyadh|almaty',
    caseSensitive: false,
  );

  test('posters: photos, unique ids, market-neutral copy', () {
    final posters = homePosters(
      onOffers: () {},
      onSchedule: () {},
      onSafety: () {},
      onRide: () {},
    );
    expect(posters, hasLength(4));
    expect(posters.map((p) => p.id).toSet(), hasLength(4));
    for (final p in posters) {
      expect(p.image, isNotNull, reason: p.id);
      expect(PromoPhoto.posters, contains(p.image));
      expect(cityName.hasMatch('${p.headline} ${p.subline}'), isFalse);
      expect(p.onTap, isNotNull, reason: p.id);
    }
  });

  test('each poster fires its own action', () {
    final hits = <String>[];
    final posters = homePosters(
      onOffers: () => hits.add('offers'),
      onSchedule: () => hits.add('schedule'),
      onSafety: () => hits.add('safety'),
      onRide: () => hits.add('ride'),
    );
    for (final p in posters) {
      p.onTap!();
    }
    expect(hits, ['offers', 'schedule', 'safety', 'ride']);
  });

  testWidgets('the Offers poster opens the Offers tab', (tester) async {
    tester.view.physicalSize = const Size(411, 914);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: RiderTabScaffold(
          showNav: true,
          home: Builder(
            builder: (context) => SingleChildScrollView(
              child: PromoCarousel(
                homePosters(
                  onOffers: () =>
                      RiderTabScaffold.goTo(context, RiderTab.offers),
                  onSchedule: () {},
                  onSafety: () {},
                  onRide: () {},
                ),
                autoAdvance: false,
              ),
            ),
          ),
          pages: {
            RiderTab.trips: (_) => const Text('TRIPS'),
            RiderTab.offers: (_) => const Text('OFFERS'),
            RiderTab.account: (_) => const Text('ACCOUNT'),
          },
        ),
      ),
    );
    expect(find.text('OFFERS'), findsNothing);
    expect(find.text('Your ride offers, in one place'), findsOneWidget);
    await tester.tap(find.byType(PromoBanner).first);
    await tester.pumpAndSettle();
    expect(find.text('OFFERS'), findsOneWidget);
  });
}
