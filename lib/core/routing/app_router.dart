import 'package:flutter/material.dart';

import '../../features/home/home_screen.dart';
import '../../features/splash/splash_screen.dart';
import 'app_routes.dart';

/// Navigator 1.0 `onGenerateRoute` table. Kept deliberately simple
/// (no external routing package) since Block 1 only has two
/// destinations; a router package can be introduced later if/when
/// deep-linking or nested navigation actually requires one.
abstract final class AppRouter {
  static Route<dynamic> generateRoute(RouteSettings settings) {
    switch (settings.name) {
      case AppRoutes.splash:
        return _route(const SplashScreen(), settings);
      case AppRoutes.home:
        return _fadeRoute(const HomeScreen(), settings);
      default:
        return _route(
          Scaffold(
            body: Center(child: Text('Route "${settings.name}" not found')),
          ),
          settings,
        );
    }
  }

  static Route<dynamic> _route(Widget child, RouteSettings settings) {
    return MaterialPageRoute<void>(builder: (_) => child, settings: settings);
  }

  static Route<dynamic> _fadeRoute(Widget child, RouteSettings settings) {
    return PageRouteBuilder<void>(
      settings: settings,
      transitionDuration: const Duration(milliseconds: 400),
      pageBuilder: (_, _, _) => child,
      transitionsBuilder: (_, animation, _, pageChild) {
        return FadeTransition(opacity: animation, child: pageChild);
      },
    );
  }
}
