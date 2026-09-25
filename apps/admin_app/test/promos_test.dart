import 'package:admin_app/data/admin_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AdminPromo parses the rider-facing Offers fields', () {
    final p = AdminPromo.fromJson({
      'code': 'WELCOME50',
      'kind': 'percent',
      'value': '50',
      'maxDiscount': '100',
      'minSubtotal': '0',
      'active': true,
      'usedCount': 3,
      'listed': true,
      'title': 'Welcome offer',
      'description': 'Half price on a ride',
    });
    expect(p.listed, isTrue);
    expect(p.title, 'Welcome offer');
    expect(p.description, 'Half price on a ride');
    expect(p.maxDiscount, 100);
    expect(p.label, '50% off');
  });

  test('an older row without the fields reads as unlisted', () {
    final p = AdminPromo.fromJson({
      'code': 'OLD',
      'kind': 'flat',
      'value': 5,
      'minSubtotal': 0,
    });
    expect(p.listed, isFalse);
    expect(p.title, isNull);
    expect(p.maxDiscount, isNull);
  });
}
