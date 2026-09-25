import 'package:flutter/material.dart';

import '../../theme/app_motion.dart';
import '../../theme/app_spacing.dart';
import '../app_sheet.dart';

/// A driver home sheet that rests at its content size (the compact view the
/// driver works from) and can be pulled up — drag, or tap the handle — to a
/// tall view that appends [extras] under the same content: a page's worth of
/// real information, so the pulled-up sheet reads as complete rather than a
/// short card over empty space.
///
/// With no [extras] it is a plain [AppSheet] (not draggable).
class DriverExpandableSheet extends StatefulWidget {
  const DriverExpandableSheet({
    super.key,
    required this.child,
    this.extras = const [],
    this.expandedFraction = 0.9,
    this.initiallyExpanded = false,
  });

  /// The compact content, shown unchanged at rest.
  final Widget child;

  /// Sections shown below [child] once the sheet is pulled up.
  final List<Widget> extras;

  /// Height of the pulled-up sheet as a share of the screen.
  final double expandedFraction;

  /// Start pulled up (tests and screenshots).
  final bool initiallyExpanded;

  @override
  State<DriverExpandableSheet> createState() => _DriverExpandableSheetState();
}

class _DriverExpandableSheetState extends State<DriverExpandableSheet> {
  late bool _expanded = widget.initiallyExpanded;
  final GlobalKey _sheetKey = GlobalKey();

  /// Live height while a drag is in progress; null at rest.
  double? _dragHeight;

  /// Height the compact sheet had when the drag started.
  double _restHeight = 0;

  double _full(BuildContext context) =>
      MediaQuery.sizeOf(context).height * widget.expandedFraction;

  void _toggle() => setState(() {
        _expanded = !_expanded;
        _dragHeight = null;
      });

  void _onDragStart(DragStartDetails _) {
    final box = _sheetKey.currentContext?.findRenderObject() as RenderBox?;
    final h = box?.size.height ?? 0;
    if (!_expanded) _restHeight = h;
    setState(() => _dragHeight = h);
  }

  void _onDragUpdate(DragUpdateDetails d) {
    final full = _full(context);
    final floor = _restHeight > 0 ? _restHeight : 0.0;
    setState(() => _dragHeight =
        ((_dragHeight ?? floor) - d.delta.dy).clamp(floor, full));
  }

  void _onDragEnd(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    final h = _dragHeight ?? 0;
    final mid = (_restHeight + _full(context)) / 2;
    setState(() {
      _expanded = v < -300 ? true : (v > 300 ? false : h > mid);
      _dragHeight = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.extras.isEmpty) return AppSheet(child: widget.child);
    final showExtras = _expanded || _dragHeight != null;
    final height = _dragHeight ?? (_expanded ? _full(context) : null);
    final sheet = AppSheet(
      key: _sheetKey,
      height: height,
      onHandleTap: _toggle,
      handleLabel: _expanded ? 'Collapse' : 'Expand',
      child: AnimatedSize(
        duration: AppMotion.of(context, AppMotion.normal),
        curve: AppMotion.standard,
        alignment: Alignment.topCenter,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            widget.child,
            if (showExtras)
              for (final e in widget.extras) ...[
                const SizedBox(height: AppSpacing.lg),
                e,
              ],
          ],
        ),
      ),
    );
    return PopScope(
      canPop: !_expanded,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _expanded) _toggle();
      },
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onVerticalDragStart: _onDragStart,
        onVerticalDragUpdate: _onDragUpdate,
        onVerticalDragEnd: _onDragEnd,
        child: sheet,
      ),
    );
  }
}
