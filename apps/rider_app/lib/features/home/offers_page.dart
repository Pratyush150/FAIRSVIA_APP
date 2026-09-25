import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_models/shared_models.dart';
import 'package:skeletonizer/skeletonizer.dart';

/// "Ends 3 Oct" / "Ends today" for an offer's expiry.
String offerExpiryLabel(DateTime when, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final d = when.toLocal();
  if (d.year == n.year && d.month == n.month && d.day == n.day) {
    return 'Ends today';
  }
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final year = d.year == n.year ? '' : ' ${d.year}';
  return 'Ends ${d.day} ${months[d.month - 1]}$year';
}

/// A countdown for an offer ending within a week — "Ends today",
/// "Ends tomorrow", "Ends in 3 days" — or null when it ends later (the date
/// is then shown in the terms line instead) or has no expiry.
String? offerCountdownLabel(DateTime? when, {DateTime? now}) {
  if (when == null) return null;
  final n = now ?? DateTime.now();
  final d = when.toLocal();
  final days = DateTime(
    d.year,
    d.month,
    d.day,
  ).difference(DateTime(n.year, n.month, n.day)).inDays;
  if (days < 0 || days > 7) return null;
  if (days == 0) return 'Ends today';
  if (days == 1) return 'Ends tomorrow';
  return 'Ends in $days days';
}

/// The discount as big type: "50%" / "₹100".
String offerValueLabel(AvailablePromo o) => o.isPercent
    ? '${o.value == o.value.roundToDouble() ? o.value.toStringAsFixed(0) : o.value}%'
    : Money.format(o.value, wholeOnly: true);

/// What a screen reader says for an offer:
/// "50% off, up to ₹100, code WELCOME50, ends 3 Oct".
String offerSemanticLabel(AvailablePromo o, {DateTime? now}) {
  final expiry = o.expiresAt;
  final ends = expiry == null
      ? null
      : (offerCountdownLabel(expiry, now: now) ??
                offerExpiryLabel(expiry, now: now))
            .replaceFirst('Ends', 'ends');
  return [
    o.headline,
    'code ${o.code}',
    if (o.minFare > 0 || o.usesLeftForMe != 1) o.conditions,
    ?ends,
  ].join(', ');
}

/// The terms line under an offer: conditions, plus the end date when no
/// countdown is shown for it.
String _termsLine(AvailablePromo o) {
  final expiry = o.expiresAt;
  return [
    o.conditions,
    if (expiry != null && offerCountdownLabel(expiry) == null)
      offerExpiryLabel(expiry),
  ].join(' · ');
}

const _appliedText = 'Applied — will be used on your next ride';
const _applyText = 'Apply to next ride';

/// The Offers tab: the promos this rider can use right now, from the server.
///
/// The first offer leads as a photo hero with its discount in big type; the
/// rest are coupon "tickets" (a teal stub with the value, a perforated
/// notch, then title, terms, countdown and code). Each has "Apply to next
/// ride" (the next ride sheet then carries the code, priced) and a
/// copyable code chip; the applied one shows a check stripe with Remove.
class OffersPage extends StatefulWidget {
  const OffersPage({
    super.key,
    required this.load,
    required this.onApply,
    required this.onRemove,
    this.selectedCode,
  });

  /// Fetches the offers (throws on a network/API error).
  final Future<List<AvailablePromo>> Function() load;
  final void Function(AvailablePromo offer) onApply;
  final VoidCallback onRemove;

  /// The code already picked for the next ride, if any.
  final String? selectedCode;

  @override
  State<OffersPage> createState() => _OffersPageState();
}

class _OffersPageState extends State<OffersPage> {
  late Future<List<AvailablePromo>> _future = widget.load();

