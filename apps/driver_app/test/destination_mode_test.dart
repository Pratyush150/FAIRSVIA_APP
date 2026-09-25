import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:driver_app/features/driver/destination_mode.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// In-memory stand-in for `/drivers/me/destination-mode`.
class _FakeApi implements DestinationModeRemoteDataSource {
  _FakeApi({this.usesToday = 0});

  int usesToday;
  DestinationPoint? active;
  int sets = 0;
  int clears = 0;

  DestinationModeStatus _view() => DestinationModeStatus(
    active: active != null,
    destination: active,
    usesToday: usesToday,
    usesPerDay: 2,
  );

  @override
  Future<DestinationModeStatus> get() async => _view();

  @override
  Future<DestinationModeStatus> set({
    required double lat,
    required double lng,
    required String label,
    bool saveAsHome = false,
  }) async {
    sets++;
    usesToday++;
    active = DestinationPoint(lat: lat, lng: lng, label: label);
    return _view();
  }

  @override
  Future<DestinationModeStatus> clear() async {
    clears++;
    active = null;
    return _view();
  }
}

Widget _host(Widget child) => MaterialApp(
  theme: AppTheme.light,
  home: Scaffold(
    body: Padding(padding: const EdgeInsets.all(16), child: child),
  ),
);

void main() {
  testWidgets(
    'Destination → pick → chip "Heading to Home · 1 of 2 today" → cancel',
    (tester) async {
      final api = _FakeApi();
      await tester.pumpWidget(
        _host(
          DestinationModeBar(
            api: api,
            onPick: (_) async =>
                const DestinationPick(lat: 41.39, lng: 69.24, label: 'Home'),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Destination'), findsOneWidget);

      await tester.tap(find.text('Destination'));
      await tester.pumpAndSettle();
      expect(api.sets, 1);
      expect(find.text('Heading to Home · 1 of 2 today'), findsOneWidget);

      await tester.tap(find.byTooltip('Cancel destination'));
      await tester.pumpAndSettle();
      expect(api.clears, 1);
      expect(find.text('Destination'), findsOneWidget);
    },
  );

  testWidgets('backing out of the picker sets nothing', (tester) async {
    final api = _FakeApi();
    await tester.pumpWidget(
      _host(DestinationModeBar(api: api, onPick: (_) async => null)),
    );
    await tester.pump();
    await tester.tap(find.text('Destination'));
    await tester.pumpAndSettle();
    expect(api.sets, 0);
    expect(find.text('Destination'), findsOneWidget);
  });

  testWidgets('limit reached: explains instead of opening the picker', (
    tester,
  ) async {
    final api = _FakeApi(usesToday: 2);
    var opened = false;
    await tester.pumpWidget(
      _host(
        DestinationModeBar(
          api: api,
          onPick: (_) async {
            opened = true;
            return null;
          },
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Destination'));
    await tester.pump();
    expect(opened, isFalse);
    expect(find.textContaining('2 times a day'), findsOneWidget);
  });

  test('status parses the backend payload', () {
    final s = DestinationModeStatus.fromJson({
      'active': true,
      'destination': {'lat': 41.39, 'lng': 69.24, 'label': 'Home'},
      'usesToday': 1,
      'usesPerDay': 2,
      'expiresAt': '2026-09-25T15:00:00.000Z',
      'home': null,
      'endedReason': null,
    });
    expect(s.active, isTrue);
    expect(s.destination!.label, 'Home');
    expect(s.expiresAt, isNotNull);
    expect(s.limitReached, isFalse);
  });
}
