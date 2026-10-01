import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_models/shared_models.dart';

import '../di/injector.dart';
import '../trip/payments_remote_data_source.dart';
import 'format.dart';
import 'support_page.dart';
import 'support_remote_data_source.dart';
import 'widgets/async_content.dart';

/// "Your trip": the detail page for one finished trip, opened from trip
/// history. Top to bottom: a route snapshot (the trip's route drawn to scale
/// over a schematic street pattern, with the distance and time on glass
/// pills), the day and total, the pickup → drop-off timeline, who drove in
/// which car, the fare breakdown and how it was paid (`GET
/// /payments/:id/receipt`), then Share receipt / Get help. The driver's own
/// copy ([showPayout]) names the rider and adds the payout split.
class ReceiptPage extends StatelessWidget {
  const ReceiptPage({
    super.key,
    required this.payments,
    required this.trip,
    this.showPayout = false,
    this.onGetHelp,
  });

  /// The page title.
  static const String title = 'Your trip';

  final PaymentsRemoteDataSource payments;
  final Trip trip;

  /// Driver view shows platform fee + payout; rider view hides them.
  final bool showPayout;

  /// "Get help". Defaults to opening Help & support when the app has
  /// registered its support API; without either, the action is hidden.
  final VoidCallback? onGetHelp;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(title)),
      body: AsyncContent<Receipt>(
        load: () => payments.receipt(trip.id),
        builder: (context, r, _) => _TripDetail(
          trip: trip,
          receipt: r,
          showPayout: showPayout,
          onGetHelp: onGetHelp ?? _defaultHelp(context),
        ),
      ),
    );
  }

  VoidCallback? _defaultHelp(BuildContext context) {
    if (!sl.isRegistered<SupportRemoteDataSource>()) return null;
    return () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => SupportPage(
            support: sl<SupportRemoteDataSource>(),
            isDriver: showPayout,
          ),
        ));
  }
}

