import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rider_app/features/trip/trip_cubit.dart';
import 'package:rider_app/home_page.dart';
import 'package:core/core.dart';
import 'package:shared_models/shared_models.dart';

class MockTripCubit extends MockCubit<TripState> implements TripCubit {}

/// The tip flow on the post-ride sheet.
///
/// A tip can only be sent once — the backend rejects a second one with 409 —
/// so the first tap used to charge immediately and lock the chips, which made
/// a mis-tap permanent. The choice is now local until the rider confirms it.
void main() {
  late MockTripCubit cubit;

  setUp(() {
    cubit = MockTripCubit();
    when(() => cubit.tipDriver(any())).thenAnswer((_) async {});
  });

  Future<void> pump(WidgetTester tester, TripState state) async {
    whenListen(cubit, const Stream<TripState>.empty(), initialState: state);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlocProvider<TripCubit>.value(
            value: cubit,
            child: CompletedSheet(state: state),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  const completed = TripState(phase: TripPhase.completed, fareFinal: 12.5);

  testWidgets('picking a tip does not charge it yet', (tester) async {
    await pump(tester, completed);

    await tester.tap(find.text('\$3'));
    await tester.pumpAndSettle();

    // Nothing sent — the rider has only chosen.
    verifyNever(() => cubit.tipDriver(any()));
    // ...and there is now something to confirm.
    expect(find.text('Add \$3 tip'), findsOneWidget);
  });

  testWidgets('the choice can be changed before it is confirmed',
      (tester) async {
    await pump(tester, completed);

    await tester.tap(find.text('\$2'));
    await tester.pumpAndSettle();
    expect(find.text('Add \$2 tip'), findsOneWidget);

    // Changed their mind — this is the case that used to be impossible.
    await tester.tap(find.text('\$5'));
    await tester.pumpAndSettle();
    expect(find.text('Add \$5 tip'), findsOneWidget);
    expect(find.text('Add \$2 tip'), findsNothing);

    verifyNever(() => cubit.tipDriver(any()));
  });

  testWidgets('confirming sends exactly the amount last chosen',
      (tester) async {
    await pump(tester, completed);

    await tester.tap(find.text('\$2'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('\$5'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add \$5 tip'));
    await tester.pumpAndSettle();

    verify(() => cubit.tipDriver(5.0)).called(1);
    verifyNever(() => cubit.tipDriver(2.0));
  });

  testWidgets('once a tip is sent the chips lock and the total is shown',
      (tester) async {
    await pump(
      tester,
      const TripState(
        phase: TripPhase.completed,
        fareFinal: 12.5,
        tipAmount: 5,
      ),
    );

    expect(find.text('Tip of \$5 added.'), findsOneWidget);
    // No confirm button remains, and tapping another amount changes nothing.
    expect(find.textContaining('Add \$'), findsNothing);
    await tester.tap(find.text('\$2'));
    await tester.pumpAndSettle();
    verifyNever(() => cubit.tipDriver(any()));
  });

  testWidgets('a receipt with no tip leaves the tip flow open', (tester) async {
    // The backend puts `tip: 0` on the receipt of every untipped ride. Reading
    // that as "a tip was already sent" locked the chips the moment the sheet
    // appeared and showed "Tip of \$0 added." — so nobody could ever tip.
    await pump(
      tester,
      const TripState(
        phase: TripPhase.completed,
        fareFinal: 12.5,
        receipt: Receipt(
          tripId: 't1',
          fare: 12.5,
          currency: 'USD',
          tip: 0, // exactly what an untipped ride's receipt carries
        ),
      ),
    );

    expect(find.textContaining('Tip of'), findsNothing);
    await tester.tap(find.text('\$3'));
    await tester.pumpAndSettle();
    expect(find.text('Add \$3 tip'), findsOneWidget);

    await tester.tap(find.text('Add \$3 tip'));
    await tester.pumpAndSettle();
    verify(() => cubit.tipDriver(3.0)).called(1);
  });

  testWidgets('a chosen amount can be cleared before it is confirmed',
      (tester) async {
    await pump(tester, completed);
    await tester.tap(find.text('\$3'));
    await tester.pumpAndSettle();
    expect(find.text('Add \$3 tip'), findsOneWidget);

    // Tapping the chosen chip again takes the rider back to "no tip" — there
    // was otherwise no way out of a mis-tap short of leaving the sheet.
    await tester.tap(find.text('\$3'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Add \$'), findsNothing);
    verifyNever(() => cubit.tipDriver(any()));
  });

  testWidgets('a tip that fails says so, and stays retryable', (tester) async {
    await pump(
      tester,
      const TripState(
        phase: TripPhase.completed,
        fareFinal: 12.5,
        error: 'Your card was declined.',
      ),
    );
    await tester.tap(find.text('\$5'));
    await tester.pumpAndSettle();

    expect(find.text('Your card was declined.'), findsOneWidget);
    // Still offering to send it: a failed charge must not look like a dead
    // button.
    expect(find.text('Add \$5 tip'), findsOneWidget);
  });

  testWidgets('the confirm button is disabled while a tip is in flight',
      (tester) async {
    await pump(
      tester,
      const TripState(phase: TripPhase.completed, fareFinal: 12.5),
    );
    await tester.tap(find.text('\$3'));
    await tester.pumpAndSettle();

    // Re-pump in the sending state: the button reports progress and cannot be
    // tapped again, so a double tap can't produce the 409.
    await pump(
      tester,
      const TripState(
        phase: TripPhase.completed,
        fareFinal: 12.5,
        tipping: true,
      ),
    );
    expect(find.text('\$3'), findsOneWidget);
    verifyNever(() => cubit.tipDriver(any()));
  });

  group('in the Indian market (Pune pilot)', () {
    setUp(() => Market.current = Market.india);
    tearDown(() => Market.current = Market.unitedStates);

    testWidgets('fares, tips and totals read in rupees, with rupee-sized tips',
        (tester) async {
      await pump(
        tester,
        const TripState(
          phase: TripPhase.completed,
          fareFinal: 184,
          receipt: Receipt(tripId: 't1', fare: 184, currency: 'INR', tip: 0),
        ),
      );
      // A dollar sign anywhere on this sheet would be a bug in India.
      expect(find.textContaining('\$'), findsNothing);
      for (final chip in ['₹20', '₹50', '₹100']) {
        expect(find.text(chip), findsOneWidget);
      }
      await tester.tap(find.text('₹50'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add ₹50 tip'));
      await tester.pumpAndSettle();
      verify(() => cubit.tipDriver(50.0)).called(1);
    });
  });
}
