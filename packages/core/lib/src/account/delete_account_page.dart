import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

import '../network/api_exception.dart';
import 'users_remote_data_source.dart';

/// Self-service account deletion (App Store 5.1.1(v), Google Play). Says
/// plainly what is erased and what the law makes us keep, asks for an explicit
/// acknowledgement, and surfaces the server's refusal (ride in progress,
/// unwithdrawn earnings) in place instead of failing silently.
class DeleteAccountPage extends StatefulWidget {
  const DeleteAccountPage({
    super.key,
    required this.users,
    required this.onDeleted,
    this.isDriver = false,
    this.onBeforeDelete,
  });

  final UsersRemoteDataSource users;
  final bool isDriver;

  /// Runs once the server has deleted the account — the app drops the local
  /// session here.
  final VoidCallback onDeleted;

  /// Drivers: go offline first so the live pool never offers them a trip
  /// mid-deletion.
  final Future<void> Function()? onBeforeDelete;

  @override
  State<DeleteAccountPage> createState() => _DeleteAccountPageState();
}

class _DeleteAccountPageState extends State<DeleteAccountPage> {
  bool _understood = false;
  bool _deleting = false;
  String? _error;

  Future<void> _delete() async {
    setState(() {
      _deleting = true;
      _error = null;
    });
    try {
      try {
        await widget.onBeforeDelete?.call();
      } catch (_) {
        // Best effort: the server takes the driver offline itself.
      }
      await widget.users.deleteMe();
      if (!mounted) return;
      AppHaptics.medium();
      widget.onDeleted();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = switch (e.statusCode) {
            // A deliberate refusal: its message is written for the user.
            409 => e.message,
            // No response at all: the network layer's connectivity hint.
            null => e.message,
            // Anything else is ours, not theirs — never show raw server text.
            _ => 'Something went wrong on our side and nothing was deleted. '
                'Please try again in a moment.',
          });
    } catch (_) {
      if (mounted) {
        setState(() => _error = "We couldn't reach ${AppBrand.name}. "
            'Check your connection and try again.');
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final secondary =
        dark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    return Scaffold(
      appBar: AppBar(title: const Text('Delete account')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xl),
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: dark ? AppColors.errorSoftDark : AppColors.errorSoft,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(PhosphorIconsRegular.userMinus,
                        color: AppColors.error, size: 28),
                  ).motion((w) => w
                      .animate()
                      .fadeIn(duration: AppMotion.normal)
                      .scale(
                          begin: const Offset(0.85, 0.85),
                          curve: AppMotion.enter)),
                  const SizedBox(height: AppSpacing.lg),
                  Text('Delete your ${AppBrand.name} account?',
                      style: theme.textTheme.headlineSmall),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    "This can't be undone. Here's exactly what happens:",
                    style: theme.textTheme.bodyLarge?.copyWith(color: secondary),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  AppCard(
                    child: Column(
                      children: [
                        const _Fact(
                          icon: PhosphorIconsRegular.trash,
                          title: 'Erased',
                          body: 'Your name, email, photo, saved places, '
                              'cards, favourites, emergency contacts '
                              'and notifications.',
                        ),
                        const _Fact(
                          icon: PhosphorIconsRegular.calendarX,
                          title: 'Cancelled',
                          body: 'Any rides you have scheduled for later.',
                        ),
                        const _Fact(
                          icon: PhosphorIconsRegular.receipt,
                          title: 'Kept, as the law requires',
                          body: 'Trip and payment records, no longer '
                              'linked to your name or number.',
                        ),
                        _Fact(
                          icon: PhosphorIconsRegular.deviceMobile,
                          title: 'Your number is released',
                          body: 'You can sign up again with it later, '
                              'as a new account.',
                          last: !widget.isDriver,
                        ),
                        if (widget.isDriver)
                          const _Fact(
                            icon: PhosphorIconsRegular.wallet,
                            title: 'Earnings first',
                            body: 'Withdraw any balance before you delete — '
                                'it cannot be paid out afterwards.',
                            last: true,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.lg),
              child: Column(
                children: [
                  // In the fixed action area, not the scrolling list: a
                  // refusal must be visible right where the user just tapped,
                  // whatever the screen height.
                  if (_error != null) ...[
                    _ErrorNotice(message: _error!).motion((w) => w
                        .animate()
                        .fadeIn(duration: AppMotion.fast)
                        .slideY(begin: 0.15, curve: AppMotion.standard)),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  _Acknowledge(
                    value: _understood,
                    onChanged: _deleting
                        ? null
                        : (v) => setState(() => _understood = v),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  PrimaryButton(
                    label: 'Delete my account',
                    destructive: true,
                    loading: _deleting,
                    onPressed: _understood ? _delete : null,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  TextButton(
                    onPressed: _deleting
                        ? null
                        : () => Navigator.of(context).maybePop(),
                    child: const Text('Keep my account'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({
    required this.icon,
    required this.title,
    required this.body,
    this.last = false,
  });

  final IconData icon;
  final String title;
  final String body;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : AppSpacing.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon,
              size: 22,
              color: dark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondaryLight),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(body, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Acknowledge extends StatelessWidget {
  const _Acknowledge({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      checked: value,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        onTap: onChanged == null ? null : () => onChanged!(!value),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Row(
            children: [
              Checkbox(
                value: value,
                onChanged:
                    onChanged == null ? null : (v) => onChanged!(v ?? false),
                activeColor: AppColors.errorInk,
              ),
              Expanded(
                child: Text(
                  'I understand my account will be permanently deleted.',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorNotice extends StatelessWidget {
  const _ErrorNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: dark ? AppColors.errorSoftDark : AppColors.errorSoft,
          borderRadius: BorderRadius.circular(AppSpacing.radius),
          border: Border.all(color: AppColors.error.withValues(alpha: 0.35)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(PhosphorIconsRegular.info,
                color: AppColors.error, size: 20),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(message, style: theme.textTheme.bodyMedium),
            ),
          ],
        ),
      ),
    );
  }
}
