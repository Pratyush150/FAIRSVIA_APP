import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/auth_bloc.dart';
import 'package:shared_models/shared_models.dart';
import '../../config/app_config.dart';
import '../../config/server_address_page.dart';
import '../../di/injector.dart';
import '../../network/token_storage.dart';

/// Phone number entry — step 1 of the OTP login flow. Shared across apps.
class PhoneEntryPage extends StatefulWidget {
  const PhoneEntryPage({super.key, this.title = AppBrand.name});

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
    final phone = Market.current.toE164(_controller.text);
    if (phone == null) return;
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
            // Scrollable so the content never overflows when the keyboard
            // shrinks the viewport (a fixed gap replaces the old Spacer, which
            // caused a 2px bottom overflow on tall screens with the keyboard up).
            return Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl, AppSpacing.xl, AppSpacing.xl, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: AppSpacing.huge),
                  GestureDetector(
                    // Pilot builds: long-press the logo to change the server
                    // address (see ServerAddressPage). Nothing in store builds.
                    onLongPress: AppConfig.allowServerOverride
                        ? () => Navigator.of(context).push(MaterialPageRoute<void>(
                              builder: (_) => ServerAddressPage(
                                store: sl<KeyValueStore>(),
                                current: sl<AppConfig>().apiBaseUrl,
                              ),
                            ))
                        : null,
                    child: Container(
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
                    decoration: InputDecoration(
                      hintText: Market.current.examplePhone,
                      prefixIcon: const Icon(Icons.phone_rounded),
                    ),
                    onChanged: (v) => setState(
                      // A local number gets the market's country code; one
                      // typed with '+' is taken as international.
                      () => _valid = Market.current.toE164(v) != null,
                    ),
                    onSubmitted: _valid ? (_) => _submit(context) : null,
                  ),
                  if (_controller.text.trim().isNotEmpty && !_valid) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Enter a mobile number, e.g. ${Market.current.examplePhone}.',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: AppColors.error),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.xl),
                ],
              ),
                    ),
                  ),
                ),
                // Pinned under the scroll view so the CTA stays visible above
                // the keyboard on small screens (it used to sit below the
                // fold with no way to reach it but a blind scroll).
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'By continuing you agree to our Terms and Privacy '
                        'Policy.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: AppColors.textTertiaryLight),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      PrimaryButton(
                        label: 'Continue',
                        loading: state.busy,
                        onPressed: _valid && !state.busy
                            ? () => _submit(context)
                            : null,
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
