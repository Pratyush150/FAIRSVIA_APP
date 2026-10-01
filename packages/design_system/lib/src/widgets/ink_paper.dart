import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_ink.dart';
import '../theme/app_motion.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

// Plan E — "Ink & Paper" drawing pieces (THEME=ink). Build-agnostic widgets:
// the call sites decide when to use them (InkPaper.on).

/// A 1 px decorative rule in the Plan E hairline colour (#DAD9D3 / #2E2E2B):
/// what separates sections instead of cards.
class InkRule extends StatelessWidget {
  const InkRule({super.key, this.indent = 0, this.height = 1});

  /// Space before the line starts (a ruled list under its text column).
  final double indent;

  /// Total vertical space; the line sits in the middle.
  final double height;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Divider(
      height: height,
      thickness: 1,
      indent: indent,
      color: InkPaper.rule(dark),
    );
  }
}

/// One line of a printed receipt: `Base fare ........ ₹40.00`.
///
/// The label, a dotted leader that fills the gap, and the amount in tabular
/// figures, right-aligned so a column of amounts lines up like a timetable.
/// The leader is drawing only — it is excluded from semantics, so a reader
/// hears "Base fare, ₹40.00".
class LeaderLine extends StatelessWidget {
  const LeaderLine({
    super.key,
    required this.label,
    required this.value,
    this.style,
    this.valueStyle,
  });

  final String label;
  final String value;
  final TextStyle? style;

  /// Defaults to [style] with tabular figures.
  final TextStyle? valueStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final s = style ?? theme.textTheme.bodyMedium;
    final scaler = MediaQuery.textScalerOf(context);
    final size = (s?.fontSize ?? 15) * scaler.scale(1);
    final vs = valueStyle ?? s?.tabular();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: LayoutBuilder(builder: (context, c) {
        // The label keeps its natural width when the row fits; on a narrow
        // phone at large text it wraps instead of pushing the amount off the
        // edge (the amount always stays whole on its line).
        double widthOf(String t, TextStyle? st) => (TextPainter(
              text: TextSpan(text: t, style: st),
              textScaler: scaler,
              textDirection: Directionality.of(context),
              maxLines: 1,
            )..layout())
                .width;
        final valueW =
            math.min(widthOf(value, vs).ceilToDouble() + 1, c.maxWidth * 0.6);
        final room = (c.maxWidth - valueW - 2 * AppSpacing.sm).floorToDouble();
        final labelW =
            math.max(0.0, math.min(widthOf(label, s).ceilToDouble(), room));
        return _row(context, dark, s, vs, size, labelW, valueW);
      }),
    );
  }

  Widget _row(BuildContext context, bool dark, TextStyle? s, TextStyle? vs,
      double size, double labelW, double valueW) {
    return Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          SizedBox(width: labelW, child: Text(label, style: s)),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: ExcludeSemantics(
              child: Padding(
                // Sit the dots on the text baseline, not the line box bottom.
                padding: EdgeInsets.only(bottom: size * 0.36),
                child: CustomPaint(
                  size: const Size.fromHeight(2),
                  painter: _DotsPainter(
                    color: dark
                        ? const Color(0xFF6A6A64)
                        : const Color(0xFFB4B3AC),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: valueW),
            child: Text(value, style: vs, textAlign: TextAlign.end),
          ),
        ],
      );
  }
}

class _DotsPainter extends CustomPainter {
  _DotsPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color;
    const gap = 4.0;
    final y = size.height / 2;
    // Right-aligned so the dots always meet the amount cleanly.
    for (var x = size.width - 1; x >= 1; x -= gap) {
      canvas.drawCircle(Offset(x, y), 0.8, p);
    }
  }

  @override
  bool shouldRepaint(_DotsPainter old) => old.color != color;
}

/// A paper ticket: the receipt's surface. Paper tone, a hairline outline and
/// a perforated top edge (a row of punched half-circles), like a slip torn
/// off a ticket machine. Put a [TearLine] inside to mark the stub.
class TicketPaper extends StatelessWidget {
  const TicketPaper({
    super.key,
    required this.child,
    this.fill,
    this.padding = const EdgeInsets.fromLTRB(
      AppSpacing.x20,
      AppSpacing.xl,
      AppSpacing.x20,
      AppSpacing.x20,
    ),
  });

  final Widget child;
  final EdgeInsets padding;

