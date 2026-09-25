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

/// The tip flow on the post-ride sheet (owner, 2026-09-25): tapping an amount
/// selects it — that IS the confirmation, no second "Add tip" button; tapping
/// it again removes it. The selected tip is charged when the rider taps Done.
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

  testWidgets('tapping an amount selects it, with no extra confirm button',
      (tester) async {
    await pump(tester, completed);
    await tester.tap(find.text('\$3'));
    await tester.pumpAndSettle();
    verifyNever(() => cubit.tipDriver(any()));
    verify(() => cubit.selectedTip = 3.0).called(1);
    expect(find.textContaining('Add \$'), findsNothing);
    expect(find.textContaining('tip will be added when you tap Done'),
        findsOneWidget);
  });

  testWidgets('tapping the same amount again removes it', (tester) async {
    await pump(tester, completed);
    await tester.tap(find.text('\$3'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('\$3'));
    await tester.pumpAndSettle();
    verify(() => cubit.selectedTip = null).called(1);
    expect(find.textContaining('tip will be added'), findsNothing);
  });

  testWidgets('switching amounts keeps only the last one', (tester) async {
    await pump(tester, completed);
    await tester.tap(find.text('\$2'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('\$5'));
    await tester.pumpAndSettle();
    verify(() => cubit.selectedTip = 5.0).called(1);
    expect(find.textContaining('\$5 tip will be added'), findsOneWidget);
  });

  testWidgets('Done sends the tip and closes the ride', (tester) async {
    when(() => cubit.finishRide()).thenAnswer((_) async {});
    whenListen(cubit, const Stream<TripState>.empty(), initialState: completed);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: BlocProvider<TripCubit>.value(
          value: cubit,
          child: const CompletedDoneButton(),
        ),
      ),
    ));
    await tester.tap(find.text('Done'));
    await tester.pump();
    verify(() => cubit.finishRide()).called(1);
  });

  testWidgets('once a tip is sent the chips lock and the total is shown',
      (tester) async {
    await pump(
      tester,
      const TripState(phase: TripPhase.completed, fareFinal: 12.5, tipAmount: 5),
    );
    expect(find.text('Tip of \$5 added.'), findsOneWidget);
    await tester.tap(find.text('\$2'));
    await tester.pumpAndSettle();
    verifyNever(() => cubit.tipDriver(any()));
  });

  group('in the Indian market (Pune pilot)', () {
    setUp(() => Market.current = Market.india);
    tearDown(() => Market.current = Market.unitedStates);

    testWidgets('tips read in rupees and select on one tap', (tester) async {
      await pump(
        tester,
        const TripState(
          phase: TripPhase.completed,
          fareFinal: 184,
          receipt: Receipt(tripId: 't1', fare: 184, currency: 'INR', tip: 0),
        ),
      );
      expect(find.textContaining('\$'), findsNothing);
      for (final chip in ['₹20', '₹50', '₹100']) {
        expect(find.text(chip), findsOneWidget);
      }
      await tester.tap(find.text('₹50'));
      await tester.pumpAndSettle();
      verify(() => cubit.selectedTip = 50.0).called(1);
      expect(find.textContaining('₹50 tip will be added'), findsOneWidget);
    });
  });
}
