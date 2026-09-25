import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('tripShareText', () {
    test('place, car, plate and driver', () {
      expect(
        tripShareText(
          brand: 'RideVela',
          destination: 'Chorsu Bazaar',
          vehicle: 'White Chevrolet Cobalt',
          plate: '01 A 123 BC',
          driverName: 'Bekzod',
        ),
        "I'm on a RideVela ride to Chorsu Bazaar. Car: White Chevrolet "
        'Cobalt, plate 01 A 123 BC. Driver: Bekzod.',
      );
    });

    test('no invented tracking link; missing pieces are left out', () {
      final text = tripShareText(brand: 'RideVela');
      expect(text, "I'm on a RideVela ride to my destination.");
      expect(text, isNot(contains('http')));
    });

    test('a real tracking link is appended', () {
      expect(
        tripShareText(
          brand: 'RideVela',
          destination: 'Home',
          trackingUrl: 'https://example.test/t/abc',
        ),
        "I'm on a RideVela ride to Home. Track it live: https://example.test/t/abc",
      );
    });
  });

  group('shareTripText', () {
    late TripTextSharer original;
    setUp(() => original = tripTextSharer);
    tearDown(() => tripTextSharer = original);

    Future<void> tapShare(WidgetTester tester, String text) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => shareTripText(context, text),
              child: const Text('Share'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('Share'));
      await tester.pump();
    }

    testWidgets('opens the native share sheet with the trip text', (
      tester,
    ) async {
      final shared = <String>[];
      tripTextSharer = (text, origin) async => shared.add(text);
      final clipboard = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') clipboard.add(call);
          return null;
        },
      );

      await tapShare(tester, "I'm on a RideVela ride to Home.");

      expect(shared, ["I'm on a RideVela ride to Home."]);
      expect(clipboard, isEmpty); // the clipboard is only a fallback
      expect(find.textContaining('copied'), findsNothing);
    });

    testWidgets('falls back to the clipboard only when sharing throws', (
      tester,
    ) async {
      tripTextSharer = (_, _) async => throw PlatformException(code: 'x');
      final clipboard = <Object?>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard.add((call.arguments as Map)['text']);
          }
          return null;
        },
      );

      await tapShare(tester, 'trip text');

      expect(clipboard, ['trip text']);
      expect(find.textContaining('copied'), findsOneWidget);
    });
  });

  group('dialPhone', () {
    test('dials tel:<number>', () async {
      Uri? launched;
      final ok = await dialPhone('+998 90 111-22-33', launch: (uri) async {
        launched = uri;
        return true;
      });
      expect(ok, isTrue);
      expect(launched.toString(), 'tel:+998901112233');
    });
  });
}
