part of 'ride_sheets.dart';

/// Draggable booking / ride sheets (owner, 2026-09-25: "whatever pages come
/// while booking or at ride completion should be draggable — they come up
/// when dragged upwards, or else appear at the ratio that was decided").
///
/// Every phase from choosing a ride to ride complete opens at its *rest*
/// size — the share [RiderSheetHeights] sets for it (or its content's height
/// when it has none, e.g. finding a driver). From there:
///
/// - a drag up, or a tap on the handle ("Expand"), pulls it up to the
///   *expanded* size ([RiderSheetHeights.expanded]: below the status bar, a
///   map peek above), where the content scrolls inside it;
/// - a drag down, or the handle again ("Collapse"), takes it back to rest —
///   and never below it, except on trip, which parks at a smaller *peek*
///   (just the status line, [RiderSheetHeights.onTripPeek]);
/// - on release the sheet snaps to the nearest size, or with a fling to the
///   next one in the fling's direction;
/// - Reduce Motion: the sheet snaps without animating.
///
/// The drag is taken anywhere on the sheet, the scrolling content included
/// (Uber / Google Maps): a drag up first grows the sheet to expanded, and
/// only once it is there does the content scroll; a drag down with the
/// content at its top shrinks the sheet (to rest, on trip on to the peek).
/// The sheet's scroll view does this through [_SheetScrollController] — it
/// is handed the controller as its [PrimaryScrollController] — so the same
/// holds under Android clamping and iOS bouncing physics. Any other scroll
/// view nested deeper still moves the sheet once it is scrolled to an end
/// (its overscroll). Pinned footers (Confirm, Done) stay on the sheet's
/// bottom edge at every size.

/// The phases whose sheet can be dragged.
bool _draggablePhase(TripPhase p) => switch (p) {
  TripPhase.choosingRide ||
  TripPhase.searching ||
  TripPhase.driverEnRoute ||
  TripPhase.driverArrived ||
  TripPhase.onTrip => true,
  // A full-screen ride-complete page has nowhere to go.
  TripPhase.completed => !_completedFullScreen(p),
  _ => false,
};

enum _SheetSnap { peek, rest, expanded }

/// Fling speed (logical px/s) past which a release goes to the next size in
/// the fling's direction rather than the nearest one.
const double _kSnapFlingVelocity = 700;

