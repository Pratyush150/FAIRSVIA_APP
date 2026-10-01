// Card effects: PressScale's press halo, AppCard's press, SweepBorder's
// light round the "Where to?" bar, and AppListSkeleton inside a list.
// Direct imports (not the barrel) keep this suite independent of unrelated
// widgets exported alongside.
import 'package:design_system/src/theme/app_colors.dart';
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
  setUpAll(() => SweepBorder.debugDisableLoops = true);

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
      // Plan E (THEME=ink) draws no card, only a ruled section, so there is
      // no press halo there; every other look has one.
      expect(
        find.byType(PressScale),
        AppColors.variant == 'ink' ? findsNothing : findsOneWidget,
      );
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
    Widget bar({bool reduce = false}) => _app(
      const SweepBorder(child: SizedBox(width: 300, height: 56)),
      reduce: reduce,
    );

    tearDown(() => SweepBorder.debugDisableLoops = true);

    testWidgets('loops continuously while visible, paused by TickerMode', (
      tester,
    ) async {
      SweepBorder.debugDisableLoops = false;
      await tester.pumpWidget(bar());
      await tester.pump(const Duration(milliseconds: 1200));
      expect(_lit(tester), isTrue);
      // Still turning long after a few laps: it never stops on its own.
      await tester.pump(const Duration(seconds: 30));
      expect(_lit(tester), isTrue);
      expect(tester.binding.hasScheduledFrame, isTrue);
      // Covered route / backgrounded app: the ticker is muted.
      await tester.pumpWidget(
        TickerMode(enabled: false, child: bar()),
      );
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isFalse);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('glow + ring sit over the child in its own repaint layer', (
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
      expect(
        find.descendant(
          of: find.byType(SweepBorder),
          matching: find.byType(DecoratedBox),
        ),
        findsWidgets,
      );
    });

    testWidgets('Reduce Motion: static gradient ring, schedules nothing', (
      tester,
    ) async {
      SweepBorder.debugDisableLoops = false;
      await tester.pumpWidget(bar(reduce: true));
      expect(_lit(tester), isTrue);
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  });

  group('card rim', () {
    testWidgets('rim cards paint a gradient hairline and a resting shadow', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          PressScale(
            rim: true,
            glow: PressScale.brandGlow(false),
            glowRadius: BorderRadius.circular(16),
            child: const SizedBox(width: 120, height: 80),
          ),
        ),
      );
      final box = tester.widget<AnimatedContainer>(
        find.descendant(
          of: find.byType(PressScale),
          matching: find.byType(AnimatedContainer),
        ),
      );
      expect((box.decoration! as BoxDecoration).boxShadow, hasLength(2));
      expect(
        find.descendant(
          of: find.byType(PressScale),
          matching: find.byType(CustomPaint),
        ),
        findsWidgets,
      );
    });

    testWidgets('press glow is clearly visible', (tester) async {
      expect(PressScale.brandGlow(false).a, greaterThanOrEqualTo(0.4));
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
