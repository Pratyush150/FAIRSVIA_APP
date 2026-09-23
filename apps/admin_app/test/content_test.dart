import 'package:admin_app/cubit/admin_cubit.dart';
import 'package:admin_app/data/admin_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockApi extends Mock implements AdminApi {}

AdminRideCard _card({bool active = true, DateTime? startsAt, DateTime? endsAt}) =>
    AdminRideCard(
      id: 'c1',
      title: 'Airport rides',
      body: 'Fixed fares to TAS',
      ctaType: 'none',
      active: active,
      sortOrder: 0,
      startsAt: startsAt,
      endsAt: endsAt,
    );

void main() {
  final now = DateTime(2026, 9, 23, 12);

  group('AdminRideCard.isLiveAt — what riders actually see', () {
    test('active with no window is live', () {
      expect(_card().isLiveAt(now), isTrue);
    });
    test('paused is never live', () {
      expect(_card(active: false).isLiveAt(now), isFalse);
    });
    test('before its start or after its end it is not live', () {
      expect(_card(startsAt: now.add(const Duration(hours: 1))).isLiveAt(now), isFalse);
      expect(_card(endsAt: now.subtract(const Duration(minutes: 1))).isLiveAt(now), isFalse);
      expect(
        _card(
          startsAt: now.subtract(const Duration(hours: 1)),
          endsAt: now.add(const Duration(hours: 1)),
        ).isLiveAt(now),
        isTrue,
      );
    });
  });

  test('saving a card reloads the list from the server', () async {
    final api = _MockApi();
    when(() => api.saveRideCard(any(), id: any(named: 'id'))).thenAnswer((_) async {});
    when(() => api.rideCards()).thenAnswer((_) async => [_card()]);
    final cubit = AdminCubit(api);

    await cubit.saveRideCard({'title': 'Airport rides'});

    verify(() => api.saveRideCard({'title': 'Airport rides'})).called(1);
    expect(cubit.state.rideCards.single.title, 'Airport rides');
    await cubit.close();
  });
}
