import 'package:driver_app/features/driver/completion_note.dart';
import 'package:flutter_test/flutter_test.dart';

/// Owner rule: Complete ends the trip wherever the driver taps. The
/// trip-complete sheet then says, without blocking, how it was charged.
void main() {
  test('ended short of the drop-off: distance + how it was charged', () {
    expect(
      completionNote({
        'breakdown': {
          'fareBasis': 'minimum',
          'endedEarly': true,
          'endedAwayFromDropoffM': 848,
        },
      }),
      'Ended 848 m before the drop-off · minimum fare',
    );
    expect(
      completionNote({
        'breakdown': {
          'fareBasis': 'metered',
          'endedEarly': true,
          'endedAwayFromDropoffM': 2300,
        },
      }),
      'Ended 2.3 km before the drop-off · metered fare',
    );
  });

  test('rider ended it', () {
    expect(
      completionNote({
        'breakdown': {
          'fareBasis': 'metered',
          'endedEarly': true,
          'endReason': 'Rider ended the trip',
        },
      }),
      'The rider ended the trip here · metered fare',
    );
  });

  test('an ordinary drop-off (or an older backend) has no note', () {
    expect(
        completionNote({
          'breakdown': {'fareBasis': 'metered', 'endedEarly': false},
        }),
        isNull);
    expect(completionNote({'fareFinal': 10}), isNull);
  });
}
