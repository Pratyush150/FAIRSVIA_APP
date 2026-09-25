import 'package:shared_models/shared_models.dart';
import 'package:test/test.dart';

void main() {
  group('FareBreakdown', () {
    test('parses the receipt/trip:completed wire shape', () {
      final b = FareBreakdown.fromJson({
        'baseFare': 2.5,
        'distanceFare': 3.12,
        'timeFare': 1.2,
        'bookingFee': 1.75,
        'surgeMultiplier': 1.2,
        'promoDiscount': 1,
        'tip': 2,
      });
      expect(b.baseFare, 2.5);
      expect(b.distanceFare, 3.12);
      expect(b.timeFare, 1.2);
      expect(b.bookingFee, 1.75);
      expect(b.surgeMultiplier, 1.2);
      expect(b.promoDiscount, 1);
      expect(b.tip, 2);
      expect(b.hasSurge, isTrue);
      expect(b.hasPromo, isTrue);
      expect(b.hasTip, isTrue);
    });

    test('defaults surge to 1x and promo/tip to zero when omitted', () {
      final b = FareBreakdown.fromJson({
        'baseFare': 2.5,
        'distanceFare': 3,
        'timeFare': 1,
        'bookingFee': 1.75,
      });
      expect(b.surgeMultiplier, 1);
      expect(b.hasSurge, isFalse);
      expect(b.hasPromo, isFalse);
      expect(b.hasTip, isFalse);
    });

    test('fromJsonOrNull is null for a null/absent breakdown', () {
      expect(FareBreakdown.fromJsonOrNull(null), isNull);
      expect(FareBreakdown.fromJsonOrNull('x'), isNull);
      expect(FareBreakdown.fromJsonOrNull({'baseFare': 1}), isNotNull);
    });

    test('copyWith(tip) keeps everything else', () {
      const b = FareBreakdown(
        baseFare: 2,
        distanceFare: 3,
        timeFare: 1,
        bookingFee: 1.75,
        surgeMultiplier: 1.5,
        promoDiscount: 0.5,
      );
      final t = b.copyWith(tip: 3);
      expect(t.tip, 3);
      expect(t.surgeMultiplier, 1.5);
      expect(t.promoDiscount, 0.5);
      expect(t.baseFare, 2);
    });

    test('parses how the fare was reached and words it truthfully', () {
      final b = FareBreakdown.fromJson(const {
        'baseFare': 20, 'distanceFare': 50, 'timeFare': 10, 'bookingFee': 5,
        'fareBasis': 'metered', 'fareAdjustment': 0, 'endedEarly': false,
      });
      expect(b.fareBasis, 'metered');
      expect(b.basisNote, 'Metered on the distance and time driven.');
      final early = FareBreakdown.fromJson(const {
        'baseFare': 20, 'distanceFare': 0, 'timeFare': 0, 'bookingFee': 5,
        'minimumFareAdjustment': 50, 'fareBasis': 'minimum',
        'endedEarly': true, 'endReason': 'Safety concern',
      });
      expect(early.basisNote,
          'Trip ended before the drop-off (Safety concern). Minimum fare applied.');
      // Older receipts: no basis, no note (never a guessed "metered").
      expect(FareBreakdown.fromJson(const {'baseFare': 1}).basisNote, isNull);
    });
  });
}
