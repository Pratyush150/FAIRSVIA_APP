import 'dart:convert';

import 'package:design_system/design_system.dart';
import 'package:design_system/src/widgets/map_styles.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;

Widget _wrap(Widget child) => MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: child),
    );

void main() {
  group('PrimaryButton', () {
    testWidgets('renders its label and fires onPressed', (tester) async {
      var tapped = false;
      await tester.pumpWidget(_wrap(
        PrimaryButton(label: 'Continue', onPressed: () => tapped = true),
      ));
      expect(find.text('Continue'), findsOneWidget);
      await tester.tap(find.byType(PrimaryButton));
      expect(tapped, isTrue);
    });

    testWidgets('shows a spinner and is disabled while loading', (tester) async {
      var tapped = false;
      await tester.pumpWidget(_wrap(
        PrimaryButton(
          label: 'Continue',
          loading: true,
          onPressed: () => tapped = true,
        ),
      ));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tap(find.byType(PrimaryButton));
      expect(tapped, isFalse);
    });

    testWidgets('is disabled when onPressed is null', (tester) async {
      await tester.pumpWidget(_wrap(const PrimaryButton(label: 'Continue')));
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);
    });
  });

  group('OtpInput', () {
    testWidgets('reports changes and fires onCompleted when all boxes filled',
        (tester) async {
      String? completed;
      final changes = <String>[];
      await tester.pumpWidget(_wrap(
        OtpInput(
          length: 4,
          onChanged: changes.add,
          onCompleted: (c) => completed = c,
        ),
      ));

      final fields = find.byType(TextField);
      expect(fields, findsNWidgets(4));

      await tester.enterText(fields.at(0), '1');
      await tester.enterText(fields.at(1), '2');
      await tester.enterText(fields.at(2), '3');
      await tester.enterText(fields.at(3), '4');
      await tester.pump();

      expect(completed, '1234');
      expect(changes.last, '1234');
    });
  });

  group('ConnectionBanner', () {
    testWidgets('is hidden when connected', (tester) async {
      await tester.pumpWidget(_wrap(const ConnectionBanner(connected: true)));
      expect(find.textContaining('Reconnecting'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('shows the reconnecting message when disconnected',
        (tester) async {
      await tester.pumpWidget(_wrap(const ConnectionBanner(connected: false)));
      expect(find.textContaining('Reconnecting'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });

  group('AppMap', () {
    testWidgets('composes a Google map with pickup + dropoff markers',
        (tester) async {
      await tester.pumpWidget(_wrap(SizedBox(
        width: 400,
        height: 600,
        child: AppMap(
          initialCenter: const LatLng(25.7743, -80.1937),
          markers: const [
            AppMapMarker(
              point: LatLng(25.7743, -80.1937),
              kind: MapMarkerKind.pickup,
            ),
            AppMapMarker(
              point: LatLng(25.7806, -80.2420),
              kind: MapMarkerKind.dropoff,
            ),
          ],
        ),
      )));
      await tester.pump();

      // AppMap builds a GoogleMap platform view without throwing. The native map
      // only renders on-device, so this is a build smoke test, not a pixel test.
      expect(find.byType(AppMap), findsOneWidget);
      expect(find.byType(gmaps.GoogleMap), findsOneWidget);
      // Light theme gets the de-cluttered light basemap style.
      final map = tester.widget<gmaps.GoogleMap>(find.byType(gmaps.GoogleMap));
      expect(map.style, mapLightStyle);
    });

    // Regression: no style was ever applied, so the map stayed white in dark
    // mode (light status-bar icons on a light map on iOS).
    testWidgets('builds under the dark theme with the night basemap style',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 600,
            child: AppMap(initialCenter: const LatLng(25.7743, -80.1937)),
          ),
        ),
      ));
      await tester.pump();

      expect(find.byType(AppMap), findsOneWidget);
      final map = tester.widget<gmaps.GoogleMap>(find.byType(gmaps.GoogleMap));
      expect(map.style, mapNightStyle);
    });

    test('map styles are valid Google Maps style JSON arrays', () {
      for (final style in [mapLightStyle, mapNightStyle]) {
        final decoded = jsonDecode(style);
        expect(decoded, isA<List<dynamic>>());
        for (final rule in decoded as List<dynamic>) {
          expect(rule, isA<Map<String, dynamic>>());
          expect((rule as Map)['stylers'], isA<List<dynamic>>());
        }
      }
    });

    // Regression: the "recenter on my location" button was dead unless the GPS
    // fix had moved — LatLng has value equality, so re-storing the same point
    // was indistinguishable from no request (always the case with a mocked
    // location). The sequence token makes every explicit request distinct.
    group('recenterChanged', () {
      const here = LatLng(25.7743, -80.1937);
      AppMap map({LatLng? recenter, int seq = 0, List<LatLng>? fit}) => AppMap(
            initialCenter: here,
            recenter: recenter,
            recenterSeq: seq,
            fitBounds: fit,
          );

      test('same point with a bumped seq is a new request', () {
        expect(
          AppMap.recenterChanged(map(recenter: here), map(recenter: here, seq: 1)),
          isTrue,
        );
      });

      test('same point and same seq is not a request', () {
        expect(
          AppMap.recenterChanged(map(recenter: here), map(recenter: here)),
          isFalse,
        );
      });

      test('a moved point with the same seq still recenters (driver follow)',
          () {
        expect(
          AppMap.recenterChanged(
            map(recenter: here),
            map(recenter: const LatLng(25.78, -80.2)),
          ),
          isTrue,
        );
      });

      test('null recenter is never a request', () {
        expect(AppMap.recenterChanged(map(), map(seq: 1)), isFalse);
      });

      test('suppressed while fitBounds frames two or more points', () {
        const fit = [here, LatLng(25.78, -80.2)];
        expect(
          AppMap.recenterChanged(
            map(recenter: here, fit: fit),
            map(recenter: here, seq: 1, fit: fit),
          ),
          isFalse,
        );
      });
    });
  });

  group('polish widgets', () {
    testWidgets('PulseRadar paints and animates without throwing',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const PulseRadar(size: 64, child: Icon(Icons.local_taxi_rounded)),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500)); // advance the loop
      expect(find.byType(PulseRadar), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('BlurredScrim builds its BackdropFilter and handles taps',
        (tester) async {
      var tapped = false;
      await tester.pumpWidget(_wrap(
        Stack(children: [BlurredScrim(onTap: () => tapped = true)]),
      ));
      await tester.pump(const Duration(milliseconds: 300)); // blur tween in
      expect(find.byType(BackdropFilter), findsOneWidget);
      await tester.tap(find.byType(BlurredScrim));
      expect(tapped, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('AppListSkeleton renders skeleton rows', (tester) async {
      await tester.pumpWidget(_wrap(const AppListSkeleton(rows: 4)));
      await tester.pump();
      expect(find.byType(AppListSkeleton), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
