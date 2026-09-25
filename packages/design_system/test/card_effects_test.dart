// Card effects: PressScale's press halo, AppCard's press, SweepBorder's
// light round the "Where to?" bar, and AppListSkeleton inside a list.
// Direct imports (not the barrel) keep this suite independent of unrelated
// widgets exported alongside.
import 'package:design_system/src/widgets/app_card.dart';
import 'package:design_system/src/widgets/app_skeleton.dart';
import 'package:design_system/src/widgets/home/press_scale.dart';
import 'package:design_system/src/widgets/sweep_border.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget child, {bool reduce = false}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reduce),
    child: Scaffold(body: Center(child: child)),
  ),
);

/// The halo's shadow colour inside [PressScale], or null without a halo.
Color? _haloColor(WidgetTester tester) {
  final boxes = tester.widgetList<AnimatedContainer>(
    find.descendant(
      of: find.byType(PressScale),
      matching: find.byType(AnimatedContainer),
    ),
  );
  if (boxes.isEmpty) return null;
  final d = boxes.first.decoration! as BoxDecoration;
  return d.boxShadow!.single.color;
}

double _scale(WidgetTester tester) => tester
    .widget<AnimatedScale>(
      find.descendant(
        of: find.byType(PressScale),
        matching: find.byType(AnimatedScale),
      ),
    )
    .scale;

/// Whether the SweepBorder's foreground light draws anything now.
bool _lit(WidgetTester tester) {
  final paint = tester.widget<CustomPaint>(
    find
        .descendant(
          of: find.byType(SweepBorder),
          matching: find.byType(CustomPaint),
        )
        .first,
  );
  final painter = paint.foregroundPainter;
  if (painter == null) return false;
  final recorder = _CountingCanvas();
  painter.paint(recorder, const Size(300, 56));
  return recorder.draws > 0;
}

class _CountingCanvas extends Fake implements Canvas {
  int draws = 0;
  @override
  void drawRRect(RRect rrect, Paint paint) => draws++;
}

void main() {
  group('PressScale glow', () {
    Widget tile({bool reduce = false, bool enabled = true}) => _app(
      PressScale(
        enabled: enabled,
        glow: PressScale.brandGlow(false),
        glowRadius: BorderRadius.circular(16),
        child: const SizedBox(width: 120, height: 80),
      ),
      reduce: reduce,
    );

    testWidgets('halo blooms and the card shrinks while held', (tester) async {
      await tester.pumpWidget(tile());
      expect(_haloColor(tester)!.a, 0);
      expect(_scale(tester), 1);

      final g = await tester.startGesture(
        tester.getCenter(find.byType(PressScale)),
      );
      await tester.pump();
      expect(_haloColor(tester), PressScale.brandGlow(false));
      expect(_scale(tester), 0.96);

      await g.up();
      await tester.pumpAndSettle();
      expect(_haloColor(tester)!.a, 0);
      expect(_scale(tester), 1);
    });

    testWidgets('Reduce Motion: no shrink, the halo still answers the press', (
      tester,
    ) async {
      await tester.pumpWidget(tile(reduce: true));
      final g = await tester.startGesture(
        tester.getCenter(find.byType(PressScale)),
      );
      await tester.pump();
      expect(_scale(tester), 1);
      expect(_haloColor(tester), PressScale.brandGlow(false));
      await g.up();
      await tester.pumpAndSettle();
    });

    testWidgets('disabled: no halo at all', (tester) async {
      await tester.pumpWidget(tile(enabled: false));
      expect(_haloColor(tester), isNull);
    });

    testWidgets('dark mode glows a little stronger', (tester) async {
      expect(
        PressScale.brandGlow(true).a,
        greaterThan(PressScale.brandGlow(false).a),
      );
    });
  });

  group('AppCard press', () {
    testWidgets('a tappable card gets the press halo and still taps', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        _app(AppCard(onTap: () => taps++, child: const Text('Card'))),
      );
      expect(find.byType(PressScale), findsOneWidget);
      await tester.tap(find.text('Card'));
      await tester.pumpAndSettle();
      expect(taps, 1);
    });

    testWidgets('a static card has no press effect', (tester) async {
      await tester.pumpWidget(_app(const AppCard(child: Text('Card'))));
      expect(find.byType(PressScale), findsNothing);
    });
  });

  group('SweepBorder', () {
    Widget bar({bool reduce = false, int laps = 2}) => _app(
      SweepBorder(
        laps: laps,
        child: const SizedBox(width: 300, height: 56),
      ),
      reduce: reduce,
    );

    testWidgets('runs its laps, then goes dark and stops ticking', (
      tester,
    ) async {
      await tester.pumpWidget(bar());
      await tester.pump(const Duration(milliseconds: 1200));
      expect(_lit(tester), isTrue);
      // A finite run: pumpAndSettle returns (the Home's tests rely on it).
      await tester.pumpAndSettle();
      expect(_lit(tester), isFalse);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('the light sits in its own repaint layer over the child', (
      tester,
    ) async {
      await tester.pumpWidget(bar());
      expect(
        find.descendant(
          of: find.byType(SweepBorder),
          matching: find.byType(RepaintBoundary),
        ),
        findsWidgets,
      );
      await tester.pumpAndSettle();
    });

    testWidgets('Reduce Motion: draws nothing, schedules nothing', (
      tester,
    ) async {
      await tester.pumpWidget(bar(reduce: true));
      expect(
        find.descendant(
          of: find.byType(SweepBorder),
          matching: find.byType(CustomPaint),
        ),
        findsNothing,
      );
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('a new replayKey runs the laps again', (tester) async {
      Widget keyed(int k) => _app(
        SweepBorder(replayKey: k, child: const SizedBox(width: 300, height: 56)),
      );
      await tester.pumpWidget(keyed(1));
      await tester.pumpAndSettle();
      expect(_lit(tester), isFalse);
      await tester.pumpWidget(keyed(2));
      await tester.pump(const Duration(milliseconds: 800));
      expect(_lit(tester), isTrue);
      await tester.pumpAndSettle();
    });
  });

  testWidgets('AppListSkeleton shrink-wraps inside another list', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        ListView(
          children: const [
            Text('Intro'),
            AppListSkeleton(rows: 2, shrinkWrap: true),
            Text('After'),
          ],
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('After'), findsOneWidget);
  });
}
