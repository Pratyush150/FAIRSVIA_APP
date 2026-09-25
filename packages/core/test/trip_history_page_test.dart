import 'dart:io';
import 'dart:ui' as ui;

import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_models/shared_models.dart';

class MockTrips extends Mock implements TripRemoteDataSource {}

class MockPayments extends Mock implements PaymentsRemoteDataSource {}

/// The pinned "now" the day headings are measured against.
final _now = DateTime(2026, 9, 25, 20, 0);

Trip _trip({
  required String id,
  required TripStatus status,
  double? fareEstimate,
  double? fareFinal,
  String? driverName,
  String? vehicle,
  String? plate,
  String? riderName,
  String dropoff = 'B',
  String tier = 'economy',
  String currency = 'USD',
  DateTime? at,
  int? myRating,
  bool hasMyRating = false,
  int? distanceM,
  int? durationS,
}) =>
    Trip(
      id: id,
      status: status,
      tier: tier,
      pickup: const TripEndpoint(point: GeoPoint(25.77, -80.19), address: 'A'),
      dropoff: TripEndpoint(point: const GeoPoint(25.79, -80.19), address: dropoff),
      fareEstimate: fareEstimate,
      fareFinal: fareFinal,
      currency: currency,
      requestedAt: at ?? DateTime(2026, 9, 10, 19, 44),
      completedAt: status == TripStatus.completed ? at : null,
      driverName: driverName,
      driverVehicleLabel: vehicle,
      driverPlate: plate,
      riderName: riderName,
      myRating: myRating,
      hasMyRatingField: hasMyRating,
      distanceM: distanceM,
      durationS: durationS,
    );

