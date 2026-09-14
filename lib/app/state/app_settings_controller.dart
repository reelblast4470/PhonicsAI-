import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/key_value_store.dart';
import '../../core/storage/storage_keys.dart';
import '../di/infrastructure.dart';

/// App-wide user preferences (not learning data). Persisted through the
/// [KeyValueStore] so it works offline and on every platform.
@immutable
class AppSettings {
  const AppSettings({
    this.interfaceLocale,
    this.themeMode = ThemeMode.system,
    this.textScale = 1.0,
    this.soundEnabled = true,
    this.onboardingComplete = false,
    this.activeProfileId,
    this.cloudSyncEnabled = false,
  });

  /// null => follow the device locale.
  final String? interfaceLocale;
  final ThemeMode themeMode;
  final double textScale;
  final bool soundEnabled;
  final bool onboardingComplete;
  final String? activeProfileId;
  final bool cloudSyncEnabled;

  AppSettings copyWith({
    Object? interfaceLocale = _sentinel,
    ThemeMode? themeMode,
    double? textScale,
    bool? soundEnabled,
    bool? onboardingComplete,
    Object? activeProfileId = _sentinel,
    bool? cloudSyncEnabled,
  }) {
    return AppSettings(
      interfaceLocale: interfaceLocale == _sentinel
          ? this.interfaceLocale
          : interfaceLocale as String?,
      themeMode: themeMode ?? this.themeMode,
      textScale: textScale ?? this.textScale,
      soundEnabled: soundEnabled ?? this.soundEnabled,
      onboardingComplete: onboardingComplete ?? this.onboardingComplete,
      activeProfileId: activeProfileId == _sentinel
          ? this.activeProfileId
          : activeProfileId as String?,
      cloudSyncEnabled: cloudSyncEnabled ?? this.cloudSyncEnabled,
    );
  }

  static const Object _sentinel = Object();

  static AppSettings read(KeyValueStore store) => AppSettings(
        interfaceLocale: store.getString(StorageKeys.interfaceLocale),
        onboardingComplete: store.getBool(StorageKeys.onboardingComplete),
        activeProfileId: store.getString(StorageKeys.activeProfileId),
      );
}

class AppSettingsController extends Notifier<AppSettings> {
  @override
  AppSettings build() => AppSettings.read(ref.watch(keyValueStoreProvider));

  KeyValueStore get _store => ref.read(keyValueStoreProvider);

  Future<void> setInterfaceLocale(String? languageCode) async {
    if (languageCode == null) {
      await _store.remove(StorageKeys.interfaceLocale);
    } else {
      await _store.setString(StorageKeys.interfaceLocale, languageCode);
    }
    state = state.copyWith(interfaceLocale: languageCode);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = state.copyWith(themeMode: mode);
  }

  Future<void> setTextScale(double scale) async {
    state = state.copyWith(textScale: scale);
  }

  Future<void> setSoundEnabled(bool enabled) async {
    state = state.copyWith(soundEnabled: enabled);
  }

  Future<void> setCloudSyncEnabled(bool enabled) async {
    state = state.copyWith(cloudSyncEnabled: enabled);
  }

  Future<void> completeOnboarding() async {
    await _store.setBool(StorageKeys.onboardingComplete, true);
    state = state.copyWith(onboardingComplete: true);
  }

  Future<void> restartOnboarding() async {
    await _store.setBool(StorageKeys.onboardingComplete, false);
    state = state.copyWith(onboardingComplete: false);
  }

  Future<void> setActiveProfile(String? profileId) async {
    if (profileId == null) {
      await _store.remove(StorageKeys.activeProfileId);
    } else {
      await _store.setString(StorageKeys.activeProfileId, profileId);
    }
    state = state.copyWith(activeProfileId: profileId);
  }
}

final appSettingsProvider =
    NotifierProvider<AppSettingsController, AppSettings>(
  AppSettingsController.new,
);
