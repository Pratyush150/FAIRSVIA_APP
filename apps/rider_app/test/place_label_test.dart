import 'package:flutter_test/flutter_test.dart';
import 'package:rider_app/features/trip/destination_search_page.dart';
import 'package:shared_models/shared_models.dart';

void main() {
  PlacePrediction p({
    String primary = '',
    String secondary = '',
    String description = '',
  }) => PlacePrediction(
    placeId: 'x',
    primaryText: primary,
    secondaryText: secondary,
    description: description,
  );

  test('a landmark keeps the name the rider chose, not its Plus Code', () {
    expect(
      placeLabel(
        p(
          primary: 'Pune station',
          description: 'Pune station, Agarkar Nagar, Pune, Maharashtra, India',
        ),
        'GVHF+GQF, Agarkar Nagar, Pune, Maharashtra 411001, India',
      ),
      'Pune station, Agarkar Nagar, Pune, Maharashtra, India',
    );
  });

  test('builds the name from its parts when there is no description', () {
    expect(
      placeLabel(
        p(primary: 'FC Road', secondary: 'Shivajinagar, Pune'),
        'addr',
      ),
      'FC Road, Shivajinagar, Pune',
    );
  });

  test('with no name at all, drops a leading Plus Code from the address', () {
    expect(
      placeLabel(p(), 'GVHF+GQF, Agarkar Nagar, Pune'),
      'Agarkar Nagar, Pune',
    );
    expect(placeLabel(p(), '12 MG Road, Pune'), '12 MG Road, Pune');
  });
}
