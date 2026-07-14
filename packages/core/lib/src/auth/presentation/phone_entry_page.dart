import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/auth_bloc.dart';

/// Phone number entry — step 1 of the OTP login flow. Shared across apps.
class PhoneEntryPage extends StatefulWidget {
  const PhoneEntryPage({super.key, this.title = 'UberNav'});

  final String title;

  @override
  State<PhoneEntryPage> createState() => _PhoneEntryPageState();
}

class _PhoneEntryPageState extends State<PhoneEntryPage> {
  final _controller = TextEditingController();
  bool _valid = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit(BuildContext context) {
    final phone = _controller.text.replaceAll(' ', '').trim();
    context.read<AuthBloc>().add(AuthOtpRequested(phone));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: BlocConsumer<AuthBloc, AuthState>(
          listenWhen: (p, c) => p.error != c.error && c.error != null,
          listener: (context, state) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(SnackBar(content: Text(state.error!)));
          },
          builder: (context, state) {
            return Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: AppSpacing.huge),
                  Container(
                    height: 64,
                    width: 64,
                    decoration: BoxDecoration(
                      color: AppColors.accentSoft,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                    ),
                    child: const Icon(
                      Icons.navigation_rounded,
                      color: AppColors.accent,
                      size: 30,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Text('Welcome to ${widget.title}',
                      style: theme.textTheme.displaySmall),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Enter your phone number and we\'ll text you a\ncode to sign in.',
                    style: theme.textTheme.bodyLarge
                        ?.copyWith(color: AppColors.textSecondaryLight),
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  Text('Phone number',
                      style: theme.textTheme.labelLarge
                          ?.copyWith(color: AppColors.textSecondaryLight)),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    controller: _controller,
                    keyboardType: TextInputType.phone,
                    autofocus: true,
                    style: theme.textTheme.titleMedium,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')),
                    ],
                    decoration: const InputDecoration(
                      hintText: '+1 305 555 0137',
                      prefixIcon: Icon(Icons.phone_rounded),
                    ),
                    onChanged: (v) => setState(
                      () => _valid = RegExp(r'^\+?[1-9]\d{7,14}$')
                          .hasMatch(v.replaceAll(' ', '').trim()),
                    ),
                    onSubmitted: _valid ? (_) => _submit(context) : null,
                  ),
                  const Spacer(),
                  Text(
                    'By continuing you agree to our Terms and Privacy Policy.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AppColors.textTertiaryLight),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  PrimaryButton(
                    label: 'Continue',
                    loading: state.busy,
                    onPressed:
                        _valid && !state.busy ? () => _submit(context) : null,
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
