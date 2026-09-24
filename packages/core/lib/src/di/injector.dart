import 'dart:ui' show PlatformDispatcher;

import 'package:design_system/design_system.dart' show AppClay3D;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart' show Brightness, ThemeMode;
import 'package:get_it/get_it.dart';

import '../theme/theme_controller.dart';

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
import '../account/support_remote_data_source.dart';
import '../account/users_remote_data_source.dart';
import '../chat/chat_remote_data_source.dart';
import '../content/content_remote_data_source.dart';
import '../safety/safety_remote_data_source.dart';

/// Shared service locator.
final GetIt sl = GetIt.instance;

/// Registers the core dependencies shared by all three apps. Call once from
/// each app's `main()` before `runApp`.
Future<void> configureCoreDependencies({AppConfig? config}) async {
  // Web can't use flutter_secure_storage on insecure origins (crypto.subtle
  // is unavailable behind plain-HTTP/IP), and shared_preferences' web method
  // channel throws MissingPluginException here — so talk to window.localStorage
  // directly on web (see kv_local_web.dart).
  final KeyValueStore store = kIsWeb
      ? createLocalStore()
      : SecureKeyValueStore();
  final cfg =
      config ?? await _pilotOverride(store) ?? AppConfig.fromEnvironment();

  final theme = await ThemeController.load(store);
  // THEME=clay3d: register the dark 3D icon set before the first frame if
  // the app will start dark, so no light icon ever flashes (no-op otherwise).
  await AppClay3D.useIconSetFor(switch (theme.value) {
    ThemeMode.dark => Brightness.dark,
    ThemeMode.light => Brightness.light,
    ThemeMode.system => PlatformDispatcher.instance.platformBrightness,
  });

  sl
    ..registerSingleton<AppConfig>(cfg)
    ..registerSingleton<ThemeController>(theme)
    ..registerSingleton<KeyValueStore>(store)
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
    ..registerFactory<AuthBloc>(
      () => AuthBloc(
        sl<AuthRepository>(),
        sessionExpired: sl<DioClient>().sessionExpired,
      ),
    )
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
    ..registerSingleton<RealtimeClient>(SocketIoRealtimeClient(cfg.wsUrl))
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
    // Help & support tickets (rider + driver).
    ..registerSingleton<SupportRemoteDataSource>(
      SupportRemoteDataSource(sl<DioClient>().authenticatedDio),
    )
    // In-trip chat (history + send; live delivery over the socket).
    ..registerSingleton<ChatRemoteDataSource>(
      ChatRemoteDataSource(sl<DioClient>().authenticatedDio),
    )
    // Safety toolkit (SOS).
    ..registerSingleton<SafetyRemoteDataSource>(
      SafetyRemoteDataSource(sl<DioClient>().authenticatedDio),
    )
    // Admin-managed content (promo cards under the ride).
    ..registerSingleton<ContentRemoteDataSource>(
      ContentRemoteDataSource(sl<DioClient>().authenticatedDio),
    );
}

/// The server address a pilot tester saved on the sign-in screen, if this
/// build allows one (see [AppConfig.allowServerOverride]) and it is valid.
Future<AppConfig?> _pilotOverride(KeyValueStore store) async {
  if (!AppConfig.allowServerOverride) return null;
  try {
    final saved = await store.read(AppConfig.serverOverrideKey);
    if (saved == null || !AppConfig.isValidOverride(saved)) return null;
    return AppConfig(apiBaseUrl: saved.trim());
  } catch (_) {
    return null; // unreadable storage must never stop the app starting
  }
}