  Future<void> _refresh() async {
    final f = widget.load();
    setState(() {
      _future = f;
    });
    try {
      await f;
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: FutureBuilder<List<AvailablePromo>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const _OffersSkeleton();
            }
            if (snap.hasError) {
              return Column(
                children: [
                  const _OffersHeader(count: null),
                  Expanded(
                    child: EmptyState(
                      icon: PhosphorIconsRegular.cloudSlash,
                      title: "Couldn't load offers",
                      message: 'Check your connection and try again.',
                      action: SecondaryButton(
                        label: 'Try again',
                        onPressed: _refresh,
                      ),
                    ),
                  ),
                ],
              );
            }
            final offers = snap.data ?? const <AvailablePromo>[];
            return RefreshIndicator(
              onRefresh: _refresh,
              child: _OffersList(
                offers: offers,
                selectedCode: widget.selectedCode,
                onApply: widget.onApply,
                onRemove: widget.onRemove,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _OffersHeader extends StatelessWidget {
  const _OffersHeader({required this.count});
  final int? count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = count;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenMargin,
        AppSpacing.lg,
        AppSpacing.screenMargin,
        AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            container: true,
            child: Text(
              'Offers',
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
          ),
          if (c != null && c > 0) ...[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              c == 1
                  ? '1 offer for your next ride'
                  : '$c offers for your next ride',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.textTheme.bodySmall?.color,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _OffersList extends StatelessWidget {
  const _OffersList({
    required this.offers,
    required this.selectedCode,
    required this.onApply,
    required this.onRemove,
    this.skeleton = false,
  });

  final List<AvailablePromo> offers;
  final String? selectedCode;
  final void Function(AvailablePromo offer) onApply;
  final VoidCallback onRemove;
  final bool skeleton;

  @override
  Widget build(BuildContext context) {
    Widget enter(Widget w, int i) => skeleton ? w : w.revealStaggered(i);
    const side = EdgeInsets.symmetric(horizontal: AppSpacing.screenMargin);
    return ListView(
      physics: skeleton
          ? const NeverScrollableScrollPhysics()
          : const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
      children: [
        _OffersHeader(count: skeleton ? null : offers.length),
        if (offers.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: AppSpacing.xxl),
            child: EmptyState(
              icon: PhosphorIconsRegular.tag,
              art: LottieMoment.gift(),
              title: 'No offers right now',
              message: 'New offers will show up here.',
            ),
          )
        else ...[
          enter(
            Padding(
              padding: side,
              child: OfferHero(
                offer: offers.first,
                applied: offers.first.code == selectedCode,
                onApply: () => onApply(offers.first),
                onRemove: onRemove,
              ),
            ),
            0,
          ),
          if (offers.length > 1) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenMargin,
                AppSpacing.xl,
                AppSpacing.screenMargin,
                AppSpacing.md,
              ),
              child: Text(
                'More offers',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            for (var i = 1; i < offers.length; i++)
              enter(
                Padding(
                  padding: side.copyWith(bottom: AppSpacing.md),
                  child: OfferCard(
                    offer: offers[i],
                    applied: offers[i].code == selectedCode,
                    onApply: () => onApply(offers[i]),
                    onRemove: onRemove,
                  ),
                ),
                i,
              ),
          ],
        ],
        if (!skeleton)
          enter(
            const Padding(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.screenMargin,
                AppSpacing.xl,
                AppSpacing.screenMargin,
                0,
              ),
              child: OffersHowItWorks(),
            ),
            offers.length + 1,
          ),
      ],
    );
  }
}

/// The loading state: the real layout, skeletonized, so nothing jumps when
/// the offers arrive.
class _OffersSkeleton extends StatelessWidget {
  const _OffersSkeleton();

  static const _placeholder = AvailablePromo(
    code: 'XXXXXXXX',
    title: 'Loading an offer',
    kind: 'percent',
    value: 20,
    maxDiscount: 100,
  );

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading offers',
      child: ExcludeSemantics(
        child: Skeletonizer(
          child: _OffersList(
            offers: const [_placeholder, _placeholder, _placeholder],
            selectedCode: null,
            onApply: (_) {},
            onRemove: () {},
            skeleton: true,
          ),
        ),
      ),
    );
  }
}

Future<void> _copyCode(BuildContext context, String code) async {
  final messenger = ScaffoldMessenger.of(context);
  AppHaptics.selection();
  await Clipboard.setData(ClipboardData(text: code));
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text('Code $code copied')));
}

/// The featured offer: a photo card with the discount in big type over a
/// scrim, its code and the primary Apply.
class OfferHero extends StatelessWidget {
  const OfferHero({
    super.key,
    required this.offer,
    required this.applied,
    required this.onApply,
    required this.onRemove,
    this.image,
  });

  final AvailablePromo offer;
  final bool applied;
  final VoidCallback onApply;
  final VoidCallback onRemove;

