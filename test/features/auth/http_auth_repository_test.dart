import 'package:flutter_test/flutter_test.dart';
import 'package:phonicsai/core/env/app_config.dart';
import 'package:phonicsai/core/network/session_token_holder.dart';
import 'package:phonicsai/core/storage/in_memory_secure_vault.dart';
import 'package:phonicsai/core/storage/key_value_store.dart';
import 'package:phonicsai/features/auth/data/http_auth_repository.dart';
import 'package:phonicsai/features/auth/domain/auth_models.dart';

typedef Responder =
    Future<({int status, Map<String, dynamic> body})> Function(
      String method,
      String url, {
      Map<String, Object?>? body,
      bool withToken,
    });

class _Recorded {
  _Recorded(this.method, this.url, this.body, this.withToken);
  final String method;
  final String url;
  final Map<String, Object?>? body;
  final bool withToken;
}

HttpAuthRepository repoWith(
  Responder responder, {
  required KeyValueStore store,
  required InMemorySecureVault vault,
  SessionTokenHolder? holder,
}) {
  return HttpAuthRepository(
    config: const AppConfig(
      flavor: AppFlavor.dev,
      apiBaseUrl: 'http://backend.test/api/v1',
      billingCurrency: 'USD',
      backendMode: BackendMode.live,
    ),
    send: (method, url, {body, withToken = false}) async {
      return responder(method, url, body: body, withToken: withToken);
    },
    store: store,
    vault: vault,
    tokenHolder: holder,
  );
}

Map<String, dynamic> pairJson({
  String access = 'ACC',
  String refresh = 'REF',
  int expiresIn = 900,
}) => {
  'access_token': access,
  'token_type': 'bearer',
  'expires_in': expiresIn,
  'refresh_token': refresh,
  'user': {
    'id': 'u-1',
    'email': 'parent@mail.phonics.dev',
    'display_name': 'Priya',
    'locale': 'en',
    'email_verified': true,
    'created_at': '2026-01-01T00:00:00Z',
  },
};

