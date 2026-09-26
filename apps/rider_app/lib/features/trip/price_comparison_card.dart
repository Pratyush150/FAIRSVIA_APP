import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:shared_models/shared_models.dart';

/// Price check: how RideVela's fare for this trip compares to the other app
/// cabs (Uber, Ola, Rapido in India). Competitor prices are modeled from
/// published / regulated fares, which the card says plainly.
///
/// Two pieces:
/// - [PriceComparisonChip]: one line under the tier list at rest — never
///   pushes the tiers or the Confirm footer down by more than a row.
/// - [PriceComparisonCard]: the full breakdown, the first section of the
///   pulled-up "Choose a ride" extras (and the chip's bottom sheet).

String _whole(double v, String currency) =>
    Money.format(v, currency: currency, wholeOnly: true);

/// Competitor names in first-appearance order ("Uber, Ola, Rapido").
List<String> _competitorNames(PriceComparison c) {
  final names = <String>[];
  for (final q in c.quotes) {
    if (!q.isOurs && !names.contains(q.displayName)) names.add(q.displayName);
  }
  return names;
}

/// The honest one-line summary: a savings claim only when we really are the
/// cheapest; otherwise a neutral "Compare prices".
String priceComparisonSummary(PriceComparison c) {
  final names = _competitorNames(c).join(', ');
  if (c.ourIsCheapest && c.maxSavings >= 1) {
    return 'Save ${_whole(c.maxSavings, c.currency)}'
        '${names.isEmpty ? '' : ' vs $names'}';
  }
  if (c.ourIsCheapest) return 'Cheapest option for this trip';
  return 'Compare prices${names.isEmpty ? '' : ' with $names'}';
}

/// Opens the full [PriceComparisonCard] in a small bottom sheet.
Future<void> showPriceComparisonSheet(
  BuildContext context,
  PriceComparison comparison,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: PriceComparisonSection(comparison: comparison),
      ),
    ),
  );
}

/// Compact strip for the resting sheet. Taps open the full card.
class PriceComparisonChip extends StatelessWidget {
  const PriceComparisonChip({super.key, required this.comparison, this.onTap});

