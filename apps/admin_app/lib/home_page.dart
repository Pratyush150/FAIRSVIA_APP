import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'cubit/admin_cubit.dart';
import 'data/admin_api.dart';
import 'widgets/status_chip.dart';

class AdminHomePage extends StatelessWidget {
  const AdminHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => AdminCubit(sl<AdminApi>())..start(),
      child: const _AdminScaffold(),
    );
  }
}

class _AdminScaffold extends StatelessWidget {
  const _AdminScaffold();

  @override
  Widget build(BuildContext context) {
    final phone = context.select((AuthBloc b) => b.state.user?.phone);
    return BlocBuilder<AdminCubit, AdminState>(
      builder: (context, state) {
        final cubit = context.read<AdminCubit>();
        return Scaffold(
          body: Row(
            children: [
              NavigationRail(
                selectedIndex: state.tab.index,
                onDestinationSelected: (i) =>
                    cubit.selectTab(AdminTab.values[i]),
                labelType: NavigationRailLabelType.all,
                leading: const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
                  child: Icon(Icons.local_taxi, color: AppColors.accent),
                ),
                trailing: Expanded(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                      child: IconButton(
                        tooltip: 'Sign out',
                        icon: const Icon(Icons.logout),
                        onPressed: () => context
                            .read<AuthBloc>()
                            .add(const AuthSignedOut()),
                      ),
                    ),
                  ),
                ),
                destinations: const [
                  NavigationRailDestination(
                    icon: Icon(Icons.dashboard_outlined),
                    selectedIcon: Icon(Icons.dashboard),
                    label: Text('Overview'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.route_outlined),
                    selectedIcon: Icon(Icons.route),
                    label: Text('Trips'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.people_outline),
                    selectedIcon: Icon(Icons.people),
                    label: Text('Users'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.directions_car_outlined),
                    selectedIcon: Icon(Icons.directions_car),
                    label: Text('Drivers'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.monitor_heart_outlined),
                    selectedIcon: Icon(Icons.monitor_heart),
                    label: Text('Monitoring'),
                  ),
                ],
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: Column(
                  children: [
                    _TopBar(
                      title: _titleFor(state.tab),
                      phone: phone,
                      loading: state.loading,
                      onRefresh: cubit.refresh,
                    ),
                    if (state.error != null)
                      _ErrorBanner(message: state.error!, onRetry: cubit.refresh),
                    Expanded(child: _Body(state: state)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _titleFor(AdminTab tab) => switch (tab) {
        AdminTab.overview => 'Overview',
        AdminTab.trips => 'Trips',
        AdminTab.users => 'Users',
        AdminTab.drivers => 'Drivers',
        AdminTab.monitoring => 'Monitoring',
      };
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.title,
    required this.phone,
    required this.loading,
    required this.onRefresh,
  });

  final String title;
  final String? phone;
  final bool loading;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl, AppSpacing.xl, AppSpacing.xl, AppSpacing.md),
      child: Row(
        children: [
          Text(title, style: theme.textTheme.headlineSmall),
          const SizedBox(width: AppSpacing.md),
          if (loading)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          const Spacer(),
          if (phone != null)
            Text(phone!, style: theme.textTheme.bodySmall),
          const SizedBox(width: AppSpacing.md),
          IconButton(
            tooltip: 'Refresh',
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.state});
  final AdminState state;

  @override
  Widget build(BuildContext context) {
    return switch (state.tab) {
      AdminTab.overview => _OverviewView(state: state),
      AdminTab.trips => _TripsView(trips: state.trips),
      AdminTab.users => const _UsersView(),
      AdminTab.drivers => _DriversView(drivers: state.drivers),
      AdminTab.monitoring => _MonitoringView(ops: state.ops),
    };
  }
}

// --- Overview ---------------------------------------------------------------

class _OverviewView extends StatelessWidget {
  const _OverviewView({required this.state});
  final AdminState state;

  @override
  Widget build(BuildContext context) {
    final s = state.stats;
    if (s == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        Wrap(
          spacing: AppSpacing.lg,
          runSpacing: AppSpacing.lg,
          children: [
            _StatCard(label: 'Users', value: '${s.users}', icon: Icons.people),
            _StatCard(
                label: 'Drivers',
                value: '${s.drivers}',
                icon: Icons.directions_car),
            _StatCard(
                label: 'Online now',
                value: '${s.onlineDrivers}',
                icon: Icons.wifi_tethering,
                color: AppColors.success),
            _StatCard(
                label: 'Active trips',
                value: '${s.activeTrips}',
                icon: Icons.route,
                color: AppColors.warning),
            _StatCard(
                label: 'Completed',
                value: '${s.completedTrips}',
                icon: Icons.check_circle),
            _StatCard(
                label: 'Gross revenue',
                value: '₹${s.grossRevenue.toStringAsFixed(0)}',
                icon: Icons.payments),
            _StatCard(
                label: 'Platform fees',
                value: '₹${s.platformRevenue.toStringAsFixed(0)}',
                icon: Icons.account_balance,
                color: AppColors.accent),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        Text('Live trips', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        if (state.trips.isEmpty)
          const _Empty(text: 'No active trips right now.')
        else
          ...state.trips.map((t) => _TripTile(trip: t)),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 200,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color ?? AppColors.accent),
          const SizedBox(height: AppSpacing.md),
          Text(value, style: theme.textTheme.headlineMedium),
          Text(label, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

// --- Trips ------------------------------------------------------------------

class _TripsView extends StatelessWidget {
  const _TripsView({required this.trips});
  final List<AdminTrip> trips;

  @override
  Widget build(BuildContext context) {
    if (trips.isEmpty) {
      return const _Empty(text: 'No trips yet.');
    }
    return ListView.builder(
      padding: const EdgeInsets.all(AppSpacing.xl),
      itemCount: trips.length,
      itemBuilder: (_, i) => _TripTile(trip: trips[i]),
    );
  }
}

class _TripTile extends StatelessWidget {
  const _TripTile({required this.trip});
  final AdminTrip trip;

  bool get _refundable => trip.status == 'completed' && trip.fare > 0;

  Future<void> _refund(BuildContext context) async {
    final cubit = context.read<AdminCubit>();
    final controller = TextEditingController(text: trip.fare.toStringAsFixed(0));
    final reason = TextEditingController();
    final amount = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Refund trip'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                prefixText: '₹ ',
                helperText: 'Fare ₹${trip.fare.toStringAsFixed(2)}',
              ),
            ),
            TextField(
              controller: reason,
              decoration: const InputDecoration(labelText: 'Reason (optional)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(ctx, double.tryParse(controller.text.trim())),
            child: const Text('Refund'),
          ),
        ],
      ),
    );
    if (amount == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await cubit.refundTrip(
        trip.id,
        amount: amount,
        reason: reason.text.trim().isEmpty ? null : reason.text.trim(),
      );
      messenger.showSnackBar(
        SnackBar(content: Text('Refunded ₹${amount.toStringAsFixed(0)}')),
      );
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('Refund failed')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ListTile(
        leading: StatusChip(status: trip.status),
        title: Text(
          '${trip.pickup ?? '—'}  →  ${trip.dropoff ?? '—'}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          'Rider ${trip.rider?.name ?? trip.rider?.phone ?? '—'}'
          '   •   Driver ${trip.driver?.name ?? trip.driver?.phone ?? 'unassigned'}'
          '   •   ${trip.tier}',
          style: theme.textTheme.bodySmall,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${trip.currency == 'INR' ? '₹' : ''}${trip.fare.toStringAsFixed(0)}',
              style: theme.textTheme.titleMedium,
            ),
            if (_refundable)
              IconButton(
                icon: const Icon(Icons.currency_exchange, size: 20),
                tooltip: 'Refund',
                onPressed: () => _refund(context),
              ),
          ],
        ),
      ),
    );
  }
}

// --- Users ------------------------------------------------------------------

class _UsersView extends StatelessWidget {
  const _UsersView();

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<AdminCubit>();
    return BlocBuilder<AdminCubit, AdminState>(
      builder: (context, state) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
              child: TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search by phone or name',
                ),
                onChanged: cubit.setUserQuery,
                onSubmitted: (_) => cubit.searchUsers(),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Expanded(
              child: state.users.isEmpty
                  ? const _Empty(text: 'No users found.')
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.xl),
                      itemCount: state.users.length,
                      itemBuilder: (_, i) =>
                          _UserTile(user: state.users[i], cubit: cubit),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _UserTile extends StatelessWidget {
  const _UserTile({required this.user, required this.cubit});
  final AdminUser user;
  final AdminCubit cubit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: user.isActive
              ? AppColors.accent.withValues(alpha: 0.15)
              : AppColors.error.withValues(alpha: 0.15),
          child: Text(user.role.substring(0, 1).toUpperCase()),
        ),
        title: Text(user.name ?? user.phone),
        subtitle: Text(
          '${user.phone}  •  ${user.role}  •  ★ ${user.ratingAvg.toStringAsFixed(2)} (${user.ratingCount})',
          style: theme.textTheme.bodySmall,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(user.isActive ? 'Active' : 'Disabled',
                style: theme.textTheme.bodySmall),
            Switch(
              value: user.isActive,
              onChanged: (_) => cubit.toggleActive(user),
            ),
          ],
        ),
      ),
    );
  }
}

// --- Drivers ----------------------------------------------------------------

class _DriversView extends StatelessWidget {
  const _DriversView({required this.drivers});
  final List<AdminDriver> drivers;

