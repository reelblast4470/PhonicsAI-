import 'dart:async';
import 'dart:convert';

import '../../../core/error/failure.dart';
import '../../../core/result/result.dart';
import '../../../core/security/secure_vault.dart';
import '../../../core/storage/key_value_store.dart';
import '../domain/auth_models.dart';
import '../domain/auth_repository.dart';

/// **Not a backend.** A per-device account so that the whole sign-in / sign-up
/// / guest / delete flow — including its loading, error and confirmation
/// states — can be built and reviewed before the auth service exists.
///
/// When `POST /auth/session` lands, `HttpAuthRepository` implements the same
/// interface and this class becomes the offline fallback for the cached user
/// only (never for credentials).
class DeviceAccountRepository implements AuthRepository {
  DeviceAccountRepository({
    required this.store,
    required this.vault,
    this.latency = const Duration(milliseconds: 550),
  });

  static const _userKey = 'phonicsai.auth.user';
  static const _passwordHintKey = 'phonicsai.auth.pwd_ok';

  final KeyValueStore store;
  final SecureVault vault;
  final Duration latency;

  final _controller = StreamController<AuthState>.broadcast();
  AuthState? _cached;

  @override
  Stream<AuthState> watchState() async* {
    yield await current();
    yield* _controller.stream;
  }

  @override
  Future<AuthState> current() async {
    if (_cached != null) return _cached!;
    final raw = store.getString(_userKey);
    final state = raw == null
        ? const AuthState.signedOut()
        : AuthState.signedIn(
            AuthUser.fromJson(jsonDecode(raw) as Map<String, dynamic>),
            AuthSession(
              accessToken: await vault.read('phonicsai.auth.token') ?? 'local',
              user: AuthUser.fromJson(jsonDecode(raw) as Map<String, dynamic>),
            ),
          );
    _cached = state;
    return state;
  }

  @override
  Future<Result<AuthSession>> signIn({
    required String email,
    required String password,
  }) async {
    await _simulate();
    final normalised = email.trim().toLowerCase();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]{2,}$').hasMatch(normalised)) {
      return const Result.fail(
        AppFailure.validation(
          'That email does not look right.',
          'invalid email format',
        ),
      );
    }
    if (password.length < 8) {
      return const Result.fail(
        AppFailure.validation(
          'Use at least 8 characters.',
          'short password',
        ),
      );
    }
    final stored = store.getString(_userKey);
    if (stored == null) {
      return const Result.fail(
        AppFailure(
          kind: FailureKind.unauthorized,
          message: 'No account on this device yet. Create one first.',
          detail: 'device store empty',
        ),
      );
    }
    return _persist(AuthUser.fromJson(jsonDecode(stored) as Map<String, dynamic>));
  }

  @override
  Future<Result<AuthSession>> signUp({
    required String email,
    required String password,
    required String displayName,
  }) async {
    await _simulate();
    final normalised = email.trim().toLowerCase();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]{2,}$').hasMatch(normalised)) {
      return const Result.fail(
        AppFailure.validation('That email does not look right.'),
      );
    }
    if (password.length < 8) {
      return const Result.fail(
        AppFailure.validation('Pick a longer password (8+ characters).'),
      );
    }
    if (displayName.trim().isEmpty) {
      return const Result.fail(AppFailure.validation('Please add your name.'));
    }
    final user = AuthUser(
      id: 'family_${normalised.hashCode.toRadixString(16)}',
      displayName: displayName.trim(),
      email: normalised,
      isGuest: false,
      createdAt: DateTime.now(),
    );
    return _persist(user);
  }

  @override
  Future<Result<AuthSession>> continueAsGuest() async {
    await _simulate();
    return _persist(AuthUser.guest());
  }

  @override
  Future<Result<void>> sendPasswordReset(String email) async {
    await _simulate();
    if (email.trim().isEmpty) {
      return const Result.fail(
        AppFailure.validation('Type the email your account uses.'),
      );
    }
    // TODO(backend): POST /auth/password-reset — always answers "check your
    // inbox" so the endpoint cannot be used to enumerate accounts.
    return const Result.ok(null);
  }

  @override
  Future<void> signOut() async {
    await store.remove(_userKey);
    await store.remove(_passwordHintKey);
    await vault.delete('phonicsai.auth.token');
    _cached = const AuthState.signedOut();
    _emit(_cached!);
  }

  @override
  Future<Result<void>> deleteAccount() async {
    // TODO(backend): DELETE /auth/account + /learners — the server must be the
    // one that actually erases, the device cannot.
    await signOut();
    return const Result.ok(null);
  }

  @override
  Future<Result<String?>> refresh() async {
    final token = await vault.read('phonicsai.auth.token');
    return Result.ok(token);
  }

  Future<Result<AuthSession>> _persist(AuthUser user) async {
    final session = AuthSession(
      accessToken: 'local-${user.id}',
      user: user,
      expiresAt: DateTime.now().add(const Duration(days: 30)),
    );
    await store.setString(_userKey, jsonEncode(user.toJson()));
    await vault.write('phonicsai.auth.token', session.accessToken);
    final state = AuthState.signedIn(user, session);
    _cached = state;
    _emit(state);
    return Result.ok(session);
  }

  void _emit(AuthState state) {
    if (!_controller.isClosed) _controller.add(state);
  }

  Future<void> _simulate() => Future<void>.delayed(latency);

  Future<void> dispose() async {
    _cached = null;
    await _controller.close();
  }
}
