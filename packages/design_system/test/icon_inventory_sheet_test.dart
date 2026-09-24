// The icon system sheet (audit 2.1): every utility icon the apps render, at
// its real size and in its real container, grouped by screen, light and dark
// side by side — plus the rules checked against the same data.
//
// The data is generated from the source by docs/brand/research/icon_inventory.py
// (re-run it after adding icons). Writing the PNG is opt-in so CI never
// touches docs/:
//
//   ICON_SHEET_OUT=../../docs/brand/research/icon-inventory.png \
//       flutter test test/icon_inventory_sheet_test.dart
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'icon_inventory_data.dart';

/// Fill is for a state only (rule 3). These are the states the apps show.
const _fillStates = {
  'star', // a rating
  'heart', // a favourited driver
  'checkCircle', // selected / done
  'sealCheck', // verified
  'square', // the destination marker on the route rail
  'circle', // an online status dot
  'toggleRight', // a switch that is on
};

double _lum(Color c) {
  double ch(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double _contrast(Color a, Color b) {
  final la = _lum(a), lb = _lum(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

Color _over(Color top, Color bottom) => Color.alphaBlend(top, bottom);

Color _surface(bool dark) =>
    dark ? AppColors.surfaceDark : AppColors.surfaceLight;

Color _roleColor(String role, bool dark) {
  switch (role) {
    case 'brand':
      return AppColors.inkFor(dark);
    case 'danger':
      return AppColors.error;
    case 'success':
      return AppColors.success;
    case 'warning':
      return AppColors.warning;
    case 'star':
      return AppColors.star;
    case 'neutral':
      return AppColors.iconNeutralFor(dark);
    case 'on-dark':
      return Colors.white;
    default:
      return dark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
  }
}

AppIconBadgeTone _tone(String role) => switch (role) {
      'danger' => AppIconBadgeTone.danger,
      'success' => AppIconBadgeTone.success,
      'warning' => AppIconBadgeTone.warning,
      'neutral' => AppIconBadgeTone.neutral,
      _ => AppIconBadgeTone.brand,
    };

bool _sizeOk(InventoryIcon i) =>
    [16.0, 20.0, 24.0].contains(i.size) ||
    ([32.0, 40.0, 48.0].contains(i.size) &&
        (i.container == 'medallion' || i.container == 'plain')) ||
    i.exception.isNotEmpty;

Future<void> _loadFonts() async {
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      loader.addFont(
          File('fonts/$f').readAsBytes().then((b) => b.buffer.asByteData()));
    }
    await loader.load();
  }

  await load('packages/design_system/PhosphorRegular', ['Phosphor-Regular.ttf']);
  await load('packages/design_system/PhosphorFill', ['Phosphor-Fill.ttf']);
  await load('packages/design_system/Inter', [
    'Inter-Regular.ttf',
    'Inter-Medium.ttf',
    'Inter-SemiBold.ttf',
    'Inter-Bold.ttf',
  ]);
}

class _Tile extends StatelessWidget {
  const _Tile(this.i, this.dark);
  final InventoryIcon i;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final color = _roleColor(i.role, dark);
    Widget glyph = Icon(i.icon, size: i.size, color: color);
    switch (i.container) {
      case 'badge':
        glyph = AppIconBadge(icon: i.icon, tone: _tone(i.role));
      case 'medallion':
        glyph = Container(
          width: 64,
          height: 64,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: i.role == 'danger'
                ? (dark ? AppColors.errorSoftDark : AppColors.errorSoft)
                : AppColors.softFor(dark),
            shape: BoxShape.circle,
          ),
          child: Icon(i.icon,
              size: i.size,
              color: i.role == 'danger' ? AppColors.error : AppColors.inkFor(dark)),
        );
      case 'map button':
        glyph = Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _surface(dark),
            shape: BoxShape.circle,
            boxShadow: AppElevation.float,
          ),
          child: Icon(i.icon, size: i.size, color: _roleColor('default', dark)),
        );
      case 'avatar disc':
        glyph = Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _surface(dark),
            shape: BoxShape.circle,
            border: Border.all(
                color: dark ? AppColors.borderDark : AppColors.borderLight),
          ),
          child: Icon(i.icon, size: i.size, color: AppColors.iconNeutralFor(dark)),
        );
      default:
        if (i.role == 'on-dark') {
          glyph = Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppColors.primaryElevated,
              borderRadius: BorderRadius.circular(8),
            ),
            child: glyph,
          );
        }
    }
    final bad = !_sizeOk(i) || (i.fill && !_fillStates.contains(i.name));
    // Stars always sit beside the numeric rating (the words carry it), so
    // their contrast is a documented exception: amber frame, not red.
    final lowContrast = i.container == 'plain' &&
        i.role != 'on-dark' &&
        i.role != 'star' &&
        _contrast(color, _surface(dark)) < 3;
    final softException = i.exception.isNotEmpty ||
        (i.role == 'star' && _contrast(color, _surface(dark)) < 3);
    final text = dark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    return Container(
      width: 96,
      height: 104,
      margin: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          width: bad || lowContrast ? 2 : 1,
          color: bad || lowContrast
              ? AppColors.error
              : softException
                  ? AppColors.warning
                  : (dark ? AppColors.borderDark : AppColors.borderLight),
        ),
      ),
      child: Column(
        children: [
          SizedBox(height: 66, child: Center(child: glyph)),
          Text(i.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontFamily: AppTypography.fontFamily, 
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: dark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight)),
          Text(
              '${i.size.toStringAsFixed(0)} ${i.fill ? 'Fill' : 'Reg'} · '
              '${i.container == 'plain' ? i.role : i.container}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontFamily: AppTypography.fontFamily, fontSize: 9, color: text)),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.dark});
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final screens = <String, List<InventoryIcon>>{};
    for (final i in inventory) {
      (screens[i.screen] ??= []).add(i);
    }
    final ink = dark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final sub = dark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    return Theme(
      data: dark ? AppTheme.dark : AppTheme.light,
      child: Material(
        type: MaterialType.transparency,
        child: Container(
        width: 900,
        color: dark ? AppColors.backgroundDark : AppColors.backgroundLight,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('RideVela icon system · ${dark ? 'dark' : 'light'}',
                style: TextStyle(fontFamily: AppTypography.fontFamily, 
                    fontSize: 22, fontWeight: FontWeight.w700, color: ink)),
            const SizedBox(height: 4),
            Text(
                'Phosphor only · 24 / 20 / 16 (hero 32 / 40 / 48) · Regular, '
                'Fill for a state · one 40 px AppIconBadge · real sizes. '
                'Red frame = breaks a rule; amber = a documented exception.',
                style: TextStyle(fontFamily: AppTypography.fontFamily, fontSize: 12, color: sub)),
            const SizedBox(height: 12),
            // The one container, every tone.
            Row(
              children: [
                for (final t in AppIconBadgeTone.values) ...[
                  AppIconBadge(icon: PhosphorIconsRegular.shieldCheck, tone: t),
                  const SizedBox(width: 6),
                  Text(t.name, style: TextStyle(fontFamily: AppTypography.fontFamily, fontSize: 11, color: sub)),
                  const SizedBox(width: 16),
                ],
              ],
            ),
            for (final e in screens.entries) ...[
              const SizedBox(height: 14),
              Text('${e.key}  (${e.value.length})',
                  style: TextStyle(fontFamily: AppTypography.fontFamily, 
                      fontSize: 14, fontWeight: FontWeight.w700, color: ink)),
              const SizedBox(height: 4),
              Wrap(children: [for (final i in e.value) _Tile(i, dark)]),
            ],
          ],
        ),
      ),
      ),
    );
  }
}

