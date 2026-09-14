import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/env/app_config.dart';
import '../core/storage/in_memory_secure_vault.dart';
import '../core/storage/key_value_store.dart';
import '../core/storage/shared_preferences_key_value_store.dart';
import '../core/storage/storage_keys.dart';
import 'di/infrastructure.dart';

/// Wires real adapters, applies storage migrations and returns the overrides
/// that `runApp` feeds into `ProviderScope`.
Future<List<Override>> bootstrap(AppConfig config) async {
  WidgetsFlutterBinding.ensureInitialized();

  KeyValueStore store = InMemoryKeyValueStore();
  if (!kIsWeb) {
    try {
      store = await SharedPreferencesKeyValueStore.create();
    } catch (error) {
      // A broken prefs file must not brick the app on a kid's tablet.
      debugPrint('bootstrap: prefs unavailable ($error), using memory');
      store = InMemoryKeyValueStore();
    }
  }

  await _applyMigrations(store);

  return [
    appConfigProvider.overrideWithValue(config),
    keyValueStoreProvider.overrideWithValue(store),
    secureVaultProvider.overrideWithValue(InMemorySecureVault()),
  ];
}

/// Versioned local schema. Records written by older builds are rewritten here.
Future<void> _applyMigrations(KeyValueStore store) async {
  const target = 1;
  final current = store.getInt(StorageKeys.schemaVersion, defaultValue: 0);
  if (current >= target) return;
  // v0 -> v1: namespaces were introduced; nothing to rewrite yet, the loader
  // simply ignores foreign keys.
  await store.setInt(StorageKeys.schemaVersion, target);
}

/// Global safety net: a layout overflow or a platform exception should log and
/// keep the current screen alive rather than showing the red screen to a child.
void installGlobalErrorHandling({AnalyticsSink? sink}) {
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    sink?.call('flutter_error', {
      'library': details.library ?? '',
      'exception': details.exceptionAsString(),
    });
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    sink?.call('dart_error', {'exception': error.toString()});
    return true;
  };
}

typedef AnalyticsSink = void Function(String name, Map<String, Object?> data);
