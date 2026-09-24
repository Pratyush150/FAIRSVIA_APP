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

  testWidgets('rider page: spaced phone, own rating line, no details slot',
      (tester) async {
    whenListen(
      auth,
      const Stream<AuthState>.empty(),
      initialState: const AuthState(
        status: AuthStatus.authenticated,
        user: AppUser(
          id: 'u1',
          phone: '+919876543210',
          role: 'rider',
          fullName: 'Asha Rao',
          ratingAvg: 4.8,
          ratingCount: 9,
        ),
      ),
    );
    await tester.pumpWidget(
      BlocProvider<AuthBloc>.value(
        value: auth,
        child: const MaterialApp(home: AccountMenuPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('+91 98765 43210'), findsOneWidget);
    expect(find.text('4.8'), findsOneWidget);
    expect(find.text('Saved places'), findsOneWidget);
    // Menu rows are navigation, not state: Regular (audit 2.1 rule 3). The
    // one Fill star left is the rating line — a real state.
    expect(find.byIcon(PhosphorIconsRegular.star), findsOneWidget);
    expect(find.byIcon(PhosphorIconsRegular.heart), findsOneWidget);
    expect(find.byIcon(PhosphorIconsFill.star), findsOneWidget);
    expect(find.byIcon(PhosphorIconsFill.heart), findsNothing);
  });

  testWidgets('driver details slot renders inside the profile card and '
      'replaces the built-in rating line', (tester) async {
    whenListen(
      auth,
      const Stream<AuthState>.empty(),
      initialState: const AuthState(
        status: AuthStatus.authenticated,
        user: AppUser(
          id: 'u1',
          phone: '+919876543210',
          role: 'driver',
          fullName: 'Ravi Kumar',
          ratingAvg: 4.8,
          ratingCount: 9,
        ),
      ),
    );
    await tester.pumpWidget(
      BlocProvider<AuthBloc>.value(
        value: auth,
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const AccountMenuPage(
            isDriver: true,
            profileDetails: Text('DETAILS'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('DETAILS'), findsOneWidget);
    expect(find.text('4.8'), findsNothing);
    expect(find.text('Earnings'), findsOneWidget);
    // The page sits on the theme's background, not a hard-coded colour.
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
    expect(scaffold.backgroundColor, isNull);
    expect(AppTheme.dark.scaffoldBackgroundColor, AppColors.backgroundDark);
    // Row icons follow the theme in dark mode (they were light-mode grey),
    // on the shared neutral icon token (audit 2.1 rule 4).
    final chevron = tester.widget<Icon>(
      find.byIcon(PhosphorIconsRegular.caretRight).first,
    );
    expect(chevron.color, AppColors.iconNeutralDark);
    expect(chevron.size, 20);
  });
}
