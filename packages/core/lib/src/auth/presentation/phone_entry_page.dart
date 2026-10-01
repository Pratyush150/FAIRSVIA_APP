import 'package:design_system/design_system.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/auth_bloc.dart';
import 'package:shared_models/shared_models.dart';
import '../../config/app_config.dart';
import '../../config/server_address_page.dart';
import '../../di/injector.dart';
import '../../network/token_storage.dart';
import 'legal_page.dart';

/// The market's example number without its country code, for the field's
/// hint ("+91 98765 43210" → "98765 43210"); the code is on the prefix chip.
String localExamplePhone(Market market) {
  final ex = market.examplePhone;
  return ex.startsWith(market.dialCode)
      ? ex.substring(market.dialCode.length).trim()
      : ex;
}

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

  /// The driver app's login ("FAIRSVIA Driver"): driver mark + "Driver" pill.
  bool get _driver => widget.title.toLowerCase().contains('driver');

  // Span recognizers must outlive build and be disposed with the state.
  late final _termsTap = TapGestureRecognizer()
    ..onTap = () => openLegalDocument(context, LegalDocument.terms);
  late final _privacyTap = TapGestureRecognizer()
    ..onTap = () => openLegalDocument(context, LegalDocument.privacy);

  @override
  void dispose() {
    _controller.dispose();
    _termsTap.dispose();
    _privacyTap.dispose();
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
                        AppSpacing.xl,
                        AppSpacing.xl,
                        AppSpacing.xl,
                        0,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: AppSpacing.huge),
                          GestureDetector(
                            // Pilot builds: long-press the logo to change the server
                            // address (see ServerAddressPage). Nothing in store builds.
                            onLongPress: AppConfig.allowServerOverride
                                ? () => Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => ServerAddressPage(
                                        store: sl<KeyValueStore>(),
                                        current: sl<AppConfig>().apiBaseUrl,
                                      ),
                                    ),
                                  )
                                : null,
                            child: Row(
                              children: [
                                RideVelaMark(size: 64, driver: _driver),
                                // The driver app says so beside the mark.
                                if (_driver) ...[
                                  const SizedBox(width: AppSpacing.md),
                                  const RideVelaDriverPill(),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xl),
                          Text(
                            'Welcome to ${widget.title}',
                            style: theme.textTheme.displaySmall,
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            'Enter your phone number and we\'ll text you a code to sign in.',
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xxl),
                          Text(
                            'Phone number',
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          TextField(
                            key: const Key('phone-field'),
                            controller: _controller,
                            keyboardType: TextInputType.phone,
                            autofocus: true,
                            autofillHints: const [
                              AutofillHints.telephoneNumberNational,
                            ],
                            style: theme.textTheme.titleMedium,
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'[0-9+ ]'),
                              ),
                            ],
                            decoration: InputDecoration(
                              hintText: localExamplePhone(Market.current),
                              // Fixed, not editable: the build's market decides
                              // the country code (toE164 adds it on submit).
                              prefixIcon: const _DialCodeChip(),
                              prefixIconConstraints: const BoxConstraints(),
                            ),
                            onChanged: (v) => setState(
                              // A local number gets the market's country code; one
                              // typed with '+' is taken as international.
                              () => _valid = Market.current.toE164(v) != null,
                            ),
                            onSubmitted: _valid
                                ? (_) => _submit(context)
                                : null,
                          ),
                          if (_controller.text.trim().isNotEmpty &&
                              !_valid) ...[
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              'Enter a mobile number, e.g. '
                              '${localExamplePhone(Market.current)}.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: AppColors.error,
                              ),
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
                    AppSpacing.xl,
                    0,
                    AppSpacing.xl,
                    AppSpacing.md,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text.rich(
                        key: const Key('legal-notice'),
                        TextSpan(
                          children: [
                            const TextSpan(
                              text: 'By continuing you agree to our ',
                            ),
                            TextSpan(
                              text: 'Terms',
                              style: _linkStyle(theme),
                              recognizer: _termsTap,
                            ),
                            const TextSpan(text: ' and '),
                            TextSpan(
                              text: 'Privacy Policy',
                              style: _linkStyle(theme),
                              recognizer: _privacyTap,
                            ),
                            const TextSpan(text: '.'),
                          ],
                        ),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
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

TextStyle _linkStyle(ThemeData theme) => TextStyle(
  color: theme.colorScheme.onSurface,
  fontWeight: FontWeight.w600,
  decoration: TextDecoration.underline,
);

/// The non-editable country prefix at the start of the phone field, e.g.
/// "IN +91", from the build's [Market].
class _DialCodeChip extends StatelessWidget {
  const _DialCodeChip();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final market = Market.current;
    return Padding(
      padding: const EdgeInsets.only(
        left: AppSpacing.sm,
        right: AppSpacing.sm,
      ),
      child: Container(
        key: const Key('dial-code-chip'),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm + 2,
          vertical: AppSpacing.xs + 2,
        ),
        decoration: BoxDecoration(
          color: AppColors.accentSoft,
          borderRadius: BorderRadius.circular(AppSpacing.pill),
        ),
        child: Text(
          '${market.code.toUpperCase()} ${market.dialCode}',
          semanticsLabel: 'Country code ${market.dialCode}',
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
