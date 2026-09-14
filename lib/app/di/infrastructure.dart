import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../core/analytics/analytics_service.dart';
import '../../core/audio/asset_audio_service.dart';
import '../../core/audio/audio_service.dart';
import '../../core/billing/billing_gateway.dart';
import '../../core/env/app_config.dart';
import '../../core/network/api_client.dart';
import '../../core/network/auth_token_provider.dart';
import '../../core/network/session_token_holder.dart';
import '../../core/notifications/reminder_scheduler.dart';
import '../../core/security/secure_vault.dart';
import '../../core/speech/speech_service.dart';
import '../../core/storage/key_value_store.dart';
import '../../core/storage/storage_keys.dart';

/// Composition root.
///
/// Everything a feature could ever need from the platform is declared here and
/// overridden per environment (tests use in-memory adapters, `main.dart` uses
/// persisted ones). Features never construct infrastructure themselves.
final appConfigProvider = Provider<AppConfig>((ref) => AppConfig.dev);

final keyValueStoreProvider = Provider<KeyValueStore>(
  (ref) => throw UnimplementedError('override in bootstrap'),
);

final analyticsServiceProvider = Provider<AnalyticsService>(
  (ref) => LoggingAnalyticsService(
    enabled: ref.watch(appConfigProvider).flavor != AppFlavor.prod,
  ),
);

final audioServiceProvider = Provider<AudioService>((ref) {
  final service = AssetAudioService(loader: const UnlinkedAudioClipLoader());
  ref.onDispose(service.dispose);
  return service;
});

final speechServiceProvider = Provider<SpeechService>(
  (ref) => AppConfig.dev.backendMode == BackendMode.mock
      ? MockSpeechService()
      : MockSpeechService(),
);

final secureVaultProvider = Provider<SecureVault>((ref) {
  // RELEASE BLOCKER: swap for the encrypted adapter
  // (flutter_secure_storage / Keystore / Keychain) in `bootstrap.dart`.
  throw UnimplementedError('override in bootstrap');
});

final reminderSchedulerProvider = Provider<ReminderScheduler>(
  (ref) => const InAppReminderScheduler(),
);

final billingGatewayProvider = Provider<BillingGateway>((ref) {
  final gateway = MockBillingGateway();
  ref.onDispose(gateway.dispose);
  return gateway;
});

/// The live bearer-token source. `features/auth` fills it in whenever the
/// session changes; ApiClient reads it per request and refreshes on 401 via
/// the repository's hook installed on the holder.
final sessionTokenHolderProvider = Provider<SessionTokenHolder>((ref) {
  final holder = SessionTokenHolder();
  ref.onDispose(holder.dispose);
  return holder;
});

/// The single HTTP facade. Features never construct `http` calls themselves —
/// that is how timeouts, token refresh and error mapping stay consistent.
final apiClientProvider = Provider<ApiClient>(
  (ref) => ApiClient(
    config: ref.watch(appConfigProvider),
    httpClient: ref.watch(httpClientProvider),
    // Mock mode has no token, which is correct behaviour; live/offlineFirst
    // share the session holder so 401s trigger a refresh transparently.
    tokenProvider: ref.watch(appConfigProvider).backendMode == BackendMode.mock
        ? const NoAuthTokenProvider()
        : ref.watch(sessionTokenHolderProvider),
  ),
);

final apiSseStreamProvider = Provider<ApiSseStream>(
  (ref) => ApiSseStream(
    ref.watch(appConfigProvider),
    ref.watch(httpClientProvider),
    ref.watch(appConfigProvider).backendMode == BackendMode.mock
        ? const NoAuthTokenProvider()
        : ref.watch(sessionTokenHolderProvider),
  ),
);

/// Shared client so connections/pools are reused across AI + content calls.
final httpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

/// Exposed for tests that need to assert the store was flushed.
final storageSchemaVersionProvider = Provider<int>((ref) {
  final store = ref.watch(keyValueStoreProvider);
  return store.getInt(StorageKeys.schemaVersion, defaultValue: 0);
});
