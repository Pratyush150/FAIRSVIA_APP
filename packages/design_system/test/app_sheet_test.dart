import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('AppSheet never extends under the top safe-area inset', (
    tester,
  ) async {
    const screen = Size(402, 874);
    const topInset = 62.0; // iPhone 17-style status bar + Dynamic Island.
    tester.view.physicalSize = screen;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: screen,
            padding: EdgeInsets.only(top: topInset),
          ),
          child: Scaffold(
            body: Stack(
              children: [
                Align(
                  alignment: Alignment.bottomCenter,
                  child: AppSheet(
                    // Far taller than the screen: must scroll, not overflow.
                    child: Column(
                      children: List.generate(
                        40,
                        (i) => SizedBox(height: 60, child: Text('row $i')),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final sheetRect = tester.getRect(find.byType(AppSheet));
    expect(sheetRect.top, greaterThanOrEqualTo(topInset));
    expect(sheetRect.bottom, screen.height);
    expect(tester.takeException(), isNull);
    // The first row is visible and the last is reachable by scrolling.
    expect(find.text('row 0'), findsOneWidget);
    await tester.drag(find.text('row 0'), const Offset(0, -3000));
    await tester.pumpAndSettle();
    expect(find.text('row 39'), findsOneWidget);
  });

  testWidgets('AppSheet shrink-wraps short content', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: AppSheet(child: SizedBox(height: 80)),
          ),
        ),
      ),
    );
    final rect = tester.getRect(find.byType(AppSheet));
    expect(rect.height, lessThan(200));
  });
}
