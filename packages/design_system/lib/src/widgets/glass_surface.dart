import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/app_glass.dart';

/// A frosted-glass panel (Plan F "Map Glass"): whatever is painted behind it
/// (the map) is blurred (σ [AppGlass.blurSigma]) and slightly saturated, then
/// tinted with the glass fill; a 1 px rim catches the light along the top
/// edge, and a soft shadow is drawn *outside* the shape only, so it never
/// greys the glass from underneath.
///
/// Under [AppGlass.solidFallback] (high contrast) it draws
/// [AppGlass.solid] with no blur at all.
///
/// [presence] (0–1) fades the whole treatment in and out — fill, rim, shadow
/// and blur together — so a sheet can dissolve into the map and back (the
/// idle "Where to?" pill floats alone, then the card condenses around the
/// next phase). At 0 no [BackdropFilter] is built at all.
///
/// Cost: every instance is one backdrop-filter pass over its own area. Keep
/// glass to floating chrome (sheet, pills, map buttons), never full-screen.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(
      Radius.circular(AppGlass.sheetRadius),
    ),
    this.strong = false,
    this.presence = 1,
    this.shadow = true,
  });

  final Widget child;
  final BorderRadius borderRadius;

  /// Use glass.fill.strong (84 %) — for glass that carries text blocks.
  final bool strong;
  final double presence;
  final bool shadow;

  /// Saturation boost applied to the blurred backdrop, so the city reads as
  /// coloured light through the glass instead of grey fog (the Liquid Glass
  /// look). 1 = unchanged.
  static const double saturation = 1.6;

  static List<double> _saturate(double s) {
    const r = 0.2126, g = 0.7152, b = 0.0722;
    final i = 1 - s;
    return [
      r * i + s, g * i, b * i, 0, 0, //
      r * i, g * i + s, b * i, 0, 0, //
      r * i, g * i, b * i + s, 0, 0, //
      0, 0, 0, 1, 0, //
    ];
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final solid = AppGlass.solidFallback(context);
    final p = presence.clamp(0.0, 1.0);
    final base = solid
        ? AppGlass.solid(dark)
        : (strong ? AppGlass.fillStrong(dark) : AppGlass.fill(dark));
    Widget body = CustomPaint(
      painter: _FillPainter(
        borderRadius: borderRadius,
        target: base,
        dark: dark,
        presence: p,
        solid: solid,
      ),
      child: child,
    );
    body = CustomPaint(
      foregroundPainter: _RimPainter(
        borderRadius: borderRadius,
        dark: dark,
        presence: p,
        solid: solid,
      ),
      child: body,
    );
    if (!solid && p > 0) {
      body = BackdropFilter(
        filter: ui.ImageFilter.compose(
          outer: ColorFilter.matrix(_saturate(1 + (saturation - 1) * p)),
          inner: ui.ImageFilter.blur(
            sigmaX: AppGlass.blurSigma * p,
            sigmaY: AppGlass.blurSigma * p,
            tileMode: TileMode.mirror,
          ),
        ),
        child: body,
      );
    }
    body = ClipRRect(borderRadius: borderRadius, child: body);
    if (shadow && p > 0) {
      body = CustomPaint(
        painter: _OuterShadowPainter(
          borderRadius: borderRadius,
          dark: dark,
          presence: p,
        ),
        child: body,
      );
    }
    return body;
  }
}

/// The glass body. Solid fallback: one flat fill. Glass: the edge band
/// ([edgeBand] px) is thinner — the map shows through it more, like light
/// bending through the rim of a lens — and the fill feathers up to the full
/// [target] alpha before any content starts (sheet content sits ≥ 20 px in),
/// so text always sits on the specified fill. A faint white sheen lights the
/// top of the panel.
class _FillPainter extends CustomPainter {
  _FillPainter({
    required this.borderRadius,
    required this.target,
    required this.dark,
    required this.presence,
    required this.solid,
  });

  final BorderRadius borderRadius;
  final Color target;
  final bool dark;
  final double presence;
  final bool solid;

