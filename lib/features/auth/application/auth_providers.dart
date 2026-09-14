import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/infrastructure.dart';
import '../../../core/error/failure.dart';
import '../../../core/result/result.dart';
import '../data/device_account_repository.dart';
import '../domain/auth_models.dart';
import '../domain/auth_repository.dart';

/// Auth adapter for the current [AppConfig.backendMode].
///
/// mock mode  -> [DeviceAccountRepository] (per-device, no network at all)
/// live mode  -> `HttpAuthRepository` (POST /auth/session) — see README
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final repository = DeviceAccountRepository(
    store: ref.watch(keyValueStoreProvider),
    vault: ref.watch(secureVaultProvider),
  );
  ref.onDispose(repository.dispose);
  return repository;
});

final authStateProvider = StreamProvider<AuthState>(
  (ref) => ref.watch(authRepositoryProvider).watchState(),
);

/// The app is usable without an account (guest) — required for a COPPA posture
/// where a child can start learning before an adult decides to sync.
final canSyncProvider = Provider<bool>(
  (ref) => ref.watch(authStateProvider).valueOrNull?.hasRealAccount ?? false,
);

class AuthFormState {
  const AuthFormState({this.isBusy = false, this.failure, this.notice});

  final bool isBusy;
  final AppFailure? failure;

  /// One-shot informational text (e.g. "reset email sent").
  final String? notice;

  AuthFormState copyWith({bool? isBusy, AppFailure? failure, String? notice}) =>
      AuthFormState(
        isBusy: isBusy ?? this.isBusy,
        failure: failure,
        notice: notice,
      );

  static const idle = AuthFormState();
}

class AuthController extends Notifier<AuthFormState> {
  @override
  AuthFormState build() => AuthFormState.idle;

  AuthRepository get _repository => ref.read(authRepositoryProvider);

  Future<bool> signIn(String email, String password) =>
      _submit(() => _repository.signIn(email: email, password: password));

  Future<bool> signUp({
    required String email,
    required String password,
    required String displayName,
  }) => _submit(
    () => _repository.signUp(
      email: email,
      password: password,
      displayName: displayName,
    ),
  );

  Future<bool> continueAsGuest() => _submit(_repository.continueAsGuest);

  Future<void> sendPasswordReset(String email) async {
    state = const AuthFormState(isBusy: true);
    final result = await _repository.sendPasswordReset(email);
    state = result.fold(
      ok: (_) => const AuthFormState(notice: 'Check your inbox for a reset link.'),
      fail: (failure) => AuthFormState(failure: failure),
    );
  }

  Future<void> signOut() async {
    await _repository.signOut();
    state = AuthFormState.idle;
  }

  Future<bool> deleteAccount() => _submitVoid(_repository.deleteAccount);

  Future<bool> _submit(
    Future<Result<AuthSession>> Function() operation,
  ) => _submitVoid(operation);

  /// One shape for every action: busy -> result -> either idle or an
  /// explainable failure. No screen has to repeat this dance.
  Future<bool> _submitVoid(Future<Result<Object?>> Function() operation) async {
    state = const AuthFormState(isBusy: true);
    final result = await operation();
    state = result.fold(
      ok: (_) => AuthFormState.idle,
      fail: (failure) => AuthFormState(failure: failure),
    );
    return result.isOk;
  }

  void clearMessages() => state = AuthFormState.idle;
}

final authControllerProvider = NotifierProvider<AuthController, AuthFormState>(
  AuthController.new,
);
