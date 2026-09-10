import 'package:bloc_test/bloc_test.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_models/shared_models.dart';

class MockAuthBloc extends MockBloc<AuthEvent, AuthState> implements AuthBloc {}

class MockUsers extends Mock implements UsersRemoteDataSource {}

void main() {
  const before = AppUser(id: 'u1', phone: '+19876543210', role: 'rider');
  const after = AppUser(
    id: 'u1',
    phone: '+19876543210',
    role: 'rider',
    fullName: 'Ada Lovelace',
    email: 'ada@example.com',
  );

  late MockAuthBloc auth;
  late MockUsers users;

  setUp(() {
    auth = MockAuthBloc();
    whenListen(
      auth,
      const Stream<AuthState>.empty(),
      initialState:
          const AuthState(status: AuthStatus.authenticated, user: before),
    );
    users = MockUsers();
    sl.registerSingleton<UsersRemoteDataSource>(users);
  });

  tearDown(() async {
    await sl.reset();
  });

  testWidgets('a saved profile edit updates the header and AuthBloc',
      (tester) async {
    when(() => users.updateMe(
          fullName: any(named: 'fullName'),
          email: any(named: 'email'),
        )).thenAnswer((_) async => after);

    await tester.pumpWidget(
      BlocProvider<AuthBloc>.value(
        value: auth,
        child: const MaterialApp(home: AccountMenuPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Add your name'), findsOneWidget);

    await tester.tap(find.text('Add your name'));
    await tester.pumpAndSettle();
    expect(find.text('Edit profile'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Full name'),
      'Ada Lovelace',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email'),
      'ada@example.com',
    );
    await tester.tap(find.widgetWithText(PrimaryButton, 'Save changes'));
    await tester.pumpAndSettle();

    // Back on the hub with the new name, and the bloc's cached user refreshed.
    expect(find.text('Edit profile'), findsNothing);
    expect(find.text('Ada Lovelace'), findsOneWidget);
    verify(() => auth.add(const AuthProfileCompleted(after))).called(1);
  });
}