mixin _SheetDrag<T extends StatefulWidget>
    on State<T>, SingleTickerProviderStateMixin<T> {
  /// The phase the sheet is showing (the drag resets on each new phase).
  TripPhase get dragPhase;

  /// Told when the sheet settles on a new size, so the map can re-fit.
  VoidCallback? get onSettled;

  late final AnimationController _snapAnim = AnimationController(
    vsync: this,
    duration: AppMotion.slow,
  );
  Animation<double>? _snapTween;
  _SheetSnap _snap = _SheetSnap.rest;
  _SheetSnap _target = _SheetSnap.rest;

  /// The sheet's height while it is dragged, snapping, or held off its rest
  /// size (peek / expanded). Null: at rest, sized by its phase's share.
  double? _dragHeight;

  /// The rest size in pixels, read off the sheet when a drag starts.
  double? _restPx;

  /// True while an inner scroll view's overscroll is driving the sheet.
  bool _overscrollDrag = false;

  final GlobalKey _dragBoxKey = GlobalKey();

  /// True while a drag on the sheet's scroll view is moving the sheet.
  bool _innerDrag = false;

  /// Handed to the sheet's scroll view: routes its drags to the sheet first.
  late final _SheetScrollController _sheetScroll = _SheetScrollController(
    this,
  );

  /// The height to hand [AppSheet.height] (null: the rest sizing).
  double? get sheetHeight => _dragHeight;

  bool get sheetExpanded => _snap == _SheetSnap.expanded;

  String get handleLabel => sheetExpanded ? 'Collapse' : 'Expand';

  @override
  void initState() {
    super.initState();
    _snapAnim.addListener(() {
      final t = _snapTween;
      if (t != null) setState(() => _dragHeight = t.value);
    });
    _snapAnim.addStatusListener((s) {
      if (s == AnimationStatus.completed) _settle(_target);
    });
  }

  @override
  void dispose() {
    _snapAnim.dispose();
    _sheetScroll.dispose();
    super.dispose();
  }

  /// A new phase opens at its rest size again: the map is the point of it.
  void resetDrag() {
    _snapAnim.stop();
    _snapTween = null;
    _snap = _SheetSnap.rest;
    _target = _SheetSnap.rest;
    _dragHeight = null;
    _restPx = null;
    _overscrollDrag = false;
    _innerDrag = false;
  }

  double get _screenHeight => MediaQuery.sizeOf(context).height;

  double _currentHeight() {
    final box = _dragBoxKey.currentContext?.findRenderObject() as RenderBox?;
    return box != null && box.hasSize ? box.size.height : 0;
  }

  /// Pixel heights of the sizes this phase can rest at, low to high.
  Map<_SheetSnap, double> _snapHeights() {
    final screen = _screenHeight;
    final media = MediaQuery.of(context);
    final heights = RiderSheetHeights.current;
    // AppSheet keeps every sheet below the status bar.
    final cap = screen - media.padding.top - AppSpacing.md;
    var expanded = heights.expandedPx(screen);
    if (expanded > cap) expanded = cap;
    var rest = _restPx ?? _currentHeight();
    if (rest > expanded) rest = expanded;
    return {
      if (dragPhase == TripPhase.onTrip &&
          heights.onTripPeekPx(screen) < rest - 1)
        _SheetSnap.peek: heights.onTripPeekPx(screen),
      _SheetSnap.rest: rest,
      _SheetSnap.expanded: expanded,
    };
  }

  void _beginDrag() {
    _snapAnim.stop();
    _snapTween = null;
    if (_dragHeight == null) {
      final now = _currentHeight();
      _restPx = now;
      _dragHeight = now;
    }
  }

  /// Moves the sheet by [delta] pixels (positive: taller).
  void _dragBy(double delta) {
    final snaps = _snapHeights();
    final low = snaps.values.first;
    final high = snaps.values.last;
    setState(() {
      _dragHeight = ((_dragHeight ?? snaps[_SheetSnap.rest]!) + delta).clamp(
        low,
        high,
      );
    });
  }

  /// Snaps to the nearest size, or with a fling ([velocity] in px/s, negative
  /// = up) to the next size in that direction.
  void _endDrag(double velocity) {
    final snaps = _snapHeights();
    final h = _dragHeight ?? snaps[_SheetSnap.rest]!;
    _SheetSnap pick;
    if (velocity.abs() >= _kSnapFlingVelocity) {
      final up = velocity < 0;
      final ordered = up
          ? snaps.entries.toList()
          : snaps.entries.toList().reversed.toList();
      pick = ordered
          .firstWhere(
            (e) => up ? e.value > h + 1 : e.value < h - 1,
            orElse: () => ordered.last,
          )
          .key;
    } else {
      pick = snaps.entries
          .reduce((a, b) => (a.value - h).abs() <= (b.value - h).abs() ? a : b)
          .key;
    }
    _animateTo(pick, snaps[pick]!);
  }

  void _animateTo(_SheetSnap snap, double px) {
    _target = snap;
    final from = _dragHeight ?? _currentHeight();
    if (AppMotion.reduced(context) || (from - px).abs() < 1) {
      _settle(snap);
      return;
    }
    _snapTween = Tween(
      begin: from,
      end: px,
    ).animate(CurvedAnimation(parent: _snapAnim, curve: AppMotion.standard));
    _snapAnim.forward(from: 0);
  }

  void _settle(_SheetSnap snap) {
    if (!mounted) return;
    final snaps = _snapHeights();
    setState(() {
      _snapTween = null;
      _snap = snap;
      // At rest the phase's own sizing takes over again (it follows the
      // content where the rest size is the content's height).
      _dragHeight = snap == _SheetSnap.rest ? null : snaps[snap];
    });
    onSettled?.call();
  }

  /// The handle: expand, or back to rest from expanded.
  void toggleSheet() {
    _beginDrag();
    final snaps = _snapHeights();
    final to = sheetExpanded ? _SheetSnap.rest : _SheetSnap.expanded;
    _animateTo(to, snaps[to]!);
  }

  /// A drag on the sheet's scroll view, [grow] pixels (positive: finger up,
  /// the sheet taller). Takes what the sheet can use — up until expanded;
  /// down, only while the content is at its top ([contentAtTop]) and until
  /// the lowest size — and returns it; the scroll view gets the rest.
  double _innerTake(double grow, {required bool contentAtTop}) {
    if (!mounted || !_draggablePhase(dragPhase) || grow == 0) return 0;
    if (!contentAtTop && grow < 0) return 0;
    // At rest the rest size is the sheet's size now.
    if (_dragHeight == null) _restPx = _currentHeight();
    final snaps = _snapHeights();
    final h = _dragHeight ?? _restPx!;
    final room = grow > 0 ? snaps.values.last - h : snaps.values.first - h;
    if (room.abs() < 0.5 || room.sign != grow.sign) return 0;
    final take = grow.abs() < room.abs() ? grow : room;
    if (!_innerDrag) {
      _innerDrag = true;
      _beginDrag();
    }
    _dragBy(take);
    return take;
  }

  /// The drag on the sheet's scroll view ended ([velocity]: px/s, negative =
  /// finger up). Snaps the sheet if that drag moved it; returns whether the
  /// sheet is (going) expanded, so the content may take the fling.
  bool? _innerRelease(double velocity) {
    if (!_innerDrag) return null;
    _innerDrag = false;
    _endDrag(velocity);
    return _target == _SheetSnap.expanded;
  }

  bool _onScroll(ScrollNotification n) {
    if (n.metrics.axis != Axis.vertical) return false;
    // The sheet's own scroll view already hands its drags to the sheet.
    if (_innerDrag) return false;
    if (n is OverscrollNotification && n.dragDetails != null) {
      if (!_overscrollDrag) {
        _overscrollDrag = true;
        _beginDrag();
      }
      _dragBy(n.overscroll);
    } else if (n is ScrollEndNotification && _overscrollDrag) {
      _overscrollDrag = false;
      _endDrag(n.dragDetails?.primaryVelocity ?? 0);
    }
    return false;
  }

  /// Wraps the built sheet in the drag: a vertical drag anywhere on it that
  /// an inner scroll view does not take, and its overscroll.
  Widget draggable(Widget sheet) {
    // Every platform (not just the mobile default): the sheet's scroll
    // view takes this controller, which moves the sheet before the content.
    sheet = PrimaryScrollController(
      controller: _sheetScroll,
      automaticallyInheritForPlatforms: TargetPlatform.values.toSet(),
      child: sheet,
    );
    if (!_draggablePhase(dragPhase)) {
      return KeyedSubtree(key: _dragBoxKey, child: sheet);
    }
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: GestureDetector(
        key: _dragBoxKey,
        behavior: HitTestBehavior.translucent,
        // Screen readers get the handle button ("Expand" / "Collapse")
        // instead of scroll actions on the whole sheet.
        excludeFromSemantics: true,
        onVerticalDragStart: (_) => _beginDrag(),
        onVerticalDragUpdate: (d) => _dragBy(-d.delta.dy),
        onVerticalDragEnd: (d) => _endDrag(d.primaryVelocity ?? 0),
        child: sheet,
      ),
    );
  }
}

