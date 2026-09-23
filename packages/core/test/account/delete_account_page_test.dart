import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockUsers extends Mock implements UsersRemoteDataSource {}

void main() {
  late _MockUsers users;
  late int deletedCalls;

  setUp(() {
    users = _MockUsers();
    deletedCalls = 0;
  });

  Future<void> pump(WidgetTester tester, {bool isDriver = false}) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: DeleteAccountPage(
        users: users,
        isDriver: isDriver,
        onDeleted: () => deletedCalls++,
      ),
    ));
    await tester.pumpAndSettle();
  }

  Finder deleteButton() => find.widgetWithText(PrimaryButton, 'Delete my account');
  bool enabled(WidgetTester tester) =>
      tester.widget<PrimaryButton>(deleteButton()).onPressed != null;

  testWidgets('cannot delete until the user acknowledges it', (tester) async {
    await pump(tester);
    expect(enabled(tester), isFalse);

    await tester.tap(find.text('I understand my account will be permanently deleted.'));
    await tester.pump();
    expect(enabled(tester), isTrue);
  });

  testWidgets('deletes and hands control back once the server confirms', (tester) async {
    when(() => users.deleteMe()).thenAnswer((_) async {});
    await pump(tester);

    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.tap(deleteButton());
    await tester.pumpAndSettle();

    verify(() => users.deleteMe()).called(1);
    expect(deletedCalls, 1);
  });

  testWidgets("shows the server's reason when it refuses, and deletes nothing", (tester) async {
    when(() => users.deleteMe()).thenThrow(const ApiException(
      'You have a ride in progress. Finish or cancel it, then delete your account.',
      statusCode: 409,
    ));
    await pump(tester);

    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.tap(deleteButton());
    await tester.pumpAndSettle();

    expect(find.textContaining('ride in progress'), findsOneWidget);
    expect(deletedCalls, 0);
    // Still on the page and able to try again.
    expect(enabled(tester), isTrue);
  });

  testWidgets('drivers are told to withdraw earnings first', (tester) async {
    await pump(tester, isDriver: true);
    expect(find.text('Earnings first'), findsOneWidget);
  });

  testWidgets('riders are not shown the driver-only earnings rule', (tester) async {
    await pump(tester);
    expect(find.text('Earnings first'), findsNothing);
  });

  testWidgets('an unexpected server error never shows raw server text', (tester) async {
    when(() => users.deleteMe()).thenThrow(
        const ApiException('Cannot DELETE /api/v1/users/me', statusCode: 404));
    await pump(tester);

    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.tap(deleteButton());
    await tester.pumpAndSettle();

    expect(find.textContaining('Cannot DELETE'), findsNothing);
    expect(find.textContaining('nothing was deleted'), findsOneWidget);
    expect(deletedCalls, 0);
  });
}
