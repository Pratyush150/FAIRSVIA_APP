import 'package:shared_models/shared_models.dart';
import 'package:test/test.dart';

void main() {
  test('parses priceMatchDiscount and flags it', () {
    final b = FareBreakdown.fromJson({
      'baseFare': 30,
      'distanceFare': 60,
      'timeFare': 10,
      'bookingFee': 5,
      'priceMatchDiscount': 12,
    });
    expect(b.priceMatchDiscount, 12);
    expect(b.hasPriceMatch, isTrue);
    expect(b.copyWith(tip: 5).priceMatchDiscount, 12);
  });

  test('absent priceMatchDiscount means no line', () {
    final b = FareBreakdown.fromJson({
      'baseFare': 30,
      'distanceFare': 60,
      'timeFare': 10,
      'bookingFee': 5,
    });
    expect(b.priceMatchDiscount, 0);
    expect(b.hasPriceMatch, isFalse);
  });
}