  @override
  Widget build(BuildContext context) {
    if (drivers.isEmpty) {
      return const _Empty(text: 'No drivers onboarded yet.');
    }
    return ListView.builder(
      padding: const EdgeInsets.all(AppSpacing.xl),
      itemCount: drivers.length,
      itemBuilder: (_, i) {
        final d = drivers[i];
        final theme = Theme.of(context);
        final online = d.liveStatus != 'offline';
        return Card(
          margin: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: ListTile(
            leading: Icon(
              Icons.circle,
              size: 12,
              color: online ? AppColors.success : theme.disabledColor,
            ),
            title: Text(d.name ?? d.phone),
            subtitle: Text(
              '${d.vehicle}  •  ★ ${d.rating.toStringAsFixed(2)}  •  ${d.totalTrips} trips',
              style: theme.textTheme.bodySmall,
            ),
            trailing: Text(d.liveStatus, style: theme.textTheme.bodySmall),
          ),
        );
      },
    );
  }
}

// --- Monitoring -------------------------------------------------------------

class _MonitoringView extends StatelessWidget {
  const _MonitoringView({required this.ops});
  final OpsMetrics? ops;

  static String _uptime(int s) {
    final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${sec}s';
    return '${sec}s';
  }

  @override
  Widget build(BuildContext context) {
    final o = ops;
    if (o == null) return const Center(child: CircularProgressIndicator());
    final theme = Theme.of(context);
    final errPct = (o.errorRate * 100);
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        Text('System', style: theme.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.lg,
          runSpacing: AppSpacing.lg,
          children: [
            _StatCard(
                label: 'Uptime',
                value: _uptime(o.uptimeSec),
                icon: Icons.timer_outlined),
            _StatCard(
                label: 'Memory (RSS)',
                value: '${o.rssMb} MB',
                icon: Icons.memory),
            _StatCard(
                label: 'Heap used',
                value: '${o.heapUsedMb} MB',
                icon: Icons.data_usage),
            _StatCard(
                label: 'Node',
                value: o.nodeVersion,
                icon: Icons.terminal),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        Text('HTTP traffic (since boot)',
            style: theme.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.lg,
          runSpacing: AppSpacing.lg,
          children: [
            _StatCard(
                label: 'Requests',
                value: '${o.requestsTotal}',
                icon: Icons.swap_vert),
            _StatCard(
                label: 'Errors (5xx)',
                value: '${o.errorsTotal}',
                icon: Icons.error_outline,
                color: o.errorsTotal > 0 ? AppColors.error : AppColors.success),
            _StatCard(
                label: 'Error rate',
                value: '${errPct.toStringAsFixed(errPct < 10 ? 1 : 0)}%',
                icon: Icons.percent,
                color: errPct > 1 ? AppColors.warning : AppColors.success),
            _StatCard(
                label: 'Avg latency',
                value: '${o.avgLatencyMs} ms',
                icon: Icons.speed),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        Text('Queues', style: theme.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.lg,
          runSpacing: AppSpacing.lg,
          children: [
            _QueueCard(name: 'Dispatch', counts: o.dispatch),
            _QueueCard(name: 'Notifications', counts: o.notifications),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        Row(
          children: [
            Text('Trip funnel', style: theme.textTheme.titleMedium),
            const SizedBox(width: AppSpacing.md),
            Text('${o.onlineDrivers} drivers online • ${o.activeTrips} active',
                style: theme.textTheme.bodySmall),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        _TripFunnel(funnel: o.tripFunnel),
      ],
    );
  }
}

class _QueueCard extends StatelessWidget {
  const _QueueCard({required this.name, required this.counts});
  final String name;
  final QueueCounts counts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget row(String label, int value, {Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: theme.textTheme.bodySmall),
              Text('$value',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: color, fontWeight: FontWeight.w600)),
            ],
          ),
        );
    return Container(
      width: 260,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.layers_outlined,
                  color: AppColors.accent, size: 18),
              const SizedBox(width: AppSpacing.sm),
              Text(name, style: theme.textTheme.titleSmall),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          row('Waiting', counts.waiting),
          row('Active', counts.active,
              color: counts.active > 0 ? AppColors.warning : null),
          row('Completed', counts.completed),
          row('Failed', counts.failed,
              color: counts.failed > 0 ? AppColors.error : AppColors.success),
          row('Delayed', counts.delayed),
        ],
      ),
    );
  }
}

