import 'package:flutter_test/flutter_test.dart';
import 'package:phonicsai/core/storage/in_memory_secure_vault.dart';
import 'package:phonicsai/core/storage/key_value_store.dart';
import 'package:phonicsai/features/auth/data/device_account_repository.dart';
import 'package:phonicsai/features/auth/domain/auth_models.dart';

void main() {
  late InMemoryKeyValueStore store;
  late DeviceAccountRepository repository;

  setUp(() {
    store = InMemoryKeyValueStore();
    repository = DeviceAccountRepository(
      store: store,
      vault: InMemorySecureVault(),
      latency: Duration.zero,
    );
  });

  tearDown(() async {
    await repository.dispose();
    await store.dispose();
  });

  test('starts signed out', () async {
    final state = await repository.current();
    expect(state.status, AuthStatus.signedOut);
    expect(state.isSignedIn, isFalse);
  });

  test('sign up stores the user and a token, and emits state', () async {
    final states = <AuthState>[];
    final sub = repository.watchState().listen(states.add);

    final result = await repository.signUp(
      email: '  Parent@Example.com ',
      password: 'longenough',
      displayName: 'Parent',
    );
    expect(result.isOk, isTrue);
    expect(result.requireValue.user.email, 'parent@example.com');
    expect(result.requireValue.user.isGuest, isFalse);
    expect(result.requireValue.accessToken, isNotEmpty);

    final state = await repository.current();
    expect(state.hasRealAccount, isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(states.any((s) => s.hasRealAccount), isTrue);
    await sub.cancel();
  });

  test('bad email and short password are validation failures', () async {
    expect((await repository.signUp(
      email: 'nope',
      password: 'longenough',
      displayName: 'P',
    )).isFailure, isTrue);

    final shortPassword = await repository.signUp(
      email: 'a@b.co',
      password: '123',
      displayName: 'P',
    );
    expect(shortPassword.isFailure, isTrue);
    expect(shortPassword.failureOrNull!.message, contains('8'));
  });

  test('guest mode can sync nothing', () async {
    final result = await repository.continueAsGuest();
    expect(result.isOk, isTrue);
    expect(result.requireValue.user.isGuest, isTrue);
    expect(result.requireValue.user.canSync, isFalse);
  });

  test('sign in before any account exists explains itself', () async {
    final result = await repository.signIn(
      email: 'a@b.co',
      password: 'longenough',
    );
    expect(result.isFailure, isTrue);
    expect(result.failureOrNull!.message, contains('Create one'));
  });

  test('sign out clears the cached state and the token', () async {
    await repository.signUp(
      email: 'a@b.co',
      password: 'longenough',
      displayName: 'P',
    );
    await repository.signOut();
    expect((await repository.current()).status, AuthStatus.signedOut);
    expect(store.getString('phonicsai.auth.user'), isNull);
  });

  test('password reset never leaks whether the account exists', () async {
    final unknown = await repository.sendPasswordReset('who@ever.com');
    final empty = await repository.sendPasswordReset('  ');
    expect(unknown.isOk, isTrue);
    expect(empty.isFailure, isTrue);
  });
}
