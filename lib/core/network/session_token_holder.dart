import 'dart:async';

import 'auth_token_provider.dart';

/// A tiny mutable [AuthTokenProvider] that `features/auth` fills in when a
/// session changes, and [ApiClient] reads on every request.
///
/// It exists so the dependency graph stays acyclic: ApiClient depends on this
/// holder, the auth repository *writes* into it, and `refresh()` delegates
/// back to the repository through [onRefresh] (set once at wiring time).
class SessionTokenHolder implements AuthTokenProvider {
  SessionTokenHolder();

  /// Hook installed by the auth repository: fetch a fresh access token from
  /// the backend, or return null when the session is gone.
  Future<String?> Function()? onRefresh;

  String? _accessToken;
  final _controller = StreamController<String?>.broadcast();

  @override
  String? get accessToken => _accessToken;

  @override
  Stream<String?> get changes => _controller.stream;

  void update(String? token) {
    if (token == _accessToken) return;
    _accessToken = token;
    _controller.add(token);
  }

  void clear() => update(null);

  @override
  Future<String?> refresh() async {
    final hook = onRefresh;
    if (hook == null) return null;
    return hook();
  }

  Future<void> dispose() => _controller.close();
}
