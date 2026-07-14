import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/auth_bloc.dart';

/// Length of the login OTP. Must match the backend's OTP_LENGTH (default 6).
const int _otpLength = 6;

/// OTP entry — step 2 of the login flow. Shared across apps.
class OtpPage extends StatefulWidget {
  const OtpPage({super.key});

  @override
  State<OtpPage> createState() => _OtpPageState();
}

class _OtpPageState extends State<OtpPage> {
  String _code = '';

  void _submit(BuildContext context) {
    context.read<AuthBloc>().add(AuthOtpSubmitted(_code));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(
          onPressed: () => context.read<AuthBloc>().add(const AuthBackToPhone()),
        ),
      ),
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
                  const SizedBox(height: AppSpacing.lg),
                  Text('Enter the code', style: theme.textTheme.headlineMedium),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Sent to ${state.phone ?? 'your phone'}',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  // A single centered field: reliable on web and mobile alike
                  // (the segmented boxes' focus auto-advance is flaky in
                  // browsers). Auto-submits when all digits are entered.
                  TextField(
                    enabled: !state.busy,
                    autofocus: true,
                    textAlign: TextAlign.center,
                    keyboardType: TextInputType.number,
                    maxLength: _otpLength,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 8,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(_otpLength),
                    ],
                    decoration: InputDecoration(
                      counterText: '',
                      hintText: '•' * _otpLength,
                    ),
                    onChanged: (v) {
                      setState(() => _code = v);
                      if (v.length == _otpLength) _submit(context);
                    },
                  ),
                  if (state.devCode != null) ...[
                    const SizedBox(height: AppSpacing.lg),
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: AppSpacing.sm,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withValues(alpha: 0.12),
                          borderRadius:
                              BorderRadius.circular(AppSpacing.radiusSm),
                        ),
                        child: Text(
                          'DEV code: ${state.devCode}',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: AppColors.warning),
                        ),
                      ),
                    ),
                  ],
                  const Spacer(),
                  PrimaryButton(
                    label: 'Verify',
                    loading: state.busy,
                    onPressed: _code.length == _otpLength && !state.busy
                        ? () => _submit(context)
                        : null,
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
