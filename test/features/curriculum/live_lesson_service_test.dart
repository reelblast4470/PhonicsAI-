import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:phonicsai/core/env/app_config.dart';
import 'package:phonicsai/core/network/api_client.dart';
import 'package:phonicsai/features/curriculum/data/live_lesson_service.dart';

class _Server {
  _Server();
  final calls = <({String method, String path, Map<String, dynamic>? json})>[];
  bool fail = false;
  Map<String, String> verdicts = {}; // answerId -> correctAnswerId

  MockClient get client => MockClient((req) async {
        final body = req.body.isEmpty
            ? null
            : (jsonDecode(req.body) as Map).cast<String, dynamic>();
        calls.add((method: req.method, path: req.url.path, json: body));
        if (fail) return http.Response('{"error":{}}', 500);
        final path = req.url.path;
        if (path.endsWith('/sessions') && req.method == 'POST') {
          return http.Response('{"id":"S-9"}', 201);
        }
        if (path.endsWith('/events')) {
          final qid = body!['payload']['question_id'];
          if (qid == null) return http.Response('{"ok":true}', 200);
          final chosen = body['payload']['answer_id'].toString();
          final correctId = verdicts[chosen] ?? 'right-1';
          return http.Response(
            jsonEncode({
              'ok': true,
              'xp_awarded': chosen == correctId ? 5 : 1,
              'correct': chosen == correctId,
              'correct_answer_id': chosen == correctId ? chosen : correctId,
              'explanation': 'sun starts with /s/.',
              'chosen_feedback': chosen == correctId ? null : 'Listen again!',
              'daily_tasks_completed': [],
              'achievements_earned': [],
            }),
            200,
          );
        }
        if (path.endsWith('/complete')) {
          return http.Response('{"ok":true,"stars":2,"xp_awarded":14}', 200);
        }
        if (path.endsWith('/abandon')) {
          return http.Response('{"ok":true}', 200);
        }
        return http.Response('{}', 404);
      });
}

ApiClient _api(_Server server) => ApiClient(
      config: const AppConfig(
        flavor: AppFlavor.dev,
        apiBaseUrl: 'http://backend.test/api/v1',
        billingCurrency: 'USD',
        backendMode: BackendMode.live,
      ),
      httpClient: server.client,
    );

void main() {
  late _Server server;
  late LiveLessonService svc;

  setUp(() {
    server = _Server();
    svc = LiveLessonService(
      api: _api(server),
      learnerIdResolver: () => 'L1',
    );
  });

  test('session opens once and is reused for the run', () async {
    final sid = await svc.sessionFor('letter-s', 'uuid-lesson');
    expect(sid, 'S-9');
    final again = await svc.sessionFor('letter-s', 'uuid-lesson');
    expect(again, 'S-9');
    expect(
      server.calls.where((c) => c.path.endsWith('/learners/L1/sessions')),
      hasLength(1),
    );
    expect(server.calls.first.json!['ref_id'], 'uuid-lesson');
  });

  test('grade returns the server verdict and reveal index comes from ids',
      () async {
    await svc.sessionFor('letter-s', 'uuid-lesson');
    server.verdicts['wrong-A'] = 'right-B';
    final v = await svc.grade(
      lessonCode: 'letter-s',
      questionId: 'q-1',
      answerId: 'wrong-A',
      phoneme: 's',
    );
    expect(v!.correct, isFalse);
    expect(v.correctAnswerId, 'right-B');
    expect(v.chosenFeedback, 'Listen again!');
    final event = server.calls.lastWhere((c) => c.path.endsWith('/events'));
    expect(event.json!['event_type'], 'question_answered');
    expect(event.json!['payload']['question_id'], 'q-1');
  });

  test('client_event_id is stable per (question, option) — dedupe-safe retry',
      () async {
    await svc.sessionFor('l', 'u');
    await svc.grade(lessonCode: 'l', questionId: 'q', answerId: 'a1');
    await svc.grade(lessonCode: 'l', questionId: 'q', answerId: 'a1');
    await svc.grade(lessonCode: 'l', questionId: 'q', answerId: 'a2');
    final ids = server.calls
        .where((c) => c.path.endsWith('/events'))
        .map((c) => c.json!['client_event_id'])
        .toList();
    expect(ids[0], ids[1]); // same answer → replay, no double XP
    expect(ids[0], isNot(ids[2])); // different answer → new attempt
  });

  test('markStep posts a step event with the stage name', () async {
    await svc.sessionFor('letter-s', 'u');
    await svc.markStep(lessonCode: 'letter-s', position: 3, stepType: 'see');
    final ev = server.calls.lastWhere((c) => c.path.endsWith('/events'));
    expect(ev.json!['event_type'], 'lesson_step_completed');
    expect(ev.json!['payload']['step'], 'see');
  });

  test('complete sends stars/accuracy/seconds and closes the session',
      () async {
    await svc.sessionFor('letter-s', 'u');
    final r = await svc.complete(
      lessonCode: 'letter-s',
      stars: 3,
      accuracy: 0.9,
      secondsSpent: 120,
      phonemes: const ['s'],
    );
    expect(r!.stars, 2); // the SERVER's stars win (engine rule)
    expect(r.xpAwarded, 14);
    final completeBody =
        server.calls.lastWhere((c) => c.path.endsWith('/complete')).json!;
    expect(completeBody['stars'], 3);
    expect(completeBody['accuracy'], 0.9);
    expect(completeBody['seconds_spent'], 120);
    expect(completeBody['phonemes'], ['s']);
    // session consumed: a second complete does nothing
    expect(await svc.complete(
      lessonCode: 'letter-s',
      stars: 3,
      accuracy: 0.9,
      secondsSpent: 1,
      phonemes: const [],
    ), isNull);
    // abandon after complete is a no-op (no fresh call)
    final before = server.calls.length;
    await svc.abandon('letter-s');
    expect(server.calls.length, before);
  });

  test('a dead server degrades quietly — never throws into the lesson',
      () async {
    server.fail = true;
    expect(await svc.sessionFor('l', 'u'), isNull);
    expect(
      await svc.grade(lessonCode: 'l', questionId: 'q', answerId: 'a'),
      isNull,
    );
    expect(
      await svc.complete(
        lessonCode: 'l',
        stars: 2,
        accuracy: 0.8,
        secondsSpent: 10,
        phonemes: const [],
      ),
      isNull,
    );
  });

  test('no bound learner id means the service stays silent', () async {
    final offlineSvc = LiveLessonService(
      api: _api(server),
      learnerIdResolver: () => null,
    );
    expect(offlineSvc.enabled, isFalse);
    expect(await offlineSvc.sessionFor('l', 'u'), isNull);
    expect(server.calls, isEmpty);
  });
}