  final PriceComparison comparison;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final c = comparison;
    if (c.quotes.isEmpty) return const SizedBox.shrink();
    final cheapest = c.ourIsCheapest;
    final fg = cheapest
        ? AppColors.accentTextFor(dark)
        : theme.colorScheme.onSurfaceVariant;
    final text = priceComparisonSummary(c);
    return Semantics(
      button: true,
      label: '$text. Show price check',
      excludeSemantics: true,
      child: Material(
        color: cheapest
            ? AppColors.softFor(dark)
            : (dark ? AppColors.surfaceMutedDark : AppColors.surfaceMutedLight),
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        child: InkWell(
          key: const Key('price-comparison-chip'),
          borderRadius: BorderRadius.circular(AppSpacing.radius),
          onTap: onTap ?? () => showPriceComparisonSheet(context, c),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: 5,
            ),
            child: Row(
              children: [
                Icon(
                  cheapest
                      ? PhosphorIconsFill.sealCheck
                      : PhosphorIconsRegular.coins,
                  size: 16,
                  color: fg,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: fg,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Icon(PhosphorIconsRegular.caretRight, size: 16, color: fg),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The full card wrapped in the sheet-extras section look ("Price check").
class PriceComparisonSection extends StatelessWidget {
  const PriceComparisonSection({super.key, required this.comparison});
  final PriceComparison comparison;

  @override
  Widget build(BuildContext context) => SheetSection(
    key: const Key('price-comparison-section'),
    title: 'Price check',
    icon: PhosphorIconsRegular.coins,
    child: PriceComparisonCard(comparison: comparison),
  );
}

/// One displayed row: ours, a single competitor, or competitors sharing
/// the same (rounded) fare — Pune app-cabs follow one regulated tariff, and
/// three identical rows would read as a bug.
class _Row {
  _Row(this.quotes);
  final List<ProviderQuote> quotes;
  ProviderQuote get first => quotes.first;
  bool get isOurs => first.isOurs;
  double get price => first.price;
  double get high => quotes
      .map((q) => q.isOurs || !q.hasRange ? q.price : q.priceHigh)
      .reduce((a, b) => a > b ? a : b);
}

List<_Row> _rows(PriceComparison c) {
  final ours = c.quotes.where((q) => q.isOurs).toList();
  final others = c.quotes.where((q) => !q.isOurs).toList()
    ..sort((a, b) => a.price.compareTo(b.price));
  final groups = <_Row>[];
  for (final q in others) {
    final match = groups.where((g) {
      final f = g.first;
      return f.price.round() == q.price.round() &&
          f.priceLow.round() == q.priceLow.round() &&
          f.priceHigh.round() == q.priceHigh.round();
    });
    if (match.isNotEmpty) {
      match.first.quotes.add(q);
    } else {
      groups.add(_Row([q]));
    }
  }
  return [for (final q in ours) _Row([q]), ...groups];
}

/// The full comparison: our row first (accent), then each competitor (or
/// same-fare group), a thin bar per row relative to the priciest, a
/// "Cheapest" pill on the lowest, and the honesty footnote.
class PriceComparisonCard extends StatelessWidget {
  const PriceComparisonCard({super.key, required this.comparison});

  final PriceComparison comparison;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = comparison;
    if (c.quotes.isEmpty) return const SizedBox.shrink();
    final rows = _rows(c);
    final maxPrice = rows
        .map((r) => r.high)
        .fold<double>(0, (a, b) => a > b ? a : b);
    final minPrice = c.quotes
        .map((q) => q.price)
        .reduce((a, b) => a < b ? a : b);
    final grouped = rows.any((r) => r.quotes.length > 1);
    final muted = theme.colorScheme.onSurfaceVariant;

    final String headline;
    if (c.ourIsCheapest && c.maxSavings >= 1) {
      headline =
          'Cheapest option — save up to ${_whole(c.maxSavings, c.currency)}';
    } else if (c.ourIsCheapest) {
      headline = 'Cheapest option for this trip';
    } else {
      final low = c.quotes.first;
      headline =
          'Lowest right now: ${low.displayName} ${_whole(low.price, low.currency)}';
    }

    // Exactly one honesty line.
    final footnote = [
      grouped
          ? 'Govt-approved app-cab fare · actual prices may vary'
          : c.disclaimer.isNotEmpty
          ? c.disclaimer
          : 'Estimates from published fares · actual prices vary',
    ];

    return Column(
      key: const Key('price-comparison-card'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          headline,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: c.ourIsCheapest
                ? AppColors.accentTextFor(theme.brightness == Brightness.dark)
                : theme.colorScheme.onSurface,
          ),
        ),
        if (c.demandHigh) ...[
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'High demand — competitor prices may be higher',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.warningTextOf(context),
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        for (final (i, r) in rows.indexed) ...[
          if (i > 0) const SizedBox(height: AppSpacing.md),
          _QuoteRow(
            row: r,
            maxPrice: maxPrice,
            cheapest: r.price.round() == minPrice.round(),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        for (final line in footnote)
          Text(
            line,
            style: theme.textTheme.labelSmall?.copyWith(color: muted),
          ),
      ],
    );
  }
}

class _QuoteRow extends StatelessWidget {
  const _QuoteRow({
    required this.row,
    required this.maxPrice,
    required this.cheapest,
  });
  final _Row row;
  final double maxPrice;
  final bool cheapest;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final ours = row.isOurs;
    final accent = AppColors.accentTextFor(dark);
    final muted = theme.colorScheme.onSurfaceVariant;
    final q = row.first;
    final name = ours
        ? AppBrand.name
        : row.quotes.map((q) => q.displayName).join(' · ');
    final product = [
      ...row.quotes.map((q) => q.productName).where((p) => p.isNotEmpty),
    ].join(' · ');
    final subtitle = [
      if (product.isNotEmpty) product,
      if (!ours && q.estimated) 'est.',
    ].join(' · ');
    final fare =
        ours || !q.hasRange || q.priceLow.round() == q.priceHigh.round()
        ? _whole(q.price, q.currency)
        : '${_whole(q.priceLow, q.currency)}–${_whole(q.priceHigh, q.currency)}';
    final frac = maxPrice <= 0 ? 0.0 : (row.high / maxPrice).clamp(0.0, 1.0);
    final track = dark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.06);

    return Semantics(
      label: '$name${subtitle.isEmpty ? '' : ', $subtitle'}, $fare'
          '${cheapest ? ', cheapest' : ''}',
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (row.quotes.length > 1)
            const _GroupAvatar()
          else
            _Monogram(text: ours ? AppBrand.name : q.displayName, ours: ours),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Wrap(
                        spacing: AppSpacing.xs,
                        runSpacing: AppSpacing.xxs,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            name,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight:
                                  ours ? FontWeight.w700 : FontWeight.w500,
                              color: ours ? accent : null,
                            ),
                          ),
                          if (cheapest) const _CheapestPill(),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      fare,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: ours ? FontWeight.w700 : FontWeight.w600,
                        color: ours ? accent : null,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
                if (subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                const SizedBox(height: AppSpacing.xs),
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppSpacing.pill),
                  child: SizedBox(
                    height: 4,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ColoredBox(color: track),
                        FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: frac,
                          child: ColoredBox(
                            color: ours
                                ? AppColors.inkFor(dark)
                                : muted.withValues(alpha: 0.45),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Same-fare group: a neutral cab glyph (letters would stack illegibly).
class _GroupAvatar extends StatelessWidget {
  const _GroupAvatar();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: dark
            ? Colors.white.withValues(alpha: 0.10)
            : Colors.black.withValues(alpha: 0.07),
      ),
      child: Icon(
        PhosphorIconsRegular.taxi,
        size: 16,
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// Neutral letter avatar — never a competitor's logo.
class _Monogram extends StatelessWidget {
  const _Monogram({required this.text, required this.ours});
  final String text;
  final bool ours;
  static const double size = 28;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final letter = text.isEmpty ? '?' : text.characters.first.toUpperCase();
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: ours
              ? AppColors.inkFor(dark)
              : (dark
                    ? Colors.white.withValues(alpha: 0.10)
                    : Colors.black.withValues(alpha: 0.07)),
        ),
        child: Text(
          letter,
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: ours
                ? AppColors.onInkFor(dark)
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _CheapestPill extends StatelessWidget {
  const _CheapestPill();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: AppColors.softFor(dark),
        borderRadius: BorderRadius.circular(AppSpacing.pill),
      ),
      child: Text(
        'Cheapest',
        style: theme.textTheme.labelSmall?.copyWith(
          color: AppColors.accentTextFor(dark),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
