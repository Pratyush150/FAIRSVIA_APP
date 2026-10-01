import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('tripShareText', () {
    test('place, car, plate and driver', () {
      expect(
        tripShareText(
          brand: 'FAIRSVIA',
          destination: 'Chorsu Bazaar',
          vehicle: 'White Chevrolet Cobalt',
          plate: '01 A 123 BC',
          driverName: 'Bekzod',
        ),
        "I'm on a FAIRSVIA ride to Chorsu Bazaar. Car: White Chevrolet "
        'Cobalt, plate 01 A 123 BC. Driver: Bekzod.',
      );
    });

    test('no invented tracking link; missing pieces are left out', () {
      final text = tripShareText(brand: 'FAIRSVIA');
      expect(text, "I'm on a FAIRSVIA ride to my destination.");
      expect(text, isNot(contains('http')));
    });

    test('a real tracking link is appended', () {
      expect(
        tripShareText(
          brand: 'FAIRSVIA',
          destination: 'Home',
          trackingUrl: 'https://example.test/t/abc',
        ),
        "I'm on a FAIRSVIA ride to Home. Track my ride live: https://example.test/t/abc",
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

      await tapShare(tester, "I'm on a FAIRSVIA ride to Home.");

      expect(shared, ["I'm on a FAIRSVIA ride to Home."]);
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

  group('shareTripTextWithLink', () {
    late TripTextSharer original;
    setUp(() => original = tripTextSharer);
    tearDown(() => tripTextSharer = original);

    Future<List<String>> tapShare(
      WidgetTester tester,
      Future<String?> Function() fetchLink, {
      Duration timeout = const Duration(seconds: 4),
    }) async {
      final shared = <String>[];
      tripTextSharer = (text, origin) async => shared.add(text);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => shareTripTextWithLink(
                context,
                "I'm on a FAIRSVIA ride to Home.",
                fetchLink: fetchLink,
                timeout: timeout,
              ),
              child: const Text('Share'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('Share'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 5));
      return shared;
    }

    testWidgets('includes the live link when the backend issues one', (
      tester,
    ) async {
      final shared = await tapShare(
        tester,
        () async => 'https://ride.example/api/v1/public/t/abcDEF_-',
      );
      expect(shared, [
        "I'm on a FAIRSVIA ride to Home. Track my ride live: "
            'https://ride.example/api/v1/public/t/abcDEF_-',
      ]);
    });

    testWidgets('still shares, without a link, when the request fails', (
      tester,
    ) async {
      final shared =
          await tapShare(tester, () async => throw Exception('offline'));
      expect(shared, ["I'm on a FAIRSVIA ride to Home."]);
    });

    testWidgets('still shares when the backend has no link (null)', (
      tester,
    ) async {
      final shared = await tapShare(tester, () async => null);
      expect(shared, ["I'm on a FAIRSVIA ride to Home."]);
    });

    testWidgets('does not wait forever on a slow link request', (tester) async {
      final never = Completer<String?>();
      final shared = await tapShare(
        tester,
        () => never.future,
        timeout: const Duration(seconds: 2),
      );
      expect(shared, ["I'm on a FAIRSVIA ride to Home."]);
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