  /// Alpha of the fill right at the edge.
  static const double edgeAlpha = 0.55;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = borderRadius.toRRect(rect);
    if (solid) {
      canvas.drawRRect(rrect, Paint()..color = target);
      return;
    }
    final opaque = target.withValues(alpha: 1);
    final edge = edgeAlpha < target.a ? edgeAlpha : target.a;
    canvas.drawRRect(
      rrect,
      Paint()..color = opaque.withValues(alpha: edge * presence),
    );
    // Interior layer: brings the composite from `edge` up to `target.a`.
    final extra = edge >= target.a ? 0.0 : 1 - (1 - target.a) / (1 - edge);
    if (extra > 0) {
      final band = (size.shortestSide * 0.2).clamp(4.0, 12.0);
      final inner = rrect.deflate(band);
      canvas.drawRRect(
        inner,
        Paint()
          ..color = opaque.withValues(alpha: extra * presence)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, band / 3),
      );
    }
    // Sheen across the top.
    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = ui.Gradient.linear(
          rect.topCenter,
          Offset(rect.center.dx, rect.top + (size.height * 0.5).clamp(0, 90)),
          [
            Colors.white.withValues(alpha: (dark ? 0.06 : 0.30) * presence),
            Colors.white.withValues(alpha: 0),
          ],
        ),
    );
  }

  @override
  bool shouldRepaint(_FillPainter old) =>
      old.borderRadius != borderRadius ||
      old.target != target ||
      old.dark != dark ||
      old.presence != presence ||
      old.solid != solid;
}

/// The glass edge: a 1 px stroke that is bright along the top (the rim
/// highlight) and fades to a faint line down the sides and bottom, so the
/// panel reads as a lens rather than a flat card.
class _RimPainter extends CustomPainter {
  _RimPainter({
    required this.borderRadius,
    required this.dark,
    required this.presence,
    required this.solid,
  });

  final BorderRadius borderRadius;
  final bool dark;
  final double presence;
  final bool solid;

  @override
  void paint(Canvas canvas, Size size) {
    if (presence <= 0) return;
    final rect = (Offset.zero & size).deflate(0.5);
    final rrect = borderRadius.toRRect(rect);
    final top = AppGlass.rim(dark);
    final Paint stroke;
    if (solid) {
      // Solid fallback: a plain hairline so the panel still has an edge.
      stroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = (dark ? const Color(0x33FFFFFF) : const Color(0x1F000000));
    } else {
      final low = top.withValues(alpha: top.a * 0.28);
      stroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = ui.Gradient.linear(
          rect.topCenter,
          rect.bottomCenter,
          [
            top.withValues(alpha: top.a * presence),
            low.withValues(alpha: low.a * presence),
            low.withValues(alpha: low.a * presence * 0.6),
          ],
          [0, 0.35, 1],
        );
    }
    canvas.drawRRect(rrect, stroke);
    if (!solid) {
      // Inner glow just inside the rim: the bright edge a lens shows where
      // light bends through it. Strongest along the top, faint at the bottom.
      final glowRect = rect.deflate(1.5);
      canvas.drawRRect(
        borderRadius.toRRect(glowRect),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.4)
          ..shader =
              ui.Gradient.linear(glowRect.topCenter, glowRect.bottomCenter, [
                Colors.white.withValues(alpha: (dark ? 0.10 : 0.70) * presence),
                Colors.white.withValues(alpha: (dark ? 0.03 : 0.30) * presence),
              ]),
      );
    }
    if (!solid && !dark) {
      // Light mode: a whisper-thin dark outline outside the rim so white glass
      // keeps its silhouette over pale map areas (parks, sand, fog).
      canvas.drawRRect(
        borderRadius.toRRect(Offset.zero & size),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.5
          ..color = Color.fromRGBO(15, 20, 23, 0.10 * presence),
      );
    }
  }

  @override
  bool shouldRepaint(_RimPainter old) =>
      old.borderRadius != borderRadius ||
      old.dark != dark ||
      old.presence != presence ||
      old.solid != solid;
}

/// A soft drop shadow painted only outside the shape: a normal box shadow
/// would sit under the translucent glass and show through it as a grey smear.
class _OuterShadowPainter extends CustomPainter {
  _OuterShadowPainter({
    required this.borderRadius,
    required this.dark,
    required this.presence,
  });

  final BorderRadius borderRadius;
  final bool dark;
  final double presence;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = borderRadius.toRRect(rect);
    canvas.save();
    canvas.clipPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(rect.inflate(80)),
        Path()..addRRect(rrect),
      ),
    );
    // Small pieces (map buttons, pills) cast a smaller, lighter shadow than
    // a sheet, so stacked glass does not muddy the gap between pieces.
    final small = size.height < 80;
    final a = (dark ? 0.45 : 0.16) * (small ? 0.7 : 1);
    canvas.drawRRect(
      rrect.shift(Offset(0, small ? 4 : 10)),
      Paint()
        ..color = Color.fromRGBO(8, 14, 20, a * presence)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, small ? 8 : 18),
    );
    canvas.drawRRect(
      rrect.shift(const Offset(0, 1)),
      Paint()
        ..color = Color.fromRGBO(8, 14, 20, a * 0.5 * presence)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_OuterShadowPainter old) =>
      old.borderRadius != borderRadius ||
      old.dark != dark ||
      old.presence != presence;
}
