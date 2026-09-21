import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../account/users_remote_data_source.dart';
import '../../di/injector.dart';
import '../../network/api_exception.dart';
import '../bloc/auth_bloc.dart';

/// First-time profile setup — shown right after signup when the account has no
/// name yet. Captures the rider/driver's name (email optional), saves it, and
/// refreshes the session user so the router advances to home.
class NameSetupPage extends StatefulWidget {
  const NameSetupPage({super.key, this.subtitle = riderSubtitle});

  /// Default copy, written for riders.
  static const riderSubtitle = 'So your driver knows who to look for.';

  /// Copy for the driver app, which should pass this explicitly.
  static const driverSubtitle = "So riders know who's picking them up.";

  /// The line under "What's your name?". Defaults to the rider wording.
  final String subtitle;

  @override
  State<NameSetupPage> createState() => _NameSetupPageState();
}

class _NameSetupPageState extends State<NameSetupPage> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _users = sl<UsersRemoteDataSource>();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Please enter your name');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final email = _email.text.trim();
      final user = await _users.updateMe(
        fullName: name,
        email: email.isEmpty ? null : email,
      );
      if (!mounted) return;
      context.read<AuthBloc>().add(AuthProfileCompleted(user));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: AppSpacing.xl),
              Text("What's your name?",
                  style: theme.textTheme.displaySmall),
              const SizedBox(height: AppSpacing.sm),
              Text(
                widget.subtitle,
                style: theme.textTheme.bodyLarge
                    ?.copyWith(color: AppColors.textSecondaryLight),
              ),
              const SizedBox(height: AppSpacing.xxl),
              TextField(
                controller: _name,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                // Backend limit; capping here avoids the raw validator text.
                maxLength: 120,
                style: theme.textTheme.titleMedium,
                decoration: const InputDecoration(
                  labelText: 'Full name',
                  hintText: 'Alex Rivera',
                  counterText: '',
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _save(),
                style: theme.textTheme.titleMedium,
                decoration: const InputDecoration(
                  labelText: 'Email (optional)',
                  hintText: 'you@example.com',
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.md),
                Text(_error!,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: AppColors.error)),
              ],
              const Spacer(),
              PrimaryButton(
                label: 'Continue',
                loading: _saving,
                onPressed: _saving ? null : _save,
              ),
              const SizedBox(height: AppSpacing.md),
            ],
          ),
        ),
      ),
    );
  }
}
