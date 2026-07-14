import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_models/shared_models.dart';

import '../auth/bloc/auth_bloc.dart';
import '../di/injector.dart';
import '../driver/driver_remote_data_source.dart';
import '../trip/payments_remote_data_source.dart';
import '../trip/places_remote_data_source.dart';
import '../trip/trip_remote_data_source.dart';
import 'driver_earnings_page.dart';
import 'payment_methods_page.dart';
import 'profile_edit_page.dart';
import 'saved_places_page.dart';
import 'scheduled_rides_page.dart';
import 'trip_history_page.dart';
import 'users_remote_data_source.dart';

/// Account hub reached from the rider/driver home menu. Shows a profile header
/// and navigates to history, places, payments, earnings, and profile editing.
/// Role-aware: drivers see Earnings; riders see Saved places + Payment methods.
class AccountMenuPage extends StatefulWidget {
  const AccountMenuPage({super.key, this.isDriver = false});

  final bool isDriver;

  @override
  State<AccountMenuPage> createState() => _AccountMenuPageState();
}

class _AccountMenuPageState extends State<AccountMenuPage> {
  AppUser? _user;

  @override
  void initState() {
    super.initState();
    _user = context.read<AuthBloc>().state.user;
  }

  Future<void> _editProfile() async {
    final user = _user;
    if (user == null) return;
    final updated = await Navigator.of(context).push<AppUser>(
      MaterialPageRoute(
        builder: (_) => ProfileEditPage(
          users: sl<UsersRemoteDataSource>(),
          user: user,
        ),
      ),
    );
    if (updated != null && mounted) setState(() => _user = updated);
  }

  void _open(Widget page) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    final user = _user;
    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: ListView(
        children: [
          _ProfileHeader(user: user, onEdit: _editProfile),
          const Divider(height: 1),
          _tile(
            icon: Icons.receipt_long_outlined,
            title: 'Your trips',
            onTap: () => _open(TripHistoryPage(
              trips: sl<TripRemoteDataSource>(),
              payments: sl<PaymentsRemoteDataSource>(),
              isDriver: widget.isDriver,
            )),
          ),
          if (widget.isDriver)
            _tile(
              icon: Icons.account_balance_wallet_outlined,
              title: 'Earnings',
              onTap: () => _open(
                  DriverEarningsPage(driver: sl<DriverRemoteDataSource>())),
            ),
          if (!widget.isDriver) ...[
            _tile(
              icon: Icons.schedule,
              title: 'Scheduled rides',
              onTap: () => _open(ScheduledRidesPage(
                trips: sl<TripRemoteDataSource>(),
              )),
            ),
            _tile(
              icon: Icons.star_border,
              title: 'Saved places',
              onTap: () => _open(SavedPlacesPage(
                users: sl<UsersRemoteDataSource>(),
                places: sl<PlacesRemoteDataSource>(),
              )),
            ),
            _tile(
              icon: Icons.credit_card,
              title: 'Payment methods',
              onTap: () => _open(PaymentMethodsPage(
                payments: sl<PaymentsRemoteDataSource>(),
              )),
            ),
          ],
          const Divider(height: 1),
          _tile(
            icon: Icons.logout,
            title: 'Sign out',
            danger: true,
            onTap: () => context.read<AuthBloc>().add(const AuthSignedOut()),
          ),
        ],
      ),
    );
  }

  Widget _tile({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    bool danger = false,
  }) {
    final color = danger ? AppColors.error : null;
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(title, style: TextStyle(color: color)),
      trailing: danger
          ? null
          : const Icon(Icons.chevron_right, size: 20),
      onTap: onTap,
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.user, required this.onEdit});
  final AppUser? user;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = (user?.fullName?.trim().isNotEmpty ?? false)
        ? user!.fullName!
        : 'Add your name';
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        children: [
          const CircleAvatar(radius: 28, child: Icon(Icons.person, size: 30)),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: theme.textTheme.titleLarge),
                const SizedBox(height: 2),
                Text(user?.phone ?? '', style: theme.textTheme.bodyMedium),
                if ((user?.ratingCount ?? 0) > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Row(
                      children: [
                        const Icon(Icons.star,
                            size: 14, color: AppColors.warning),
                        const SizedBox(width: 2),
                        Text(user!.ratingAvg.toStringAsFixed(1),
                            style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: onEdit,
          ),
        ],
      ),
    );
  }
}
