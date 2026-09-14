import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/env/app_config.dart';
import '../../../core/error/failure.dart';
import '../../../core/network/session_token_holder.dart';
import '../../../core/result/result.dart';
import '../../../core/security/secure_vault.dart';
import '../../../core/storage/key_value_store.dart';
import '../domain/auth_models.dart';
import '../domain/auth_repository.dart';

/// Talks to the real PhonicsAI backend (`/api/v1`).
///
/// Contract with `api/` (see `api/app/routers/auth.py`):
///  * `POST /auth/login` and `/auth/refresh` return a token pair; the refresh
///    token ROTATES, so it is re-persisted on every refresh.
///  * Only the refresh token goes into [SecureVault]; the access token lives in
///    memory and is handed to [SessionTokenHolder] for ApiClient's bearer.
///  * The access token is treated as expiring client-side a minute early, and
///    `_ensureFresh` refreshes lazily before authenticated calls.
///
/// Guest mode stays device-local by design (COPPA posture): a child can use
/// the app with zero server data, and signing in later starts sync.
class HttpAuthRepository implements AuthRepository {
  /// Real-network constructor used by the DI container.
  factory HttpAuthRepository.live({
    required AppConfig config,
    required http.Client client,
    required KeyValueStore store,
    required SecureVault vault,
    SessionTokenHolder? tokenHolder,
  }) {
    final send = _HttpClientSend(client);
    final repo = HttpAuthRepository(
      config: config,
      send: send.call,
      store: store,
      vault: vault,
      tokenHolder: tokenHolder,
    );
    send.repository = repo; // authenticated calls read the bearer from here
    return repo;
  }

  /// Visible-for-testing constructor: [send] is the raw transport so unit
  /// tests can answer with canned payloads, no sockets involved.
  HttpAuthRepository({
    required AppConfig config,
    required this._send,
    required this._store,
    required this._vault,
    SessionTokenHolder? tokenHolder,
    this._refreshSkew = const Duration(minutes: 1),
  })  : _base = config.apiBaseUrl.trim() {
    holder = tokenHolder ?? SessionTokenHolder();
    holder.onRefresh = _refreshToAccessToken;
  }

  final Future<({int status, Map<String, dynamic> body})> Function(
    String method,
    String url, {
    Map<String, Object?>? body,
    bool withToken,
  }) _send;

  final String _base;
  final KeyValueStore _store;
  final SecureVault _vault;
  final Duration _refreshSkew;
  late final SessionTokenHolder holder;

  static const _refreshKey = 'phonicsai.auth.refresh';
  static const _userKey = 'phonicsai.auth.user';

  final _stateController = StreamController<AuthState>.broadcast();
  AuthState? _cached;
  DateTime? _accessExpiresAt;
  bool _closed = false;

  // ---------------------------------------------------------------- lifecycle

  @override
  Stream<AuthState> watchState() async* {
    yield await current();
    yield* _stateController.stream;
  }

  @override
  Future<AuthState> current() async {
    if (_cached != null) return _cached!;
    final userJson = _store.getJson<Map<String, dynamic>>(
      _userKey,
      (j) => j,
    );
    final refresh = await _vault.read(_refreshKey);
    if (userJson == null) {
      _cached = const AuthState.signedOut();
      return _cached!;
    }
    final user = AuthUser.fromJson(userJson);
    if (user.isGuest) {
      // Guest sessions are device-local: no server tokens exist.
      _cached = AuthState.signedIn(user, AuthSession(accessToken: '', user: user));
      return _cached!;
    }
    if (refresh == null) {
      _cached = const AuthState.signedOut();
      return _cached!;
    }
    // Mint a fresh access token from the stored refresh token. If the server
    // rejects it, the session is gone — not a half-logged-in state.
    final access = await _refreshToAccessToken();
    if (access == null) {
      _cached = const AuthState.signedOut();
      return _cached!;
    }
    _cached = AuthState.signedIn(
      user,
      AuthSession(accessToken: access, user: user, expiresAt: _accessExpiresAt),
    );
    return _cached!;
  }

  // ----------------------------------------------------------------- sign-in

  @override
  Future<Result<AuthSession>> signIn({
    required String email,
    required String password,
  }) async {
    final normalised = email.trim().toLowerCase();
    if (password.isEmpty || normalised.isEmpty) {
      return const Result.fail(
        AppFailure.validation('Enter your email and password.'),
      );
    }
    final res = await _call('POST', '/auth/login',
        body: {'email': normalised, 'password': password});
    return switch (res) {
      Ok(:final value) => _establishSession(value, normalised),
      Fail(:final failure) => Result.fail(failure),
    };
  }