void main() {
  test('every icon is on the size scale (rule 2)', () {
    final off = inventory.where((i) => !_sizeOk(i)).map((i) =>
        '${i.where} ${i.name} ${i.size}');
    expect(off, isEmpty);
  });

  test('Fill is used only for a state (rule 3)', () {
    final misuse = inventory
        .where((i) => i.fill && !_fillStates.contains(i.name))
        .map((i) => '${i.where} ${i.name}');
    expect(misuse, isEmpty);
  });

  test('every AppIconBadge tone clears 3:1 in both modes (rule 7)', () {
    for (final dark in [false, true]) {
      for (final t in AppIconBadgeTone.values) {
        final (fill, glyph) = AppIconBadge.colorsFor(t, dark);
        final bg = _over(fill, _surface(dark));
        expect(_contrast(glyph, bg), greaterThanOrEqualTo(3),
            reason: '${t.name} ${dark ? 'dark' : 'light'}');
      }
    }
  });

  testWidgets('AppIconBadge is 40 px with a 20 px glyph (rule 5)',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Center(child: AppIconBadge(icon: PhosphorIconsRegular.car)),
    ));
    expect(tester.getSize(find.byType(AppIconBadge)), const Size(40, 40));
    expect(tester.widget<Icon>(find.byType(Icon)).size, 20);
  });

  testWidgets('renders the icon system sheet', (tester) async {
    await tester.runAsync(_loadFonts);
    tester.view.physicalSize = const Size(1840, 9000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Align(
        alignment: Alignment.topLeft,
        child: RepaintBoundary(
          key: key,
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [_Panel(dark: false), _Panel(dark: true)],
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final out = Platform.environment['ICON_SHEET_OUT'];
    if (out == null) return;
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      File(out).writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  });
}
