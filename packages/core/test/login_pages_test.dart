import 'package:bloc_test/bloc_test.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_models/shared_models.dart';

class MockAuthBloc extends MockBloc<AuthEvent, AuthState> implements AuthBloc {}

void main() {
  late MockAuthBloc bloc;
  final previousMarket = Market.current;

  setUp(() {
    Market.current = Market.india;
    bloc = MockAuthBloc();
  });

  tearDown(() => Market.current = previousMarket);

  Widget host(Widget page, AuthState state, {bool dark = false}) {
    whenListen(bloc, const Stream<AuthState>.empty(), initialState: state);
    return MaterialApp(
      theme: dark ? AppTheme.dark : AppTheme.light,
      home: BlocProvider<AuthBloc>.value(value: bloc, child: page),
    );
  }

  group('PhoneEntryPage', () {
    const unauth = AuthState(status: AuthStatus.unauthenticated);

    testWidgets('shows the market prefix chip and a local-format hint', (
      tester,
    ) async {
      await tester.pumpWidget(host(const PhoneEntryPage(), unauth));

      expect(
        find.descendant(
          of: find.byKey(const Key('dial-code-chip')),
          matching: find.text('IN +91'),
        ),
        findsOneWidget,
      );
      final field = tester.widget<TextField>(
        find.byKey(const Key('phone-field')),
      );
      expect(field.decoration?.hintText, '98765 43210');
      // The chip is decoration, not text the user can edit.
      expect(field.controller?.text, isEmpty);
      // The 64 px logomark sits in the header.
      expect(tester.widget<RideVelaMark>(find.byType(RideVelaMark)).size, 64);
    });

    testWidgets('prefix follows the build market', (tester) async {
      Market.current = Market.uzbekistan;
      await tester.pumpWidget(host(const PhoneEntryPage(), unauth));
      expect(find.text('UZ +998'), findsOneWidget);
      final field = tester.widget<TextField>(
        find.byKey(const Key('phone-field')),
      );
      expect(field.decoration?.hintText, '90 123 45 67');
    });

    testWidgets('submits the typed local number as E.164', (tester) async {
      await tester.pumpWidget(host(const PhoneEntryPage(), unauth));
      await tester.enterText(
        find.byKey(const Key('phone-field')),
        '98765 43210',
      );
      await tester.pump();
      await tester.tap(find.text('Continue'));
      await tester.pump();
      verify(() => bloc.add(const AuthOtpRequested('+919876543210'))).called(1);
    });

    testWidgets('Terms and Privacy Policy are tappable links', (tester) async {
      await tester.pumpWidget(host(const PhoneEntryPage(), unauth));

      await tester.tapOnText(find.textRange.ofSubstring('Terms'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'Terms of Service'), findsOneWidget);
      expect(find.text('Draft — not yet published'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tapOnText(find.textRange.ofSubstring('Privacy Policy'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'Privacy Policy'), findsOneWidget);
    });
  });

  group('OtpPage', () {
    const sent = AuthState(
      status: AuthStatus.codeSent,
      phone: '+919876543210',
      devCode: '123456',
    );

    testWidgets('the code field asks for one-time-code autofill', (
      tester,
    ) async {
      await tester.pumpWidget(host(const OtpPage(), sent));
      final field = tester.widget<TextField>(
        find.byKey(const Key('otp-field')),
      );
      expect(field.autofillHints, contains(AutofillHints.oneTimeCode));
      // Dev code chip is still offered.
      expect(find.text('Dev code: 123456'), findsOneWidget);
    });

    testWidgets('the phone number reads on a dark screen (audit #1)', (
      tester,
    ) async {
      await tester.pumpWidget(host(const OtpPage(), sent, dark: true));
      final rich = tester.widget<RichText>(
        find.byWidgetPredicate((w) =>
            w is RichText && w.text.toPlainText().contains('+919876543210')),
      );
      TextSpan? number;
      rich.text.visitChildren((span) {
        if (span is TextSpan && span.text == '+919876543210') number = span;
        return true;
      });
      final bg = AppTheme.dark.colorScheme.surface;
      final fg = number!.style!.color!;
      double lum(Color c) => c.computeLuminance();
      final hi = lum(fg) > lum(bg) ? lum(fg) : lum(bg);
      final lo = lum(fg) > lum(bg) ? lum(bg) : lum(fg);
      expect((hi + 0.05) / (lo + 0.05), greaterThanOrEqualTo(4.5));
    });

    testWidgets(
      'a pasted code with spaces is reduced to digits and submitted',
      (tester) async {
        await tester.pumpWidget(host(const OtpPage(), sent));
        await tester.enterText(find.byKey(const Key('otp-field')), '123 456');
        await tester.pump();
        verify(() => bloc.add(const AuthOtpSubmitted('123456'))).called(1);
      },
    );
  });
}
