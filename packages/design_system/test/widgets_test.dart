import 'package:design_system/design_system.dart';
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
