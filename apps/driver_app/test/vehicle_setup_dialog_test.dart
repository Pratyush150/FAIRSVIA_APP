import 'package:bloc_test/bloc_test.dart';
import 'package:design_system/design_system.dart';
import 'package:driver_app/features/driver/driver_cubit.dart';
import 'package:driver_app/features/driver/vehicle_setup_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_models/shared_models.dart';

class MockDriverCubit extends MockCubit<DriverState> implements DriverCubit {}

/// Vehicle setup: a driver in the Pune pilot can register an auto-rickshaw or
/// a bike taxi, with the same Indian plate rule as a car.
void main() {
  late MockDriverCubit cubit;
  final previousMarket = Market.current;

  setUp(() {
    Market.current = Market.india;
    cubit = MockDriverCubit();
    whenListen(cubit, const Stream<DriverState>.empty(),
        initialState: const DriverState());
    when(() => cubit.onboard(
          make: any(named: 'make'),
          model: any(named: 'model'),
          plate: any(named: 'plate'),
          tier: any(named: 'tier'),
          color: any(named: 'color'),
          goOnlineAfter: any(named: 'goOnlineAfter'),
        )).thenAnswer((_) async => true);
  });
  tearDown(() => Market.current = previousMarket);

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: VehicleSetupDialog(cubit: cubit)),
    ));
  }

  Future<void> fill(WidgetTester tester, String plate) async {
    await tester.enterText(find.widgetWithText(TextField, 'Make'), 'Bajaj');
    await tester.enterText(find.widgetWithText(TextField, 'Model'), 'RE Compact');
    await tester.enterText(
        find.widgetWithText(TextField, 'Plate number'), plate);
  }

  Future<void> pick(WidgetTester tester, String label) async {
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  const extra = bool.fromEnvironment('EXTRA_TIERS');

  testWidgets('offers only the car tiers while auto/bike are held back',
      (tester) async {
    await pump(tester);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    expect(find.text('Bike (bike taxi, 1 rider)'), findsNothing);
    expect(find.text('Auto (auto-rickshaw, 3 riders)'), findsNothing);
    for (final label in ['Comfort', 'XL', 'Premium']) {
      expect(find.text(label), findsWidgets, reason: label);
    }
  }, skip: extra);

  testWidgets('offers Bike and Auto first, then the car tiers', skip: !extra,
      (tester) async {
    await pump(tester);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    for (final label in [
      'Bike (bike taxi, 1 rider)',
      'Auto (auto-rickshaw, 3 riders)',
      'Comfort',
      'XL',
      'Premium',
    ]) {
      expect(find.text(label), findsWidgets, reason: label);
    }
    final bikeY = tester.getTopLeft(find.text('Bike (bike taxi, 1 rider)').last).dy;
    final autoY =
        tester.getTopLeft(find.text('Auto (auto-rickshaw, 3 riders)').last).dy;
    final xlY = tester.getTopLeft(find.text('XL').last).dy;
    expect(bikeY, lessThan(autoY));
    expect(autoY, lessThan(xlY));
  });

  testWidgets('registers an auto with an Indian plate', skip: !extra, (tester) async {
    await pump(tester);
    await fill(tester, 'mh 12 ab 1234');
    await pick(tester, 'Auto (auto-rickshaw, 3 riders)');
    await tester.tap(find.text('Save & go online'));
    await tester.pumpAndSettle();
    verify(() => cubit.onboard(
          make: 'Bajaj',
          model: 'RE Compact',
          plate: 'MH 12 AB 1234',
          tier: 'auto',
          color: null,
          goOnlineAfter: true,
        )).called(1);
  });

  testWidgets('registers a bike', skip: !extra, (tester) async {
    await pump(tester);
    await fill(tester, 'MH12XY9876');
    await pick(tester, 'Bike (bike taxi, 1 rider)');
    await tester.tap(find.text('Save & go online'));
    await tester.pumpAndSettle();
    verify(() => cubit.onboard(
          make: any(named: 'make'),
          model: any(named: 'model'),
          plate: 'MH12XY9876',
          tier: 'bike',
          color: any(named: 'color'),
          goOnlineAfter: any(named: 'goOnlineAfter'),
        )).called(1);
  });

  testWidgets('an auto still needs a valid plate', skip: !extra, (tester) async {
    await pump(tester);
    await fill(tester, 'AUTO1');
    await pick(tester, 'Auto (auto-rickshaw, 3 riders)');
    await tester.tap(find.text('Save & go online'));
    await tester.pumpAndSettle();
    expect(find.textContaining('as it is on the vehicle, e.g. MH 12 AB 1234'),
        findsOneWidget);
    verifyNever(() => cubit.onboard(
          make: any(named: 'make'),
          model: any(named: 'model'),
          plate: any(named: 'plate'),
          tier: any(named: 'tier'),
          color: any(named: 'color'),
          goOnlineAfter: any(named: 'goOnlineAfter'),
        ));
  });

  testWidgets('hints an auto make when it is missing', skip: !extra, (tester) async {
    await pump(tester);
    await pick(tester, 'Auto (auto-rickshaw, 3 riders)');
    await tester.tap(find.text('Save & go online'));
    await tester.pumpAndSettle();
    expect(find.text('Enter the vehicle make (e.g. Bajaj).'), findsOneWidget);
  });
}
