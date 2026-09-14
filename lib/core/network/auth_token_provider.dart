/// The API layer needs a bearer token but must not know how auth works.
/// `features/auth` implements this and hands it to [ApiClient].
abstract interface class AuthTokenProvider {
  String? get accessToken;
  Stream<String?> get changes;

  /// Called by the client once when a request came back 401; implementations
  /// should refresh the session and return the new token (or null).
  Future<String?> refresh();
}

/// Used while no account backend is wired (mock mode / signed-out).
class NoAuthTokenProvider implements AuthTokenProvider {
  const NoAuthTokenProvider();

  @override
  String? get accessToken => null;

  @override
  Stream<String?> get changes => const Stream<String?>.empty();

  @override
  Future<String?> refresh() async => null;
}