  @override
  Future<Result<AuthSession>> signUp({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final normalised = email.trim().toLowerCase();
    if (password.length < 8) {
      return const Result.fail(
        AppFailure.validation('Pick a longer password (8+ characters).'),
      );
    }
    final created = await _call('POST', '/auth/register', body: {
      'email': normalised,
      'password': password,
      'display_name': displayName.trim().isEmpty ? 'Parent' : displayName.trim(),
      'locale': 'en',
    });
    if (created case Fail(:final failure)) return Result.fail(failure);
    // The API separates account creation from session minting; sign straight in.
    return signIn(email: normalised, password: password);
  }

  @override
  Future<Result<AuthSession>> continueAsGuest() async {
    final user = AuthUser.guest();
    await _store.setJson(_userKey, user.toJson());
    final state =
        AuthState.signedIn(user, AuthSession(accessToken: '', user: user));
    _cached = state;
    _emit(state);
    return Result.ok(state.session!);
  }

  // ------------------------------------------------------------- password flow

  @override
  Future<Result<void>> sendPasswordReset(String email) async {
    // The endpoint answers 202 even for unknown addresses (no enumeration).
    final res = await _call('POST', '/auth/password-reset',
        body: {'email': email.trim().toLowerCase()});
    return switch (res) {
      Ok() => const Result.ok(null),
      Fail(:final failure) => Result.fail(failure),
    };
  }

  // --------------------------------------------------------------------- misc

  @override
  Future<void> signOut() async {
    final refresh = await _vault.read(_refreshKey);
    if (refresh != null) {
      // Best-effort server-side revocation; local teardown must not wait on it.
      try {
        await _send('POST', '$_base/auth/logout',
            body: {'refresh_token': refresh}, withToken: true);
      } on Object {
        // ignored: tokens are cleared locally regardless
      }
    }
    await _teardownLocal();
  }

  @override
  Future<Result<void>> deleteAccount() async {
    final res = await _call('DELETE', '/auth/account');
    if (res case Fail(:final failure)) return Result.fail(failure);
    await _teardownLocal();
    return const Result.ok(null);
  }

  @override
  Future<Result<String?>> refresh() async {
    final token = await _refreshToAccessToken();
    if (token == null) {
      return const Result.fail(
        AppFailure(
          kind: FailureKind.unauthorized,
          message: 'Please sign in again.',
          detail: 'refresh token rejected',
        ),
      );
    }
    return Result.ok(token);
  }

  /// Called by [ApiClient] after a 401: refresh once, report the new token.
  Future<String?> _refreshToAccessToken() async {
    if (_accessExpiresAt != null &&
        DateTime.now().isBefore(_accessExpiresAt!.subtract(_refreshSkew)) &&
        holder.accessToken != null &&
        holder.accessToken!.isNotEmpty) {
      return holder.accessToken;
    }
    final refresh = await _vault.read(_refreshKey);
    if (refresh == null) return null;
    try {
      final res = await _send('POST', '$_base/auth/refresh',
          body: {'refresh_token': refresh});
      if (res.status != 200) {
        await _teardownLocal();
        return null;
      }
      final ok = await _storePair(res.body);
      return ok ? res.body['access_token'] as String? : null;
    } on Object {
      return null;
    }
  }

  Future<bool> _storePair(Map<String, dynamic> body) async {
    final access = body['access_token'];
    final refresh = body['refresh_token'];
    if (access is! String || refresh is! String) return false;
    final expiresIn = (body['expires_in'] as num?)?.toInt() ?? 900;
    await _vault.write(_refreshKey, refresh);
    _accessExpiresAt = DateTime.now().add(Duration(seconds: expiresIn));
    holder.update(access);
    return true;
  }

  Future<Result<AuthSession>> _establishSession(
    Map<String, dynamic> body,
    String email,
  ) async {
    final userJson = body['user'] as Map<String, dynamic>? ?? const {};
    final user = AuthUser(
      id: (userJson['id'] ?? '').toString(),
      displayName: (userJson['display_name'] ?? email.split('@').first).toString(),
      email: (userJson['email'] ?? email).toString(),
      isGuest: false,
      createdAt:
          DateTime.tryParse((userJson['created_at'] ?? '').toString()) ??
              DateTime.now(),
    );
    await _store.setJson(_userKey, user.toJson());
    if (!await _storePair(body)) {
      return Result.fail(
        const AppFailure(
          kind: FailureKind.parse,
          message: 'The sign-in response could not be read.',
          detail: 'malformed token pair',
        ),
      );
    }
    final session = AuthSession(
      accessToken: body['access_token'] as String,
      user: user,
      expiresAt: _accessExpiresAt,
    );
    final state = AuthState.signedIn(user, session);
    _cached = state;
    _emit(state);
    return Result.ok(session);
  }

  Future<void> _teardownLocal() async {
    await _vault.delete(_refreshKey);
    await _store.remove(_userKey);
    _accessExpiresAt = null;
    holder.clear();
    final state = const AuthState.signedOut();
    _cached = state;
    _emit(state);
  }

  /// Transport-level error mapping shared by all non-refresh calls.
  Future<Result<Map<String, dynamic>>> _call(
    String method,
    String path, {
    Map<String, Object?>? body,
  }) async {
    try {
      final res = await _send(method, '$_base$path', body: body, withToken: true);
      if (res.status >= 200 && res.status < 300) return Result.ok(res.body);
      return Result.fail(_mapStatus(res.status, res.body, path: path));
    } on TimeoutException {
      return const Result.fail(
        AppFailure(
          kind: FailureKind.timeout,
          message: 'The tutor is taking too long to answer.',
          detail: 'auth request timed out',
        ),
      );
    } on AppFailure catch (e) {
      return Result.fail(e);
    } on Object catch (e) {
      return Result.fail(
        AppFailure(
          kind: FailureKind.offline,
          message: 'No connection right now.',
          detail: '$e',
        ),
      );
    }
  }

  AppFailure _mapStatus(int status, Map<String, dynamic> body,
      {String path = ''}) {
    final code = switch (body['error']) {
      final Map<String, dynamic> e => (e['code'] ?? '').toString(),
      _ => '',
    };
    final detail = code.isEmpty ? 'HTTP $status' : code;
    final isLoginAttempt = path.endsWith('/auth/login');
    return switch (status) {
      401 || 403 => AppFailure(
          kind: FailureKind.unauthorized,
          message: switch (code) {
            'invalid_credentials' ||
            'unauthorized' when isLoginAttempt =>
              'That email and password do not match.',
            'account_disabled' => 'This account has been disabled.',
            _ => 'Please sign in again.',
          },
          detail: detail,
        ),
      404 => AppFailure(
          kind: FailureKind.notFound,
          message: 'We could not find that.',
          detail: detail,
        ),
      409 => AppFailure(
          kind: FailureKind.conflict,
          message: switch (code) {
            'email_taken' => 'That email already has an account.',
            _ => 'That conflicts with something we already have.',
          },
          detail: detail,
        ),
      422 => AppFailure(
          kind: FailureKind.validation,
          message: 'Please check what you typed.',
          detail: detail,
        ),
      429 => AppFailure(
          kind: FailureKind.rateLimited,
          message: 'A few too many attempts — try again in a minute.',
          detail: detail,
        ),
      _ => AppFailure(
          kind: FailureKind.unknown,
          message: status >= 500
              ? 'Our servers are having a moment.'
              : 'That did not work.',
          detail: detail,
        ),
    };
  }

  void _emit(AuthState state) {
    if (!_closed) _stateController.add(state);
  }

  /// Used by [_HttpClientSend] for authenticated calls.
  String? get bearer => holder.accessToken;

  Future<void> dispose() async {
    _closed = true;
    await _stateController.close();
    await holder.dispose();
  }
}


/// Thin default transport: JSON in, JSON out, bearer from the repository.
class _HttpClientSend {
  _HttpClientSend(this._client);

  final http.Client _client;
  HttpAuthRepository? repository;

  Future<({int status, Map<String, dynamic> body})> call(
    String method,
    String url, {
    Map<String, Object?>? body,
    bool withToken = false,
  }) async {
    final bearer = withToken ? repository?.bearer : null;
    final request = http.Request(method, Uri.parse(url))
      ..headers.addAll({
        'Accept': 'application/json',
        if (bearer != null && bearer.isNotEmpty)
          'Authorization': 'Bearer $bearer',
      });
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    final streamed = await _client.send(request).timeout(
      const Duration(seconds: 20),
    );
    final response = await http.Response.fromStream(streamed);
    Map<String, dynamic> decoded;
    if (response.body.isEmpty) {
      decoded = const <String, dynamic>{};
    } else {
      final raw = jsonDecode(response.body);
      decoded = raw is Map<String, dynamic>
          ? raw
          : <String, dynamic>{'data': raw};
    }
    return (status: response.statusCode, body: decoded);
  }
}
