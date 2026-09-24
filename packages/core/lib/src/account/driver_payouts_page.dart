import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../driver/driver_remote_data_source.dart';
import '../network/api_exception.dart';
import 'format.dart';
import 'widgets/async_content.dart';
import 'package:shared_models/shared_models.dart';

/// Driver payout balance + ledger, with a withdrawal action
/// (`GET/POST /drivers/balance`).
class DriverPayoutsPage extends StatefulWidget {
  const DriverPayoutsPage({super.key, required this.driver});

  final DriverRemoteDataSource driver;

  /// Client-side check mirroring the server's rule (`0 < amount <= balance`).
  /// Returns an error message, or null when [raw] is an acceptable amount.
  static String? validateWithdrawal(String raw, double max) {
    final amount = double.tryParse(raw.trim());
    if (amount == null) return 'Enter a valid amount.';
    if (amount <= 0) return 'Enter an amount greater than zero.';
    // Compare at cent precision so "12.60" against 12.6 never trips.
    if ((amount * 100).round() > (max * 100).round()) {
      return 'You can withdraw up to ${Fmt.money(max)}.';
    }
    return null;
  }

  @override
  State<DriverPayoutsPage> createState() => _DriverPayoutsPageState();
}

class _DriverPayoutsPageState extends State<DriverPayoutsPage> {
  int _reloadKey = 0;

  Future<void> _withdraw(BuildContext context, double max) async {
    // Pre-fill with cents: rounding $12.60 to "13" exceeds the balance and
    // the server rejects it.
    final controller = TextEditingController(text: max.toStringAsFixed(2));
    String? error;
    final amount = await showDialog<double>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Withdraw to bank'),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              prefixText: '${Money.symbol()} ',
              helperText: 'Available: ${Fmt.money(max)}',
              errorText: error,
            ),
            onChanged: (_) {
              if (error != null) setDialogState(() => error = null);
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final problem =
                    DriverPayoutsPage.validateWithdrawal(controller.text, max);
                if (problem != null) {
                  setDialogState(() => error = problem);
                  return;
                }
                Navigator.pop(ctx, double.parse(controller.text.trim()));
              },
              child: const Text('Withdraw'),
            ),
          ],
        ),
      ),
    );
    if (amount == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.driver.withdraw(amount);
      messenger.showSnackBar(
        SnackBar(content: Text('Withdrew ${Fmt.money(amount)}')),
      );
      if (mounted) setState(() => _reloadKey++);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Payouts')),
      body: AsyncContent<PayoutBalance>(
        key: ValueKey(_reloadKey),
        load: widget.driver.balance,
        isEmpty: (_) => false,
        builder: (context, data, _) {
          final theme = Theme.of(context);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ConnectPayoutSetup(driver: widget.driver),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Available balance',
                        style: theme.textTheme.bodyMedium),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      Fmt.money(data.balance, data.currency),
                      style: theme.textTheme.displaySmall,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    PrimaryButton(
                      label: 'Withdraw to bank',
                      onPressed: data.balance > 0
                          ? () => _withdraw(context, data.balance)
                          : null,
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.md,
                  AppSpacing.lg,
                  AppSpacing.sm,
                ),
                child: Text('Recent activity',
                    style: theme.textTheme.titleMedium),
              ),
              Expanded(
                child: data.entries.isEmpty
                    ? Center(
                        child: Text('No payouts yet',
                            style: theme.textTheme.bodyMedium),
                      )
                    : ListView.separated(
                        itemCount: data.entries.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, i) =>
                            _LedgerTile(entry: data.entries[i]),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Stripe Connect onboarding banner. Shows a "set up direct deposit" CTA until
/// the driver's account can receive payouts, then a subtle confirmation. Until
/// onboarding is complete, withdrawals still work via the mock ledger.
class _ConnectPayoutSetup extends StatefulWidget {
  const _ConnectPayoutSetup({required this.driver});
  final DriverRemoteDataSource driver;

  @override
  State<_ConnectPayoutSetup> createState() => _ConnectPayoutSetupState();
}

class _ConnectPayoutSetupState extends State<_ConnectPayoutSetup> {
  ConnectStatus? _status;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _busy = true);
    try {
      final status = await widget.driver.connectStatus();
      if (mounted) setState(() => _status = status);
    } on ApiException {
      // Non-fatal — leave the banner in its "set up" state.
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _startOnboarding() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final url = await widget.driver.connectOnboard();
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Finish setup in your browser, then tap "Check status".'),
        ),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = _status;

    // Payouts ready — subtle confirmation row.
    if (status != null && status.payoutsEnabled) {
      return Container(
        width: double.infinity,
        color: AppColors.success.withValues(alpha: 0.10),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            const Icon(PhosphorIconsFill.sealCheck, color: AppColors.success, size: 20),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                'Direct deposit active — withdrawals go to your bank.',
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      );
    }

    // Not yet enabled — show the setup CTA.
    return Container(
      color: AppColors.accentSoft.withValues(alpha: 0.35),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(PhosphorIconsRegular.bank, size: 20),
              const SizedBox(width: AppSpacing.sm),
              Text('Set up direct deposit', style: theme.textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Connect a bank account to get your earnings paid out automatically.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: PrimaryButton(
                  label: status?.onboarded == true
                      ? 'Continue setup'
                      : 'Set up payouts',
                  loading: _busy,
                  onPressed: _busy ? null : _startOnboarding,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              TextButton(
                onPressed: _busy ? null : _refresh,
                child: const Text('Check status'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LedgerTile extends StatelessWidget {
  const _LedgerTile({required this.entry});
  final LedgerEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final credit = entry.amount >= 0;
    return ListTile(
      leading: Icon(
        _icon(entry.type),
        color: credit ? AppColors.success : AppColors.error,
      ),
      title: Text(entry.note ?? _label(entry.type)),
      subtitle: entry.createdAt != null
          ? Text(Fmt.dateTime(entry.createdAt!))
          : null,
      trailing: Text(
        '${credit ? '+' : '−'}${Fmt.money(entry.amount.abs())}',
        style: theme.textTheme.titleMedium?.copyWith(
          color: credit ? AppColors.success : AppColors.error,
        ),
      ),
    );
  }

  IconData _icon(String type) {
    switch (type) {
      case 'earning':
        return PhosphorIconsRegular.car;
      case 'tip':
        return PhosphorIconsRegular.handHeart;
      case 'withdrawal':
        return PhosphorIconsRegular.bank;
      case 'commission':
        return PhosphorIconsRegular.percent;
      default:
        return PhosphorIconsRegular.receipt;
    }
  }

  String _label(String type) {
    switch (type) {
      case 'earning':
        return 'Ride earning';
      case 'tip':
        return 'Tip';
      case 'withdrawal':
        return 'Withdrawal';
      case 'commission':
        return 'Commission';
      default:
        return 'Adjustment';
    }
  }
}