  /// The ticket's paper; bg.base (paper) by default, for a ticket on a white
  /// sheet. Give the surface colour when the page itself is paper.
  final Color? fill;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return CustomPaint(
      painter: _TicketPainter(
        fill: fill ?? InkPaper.paper(dark),
        edge: InkPaper.rule(dark),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

/// The outline of [TicketPaper]: straight sides and bottom, a perforated top.
Path ticketPath(Size size) {
  const r = 3.2; // punched hole radius
  const pitch = 11.0; // hole spacing
  final n = math.max(1, ((size.width - 2 * pitch) / pitch).floor());
  final start = (size.width - (n - 1) * pitch) / 2;
  final path = Path()..moveTo(0, 0);
  for (var i = 0; i < n; i++) {
    final cx = start + i * pitch;
    path
      ..lineTo(cx - r, 0)
      ..arcToPoint(
        Offset(cx + r, 0),
        radius: const Radius.circular(r),
        clockwise: false,
      );
  }
  path
    ..lineTo(size.width, 0)
    ..lineTo(size.width, size.height)
    ..lineTo(0, size.height)
    ..close();
  return path;
}

class _TicketPainter extends CustomPainter {
  _TicketPainter({required this.fill, required this.edge});
  final Color fill;
  final Color edge;

  @override
  void paint(Canvas canvas, Size size) {
    final path = ticketPath(size);
    canvas.drawPath(path, Paint()..color = fill);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = edge,
    );
  }

  @override
  bool shouldRepaint(_TicketPainter old) =>
      old.fill != fill || old.edge != edge;
}

/// A dashed hairline across a ticket: the tear line above the total.
class TearLine extends StatelessWidget {
  const TearLine({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ExcludeSemantics(
      child: CustomPaint(
        size: const Size.fromHeight(1),
        painter: _DashPainter(InkPaper.rule(dark)),
      ),
    );
  }
}

class _DashPainter extends CustomPainter {
  _DashPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += 7) {
      canvas.drawLine(
        Offset(x, 0.5),
        Offset(math.min(x + 4, size.width), 0.5),
        p,
      );
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) => old.color != color;
}

/// The Plan E selection mark: a hand-drawn teal underline that draws itself
/// in 200 ms (Reduce Motion: appears at once). Sits under the selected
/// ride type's name. Colour is never the only cue — the row also carries a
/// check and `Semantics(selected: true)`.
class MarkerUnderline extends StatelessWidget {
  const MarkerUnderline({
    super.key,
    required this.child,
    required this.visible,
    this.color,
  });

  final Widget child;
  final bool visible;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final c = color ?? InkPaper.teal(dark);
    return TweenAnimationBuilder<double>(
      tween: Tween(end: visible ? 1 : 0),
      duration: AppMotion.of(context, AppMotion.normal),
      curve: AppMotion.standard,
      child: child,
      builder: (context, t, child) => CustomPaint(
        foregroundPainter: t == 0 ? null : _MarkerPainter(c, t),
        child: Padding(padding: const EdgeInsets.only(bottom: 5), child: child),
      ),
    );
  }
}

class _MarkerPainter extends CustomPainter {
  _MarkerPainter(this.color, this.t);
  final Color color;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    // A slightly rising, slightly bowed stroke — a pen, not a ruler.
    final w = size.width + 4;
    final y = size.height - 1.5;
    final path = Path()
      ..moveTo(-2, y + 0.6)
      ..cubicTo(w * 0.3, y - 0.4, w * 0.62, y + 1.4, w - 2, y - 1.2);
    final metric = path.computeMetrics().first;
    canvas.drawPath(
      metric.extractPath(0, metric.length * t),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_MarkerPainter old) => old.t != t || old.color != color;
}

/// Text whose lines are balanced (CSS `text-wrap: balance`): when [text]
/// needs more than one line, it is laid out at the narrowest width that
/// still gives the same number of lines, so a serif headline breaks as
/// "Rahul arriving / in 3 min" rather than leaving "min" alone on a line.
/// The string is unchanged; only the wrap width moves.
class BalancedText extends StatelessWidget {
  const BalancedText(this.text, {super.key, this.style, this.textAlign});

  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final plain = Text(text, style: style, textAlign: textAlign);
        if (!box.hasBoundedWidth) return plain;
        final painter = TextPainter(
          text: TextSpan(
            text: text,
            style: DefaultTextStyle.of(context).style.merge(style),
          ),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        );
        int lines(double w) {
          painter.layout(maxWidth: w);
          return painter.computeLineMetrics().length;
        }

        final max = box.maxWidth;
        final n = lines(max);
        if (n < 2) {
          painter.dispose();
          return plain;
        }
        var lo = max / 2, hi = max;
        for (var i = 0; i < 12; i++) {
          final mid = (lo + hi) / 2;
          if (lines(mid) > n) {
            lo = mid;
          } else {
            hi = mid;
          }
        }
        painter.dispose();
        final aligned = textAlign == TextAlign.center
            ? Alignment.topCenter
            : Alignment.topLeft;
        return Align(
          alignment: aligned,
          widthFactor: 1,
          child: SizedBox(width: hi.ceilToDouble() + 1, child: plain),
        );
      },
    );
  }
}
