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
        trailing: Text(
          '${trip.currency == 'INR' ? '₹' : ''}${trip.fare.toStringAsFixed(0)}',
          style: theme.textTheme.titleMedium,
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
