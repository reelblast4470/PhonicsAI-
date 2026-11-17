import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:phonicsai/core/env/app_config.dart';
import 'package:phonicsai/core/error/failure.dart';
import 'package:phonicsai/core/network/api_client.dart';
import 'package:phonicsai/features/tutor/data/api_tutor_service.dart';
import 'package:phonicsai/features/tutor/domain/tutor_models.dart';
import 'package:phonicsai/features/tutor/domain/tutor_service.dart';

/// Wire format emitted by `api/app/routers/tutor.py` for `?sse=true`:
/// one `token` event per chunk, then a single `final` event with the reply.
String _sse(List<String> chunks, Map<String, dynamic> finalReply) {
  final buffer = StringBuffer();
  for (final chunk in chunks) {
    buffer.write('event: token\ndata: ${jsonEncode({'text': chunk})}\n\n');
  }
  buffer.write('event: final\ndata: ${jsonEncode(finalReply)}\n\n');
  return buffer.toString();
}

const _context = TutorContext(
  learnerName: 'Iris',
  ageYears: 6,
  levelLabel: 'Sounds & symbols',
  recentPhonemes: ['s'],
  strugglingPhonemes: ['sh'],
);

ApiTutorService _service(http.Client client) => ApiTutorService(
      api: ApiClient(
        config: const AppConfig(
          flavor: AppFlavor.dev,
          apiBaseUrl: 'http://backend.test/api/v1',
          billingCurrency: 'USD',
          backendMode: BackendMode.live,
        ),
        httpClient: client,
      ),
      learnerId: 'learner-1',
    );

void main() {
  test('token events build cumulative partial text; the final reply wins',
      () async {
    final service = _service(MockClient((req) async {
      return http.Response(
        _sse(['Let us ', 'blend.'], {
          'text': 'Let us blend.',
          'chips': ['Again'],
          'action': {
            'kind': 'openPronunciation',
            'target': 's',
            'label': 'Practise this sound',
          },
          'flagged': false,
        }),
        200,
        headers: {'content-type': 'text/event-stream'},
      );
    }));

    final partials = <String>[];
    final result = await service.reply(
      message: 'how do I blend?',
      context: _context,
      onToken: partials.add,
    );

    expect(partials, ['Let us ', 'Let us blend.']);
    final reply = result.requireValue;
    expect(reply.text, 'Let us blend.');
    expect(reply.chips, ['Again']);
    expect(reply.action?.kind, TutorActionKind.openPronunciation);
    expect(reply.flagged, isFalse);
  });

  test('streams from ?sse=true and sends only the question and parent flag',
      () async {
    late Uri url;
    late Map<String, dynamic> sentBody;
    final service = _service(MockClient((req) async {
      url = req.url;
      sentBody = jsonDecode(req.body) as Map<String, dynamic>;
      return http.Response(
        _sse([], {'text': 'Hi!', 'chips': <String>[], 'flagged': false}),
        200,
        headers: {'content-type': 'text/event-stream'},
      );
    }));

    final result = await service.reply(
      message: 'hello',
      context: _context,
      onToken: (_) {},
    );

    expect(result.isOk, isTrue);
    expect(url.path, '/api/v1/learners/learner-1/tutor/reply');
    expect(url.queryParameters['sse'], 'true');
    expect(sentBody.keys.toSet(), {'message', 'open_chat_allowed'});
    expect(sentBody['message'], 'hello');
  });

  test('without onToken the JSON endpoint is used instead', () async {
    late Uri url;
    final service = _service(MockClient((req) async {
      url = req.url;
      return http.Response(
        jsonEncode({'text': 'Sure.', 'chips': <String>[], 'flagged': false}),
        200,
        headers: {'content-type': 'application/json'},
      );
    }));

    final result = await service.reply(message: 'hi', context: _context);

    expect(url.queryParameters['sse'], 'false');
    expect(result.requireValue.text, 'Sure.');
  });

  test('a quota refusal before streaming is a rate-limit failure', () async {
    final service = _service(MockClient((req) async {
      return http.Response(
        jsonEncode({
          'error': {
            'code': 'tutor_quota_exceeded',
            'message': "You've used today's free tutor questions.",
          },
        }),
        429,
        headers: {'content-type': 'application/json'},
      );
    }));

    final result = await service.reply(
      message: 'one more',
      context: _context,
      onToken: (_) {},
    );

    expect(result.isOk, isFalse);
    expect(result.failureOrNull?.kind, FailureKind.rateLimited);
  });

  test('a stream that ends without a final event fails honestly', () async {
    final partials = <String>[];
    final service = _service(MockClient((req) async {
      return http.Response(
        'event: token\ndata: ${jsonEncode({'text': 'Hel'})}\n\n',
        200,
        headers: {'content-type': 'text/event-stream'},
      );
    }));

    final result = await service.reply(
      message: 'hi',
      context: _context,
      onToken: partials.add,
    );

    expect(partials, ['Hel']);
    expect(result.isOk, isFalse);
    expect(result.failureOrNull?.kind, FailureKind.unknown);
  });

  test('the complete final text replaces a partial stream', () async {
    final service = _service(MockClient((req) async {
      return http.Response(
        _sse(['Hel'], {'text': 'Hello', 'chips': <String>[], 'flagged': false}),
        200,
        headers: {'content-type': 'text/event-stream'},
      );
    }));

    final partials = <String>[];
    final result = await service.reply(
      message: 'hi',
      context: _context,
      onToken: partials.add,
    );

    expect(partials, ['Hel', 'Hello']);
    expect(result.requireValue.text, 'Hello');
  });
}
