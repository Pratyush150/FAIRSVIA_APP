import 'package:shared_models/shared_models.dart';
import 'package:test/test.dart';

PlacePrediction _p(String id, [int? distanceM]) => PlacePrediction(
  placeId: id,
  primaryText: id,
  secondaryText: '',
  description: id,
  distanceM: distanceM,
);

void main() {
  group('PlacePrediction', () {
    test(
      'parses distanceM (rounding a fractional value) and tolerates its absence',
      () {
        final near = PlacePrediction.fromJson({
          'placeId': 'a',
          'primaryText': 'Cafe',
          'secondaryText': 'Main St',
          'description': 'Cafe, Main St',
          'distanceM': 349.6,
        });
        expect(near.distanceM, 350);
        final unknown = PlacePrediction.fromJson({
          'placeId': 'b',
          'primaryText': 'Cafe',
          'secondaryText': '',
          'description': 'Cafe',
        });
        expect(unknown.distanceM, isNull);
        expect(near == unknown, isFalse);
      },
    );

    test('sortedByDistance orders nearest first when every row has one', () {
      final sorted = PlacePrediction.sortedByDistance([
        _p('far', 5000),
        _p('near', 120),
        _p('mid', 900),
      ]);
      expect(sorted.map((p) => p.placeId), ['near', 'mid', 'far']);
    });

    test('sortedByDistance is stable for equal distances', () {
      final sorted = PlacePrediction.sortedByDistance([
        _p('x', 100),
        _p('y', 100),
        _p('w', 50),
      ]);
      expect(sorted.map((p) => p.placeId), ['w', 'x', 'y']);
    });

    test(
      'sortedByDistance keeps provider order when any distance is unknown',
      () {
        final input = [_p('far', 5000), _p('unknown'), _p('near', 120)];
        final sorted = PlacePrediction.sortedByDistance(input);
        expect(sorted.map((p) => p.placeId), ['far', 'unknown', 'near']);
      },
    );
  });
}