void main() {
  late InMemoryKeyValueStore store;
  late InMemorySecureVault vault;
  late SessionTokenHolder holder;
  late List<_Recorded> sent;

  setUp(() {
    store = InMemoryKeyValueStore();
    vault = InMemorySecureVault();
    holder = SessionTokenHolder();
    sent = [];
  });

  tearDown(() async {
    await store.dispose();
  });

  group('signIn', () {
    test('stores refresh in the vault, access in the holder, emits signedIn',
        () async {
      final repo = repoWith((m, u, {body, withToken = false}) async {
        sent.add(_Recorded(m, u, body, withToken));
        expect(u, 'http://backend.test/api/v1/auth/login');
        return (status: 200, body: pairJson());
      }, store: store, vault: vault, holder: holder);
      addTearDown(repo.dispose);

      final states = <AuthState>[];
      final sub = repo.watchState().listen(states.add);
      addTearDown(sub.cancel);

      final result = await repo.signIn(
        email: ' Parent@Mail.Phonics.Dev ',
        password: 'longenoughpw',
      );
      expect(result.isOk, isTrue);
      expect(result.valueOrNull!.accessToken, 'ACC');
      expect(await vault.read('phonicsai.auth.refresh'), 'REF');
      expect(holder.accessToken, 'ACC');
      expect(sent.single.body!['email'], 'parent@mail.phonics.dev');
      await pumpEventQueue();
      expect(states.last.isSignedIn, isTrue);
      expect(states.last.user!.displayName, 'Priya');
    });

    test('maps invalid_credentials to a friendly failure', () async {
      final repo = repoWith((m, u, {body, withToken = false}) async {
        return (
          status: 401,
          body: {
            'error': {'code': 'invalid_credentials', 'message': 'no'},
          },
        );
      }, store: store, vault: vault, holder: holder);
      addTearDown(repo.dispose);
      final result = await repo.signIn(
        email: 'a@b.dev',
        password: 'whatever',
      );
      expect(result.isFailure, isTrue);
      expect(result.failureOrNull!.message,
          'That email and password do not match.');
    });

    test('rate limit surfaces as a retry-later failure', () async {
      final repo = repoWith((m, u, {body, withToken = false}) async {
        return (status: 429, body: const <String, dynamic>{});
      }, store: store, vault: vault, holder: holder);
      addTearDown(repo.dispose);
      final result = await repo.signIn(email: 'a@b.dev', password: 'x');
      expect(result.failureOrNull!.kind.name, 'rateLimited');
    });
  });

  group('signUp', () {
    test('registers then signs in automatically', () async {
      final repo = repoWith((m, u, {body, withToken = false}) async {
        sent.add(_Recorded(m, u, body, withToken));
        if (u.endsWith('/auth/register')) {
          return (
            status: 201,
            body: {'id': 'u-1', 'email': 'new@dev.io'},
          );
        }
        return (status: 200, body: pairJson());
      }, store: store, vault: vault, holder: holder);
      addTearDown(repo.dispose);

      final result = await repo.signUp(
        email: 'new@dev.io',
        password: 'longenoughpw',
        displayName: 'New',
      );
      expect(result.isOk, isTrue);
      expect(sent.map((r) => r.url), [
        'http://backend.test/api/v1/auth/register',
        'http://backend.test/api/v1/auth/login',
      ]);
    });

    test('short passwords never hit the network', () async {
      final repo = repoWith((m, u, {body, withToken = false}) async {
        throw StateError('must not be called');
      }, store: store, vault: vault, holder: holder);
      addTearDown(repo.dispose);
      final result = await repo.signUp(
        email: 'a@b.dev',
        password: 'short',
        displayName: 'x',
      );
      expect(result.isFailure, isTrue);
    });
  });

  test('current() mints a fresh access token from the stored refresh', () async {
    await vault.write('phonicsai.auth.refresh', 'SAVED');
    await store.setString(
      'phonicsai.auth.user',
      '{"id":"u-1","displayName":"Priya","email":"p@q.dev","isGuest":false,'
          '"createdAt":"2026-01-01T00:00:00Z"}',
    );
    final repo = repoWith((m, u, {body, withToken = false}) async {
      sent.add(_Recorded(m, u, body, withToken));
      expect(u, endsWith('/auth/refresh'));
      expect(body!['refresh_token'], 'SAVED');
      return (status: 200, body: pairJson(access: 'FRESH', refresh: 'ROT'));
    }, store: store, vault: vault, holder: holder);
    addTearDown(repo.dispose);

    final state = await repo.current();
    expect(state.isSignedIn, isTrue);
    expect(state.session!.accessToken, 'FRESH');
    expect(holder.accessToken, 'FRESH');
    expect(await vault.read('phonicsai.auth.refresh'), 'ROT'); // rotated
  });

  test('a rejected refresh signs the session out', () async {
    await vault.write('phonicsai.auth.refresh', 'STALE');
    await store.setString(
      'phonicsai.auth.user',
      '{"id":"u-1","displayName":"P","email":"p@q.dev","isGuest":false,'
          '"createdAt":"2026-01-01T00:00:00Z"}',
    );
    final repo = repoWith((m, u, {body, withToken = false}) async {
      return (status: 401, body: const <String, dynamic>{});
    }, store: store, vault: vault, holder: holder);
    addTearDown(repo.dispose);

    final state = await repo.current();
    expect(state.status, AuthStatus.signedOut);
    expect(await vault.read('phonicsai.auth.refresh'), isNull);
  });

  test('signOut revokes server-side then clears locally', () async {
    await vault.write('phonicsai.auth.refresh', 'REF');
    final repo = repoWith((m, u, {body, withToken = false}) async {
      sent.add(_Recorded(m, u, body, withToken));
      if (u.endsWith('/auth/login')) return (status: 200, body: pairJson());
      return (status: 204, body: const <String, dynamic>{});
    }, store: store, vault: vault, holder: holder);
    addTearDown(repo.dispose);
    await repo.signIn(email: 'a@b.dev', password: 'password1!');
    sent.clear();

    await repo.signOut();
    final logout = sent.singleWhere((r) => r.url.endsWith('/auth/logout'));
    expect(logout.withToken, isTrue);
    expect(logout.body!['refresh_token'], isNotNull);
    expect(await vault.read('phonicsai.auth.refresh'), isNull);
    expect(holder.accessToken, isNull);
  });

  test('sendPasswordReset never reveals account existence', () async {
    var called = 0;
    final repo = repoWith((m, u, {body, withToken = false}) async {
      called++;
      expect(u, endsWith('/auth/password-reset'));
      return (status: 202, body: const {'ok': true});
    }, store: store, vault: vault, holder: holder);
    addTearDown(repo.dispose);
    expect((await repo.sendPasswordReset('whoever@x.dev')).isOk, isTrue);
    expect(called, 1);
  });

  test('guest mode is fully local (no network, no tokens)', () async {
    final repo = repoWith((m, u, {body, withToken = false}) async {
      sent.add(_Recorded(m, u, body, withToken));
      return (status: 200, body: const <String, dynamic>{});
    }, store: store, vault: vault, holder: holder);
    addTearDown(repo.dispose);

    final result = await repo.continueAsGuest();
    expect(result.isOk, isTrue);
    expect(sent, isEmpty);
    final state = await repo.current();
    expect(state.user!.isGuest, isTrue);
    expect(holder.accessToken, isNull); // nothing to authorize with
  });

  test('deleteAccount sends the bearer and tears the session down', () async {
    final repo = repoWith((m, u, {body, withToken = false}) async {
      sent.add(_Recorded(m, u, body, withToken));
      if (u.endsWith('/auth/login')) return (status: 200, body: pairJson());
      return (status: 204, body: const <String, dynamic>{});
    }, store: store, vault: vault, holder: holder);
    addTearDown(repo.dispose);
    await repo.signIn(email: 'a@b.dev', password: 'password1!');
    sent.clear();

    final result = await repo.deleteAccount();
    expect(result.isOk, isTrue);
    final del = sent.single;
    expect(del.method, 'DELETE');
    expect(del.withToken, isTrue);
    expect(store.getString('phonicsai.auth.user'), isNull);
  });
}
