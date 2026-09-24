part of 'ride_sheets.dart';

/// Plan F "Map Glass" (`THEME=glass` only): the same phase sheets, carried
/// by one floating glass card that *morphs* between phases instead of
/// cross-fading whole sheets.
///
/// - Home: no card at all — the "Where to?" pill floats over the map on its
///   own, saved places in a small glass card under it.
/// - Driver on the way / arrived / on trip: map-first. The card opens
///   compact ([kGlassCompactFraction] of the screen: the status, the car and
///   plate, the PIN) and the handle expands it to the full sheet — same
///   content, same order, it only scrolls less.
/// - The card's size springs between phases ([GlassSpringCurve]) while the
///   content swaps inside it; under Reduce Motion the size snaps and the
///   content cross-fades.

/// Share of the screen the compact live-ride card takes.
const double kGlassCompactFraction = 0.40;

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
  });

  final TripState state;
  final Widget child;
  final Widget? footer;
  final bool chromeless;

  @override
  State<_GlassPhaseSheet> createState() => _GlassPhaseSheetState();
}

class _GlassPhaseSheetState extends State<_GlassPhaseSheet> {
  bool _expanded = false;

  @override
  void didUpdateWidget(_GlassPhaseSheet old) {
    super.didUpdateWidget(old);
    // Each live phase opens compact again: the map is the point of it.
    if (old.state.phase != widget.state.phase) _expanded = false;
  }

  void _toggle() => setState(() => _expanded = !_expanded);

  @override
  Widget build(BuildContext context) {
    final phase = widget.state.phase;
    final compactable = _glassCompactPhase(phase);
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
    return AppSheet(
      chromeless: widget.chromeless,
      handle: !widget.chromeless,
      maxHeightFraction: phase == TripPhase.choosingRide
          ? kRideOptionsSheetFraction
          : compactable && !_expanded
          ? kGlassCompactFraction
          : null,
      onHandleTap: compactable ? _toggle : null,
      handleLabel: compactable
          ? (_expanded ? 'Show less' : 'Show more ride details')
          : null,
      onHandleDrag: compactable
          ? (v) {
              if (v < -200 && !_expanded) setState(() => _expanded = true);
              if (v > 200 && _expanded) setState(() => _expanded = false);
            }
          : null,
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
