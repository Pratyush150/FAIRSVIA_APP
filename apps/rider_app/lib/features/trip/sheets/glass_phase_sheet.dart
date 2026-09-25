part of 'ride_sheets.dart';

/// Plan F "Map Glass" (`THEME=glass` only): the same phase sheets, carried
/// by one floating glass card that *morphs* between phases instead of
/// cross-fading whole sheets.
///
/// - Home: no card at all — the "Where to?" pill floats over the map on its
///   own, saved places in a small glass card under it.
/// - Driver on the way / arrived / on trip: map-first. The card opens
///   compact ([RiderSheetHeights.pickupCompact] / [RiderSheetHeights.onTripCompact]
///   of the screen: the status, the car and plate, the PIN).
/// - Choosing a ride: [RiderSheetHeights.chooseRide] of the screen.
/// - Ride complete: the card grows to [RiderSheetHeights.completed] of the
///   screen (a map peek above it; 1.0 is a full-screen page).
/// - Each of those is its rest size; the card drags up to
///   [RiderSheetHeights.expanded] and back ([_SheetDrag]).
/// - The card's size springs between phases ([GlassSpringCurve]) while the
///   content swaps inside it; under Reduce Motion the size snaps and the
///   content cross-fades.

/// The phases that open as a compact card over the map.
bool _glassCompactPhase(TripPhase p) =>
    p == TripPhase.driverEnRoute ||
    p == TripPhase.driverArrived ||
    p == TripPhase.onTrip;

class _GlassPhaseSheet extends StatefulWidget {
  const _GlassPhaseSheet({
    required this.state,
    required this.child,
    required this.footer,
    required this.chromeless,
    this.onSettled,
  });

  final TripState state;
  final Widget child;
  final Widget? footer;
  final bool chromeless;
  final VoidCallback? onSettled;

  @override
  State<_GlassPhaseSheet> createState() => _GlassPhaseSheetState();
}

class _GlassPhaseSheetState extends State<_GlassPhaseSheet>
    with SingleTickerProviderStateMixin, _SheetDrag {
  @override
  TripPhase get dragPhase => widget.state.phase;

  @override
  VoidCallback? get onSettled => widget.onSettled;

  @override
  void didUpdateWidget(_GlassPhaseSheet old) {
    super.didUpdateWidget(old);
    // Each phase opens at its rest size again: the map is the point of it.
    if (old.state.phase != widget.state.phase) resetDrag();
  }

  @override
  Widget build(BuildContext context) {
    final phase = widget.state.phase;
    final compactable = _glassCompactPhase(phase);
    final toggles = _draggablePhase(phase) && !widget.chromeless;
    final heights = RiderSheetHeights.current;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final fixed = _fixedFraction(phase, screenHeight);
    final reduced = AppMotion.reduced(context);
    final switcher = AnimatedSwitcher(
      duration: reduced ? AppMotion.normal : AppMotion.slow,
      switchInCurve: AppMotion.enter,
      switchOutCurve: AppMotion.exit,
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        // The card changes shape; the content only settles into it —
        // a slight scale from the card's bottom edge, no slide.
        child: reduced
            ? child
            : ScaleTransition(
                scale: Tween(begin: 0.96, end: 1.0).animate(anim),
                alignment: Alignment.bottomCenter,
                child: child,
              ),
      ),
      layoutBuilder: (currentChild, previousChildren) => Stack(
        alignment: Alignment.bottomCenter,
        children: [...previousChildren, ?currentChild],
      ),
      child: KeyedSubtree(key: ValueKey(phase), child: widget.child),
    );
    return draggable(
      AppSheet(
        chromeless: widget.chromeless,
        handle: !widget.chromeless,
        // Dragged, snapping, or parked off its rest size (peek / expanded).
        height: sheetHeight,
        maxHeightFraction: compactable
            ? heights.liveCompactAt(
                onTrip: phase == TripPhase.onTrip,
                screenHeight: screenHeight,
              )
            : fixed,
        // Choosing a ride: its set share from the start, however few tiers.
        minHeightFraction: fixed,
        // Ride complete: the card grows into a full-screen page (or nearly).
        fullScreen: _completedFullScreen(phase),
        onHandleTap: toggles ? toggleSheet : null,
        handleLabel: toggles ? handleLabel : null,
        footer: widget.footer,
        child: reduced
            // Reduce Motion: no spring; the card takes its new size at once.
            // (Not an AnimatedSize with a zero duration: in this tree that
            // threw "RenderAnimatedSize was mutated in its own performLayout".)
            ? switcher
            : AnimatedSize(
                duration: AppMotion.slower,
                curve: const GlassSpringCurve(),
                alignment: Alignment.bottomCenter,
                child: switcher,
              ),
      ),
    );
  }
}

/// Plan F home: the "Where to?" pill as its own floating glass pill, and the
/// saved places (same rows, same order) in a glass card under it.
class _FloatingWhereTo extends StatelessWidget {
  const _FloatingWhereTo({required this.pill, required this.savedPlaces});

  final Widget pill;
  final List<Widget> savedPlaces;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlassSurface(
          strong: true,
          borderRadius: BorderRadius.circular(AppSpacing.pill),
          child: pill,
        ),
        if (savedPlaces.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          GlassSurface(
            strong: true,
            borderRadius: BorderRadius.circular(AppGlass.sheetRadius - 4),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: savedPlaces,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
