import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rider_app/features/trip/trip_cubit.dart';
import 'package:rider_app/home_page.dart';

class MockTripCubit extends MockCubit<TripState> implements TripCubit {}

void main() {
  Future<String?> open(WidgetTester tester, TripCubit cubit) async {
    String? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () async {
              result = await showDialog<String>(
                context: context,
                builder: (_) =>
                    CancelRideDialog(cubit: cubit, feeWarning: false),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('confirming cancel while the phase flips to idle does not '
      'double-pop (regression: !_debugLocked crash)', (tester) async {
    final cubit = MockTripCubit();
    final states = StreamController<TripState>.broadcast();
    whenListen(cubit, states.stream,
        initialState: const TripState(phase: TripPhase.searching));

    await open(tester, cubit);
    expect(find.text('Cancel this ride?'), findsOneWidget);

    // User picks a reason → dialog pops with it; the cubit then goes idle
    // while the pop is still in flight (what cancelTrip() does).
    await tester.tap(find.text('Changed my plans'));
    states.add(const TripState());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Cancel this ride?'), findsNothing);
    await states.close();
  });

  testWidgets('closes itself when the trip ends underneath it', (tester) async {
    final cubit = MockTripCubit();
    final states = StreamController<TripState>.broadcast();
    whenListen(cubit, states.stream,
        initialState: const TripState(phase: TripPhase.searching));

    await open(tester, cubit);
    expect(find.text('Cancel this ride?'), findsOneWidget);

    states.add(const TripState(phase: TripPhase.choosingRide));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Cancel this ride?'), findsNothing);
    await states.close();
  });
}
