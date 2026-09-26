import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:driver_app/features/home_extras/driver_home_extras.dart';
import 'package:driver_app/features/incentives/quests.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DriverQuest _q(String id, String status, {int progress = 2}) => DriverQuest(
      id: id,
      title: 'Daily quest: 10 trips today',
      progress: progress,
      target: 10,
      bonus: 150,
      currency: 'INR',
      endsAt: DateTime(2026, 9, 25, 23),
      completed: false,
      paid: false,
      status: status,
    );

Widget _host(Widget child) => MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  test('ended quest leads with "Ended", never "ends …"', () {
    final line = questLine(_q('a', 'ended'));
    expect(line, 'Ended · 2 of 10 trips');
    expect(line.contains('ends'), isFalse);
  });

  testWidgets('ended quest tile is muted', (tester) async {
    await tester.pumpWidget(_host(QuestTile(quest: _q('a', 'ended'))));
    expect(find.byKey(const Key('quest-ended')), findsOneWidget);
    await tester.pumpWidget(_host(QuestTile(quest: _q('b', 'active'))));
    expect(find.byKey(const Key('quest-ended')), findsNothing);
  });

  testWidgets('home card prefers an active quest over an ended one',
      (tester) async {
    await tester.pumpWidget(_host(DriverQuestsCard(
      load: () async => [_q('e', 'ended'), _q('x', 'active', progress: 4)],
    )));
    await tester.pumpAndSettle();
    expect(find.textContaining('4 of 10 trips'), findsOneWidget);
    expect(find.textContaining('Ended'), findsNothing);
  });

  testWidgets('busy areas lists only hotspots within 5 km', (tester) async {
    await tester.pumpWidget(_host(const DriverBusyAreasSection(
      cells: [
        // ~1.5 km away
        DemandCell(lat: 18.52, lng: 73.86, count: 3, intensity: 0.4),
        // ~9.6 km away, busier — must not be called "nearby"
        DemandCell(lat: 18.596, lng: 73.87, count: 9, intensity: 0.9),
      ],
      from: LatLng(18.51, 73.85),
    )));
    expect(find.text('Busy area'), findsOneWidget);
    expect(find.text('Very busy area'), findsNothing);
  });

  testWidgets('only far hotspots -> "No hotspots right now"', (tester) async {
    await tester.pumpWidget(_host(const DriverBusyAreasSection(
      cells: [DemandCell(lat: 18.596, lng: 73.87, count: 9, intensity: 0.9)],
      from: LatLng(18.51, 73.85),
    )));
    expect(find.text('No hotspots right now'), findsOneWidget);
  });

  testWidgets('driver tip poster bodies are short enough for 2 lines at 360dp',
      (tester) async {
    late List<DriverPoster> posters;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (c) {
      posters = driverTipPosters(c, onQuests: () {});
      return const SizedBox();
    })));
    for (final p in posters) {
      expect(p.body.length, lessThanOrEqualTo(72), reason: p.body);
    }
  });
}
