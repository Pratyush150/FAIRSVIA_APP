import 'package:shared_models/shared_models.dart';
import 'package:test/test.dart';

void main() {
  tearDown(() => Market.current = Market.unitedStates);

  group('Market', () {
    test('parses build codes, defaulting to the US', () {
      expect(Market.parse('in'), Market.india);
      expect(Market.parse(' UZ '), Market.uzbekistan);
      expect(Market.parse(null), Market.unitedStates);
      expect(Market.parse('xx'), Market.unitedStates);
    });

    test('metric markets read metres and kilometres', () {
      expect(Market.india.distance(843), '840 m');
      expect(Market.india.distance(12345), '12.3 km');
      expect(Market.india.distance(3200, approx: true), '~3.2 km');
      expect(Market.india.distanceUnit, 'km');
    });

    test('offer-card rules: practically-there and one-decimal legs', () {
      expect(Market.india.nearLabel(120), '< 150 m');
      expect(Market.india.nearLabel(400), isNull);
      expect(Market.india.legDistance(300), '0.3 km');
      expect(Market.unitedStates.nearLabel(100), '< 500 ft');
      expect(Market.unitedStates.legDistance(161), '0.1 mi');
    });

    test('an Indian offer card reads km end to end', () {
      Market.current = Market.india;
      final offer = RideOffer.fromJson({
        'tripId': 't',
        'pickup': {'lat': 18.5, 'lng': 73.8},
        'dropoff': {'lat': 18.6, 'lng': 73.9},
        'fare': 180,
        'distanceM': 4200,
        'durationS': 900,
        'approachDistanceM': 1800,
        'approachEtaS': 240,
        'approachSource': 'road',
      });
      expect(offer.tripLabel, '4.2 km · 15 min');
      expect(offer.approachEtaLabel, '4 min · 1.8 km to pickup');
    });

    test('turns what people type into E.164', () {
      expect(Market.india.toE164('98765 43210'), '+919876543210');
      expect(Market.india.toE164('098765 43210'), '+919876543210');
      expect(Market.india.toE164('+91 98765-43210'), '+919876543210');
      // Typed with '+': international, not forced into India.
      expect(Market.india.toE164('+998 90 123 45 67'), '+998901234567');
      expect(Market.uzbekistan.toE164('90 123 45 67'), '+998901234567');
      expect(Market.india.toE164('123'), isNull);
      expect(Market.india.toE164(''), isNull);
    });

    test('maps open on the market\'s own city before GPS arrives', () {
      final (lat, lng) = Market.india.cityCenter;
      expect(lat, closeTo(18.52, 0.01)); // Pune
      expect(lng, closeTo(73.86, 0.01));
      expect(Market.uzbekistan.cityCenter.$1, closeTo(41.31, 0.01)); // Tashkent
    });

    test('money groups digits the local way', () {
      expect(Money.format(125000, currency: 'INR'), '₹1,25,000');
      expect(Money.format(12500000, currency: 'INR'), '₹1,25,00,000');
      expect(Money.format(1234.5, currency: 'INR'), '₹1,234.50');
      expect(Money.format(999, currency: 'INR'), '₹999');
      expect(Money.format(-102, currency: 'INR'), '-₹102');
      expect(Money.format(1234567.25, currency: 'USD'), '\$1,234,567.25');
      expect(Money.format(18500, currency: 'UZS'), "18 500 so'm");
    });

    test('SOS numbers are the market\'s own, never another country\'s', () {
      expect(Market.india.emergencyNumbers,
          [('Emergency', '112'), ('Police', '100'), ('Ambulance', '108')]);
      expect(Market.uzbekistan.emergencyNumbers.first, ('Police', '102'));
      expect(Market.unitedStates.emergencyNumbers, [('Emergency', '911')]);
      for (final m in [Market.india, Market.uzbekistan, Market.unitedStates]) {
        // The SOS sheet shows three tiles; a fourth would be silently dropped.
        expect(m.emergencyNumbers.length, inInclusiveRange(1, 3));
      }
    });

    test('Indian plates: checked like the server, shown as printed', () {
      expect(Market.india.isValidPlate('mh 12-ab 1234'), isTrue);
      expect(Market.india.isValidPlate('22 BH 1234 AA'), isTrue);
      expect(Market.india.isValidPlate('FL534048'), isFalse);
      expect(Market.india.formatPlate('MH12AB1234'), 'MH 12 AB 1234');
      expect(Market.india.formatPlate('dl3cab1234'), 'DL 3 CAB 1234');
      expect(Market.unitedStates.isValidPlate('FL534048'), isTrue);
    });

    test('the US reads feet and miles', () {
      expect(Market.unitedStates.distance(100), '330 ft');
      expect(Market.unitedStates.distance(16093), '10.0 mi');
    });
  });

  group('Money', () {
    test('formats each currency the way people write it', () {
      expect(Money.format(245, currency: 'INR'), '₹245');
      expect(Money.format(245.5, currency: 'INR'), '₹245.50');
      expect(Money.format(12.3, currency: 'USD'), '\$12.30');
      expect(Money.format(18500, currency: 'UZS'), "18 500 so'm");
      expect(Money.format(-4, currency: 'INR'), '-₹4');
      expect(Money.format(12.3, currency: 'EUR'), 'EUR 12.30');
      expect(Money.format(245.5, currency: 'INR', wholeOnly: true), '₹246');
    });

    test('falls back to the current market currency', () {
      Market.current = Market.india;
      expect(Money.format(80), '₹80');
      expect(Money.symbol(), '₹');
    });
  });
}
