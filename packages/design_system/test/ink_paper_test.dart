// Plan E — "Ink & Paper" (THEME=ink): the drawing pieces, the fonts it
// bundles, and that every Plan E switch stays off in the other builds.
//
// Runs in every build; CI's theme loop and `flutter test
// --dart-define=THEME=ink` exercise the ink branch.
import 'dart:io';
import 'dart:math' as math;

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ridevela_glyphs_test.dart' show glyphOutlineBytes;

double _contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

Widget _app(Widget child, {bool dark = false, bool reduce = false}) =>
    MaterialApp(
      theme: dark ? AppTheme.dark : AppTheme.light,
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduce),
        child: Scaffold(body: Center(child: child)),
      ),
    );

void main() {
  group('build switch', () {
    test('Plan E is on only in the ink build', () {
      expect(InkPaper.on, AppColors.variant == 'ink');
    });

    test('utility icons: Phosphor Light under ink, Regular elsewhere', () {
      expect(PhosphorIconsRegular.car.fontFamily,
          InkPaper.on
              ? 'PhosphorLight'
              : AppClay3D.on
              ? 'Phosphor3D'
              : 'PhosphorRegular');
      // Same code points in both classes.
      expect(PhosphorIconsLight.car.codePoint, PhosphorIconsRegular.car.codePoint);
      expect(PhosphorIconsLight.autoRickshaw.codePoint,
          PhosphorIconsRegular.autoRickshaw.codePoint);
      expect(PhosphorIconsLight.car.fontFamily, 'PhosphorLight');
    });

    test('vehicle art: the line drawings under ink only', () {
      const top = 'packages/design_system/assets/vehicles/top/xl.png';
      if (InkPaper.on) {
        expect(VehicleGlyph.artSet(false), 'ink');
        expect(VehicleGlyph.artSet(true), 'ink_dark');
        expect(VehicleGlyph.markerAsset(top),
            'packages/design_system/assets/vehicles/ink_top/xl.png');
      } else {
        expect(VehicleGlyph.artSet(false), isNot(startsWith('ink')));
        expect(VehicleGlyph.markerAsset(top), top);
      }
    });

    test('serif moments and section labels fall back outside ink', () {
      const base = TextStyle(fontSize: 22, fontWeight: FontWeight.w600);
      final serif = base.serifMoment(32);
      if (InkPaper.on) {
        expect(serif.fontFamily, InkPaper.serifFamily);
        expect(serif.fontSize, 32);
        // Instrument Serif has one weight, and never goes below 22 pt.
        expect(serif.fontWeight, FontWeight.w400);
      } else {
        expect(serif, same(base));
      }
    });
  });

  group('the assets it needs exist', () {
    for (final set in ['ink', 'ink_dark']) {
      for (final v in ['economy', 'comfort', 'xl', 'premium', 'auto', 'bike', 'driver']) {
        test('$set/$v at 1x and 2x', () {
          expect(File('assets/vehicles/$set/$v.png').existsSync(), isTrue);
          expect(File('assets/vehicles/$set/2.0x/$v.png').existsSync(), isTrue);
        });
      }
    }
    for (final v in ['economy', 'comfort', 'xl', 'premium', 'auto', 'bike', 'driver']) {
      test('ink_top/$v at 1x and 2x', () {
        expect(File('assets/vehicles/ink_top/$v.png').existsSync(), isTrue);
        expect(File('assets/vehicles/ink_top/2.0x/$v.png').existsSync(), isTrue);
      });
    }

    test('Phosphor Light maps every icon the apps use, with an outline', () {
      final ttf = File('fonts/Phosphor-Light.ttf').readAsBytesSync();
      // A spread of the constants, plus both RideVela additions.
      for (final icon in [
        PhosphorIconsLight.car,
        PhosphorIconsLight.x,
        PhosphorIconsLight.mapPin,
        PhosphorIconsLight.receipt,
        PhosphorIconsLight.shieldCheck,
        PhosphorIconsLight.motorcycle,
        PhosphorIconsLight.autoRickshaw,
        PhosphorIconsLight.cashRupee,
      ]) {
        expect(glyphOutlineBytes(ttf, icon.codePoint), greaterThan(0),
            reason: '0x${icon.codePoint.toRadixString(16)}');
      }
    });

    test('the caps and serif fonts are bundled with their licences', () {
      for (final f in [
        'fonts/InstrumentSerif-Regular.ttf',
        'fonts/InstrumentSerif-Italic.ttf',
        'fonts/InstrumentSerif-LICENSE.txt',
        'fonts/RideVelaCaps-SemiBold.ttf',
        'fonts/Phosphor-Light.ttf',
      ]) {
        expect(File(f).existsSync(), isTrue, reason: f);
      }
      // The caps font draws "a" with the glyph of "A".
      final caps = File('fonts/RideVelaCaps-SemiBold.ttf').readAsBytesSync();
      expect(glyphOutlineBytes(caps, 0x61), glyphOutlineBytes(caps, 0x41));
    });
  });

  group('contrast (Plan E tokens, computed)', () {
    for (final dark in [false, true]) {
      final paper = InkPaper.paper(dark);
      final sheet = dark ? AppColors.surfaceDark : AppColors.surfaceLight;
      test('dark=$dark', () {
        // Small-caps labels are text: AA 4.5:1 on paper and on the sheet.
        final label = InkPaper.label(dark).color!;
        expect(_contrast(label, paper), greaterThan(4.5));
        expect(_contrast(label, sheet), greaterThan(4.5));
        // Outlines are a control's only edge: 3:1 non-text.
        expect(_contrast(InkPaper.outline(dark), paper), greaterThan(3));
        expect(_contrast(InkPaper.outline(dark), sheet), greaterThan(3));
        // Ink on paper.
        expect(_contrast(InkPaper.ink(dark), paper), greaterThan(7));
        if (InkPaper.on) {
          // Teal is used for the selection mark and links: AA on the sheet.
          expect(_contrast(InkPaper.teal(dark), sheet), greaterThan(4.5));
          // The primary button is ink with a white (or ink) label.
          expect(_contrast(AppColors.onInkFor(dark), AppColors.inkFor(dark)),
              greaterThan(15));
        }
      });
    }
  });

  group('widgets', () {
    testWidgets('LeaderLine: label and value read, the dots do not',
        (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_app(const SizedBox(
          width: 300, child: LeaderLine(label: 'Base fare', value: '₹40'))));
      expect(find.text('Base fare'), findsOneWidget);
      expect(find.text('₹40'), findsOneWidget);
      final value = tester.getRect(find.text('₹40'));
      // The amount is flush right (a column of amounts lines up).
      expect(value.right, closeTo(tester.getRect(find.byType(LeaderLine)).right, 0.5));
      expect(tester.takeException(), isNull);
      handle.dispose();
    });

    testWidgets('TicketPaper draws its child; its edge is perforated',
        (tester) async {
      await tester.pumpWidget(_app(const SizedBox(
          width: 300, child: TicketPaper(child: Text('Total')))));
      expect(find.text('Total'), findsOneWidget);
      // The outline punches holes along the top edge only.
      final path = ticketPath(const Size(300, 120));
      expect(path.contains(const Offset(150, 1)), isFalse,
          reason: 'a hole is centred on the middle of the top edge');
      expect(path.contains(const Offset(150, 60)), isTrue);
    });

    testWidgets('BalancedText keeps the string and the line count, narrower',
        (tester) async {
      const text = 'Rahul arriving in 3 min';
      const style = TextStyle(fontSize: 32);
      await tester.pumpWidget(_app(const SizedBox(
          width: 220, child: BalancedText(text, style: style))));
      expect(find.text(text), findsOneWidget);
      final w = tester.getSize(find.text(text)).width;
      expect(w, lessThanOrEqualTo(220));
      await tester.pumpWidget(_app(const SizedBox(
          width: 220, child: Text(text, style: style))));
      final lines = tester.getSize(find.text(text)).height;
      await tester.pumpWidget(_app(const SizedBox(
          width: 220, child: BalancedText(text, style: style))));
      expect(tester.getSize(find.text(text)).height, lines,
          reason: 'balanced, not an extra line');
    });

    testWidgets('MarkerUnderline appears at once under Reduce Motion',
        (tester) async {
      await tester.pumpWidget(_app(
          const MarkerUnderline(visible: true, child: Text('Economy')),
          reduce: true));
      await tester.pump();
      final paint = tester.widget<CustomPaint>(find.descendant(
          of: find.byType(MarkerUnderline), matching: find.byType(CustomPaint)));
      expect(paint.foregroundPainter, isNotNull);
    });

    testWidgets('icon badge: hairline ring under ink, tinted disc elsewhere',
        (tester) async {
      await tester.pumpWidget(
          _app(const AppIconBadge(icon: PhosphorIconsRegular.house)));
      final box = tester.widget<Container>(find.descendant(
          of: find.byType(AppIconBadge), matching: find.byType(Container)));
      final deco = box.decoration! as BoxDecoration;
      // Plan F draws its own glass bead (tested in glass_test.dart).
      if (AppGlass.enabled) return;
      if (InkPaper.on) {
        expect(deco.color, isNull);
        expect(deco.border, isNotNull);
      } else {
        expect(deco.color, isNotNull);
      }
      // Still 40 px (rule 5; 44 under clay3d) and decorative.
      expect(tester.getSize(find.byType(AppIconBadge)),
          const Size.square(AppIconBadge.size));
      expect(AppIconBadge.size, AppClay3D.on ? 44 : 40);
      expect(
          tester.getSemantics(find.byType(AppIconBadge)).label, isEmpty);
    });
  });
}