Color _mutedOf(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? AppColors.textSecondaryDark
        : AppColors.textSecondaryLight;

/// "economy" → "Economy", "xl" → "XL".
String _tierLabel(String tier) {
  final t = tier.trim();
  if (t.isEmpty) return 'Ride';
  if (t.length <= 2) return t.toUpperCase();
  return t[0].toUpperCase() + t.substring(1).replaceAll('_', ' ');
}

class _TripDetail extends StatelessWidget {
  const _TripDetail({
    required this.trip,
    required this.receipt,
    required this.showPayout,
    required this.onGetHelp,
  });

  final Trip trip;
  final Receipt receipt;
  final bool showPayout;
  final VoidCallback? onGetHelp;

  List<LatLng> get _path {
    final poly = trip.routePolyline;
    if (poly != null && poly.isNotEmpty) {
      try {
        final pts = decodePolyline(poly);
        if (pts.length >= 2) return pts;
      } catch (_) {
        // A malformed polyline falls back to the two ends.
      }
    }
    return [
      LatLng(trip.pickup.point.lat, trip.pickup.point.lng),
      LatLng(trip.dropoff.point.lat, trip.dropoff.point.lng),
    ];
  }

  String _shareText() {
    final r = receipt;
    final when = trip.completedAt ?? trip.scheduledAt ?? trip.requestedAt;
    return [
      '${AppBrand.name} trip receipt',
      if (when != null) Fmt.dateTime(when),
      'From: ${trip.pickup.address ?? 'Pickup'}',
      'To: ${trip.dropoff.address ?? 'Destination'}',
      'Fare: ${Fmt.money(r.chargedAmount ?? r.fare, r.currency)}',
      if (r.tip > 0) 'Tip: ${Fmt.money(r.tip, r.currency)}',
      if (r.isRefunded)
        'Refunded: ${Fmt.money(r.refundedAmount, r.currency)}',
      'Total: ${Fmt.money(r.total, r.currency)}',
      if (r.isCash) 'Paid in cash',
      if (!r.isCash && r.cardLabel != null) 'Paid with ${r.cardLabel}',
    ].join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = _mutedOf(context);
    final r = receipt;
    final when = trip.completedAt ?? trip.scheduledAt ?? trip.requestedAt;
    final meta = [
      if (trip.distanceM != null && trip.distanceM! > 0)
        Fmt.distance(trip.distanceM!),
      if (trip.durationS != null && trip.durationS! > 0)
        Fmt.duration(trip.durationS!),
    ];

    final stops = <RouteTimelineStop>[
      RouteTimelineStop(
          label: 'Pickup', address: trip.pickup.address ?? 'Pickup point'),
      for (var i = 0; i < trip.stops.length; i++)
        RouteTimelineStop(
          label: trip.stops.length == 1 ? 'Stop' : 'Stop ${i + 1}',
          address: trip.stops[i].address ?? 'Stop',
        ),
      RouteTimelineStop(
          label: 'Drop-off',
          address: trip.dropoff.address ?? 'Destination'),
    ];

    final children = <Widget>[
      // --- Route snapshot ------------------------------------------------
      RouteSnapshot(
        path: _path,
        semanticLabel: 'Route map from '
            '${trip.pickup.address ?? 'pickup'} to '
            '${trip.dropoff.address ?? 'destination'}',
        overlay: meta.isEmpty
            ? null
            : Positioned(
                left: AppSpacing.md,
                bottom: AppSpacing.md,
                right: AppSpacing.md,
                child: Align(
                  alignment: Alignment.bottomLeft,
                  child: Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.xs,
                    children: [
                      if (trip.distanceM != null && trip.distanceM! > 0)
                        _MapPill(
                            icon: PhosphorIconsRegular.path,
                            text: Fmt.distance(trip.distanceM!)),
                      if (trip.durationS != null && trip.durationS! > 0)
                        _MapPill(
                            icon: PhosphorIconsRegular.clock,
                            text: Fmt.duration(trip.durationS!)),
                    ],
                  ),
                ),
              ),
      ),
      const SizedBox(height: AppSpacing.lg),

      // --- Summary: when, ride type, total ------------------------------
      _Summary(trip: trip, receipt: r, when: when),
      const SizedBox(height: AppSpacing.lg),

      // --- Route timeline -------------------------------------------------
      _Section(child: RouteTimeline(stops: stops)),

      // --- Driver (or rider) + vehicle -----------------------------------
      if (_PersonCard.hasContent(trip, showPayout)) ...[
        const SizedBox(height: AppSpacing.md),
        _Section(child: _PersonCard(trip: trip, showPayout: showPayout)),
      ],

      // --- Fare + payment ---------------------------------------------------
      const SizedBox(height: AppSpacing.md),
      _Section(
        ticket: InkPaper.on,
        child: _FareCard(receipt: r, showPayout: showPayout),
      ),

      // --- Actions -----------------------------------------------------------
      const SizedBox(height: AppSpacing.lg),
      SecondaryButton(
        label: 'Share receipt',
        icon: PhosphorIconsRegular.export,
        onPressed: () => SharePlus.instance.share(
          ShareParams(text: _shareText(), subject: 'Trip receipt'),
        ),
      ),
      if (onGetHelp != null) ...[
        const SizedBox(height: AppSpacing.sm),
        SecondaryButton(
          label: 'Get help with this trip',
          icon: PhosphorIconsRegular.headset,
          onPressed: onGetHelp,
        ),
      ],
      const SizedBox(height: AppSpacing.sm),
      Text(
        'Trip ID ${trip.id}',
        textAlign: TextAlign.center,
        style: theme.textTheme.bodySmall?.copyWith(color: muted),
      ),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.xl),
      children: children,
    );
  }
}

