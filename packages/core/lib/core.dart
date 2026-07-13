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
