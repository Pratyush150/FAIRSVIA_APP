import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'home_page.dart';

class DriverApp extends StatefulWidget {
  const DriverApp({super.key});

  @override
  State<DriverApp> createState() => _DriverAppState();
}

class _DriverAppState extends State<DriverApp> {
  late final AuthBloc _authBloc;
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _authBloc = sl<AuthBloc>()..add(const AuthStarted());
    _router = createAppRouter(
      authBloc: _authBloc,
      appTitle: AppBrand.driverTitle,
      nameSetupSubtitle: NameSetupPage.driverSubtitle,
      homeBuilder: (_) => const DriverHomePage(),
    );
  }

  @override
  void dispose() {
    _authBloc.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _authBloc,
      // Light / Dark / Same as phone, chosen in Account → Appearance.
      child: ValueListenableBuilder<ThemeMode>(
        valueListenable: sl.isRegistered<ThemeController>()
            ? sl<ThemeController>().effective
            : ValueNotifier(ThemeMode.system),
        builder: (context, mode, _) => MaterialApp.router(
          title: AppBrand.driverTitle,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: mode,
          routerConfig: _router,
          // The brand signature covers the router's first frame — auth gate,
          // home, or a ride restored from a cold start — so no screen has to
          // know it exists. It hands over on a fixed timer, not on a load
          // event: it is a signature, not a loading screen.
          builder: (context, child) {
            // Ink colours (black on light, white on dark) follow the theme.
            AppColors.syncBrightness(Theme.of(context).brightness);
            return BrandSplashGate(
              driver: true,
              child: ErrorOverlay(child: child ?? const SizedBox.shrink()),
            );
          },
        ),
      ),
    );
  }
}
