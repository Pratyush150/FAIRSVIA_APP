import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_models/shared_models.dart';

class MockUsers extends Mock implements UsersRemoteDataSource {}

class MockPlaces extends Mock implements PlacesRemoteDataSource {}

void main() {
  late MockUsers users;
  late MockPlaces places;

  setUp(() {
    users = MockUsers();
    places = MockPlaces();
    when(() => users.listPlaces()).thenAnswer((_) async => []);
    when(() => places.autocomplete(any())).thenAnswer(
      (_) async => const [
        PlacePrediction(
          placeId: 'p1',
          primaryText: '1 Main St',
          secondaryText: 'Miami',
          description: '1 Main St, Miami',
        ),
      ],
    );
    when(() => places.details('p1')).thenAnswer(
      (_) async => const PlaceDetails(
        placeId: 'p1',
        address: '1 Main St, Miami',
        location: GeoPoint(25.77, -80.19),
      ),
    );
  });

  PrimaryButton saveButton(WidgetTester tester) =>
      tester.widget<PrimaryButton>(find.widgetWithText(PrimaryButton, 'Save'));

  testWidgets('tapping a Home/Work chip enables Save without typing',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: SavedPlacesPage(users: users, places: places)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    // Pick an address first so the label is the only thing missing.
    await tester.enterText(
      find.widgetWithText(TextField, 'Address'),
      '1 Main',
    );
    await tester.pump(const Duration(milliseconds: 350)); // debounce
    await tester.pumpAndSettle();
    await tester.tap(find.text('1 Main St'));
    await tester.pumpAndSettle();
    expect(saveButton(tester).onPressed, isNull);

    await tester.tap(find.widgetWithText(ActionChip, 'Home'));
    await tester.pump();

    expect(saveButton(tester).onPressed, isNotNull);
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, 'Label'))
          .controller!
          .text,
      'Home',
    );
  });
}
