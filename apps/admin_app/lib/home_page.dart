import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:shared_models/shared_models.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'cubit/admin_cubit.dart';
import 'data/admin_api.dart';
import 'widgets/status_chip.dart';

/// Where the monitoring dashboards live. Override per environment with
/// `--dart-define=GRAFANA_URL=https://grafana.example.com`.
const String kGrafanaUrl = String.fromEnvironment(
  'GRAFANA_URL',
  defaultValue: 'http://localhost:3001',
);

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
                leading: Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
                  child: Icon(Icons.local_taxi, color: AppColors.accent),
                ),
                trailing: Expanded(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // The Monitoring tab used to live in this rail.
                          // Uptime, memory, error rate and queue depth are
                          // Grafana's job — it has history and alerting, and
                          // something actually watches it. This is the
                          // signpost so nobody goes looking for the old tab.
                          IconButton(
                            tooltip: 'Monitoring (Grafana)',
                            icon: const Icon(Icons.monitor_heart_outlined),
                            onPressed: () => openExternalUrl(kGrafanaUrl),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          IconButton(
                            tooltip: 'Sign out',
                            icon: const Icon(Icons.logout),
                            onPressed: () => context
                                .read<AuthBloc>()
                                .add(const AuthSignedOut()),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                destinations: [
                  const NavigationRailDestination(
                    icon: Icon(Icons.dashboard_outlined),
                    selectedIcon: Icon(Icons.dashboard),
                    label: Text('Overview'),
                  ),
                  NavigationRailDestination(
                    icon: Badge(
                      isLabelVisible: state.openIncidents > 0,
                      label: Text('${state.openIncidents}'),
                      child: const Icon(Icons.health_and_safety_outlined),
                    ),
                    selectedIcon: Badge(
                      isLabelVisible: state.openIncidents > 0,
                      label: Text('${state.openIncidents}'),
                      child: const Icon(Icons.health_and_safety),
                    ),
                    label: const Text('Safety'),
                  ),
                  const NavigationRailDestination(
                    icon: Icon(Icons.route_outlined),
                    selectedIcon: Icon(Icons.route),
                    label: Text('Trips'),
                  ),
                  const NavigationRailDestination(
                    icon: Icon(Icons.people_outline),
                    selectedIcon: Icon(Icons.people),
                    label: Text('Users'),
                  ),
                  const NavigationRailDestination(
                    icon: Icon(Icons.directions_car_outlined),
                    selectedIcon: Icon(Icons.directions_car),
                    label: Text('Drivers'),
                  ),
                  const NavigationRailDestination(
                    icon: Icon(Icons.map_outlined),
                    selectedIcon: Icon(Icons.map),
                    label: Text('Live'),
                  ),
                  const NavigationRailDestination(
                    icon: Icon(Icons.support_agent_outlined),
                    selectedIcon: Icon(Icons.support_agent),
                    label: Text('Support'),
                  ),
                  const NavigationRailDestination(
                    icon: Icon(Icons.local_offer_outlined),
                    selectedIcon: Icon(Icons.local_offer),
                    label: Text('Promos'),
                  ),
                  const NavigationRailDestination(
                    icon: Icon(Icons.view_carousel_outlined),
                    selectedIcon: Icon(Icons.view_carousel),
                    label: Text('Content'),
                  ),
                  const NavigationRailDestination(
                    icon: Icon(Icons.payments_outlined),
                    selectedIcon: Icon(Icons.payments),
                    label: Text('Pricing'),
                  ),
                  const NavigationRailDestination(
                    icon: Icon(Icons.compare_arrows_outlined),
                    selectedIcon: Icon(Icons.compare_arrows),
                    label: Text('Compare'),
                  ),
                  const NavigationRailDestination(
                    icon: Icon(Icons.toggle_off_outlined),
                    selectedIcon: Icon(Icons.toggle_on),
                    label: Text('Controls'),
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
                    if (state.openIncidents > 0 && state.tab != AdminTab.safety)
                      _SosBanner(
                        count: state.openIncidents,
                        onOpen: () => cubit.selectTab(AdminTab.safety),
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
        AdminTab.safety => 'Safety — SOS incidents',
        AdminTab.trips => 'Trips',
        AdminTab.users => 'Users',
        AdminTab.drivers => 'Drivers',
        AdminTab.live => 'Live map',
        AdminTab.support => 'Support',
        AdminTab.promos => 'Promotions',
        AdminTab.content => 'Content — cards under the ride',
        AdminTab.pricing => 'Pricing & surge',
        AdminTab.comparison => 'Price comparison & calibration',
        AdminTab.controls => 'Operational controls',
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
          Flexible(
            child: Text(title,
                style: theme.textTheme.headlineSmall,
                overflow: TextOverflow.ellipsis),
          ),
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
      AdminTab.drivers => _DriversView(
          drivers: state.drivers,
          pendingOnly: state.driversPendingOnly,
        ),
      AdminTab.live => _LiveView(live: state.live),
      AdminTab.safety => _SafetyView(incidents: state.incidents),
      AdminTab.support => _SupportView(state: state),
      AdminTab.promos => _PromosView(promos: state.promos),
      AdminTab.content => _ContentView(cards: state.rideCards),
      AdminTab.pricing => _PricingView(fares: state.fares, surge: state.surge),
      AdminTab.comparison =>
        _ComparisonView(models: state.comparisonModels),
      AdminTab.controls => _ControlsView(flags: state.opsFlags),
    };
  }
}

// --- Support ----------------------------------------------------------------

const _ticketFilters = <String, String>{
  'open': 'Open',
  'active': 'Active',
  'resolved': 'Resolved',
  'closed': 'Closed',
  '': 'All',
};

Color _ticketStatusColor(String status) => switch (status) {
      'open' => AppColors.warning,
      'active' => AppColors.accent,
      'resolved' => AppColors.success,
      _ => Colors.grey,
    };

class _SupportView extends StatelessWidget {
  const _SupportView({required this.state});
  final AdminState state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<AdminCubit>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.sm),
          child: Wrap(
            spacing: AppSpacing.sm,
            children: [
              for (final e in _ticketFilters.entries)
                ChoiceChip(
                  label: Text(e.value),
                  selected: state.ticketFilter == e.key,
                  onSelected: (_) => cubit.setTicketFilter(e.key),
                ),
            ],
          ),
        ),
        Expanded(
          child: state.tickets.isEmpty
              ? const _Empty(text: 'No tickets in this view.')
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
                  itemCount: state.tickets.length,
                  itemBuilder: (_, i) => _TicketTile(ticket: state.tickets[i]),
                ),
        ),
      ],
    );
  }
}

