import 'package:bloc_test/bloc_test.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rider_app/features/trip/trip_cubit.dart';
import 'package:rider_app/home_page.dart';

class MockTripCubit extends MockCubit<TripState> implements TripCubit {}

/// The two ride moments that must visibly move: the car gliding toward the
/// pickup pin as the real ETA falls, and the confetti burst when the ride
/// completes (present, animating, not clipped by the sheet's scroll view).
void main() {
  double glyphLeft(WidgetTester tester) =>
      tester.getTopLeft(find.byKey(const ValueKey('ride-progress-glyph'))).dx;

  Widget host(Widget child) => MaterialApp(
    home: Scaffold(
      body: Padding(padding: const EdgeInsets.all(16), child: child),
    ),
  );

  testWidgets(
    'driver arriving: car glides toward the pickup pin as ETA falls',
    (tester) async {
      await tester.pumpWidget(host(const DriverArrivingCard(etaSec: 600)));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('ride-progress-end-glyph')),
        findsOneWidget,
      );
      final start = glyphLeft(tester);
      LinearProgressIndicator bar() => tester.widget<LinearProgressIndicator>(
        find.byKey(const ValueKey('ride-progress-bar')),
      );
      expect(bar().value, 0);

      // ETA halves: the car is mid-glide a moment later, then rests at 50%.
      await tester.pumpWidget(host(const DriverArrivingCard(etaSec: 300)));
      await tester.pump(const Duration(milliseconds: 200));
      final mid = glyphLeft(tester);
      expect(mid, greaterThan(start));
      await tester.pumpAndSettle();
      expect(bar().value, closeTo(0.5, 1e-9));
      expect(glyphLeft(tester), greaterThan(mid));
      expect(find.text('5 min away'), findsOneWidget);
    },
  );

  testWidgets('driver arriving: a re-route that raises the ETA never goes '
      'negative', (tester) async {
    await tester.pumpWidget(host(const DriverArrivingCard(etaSec: 300)));
    await tester.pumpWidget(host(const DriverArrivingCard(etaSec: 900)));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<LinearProgressIndicator>(
            find.byKey(const ValueKey('ride-progress-bar')),
          )
          .value,
      0,
    );
  });

  testWidgets('completed: confetti is on screen, unclipped, and plays once', (
    tester,
  ) async {
    const state = TripState(phase: TripPhase.completed, fareFinal: 12.5);
    final cubit = MockTripCubit();
    whenListen(cubit, const Stream<TripState>.empty(), initialState: state);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlocProvider<TripCubit>.value(
            value: cubit,
            child: const CompletedSheet(state: state),
          ),
        ),
      ),
    );
    if (LocalArt.on) return; // the local variant shows its flower art instead
    final confetti = find.byWidgetPredicate(
      (w) => w is LottieMoment && w.asset == 'confetti',
    );
    expect(confetti, findsOneWidget);
    // The sheet's scroll view must not clip the burst above the check.
    final scroll = tester.widget<SingleChildScrollView>(
      find
          .ancestor(of: confetti, matching: find.byType(SingleChildScrollView))
          .first,
    );
    expect(scroll.clipBehavior, Clip.none);

    // Let the real asset load, then the controller must be running.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    await tester.pump();
    // (lottie is design_system's dependency, not this app's: match by name.)
    final dynamic lottie = tester.widget(
      find.descendant(
        of: confetti,
        matching: find.byWidgetPredicate(
          (w) => w.runtimeType.toString() == 'Lottie',
        ),
      ),
    );
    final c = lottie.controller as AnimationController;
    await tester.pump(const Duration(milliseconds: 16));
    expect(c.isAnimating, isTrue);
    expect(c.value, greaterThan(0));
    // One-shot: it finishes and fades away, so pumpAndSettle settles.
    await tester.pumpAndSettle();
    expect(c.isAnimating, isFalse);
    expect(
      tester
          .widget<AnimatedOpacity>(
            find.descendant(
              of: confetti,
              matching: find.byType(AnimatedOpacity),
            ),
          )
          .opacity,
      0,
    );
  });
}
