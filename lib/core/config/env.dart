/// Non-secret runtime configuration for the Flutter client.
///
/// IMPORTANT: this file must never hold API keys, JWT secrets, database
/// credentials or any other secret. The RailRadar API key in particular
/// stays server-side, inside the Train Yatri backend's own environment
/// variables - the Flutter app only ever talks to that backend, never to
/// RailRadar directly:
///
///   Flutter -> Train Yatri backend -> RailRadar
///
/// See `services/railradar/` (added in a later block) for the client
/// that calls the backend. Everything in this file is safe-by-definition
/// (a base URL is not a secret); it exists purely so screens/services
/// never hard-code environment-specific values inline.
enum AppEnvironment { development, staging, production }

abstract final class Env {
  /// Raw `--dart-define=ENVIRONMENT=...` value. Must be exactly one of
  /// `development` (default), `staging`/`stage` or `production`/`prod` -
  /// kept as a plain const equality chain (rather than a parsing
  /// function) so [current] can stay a genuine compile-time constant.
  static const String _rawEnvironment = String.fromEnvironment(
    'ENVIRONMENT',
    defaultValue: 'development',
  );

  /// Selected with:
  ///   flutter run --dart-define=ENVIRONMENT=staging
  /// Defaults to development so a plain `flutter run` never accidentally
  /// talks to production.
  static const AppEnvironment current =
      _rawEnvironment == 'production' || _rawEnvironment == 'prod'
      ? AppEnvironment.production
      : _rawEnvironment == 'staging' || _rawEnvironment == 'stage'
      ? AppEnvironment.staging
      : AppEnvironment.development;

  static const _environmentDefaultUrls = {
    AppEnvironment.development: 'https://dev-api.trainyatri.app',
    AppEnvironment.staging: 'https://staging-api.trainyatri.app',
    AppEnvironment.production: 'https://api.trainyatri.app',
  };

  /// Overridable independently of [current] with:
  ///   flutter run --dart-define=API_BASE_URL=https://api.example.com
  static String get apiBaseUrl {
    const override = String.fromEnvironment('API_BASE_URL');
    if (override.isNotEmpty) return override;
    return _environmentDefaultUrls[current]!;
  }

  static bool get isProduction => current == AppEnvironment.production;
}