class _TicketTile extends StatelessWidget {
  const _TicketTile({required this.ticket});
  final AdminSupportTicket ticket;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _ticketStatusColor(ticket.status);
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            ticket.status,
            style: TextStyle(
                color: color, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
        title: Text(
          ticket.subject,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(ticket.category, style: theme.textTheme.bodySmall),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => showDialog<void>(
          context: context,
          builder: (_) => BlocProvider.value(
            value: context.read<AdminCubit>(),
            child: _TicketDialog(ticketId: ticket.id, subject: ticket.subject),
          ),
        ),
      ),
    );
  }
}

/// A modal thread view: loads the full conversation, lets the agent reply and
/// change status.
class _TicketDialog extends StatefulWidget {
  const _TicketDialog({required this.ticketId, required this.subject});
  final String ticketId;
  final String subject;

  @override
  State<_TicketDialog> createState() => _TicketDialogState();
}

class _TicketDialogState extends State<_TicketDialog> {
  final _reply = TextEditingController();
  AdminSupportTicket? _ticket;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final cubit = context.read<AdminCubit>();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final t = await cubit.ticketThread(widget.ticketId);
      if (mounted) setState(() => _ticket = t);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _send() async {
    final body = _reply.text.trim();
    if (body.isEmpty) return;
    final cubit = context.read<AdminCubit>();
    setState(() => _busy = true);
    try {
      final t = await cubit.replyTicket(widget.ticketId, body);
      if (!mounted) return;
      _reply.clear();
      setState(() => _ticket = t);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setStatus(String status) async {
    final cubit = context.read<AdminCubit>();
    setState(() => _busy = true);
    try {
      await cubit.setTicketStatus(widget.ticketId, status);
      await _load();
    } catch (_) {
      // error surfaced via cubit banner
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = _ticket;
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(widget.subject,
                        style: theme.textTheme.titleLarge),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              if (t != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: AppSpacing.sm,
                    children: [
                      for (final s in const ['active', 'resolved', 'closed'])
                        if (s != t.status)
                          OutlinedButton(
                            onPressed: _busy ? null : () => _setStatus(s),
                            child: Text('Mark $s'),
                          ),
                    ],
                  ),
                ),
              const Divider(),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                        ? Center(child: Text(_error!))
                        : ListView(
                            children: [
                              for (final m in t?.messages ?? const [])
                                _AdminBubble(message: m),
                            ],
                          ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _reply,
                      enabled: !_busy,
                      minLines: 1,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        hintText: 'Reply as support…',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  FilledButton(
                    onPressed: _busy ? null : _send,
                    child: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Send'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdminBubble extends StatelessWidget {
  const _AdminBubble({required this.message});
  final AdminSupportMessage message;

  @override
  Widget build(BuildContext context) {
    final admin = message.isFromAdmin;
    final theme = Theme.of(context);
    return Align(
      alignment: admin ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: const BoxConstraints(maxWidth: 380),
        decoration: BoxDecoration(
          color: admin
              ? AppColors.accent
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment:
              admin ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(
              admin ? 'Support' : 'User',
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: admin ? Colors.white70 : null,
              ),
            ),
            Text(
              message.body,
              style: TextStyle(color: admin ? Colors.white : null),
            ),
          ],
        ),
      ),
    );
  }
}

// --- Live map ---------------------------------------------------------------

/// A real-coordinate scatter of online drivers + active-trip pickups. No
/// external map tiles — positions are plotted within their own bounding box so
/// the ops team can see the fleet's spatial spread and statuses at a glance.
class _LiveView extends StatelessWidget {
  const _LiveView({required this.live});
  final LiveSnapshot live;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onTrip = live.drivers.where((d) => d.status != 'online').length;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _LiveStat(label: 'Online drivers', value: '${live.drivers.length}'),
              const SizedBox(width: AppSpacing.xl),
              _LiveStat(label: 'On a trip', value: '$onTrip'),
              const SizedBox(width: AppSpacing.xl),
              _LiveStat(label: 'Active trips', value: '${live.trips.length}'),
              const Spacer(),
              Row(children: [
                _Legend(color: AppColors.success, label: 'Idle'),
                SizedBox(width: AppSpacing.md),
                _Legend(color: AppColors.warning, label: 'On trip'),
                SizedBox(width: AppSpacing.md),
                _Legend(color: AppColors.accent, label: 'Pickup'),
              ]),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Expanded(
            child: live.drivers.isEmpty && live.trips.isEmpty
                ? Center(
                    child: Text('No drivers online right now.',
                        style: theme.textTheme.bodyLarge),
                  )
                : Card(
                    clipBehavior: Clip.antiAlias,
                    child: CustomPaint(
                      painter: _FleetPainter(live),
                      child: const SizedBox.expand(),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _LiveStat extends StatelessWidget {
  const _LiveStat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: theme.textTheme.headlineMedium),
        Text(label, style: theme.textTheme.bodySmall),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: AppSpacing.xs),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

/// Plots each driver/pickup as a dot within the lat/lng bounding box of all
/// points, with a little padding. A genuine visualization of live coordinates.
class _FleetPainter extends CustomPainter {
  _FleetPainter(this.live);
  final LiveSnapshot live;

  @override
  void paint(Canvas canvas, Size size) {
    final lats = <double>[
      ...live.drivers.map((d) => d.lat),
      ...live.trips.map((t) => t.pickupLat),
    ];
    final lngs = <double>[
      ...live.drivers.map((d) => d.lng),
      ...live.trips.map((t) => t.pickupLng),
    ];
    if (lats.isEmpty) return;

    var minLat = lats.reduce((a, b) => a < b ? a : b);
    var maxLat = lats.reduce((a, b) => a > b ? a : b);
    var minLng = lngs.reduce((a, b) => a < b ? a : b);
    var maxLng = lngs.reduce((a, b) => a > b ? a : b);
    // Avoid a zero-span box when all points coincide.
    if (maxLat - minLat < 1e-4) {
      minLat -= 0.01;
      maxLat += 0.01;
    }
    if (maxLng - minLng < 1e-4) {
      minLng -= 0.01;
      maxLng += 0.01;
    }
    const pad = 24.0;
    Offset project(double lat, double lng) {
      final x = pad +
          (lng - minLng) / (maxLng - minLng) * (size.width - 2 * pad);
      // Latitude increases upward, so invert Y.
      final y = pad +
          (maxLat - lat) / (maxLat - minLat) * (size.height - 2 * pad);
      return Offset(x, y);
    }

    final pickupPaint = Paint()..color = AppColors.accent.withValues(alpha: 0.8);
    for (final t in live.trips) {
      canvas.drawCircle(project(t.pickupLat, t.pickupLng), 4, pickupPaint);
    }
    for (final d in live.drivers) {
      final paint = Paint()
        ..color = d.status == 'online' ? AppColors.success : AppColors.warning;
      canvas.drawCircle(project(d.lat, d.lng), 6, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _FleetPainter old) => old.live != live;
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
                value: Money.format(s.grossRevenue, wholeOnly: true),
                icon: Icons.payments),
            _StatCard(
                label: 'Platform fees',
                value: Money.format(s.platformRevenue, wholeOnly: true),
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
    final tint = color ?? AppColors.accent;
    return Container(
      width: 208,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 40,
            width: 40,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
            child: Icon(icon, color: tint, size: 22),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(value, style: theme.textTheme.displaySmall),
          const SizedBox(height: 2),
          Text(label.toUpperCase(),
              style: theme.textTheme.labelMedium?.copyWith(
                color: AppColors.textTertiaryLight,
                letterSpacing: 0.6,
              )),
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
                prefixText: '${Money.symbol(trip.currency)} ',
                helperText: 'Fare ${Money.format(trip.fare, currency: trip.currency)}',
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
        SnackBar(
            content: Text(
                'Refunded ${Money.format(amount, currency: trip.currency)}')),
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
              Money.format(trip.fare, currency: trip.currency, wholeOnly: true),
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
  const _DriversView({required this.drivers, required this.pendingOnly});
  final List<AdminDriver> drivers;
  final bool pendingOnly;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<AdminCubit>();
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl, AppSpacing.lg, AppSpacing.xl, AppSpacing.sm),
          child: Row(
            children: [
              Text('Drivers', style: theme.textTheme.titleMedium),
              const SizedBox(width: AppSpacing.lg),
              FilterChip(
                label: const Text('Pending KYC only'),
                selected: pendingOnly,
                onSelected: cubit.setDriversPendingOnly,
              ),
            ],
          ),
        ),
        Expanded(
          child: drivers.isEmpty
              ? _Empty(
                  text: pendingOnly
                      ? 'No drivers awaiting verification.'
                      : 'No drivers onboarded yet.')
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.xl),
                  itemCount: drivers.length,
                  itemBuilder: (_, i) =>
                      _DriverCard(driver: drivers[i], cubit: cubit),
                ),
        ),
      ],
    );
  }
}

class _DriverCard extends StatelessWidget {
  const _DriverCard({required this.driver, required this.cubit});
  final AdminDriver driver;
  final AdminCubit cubit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final d = driver;
    final online = d.liveStatus != 'offline';
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Icon(Icons.circle,
                size: 12,
                color: online ? AppColors.success : theme.disabledColor),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(d.name ?? d.phone,
                            style: theme.textTheme.titleSmall,
                            overflow: TextOverflow.ellipsis),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      _KycChip(verified: d.docsVerified),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${d.vehicle}  •  ★ ${d.rating.toStringAsFixed(2)}  •  ${d.totalTrips} trips  •  ${d.liveStatus}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            // KYC action: approve pending drivers, or revoke a verified one.
            if (d.docsVerified)
              TextButton(
                onPressed: () => cubit.verifyDriver(d, false),
                child: const Text('Revoke'),
              )
            else
              FilledButton(
                onPressed: () => cubit.verifyDriver(d, true),
                child: const Text('Approve'),
              ),
          ],
        ),
      ),
    );
  }
}

