import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/infrastructure.dart';
import '../../../core/notifications/reminder_scheduler.dart';
import '../../../core/storage/key_value_store.dart';

/// Grown-up settings that change what the child can do.
///
/// These are enforced in the app (not just "recommended"), and the same values
/// are sent to the backend as entitlement/consent flags once accounts exist.
@immutable
class ParentControls {
  const ParentControls({
    this.dailyLimitMinutes = 25,
    this.allowMicrophone = true,
    this.allowOpenChat = true,
    this.allowStickerShop = false,
    this.reminderTime = const TimeOfDay24(17, 30),
    this.remindersEnabled = true,
    this.contentRatingMild = true,
  });

  final int dailyLimitMinutes;
  final bool allowMicrophone;

  /// When false the tutor only answers the on-screen suggestion chips.
  final bool allowOpenChat;
  final bool allowStickerShop;
  final TimeOfDay24 reminderTime;
  final bool remindersEnabled;

  /// Keeps examples classroom-safe (no scary/competitive content).
  final bool contentRatingMild;

  bool get hasDailyLimit => dailyLimitMinutes > 0;

  ParentControls copyWith({
    int? dailyLimitMinutes,
    bool? allowMicrophone,
    bool? allowOpenChat,
    bool? allowStickerShop,
    TimeOfDay24? reminderTime,
    bool? remindersEnabled,
    bool? contentRatingMild,
  }) {
    return ParentControls(
      dailyLimitMinutes: dailyLimitMinutes ?? this.dailyLimitMinutes,
      allowMicrophone: allowMicrophone ?? this.allowMicrophone,
      allowOpenChat: allowOpenChat ?? this.allowOpenChat,
      allowStickerShop: allowStickerShop ?? this.allowStickerShop,
      reminderTime: reminderTime ?? this.reminderTime,
      remindersEnabled: remindersEnabled ?? this.remindersEnabled,
      contentRatingMild: contentRatingMild ?? this.contentRatingMild,
    );
  }

  Map<String, dynamic> toJson() => {
        'limit': dailyLimitMinutes,
        'mic': allowMicrophone,
        'chat': allowOpenChat,
        'shop': allowStickerShop,
        'remind_h': reminderTime.hour,
        'remind_m': reminderTime.minute,
        'remind_on': remindersEnabled,
        'mild': contentRatingMild,
      };

  factory ParentControls.fromJson(Map<String, dynamic> json) => ParentControls(
        dailyLimitMinutes: (json['limit'] as num?)?.toInt() ?? 25,
        allowMicrophone: json['mic'] as bool? ?? true,
        allowOpenChat: json['chat'] as bool? ?? true,
        allowStickerShop: json['shop'] as bool? ?? false,
        reminderTime: TimeOfDay24(
          (json['remind_h'] as num?)?.toInt() ?? 17,
          (json['remind_m'] as num?)?.toInt() ?? 30,
        ),
        remindersEnabled: json['remind_on'] as bool? ?? true,
        contentRatingMild: json['mild'] as bool? ?? true,
      );
}

class ParentControlsController extends Notifier<ParentControls> {
  static const storageKey = 'phonicsai.parent.controls';

  KeyValueStore get _store => ref.read(keyValueStoreProvider);

  @override
  ParentControls build() =>
      _store.getJson<ParentControls>(storageKey, ParentControls.fromJson) ??
      const ParentControls();

  Future<void> _write(ParentControls next) async {
    state = next;
    await _store.setJson(storageKey, next.toJson());
  }

  Future<void> setDailyLimit(int minutes) =>
      _write(state.copyWith(dailyLimitMinutes: minutes.clamp(0, 120)));

  Future<void> setAllowMicrophone(bool value) =>
      _write(state.copyWith(allowMicrophone: value));

  Future<void> setAllowOpenChat(bool value) =>
      _write(state.copyWith(allowOpenChat: value));

  Future<void> setStickerShop(bool value) =>
      _write(state.copyWith(allowStickerShop: value));

  Future<void> setReminders({
    required bool enabled,
    TimeOfDay24? at,
  }) async {
    final next = state.copyWith(
      remindersEnabled: enabled,
      reminderTime: at ?? state.reminderTime,
    );
    await _write(next);
    final scheduler = ref.read(reminderSchedulerProvider);
    if (!enabled) {
      await scheduler.cancelAll();
      return;
    }
    await scheduler.requestPermissions();
    await scheduler.scheduleDaily(
      id: 'daily_practice',
      at: next.reminderTime,
      title: 'Time for your reading game',
      body: 'Three small missions are waiting for you.',
    );
  }
}

final parentControlsProvider =
    NotifierProvider<ParentControlsController, ParentControls>(
  ParentControlsController.new,
);
