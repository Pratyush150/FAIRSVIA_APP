import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rider_app/home_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pump(
    WidgetTester tester,
    Future<List<RideCard>> Function() load, {
    Future<bool> Function(String)? openUrl,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: RideCardsSection(load: load, openUrl: openUrl),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows the live cards with their actions', (tester) async {
    await pump(
      tester,
      () async => const [
        RideCard(
          id: 'a',
          title: '20% off your next ride',
          body: 'This week only.',
          ctaType: 'promo_code',
          ctaLabel: 'Copy code',
          ctaValue: 'SAVE20',
        ),
        RideCard(id: 'b', title: 'Airport rides', body: 'Fixed fares to TAS.'),
      ],
    );
    expect(find.text('20% off your next ride'), findsOneWidget);
    expect(find.text('Airport rides'), findsOneWidget);
    expect(find.text('Copy code'), findsOneWidget);
  });

  testWidgets('a code card copies the code and says so', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    await pump(
      tester,
      () async => const [
        RideCard(
          id: 'a',
          title: 'Promo',
          body: 'x',
          ctaType: 'promo_code',
          ctaLabel: 'Copy code',
          ctaValue: 'SAVE20',
        ),
      ],
    );
    await tester.tap(find.text('Copy code'));
    await tester.pump();
    expect(copied, 'SAVE20');
    expect(find.textContaining('Code SAVE20 copied'), findsOneWidget);
  });

  testWidgets('a link card opens its link', (tester) async {
    final opened = <String>[];
    await pump(
      tester,
      () async => const [
        RideCard(
          id: 'a',
          title: 'News',
          body: 'x',
          ctaType: 'url',
          ctaLabel: 'Read',
          ctaValue: 'https://ridevela.com/news',
        ),
      ],
      openUrl: (u) async {
        opened.add(u);
        return true;
      },
    );
    await tester.tap(find.text('Read'));
    await tester.pump();
    expect(opened, ['https://ridevela.com/news']);
  });

  testWidgets('if content cannot load, the section is simply absent', (
    tester,
  ) async {
    await pump(tester, () async => throw const ApiException('down'));
    expect(find.byType(Container), findsNothing);
  });
}
