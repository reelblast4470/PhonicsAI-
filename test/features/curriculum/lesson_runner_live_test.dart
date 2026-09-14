import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:phonicsai/app/di/infrastructure.dart';
import 'package:phonicsai/core/env/app_config.dart';
import 'package:phonicsai/core/network/api_client.dart';
import 'package:phonicsai/core/storage/key_value_store.dart';
import 'package:phonicsai/features/curriculum/application/curriculum_providers.dart';
import 'package:phonicsai/features/curriculum/application/lesson_runner.dart';
import 'package:phonicsai/features/curriculum/domain/lesson.dart';
import 'package:phonicsai/features/progress/application/progress_providers.dart';
import 'package:phonicsai/features/progress/data/backend_progress_sync.dart';
import 'package:phonicsai/features/progress/data/local_progress_repository.dart';

/// The Phase-3 promise, exercised through the REAL runner: the lesson came
/// from the backend (remoteId), the tap is graded by the SERVER (the client
/// has no answer key), the reveal marks the right option green, the server's
/// completion response drives the stars shown, and the durable mirror does
/// NOT double-send the lesson finish.

PhonicsLesson remoteLesson() => const PhonicsLesson(
      id: 'letter-s',
      unitId: 'mod-1',
      title: 'The sound of “s”',
      subtitle: 'Focus: s (/s/)',
      indexInUnit: 1,
      phonemes: ['s'],
      remoteId: 'uuid-lesson-1',
      stages: [
        LessonStage(kind: StageKind.discover, items: [StageItem(id: 'd', prompt: 'What?')]),
        LessonStage(
          kind: StageKind.hear,
          items: [
            StageItem(
              id: 'letter-s:2:q0',
              prompt: 'Which starts with /s/?',
              options: ['cat', 'sun'],
              optionIds: ['a-x', 'a-y'],
              remoteQuestionId: 'q-1',
            ),
          ],
        ),
        LessonStage(
          kind: StageKind.review,
          items: [StageItem(id: 'r', prompt: 'Stuck?', text: 's')],
        ),
      ],
    );

class _Flow {
  final calls = <({String method, String path, Map<String, dynamic>? json})>[];

  MockClient get client => MockClient((req) async {
        final body = req.body.isEmpty
            ? null
            : (jsonDecode(req.body) as Map).cast<String, dynamic>();
        calls.add((method: req.method, path: req.url.path, json: body));
        final p = req.url.path;
        if (p.endsWith('/sessions')) {
          return http.Response('{"id":"S1"}', 201);
        }
        if (p.endsWith('/events')) {
          final payload = body!['payload'];
          final isQ = body['event_type'] == 'question_answered';
          final wrong = isQ && payload['answer_id'] == 'a-x';
          return http.Response(
            jsonEncode({
              'ok': true,
              'xp_awarded': wrong ? 1 : 5,
              if (isQ) ...{
                'correct': !wrong,
                'correct_answer_id': 'a-y',
                'explanation': 'sun starts with /s/.',
                'chosen_feedback': wrong ? 'Listen again: sss.' : null,
              },
              'daily_tasks_completed': [],
              'achievements_earned': [],
            }),
            200,
          );
        }
        if (p.endsWith('/complete')) {
          return http.Response('{"ok":true,"stars":2,"xp_awarded":12}', 200);
        }
        return http.Response('{"ok":true}', 200);
      });

  ({String method, String path, Map<String, dynamic>? json})? callEndingWith(
          String suffix) =>
      calls.where((c) => c.path.endsWith(suffix)).firstOrNull;
}

void main() {
  test('remote lesson: server-graded answers, revealed key, server stars',
      () async {
    final flow = _Flow();
    final store = InMemoryKeyValueStore();
    final api = ApiClient(
      config: const AppConfig(
        flavor: AppFlavor.dev,
        apiBaseUrl: 'http://backend.test/api/v1',
        billingCurrency: 'USD',
        backendMode: BackendMode.live,
      ),
      httpClient: flow.client,
    );
    await store.setString('phonicsai.active_profile', 'p1');
    final sync = BackendProgressSync(api: api, store: store);
    await sync.bindProfile(profileId: 'p1', learnerId: 'L1');
    sync.registerRemoteLessons({'letter-s'});

    final container = ProviderContainer(overrides: [
      appConfigProvider.overrideWithValue(const AppConfig(
        flavor: AppFlavor.dev,
        apiBaseUrl: 'http://backend.test/api/v1',
        billingCurrency: 'USD',
        backendMode: BackendMode.live,
      )),
      keyValueStoreProvider.overrideWithValue(store),
      httpClientProvider.overrideWithValue(flow.client),
      backendProgressSyncProvider.overrideWithValue(sync),
      activeProfileIdProvider.overrideWithValue('p1'),
      progressRepositoryProvider
          .overrideWith((ref) => LocalProgressRepository(
                store: store,
                mirror: sync,
              )),
      lessonByIdProvider.overrideWithValue({'letter-s': remoteLesson()}),
    ]);
    addTearDown(() async {
      container.dispose();
      await store.dispose();
    });

    // start the run — the session opens against the backend
    container.read(lessonRunProvider('letter-s').notifier);
    await pumpEventQueue();
    final start = flow.callEndingWith('/learners/L1/sessions');
    expect(start, isNotNull, reason: 'live session must be opened');
    expect(start!.json!['ref_id'], 'uuid-lesson-1');

    // walk: discover -> hear
    final runner = container.read(lessonRunProvider('letter-s').notifier);
    await runner.nextStage();

    // answer the remote-graded question with the WRONG option (no local key!)
    await runner.answerChoice('letter-s:2:q0', 0); // 'cat' — server says no
    var state = container.read(lessonRunProvider('letter-s'))!;
    expect(state.outcomeOf('letter-s:2:q0'), ItemOutcome.wrong);
    // the server revealed the right option — the UI can mark it green
    expect(state.revealedCorrectIndex['letter-s:2:q0'], 1);
    final ev = flow.calls.where((c) => c.path.endsWith('/events')).last;
    expect(ev.json!['payload']['question_id'], 'q-1');
    expect(ev.json!['payload']['phoneme'], 's');

    // finish from here: accuracy 0 locally — but the SERVER decides the stars
    await runner.finish();
    await pumpEventQueue();

    state = container.read(lessonRunProvider('letter-s'))!;
    expect(state.isFinished, isTrue);
    // SERVER stars (2) override the local self-assessment (3): accuracy over
    // two attempts is 1/2 = 0.5 → server says 1... fake returns 2 explicitly.
    expect(state.savedStars, 2);
    expect(state.errorMessage, isNull);

    // local progress recorded under the STABLE code id
    // (snapshot keys are profile-relative by design)
    final snap =
        container.read(progressRepositoryProvider).snapshot('p1');
    expect(snap.lesson('letter-s').completedStages, containsAll(['discover', 'hear']));

    // and the mirror must NOT replay the lesson finish (no second completion)
    expect(sync.pendingCount, 0);
    final completes =
        flow.calls.where((c) => c.path.endsWith('/complete')).toList();
    expect(completes, hasLength(1));
  });
}