/// A glass pill over the route snapshot (a solid chip outside Plan F).
class _MapPill extends StatelessWidget {
  const _MapPill({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final content = Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.onSurface),
          const SizedBox(width: 6),
          Text(
            text,
            style: theme.textTheme.labelLarge
                ?.copyWith(fontWeight: FontWeight.w600)
                .tabular(),
          ),
        ],
      ),
    );
    const radius = BorderRadius.all(Radius.circular(AppSpacing.pill));
    if (AppGlass.enabled) {
      return GlassSurface(strong: true, borderRadius: radius, child: content);
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: dark ? 0.9 : 0.95),
        borderRadius: radius,
        boxShadow: AppElevation.sm,
      ),
      child: content,
    );
  }
}

/// One content block of the page: a hairline-outlined card (the ink build's
/// ruled section, or its paper ticket for the fare).
class _Section extends StatelessWidget {
  const _Section({required this.child, this.ticket = false});

  final Widget child;
  final bool ticket;

  @override
  Widget build(BuildContext context) {
    if (ticket) {
      return TicketPaper(fill: Theme.of(context).colorScheme.surface, child: child);
    }
    return AppCard(
      outlined: true,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: child,
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.trip, required this.receipt, required this.when});

  final Trip trip;
  final Receipt receipt;
  final DateTime? when;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = _mutedOf(context);
    final dayLine =
        when == null ? 'Trip' : '${Fmt.dayLabel(when!)} · ${Fmt.time(when)}';
    final sub = [
      _tierLabel(trip.tier),
      if (receipt.isRefunded)
        'Refunded'
      else if (trip.status == TripStatus.completed)
        'Completed',
    ].join(' · ');
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 64,
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: theme.brightness == Brightness.dark
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.black.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          ),
          child: ExcludeSemantics(
            child: VehicleGlyph(tier: trip.tier, width: 56),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                dayLine,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(sub,
                  style: theme.textTheme.bodyMedium?.copyWith(color: muted)),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        // The total never squeezes the date: scales down at large text.
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 120),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Semantics(
              label: 'Total ${Fmt.money(receipt.total, receipt.currency)}',
              excludeSemantics: true,
              child: Text(
                Fmt.money(receipt.total, receipt.currency),
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800)
                    .tabular(),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Who drove (the rider, on the driver's own copy) and in which car.
class _PersonCard extends StatelessWidget {
  const _PersonCard({required this.trip, required this.showPayout});

  final Trip trip;
  final bool showPayout;

  static String? _name(Trip trip, bool showPayout) {
    final n = showPayout
        ? (trip.passenger?.name ?? trip.riderName)
        : trip.driverName;
    final t = n?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }

  static bool hasContent(Trip trip, bool showPayout) =>
      _name(trip, showPayout) != null ||
      (!showPayout &&
          (trip.driverVehicleLabel != null || trip.driverPlate != null));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = _mutedOf(context);
    final dark = theme.brightness == Brightness.dark;
    final name = _name(trip, showPayout);
    final vehicle = showPayout ? null : trip.driverVehicleLabel?.trim();
    final plate = showPayout ? null : trip.driverPlate?.trim();
    final rating = trip.myRating;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            AppAvatar(
              name: name,
              imageUrl: showPayout ? null : trip.driverAvatarUrl,
              size: 48,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name ?? (showPayout ? 'Your rider' : 'Your driver'),
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  if (rating != null && rating > 0)
                    Semantics(
                      label: 'You rated $rating out of 5',
                      excludeSemantics: true,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (var i = 1; i <= 5; i++)
                            Icon(
                              i <= rating
                                  ? PhosphorIconsFill.star
                                  : PhosphorIconsRegular.star,
                              size: 14,
                              color: i <= rating
                                  ? AppColors.star
                                  : AppColors.iconNeutralFor(dark),
                            ),
                        ],
                      ),
                    )
                  else
                    Text(
                      showPayout ? 'Your rider' : 'Your driver',
                      style:
                          theme.textTheme.bodyMedium?.copyWith(color: muted),
                    ),
                ],
              ),
            ),
          ],
        ),
        if ((vehicle != null && vehicle.isNotEmpty) ||
            (plate != null && plate.isNotEmpty)) ...[
          Divider(height: AppSpacing.xl, color: theme.dividerColor),
          Row(
            children: [
              Icon(PhosphorIconsRegular.car,
                  size: 20, color: AppColors.iconNeutralFor(dark)),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  (vehicle == null || vehicle.isEmpty)
                      ? _tierLabel(trip.tier)
                      : vehicle,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              if (plate != null && plate.isNotEmpty) ...[
                const SizedBox(width: AppSpacing.sm),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Semantics(
                      label:
                          'Plate ${AppA11y.spell(Market.current.formatPlate(plate))}',
                      excludeSemantics: true,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm, vertical: 4),
                        decoration: BoxDecoration(
                          borderRadius:
                              BorderRadius.circular(AppSpacing.radiusSm),
                          border: Border.all(
                              color: dark
                                  ? AppColors.borderDark
                                  : AppColors.borderLight,
                              width: 1.5),
                        ),
                        child: Text(
                          Market.current.formatPlate(plate),
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

class _FareCard extends StatelessWidget {
  const _FareCard({required this.receipt, required this.showPayout});

  final Receipt receipt;
  final bool showPayout;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final muted = _mutedOf(context);
    final r = receipt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text('Fare breakdown',
              style: InkPaper.on
                  ? inkSectionLabel(context, theme.textTheme.titleMedium)
                  : theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
        ),
        const SizedBox(height: AppSpacing.sm),
        // Itemised lines first (when the backend recorded them), then the
        // authoritative fare — a clamp/minimum can move it off the sum.
        if (r.breakdown != null) ...[
          FareBreakdownRows(
            breakdown: r.breakdown!,
            currency: r.currency,
            showTip: false,
            style: theme.textTheme.bodyMedium?.copyWith(color: muted),
          ),
          Divider(height: AppSpacing.lg, color: theme.dividerColor),
        ],
        _row(context, 'Fare', Fmt.money(r.chargedAmount ?? r.fare, r.currency)),
        if (r.tip > 0) _row(context, 'Tip', Fmt.money(r.tip, r.currency)),
        // Refund sits above the total so "Total" is what was actually paid.
        if (r.isRefunded)
          _row(
            context,
            'Refunded',
            '- ${Fmt.money(r.refundedAmount, r.currency)}',
          ),
        if (InkPaper.on)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: TearLine(),
          )
        else
          Divider(height: AppSpacing.lg, color: theme.dividerColor),
        _row(context, 'Total', Fmt.money(r.total, r.currency), bold: true),
        if (r.isCash || r.cardLabel != null || r.status != null) ...[
          const SizedBox(height: AppSpacing.md),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md, vertical: AppSpacing.sm),
            decoration: BoxDecoration(
              color: dark
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.black.withValues(alpha: 0.035),
              borderRadius: BorderRadius.circular(AppSpacing.radius),
            ),
            child: Row(
              children: [
                Icon(
                  r.isCash
                      ? PhosphorIconsRegular.money
                      : PhosphorIconsRegular.creditCard,
                  size: 20,
                  color: AppColors.iconNeutralFor(dark),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    r.isCash
                        ? 'Paid in cash'
                        : (r.cardLabel != null
                            ? 'Paid with ${r.cardLabel}'
                            : 'Card payment'),
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w500),
                  ),
                ),
                if (r.status != null) ...[
                  const SizedBox(width: AppSpacing.sm),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 120),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: AppStatusChip(
                        label: Fmt.status(r.status!),
                        // Success green text on its tint is under 4.5:1;
                        // only a failure earns colour.
                        tone: r.status == 'failed'
                            ? StatusTone.warning
                            : StatusTone.neutral,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
        if (showPayout && r.driverPayout != null) ...[
          const SizedBox(height: AppSpacing.lg),
          Text('Payout',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: AppSpacing.sm),
          if (r.platformFee != null)
            _row(context, 'Platform fee',
                '- ${Fmt.money(r.platformFee!, r.currency)}'),
          _row(context, 'You earn', Fmt.money(r.driverPayout!, r.currency),
              bold: true),
        ],
      ],
    );
  }

  Widget _row(BuildContext context, String label, String value,
      {bool bold = false}) {
    if (InkPaper.on) return _inkRow(context, label, value, bold: bold);
    final theme = Theme.of(context);
    final style = bold
        ? theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)
        : theme.textTheme.bodyLarge;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label, style: style)),
          const SizedBox(width: AppSpacing.md),
          Text(value, style: style?.tabular()),
        ],
      ),
    );
  }
}

