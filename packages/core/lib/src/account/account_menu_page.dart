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
import 'delete_account_page.dart';
import 'driver_payouts_page.dart';
import 'favorite_drivers_page.dart';
import 'favorites_remote_data_source.dart';
import 'inbox_page.dart';
import 'inbox_remote_data_source.dart';
import 'profile_edit_page.dart';
import 'saved_places_page.dart';
import 'scheduled_rides_page.dart';
import 'support_page.dart';
import 'support_remote_data_source.dart';
import 'trip_history_page.dart';
import 'users_remote_data_source.dart';

/// Account hub reached from the rider/driver home menu. Shows a profile header
/// and navigates to history, places, payments, earnings, and profile editing.
/// Role-aware: drivers see Earnings; riders see Saved places + Payment methods.
class AccountMenuPage extends StatefulWidget {
  const AccountMenuPage({
    super.key,
    this.isDriver = false,
    this.onVehicle,
    this.onBeforeSignOut,
    this.signOutBlocker,
  });

  final bool isDriver;

  /// Drivers: opens the vehicle editor (shown as a "Vehicle" row).
  final VoidCallback? onVehicle;

  /// Runs after the user confirms sign-out and before the session is dropped
  /// (the driver app uses it to go offline first).
  final Future<void> Function()? onBeforeSignOut;