Future<void> _show(
  WidgetTester tester,
  List<Trip> list, {
  bool isDriver = false,
  RateTrip? onRate,
  VoidCallback? onBookRide,
  ThemeData? theme,
}) async {
  final trips = MockTrips();
  when(() => trips.history()).thenAnswer((_) async => list);
  await tester.pumpWidget(MaterialApp(
    theme: theme,
    home: TripHistoryPage(
      trips: trips,
      payments: MockPayments(),
      isDriver: isDriver,
      onRate: onRate,
      onBookRide: onBookRide,
      now: () => _now,
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('cancelled trips do not show the (uncharged) estimate',
      (tester) async {
    await _show(tester, [
      _trip(
        id: 'done',
        status: TripStatus.completed,
        fareEstimate: 8.73,
        fareFinal: 6.50,
      ),
      _trip(id: 'gone', status: TripStatus.cancelled, fareEstimate: 7.61),
      _trip(
        id: 'fee',
        status: TripStatus.cancelled,
        fareEstimate: 7.61,
        fareFinal: 2.00,
      ),
    ]);

    expect(find.text('\$6.50'), findsOneWidget);
    expect(find.text('\$7.61'), findsNothing);
    expect(find.text('\$2'), findsOneWidget);
  });

  testWidgets('groups by day, newest first: Today, Yesterday, then a date',
      (tester) async {
    await _show(tester, [
      _trip(
          id: 'old',
          status: TripStatus.completed,
          dropoff: 'Old Town',
          at: DateTime(2026, 9, 22, 9, 5)),
      _trip(
          id: 'today',
          status: TripStatus.completed,
          dropoff: 'Pune Railway Station, Agarkar Nagar, Pune',
          at: DateTime(2026, 9, 25, 18, 42)),
      _trip(
          id: 'yday',
          status: TripStatus.completed,
          dropoff: 'Airport',
          at: DateTime(2026, 9, 24, 8, 0)),
    ]);

    final today = tester.getTopLeft(find.text('Today')).dy;
    final yday = tester.getTopLeft(find.text('Yesterday')).dy;
    final older = tester.getTopLeft(find.text('Tue, 22 Sep')).dy;
    expect(today < yday && yday < older, isTrue);
    // The destination is the address's first part, on one line.
    expect(find.text('Pune Railway Station'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Pune Railway Station')).dy,
        allOf(greaterThan(today), lessThan(yday)));
    expect(find.text('6:42 PM'), findsOneWidget);
  });

  testWidgets('no tick or cross icons; a chip only for rides that did not complete',
      (tester) async {
    await _show(tester, [
      _trip(id: 'done', status: TripStatus.completed, fareFinal: 6.5),
      _trip(id: 'gone', status: TripStatus.cancelled),
      _trip(id: 'none', status: TripStatus.noDrivers),
      _trip(id: 'pay', status: TripStatus.paymentFailed, fareFinal: 9),
    ]);

    expect(find.byIcon(PhosphorIconsRegular.check), findsNothing);
    expect(find.byIcon(PhosphorIconsRegular.x), findsNothing);
    expect(find.byType(AppStatusChip), findsNWidgets(3));
    expect(find.widgetWithText(AppStatusChip, 'Cancelled'), findsOneWidget);
    expect(find.widgetWithText(AppStatusChip, 'No drivers'), findsOneWidget);
    expect(find.widgetWithText(AppStatusChip, 'Completed'), findsNothing);
    final pay = tester.widget<AppStatusChip>(
        find.widgetWithText(AppStatusChip, 'Payment failed'));
    expect(pay.tone, StatusTone.warning);
    expect(find.byType(VehicleGlyph), findsNWidgets(4));
  });

  testWidgets('filter pills narrow the list', (tester) async {
    await _show(tester, [
      _trip(id: 'done', status: TripStatus.completed, dropoff: 'Mall'),
      _trip(id: 'gone', status: TripStatus.cancelled, dropoff: 'Park'),
    ]);
    expect(find.text('Mall'), findsOneWidget);
    expect(find.text('Park'), findsOneWidget);

    await tester.tap(find.text('Cancelled').first);
    await tester.pumpAndSettle();
    expect(find.text('Mall'), findsNothing);
    expect(find.text('Park'), findsOneWidget);

    await tester.tap(find.text('Completed'));
    await tester.pumpAndSettle();
    expect(find.text('Mall'), findsOneWidget);
    expect(find.text('Park'), findsNothing);
  });

  testWidgets('rider rows: who drove, the car and plate; rated shows the stars',
      (tester) async {
    await _show(tester, [
      _trip(
        id: 'done',
        status: TripStatus.completed,
        fareFinal: 6.50,
        driverName: 'Aziz Karimov',
        vehicle: 'White Chevrolet Cobalt',
        plate: 'AB1234',
        myRating: 5,
        hasMyRating: true,
      ),
      _trip(id: 'gone', status: TripStatus.cancelled),
    ]);

    expect(find.textContaining('with Aziz · White Chevrolet Cobalt'),
        findsOneWidget);
    expect(find.textContaining('with '), findsOneWidget);
    expect(find.byIcon(PhosphorIconsFill.star), findsOneWidget);
    expect(find.text('Rate'), findsNothing);
  });

  testWidgets('an unrated completed trip offers Rate; rating updates the row',
      (tester) async {
    Trip? asked;
    await _show(
      tester,
      [
        _trip(
            id: 'done',
            status: TripStatus.completed,
            fareFinal: 6.5,
            hasMyRating: true),
        _trip(id: 'gone', status: TripStatus.cancelled, hasMyRating: true),
      ],
      onRate: (context, trip) async {
        asked = trip;
        return 4;
      },
    );

    expect(find.text('Rate'), findsOneWidget);
    await tester.tap(find.text('Rate'));
    await tester.pumpAndSettle();
    expect(asked?.id, 'done');
    expect(find.text('Rate'), findsNothing);
    expect(find.text('4'), findsOneWidget);
  });

  testWidgets('no Rate button without a rating handler', (tester) async {
    await _show(tester, [
      _trip(id: 'done', status: TripStatus.completed, hasMyRating: true),
    ]);
    expect(find.text('Rate'), findsNothing);
  });

  testWidgets("driver view names the rider, never the driver's car or a phone",
      (tester) async {
    await _show(
      tester,
      [
        _trip(
          id: 'done',
          status: TripStatus.completed,
          fareFinal: 6.5,
          riderName: 'Priya Sharma',
        ),
      ],
      isDriver: true,
      onBookRide: () {},
    );
    expect(find.text('with Priya'), findsOneWidget);
    expect(find.textContaining('+'), findsNothing);
  });

  testWidgets('each row reads as one sentence', (tester) async {
    final handle = tester.ensureSemantics();
    await _show(tester, [
      _trip(
        id: 'done',
        status: TripStatus.completed,
        fareFinal: 6.5,
        dropoff: 'Airport, Terminal 2',
        at: DateTime(2026, 9, 25, 18, 42),
      ),
    ]);
    expect(
      find.bySemanticsLabel(
          RegExp(r'^Trip to Airport, 6:42 PM, \$6\.50, completed')),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('empty: calm art, "No trips yet" and Book a ride',
      (tester) async {
    var booked = false;
    await _show(tester, const [], onBookRide: () => booked = true);
    expect(find.text('No trips yet'), findsOneWidget);
    expect(find.byType(LottieMoment), findsOneWidget);
    expect(tester.widget<LottieMoment>(find.byType(LottieMoment)).asset,
        'empty_box');
    await tester.tap(find.text('Book a ride'));
    expect(booked, isTrue);
  });

  testWidgets('driver empty state has no Book a ride', (tester) async {
    await _show(tester, const [], isDriver: true, onBookRide: () {});
    expect(find.text('No trips yet'), findsOneWidget);
    expect(find.text('Book a ride'), findsNothing);
  });

  testWidgets('360 dp wide at 1.3x text: no overflow', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final trips = MockTrips();
    when(() => trips.history()).thenAnswer((_) async => _sample);
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(1.3)),
        child: child!,
      ),
      home: TripHistoryPage(
        trips: trips,
        payments: MockPayments(),
        onRate: (_, _) async => null,
        now: () => _now,
      ),
    ));
    await tester.pumpAndSettle();
    final errors = <Object>[];
    Object? e;
    while ((e = tester.takeException()) != null) {
      errors.add(e!);
    }
    expect(errors, isEmpty);
  });

  _screenshots();
}

final _sample = [
  _trip(
    id: '1',
    status: TripStatus.completed,
    fareFinal: 75,
    currency: 'INR',
    dropoff: 'Pune Railway Station, Agarkar Nagar, Pune',
    at: DateTime(2026, 9, 25, 18, 42),
    driverName: 'Priya Sharma',
    vehicle: 'White Maruti Dzire',
    plate: 'MH12AB1234',
    hasMyRating: true,
    distanceM: 4200,
    durationS: 840,
  ),
  _trip(
    id: '2',
    status: TripStatus.cancelled,
    currency: 'INR',
    dropoff: 'Phoenix Marketcity, Viman Nagar',
    at: DateTime(2026, 9, 25, 9, 10),
  ),
  _trip(
    id: '3',
    status: TripStatus.completed,
    tier: 'auto',
    fareFinal: 48,
    currency: 'INR',
    dropoff: 'FC Road, Shivajinagar',
    at: DateTime(2026, 9, 24, 21, 5),
    driverName: 'Ramesh Patil',
    vehicle: 'Bajaj RE',
    plate: 'MH12QX4471',
    myRating: 5,
    hasMyRating: true,
    distanceM: 2600,
    durationS: 660,
  ),
  _trip(
    id: '4',
    status: TripStatus.paymentFailed,
    tier: 'comfort',
    fareFinal: 212,
    currency: 'INR',
    dropoff: 'Pune International Airport, Lohegaon',
    at: DateTime(2026, 9, 22, 6, 15),
    driverName: 'Sanjay Kulkarni',
    vehicle: 'Grey Hyundai Verna',
    plate: 'MH14DE9087',
    hasMyRating: true,
  ),
  _trip(
    id: '5',
    status: TripStatus.noDrivers,
    tier: 'xl',
    currency: 'INR',
    dropoff: 'Hinjewadi Phase 1',
    at: DateTime(2026, 9, 22, 5, 50),
  ),
  _trip(
    id: '6',
    status: TripStatus.completed,
    tier: 'bike',
    fareFinal: 36,
    currency: 'INR',
    dropoff: 'Koregaon Park Lane 5',
    at: DateTime(2026, 9, 20, 13, 30),
    driverName: 'Imran Shaikh',
    vehicle: 'Honda Activa',
    myRating: 4,
    hasMyRating: true,
  ),
];

/// TRIPS_SHOTS names a directory; only then are PNGs written:
///
///   TRIPS_SHOTS=../../docs/brand/research/trips \
///     flutter test --dart-define=THEME=glass test/trip_history_page_test.dart
void _screenshots() {
  final shots = Platform.environment['TRIPS_SHOTS'];
  if (shots == null) return;

  setUpAll(_loadFonts);

  Future<void> shoot(WidgetTester tester, String name,
      {required bool dark, required List<Trip> list, double scale = 1,
      bool driver = false, Widget? home, double height = 800}) async {
    tester.view.physicalSize = Size(360, height) * 2.625;
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    AppColors.syncBrightness(dark ? Brightness.dark : Brightness.light);
    addTearDown(() => AppColors.syncBrightness(Brightness.light));
    final trips = MockTrips();
    when(() => trips.history()).thenAnswer((_) async => list);
    final key = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(
      key: key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: dark ? AppTheme.dark : AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: home ?? TripHistoryPage(
          trips: trips,
          payments: MockPayments(),
          isDriver: driver,
          onRate: (_, _) async => null,
          onBookRide: () {},
          now: () => _now,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    // Decode the car / clay art for real, then repaint.
    await tester.runAsync(() async {
      final ctx = key.currentContext!;
      for (final e in find.byType(Image).evaluate()) {
        await precacheImage((e.widget as Image).image, ctx);
      }
    });
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      Directory(shots).createSync(recursive: true);
      File('$shots/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  }

  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';
    testWidgets('shot trips list $mode', (tester) async {
      await shoot(tester, 'trips-$mode', dark: dark, list: _sample);
    });
    testWidgets('shot trips empty $mode', (tester) async {
      await shoot(tester, 'trips-empty-$mode', dark: dark, list: const []);
    });
  }
  for (final dark in [false, true]) {
    testWidgets('shot receipt ${dark ? 'dark' : 'light'}', (tester) async {
      final payments = MockPayments();
      when(() => payments.receipt('1')).thenAnswer((_) async => const Receipt(
            tripId: '1',
            fare: 75,
            currency: 'INR',
            tip: 10,
            method: 'card',
            cardLabel: 'Visa •4242',
            status: 'succeeded',
            breakdown: FareBreakdown(
              baseFare: 30,
              distanceFare: 35,
              timeFare: 7,
              bookingFee: 3,
            ),
          ));
      await shoot(tester, 'yourtrip_${dark ? 'dark' : 'light'}',
          dark: dark,
          list: const [],
          height: 1320,
          home: ReceiptPage(
            payments: payments,
            onGetHelp: () {},
            trip: Trip(
              id: '1',
              status: TripStatus.completed,
              tier: 'economy',
              pickup: const TripEndpoint(
                  point: GeoPoint(18.52, 73.85),
                  address: 'Shivajinagar, Pune'),
              dropoff: const TripEndpoint(
                  point: GeoPoint(18.53, 73.87),
                  address: 'Pune Railway Station, Agarkar Nagar, Pune'),
              fareFinal: 75,
              currency: 'INR',
              completedAt: DateTime(2026, 9, 24, 18, 42),
              distanceM: 4200,
              durationS: 840,
              driverName: 'Priya Sharma',
              driverVehicleLabel: 'White Maruti Dzire',
              driverPlate: 'MH12AB1234',
              myRating: 5,
              hasMyRatingField: true,
            ),
          ));
    });
  }
  testWidgets('shot trips 1.3x', (tester) async {
    await shoot(tester, 'trips-light-1.3x',
        dark: false, list: _sample, scale: 1.3);
  });
  testWidgets('shot trips driver', (tester) async {
    await shoot(tester, 'trips-driver-light', dark: false, driver: true, list: [
      for (final t in _sample.take(3))
        _trip(
          id: t.id,
          status: t.status,
          tier: t.tier,
          fareFinal: t.fareFinal,
          currency: 'INR',
          dropoff: t.dropoff.address!,
          at: t.requestedAt,
          riderName: 'Ananya Rao',
        ),
    ]);
  });
}

final String _flutterRoot =
    Platform.environment['FLUTTER_ROOT'] ??
    File(Platform.resolvedExecutable).parent.parent.parent.parent.parent.path;

Future<void> _loadFonts() async {
  final fonts = Directory(
    '${Directory.current.path}/../design_system/fonts',
  ).resolveSymbolicLinksSync();
  Future<void> load(String family, List<String> paths) async {
    final loader = FontLoader(family);
    for (final p in paths) {
      loader.addFont(File(p).readAsBytes().then((b) => b.buffer.asByteData()));
    }
    await loader.load();
  }

  await load('MaterialIcons', [
    '$_flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  ]);
  await load('packages/design_system/PhosphorRegular', [
    '$fonts/Phosphor-Regular.ttf',
  ]);
  await load('packages/design_system/PhosphorFill', [
    '$fonts/Phosphor-Fill.ttf',
  ]);
  await load('packages/design_system/Inter', [
    '$fonts/Inter-Regular.ttf',
    '$fonts/Inter-Medium.ttf',
    '$fonts/Inter-SemiBold.ttf',
    '$fonts/Inter-Bold.ttf',
    '$fonts/Inter-ExtraBold.ttf',
  ]);
}
