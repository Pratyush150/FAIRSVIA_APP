import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

import '../driver/driver_remote_data_source.dart';
import '../network/api_exception.dart';
import 'format.dart';
import 'widgets/async_content.dart';

/// Driver payout balance + ledger, with a withdrawal action
/// (`GET/POST /drivers/balance`).
class DriverPayoutsPage extends StatefulWidget {
  const DriverPayoutsPage({super.key, required this.driver});

  final DriverRemoteDataSource driver;

  @override
  State<DriverPayoutsPage> createState() => _DriverPayoutsPageState();
}

class _DriverPayoutsPageState extends State<DriverPayoutsPage> {
  int _reloadKey = 0;

  Future<void> _withdraw(BuildContext context, double max) async {
    final controller = TextEditingController(text: max.toStringAsFixed(0));
    final amount = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Withdraw to bank'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            prefixText: '\$ ',
            helperText: 'Available: \$${max.toStringAsFixed(2)}',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(ctx, double.tryParse(controller.text.trim())),
            child: const Text('Withdraw'),
          ),
        ],
      ),
    );
    if (amount == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.driver.withdraw(amount);
      messenger.showSnackBar(
        SnackBar(content: Text('Withdrew \$${amount.toStringAsFixed(0)}')),
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
        '${credit ? '+' : '−'}\$${entry.amount.abs().toStringAsFixed(2)}',
        style: theme.textTheme.titleMedium?.copyWith(
          color: credit ? AppColors.success : AppColors.error,
        ),
      ),
    );
  }

  IconData _icon(String type) {
    switch (type) {
      case 'earning':
        return Icons.directions_car;
      case 'tip':
        return Icons.volunteer_activism;
      case 'withdrawal':
        return Icons.account_balance;
      case 'commission':
        return Icons.percent;
      default:
        return Icons.receipt_long;
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