  /// Returns a message when signing out must be refused right now (e.g. a
  /// driver with a live trip), or null to allow it.
  final String? Function()? signOutBlocker;

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
    if (updated == null || !mounted) return;
    // Refresh AuthBloc's cached user too, so every other reader of
    // `state.user` (home drawer, name gate, next visit here) sees the edit.
    context.read<AuthBloc>().add(AuthProfileCompleted(updated));
    setState(() => _user = updated);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Profile updated.')));
  }

  Future<void> _confirmSignOut() async {
    final blocked = widget.signOutBlocker?.call();
    if (blocked != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(blocked)));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: Text(widget.isDriver
            ? "You'll go offline and stop receiving trip requests."
            : "You'll need a new code to sign back in."),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final bloc = context.read<AuthBloc>();
    try {
      await widget.onBeforeSignOut?.call();
    } catch (_) {
      // Going offline is best effort; the sign-out itself must not be stuck.
    }
    bloc.add(const AuthSignedOut());
  }

  void _openDeleteAccount() {
    final blocked = widget.signOutBlocker?.call();
    if (blocked != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(blocked)));
      return;
    }
    final bloc = context.read<AuthBloc>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    _open(DeleteAccountPage(
      users: sl<UsersRemoteDataSource>(),
      isDriver: widget.isDriver,
      onBeforeDelete: widget.onBeforeSignOut,
      onDeleted: () {
        navigator.popUntil((r) => r.isFirst);
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
              const SnackBar(content: Text('Your account has been deleted.')));
        bloc.add(const AuthSignedOut());
      },
    ));
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
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xxl),
        children: [
          _ProfileHeader(user: user, onEdit: _editProfile),
          const SizedBox(height: AppSpacing.xl),
          _group([
            _Item(
              icon: Icons.notifications_none_rounded,
              title: 'Notifications',
              onTap: () =>
                  _open(InboxPage(inbox: sl<InboxRemoteDataSource>())),
            ),
            _Item(
              icon: Icons.receipt_long_rounded,
              title: 'Your trips',
              onTap: () => _open(TripHistoryPage(
                trips: sl<TripRemoteDataSource>(),
                payments: sl<PaymentsRemoteDataSource>(),
                isDriver: widget.isDriver,
              )),
            ),
          ]),
          const SizedBox(height: AppSpacing.lg),
          if (widget.isDriver)
            _group([
              _Item(
                icon: Icons.account_balance_wallet_rounded,
                title: 'Earnings',
                onTap: () => _open(
                    DriverEarningsPage(driver: sl<DriverRemoteDataSource>())),
              ),
              _Item(
                icon: Icons.payments_rounded,
                title: 'Payouts',
                onTap: () => _open(
                    DriverPayoutsPage(driver: sl<DriverRemoteDataSource>())),
              ),
              if (widget.onVehicle != null)
                _Item(
                  icon: Icons.directions_car_rounded,
                  title: 'Vehicle',
                  onTap: widget.onVehicle!,
                ),
            ]),
          if (!widget.isDriver)
            _group([
              _Item(
                icon: Icons.schedule_rounded,
                title: 'Scheduled rides',
                onTap: () => _open(ScheduledRidesPage(
                  trips: sl<TripRemoteDataSource>(),
                )),
              ),
              _Item(
                icon: Icons.star_rounded,
                title: 'Saved places',
                onTap: () => _open(SavedPlacesPage(
                  users: sl<UsersRemoteDataSource>(),
                  places: sl<PlacesRemoteDataSource>(),
                )),
              ),
              _Item(
                icon: Icons.credit_card_rounded,
                title: 'Payment methods',
                onTap: () => _open(PaymentMethodsPage(
                  payments: sl<PaymentsRemoteDataSource>(),
                  // Real Stripe PaymentSheet if the app registered one, else the
                  // mock add-card sheet.
                  stripeCardAdder: sl.isRegistered<StripeCardAdder>()
                      ? sl<StripeCardAdder>()
                      : null,
                )),
              ),
              _Item(
                icon: Icons.favorite_rounded,
                title: 'Favourite drivers',
                onTap: () => _open(FavoriteDriversPage(
                  favorites: sl<FavoritesRemoteDataSource>(),
                )),
              ),
            ]),
          const SizedBox(height: AppSpacing.lg),
          _group([
            _Item(
              icon: Icons.support_agent_rounded,
              title: 'Help & support',
              onTap: () => _open(SupportPage(
                support: sl<SupportRemoteDataSource>(),
                isDriver: widget.isDriver,
              )),
            ),
          ]),
          const SizedBox(height: AppSpacing.lg),
          _group([
            _Item(
              icon: Icons.logout_rounded,
              title: 'Sign out',
              danger: true,
              onTap: _confirmSignOut,
            ),
          ]),
          const SizedBox(height: AppSpacing.xl),
          // Deliberately quiet: reachable (a store requirement) but not a
          // button anyone taps by accident next to "Sign out".
          Center(
            child: TextButton(
              onPressed: _openDeleteAccount,
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).brightness == Brightness.dark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondaryLight,
              ),
              child: const Text('Delete account'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _group(List<_Item> items) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0)
              const Divider(height: 1, indent: 60, endIndent: AppSpacing.md),
            _tile(items[i]),
          ],
        ],
      ),
    );
  }

  Widget _tile(_Item item) {
    final color = item.danger ? AppColors.error : null;
    return Builder(builder: (context) {
      final theme = Theme.of(context);
      return InkWell(
        onTap: item.onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              Icon(item.icon,
                  size: 22,
                  color: color ?? AppColors.textSecondaryLight),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  item.title,
                  style: theme.textTheme.titleSmall?.copyWith(color: color),
                ),
              ),
              if (!item.danger)
                const Icon(Icons.chevron_right_rounded,
                    size: 22, color: AppColors.textTertiaryLight),
            ],
          ),
        ),
      );
    });
  }
}

class _Item {
  const _Item({
    required this.icon,
    required this.title,
    required this.onTap,
    this.danger = false,
  });
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final bool danger;
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.user, required this.onEdit});
  final AppUser? user;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasName = user?.fullName?.trim().isNotEmpty ?? false;
    final name = hasName ? user!.fullName! : 'Add your name';
    return AppCard(
      onTap: onEdit,
      child: Row(
        children: [
          AppAvatar(name: hasName ? name : null, size: 56),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: theme.textTheme.titleLarge),
                const SizedBox(height: 2),
                Text(user?.phone ?? '',
                    style: theme.textTheme.bodyMedium),
                if ((user?.ratingCount ?? 0) > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: Row(
                      children: [
                        const Icon(Icons.star_rounded,
                            size: 15, color: AppColors.star),
                        const SizedBox(width: 3),
                        Text(user!.ratingAvg.toStringAsFixed(1),
                            style: theme.textTheme.labelLarge),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const Icon(Icons.edit_rounded,
              size: 20, color: AppColors.textTertiaryLight),
        ],
      ),
    );
  }
}
