import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:phonicsai/core/env/app_config.dart';
import 'package:phonicsai/core/network/api_client.dart';
import 'package:phonicsai/core/storage/key_value_store.dart';
import 'package:phonicsai/features/progress/data/backend_progress_sync.dart';
import 'package:phonicsai/features/progress/data/local_progress_repository.dart';

class _Backend {
  _Backend();

  final requests =
      <({String method, String path, Map<String, dynamic>? json})>[];
  bool failNext = false;

  MockClient get client => MockClient((request) async {
        final path = request.url.path;
        requests.add((
          method: request.method,
          path: path,
          json: request.body.isEmpty
              ? null
              : (jsonDecode(request.body) as Map).cast<String, dynamic>(),
        ));
        if (failNext) {
          failNext = false;
          return http.Response('{"error":{"code":"internal_error"}}', 500);
        }
        if (request.method == 'GET' && path == '/api/v1/learners') {
          return http.Response(
            jsonEncode([
              {'id': 'L1', 'display_name': 'Aarav'},
              {'id': 'L2', 'display_name': 'Meera'},
            ]),
            200,
          );
        }
        if (path.endsWith('/sessions') && request.method == 'POST') {
          return http.Response('{"id":"S${requests.length}"}', 201);
        }
        if (path.endsWith('/events')) {
          return http.Response('{"xp_awarded":5,"duplicate":false}', 200);
        }
        if (path.endsWith('/complete')) {
          return http.Response('{"ok":true,"xp_awarded":20}', 200);
        }
        if (path.endsWith('/abandon')) {
          return http.Response('{"ok":true}', 200);
        }
        return http.Response('{"detail":"not found"}', 404);
      });
}

ApiClient _apiFor(_Backend backend) => ApiClient(
      config: const AppConfig(
        flavor: AppFlavor.dev,
        apiBaseUrl: 'http://backend.test/api/v1',
        billingCurrency: 'USD',
        backendMode: BackendMode.live,
      ),
      httpClient: backend.client,
    );