class _KycChip extends StatelessWidget {
  const _KycChip({required this.verified});
  final bool verified;

  @override
  Widget build(BuildContext context) {
    final color = verified ? AppColors.success : AppColors.warning;
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppSpacing.pill),
      ),
      child: Text(
        verified ? 'Verified' : 'Pending KYC',
        style: TextStyle(
            color: color, fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }
}

// --- Promotions -------------------------------------------------------------

class _PromosView extends StatelessWidget {
  const _PromosView({required this.promos});
  final List<AdminPromo> promos;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<AdminCubit>();
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl, AppSpacing.lg, AppSpacing.xl, AppSpacing.sm),
          child: Row(
            children: [
              Text('Promo codes', style: theme.textTheme.titleMedium),
              const Spacer(),
              FilledButton.icon(
                onPressed: () => _showCreatePromo(context, cubit),
                icon: const Icon(Icons.add),
                label: const Text('New promo'),
              ),
            ],
          ),
        ),
        Expanded(
          child: promos.isEmpty
              ? const _Empty(text: 'No promo codes yet.')
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.xl),
                  itemCount: promos.length,
                  itemBuilder: (_, i) {
                    final p = promos[i];
                    final usage = p.usageLimit == null
                        ? '${p.usedCount} used'
                        : '${p.usedCount}/${p.usageLimit} used';
                    return Card(
                      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: ListTile(
                        title: Text(p.code, style: theme.textTheme.titleSmall),
                        subtitle: Text(
                          '${p.label}  •  min ${Money.format(p.minSubtotal, wholeOnly: true)}  •  $usage',
                          style: theme.textTheme.bodySmall,
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(p.active ? 'Active' : 'Off',
                                style: theme.textTheme.bodySmall),
                            Switch(
                              value: p.active,
                              onChanged: (v) => cubit.setPromoActive(p, v),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

Future<void> _showCreatePromo(BuildContext context, AdminCubit cubit) async {
  final code = TextEditingController();
  final value = TextEditingController();
  final minSubtotal = TextEditingController();
  final usageLimit = TextEditingController();
  String kind = 'flat';
  String? error;
  await showDialog<void>(
    context: context,
    builder: (dialogCtx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: const Text('New promo code'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: code,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                    labelText: 'Code', hintText: 'WELCOME10'),
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: kind,
                      decoration: const InputDecoration(labelText: 'Type'),
                      items: [
                        DropdownMenuItem(
                            value: 'flat', child: Text('${Money.symbol()} off')),
                        const DropdownMenuItem(
                            value: 'percent', child: Text('% off')),
                      ],
                      onChanged: (v) => setLocal(() => kind = v ?? 'flat'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: TextField(
                      controller: value,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                          labelText: kind == 'percent' ? 'Percent' : 'Amount'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: minSubtotal,
                      keyboardType: TextInputType.number,
                      decoration:
                          const InputDecoration(labelText: 'Min fare (opt)'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: TextField(
                      controller: usageLimit,
                      keyboardType: TextInputType.number,
                      decoration:
                          const InputDecoration(labelText: 'Usage cap (opt)'),
                    ),
                  ),
                ],
              ),
              if (error != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(error!,
                    style: const TextStyle(color: AppColors.error, fontSize: 12)),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final c = code.text.trim();
              final v = double.tryParse(value.text.trim());
              if (c.isEmpty || v == null || v <= 0) {
                setLocal(() => error = 'Enter a code and a positive value');
                return;
              }
              try {
                await cubit.createPromo({
                  'code': c,
                  'kind': kind,
                  'value': v,
                  if (minSubtotal.text.trim().isNotEmpty)
                    'minSubtotal': double.tryParse(minSubtotal.text.trim()),
                  if (usageLimit.text.trim().isNotEmpty)
                    'usageLimit': int.tryParse(usageLimit.text.trim()),
                });
                if (dialogCtx.mounted) Navigator.pop(dialogCtx);
              } catch (e) {
                setLocal(() => error = e.toString());
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    ),
  );
}

// --- Pricing & surge --------------------------------------------------------

class _PricingView extends StatelessWidget {
  const _PricingView({required this.fares, required this.surge});
  final List<AdminFare> fares;
  final AdminSurge surge;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<AdminCubit>();
    final theme = Theme.of(context);
    final active = (surge.override ?? 1.0) > 1.0;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        // Surge control.
        Text('Surge override', style: theme.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.xs),
        Text(
          active
              ? 'A ${surge.override!.toStringAsFixed(2)}× floor is active on all fares.'
              : 'No override — fares follow organic demand (cap ${surge.cap.toStringAsFixed(1)}×).',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          children: [
            for (final m in const [1.0, 1.25, 1.5, 1.75, 2.0])
              ChoiceChip(
                label: Text(m == 1.0 ? 'Off' : '$m×'),
                selected: (surge.override ?? 1.0) == m,
                onSelected: (_) => cubit.setSurge(m),
              ),
          ],
        ),
        if (surge.cells.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          Text('Live demand cells', style: theme.textTheme.labelLarge),
          const SizedBox(height: AppSpacing.xs),
          for (final c in surge.cells.take(6))
            Text('${c.cell}  —  ${c.demand} recent requests',
                style: theme.textTheme.bodySmall),
        ],
        const Divider(height: AppSpacing.xxl),
        // Fares.
        Text('Fares by tier', style: theme.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        for (final f in fares)
          Card(
            margin: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: ListTile(
              title: Text(f.label, style: theme.textTheme.titleSmall),
              subtitle: Text(
                'base ${Money.format(f.baseFare)} · '
                '${Money.format(_perUnitDistance(f.perMile))}/${Market.current.distanceUnit} · '
                '${Money.format(f.perMin)}/min · '
                'min ${Money.format(f.minFare)} · '
                'booking ${Money.format(f.bookingFee)}',
                style: theme.textTheme.bodySmall,
              ),
              trailing: TextButton(
                onPressed: () => _showEditFare(context, cubit, f),
                child: const Text('Edit'),
              ),
            ),
          ),
      ],
    );
  }
}

const _metresPerMile = 1609.344;

/// A per-mile rate as the market prices it: per km when metric.
double _perUnitDistance(double perMile) =>
    Market.current.metric ? perMile * 1000 / _metresPerMile : perMile;

/// Back to the stored per-mile rate from what the admin typed.
double _perMileFromUnit(double perUnit) =>
    Market.current.metric ? perUnit * _metresPerMile / 1000 : perUnit;

Future<void> _showEditFare(
    BuildContext context, AdminCubit cubit, AdminFare f) async {
  final base = TextEditingController(text: f.baseFare.toStringAsFixed(2));
  // Edited per km in metric markets; stored per mile (the pricing unit).
  final perMile = TextEditingController(
      text: _perUnitDistance(f.perMile).toStringAsFixed(2));
  final perMin = TextEditingController(text: f.perMin.toStringAsFixed(2));
  final minFare = TextEditingController(text: f.minFare.toStringAsFixed(2));
  final booking = TextEditingController(text: f.bookingFee.toStringAsFixed(2));
  String? error;

  Widget field(String label, TextEditingController c) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: TextField(
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration:
              InputDecoration(labelText: label, prefixText: '${Money.symbol()} '),
        ),
      );

  await showDialog<void>(
    context: context,
    builder: (dialogCtx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: Text('Edit ${f.label} fare'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              field('Base fare', base),
              field('Per ${Market.current.metric ? 'km' : 'mile'}', perMile),
              field('Per minute', perMin),
              field('Minimum fare', minFare),
              field('Booking fee', booking),
              if (error != null)
                Text(error!,
                    style:
                        const TextStyle(color: AppColors.error, fontSize: 12)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final b = double.tryParse(base.text.trim());
              final pmi = double.tryParse(perMile.text.trim());
              final pmn = double.tryParse(perMin.text.trim());
              final mf = double.tryParse(minFare.text.trim());
              final bf = double.tryParse(booking.text.trim());
              if ([b, pmi, pmn, mf, bf].any((v) => v == null || v < 0)) {
                setLocal(() => error = 'All values must be 0 or more');
                return;
              }
              try {
                await cubit.updateFare(f.tier, {
                  'baseFare': b,
                  'perMile': _perMileFromUnit(pmi!),
                  'perMin': pmn,
                  'minFare': mf,
                  'bookingFee': bf,
                });
                if (dialogCtx.mounted) Navigator.pop(dialogCtx);
              } catch (e) {
                setLocal(() => error = e.toString());
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}


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

// --- Price comparison & calibration -----------------------------------------

class _ComparisonView extends StatelessWidget {
  const _ComparisonView({required this.models});
  final List<AdminComparisonModel> models;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cubit = context.read<AdminCubit>();
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        Text('Competitor rate cards', style: theme.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Modeled from published fares — not live quotes. Record real observed '
          'fares below and the model re-fits itself to track them per market.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: AppSpacing.md),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: () => _showRecordSample(context, cubit, models),
            icon: const Icon(Icons.add_chart_outlined, size: 18),
            label: const Text('Record observed fare'),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        for (final m in models)
          Card(
            margin: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: ListTile(
              title: Row(
                children: [
                  Text('${m.displayName} · ${m.productName}',
                      style: theme.textTheme.titleSmall),
                  const SizedBox(width: AppSpacing.sm),
                  _CalibrationChip(
                      calibrated: m.calibrated, residualPct: m.residualPct),
                ],
              ),
              subtitle: Text(
                // Competitor rate cards are US fares (USD, per mile).
                'base \$${m.baseFare.toStringAsFixed(2)} · '
                '\$${m.perMile.toStringAsFixed(2)}/mi · '
                '\$${m.perMin.toStringAsFixed(2)}/min · '
                'min \$${m.minFare.toStringAsFixed(2)} · '
                'booking \$${m.bookingFee.toStringAsFixed(2)} (USD)',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ),
        if (models.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xl),
            child: Text('No competitor models loaded.',
                style: theme.textTheme.bodySmall),
          ),
      ],
    );
  }
}

class _CalibrationChip extends StatelessWidget {
  const _CalibrationChip({required this.calibrated, required this.residualPct});
  final bool calibrated;
  final double residualPct;

  @override
  Widget build(BuildContext context) {
    final color = calibrated ? AppColors.success : AppColors.warning;
    final label = calibrated
        ? 'calibrated · ${(residualPct * 100).toStringAsFixed(1)}% err'
        : 'seed defaults';
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}

Future<void> _showRecordSample(
  BuildContext context,
  AdminCubit cubit,
  List<AdminComparisonModel> models,
) async {
  final providers =
      models.isEmpty ? ['uber', 'lyft', 'empower'] : models.map((m) => m.provider).toList();
  var provider = providers.first;
  final miles = TextEditingController();
  final minutes = TextEditingController();
  final fare = TextEditingController();
  final surge = TextEditingController(text: '1.0');
  String? error;
  var saving = false;

  Widget field(String label, TextEditingController c, {String? prefix}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: TextField(
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: label, prefixText: prefix),
        ),
      );

  await showDialog<void>(
    context: context,
    builder: (dialogCtx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: const Text('Record observed competitor fare'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: provider,
                decoration: const InputDecoration(labelText: 'Provider'),
                items: [
                  for (final p in providers)
                    DropdownMenuItem(value: p, child: Text(p)),
                ],
                onChanged: (v) => setLocal(() => provider = v ?? provider),
              ),
              const SizedBox(height: AppSpacing.sm),
              field('Trip distance (miles)', miles),
              field('Trip duration (minutes)', minutes),
              field('Observed fare (USD)', fare, prefix: '\$ '),
              field('Surge at the time (1.0 = none)', surge, prefix: '× '),
              if (error != null)
                Text(error!,
                    style:
                        const TextStyle(color: AppColors.error, fontSize: 12)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: saving ? null : () => Navigator.pop(dialogCtx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: saving
                ? null
                : () async {
                    final mi = double.tryParse(miles.text.trim());
                    final mn = double.tryParse(minutes.text.trim());
                    final f = double.tryParse(fare.text.trim());
                    final s = double.tryParse(surge.text.trim()) ?? 1.0;
                    if (mi == null || mn == null || f == null || mi <= 0) {
                      setLocal(() => error = 'Enter valid distance, time, fare.');
                      return;
                    }
                    setLocal(() {
                      saving = true;
                      error = null;
                    });
                    try {
                      await cubit.recordFareSample({
                        'provider': provider,
                        'distanceM': (mi * 1609.34).round(),
                        'durationS': (mn * 60).round(),
                        'observedFare': f,
                        'surgeAtSample': s,
                        'source': 'admin',
                      });
                      if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                    } catch (e) {
                      setLocal(() {
                        saving = false;
                        error = '$e';
                      });
                    }
                  },
            child: saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Save'),
          ),
        ],
      ),
    ),
  );
}

// --- Operational controls ---------------------------------------------------

/// The kill switches.
///
/// Every one of these changes how the marketplace behaves for real users, so
/// each is confirmed before it takes effect and each says plainly what it will
/// do. They are all reversible, and every flip is recorded in the audit log by
/// the backend without this screen doing anything.
class _ControlsView extends StatelessWidget {
  const _ControlsView({required this.flags});

  final List<OpsFlag> flags;

  /// Off is the healthy state, so an active switch is drawn as a warning
  /// rather than as a neutral "on".
  static const _activeTone = AppColors.warning;

  @override
  Widget build(BuildContext context) {
    if (flags.isEmpty) {
      return const _Empty(text: 'No operational controls available.');
    }
    final theme = Theme.of(context);
    final active = flags.where((f) => f.on).length;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        if (active > 0)
          Container(
            margin: const EdgeInsets.only(bottom: AppSpacing.lg),
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: _activeTone.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppSpacing.radius),
              border: Border.all(color: _activeTone),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: _activeTone),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    active == 1
                        ? '1 control is active — the marketplace is not '
                            'running normally.'
                        : '$active controls are active — the marketplace is '
                            'not running normally.',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
          ),
        Text(
          'Each of these takes effect immediately, on every server, and is '
          'recorded against your account. All are reversible.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: AppSpacing.lg),
        for (final flag in flags)
          Card(
            margin: const EdgeInsets.only(bottom: AppSpacing.md),
            child: SwitchListTile(
              value: flag.on,
              activeTrackColor: _activeTone,
              title: Text(flag.label, style: theme.textTheme.titleMedium),
              subtitle: Text(
                flag.on ? 'Active' : 'Off (normal operation)',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: flag.on ? _activeTone : null,
                ),
              ),
              secondary: Icon(
                flag.on ? Icons.toggle_on : Icons.toggle_off_outlined,
                color: flag.on ? _activeTone : null,
              ),
              onChanged: (next) => _confirm(context, flag, next),
            ),
          ),
      ],
    );
  }

  Future<void> _confirm(BuildContext context, OpsFlag flag, bool next) async {
    final cubit = context.read<AdminCubit>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(next ? 'Activate this control?' : 'Turn this control off?'),
        content: Text(
          next
              ? '${flag.label}\n\nThis changes how the app behaves for every '
                  'rider and driver, immediately. It is reversible.'
              : '${flag.label}\n\nNormal operation resumes immediately.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: next
                ? FilledButton.styleFrom(backgroundColor: _activeTone)
                : null,
            child: Text(next ? 'Activate' : 'Turn off'),
          ),
        ],
      ),
    );
    if (ok == true) await cubit.setOpsFlag(flag.name, next);
  }
}

