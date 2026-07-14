import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:get_it/get_it.dart';

import '../auth/auth_remote_data_source.dart';
import '../auth/auth_repository.dart';
import '../auth/bloc/auth_bloc.dart';
import '../config/app_config.dart';
import '../network/dio_client.dart';
import '../network/token_storage.dart';
import '../network/kv_local_stub.dart'
    if (dart.library.html) '../network/kv_local_web.dart';
import '../realtime/realtime_client.dart';
import '../driver/driver_remote_data_source.dart';
import '../trip/places_remote_data_source.dart';
import '../trip/trip_remote_data_source.dart';
import '../trip/trip_repository.dart';
import '../trip/payments_remote_data_source.dart';
import '../trip/ratings_remote_data_source.dart';
import '../account/favorites_remote_data_source.dart';
import '../account/inbox_remote_data_source.dart';
import '../account/users_remote_data_source.dart';
import '../chat/chat_remote_data_source.dart';
import '../safety/safety_remote_data_source.dart';

/// Shared service locator.
final GetIt sl = GetIt.instance;

/// Registers the core dependencies shared by all three apps. Call once from
/// each app's `main()` before `runApp`.
Future<void> configureCoreDependencies({AppConfig? config}) async {
  final cfg = config ?? AppConfig.fromEnvironment();

  sl
    ..registerSingleton<AppConfig>(cfg)
    // Web can't use flutter_secure_storage on insecure origins (crypto.subtle
    // is unavailable behind plain-HTTP/IP), and shared_preferences' web method
    // channel throws MissingPluginException here — so talk to window.localStorage
    // directly on web (see kv_local_web.dart).
    ..registerSingleton<KeyValueStore>(
      kIsWeb ? createLocalStore() : SecureKeyValueStore(),
    )
    ..registerSingleton<TokenStorage>(TokenStorage(sl<KeyValueStore>()))
    ..registerSingleton<DioClient>(
      DioClient(config: cfg, storage: sl<TokenStorage>()),
    )
    ..registerSingleton<AuthRemoteDataSource>(
      AuthRemoteDataSource(sl<DioClient>().authenticatedDio),
    )
    ..registerSingleton<AuthRepository>(
      AuthRepository(sl<AuthRemoteDataSource>(), sl<TokenStorage>()),
    )
    ..registerFactory<AuthBloc>(() => AuthBloc(sl<AuthRepository>()))
    // Trip flow (Phase 1): places proxy + trip estimate/create/cancel.
    ..registerSingleton<PlacesRemoteDataSource>(
      PlacesRemoteDataSource(sl<DioClient>().authenticatedDio),
    )
    ..registerSingleton<TripRemoteDataSource>(
      TripRemoteDataSource(sl<DioClient>().authenticatedDio),
    )
    ..registerSingleton<TripRepository>(
      TripRepository(sl<PlacesRemoteDataSource>(), sl<TripRemoteDataSource>()),
    )
    // Realtime transport (Phase 2): shared Socket.IO client.
    ..registerSingleton<RealtimeClient>(
      SocketIoRealtimeClient(cfg.wsUrl),
    )
    ..registerSingleton<DriverRemoteDataSource>(
      DriverRemoteDataSource(sl<DioClient>().authenticatedDio),
    )
    // Payments + ratings (Phase 3/4): receipts, tips, two-way ratings.
    ..registerSingleton<PaymentsRemoteDataSource>(
      PaymentsRemoteDataSource(sl<DioClient>().authenticatedDio),
    )
    ..registerSingleton<RatingsRemoteDataSource>(
      RatingsRemoteDataSource(sl<DioClient>().authenticatedDio),
    )
    // Account (profile + saved places) for the menu hub screens.
    ..registerSingleton<UsersRemoteDataSource>(
      UsersRemoteDataSource(sl<DioClient>().authenticatedDio),
    )
    // Favourite drivers (rider).
    ..registerSingleton<FavoritesRemoteDataSource>(
      FavoritesRemoteDataSource(sl<DioClient>().authenticatedDio),
    )
    // In-app notification inbox (rider + driver).
    ..registerSingleton<InboxRemoteDataSource>(
      InboxRemoteDataSource(sl<DioClient>().authenticatedDio),
    )
    // In-trip chat (history + send; live delivery over the socket).
    ..registerSingleton<ChatRemoteDataSource>(
      ChatRemoteDataSource(sl<DioClient>().authenticatedDio),
    )
    // Safety toolkit (SOS).
    ..registerSingleton<SafetyRemoteDataSource>(
      SafetyRemoteDataSource(sl<DioClient>().authenticatedDio),
    );
}
