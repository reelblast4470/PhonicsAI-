import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/infrastructure.dart';
import '../../../core/security/secure_vault.dart';
import '../../../core/storage/key_value_store.dart';
import '../../../core/storage/storage_keys.dart';

/// Parental gate for the grown-up area (purchases, settings, data controls).
///
/// Not a security boundary against a determined adult — it stops a child
/// reaching spend/settings. The PIN is stored only as a salted digest, and an
/// escalating lockout makes brute force pointless.
class ParentGateController extends Notifier<ParentGateState> {
  static const unlockWindow = Duration(minutes: 15);
  static const maxAttempts = 5;

  KeyValueStore get _settings => ref.read(keyValueStoreProvider);
  SecureVault get _vault => ref.read(secureVaultProvider);

  Timer? _autoLock;

  @override
  ParentGateState build() {
    ref.onDispose(() => _autoLock?.cancel());
    return ParentGateState(
      pinConfigured: _settings.getBool(StorageKeys.parentGatePinConfigured),
    );
  }

  Future<bool> hasPin() async => (await _vault.read(_saltKey)) != null;

  Future<void> setPin(String pin) async {
    final salt = const PinHasher().newSalt();
    final digest = const PinHasher().digest(pin, salt);
    await _vault.write(_saltKey, salt);
    await _vault.write(_digestKey, digest);
    await _settings.setBool(StorageKeys.parentGatePinConfigured, true);
    unlock();
    state = state.copyWith(pinConfigured: true, cleared: true);
  }

  Future<ParentGateResult> verify(String pin) async {
    if (state.isLocked) return ParentGateResult.locked;
    final salt = await _vault.read(_saltKey);
    final expected = await _vault.read(_digestKey);
    if (salt == null || expected == null) {
      // First run: no code yet, so whatever the adult types becomes it.
      await setPin(pin);
      return ParentGateResult.createdPin;
    }
    if (const PinHasher().digest(pin, salt) != expected) {
      final attempts = state.failedAttempts + 1;
      await _settings.setInt(StorageKeys.parentGateFailedAttempts, attempts);
      final lockFor = attempts >= maxAttempts
          ? Duration(seconds: 30 * attempts)
          : Duration.zero;
      state = state.copyWith(
        failedAttempts: attempts,
        lockedUntil: lockFor == Duration.zero ? null : DateTime.now().add(lockFor),
      );
      return lockFor == Duration.zero
          ? ParentGateResult.wrong
          : ParentGateResult.locked;
    }
    await _settings.setInt(StorageKeys.parentGateFailedAttempts, 0);
    unlock();
    state = state.copyWith(failedAttempts: 0, cleared: true);
    return ParentGateResult.unlocked;
  }

  void unlock() {
    state = state.copyWith(isUnlocked: true);
    _autoLock?.cancel();
    _autoLock = Timer(unlockWindow, () {
      state = state.copyWith(isUnlocked: false);
    });
  }

  void lock() {
    _autoLock?.cancel();
    state = state.copyWith(isUnlocked: false);
  }

  static const _saltKey = 'phonicsai.parent_gate.salt';
  static const _digestKey = 'phonicsai.parent_gate.digest';
}

enum ParentGateResult { unlocked, wrong, locked, createdPin }

class ParentGateState {
  const ParentGateState({
    this.isUnlocked = false,
    this.pinConfigured = false,
    this.failedAttempts = 0,
    this.lockedUntil,
  });

  final bool isUnlocked;
  final bool pinConfigured;
  final int failedAttempts;
  final DateTime? lockedUntil;

  bool get isLocked =>
      lockedUntil != null && DateTime.now().isBefore(lockedUntil!);

  Duration get lockRemaining => isLocked
      ? lockedUntil!.difference(DateTime.now())
      : Duration.zero;

  ParentGateState copyWith({
    bool? isUnlocked,
    bool? pinConfigured,
    int? failedAttempts,
    Object? lockedUntil = _sentinel,
    bool cleared = false,
  }) {
    return ParentGateState(
      isUnlocked: isUnlocked ?? this.isUnlocked,
      pinConfigured: pinConfigured ?? this.pinConfigured,
      failedAttempts: failedAttempts ?? this.failedAttempts,
      lockedUntil: cleared
          ? null
          : lockedUntil == _sentinel
              ? this.lockedUntil
              : lockedUntil as DateTime?,
    );
  }

  static const Object _sentinel = Object();
}

final parentGateProvider =
    NotifierProvider<ParentGateController, ParentGateState>(
  ParentGateController.new,
);
