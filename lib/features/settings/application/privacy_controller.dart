import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/infrastructure.dart';
import '../../../app/state/app_settings_controller.dart';
import '../../auth/application/auth_providers.dart';
import '../../parent/application/parent_gate_controller.dart';
import '../../profile/application/profile_providers.dart';
import '../../progress/application/progress_providers.dart';
import '../../subscription/application/subscription_providers.dart';

/// Privacy and account controls: what is collected, whether it syncs, export,
/// and the "delete everything" path a parent (or a curious 6-year-old with a
/// borrowed tablet) can actually complete without contacting support.
class PrivacyController extends Notifier<PrivacyState> {
  @override
  PrivacyState build() {
    final store = ref.read(keyValueStoreProvider);
    return PrivacyState(
      cloudSyncEnabled: store.getBool('phonicsai.privacy.cloud_sync'),
      analyticsEnabled: store.getBool('phonicsai.privacy.analytics'),
      isErasing: false,
    );
  }

  Future<void> setCloudSync(bool enabled) async {
    await ref.read(keyValueStoreProvider).setBool(
          'phonicsai.privacy.cloud_sync',
          enabled,
        );
    state = state.copyWith(cloudSyncEnabled: enabled);
    await ref.read(appSettingsProvider.notifier).setCloudSyncEnabled(enabled);
  }

  Future<void> setAnalytics(bool enabled) async {
    await ref.read(keyValueStoreProvider).setBool(
          'phonicsai.privacy.analytics',
          enabled,
        );
    state = state.copyWith(analyticsEnabled: enabled);
  }

  /// Local export. Returns a JSON string the parent can share; nothing is
  /// uploaded by this call.
  Future<String> exportBundle() async {
    final store = ref.read(keyValueStoreProvider);
    final profiles = ref.read(profileRepositoryProvider).readAllSync();
    final progress = ref.read(profileProgressProvider).valueOrNull;
    final keys = <String, String>{};
    for (final key in store.keysStartingWith('phonicsai.')) {
      final value = store.getString(key);
      if (value != null) keys[key] = value;
    }
    final buffer = StringBuffer('{"exported_at":"${DateTime.now().toIso8601String()}"'
        ',"profiles":[');
    buffer.write(profiles.map((p) => _encode(p.displayName)).join(','));
    buffer.write('],"lesson_count":${progress?.lessons.length ?? 0}');
    buffer.write(',"keys":{');
    buffer.write(keys.entries
        .map((e) => '"${e.key}":${_encode(e.value)}')
        .join(','));
    buffer.write('}}');
    return buffer.toString();
  }

  static String _encode(String value) =>
      '"${value.replaceAll('\\', '\\\\').replaceAll('"', '\\"')}"';

  /// Erase this device's copy of everything. Deliberately does not touch the
  /// store account's server data — that is `deleteAccount()`, and the two must
  /// not be confused in the UI.
  Future<void> eraseLocalData() async {
    state = state.copyWith(isErasing: true);
    final store = ref.read(keyValueStoreProvider);
    for (final key in store.keysStartingWith('phonicsai.').toList()) {
      await store.remove(key);
    }
    final profileId = ref.read(appSettingsProvider).activeProfileId;
    if (profileId != null) {
      await ref.read(progressRepositoryProvider).reset(profileId);
    }
    await ref.read(secureVaultProvider).clear();
    state = state.copyWith(isErasing: false);
  }

  /// Account deletion + local wipe. The backend call is where a real server
  /// must confirm erasure within the legal window.
  Future<void> eraseEverything() async {
    state = state.copyWith(isErasing: true);
    // TODO(backend): DELETE /auth/account (cascades learners, progress,
    // receipts to the erasure queue). Mock mode skips the network by design.
    await ref.read(authRepositoryProvider).deleteAccount();
    await eraseLocalData();
    await ref.read(subscriptionProvider.notifier).refresh();
    ref.read(parentGateProvider.notifier).lock();
    await ref.read(appSettingsProvider.notifier).restartOnboarding();
    state = state.copyWith(isErasing: false);
  }
}

class PrivacyState {
  const PrivacyState({
    this.cloudSyncEnabled = false,
    this.analyticsEnabled = true,
    this.isErasing = false,
  });

  final bool cloudSyncEnabled;
  final bool analyticsEnabled;
  final bool isErasing;

  PrivacyState copyWith({
    bool? cloudSyncEnabled,
    bool? analyticsEnabled,
    bool? isErasing,
  }) {
    return PrivacyState(
      cloudSyncEnabled: cloudSyncEnabled ?? this.cloudSyncEnabled,
      analyticsEnabled: analyticsEnabled ?? this.analyticsEnabled,
      isErasing: isErasing ?? this.isErasing,
    );
  }
}

final privacyControllerProvider =
    NotifierProvider<PrivacyController, PrivacyState>(PrivacyController.new);
