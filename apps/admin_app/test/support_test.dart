import 'package:admin_app/cubit/admin_cubit.dart';
import 'package:admin_app/data/admin_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockApi extends Mock implements AdminApi {}

Map<String, dynamic> _ticket(String id, String status) => {
      'id': id,
      'subject': 'Charged twice',
      'category': 'payment',
      'status': status,
      'updatedAt': '2026-09-26T07:00:00.000Z',
      'messages': [
        {'authorRole': 'user', 'body': 'hello', 'createdAt': '2026-09-26T07:00:00.000Z'},
        {'authorRole': 'admin', 'body': 'on it', 'createdAt': '2026-09-26T07:01:00.000Z'},
      ],
    };

void main() {
  test('AdminSupportTicket parses the server thread shape', () {
    final t = AdminSupportTicket.fromJson(_ticket('a', 'active'));
    expect(t.subject, 'Charged twice');
    expect(t.status, 'active');
    expect(t.messages.map((m) => m.authorRole), ['user', 'admin']);
  });

  group('AdminCubit support queue', () {
    late _MockApi api;
    setUp(() {
      api = _MockApi();
      when(() => api.supportTickets(status: any(named: 'status')))
          .thenAnswer((_) async => [AdminSupportTicket.fromJson(_ticket('a', 'open'))]);
    });

    Future<void> settle() => Future<void>.delayed(Duration.zero);

    test('support tab loads the open queue by default; "All" drops the filter',
        () async {
      final cubit = AdminCubit(api);
      cubit.selectTab(AdminTab.support);
      await settle();
      verify(() => api.supportTickets(status: 'open')).called(1);
      expect(cubit.state.tickets.single.id, 'a');

      cubit.setTicketFilter('');
      await settle();
      verify(() => api.supportTickets(status: null)).called(1);
      await cubit.close();
    });

    test('reply and close go to the API and refresh the queue', () async {
      when(() => api.supportReply('a', 'on it')).thenAnswer(
          (_) async => AdminSupportTicket.fromJson(_ticket('a', 'active')));
      when(() => api.supportSetStatus('a', 'closed')).thenAnswer((_) async {});
      final cubit = AdminCubit(api);
      cubit.selectTab(AdminTab.support);
      await settle();

      final replied = await cubit.replyTicket('a', 'on it');
      expect(replied.status, 'active');
      await cubit.setTicketStatus('a', 'closed');
      verify(() => api.supportSetStatus('a', 'closed')).called(1);
      verify(() => api.supportTickets(status: 'open')).called(2);
      await cubit.close();
    });
  });
}
