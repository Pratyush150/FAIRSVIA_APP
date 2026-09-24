import 'package:design_system/design_system.dart';
import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The error banner has one job it must never fail at: showing an error.
///
/// It is installed as `MaterialApp.builder`, which puts it ABOVE the Navigator
/// — so it has no Overlay ancestor. Anything inside it that needs one (a
/// Tooltip, a SelectableText) throws while rendering, replacing the error being
/// reported with its own, and taking the screen down with it.
void main() {
  tearDown(() => lastCaughtError.value = null);

  testWidgets('renders an error with no Overlay ancestor available',
      (tester) async {
    lastCaughtError.value = 'Something went wrong in a widget';

    // Deliberately no Navigator/Overlay anywhere in this tree — the same
    // position ErrorOverlay occupies in the real apps.
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: MediaQueryData(),
          child: ErrorOverlay(child: SizedBox.expand()),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('Something went wrong'), findsOneWidget);
  });

  testWidgets('stays out of the way when there is nothing to report',
      (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: MediaQueryData(),
          child: ErrorOverlay(child: SizedBox.expand()),
        ),
      ),
    );
    await tester.pump();
    expect(find.byIcon(PhosphorIconsRegular.warningCircle), findsNothing);
  });

  testWidgets('can be dismissed', (tester) async {
    lastCaughtError.value = 'boom';
    await tester.pumpWidget(
      const MaterialApp(home: ErrorOverlay(child: SizedBox.expand())),
    );
    await tester.pump();
    expect(find.text('boom'), findsOneWidget);

    await tester.tap(find.byIcon(PhosphorIconsRegular.x));
    await tester.pump();
    expect(find.text('boom'), findsNothing);
  });
}
