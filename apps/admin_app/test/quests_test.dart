import 'package:admin_app/quests/quests_api.dart';
import 'package:admin_app/quests/quests_view.dart';
import 'package:design_system/design_system.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeApi extends QuestsApi {
  _FakeApi() : super(Dio());
  final created = <Map<String, dynamic>>[];
  final updates = <String, Map<String, dynamic>>{};
  final rows = <AdminQuest>[
    AdminQuest.fromJson({
      'id': 'q1',
      'title': 'Morning rush',
      'tiers': <String>[],
      'targetTrips': 10,
      'startsAt': '2026-09-25T01:30:00.000Z',
      'endsAt': '2026-09-25T05:30:00.000Z',
      'bonusAmount': '150',
      'currency': 'INR',
      'active': true,
      'awards': 3,
    }),
  ];

  @override
  Future<List<AdminQuest>> list() async => rows;
  @override
  Future<void> create(Map<String, dynamic> body) async => created.add(body);
  @override
  Future<void> update(String id, Map<String, dynamic> body) async =>
      updates[id] = body;
}

void main() {
  test('AdminQuest parses the API row (Decimal bonus as string)', () {
    final q = _FakeApi().rows.first;
    expect(q.bonusAmount, 150);
    expect(q.tiers, isEmpty);
    expect(q.awards, 3);
  });

  testWidgets('lists quests, toggles active, and creates one', (t) async {
    t.view.physicalSize = const Size(1400, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final api = _FakeApi();
    await t.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: QuestsView(api: api)),
    ));
    await t.pumpAndSettle();
    expect(find.text('Morning rush'), findsOneWidget);
    expect(find.textContaining('10 trips'), findsOneWidget);
    expect(find.textContaining('3 paid'), findsOneWidget);

    await t.tap(find.byType(Switch));
    await t.pumpAndSettle();
    expect(api.updates['q1'], {'active': false});

    await t.tap(find.byKey(const Key('new-quest')));
    await t.pumpAndSettle();
    // Validation: a title is required.
    await t.tap(find.byKey(const Key('quest-create')));
    await t.pumpAndSettle();
    expect(find.textContaining('Enter a title'), findsOneWidget);
    await t.enterText(find.byKey(const Key('quest-title')), 'Evening peak');
    await t.enterText(find.byKey(const Key('quest-target')), '5');
    await t.enterText(find.byKey(const Key('quest-bonus')), '80');
    await t.tap(find.text('xl'));
    await t.pump();
    await t.tap(find.byKey(const Key('quest-create')));
    await t.pumpAndSettle();
    expect(api.created, hasLength(1));
    expect(api.created.first, containsPair('title', 'Evening peak'));
    expect(api.created.first, containsPair('targetTrips', 5));
    expect(api.created.first, containsPair('bonusAmount', 80.0));
    expect(api.created.first['tiers'], ['xl']);
    expect(
      DateTime.parse(api.created.first['endsAt'] as String)
          .isAfter(DateTime.parse(api.created.first['startsAt'] as String)),
      isTrue,
    );
  });
}
