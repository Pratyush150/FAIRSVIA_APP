import 'dart:async';

import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:driver_app/features/incentives/driver_rates.dart';
import 'package:driver_app/features/incentives/quests.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_models/shared_models.dart';

Widget _host(Widget child) => MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Padding(padding: const EdgeInsets.all(16), child: child),
      ),
    );

DriverQuest _quest({
  String id = 'q1',
  int progress = 6,
  int target = 10,
  bool completed = false,
  bool paid = false,
  String status = 'active',
  DateTime? endsAt,
}) =>
    DriverQuest(
      id: id,
      title: 'Morning rush',
      progress: progress,
      target: target,
      bonus: 150,
      currency: 'INR',
      endsAt: endsAt ?? DateTime(2026, 9, 25, 11),
      completed: completed,
      paid: paid,
      status: status,
    );

void main() {
  late Market saved;
  setUp(() {
    saved = Market.current;
    Market.current = Market.india;
    DriverQuestsCard.seenUnfinished.clear();
  });
  tearDown(() => Market.current = saved);

  group('DriverRates', () {
    Future<void> pump(WidgetTester t, DriverStats s) async {
      await t.pumpWidget(_host(DriverRates(load: () async => s)));
      await t.pumpAndSettle();
    }

    testWidgets('neutral when acceptance ≥ 70% and cancellation ≤ 10%',
        (t) async {
      await pump(
        t,
        const DriverStats(
          window: '7d',
          acceptanceRate: 0.92,
          cancellationRate: 0.04,
          offers: 25,
          accepted: 23,
          cancelled: 1,
        ),
      );
      expect(find.text('92%'), findsOneWidget);
      expect(find.text('4%'), findsOneWidget);
      expect(find.byIcon(PhosphorIconsRegular.warning), findsNothing);
      expect(find.textContaining('accepted 23 of 25 offers'), findsOneWidget);
      expect(find.textContaining('no-shows never count'), findsOneWidget);
    });

    testWidgets('amber + icon under 70% acceptance and over 10% cancellation',
        (t) async {
      await pump(
        t,
        const DriverStats(
          window: '7d',
          acceptanceRate: 0.6,
          cancellationRate: 0.2,
          offers: 10,
          accepted: 6,
          cancelled: 1,
        ),
      );
      expect(find.byIcon(PhosphorIconsRegular.warning), findsNWidgets(2));
      final pct = t.widget<Text>(find.text('60%'));
      expect(pct.style?.color, AppColors.warningText);
      expect(find.textContaining('above 70%'), findsOneWidget);
    });

    testWidgets('a new driver sees dashes, not 0%', (t) async {
      await pump(t, const DriverStats(window: '7d'));
      expect(find.text('—'), findsNWidgets(2));
      expect(find.textContaining('No trip offers'), findsOneWidget);
    });
  });

  group('quest copy', () {
    test('"6 of 10 trips · ₹150 bonus · ends 11 AM"', () {
      expect(
        questLine(_quest(), now: DateTime(2026, 9, 25, 8)),
        '6 of 10 trips · ₹150 bonus · ends 11 AM',
      );
    });
    test('paid, midnight and another-day endings', () {
      expect(questLine(_quest(progress: 10, completed: true, paid: true)),
          '10 of 10 trips · ₹150 bonus paid');
      expect(
          questEndsLabel(DateTime(2026, 9, 26), now: DateTime(2026, 9, 25, 9)),
          'midnight');
      expect(
          questEndsLabel(DateTime(2026, 9, 27, 19, 30),
              now: DateTime(2026, 9, 25, 9)),
          '27 Sep, 7:30 PM');
    });
  });

  group('DriverQuestsCard', () {
    testWidgets('shows the running quest with its progress bar', (t) async {
      await t.pumpWidget(_host(DriverQuestsCard(load: () async => [_quest()])));
      await t.pumpAndSettle();
      expect(find.text('Quests'), findsOneWidget);
      expect(find.text('Morning rush'), findsOneWidget);
      final bar = t.widget<LinearProgressIndicator>(
          find.byType(LinearProgressIndicator));
      expect(bar.value, closeTo(0.6, 1e-9));
    });

    testWidgets('hidden when there are no quests', (t) async {
      await t.pumpWidget(_host(DriverQuestsCard(load: () async => [])));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('quests-card')), findsNothing);
    });

    testWidgets('celebrates once on a quest:completed push', (t) async {
      final pushes = StreamController<Map<String, dynamic>>.broadcast();
      var done = false;
      await t.pumpWidget(_host(DriverQuestsCard(
        load: () async => [
          _quest(
              id: 'q-push',
              progress: done ? 10 : 9,
              completed: done,
              paid: done)
        ],
        completions: pushes.stream,
      )));
      await t.pumpAndSettle();
      done = true;
      pushes.add({
        'questId': 'q-push',
        'title': 'Morning rush',
        'bonus': 150,
        'currency': 'INR',
      });
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const Key('quest-celebration')), findsOneWidget);
      expect(find.text('Morning rush complete · ₹150 bonus added'),
          findsOneWidget);
      // The same quest never celebrates twice.
      pushes.add({'questId': 'q-push', 'title': 'Morning rush', 'bonus': 150});
      await t.pump(const Duration(seconds: 5));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('quest-celebration')), findsNothing);
      await pushes.close();
    });

    testWidgets('tapping opens the quests list page', (t) async {
      await t.pumpWidget(_host(DriverQuestsCard(
        load: () async => [
          _quest(),
          _quest(id: 'q2', progress: 3, target: 3, completed: true, paid: true),
        ],
      )));
      await t.pumpAndSettle();
      expect(find.text('+1 more'), findsOneWidget);
      await t.tap(find.byKey(const Key('quests-card')));
      await t.pumpAndSettle();
      expect(find.byType(QuestsPage), findsOneWidget);
      expect(find.byType(QuestTile), findsNWidgets(2));
      expect(find.textContaining('bonus paid'), findsOneWidget);
    });
  });
}