/// THEME=ink (Plan E): receipt lines with dotted leaders; the bold row (the
/// total, the payout) as a small-caps label and a serif amount.
Widget _inkRow(BuildContext context, String label, String value,
    {bool bold = false}) {
  final theme = Theme.of(context);
  if (!bold) {
    return LeaderLine(
        label: label, value: value, style: theme.textTheme.bodyLarge);
  }
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Expanded(
            child: Text(label, style: inkSectionLabel(context, null)
                ?.copyWith(fontSize: 13))),
        // Scales down rather than overflowing on a narrow phone at large text.
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text.rich(inkAmountSpan(value,
                size: 44, color: theme.colorScheme.onSurface)),
          ),
        ),
      ],
    ),
  );
}

/// The itemised lines of a [FareBreakdown]: Base fare, Distance, Time,
/// Booking fee, then Surge (only when > 1×), Promo (−, only when > 0) and Tip
/// (only when > 0 and [showTip]). Base fare, Time and Booking fee are left out
/// when they are zero — a metered auto or bike fare is distance only, and
/// three "₹0" lines above it would only be noise. Shared by the receipt page and the rider's
/// trip-complete sheet so both read the same way.
class FareBreakdownRows extends StatelessWidget {
  const FareBreakdownRows({
    super.key,
    required this.breakdown,
    this.currency,
    this.showTip = true,
    this.style,
  });

