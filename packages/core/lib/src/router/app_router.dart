import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../auth/bloc/auth_bloc.dart';
import '../auth/presentation/name_setup_page.dart';
import '../auth/presentation/otp_page.dart';
import '../auth/presentation/phone_entry_page.dart';
import 'go_router_refresh_stream.dart';

/// Builds the shared router. The auth state gates navigation: unauthenticated
/// users see phone/OTP; authenticated users see the app-supplied [homeBuilder].
GoRouter createAppRouter({
  required AuthBloc authBloc,
  required WidgetBuilder homeBuilder,
  String appTitle = AppBrand.name,
  // The driver app passes [NameSetupPage.driverSubtitle]; riders keep the
  // default copy.
  String nameSetupSubtitle = NameSetupPage.riderSubtitle,
}) {
  return GoRouter(
    initialLocation: '/',
    refreshListenable: GoRouterRefreshStream(authBloc.stream),
    redirect: (context, state) {
      final status = authBloc.state.status;
      final loc = state.matchedLocation;
      switch (status) {
        case AuthStatus.unknown:
          return loc == '/' ? null : '/';
        case AuthStatus.unauthenticated:
          return loc == '/phone' ? null : '/phone';
        case AuthStatus.codeSent:
          return loc == '/otp' ? null : '/otp';
        case AuthStatus.authenticated:
          // First-time riders/drivers have no name yet — capture it before
          // home. Admins skip this (they use the web console).
          final u = authBloc.state.user;
          final needsName = u != null &&
              u.role != 'admin' &&
              (u.fullName ?? '').trim().isEmpty;
          if (needsName) {
            return loc == '/profile-setup' ? null : '/profile-setup';
          }
          return loc == '/home' ? null : '/home';
      }
    },
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => _SplashPage(
          // The driver app is the one that passes the driver name-setup copy;
          // its held launch frame keeps the Driver pill.
          driver: nameSetupSubtitle == NameSetupPage.driverSubtitle ||
              appTitle.toLowerCase().contains('driver'),
        ),
      ),
      GoRoute(
        path: '/phone',
        builder: (_, _) => PhoneEntryPage(title: appTitle),
      ),
      GoRoute(path: '/otp', builder: (_, _) => const OtpPage()),
      GoRoute(
        path: '/profile-setup',
        builder: (_, _) => NameSetupPage(subtitle: nameSetupSubtitle),
      ),
      GoRoute(path: '/home', builder: (context, _) => homeBuilder(context)),
    ],
  );
}

class _SplashPage extends StatelessWidget {
  const _SplashPage({this.driver = false});

  final bool driver;

  @override
  Widget build(BuildContext context) {
    // Session still restoring after the 1.8 s launch splash: hold the
    // splash's final frame (wordmark + finished road) with a subtle shimmer,
    // so the hand-off from BrandSplash is seamless. Still under Reduce Motion.
    return BrandLaunchHold(driver: driver);
  }
}
