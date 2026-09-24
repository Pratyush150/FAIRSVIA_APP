import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_models/shared_models.dart';

import '../auth/bloc/auth_bloc.dart';
import '../di/injector.dart';
import '../driver/driver_remote_data_source.dart';
import '../trip/payments_remote_data_source.dart';
import '../trip/places_remote_data_source.dart';
import '../safety/emergency_contacts_page.dart';
import '../safety/safety_remote_data_source.dart';
import '../trip/trip_remote_data_source.dart';
import 'driver_earnings_page.dart';
import 'format.dart';
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
import '../theme/appearance_sheet.dart';
import '../theme/theme_controller.dart';

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
    this.profileDetails,
  });

  final bool isDriver;

  /// App-specific facts shown inside the profile card, under the name and
  /// phone (the driver app puts rating, trips and plate here). When given, it
  /// owns the rating too, so the card's own rating line is not repeated.
  final Widget? profileDetails;

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
        builder: (_) =>
            ProfileEditPage(users: sl<UsersRemoteDataSource>(), user: user),
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
        content: Text(
          widget.isDriver
              ? "You'll go offline and stop receiving trip requests."
              : "You'll need a new code to sign back in.",
        ),
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
    _open(
      DeleteAccountPage(
        users: sl<UsersRemoteDataSource>(),
        isDriver: widget.isDriver,
        onBeforeDelete: widget.onBeforeSignOut,
        onDeleted: () {
          navigator.popUntil((r) => r.isFirst);
          messenger
            ..hideCurrentSnackBar()
            ..showSnackBar(
              const SnackBar(content: Text('Your account has been deleted.')),
            );
          bloc.add(const AuthSignedOut());
        },
      ),
    );
  }

  void _open(Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    final user = _user;
    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.xxl,
        ),
        children: [
          _ProfileHeader(
            user: user,
            onEdit: _editProfile,
            details: widget.profileDetails,
          ),
          const SizedBox(height: AppSpacing.xl),
          _group([
            _Item(
              icon: PhosphorIconsRegular.bell,
              title: 'Notifications',
              onTap: () => _open(InboxPage(inbox: sl<InboxRemoteDataSource>())),
            ),
            _Item(
              icon: PhosphorIconsRegular.receipt,
              title: 'Your trips',
              onTap: () => _open(
                TripHistoryPage(
                  trips: sl<TripRemoteDataSource>(),
                  payments: sl<PaymentsRemoteDataSource>(),
                  isDriver: widget.isDriver,
                ),
              ),
            ),
          ]),
          const SizedBox(height: AppSpacing.lg),
          if (widget.isDriver)
            _group([
              _Item(
                icon: PhosphorIconsRegular.wallet,
                title: 'Earnings',
                onTap: () => _open(
                  DriverEarningsPage(driver: sl<DriverRemoteDataSource>()),
                ),
              ),
              _Item(
                icon: PhosphorIconsRegular.money,
                title: 'Payouts',
                onTap: () => _open(
                  DriverPayoutsPage(driver: sl<DriverRemoteDataSource>()),
                ),
              ),
              if (widget.onVehicle != null)
                _Item(
                  icon: PhosphorIconsRegular.car,
                  title: 'Vehicle',
                  onTap: widget.onVehicle!,
                ),
            ]),
          if (!widget.isDriver)
            _group([
              _Item(
                icon: PhosphorIconsRegular.clock,
                title: 'Scheduled rides',
                onTap: () => _open(
                  ScheduledRidesPage(trips: sl<TripRemoteDataSource>()),
                ),
              ),
              _Item(
                // Regular, not Fill: nothing is "on" here — Fill is for a
                // state (a rated star, a favourited driver). Audit 2.1 rule 3.
                icon: PhosphorIconsRegular.star,
                title: 'Saved places',
                onTap: () => _open(
                  SavedPlacesPage(
                    users: sl<UsersRemoteDataSource>(),
                    places: sl<PlacesRemoteDataSource>(),
                  ),
                ),
              ),
              _Item(
                icon: PhosphorIconsRegular.creditCard,
                title: 'Payment methods',
                onTap: () => _open(
                  PaymentMethodsPage(
                    payments: sl<PaymentsRemoteDataSource>(),
                    // Real Stripe PaymentSheet if the app registered one, else the
                    // mock add-card sheet.
                    stripeCardAdder: sl.isRegistered<StripeCardAdder>()
                        ? sl<StripeCardAdder>()
                        : null,
                  ),
                ),
              ),
              _Item(
                icon: PhosphorIconsRegular.heart,
                title: 'Favourite drivers',
                onTap: () => _open(
                  FavoriteDriversPage(
                    favorites: sl<FavoritesRemoteDataSource>(),
                  ),
                ),
              ),
            ]),
          const SizedBox(height: AppSpacing.lg),
          _group([
            _Item(
              icon: PhosphorIconsRegular.addressBook,
              title: 'Emergency contacts',
              onTap: () => _open(
                EmergencyContactsPage(safety: sl<SafetyRemoteDataSource>()),
              ),
            ),
            _Item(
              icon: PhosphorIconsRegular.circleHalf,
              title: 'Appearance',
              onTap: () => showAppearanceSheet(context, sl<ThemeController>()),
            ),
            _Item(
              icon: PhosphorIconsRegular.headset,
              title: 'Help & support',
              onTap: () => _open(
                SupportPage(
                  support: sl<SupportRemoteDataSource>(),
                  isDriver: widget.isDriver,
                ),
              ),
            ),
          ]),
          const SizedBox(height: AppSpacing.lg),
          _group([
            _Item(
              icon: PhosphorIconsRegular.signOut,
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
              // Starts under the title: 12 inset + 24 icon + 12 gap.
              const Divider(height: 1, indent: 48, endIndent: AppSpacing.md),
            _tile(items[i]),
          ],
        ],
      ),
    );
  }

  Widget _tile(_Item item) {
    return Builder(
      builder: (context) {
        final theme = Theme.of(context);
        final dark = theme.brightness == Brightness.dark;
        final color = item.danger ? AppColors.dangerFor(dark) : null;
        return InkWell(
          onTap: item.onTap,
          borderRadius: BorderRadius.circular(AppSpacing.radius),
          child: Padding(
            // 12 + 24 + 12 = 48 px rows: above the 44 pt touch minimum.
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.md,
            ),
            // Icon, title and chevron share one centre line: the title's
            // line box is single-height with even leading, so its glyphs sit
            // on the same axis as the 24 px icon and the 20 px chevron
            // instead of riding high in a 1.3× line.
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(
                  item.icon,
                  size: 24,
                  // Neutral glyph colour (audit 2.1 rule 4): colour only
                  // when it means something — here, danger.
                  color: color ?? AppColors.iconNeutralFor(dark),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    item.title,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(color: color, height: 1.0),
                    textHeightBehavior: const TextHeightBehavior(
                      leadingDistribution: TextLeadingDistribution.even,
                    ),
                  ),
                ),
                if (!item.danger)
                  Icon(
                    PhosphorIconsRegular.caretRight,
                    size: 20,
                    color: AppColors.iconNeutralFor(dark),
                  ),
              ],
            ),
          ),
        );
      },
    );
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
  const _ProfileHeader({required this.user, required this.onEdit, this.details});
  final AppUser? user;
  final VoidCallback onEdit;
  final Widget? details;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final hasName = user?.fullName?.trim().isNotEmpty ?? false;
    final name = hasName ? user!.fullName! : 'Add your name';
    final identity = Row(
      children: [
        AppAvatar(name: hasName ? name : null, size: 56),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: theme.textTheme.titleLarge),
              const SizedBox(height: 2),
              // Spaced the way it is read aloud, and in tabular figures so
              // the groups line up.
              Text(
                Fmt.phone(user?.phone),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              if (details == null && (user?.ratingCount ?? 0) > 0)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Row(
                    children: [
                      const Icon(
                        PhosphorIconsFill.star,
                        size: 16,
                        color: AppColors.star,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        user!.ratingAvg.toStringAsFixed(1),
                        style: theme.textTheme.labelLarge,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        Icon(
          PhosphorIconsRegular.pencilSimple,
          size: 20,
          color: AppColors.iconNeutralFor(dark),
        ),
      ],
    );
    final extra = details;
    if (extra == null) return AppCard(onTap: onEdit, child: identity);
    // Only the identity row edits the profile; the details below are facts,
    // not a second way into the editor.
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: onEdit,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AppSpacing.radius),
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: identity,
              ),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: extra,
          ),
        ],
      ),
    );
  }
}
