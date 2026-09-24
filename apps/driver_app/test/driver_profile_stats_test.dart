import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:driver_app/features/account/driver_profile_stats.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_models/shared_models.dart';

void main() {
  const profile = DriverProfile(
    status: 'offline',
    vehicleMake: 'Maruti',
    vehicleModel: 'Dzire',
    plateNumber: 'MH12AB1234',
    vehicleTier: 'economy',
    docsVerified: true,
  );

  late Market saved;
  setUp(() {
    saved = Market.current;
    Market.current = Market.india;
  });
  tearDown(() => Market.current = saved);

  Future<void> pump(
    WidgetTester tester, {
    double ratingAvg = 4.86,
    int ratingCount = 37,
    Future<DriverProfile> Function()? loadProfile,
    Future<DriverEarnings> Function()? loadWeek,
    ThemeData? theme,
  }) async {
    await tester.pumpWidget(MaterialApp(
      theme: theme ?? AppTheme.light,
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: DriverProfileStats(
            ratingAvg: ratingAvg,
            ratingCount: ratingCount,
            loadProfile: loadProfile ?? () async => profile,
            loadWeek: loadWeek ??
                () async =>
                    const DriverEarnings(total: 1840, trips: 12, range: 'week'),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('shows rating, trips in the last 7 days and the spaced plate',
      (tester) async {
    await pump(tester);
    expect(find.text('4.9'), findsOneWidget);
    expect(find.text('37 ratings'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('Trips, last 7 days'), findsOneWidget);
    expect(find.text('MH 12 AB 1234'), findsOneWidget);
    expect(find.text('Plate'), findsOneWidget);
  });

  testWidgets('a driver with no ratings reads "New", not a fake 5.0',
      (tester) async {
    await pump(tester, ratingAvg: 5, ratingCount: 0, theme: AppTheme.dark);
    expect(find.text('New'), findsOneWidget);
    expect(find.text('No ratings yet'), findsOneWidget);
    expect(find.text('5.0'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed earnings call still shows the plate', (tester) async {
    await pump(
      tester,
      loadWeek: () async => throw const ApiException('offline'),
    );
    expect(find.text('—'), findsOneWidget);
    expect(find.text('MH 12 AB 1234'), findsOneWidget);
  });

  testWidgets('no vehicle yet → "Not added"', (tester) async {
    await pump(
      tester,
      loadProfile: () async => throw const ApiException('Complete onboarding first'),
    );
    expect(find.text('Not added'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
  });
}
