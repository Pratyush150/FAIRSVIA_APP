/// Core app framework: config, networking, storage, DI, router, and the
/// shared auth feature (data, bloc, and UI) used by all three apps.
library;

export 'src/config/app_config.dart';
export 'src/network/api_exception.dart';
export 'src/network/token_storage.dart';
export 'src/network/dio_client.dart';
export 'src/auth/auth_remote_data_source.dart';
export 'src/auth/auth_repository.dart';
export 'src/auth/bloc/auth_bloc.dart';
export 'src/auth/presentation/phone_entry_page.dart';
export 'src/auth/presentation/otp_page.dart';
export 'src/auth/presentation/name_setup_page.dart';
export 'src/realtime/realtime_client.dart';
export 'src/driver/driver_remote_data_source.dart';
export 'src/trip/places_remote_data_source.dart';
export 'src/trip/trip_remote_data_source.dart';
export 'src/trip/trip_repository.dart';
export 'src/trip/payments_remote_data_source.dart';
export 'src/trip/ratings_remote_data_source.dart';
export 'src/router/app_router.dart';
export 'src/di/injector.dart';
export 'src/debug/error_overlay.dart';
// Account feature: profile hub + history/receipt/places/payments/earnings.
export 'src/account/format.dart';
export 'src/account/users_remote_data_source.dart';
export 'src/account/account_menu_page.dart';
export 'src/account/delete_account_page.dart';
export 'src/account/trip_history_page.dart';
export 'src/account/receipt_page.dart';
export 'src/account/profile_edit_page.dart';
export 'src/account/driver_payouts_page.dart';
export 'src/account/favorite_drivers_page.dart';
export 'src/account/favorites_remote_data_source.dart';
export 'src/account/inbox_page.dart';
export 'src/account/inbox_remote_data_source.dart';
export 'src/account/support_page.dart';
export 'src/account/support_thread_page.dart';
export 'src/account/support_remote_data_source.dart';
export 'src/account/saved_places_page.dart';
export 'src/account/scheduled_rides_page.dart';
export 'src/account/payment_methods_page.dart';
export 'src/account/driver_earnings_page.dart';
// In-trip chat.
export 'src/chat/chat_remote_data_source.dart';
export 'src/chat/chat_page.dart';
// Safety toolkit (SOS).
export 'src/safety/safety_remote_data_source.dart';
export 'src/safety/safety_sheet.dart';
export 'src/util/navigation_launcher.dart';
export 'src/network/auth_interceptor.dart';
export 'src/navigation/external_nav.dart';