/// The sheet scroll view's controller: its positions offer every drag to the
/// sheet ([_SheetDrag._innerTake]) before scrolling, and a release to the
/// sheet's snap before any fling of the content.
class _SheetScrollController extends ScrollController {
  _SheetScrollController(this.host) : super(debugLabel: 'ride sheet');

  final _SheetDrag host;

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) => _SheetScrollPosition(
    host: host,
    physics: physics,
    context: context,
    oldPosition: oldPosition,
    debugLabel: debugLabel,
  );
}

class _SheetScrollPosition extends ScrollPositionWithSingleContext {
  _SheetScrollPosition({
    required this.host,
    required super.physics,
    required super.context,
    super.oldPosition,
    super.debugLabel,
  });

  final _SheetDrag host;

  @override
  void applyUserOffset(double delta) {
    // [delta]: the finger's move, positive = down (the sheet shorter).
    final atTop = hasPixels && pixels <= minScrollExtent;
    final taken = host._innerTake(-delta, contentAtTop: atTop);
    final left = delta + taken;
    if (left != 0) super.applyUserOffset(left);
  }

  @override
  void goBallistic(double velocity) {
    // [velocity]: scroll px/s, positive = content forward (finger up).
    final expanded = host._innerRelease(-velocity);
    if (expanded == null) return super.goBallistic(velocity);
    // The drag moved the sheet: its snap takes the fling, unless the sheet
    // is at expanded and the fling runs on up into the content.
    super.goBallistic(expanded && velocity > 0 ? velocity : 0);
  }
}