class _TripFunnel extends StatelessWidget {
  const _TripFunnel({required this.funnel});
  final Map<String, int> funnel;

  // Show statuses in lifecycle order, only those with a count.
  static const _order = [
    'requested',
    'matching',
    'accepted',
    'arrived',
    'in_progress',
    'completed',
    'cancelled',
    'no_drivers',
    'payment_failed',
    'expired',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = [
      for (final k in _order)
        if ((funnel[k] ?? 0) > 0) MapEntry(k, funnel[k]!),
    ];
    if (entries.isEmpty) {
      return const _Empty(text: 'No trips recorded yet.');
    }
    final max = entries.map((e) => e.value).reduce((a, b) => a > b ? a : b);
    Color colorFor(String s) => switch (s) {
          'completed' => AppColors.success,
          'cancelled' || 'no_drivers' || 'payment_failed' || 'expired' =>
            AppColors.error,
          _ => AppColors.accent,
        };
    return Column(
      children: [
        for (final e in entries)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 110,
                  child: Text(e.key.replaceAll('_', ' '),
                      style: theme.textTheme.bodySmall),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: max == 0 ? 0 : e.value / max,
                      minHeight: 16,
                      backgroundColor: theme.dividerColor.withValues(alpha: 0.3),
                      valueColor:
                          AlwaysStoppedAnimation(colorFor(e.key)),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                SizedBox(
                  width: 44,
                  child: Text('${e.value}',
                      textAlign: TextAlign.right,
                      style: theme.textTheme.bodyMedium),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// --- Shared bits ------------------------------------------------------------

class _Empty extends StatelessWidget {
  const _Empty({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.error.withValues(alpha: 0.12),
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xl, vertical: AppSpacing.sm),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: AppColors.error, size: 18),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text(message)),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