  final FareBreakdown breakdown;

  /// The trip's currency; the build's market currency when unknown.
  final String? currency;

  /// Off when the caller already renders a tip line of its own.
  final bool showTip;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final b = breakdown;
    final textStyle = style ?? Theme.of(context).textTheme.bodyMedium;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (b.baseFare != 0)
          _line('Base fare', Fmt.money(b.baseFare, currency), textStyle),
        _line('Distance', Fmt.money(b.distanceFare, currency), textStyle),
        if (b.timeFare != 0)
          _line('Time', Fmt.money(b.timeFare, currency), textStyle),
        if (b.bookingFee != 0)
          _line('Booking fee', Fmt.money(b.bookingFee, currency), textStyle),
        if (b.hasMinimumFare)
          _line('Minimum fare', Fmt.money(b.minimumFareAdjustment, currency),
              textStyle),
        // The quote bounded the metered fare (lifted to 0.8x or capped at
        // 1.5x of it) — never labelled a "minimum fare".
        if (b.hasFareAdjustment)
          _line(
              b.fareAdjustment > 0
                  ? 'Up-front price adjustment'
                  : 'Capped at up-front price',
              b.fareAdjustment > 0
                  ? Fmt.money(b.fareAdjustment, currency)
                  : '−${Fmt.money(-b.fareAdjustment, currency)}',
              textStyle),
        if (b.hasSurge) _line('Surge', Fmt.surge(b.surgeMultiplier), textStyle),
        if (b.hasPromo)
          _line('Promo', '−${Fmt.money(b.promoDiscount, currency)}', textStyle),
        if (showTip && b.hasTip) _line('Tip', Fmt.money(b.tip, currency), textStyle),
        if (b.basisNote != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(b.basisNote!,
                style: Theme.of(context).textTheme.bodySmall),
          ),
      ],
    );
  }

  Widget _line(String label, String value, TextStyle? style) => InkPaper.on
      // THEME=ink: a printed receipt line with a dotted leader.
      ? LeaderLine(label: label, value: value, style: style)
      : Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // The label wraps at large text instead of pushing the amount
            // off the edge.
            Expanded(child: Text(label, style: style)),
            const SizedBox(width: AppSpacing.md),
            Text(value, style: style?.tabular()),
          ],
        ),
      );
}
