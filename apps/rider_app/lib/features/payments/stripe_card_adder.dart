import 'package:core/core.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

/// Drives real card entry via the native Stripe PaymentSheet (setup-intent
/// mode — saves a card for later off-session charges). Registered as a
/// [StripeCardAdder] in DI so the shared PaymentMethodsPage can use it without
/// `core` depending on flutter_stripe.
///
/// Returns [StripeCardResult.unavailable] when the backend is on the mock
/// gateway (no publishable key), so the caller falls back to the mock sheet.
/// Any Stripe failure that isn't a user cancel is converted to an [ApiException]
/// so the page shows a friendly message.
Future<StripeCardResult> addStripeCard(PaymentsRemoteDataSource payments) async {
  final setup = await payments.createSetupIntent();
  if (!setup.isConfigured) return StripeCardResult.unavailable;

  Stripe.publishableKey = setup.publishableKey;
  await Stripe.instance.applySettings();

  await Stripe.instance.initPaymentSheet(
    paymentSheetParameters: SetupPaymentSheetParameters(
      merchantDisplayName: 'Ride App',
      customerId: setup.customerId,
      customerEphemeralKeySecret: setup.ephemeralKeySecret,
      setupIntentClientSecret: setup.setupIntentClientSecret,
    ),
  );

  try {
    await Stripe.instance.presentPaymentSheet();
  } on StripeException catch (e) {
    if (e.error.code == FailureCode.Canceled) {
      return StripeCardResult.cancelled;
    }
    throw ApiException(
      e.error.localizedMessage ?? e.error.message ?? 'Could not save the card.',
    );
  }

  // Card saved + attached to the customer — pull it into our list.
  await payments.syncMethods();
  return StripeCardResult.added;
}
