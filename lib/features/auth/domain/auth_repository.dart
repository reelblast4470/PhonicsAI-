import '../../../core/result/result.dart';
import 'auth_models.dart';

/// Account boundary. `data/` decides whether this is the real PhonicsAI auth
/// API, a device-only stand-in, or a cache in front of both.
///
/// Notes for the backend team:
///  * tokens are stored in [SecureVault] and refreshed by [refresh];
///  * the client is expected to authenticate against *our* API, which then
///    calls the AI provider — no provider key ever ships in the binary.
abstract interface class AuthRepository {
  Stream<AuthState> watchState();

  Future<AuthState> current();

  Future<Result<AuthSession>> signIn({
    required String email,
    required String password,
  });

  Future<Result<AuthSession>> signUp({
    required String email,
    required String password,
    required String displayName,
  });

  Future<Result<AuthSession>> continueAsGuest();

  /// Passwordless reset: we ask the backend to email a link. The client must
  /// never see or compare the password itself.
  Future<Result<void>> sendPasswordReset(String email);

  Future<void> signOut();

  /// Removes the account and asks the backend to erase its data.
  Future<Result<void>> deleteAccount();

  Future<Result<String?>> refresh();
}
