import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StripeSetupIntent', () {
    test('parses a fully-configured Stripe response', () {
      final s = StripeSetupIntent.fromJson({
        'setupIntentClientSecret': 'seti_1_secret',
        'customerId': 'cus_1',
        'ephemeralKeySecret': 'ek_secret',
        'publishableKey': 'pk_test_x',
      });
      expect(s.isConfigured, isTrue);
      expect(s.customerId, 'cus_1');
      expect(s.ephemeralKeySecret, 'ek_secret');
    });

    test('is not configured when the publishable key is empty (mock gateway)', () {
      final s = StripeSetupIntent.fromJson({
        'setupIntentClientSecret': 'seti_1_secret',
        'publishableKey': '',
      });
      expect(s.isConfigured, isFalse);
    });

    test('is not configured when there is no client secret', () {
      final s = StripeSetupIntent.fromJson({'publishableKey': 'pk_test_x'});
      expect(s.isConfigured, isFalse);
    });
  });

  group('ConnectStatus', () {
    test('parses payout readiness flags', () {
      final c = ConnectStatus.fromJson({
        'onboarded': true,
        'payoutsEnabled': true,
        'detailsSubmitted': true,
      });
      expect(c.onboarded, isTrue);
      expect(c.payoutsEnabled, isTrue);
      expect(c.detailsSubmitted, isTrue);
    });

    test('defaults missing flags to false', () {
      final c = ConnectStatus.fromJson({});
      expect(c.onboarded, isFalse);
      expect(c.payoutsEnabled, isFalse);
      expect(c.detailsSubmitted, isFalse);
    });
  });
}
