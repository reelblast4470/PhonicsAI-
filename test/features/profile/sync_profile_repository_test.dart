import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:phonicsai/app/di/infrastructure.dart';
import 'package:phonicsai/core/domain/learner_profile.dart';
import 'package:phonicsai/core/env/app_config.dart';
import 'package:phonicsai/core/network/api_client.dart';
import 'package:phonicsai/core/result/result.dart';
import 'package:phonicsai/core/storage/key_value_store.dart';
import 'package:phonicsai/features/profile/application/profile_providers.dart';
import 'package:phonicsai/features/profile/data/local_profile_repository.dart';
import 'package:phonicsai/features/profile/data/sync_profile_repository.dart';
import 'package:phonicsai/features/profile/domain/profile_repository.dart';
import 'package:phonicsai/features/progress/data/backend_progress_sync.dart';


void main() {
  late InMemoryKeyValueStore store;
  late List<String> calls;
  late bool offline;

  MockClient client() => MockClient((req) async {
        if (offline) return http.Response('{"error":{}}', 500);
        calls.add('${req.method} ${req.url.path}');
        if (req.method == 'POST' && req.url.path.endsWith('/learners')) {
          final body = jsonDecode(req.body) as Map;
          return http.Response(
            jsonEncode({
              'id': 'L-${body['display_name']}',
              'display_name': body['display_name'],
            }),
            201,
          );
        }
        return http.Response('{"ok":true}', 200);
      });

  setUp(() {
    store = InMemoryKeyValueStore();
    calls = [];
    offline = false;
  });
  tearDown(() => store.dispose());

  SyncProfileRepository repo(BackendProgressSync? sync) =>
      SyncProfileRepository(
        local: LocalProfileRepository(store: store),
        api: ApiClient(
          config: const AppConfig(
            flavor: AppFlavor.dev,
            apiBaseUrl: 'http://backend.test/api/v1',
            billingCurrency: 'USD',
            backendMode: BackendMode.live,
          ),
          httpClient: client(),
        ),
        store: store,
        sync: sync,
      );

  test('create pushes to the API and arms the progress mirror binding',
      () async {
    final sync = BackendProgressSync(
      api: ApiClient(
        config: const AppConfig(
          flavor: AppFlavor.dev,
          apiBaseUrl: 'http://backend.test/api/v1',
          billingCurrency: 'USD',
          backendMode: BackendMode.live,
        ),
        httpClient: client(),
      ),
      store: store,
    );
    final repository = repo(sync);
    final result = await repository.create(
      displayName: 'Aarav',
      ageMonths: 60,
      avatarId: 'tiger',
      level: ReadingLevelSeed.takeTest,
    );
    expect(result.isOk, isTrue);
    final profile = (result as Ok<LearnerProfile>).value;
    expect(calls, contains('POST /api/v1/learners'));
    expect(sync.learnerIdFor(profile.id), 'L-Aarav');
    expect(store.getString('phonicsai.profiles.pending'), isNot(contains('Aarav')));
  });

  test('offline create stays local, queues pending, flushes on warmUp',
      () async {
    offline = true;
    final repository = repo(null);
    final result = await repository.create(
      displayName: 'Meera',
      ageMonths: 66,
      avatarId: 'owl',
      level: ReadingLevelSeed.manual,
    );
    expect(result.isOk, isTrue); // the child can start learning NOW
    expect(store.getString('phonicsai.profiles.pending'), contains('Meera'));

    offline = false;
    await repository.warmUp();
    expect(calls, contains('POST /api/v1/learners'));
    expect(store.getString('phonicsai.profiles.pending') ?? '[]', isNot(contains('Meera')));
    expect(repository.remoteIdFor((result as Ok<LearnerProfile>).value.id), 'L-Meera');
  });

  test('update patches the remote display name when bound', () async {
    final repository = repo(null);
    final created = (await repository.create(
      displayName: 'Zoe',
      ageMonths: 60,
      avatarId: 'fox',
      level: ReadingLevelSeed.takeTest,
    )) as Ok<LearnerProfile>;
    calls.clear();
    await repository.update(created.value.copyWith(displayName: 'Zoe R'));
    expect(calls, contains('PATCH /api/v1/learners/L-Zoe'));
  });

  test('delete reaches the API and drops the binding', () async {
    final repository = repo(null);
    final created = (await repository.create(
      displayName: 'Sam',
      ageMonths: 72,
      avatarId: 'owl',
      level: ReadingLevelSeed.takeTest,
    )) as Ok<LearnerProfile>;
    await repository.delete(created.value.id);
    expect(calls, contains('DELETE /api/v1/learners/L-Sam'));
    expect(repository.remoteIdFor(created.value.id), isNull);
  });

  test('provider override composes the same stack', () async {
    final container = ProviderContainer(overrides: [
      keyValueStoreProvider.overrideWithValue(store),
      appConfigProvider.overrideWithValue(const AppConfig(
        flavor: AppFlavor.dev,
        apiBaseUrl: 'http://backend.test/api/v1',
        billingCurrency: 'USD',
        backendMode: BackendMode.live,
      )),
      httpClientProvider.overrideWithValue(client()),
    ]);
    addTearDown(container.dispose);
    final repository = container.read(profileRepositoryProvider);
    expect(repository, isA<SyncProfileRepository>());
  });
}
