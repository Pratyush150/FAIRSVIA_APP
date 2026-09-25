import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final json = <String, dynamic>{
    'range': 'week',
    'total': 280,
    'trips': 2,
    'onlineSeconds': 7200,
    'cancellationFees': 40,
    'days': [
      for (var i = 19; i <= 25; i++)
        {
          'date': '2026-09-$i',
          'total': i == 25 ? 160 : (i == 22 ? 120 : 0),
          'trips': i == 25 || i == 22 ? 1 : 0,
          'onlineSeconds': i == 25 ? 3600 : 0,
        },
    ],
    'recentTrips': [
      {
        'id': 't1',
        'completedAt': '2026-09-25T10:00:00Z',
        'pickupAddr': 'FC Road',
        'dropoffAddr': 'Pune Airport',
        'distanceM': 8200,
        'tier': 'economy',
        'paymentMode': 'cash',
        'earned': 160,
        'tip': 20,
      },
    ],
  };

  test('parses the dashboard payload, and an older one without the extras', () {
    final e = DriverEarnings.fromJson(json);
    expect(e.total, 280);
    expect(e.onlineSeconds, 7200);
    expect(e.cancellationFees, 40);
    expect(e.days, hasLength(7));
    expect(e.days.last.date, DateTime(2026, 9, 25));
    expect(e.recentTrips.single.paymentMode, 'cash');
    expect(e.recentTrips.single.distanceM, 8200);

    final old = DriverEarnings.fromJson({'range': 'today', 'total': 5, 'trips': 1});
    expect(old.onlineSeconds, isNull);
    expect(old.days, isEmpty);
    expect(old.recentTrips, isEmpty);
  });

  test('per-hour needs at least 10 minutes online', () {
    expect(EarningsDashboard.perHour(100, null), isNull);
    expect(EarningsDashboard.perHour(100, 300), isNull);
    expect(EarningsDashboard.perHour(100, 7200), 50);
    expect(EarningsDashboard.online(30), '0 min');
    expect(EarningsDashboard.online(7500), '2 h 5 min');
  });

  for (final brightness in Brightness.values) {
    testWidgets('renders at 360 dp without overflow (${brightness.name})',
        (tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(MaterialApp(
        theme: brightness == Brightness.dark ? AppTheme.dark : AppTheme.light,
        home: Scaffold(
          body: EarningsDashboard(
            earnings: DriverEarnings.fromJson(json),
            range: 'week',
          ),
        ),
      ));
      expect(tester.takeException(), isNull);
      expect(find.text('Last 7 days'), findsNWidgets(2));
      expect(find.text('2 h'), findsOneWidget); // online
      expect(find.textContaining('FC Road'), findsOneWidget);
      expect(find.textContaining('in cancellation fees'), findsOneWidget);
      // Each bar is a labelled node — the chart's table view.
      expect(find.bySemanticsLabel(RegExp(r'^Today: .*1 trip$')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'^Tuesday: .*1 trip$')), findsOneWidget);
      handle.dispose();
    });
  }

  testWidgets('an empty day says so instead of a blank list', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: EarningsDashboard(
          earnings: DriverEarnings.fromJson({'range': 'today', 'total': 0, 'trips': 0}),
          range: 'today',
        ),
      ),
    ));
    expect(find.textContaining('No trips yet today'), findsOneWidget);
    // No chart without a daily series (older backend).
    expect(find.byType(WeekBars), findsNothing);
  });
}
