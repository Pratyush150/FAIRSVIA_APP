import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

import '../driver/driver_remote_data_source.dart';
import 'format.dart';
import 'widgets/async_content.dart';

/// Driver earnings with a today/week toggle (`GET /drivers/me/earnings`).
class DriverEarningsPage extends StatefulWidget {
  const DriverEarningsPage({super.key, required this.driver});

  final DriverRemoteDataSource driver;

  @override
  State<DriverEarningsPage> createState() => _DriverEarningsPageState();
}

class _DriverEarningsPageState extends State<DriverEarningsPage> {
  String _range = 'today';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Earnings')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'today', label: Text('Today')),
                ButtonSegment(value: 'week', label: Text('This week')),
              ],
              selected: {_range},
              onSelectionChanged: (s) => setState(() => _range = s.first),
            ),
          ),
          Expanded(
            child: AsyncContent<DriverEarnings>(
              // Keyed by range so switching reloads with a fresh future.
              key: ValueKey(_range),
              load: () => widget.driver.earnings(range: _range),
              builder: (context, e, _) => _body(context, e),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, DriverEarnings e) {
    final theme = Theme.of(context);
    final perTrip = e.trips > 0 ? e.total / e.trips : 0.0;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              children: [
                Text(_range == 'today' ? "Today's earnings" : "This week",
                    style: theme.textTheme.titleMedium),
                const SizedBox(height: AppSpacing.sm),
                Text(Fmt.money(e.total),
                    style: theme.textTheme.displaySmall
                        ?.copyWith(color: AppColors.accent)),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: _Stat(label: 'Trips', value: '${e.trips}'),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: _Stat(label: 'Avg / trip', value: Fmt.money(perTrip)),
            ),
          ],
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: theme.textTheme.headlineSmall),
            const SizedBox(height: AppSpacing.xs),
            Text(label, style: theme.textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}
