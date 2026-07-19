import 'package:core/core.dart';
import 'package:flutter/material.dart';

import 'app.dart';
import 'features/payments/stripe_card_adder.dart';

Future<void> main() async {
  runGuarded(() async {
    await configureCoreDependencies();
    // Register the real Stripe PaymentSheet card-adder so PaymentMethodsPage
    // uses it (falls back to the mock sheet when Stripe isn't configured).
    sl.registerSingleton<StripeCardAdder>(addStripeCard);
    runApp(const RiderApp());
  });
}