void main() {
  late InMemoryKeyValueStore store;
  late _Backend backend;
  late BackendProgressSync sync;

  setUp(() {
    store = InMemoryKeyValueStore();
    backend = _Backend();
    sync = BackendProgressSync(api: _apiFor(backend), store: store);
  });

  tearDown(() async {
    await sync.dispose();
    await store.dispose();
  });

  test('unbound writes are queued durably, not dropped or guessed', () async {
    await sync.onGameRound(
      profileId: 'p1',
      gameId: 'soundMatch',
      score: 240,
      stars: 2,
      secondsSpent: 95,
    );
    expect(sync.pendingCount, 1);
    expect(backend.requests, isEmpty); // nothing left the device

    // Survives a "restart": a fresh instance reads the same durable queue.
    final revived = BackendProgressSync(api: _apiFor(backend), store: store);
    expect(revived.pendingCount, 1);
  });

  test('bindProfileByName resolves via the API and flushes the queue', () async {
    await sync.onGameRound(
      profileId: 'p1',
      gameId: 'soundMatch',
      score: 240,
      stars: 2,
      secondsSpent: 95,
    );
    final bound = await sync.bindProfileByName(
      profileId: 'p1',
      learnerName: 'aarav',
    );
    expect(bound.isOk, isTrue);
    expect(bound.valueOrNull, 'L1');

    await sync.flush(); // bind already drains; this must be a safe no-op
    expect(sync.pendingCount, 0);

    final paths = backend.requests
        .skip(1) // first was GET /learners from the bind
        .map((r) => r.path)
        .toList();
    expect(paths.any((p) => p.endsWith('/sessions')), isTrue);
    expect(paths.any((p) => p.endsWith('/events')), isTrue);
    expect(paths.any((p) => p.endsWith('/abandon')), isTrue);

    final start = backend.requests.firstWhere(
      (r) => r.method == 'POST' && r.path.endsWith('/sessions'),
    );
    expect(start.json!['kind'], 'game');
    expect(start.json!['ref_key'], 'sound-match'); // local id mapped
    final event = backend.requests.firstWhere((r) => r.path.endsWith('/events'));
    expect(event.json!['event_type'], 'game_completed');
    expect(event.json!['payload']['score'], 240);
    expect(event.json!['client_event_id'], isNotNull);
  });

  test('unknown learner name binds to nothing (no client-side invention)',
      () async {
    final bound = await sync.bindProfileByName(
      profileId: 'p1',
      learnerName: 'Nobody',
    );
    expect(bound.isOk, isTrue);
    expect(bound.valueOrNull, isNull);
    expect(sync.isEnabled, isFalse);
  });

  test('transient network failure keeps the op queued with attempts', () async {
    await sync.bindProfileByName(profileId: 'p1', learnerName: 'Aarav');
    backend.failNext = true; // next call after the bind GET fails
    await sync.onReadingMinutes(profileId: 'p1', minutes: 7);
    expect(sync.pendingCount, 1); // retried later
  });

  test('lesson finishes wait for a content mapping — never a guessed id',
      () async {
    await sync.bindProfileByName(profileId: 'p1', learnerName: 'Aarav');
    await sync.onLessonFinish(
      profileId: 'p1',
      lessonId: 'unit_satpin',
      stars: 3,
      accuracy: 0.9,
      secondsSpent: 210,
    );
    expect(sync.pendingCount, 1); // unmapped -> stays queued

    await sync.bindLesson(localLessonId: 'unit_satpin', backendLessonId: 'BEEF');
    await sync.onLessonFinish(
      profileId: 'p1',
      lessonId: 'unit_satpin',
      stars: 2,
      accuracy: 0.7,
      secondsSpent: 200,
    );
    await sync.flush();
    expect(sync.pendingCount, 0); // both delivered once mapped
    final complete = backend.requests.lastWhere((r) => r.path.endsWith('/complete'));
    expect(complete.json!['stars'], anyOf(2, 3));
  });

  test('LocalProgressRepository mirrors successful writes without blocking',
      () async {
    final mirror = _MirrorSpy();
    final repo = LocalProgressRepository(store: store, mirror: mirror);
    addTearDown(repo.dispose);

    await repo.finishLesson(
      profileId: 'kid',
      lessonId: 'unit_satpin',
      stars: 3,
      accuracy: 0.92,
      xp: 30,
      secondsSpent: 180,
      phonemes: ['s', 'a'],
    );
    await repo.recordGameRound(
      profileId: 'kid',
      gameId: 'bubblePop',
      score: 100,
      stars: 1,
      secondsSpent: 40,
    );
    await repo.addReadingMinutes(profileId: 'kid', minutes: 5);
    await pumpEventQueue();

    expect(mirror.lessons, 1);
    expect(mirror.games, 1);
    expect(mirror.reading, 1);
    expect(mirror.reviews, greaterThanOrEqualTo(2)); // from finishLesson loop
  });

  test('a mirror that throws never breaks the local write path', () async {
    final repo = LocalProgressRepository(store: store, mirror: _ThrowingMirror());
    addTearDown(repo.dispose);
    final result = await repo.addReadingMinutes(profileId: 'kid', minutes: 3);
    expect(result.isOk, isTrue);
    await pumpEventQueue();
  });
}

class _MirrorSpy implements ProgressMirror {
  int lessons = 0;
  int games = 0;
  int reading = 0;
  int reviews = 0;

  @override
  Future<void> onLessonFinish({
    required String profileId,
    required String lessonId,
    required int stars,
    required double accuracy,
    required double secondsSpent,
  }) async =>
      lessons++;

  @override
  Future<void> onGameRound({
    required String profileId,
    required String gameId,
    required int score,
    required int stars,
    required double secondsSpent,
  }) async =>
      games++;

  @override
  Future<void> onReadingMinutes({
    required String profileId,
    required int minutes,
  }) async =>
      reading++;

  @override
  Future<void> onSoundReview({
    required String profileId,
    required String phoneme,
    required int grade,
  }) async =>
      reviews++;
}

class _ThrowingMirror implements ProgressMirror {
  @override
  Future<void> onLessonFinish({
    required String profileId,
    required String lessonId,
    required int stars,
    required double accuracy,
    required double secondsSpent,
  }) async {
    throw StateError('boom');
  }

  @override
  Future<void> onGameRound({
    required String profileId,
    required String gameId,
    required int score,
    required int stars,
    required double secondsSpent,
  }) async {
    throw StateError('boom');
  }

  @override
  Future<void> onReadingMinutes({
    required String profileId,
    required int minutes,
  }) async {
    throw StateError('boom');
  }

  @override
  Future<void> onSoundReview({
    required String profileId,
    required String phoneme,
    required int grade,
  }) async {
    throw StateError('boom');
  }
}
