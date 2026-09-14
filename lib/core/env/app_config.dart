/// Compile-time / runtime configuration.
///
/// SECURITY: this class intentionally holds **no** secrets. AI keys, billing
/// secrets and backend credentials must live behind the PhonicsAI backend (or a
/// token exchange) and are never compiled into the client. The only values a
/// client may know are the public API base URL and the publishable billing ids.
class AppConfig {
  const AppConfig({
    required this.flavor,
    required this.apiBaseUrl,
    required this.billingCurrency,
    required this.backendMode,
    this.logHttpBodies = false,
  });

  final AppFlavor flavor;

  /// Empty string => the app runs fully on local/mock adapters.
  final String apiBaseUrl;
  final String billingCurrency;

  /// Which adapter set backs repositories that normally talk to a backend.
  final BackendMode backendMode;
  final bool logHttpBodies;

  bool get hasBackend => apiBaseUrl.trim().isNotEmpty;

  static const AppConfig dev = AppConfig(
    flavor: AppFlavor.dev,
    apiBaseUrl: '',
    billingCurrency: 'USD',
    backendMode: BackendMode.mock,
    logHttpBodies: true,
  );

  static const AppConfig staging = AppConfig(
    flavor: AppFlavor.staging,
    apiBaseUrl: 'https://staging-api.phonicsai.example.com/v1',
    billingCurrency: 'USD',
    backendMode: BackendMode.offlineFirst,
  );

  static const AppConfig prod = AppConfig(
    flavor: AppFlavor.prod,
    apiBaseUrl: 'https://api.phonicsai.example.com/v1',
    billingCurrency: 'USD',
    backendMode: BackendMode.offlineFirst,
  );

  /// Resolution via `--dart-define`, e.g.
  /// `flutter run --dart-define=API_BASE_URL=https://api... --dart-define=FLAVOR=prod`
  factory AppConfig.fromEnvironment() {
    final flavor = switch (const String.fromEnvironment('FLAVOR')) {
      'prod' => AppFlavor.prod,
      'staging' => AppFlavor.staging,
      _ => AppFlavor.dev,
    };
    final mode = switch (const String.fromEnvironment('BACKEND_MODE')) {
      'live' => BackendMode.live,
      'offlineFirst' => BackendMode.offlineFirst,
      _ => BackendMode.mock,
    };
    const base = String.fromEnvironment('API_BASE_URL');
    return AppConfig(
      flavor: flavor,
      apiBaseUrl: base,
      billingCurrency: const String.fromEnvironment(
        'BILLING_CURRENCY',
        defaultValue: 'USD',
      ),
      backendMode: base.isEmpty ? BackendMode.mock : mode,
    );
  }
}

enum AppFlavor {
  dev('dev'),
  staging('staging'),
  prod('prod');

  const AppFlavor(this.label);
  final String label;
}

/// How feature repositories obtain remote data.
enum BackendMode {
  /// No backend yet: in-memory/asset backed adapters, still behind the real
  /// repository interfaces so UI, tests and DI do not change when it lands.
  mock,

  /// Real backend with a local cache; every screen works offline.
  offlineFirst,

  /// Real backend is mandatory; cache is only used for retry/last-known state.
  live,
}
