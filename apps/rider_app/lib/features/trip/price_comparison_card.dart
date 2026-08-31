import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:shared_models/shared_models.dart';

/// Shows how FairsVia's fare for this trip compares to modeled Uber / Lyft /
/// Empower prices, with the minimum-price provider flagged. Competitor prices
/// are estimates (from published rate cards), which the card states plainly.
class PriceComparisonCard extends StatelessWidget {
  const PriceComparisonCard({super.key, required this.comparison});

  final PriceComparison comparison;

  String _money(double v) => '\$${v.toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = comparison;
    if (c.quotes.isEmpty) return const SizedBox.shrink();

    // Headline: either we're cheapest, or name the cheaper option honestly.
    final Widget headline;
    if (c.ourIsCheapest && c.maxSavings > 0) {
      headline = _Headline(
        icon: Icons.savings_rounded,
        color: AppColors.accent,
        text: 'Cheapest option — save up to ${_money(c.maxSavings)} vs others',
      );
    } else if (c.ourIsCheapest) {
      headline = const _Headline(
        icon: Icons.verified_rounded,
        color: AppColors.accent,
        text: 'Cheapest option for this trip',
      );
    } else {
      final cheapest = c.quotes.first;
      headline = _Headline(
        icon: Icons.info_outline_rounded,
        color: theme.colorScheme.onSurfaceVariant,
        text:
            'Lowest right now: ${cheapest.displayName} ${_money(cheapest.price)}',
      );
    }

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppSpacing.md),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('Price comparison', style: theme.textTheme.titleSmall),
              const Spacer(),
              Tooltip(
                message: c.disclaimer,
                triggerMode: TooltipTriggerMode.tap,
                showDuration: const Duration(seconds: 6),
                child: Icon(
                  Icons.help_outline_rounded,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          headline,
          if (c.demandHigh) ...[
            const SizedBox(height: AppSpacing.xs),
            const _Headline(
              icon: Icons.bolt_rounded,
              color: AppColors.warning,
              text: 'High demand — competitor prices may be higher',
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          for (final q in c.quotes) _QuoteRow(quote: q, money: _money),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Other services’ prices are estimates from published rates, '
            'not live quotes.',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _Headline extends StatelessWidget {
  const _Headline({required this.icon, required this.color, required this.text});
  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: color, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class _QuoteRow extends StatelessWidget {
  const _QuoteRow({required this.quote, required this.money});
  final ProviderQuote quote;
  final String Function(double) money;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isOurs = quote.isOurs;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          if (isOurs)
            const Icon(Icons.local_taxi_rounded,
                size: 16, color: AppColors.accent)
          else
            Icon(Icons.circle_outlined,
                size: 16, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: AppSpacing.sm),
          Text(
            quote.displayName,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: isOurs ? FontWeight.w700 : FontWeight.w400,
              color: isOurs ? AppColors.accent : null,
            ),
          ),
          if (quote.estimated) ...[
            const SizedBox(width: AppSpacing.xs),
            Text('est.',
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
          const Spacer(),
          Text(
            // Competitor estimates show a range (they're modeled, not exact);
            // our own fare shows a single precise number.
            quote.isOurs || !quote.hasRange
                ? money(quote.price)
                : '\$${quote.priceLow.round()}–\$${quote.priceHigh.round()}',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: isOurs ? FontWeight.w700 : FontWeight.w500,
              color: isOurs ? AppColors.accent : null,
            ),
          ),
        ],
      ),
    );
  }
}
