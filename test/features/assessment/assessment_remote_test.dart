import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:phonicsai/core/domain/reading_level.dart';
import 'package:phonicsai/core/env/app_config.dart';
import 'package:phonicsai/core/network/api_client.dart';
import 'package:phonicsai/core/result/result.dart';
import 'package:phonicsai/features/assessment/data/assessment_remote.dart';


Map<String, dynamic> _serverQuestions(int n) => {
      'result_id': 'R-1',
      'questions': [
        for (var i = 0; i < n; i++)
          {
            'id': 'q$i',
            'position': i,
            'kind': 'multiple_choice',
            'points': 1,
            'explanation': null,
            'prompt': {'text': 'Q$i?', 'skill': 'letter-sound'},
            'answers': [
              {'id': 'q$i-a0', 'position': 0, 'text': 'sun', 'feedback': null},
              {'id': 'q$i-a1', 'position': 1, 'text': 'bed', 'feedback': null},
            ],
          },
      ],
    };

void main() {
  late List<({String method, String path, String body})> calls;
  late Map<String, dynamic> submitResponse;

  ApiClient api() => ApiClient(
        config: const AppConfig(
          flavor: AppFlavor.dev,
          apiBaseUrl: 'http://backend.test/api/v1',
          billingCurrency: 'USD',
          backendMode: BackendMode.live,
        ),
        httpClient: MockClient((req) async {
          calls.add((
            method: req.method,
            path: req.url.path,
            body: req.body,
          ));
          final p = req.url.path;
          if (req.method == 'GET' && p.endsWith('/assessments')) {
            return http.Response(
                jsonEncode([
                  {'key': 'placement-english-v2', 'title': 'Placement'},
                ]),
                200);
          }
          if (p.endsWith('/start')) {
            return http.Response(jsonEncode(_serverQuestions(16)), 200);
          }
          if (p.endsWith('/submit')) {
            return http.Response(jsonEncode(submitResponse), 200);
          }
          return http.Response('{}', 404);
        }),
      );

  setUp(() {
    calls = [];
    submitResponse = {
      'id': 'R-1',
      'score': 14,
      'score_max': 16,
      'band_key': 'progressing',
      'completed_at': '2026-09-14T00:00:00Z',
      'per_question': [
        for (var i = 0; i < 16; i++)
          {'question_id': 'q$i', 'answer_id': 'q$i-a0', 'correct': i < 14},
      ],
    };
  });

  test('start maps the server set with no local answer key', () async {
    final remote = await AssessmentRemote.tryStart(
        api: api(), learnerId: 'L1');
    expect(remote, isNotNull);
    expect(remote!.questions, hasLength(16));
    expect(remote.questions.first.correctIndex, -1); // no on-the-spot reveal
    expect(remote.questions.first.options.map((o) => o.word), ['sun', 'bed']);
    expect(calls.first.path, endsWith('/assessments'));
    expect(calls.map((c) => c.path),
        contains('/api/v1/learners/L1/assessments/placement-english-v2/start'));
  });

  test('submit maps server score + band to a domain outcome', () async {
    final remote = await AssessmentRemote.tryStart(
        api: api(), learnerId: 'L1');
    final answers = List<int?>.filled(16, 0);
    final result = await remote!.submit(answers);
    expect(result.isOk, isTrue);
    final outcome = (result as Ok).value;
    expect(outcome.level, ReadingLevel.earlyDecoder); // 'progressing'
    expect(outcome.correctCount, 14);
    expect(outcome.total, 16);
    expect(outcome.confidence, closeTo(0.875, 1e-9));
    final body = jsonDecode(calls.last.body) as Map;
    expect((body['answers'] as List).length, 16);
    expect((body['answers'] as List).first['answer_id'], 'q0-a0');
  });

  test('no learner binding => caller stays on the local flow', () async {
    final remote = await AssessmentRemote.tryStart(api: api(), learnerId: null);
    expect(remote, isNull);
    expect(calls, isEmpty);
  });
}
