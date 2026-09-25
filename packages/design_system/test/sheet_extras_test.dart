import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child, double scale) async {
    tester.view.physicalSize = const Size(360, 1400) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: MediaQuery(
          data: MediaQueryData(
            size: const Size(360, 1400),
            textScaler: TextScaler.linear(scale),
          ),
          child: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: child,
            ),
          ),
        ),
      ),
    );
  }

  final sections = Column(
    children: const [
      SheetSection(
        title: 'Compare rides',
        child: CompareTable(
          columns: ['Seats', 'Pickup', 'Fare'],
          rows: [
            CompareRow(
              label: 'Economy',
              cells: ['4', '3 min', '₹102'],
              highlighted: true,
            ),
            CompareRow(
              label: 'Comfort with a long name',
              cells: ['4', '4 min', '₹1,140'],
            ),
          ],
        ),
      ),
      SheetSection(
        title: 'About this fare',
        child: InfoPoints([
          InfoPoint(icon: Icons.route, title: 'Route', text: '4.2 km'),
          InfoPoint(icon: Icons.info, text: 'Tolls are separate.'),
        ]),
      ),
      SheetSection(
        title: 'Safety',
        card: false,
        child: FeatureGrid([
          FeatureItem(icon: Icons.pin, title: 'Start code', subtitle: 'PIN'),
          FeatureItem(icon: Icons.share, title: 'Share', subtitle: 'Link'),
          FeatureItem(icon: Icons.sos, title: 'SOS', subtitle: 'Contacts'),
        ]),
      ),
    ],
  );

  for (final scale in const [1.0, 1.5, 2.0]) {
    testWidgets('sheet extras lay out at 360 dp ×$scale', (tester) async {
      await pump(tester, sections, scale);
      expect(tester.takeException(), isNull);
      expect(find.text('Compare rides'), findsOneWidget);
      expect(find.text('₹102'), findsOneWidget);
      expect(find.text('Tolls are separate.', findRichText: true),
          findsOneWidget);
      // An odd count still lays out (the last tile alone on its row).
      expect(find.text('SOS'), findsOneWidget);
    });
  }

  testWidgets('a compare row reads as one sentence, selected', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester, sections, 1);
    expect(
      find.bySemanticsLabel(
        'Economy, Seats 4, Pickup 3 min, Fare ₹102',
      ),
      findsOneWidget,
    );
    handle.dispose();
  });
}
