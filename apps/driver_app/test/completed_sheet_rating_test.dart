import 'package:bloc_test/bloc_test.dart';
import 'package:design_system/design_system.dart';
import 'package:driver_app/features/driver/driver_cubit.dart';
import 'package:driver_app/home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

class MockDriverCubit extends MockCubit<DriverState> implements DriverCubit {}

/// Owner report (driver 2.10.0): the "Rate your rider" card was not showing
/// at the end of a trip. The trip-complete sheet must show the rating title,
/// the stars and Done inside the viewport on small and large phones, at 1.0
/// and 1.3 text scale, with the cash banner and end note present.
void main() {
  const sizes = [Size(360, 780), Size(411, 914)];
  const scales = [1.0, 1.3];

  for (final size in sizes) {
    for (final scale in scales) {
      testWidgets(
        'rating + Done visible at ${size.width.toInt()}x${size.height.toInt()} text $scale',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.reset);
          final cubit = MockDriverCubit();
          final state = DriverState(
            phase: DriverPhase.completed,
            lastTripId: 'trip-1',
            lastEarned: 1234,
            cashToCollect: 245,
            endNote: 'Ended before the drop-off — charged the metered fare.',
          );
          whenListen(
            cubit,
            const Stream<DriverState>.empty(),
            initialState: state,
          );
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.light,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: Scaffold(
                body: BlocProvider<DriverCubit>.value(
                  value: cubit,
                  child: DriverSheetLayer(state: state),
                ),
              ),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 600));

          final screen = Offset.zero & size;
          for (final f in [
            find.text('Rate your rider'),
            find.byType(StarRating),
            find.text('Done'),
          ]) {
            expect(f, findsOneWidget);
            final r = tester.getRect(f);
            expect(
              screen.contains(r.topLeft) &&
                  screen.contains(r.bottomRight - const Offset(0.1, 0.1)),
              isTrue,
              reason: '$f at $r is outside the $size viewport',
            );
            f.hitTestable().evaluate().isNotEmpty ||
                fail('$f is not hit-testable (clipped/covered)');
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
