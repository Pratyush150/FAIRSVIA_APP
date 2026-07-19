package `in`.novarobotics.ubernav.rider_app

import io.flutter.embedding.android.FlutterFragmentActivity

// flutter_stripe requires FlutterFragmentActivity (not FlutterActivity) so the
// Stripe PaymentSheet can attach its own fragments.
class MainActivity : FlutterFragmentActivity()
