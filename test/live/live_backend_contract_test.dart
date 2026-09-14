@Tags(['live'])
library;

/// Flutter <-> FastAPI contract test against a REAL server over a REAL socket.
///
/// Opt-in because it needs the API running, e.g.:
///   cd api && python3 -m uvicorn app.main:app --port 8099 &
///   PHONICS_LIVE_BASE=http://127.0.0.1:8099/api/v1 \
///     flutter test test/live/live_backend_contract_test.dart
///
/// It exercises exactly what the app's adapters send — nothing hand-rolled.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:phonicsai/core/env/app_config.dart';
import 'package:phonicsai/core/network/api_client.dart';
import 'package:phonicsai/core/network/session_token_holder.dart';
import 'package:phonicsai/core/storage/in_memory_secure_vault.dart';
import 'package:phonicsai/core/storage/key_value_store.dart';
import 'package:phonicsai/features/assessment/data/assessment_remote.dart';
import 'package:phonicsai/features/auth/data/http_auth_repository.dart';
import 'package:phonicsai/features/progress/data/backend_progress_sync.dart';

final base = Platform.environment['PHONICS_LIVE_BASE'] ?? '';

void main() {
  final skip = base.isEmpty
      ? 'set PHONICS_LIVE_BASE (e.g. http://127.0.0.1:8099/api/v1) to run'
      : null;

  late AppConfig config;
  late http.Client client;
  late InMemoryKeyValueStore store;
  late InMemorySecureVault vault;
  late SessionTokenHolder holder;
  late HttpAuthRepository auth;
  late ApiClient api;

  setUp(() {
    config = AppConfig(
      flavor: AppFlavor.dev,
      apiBaseUrl: base,
      billingCurrency: 'INR',
      backendMode: BackendMode.live,
    );
    client = http.Client();
    store = InMemoryKeyValueStore();
    vault = InMemorySecureVault();
    holder = SessionTokenHolder();
    auth = HttpAuthRepository.live(
      config: config,
      client: client,
      store: store,
      vault: vault,
      tokenHolder: holder,
    );
    api = ApiClient(
      config: config,
      httpClient: client,
      tokenProvider: holder,
    );
  });

  tearDown(() async {
    await auth.dispose();
    await holder.dispose();
    await store.dispose();
    client.close();
  });

  test('full family journey over real HTTP', () async {
    final email = 'flutter-live-${DateTime.now().microsecondsSinceEpoch}@mail.phonics.dev';
    const password = 'Str0ngPassphrase!42';

    final signUp = await auth.signUp(
      email: email,
      password: password,
      displayName: 'Live Tester',
    );
    expect(signUp.isOk, isTrue, reason: '${signUp.failureOrNull?.detail}');
    expect(holder.accessToken, isNotNull);

    // bearer flows through ApiClient automatically
    final courses = await api.getListJson('/content/courses');
    expect(courses, isNotEmpty);
    final firstLesson =
        (courses.first['modules'] as List).first['lessons'].first as Map;
    expect(firstLesson['title'], isNotNull);

    final learners = await api.getListJson('/learners');
    expect(learners, isEmpty);
    final learner = await api.postJson('/learners', body: {
      'display_name': 'Viva',
      'daily_target_minutes': 15,
    });
    final learnerId = learner['id'] as String;

    // the sync adapter pushes real ledger events end-to-end
    final sync = BackendProgressSync(api: api, store: store);
    final bound = await sync.bindProfileByName(
      profileId: 'profile-viva',
      learnerName: 'Viva',
    );
    expect(bound.valueOrNull, learnerId);

    await sync.onGameRound(
      profileId: 'profile-viva',
      gameId: 'soundMatch',
      score: 220,
      stars: 2,
      secondsSpent: 65,
    );
    expect(sync.pendingCount, 0); // delivered live, nothing queued

    final snapshot = await api.getJson('/learners/$learnerId/snapshot');
    expect(snapshot['xp'], greaterThan(0)); // server derived, not client-fed

    final tasks = await api.getListJson('/learners/$learnerId/daily-tasks');
    expect(tasks.any((t) => t['completed'] == true), isTrue);

    // ---- Phase 3: real curriculum straight from the database ----
    final curriculum = await api.getJson('/content/curriculum');
    expect(curriculum['version'], isNotNull); // content_versions stamp
    final lessons = [
      for (final m in curriculum['courses'][0]['modules'] as List)
        for (final l in m['lessons'] as List) l as Map<String, dynamic>,
    ];
    expect(lessons.length, greaterThanOrEqualTo(50));

    // recommendation engine picks the first lesson for a fresh learner
    var rec = await api.getJson('/learners/$learnerId/recommendation');
    expect(rec['type'], 'lesson');
    expect(rec['lesson_code'], 'letter-s');
    final lessonUuid = rec['lesson_id'].toString();

    // open a REAL lesson (10 steps), answer a question, get the server verdict
    final lesson = await api.getJson('/content/lessons/$lessonUuid');
    expect((lesson['steps'] as List), hasLength(10));
    final lessonSid = (await api.postJson('/learners/$learnerId/sessions',
        body: {'kind': 'lesson', 'ref_id': lessonUuid}))['id'];
    final hearStep = (lesson['steps'] as List)
        .cast<Map<String, dynamic>>()
        .firstWhere((st) => st['step_type'] == 'hear');
    final q = (hearStep['questions'] as List).first as Map<String, dynamic>;
    final verdict = await api.postJson(
      '/learners/$learnerId/sessions/$lessonSid/events',
      body: {
        'event_type': 'question_answered',
        'payload': {
          'question_id': q['id'],
          'answer_id': (q['answers'] as List).first['id'],
          'phoneme': 's',
        },
      },
    );
    expect(verdict['correct'], isA<bool>()); // server decides
    if (verdict['correct'] == false) {
      expect(verdict['correct_answer_id'], isNotNull); // reveal after grading
    }
    final done = await api.postJson(
      '/learners/$learnerId/sessions/$lessonSid/complete',
      body: {
        'stars': 3,
        'accuracy': 0.95,
        'seconds_spent': 140,
        'phonemes': ['s'],
      },
    );
    expect(done['ok'], true);

    // mastery persisted server-side; recommendation advanced deterministically
    final mastery = await api.getListJson('/learners/$learnerId/mastery');
    expect(mastery.any((r) => r['subject_key'] == 's'), isTrue);
    rec = await api.getJson('/learners/$learnerId/recommendation');
    expect(rec['lesson_code'], 'letter-a');

    // placement through the app's OWN adapter: 16 server items, server band
    final remote = await AssessmentRemote.tryStart(
      api: api,
      learnerId: learnerId,
    );
    expect(remote, isNotNull);
    expect(remote!.questions, hasLength(16));
    final submitted = await remote.submit(List<int?>.filled(16, 0));
    expect(submitted.isOk, isTrue);
    final learnerAfter = await api.getJson('/learners/$learnerId');
    expect(learnerAfter['reading_level_key'], isNotNull);

    // wrong password fails cleanly through the auth adapter
    final bad = await auth.signIn(email: email, password: 'nope-nope-nope');
    expect(bad.isFailure, isTrue);
    expect(bad.failureOrNull!.message, contains('do not match'));

    // and the account wipes itself server-side
    await auth.signOut();
    final relogin = await auth.signIn(email: email, password: password);
    expect(relogin.isOk, isTrue); // signOut must NOT delete the account
    final deleted = await auth.deleteAccount();
    expect(deleted.isOk, isTrue, reason: '${deleted.failureOrNull?.detail}');
    final afterDelete = await auth.signIn(email: email, password: password);
    expect(afterDelete.isFailure, isTrue); // and it must
  }, skip: skip);
}
