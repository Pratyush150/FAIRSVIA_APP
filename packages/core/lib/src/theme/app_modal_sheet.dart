import 'dart:math' as math;

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// The one modal bottom sheet every shared screen opens (audit 2026-09-25,
/// item 8: four container styles). In the shipped Plan F "Map Glass" build it
/// is the same floating glass card as the in-page [AppSheet]: inset
/// [AppGlass.sheetInset] from the screen edges, [AppGlass.sheetRadius]
/// corners on all four sides, a grab handle. Every other build keeps the
/// theme's rounded solid sheet with Material's drag handle.
///
/// The builder's content is responsible for its own padding and, for forms,
/// the keyboard inset (as before).
Future<T?> showAppModalSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  bool useSafeArea = false,
  bool isDismissible = true,
}) {
  if (!AppGlass.enabled) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: isScrollControlled,
      useSafeArea: useSafeArea,
      isDismissible: isDismissible,
      showDragHandle: true,
      builder: builder,
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    useSafeArea: useSafeArea,
    isDismissible: isDismissible,
    showDragHandle: false,
    backgroundColor: Colors.transparent,
    elevation: 0,
    shape: const RoundedRectangleBorder(),
    builder: (ctx) => AppGlassModal(child: builder(ctx)),
  );
}

/// The glass card a modal sheet's content sits in (Plan F). Public so tests
/// and screens can find it; open sheets with [showAppModalSheet].
class AppGlassModal extends StatelessWidget {
  const AppGlassModal({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    // Large text: the float shrinks so rows keep their width (as AppSheet).
    final roomy = media.textScaler.scale(10) <= 13;
    final inset = roomy ? AppGlass.sheetInset : 6.0;
    final bottom = math.max(media.padding.bottom, inset);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: EdgeInsets.fromLTRB(inset, 0, inset, bottom),
      child: GlassSurface(
        strong: true,
        child: MediaQuery.removePadding(
          context: context,
          removeBottom: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ExcludeSemantics(
                child: Center(
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: (dark ? Colors.white : Colors.black)
                          .withValues(alpha: 0.24),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
              Flexible(child: child),
            ],
          ),
        ),
      ),
    );
  }
}