  /// Photo asset; defaults to one of the promo photos, picked by the code so
  /// an offer keeps its picture between visits.
  final String? image;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final photo =
        image ??
        PromoPhoto.all[offer.code.codeUnits.fold<int>(0, (a, b) => a + b) %
            PromoPhoto.all.length];
    final countdown = offerCountdownLabel(offer.expiresAt);
    const onPhoto = Colors.white;
    final radius = BorderRadius.circular(AppSpacing.radiusXl);
    return Semantics(
      container: true,
      label: 'Featured offer: ${offer.title}. ${offerSemanticLabel(offer)}',
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          children: [
            Positioned.fill(
              child: ExcludeSemantics(
                child: Image.asset(
                  photo,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) =>
                      ColoredBox(color: AppColors.inkFor(true)),
                ),
              ),
            ),
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0x59000000),
                      Color(0x8C000000),
                      Color(0xF0000000),
                    ],
                    stops: [0, 0.35, 0.8],
                  ),
                ),
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 248),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    ExcludeSemantics(
                      child: Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.xs,
                        children: [
                          const _PhotoBadge(
                            icon: PhosphorIconsFill.star,
                            label: 'Featured',
                          ),
                          if (countdown != null)
                            _PhotoBadge(
                              icon: PhosphorIconsRegular.hourglass,
                              label: countdown,
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ExcludeSemantics(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                Text(
                                  offerValueLabel(offer),
                                  style: theme.textTheme.displayMedium
                                      ?.copyWith(
                                        color: onPhoto,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: -1.5,
                                        height: 1,
                                      ),
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                Text(
                                  'OFF',
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    color: onPhoto,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        ExcludeSemantics(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                offer.title,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: onPhoto,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.xxs),
                              Text(
                                offer.headline,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: onPhoto.withValues(alpha: 0.85),
                                ),
                              ),
                              Text(
                                _termsLine(offer),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: onPhoto.withValues(alpha: 0.72),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        if (applied)
                          _AppliedStripe(onRemove: onRemove, onPhoto: true)
                        else
                          Wrap(
                            spacing: AppSpacing.sm,
                            runSpacing: AppSpacing.sm,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              _ApplyPill(onPressed: onApply, dark: dark),
                              CodeChip(
                                code: offer.code,
                                onPhoto: true,
                                onCopy: () => _copyCode(context, offer.code),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotoBadge extends StatelessWidget {
  const _PhotoBadge({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xxs + 1,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(AppSpacing.pill),
        border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: AppSpacing.xs),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// One offer as a coupon ticket: a teal stub with the value, a perforated
/// notch, then title, terms, countdown and code. Tap to show the fine print.
class OfferCard extends StatefulWidget {
  const OfferCard({
    super.key,
    required this.offer,
    required this.applied,
    required this.onApply,
    required this.onRemove,
  });

  final AvailablePromo offer;
  final bool applied;
  final VoidCallback onApply;
  final VoidCallback onRemove;

  @override
  State<OfferCard> createState() => _OfferCardState();
}

class _OfferCardState extends State<OfferCard> {
  bool _expanded = false;

  static const double _stub = 92;

  @override
  Widget build(BuildContext context) {
    final offer = widget.offer;
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final muted = theme.textTheme.bodySmall?.color;
    final ink = AppColors.inkFor(dark);
    final onInk = AppColors.onInkFor(dark);
    final countdown = offerCountdownLabel(offer.expiresAt);
    final border = widget.applied
        ? ink
        : (dark ? AppColors.borderDark : AppColors.borderLight);
    final shape = TicketBorder(
      notchX: _stub,
      radius: AppSpacing.radiusLg,
      side: BorderSide(color: border, width: widget.applied ? 1.5 : 1),
    );

    return Semantics(
      container: true,
      label: '${offer.title}. ${offerSemanticLabel(offer)}',
      child: Material(
        color: dark ? AppColors.surfaceDark : AppColors.surfaceLight,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        elevation: dark ? 0 : 1,
        shadowColor: Colors.black.withValues(alpha: 0.25),
        child: InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // The stub: the value in big type on the brand teal.
                ExcludeSemantics(
                  child: Container(
                    width: _stub,
                    color: ink,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: AppSpacing.lg,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (widget.applied) ...[
                          Icon(
                            PhosphorIconsFill.checkCircle,
                            color: onInk,
                            size: 20,
                          ),
                          const SizedBox(height: AppSpacing.xs),
                        ],
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            offerValueLabel(offer),
                            style: theme.textTheme.headlineMedium?.copyWith(
                              color: onInk,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.8,
                              height: 1,
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          'OFF',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: onInk.withValues(alpha: 0.85),
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // The perforation between the notches.
                CustomPaint(
                  size: const Size(0, double.infinity),
                  painter: _PerforationPainter(
                    color: dark ? AppColors.borderDark : AppColors.borderLight,
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md + 2,
                      AppSpacing.md,
                      AppSpacing.md,
                      AppSpacing.md,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ExcludeSemantics(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Text(
                                      offer.title,
                                      style: theme.textTheme.titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  ),
                                  ExcludeSemantics(
                                    child: AnimatedRotation(
                                      turns: _expanded ? 0.5 : 0,
                                      duration: AppMotion.of(
                                        context,
                                        AppMotion.normal,
                                      ),
                                      child: Icon(
                                        PhosphorIconsRegular.caretDown,
                                        size: 18,
                                        color: muted,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: AppSpacing.xxs),
                              Text(
                                offer.headline,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: AppColors.accentTextFor(dark),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.xxs),
                              Text(
                                _termsLine(offer),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: muted,
                                ),
                              ),
                              if (countdown != null) ...[
                                const SizedBox(height: AppSpacing.xs),
                                _CountdownTag(label: countdown),
                              ],
                            ],
                          ),
                        ),
                        AnimatedSize(
                          duration: AppMotion.of(context, AppMotion.normal),
                          curve: AppMotion.standard,
                          alignment: Alignment.topCenter,
                          child: _expanded
                              ? Padding(
                                  padding: const EdgeInsets.only(
                                    top: AppSpacing.sm,
                                  ),
                                  child: Text(
                                    [
                                      if (offer.description != null)
                                        offer.description!,
                                      'One offer per ride. The discount is '
                                          'taken off the fare when you book.',
                                    ].join('\n'),
                                    style: theme.textTheme.bodySmall,
                                  ),
                                )
                              : const SizedBox(width: double.infinity),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        if (widget.applied)
                          _AppliedStripe(onRemove: widget.onRemove)
                        else
                          SizedBox(
                            width: double.infinity,
                            child: Wrap(
                              alignment: WrapAlignment.spaceBetween,
                              spacing: AppSpacing.sm,
                              runSpacing: AppSpacing.sm,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                CodeChip(
                                  code: offer.code,
                                  onCopy: () => _copyCode(context, offer.code),
                                ),
                                _ApplyPill(
                                  onPressed: widget.onApply,
                                  dark: dark,
                                  compact: true,
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CountdownTag extends StatelessWidget {
  const _CountdownTag({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final color = dark ? AppColors.warningDark : AppColors.warning;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(PhosphorIconsRegular.hourglass, size: 14, color: color),
        const SizedBox(width: AppSpacing.xs),
        Flexible(
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _ApplyPill extends StatelessWidget {
  const _ApplyPill({
    required this.onPressed,
    required this.dark,
    this.compact = false,
  });
  final VoidCallback onPressed;
  final bool dark;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: () {
        AppHaptics.light();
        onPressed();
      },
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.inkFor(dark),
        foregroundColor: AppColors.onInkFor(dark),
        shape: const StadiumBorder(),
        minimumSize: Size(0, compact ? 40 : 48),
        padding: EdgeInsets.symmetric(
          horizontal: compact ? AppSpacing.lg : AppSpacing.x20,
        ),
        textStyle: Theme.of(
          context,
        ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
      child: Text(compact ? 'Apply' : _applyText, semanticsLabel: _applyText),
    );
  }
}

/// The applied state: a teal check stripe with Remove.
class _AppliedStripe extends StatelessWidget {
  const _AppliedStripe({required this.onRemove, this.onPhoto = false});
  final VoidCallback onRemove;
  final bool onPhoto;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final ink = AppColors.inkFor(dark);
    final fg = onPhoto ? Colors.white : theme.textTheme.bodyMedium?.color;
    final check = Icon(
      PhosphorIconsFill.checkCircle,
      size: 20,
      color: onPhoto ? Colors.white : ink,
    );
    final label = Text(
      _appliedText,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: fg,
        fontWeight: FontWeight.w600,
      ),
    );
    final remove = TextButton(
      onPressed: onRemove,
      style: onPhoto
          ? TextButton.styleFrom(foregroundColor: Colors.white)
          : null,
      child: const Text('Remove'),
    );
    return Container(
      padding: const EdgeInsets.only(
        left: AppSpacing.md,
        top: AppSpacing.xxs,
        bottom: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        color: onPhoto
            ? Colors.white.withValues(alpha: 0.18)
            : AppColors.softFor(dark),
        border: Border(left: BorderSide(color: ink, width: 4)),
      ),
      child: onPhoto
          ? Row(
              children: [
                check,
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: label),
                remove,
              ],
            )
          : Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.md),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        check,
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(child: label),
                      ],
                    ),
                  ),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: remove,
                  ),
                ],
              ),
            ),
    );
  }
}

/// An offer's code with a copy icon; tap copies it.
class CodeChip extends StatelessWidget {
  const CodeChip({
    super.key,
    required this.code,
    required this.onCopy,
    this.onPhoto = false,
  });
  final String code;
  final VoidCallback onCopy;
  final bool onPhoto;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final fg = onPhoto ? Colors.white : theme.textTheme.bodyLarge?.color;
    return Semantics(
      button: true,
      label: 'Copy code $code',
      onTap: onCopy,
      excludeSemantics: true,
      child: Material(
        color: onPhoto
            ? Colors.white.withValues(alpha: 0.16)
            : AppColors.softFor(dark),
        shape: StadiumBorder(
          side: BorderSide(
            color: onPhoto
                ? Colors.white.withValues(alpha: 0.4)
                : AppColors.inkFor(dark).withValues(alpha: 0.35),
          ),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onCopy,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 40),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        code,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: fg,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs + 2),
                  Icon(PhosphorIconsRegular.copy, size: 16, color: fg),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "How offers work": three one-line steps under the list.
class OffersHowItWorks extends StatelessWidget {
  const OffersHowItWorks({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final muted = theme.textTheme.bodySmall?.color;
    const steps = [
      (PhosphorIconsRegular.tag, 'Pick an offer and tap Apply.'),
      (
        PhosphorIconsRegular.receipt,
        'It is taken off the fare when you book — you see the new price first.',
      ),
      (PhosphorIconsRegular.ticket, 'One offer per ride.'),
    ];
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: dark ? AppColors.surfaceMutedDark : AppColors.surfaceMutedLight,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              'How offers work',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          for (final (icon, text) in steps) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 18, color: AppColors.accentTextFor(dark)),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    text,
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// A rounded ticket with two semicircle notches cut at [notchX] — the tear
/// line between the coupon's stub and its body.
class TicketBorder extends ShapeBorder {
  const TicketBorder({
    required this.notchX,
    this.radius = 16,
    this.notchRadius = 9,
    this.side = BorderSide.none,
  });

  final double notchX;
  final double radius;
  final double notchRadius;
  final BorderSide side;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.width);

  Path _path(Rect rect) {
    final body = Path()
      ..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));
    final x = rect.left + notchX;
    final notches = Path()
      ..addOval(
        Rect.fromCircle(center: Offset(x, rect.top), radius: notchRadius),
      )
      ..addOval(
        Rect.fromCircle(center: Offset(x, rect.bottom), radius: notchRadius),
      );
    return Path.combine(PathOperation.difference, body, notches);
  }

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) => _path(rect);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      _path(rect.deflate(side.width));

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none || side.width == 0) return;
    canvas.drawPath(
      _path(rect.deflate(side.width / 2)),
      side.toPaint()..style = PaintingStyle.stroke,
    );
  }

  @override
  ShapeBorder scale(double t) => TicketBorder(
    notchX: notchX * t,
    radius: radius * t,
    notchRadius: notchRadius * t,
    side: side.scale(t),
  );

  @override
  bool operator ==(Object other) =>
      other is TicketBorder &&
      other.notchX == notchX &&
      other.radius == radius &&
      other.notchRadius == notchRadius &&
      other.side == side;

  @override
  int get hashCode => Object.hash(notchX, radius, notchRadius, side);
}

/// A dashed vertical tear line, clear of the notches at both ends.
class _PerforationPainter extends CustomPainter {
  _PerforationPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    const dash = 5.0, gap = 5.0, inset = 14.0;
    for (var y = inset; y < size.height - inset; y += dash + gap) {
      canvas.drawLine(
        Offset(0, y),
        Offset(0, (y + dash).clamp(0, size.height - inset)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_PerforationPainter old) => old.color != color;
}