/// Shown on every tab except Safety while any SOS is unacknowledged.
class _SosBanner extends StatelessWidget {
  const _SosBanner({required this.count, required this.onOpen});

  final int count;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Material(
        color: AppColors.errorInk,
        child: InkWell(
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xl, vertical: AppSpacing.md),
            child: Row(
              children: [
                const Icon(Icons.sos_rounded, color: Colors.white),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    count == 1
                        ? 'An SOS is waiting for someone to acknowledge it.'
                        : '$count SOS alerts are waiting for someone to acknowledge them.',
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w700),
                  ),
                ),
                const Text('Open Safety',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w700)),
                const Icon(Icons.chevron_right_rounded, color: Colors.white),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SafetyView extends StatelessWidget {
  const _SafetyView({required this.incidents});

  final List<AdminSafetyIncident> incidents;

  @override
  Widget build(BuildContext context) {
    if (incidents.isEmpty) {
      return const EmptyState(
        icon: Icons.health_and_safety_outlined,
        title: 'No SOS incidents',
        message: 'When a rider or driver presses SOS during a ride it appears '
            'here within seconds, and a banner shows on every tab until '
            'someone acknowledges it.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.xl),
      itemCount: incidents.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
      itemBuilder: (_, i) => _IncidentCard(incident: incidents[i]),
    );
  }
}

class _IncidentCard extends StatelessWidget {
  const _IncidentCard({required this.incident});

  final AdminSafetyIncident incident;

  static String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 24) return '${d.inHours} h ago';
    return '${d.inDays} d ago';
  }

  Future<void> _resolve(BuildContext context) async {
    final cubit = context.read<AdminCubit>();
    final note = TextEditingController(text: incident.note ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Resolve this SOS'),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: note,
            autofocus: true,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'What happened?',
              hintText: 'e.g. Called the rider — she is safe at home.',
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Resolve')),
        ],
      ),
    );
    final text = note.text.trim();
    note.dispose();
    if (ok != true) return;
    await cubit.updateIncident(incident.id, 'resolved',
        note: text.isEmpty ? null : text);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final i = incident;
    final (color, label) = switch (i.status) {
      'open' => (AppColors.error, 'OPEN'),
      'acknowledged' => (AppColors.warning, 'ACKNOWLEDGED'),
      _ => (AppColors.success, 'RESOLVED'),
    };
    final raiser = i.raisedBy;
    final other = i.raisedByRole == 'driver' ? i.rider : i.driver;

    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 4,
            height: 96,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(label,
                        style: theme.textTheme.labelMedium?.copyWith(
                            color: color, fontWeight: FontWeight.w800)),
                    const SizedBox(width: AppSpacing.sm),
                    Text('· ${_ago(i.createdAt)} · trip ${i.tripStatus.replaceAll('_', ' ')}',
                        style: theme.textTheme.bodySmall),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  raiser?.name == null
                      ? 'A ${i.raisedByRole} (no name on the account) pressed SOS'
                      : '${i.raisedByRole == 'driver' ? 'Driver' : 'Rider'} '
                          '${raiser!.name} pressed SOS',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.xs),
                SelectableText(
                  [
                    if (raiser?.phone != null) 'Call them: ${raiser!.phone}',
                    if (other != null)
                      '${i.raisedByRole == 'driver' ? 'Rider' : 'Driver'}: '
                          '${other.name ?? '(no name)'} ${other.phone ?? ''}',
                    if (i.driver?.plate != null) 'Plate ${i.driver!.plate}',
                  ].join('   ·   '),
                  style: theme.textTheme.bodyMedium,
                ),
                if (i.pickup != null || i.dropoff != null)
                  Text('${i.pickup ?? '?'}  →  ${i.dropoff ?? '?'}',
                      style: theme.textTheme.bodySmall),
                Text(
                  i.contactsTotal == 0
                      ? 'No emergency contacts saved — nobody was texted.'
                      : 'Texted ${i.contactsNotified} of ${i.contactsTotal} emergency contacts.',
                  style: theme.textTheme.bodySmall,
                ),
                if (i.note != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text('Note: ${i.note}',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(fontStyle: FontStyle.italic)),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (i.mapUrl != null)
                OutlinedButton.icon(
                  onPressed: () => openExternalUrl(i.mapUrl!),
                  icon: const Icon(Icons.map_outlined, size: 18),
                  label: const Text('Location'),
                ),
              const SizedBox(height: AppSpacing.sm),
              if (i.isOpen)
                FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: AppColors.errorInk),
                  onPressed: () => context
                      .read<AdminCubit>()
                      .updateIncident(i.id, 'acknowledged'),
                  child: const Text("I'm on it"),
                ),
              if (i.status != 'resolved')
                TextButton(
                  onPressed: () => _resolve(context),
                  child: const Text('Resolve…'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Promo / recommendation cards riders see under the ride details.
class _ContentView extends StatelessWidget {
  const _ContentView({required this.cards});

  final List<AdminRideCard> cards;

  Future<void> _edit(BuildContext context, [AdminRideCard? card]) async {
    await showDialog<void>(
      context: context,
      builder: (_) => BlocProvider.value(
        value: context.read<AdminCubit>(),
        child: _RideCardEditor(card: card),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final live = cards.where((c) => c.isLiveAt(now)).length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.xl),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                live == 0
                    ? 'No card is live — riders see nothing under the ride.'
                    : '$live live now. Riders see up to 3, lowest order first.',
                style: theme.textTheme.bodyMedium,
              ),
            ),
            FilledButton.icon(
              onPressed: () => _edit(context),
              icon: const Icon(Icons.add),
              label: const Text('New card'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        if (cards.isEmpty)
          const EmptyState(
            icon: Icons.view_carousel_outlined,
            title: 'No cards yet',
            message: 'A card is a short offer or tip shown under the ride '
                'details while a rider waits — optionally with a promo code '
                'to copy or a link to open.',
          ),
        for (final c in cards) ...[
          AppCard(
            child: Row(
              children: [
                SizedBox(
                  width: 72,
                  child: Text(
                    c.isLiveAt(now) ? 'LIVE' : (c.active ? 'SCHEDULED' : 'PAUSED'),
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: c.isLiveAt(now) ? AppColors.success : AppColors.textTertiaryLight,
                    ),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('#${c.sortOrder}  ${c.title}', style: theme.textTheme.titleSmall),
                      Text(c.body, style: theme.textTheme.bodySmall),
                      if (c.ctaType != 'none')
                        Text(
                          c.ctaType == 'promo_code'
                              ? '“${c.ctaLabel}” copies code ${c.ctaValue}'
                              : '“${c.ctaLabel}” opens ${c.ctaValue}',
                          style: theme.textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
                Switch(
                  value: c.active,
                  onChanged: (v) => context
                      .read<AdminCubit>()
                      .saveRideCard({'active': v}, id: c.id),
                ),
                IconButton(
                  tooltip: 'Edit',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => _edit(context, c),
                ),
                IconButton(
                  tooltip: 'Delete',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => context.read<AdminCubit>().deleteRideCard(c.id),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ],
    );
  }
}

class _RideCardEditor extends StatefulWidget {
  const _RideCardEditor({this.card});

  final AdminRideCard? card;

  @override
  State<_RideCardEditor> createState() => _RideCardEditorState();
}

class _RideCardEditorState extends State<_RideCardEditor> {
  late final _title = TextEditingController(text: widget.card?.title ?? '');
  late final _body = TextEditingController(text: widget.card?.body ?? '');
  late final _label = TextEditingController(text: widget.card?.ctaLabel ?? '');
  late final _value = TextEditingController(text: widget.card?.ctaValue ?? '');
  late final _order =
      TextEditingController(text: '${widget.card?.sortOrder ?? 0}');
  late String _type = widget.card?.ctaType ?? 'none';
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_title, _body, _label, _value, _order]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await context.read<AdminCubit>().saveRideCard({
        'title': _title.text.trim(),
        'body': _body.text.trim(),
        'ctaType': _type,
        if (_type != 'none') 'ctaLabel': _label.text.trim(),
        if (_type != 'none') 'ctaValue': _value.text.trim(),
        'sortOrder': int.tryParse(_order.text.trim()) ?? 0,
      }, id: widget.card?.id);
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.card == null ? 'New card' : 'Edit card'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _title,
                maxLength: 80,
                decoration: const InputDecoration(labelText: 'Title'),
              ),
              TextField(
                controller: _body,
                maxLength: 240,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Text'),
              ),
              DropdownButtonFormField<String>(
                initialValue: _type,
                decoration: const InputDecoration(labelText: 'Button'),
                items: const [
                  DropdownMenuItem(value: 'none', child: Text('No button')),
                  DropdownMenuItem(value: 'promo_code', child: Text('Copy a promo code')),
                  DropdownMenuItem(value: 'url', child: Text('Open a link')),
                ],
                onChanged: (v) => setState(() => _type = v ?? 'none'),
              ),
              if (_type != 'none') ...[
                TextField(
                  controller: _label,
                  maxLength: 40,
                  decoration: const InputDecoration(labelText: 'Button label'),
                ),
                TextField(
                  controller: _value,
                  decoration: InputDecoration(
                    labelText: _type == 'url' ? 'Link (https://…)' : 'Promo code',
                  ),
                ),
              ],
              TextField(
                controller: _order,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'Order (lower shows first)'),
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.md),
                Text(_error!, style: const TextStyle(color: AppColors.error)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Saving…' : 'Save'),
        ),
      ],
    );
  }
}

