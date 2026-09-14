import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../env/app_config.dart';
import '../error/failure.dart';
import 'auth_token_provider.dart';

/// The one HTTP door for the whole app.
///
/// Responsibilities: base-url joining, bearer token, timeouts, a single retry
/// for idempotent calls, status->AppFailure mapping and payload parsing.
/// Feature DTOs never see `http`.
class ApiClient {
  ApiClient({
    required this.config,
    required http.Client httpClient,
    AuthTokenProvider? tokenProvider,
    Duration timeout = const Duration(seconds: 20),
  }) : _http = httpClient,
       _tokens = tokenProvider ?? const NoAuthTokenProvider(),
       timeout2 = timeout;

  final AppConfig config;
  final http.Client _http;
  final AuthTokenProvider _tokens;
  final Duration timeout2;

  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, String>? query,
  }) =>
      _send('GET', path, query: query);

  Future<Map<String, dynamic>> postJson(
    String path, {
    Map<String, Object?>? body,
  }) =>
      _send('POST', path, body: body);

  Future<Map<String, dynamic>> patchJson(
    String path, {
    Map<String, Object?>? body,
  }) =>
      _send('PATCH', path, body: body);

  Future<Map<String, dynamic>> deleteJson(String path) =>
      _send('DELETE', path);

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, Object?>? body,
  }) async {
    if (!config.hasBackend) {
      throw const ApiNotConfiguredFailure();
    }
    final uri = Uri.parse('${config.apiBaseUrl}$path')
        .replace(queryParameters: query?.isNotEmpty == true ? query : null);
    var attempt = 0;
    while (true) {
      attempt++;
      try {
        final request = http.Request(method, uri)
          ..headers.addAll(await _headers())
          ..body = body == null ? '' : jsonEncode(body);
        if (body != null) {
          request.headers['Content-Type'] = 'application/json';
        }
        final streamed = await _http
            .send(request)
            .timeout(timeout2)
            .then(http.Response.fromStream);
        return _decode(streamed);
      } on TimeoutException {
        if (attempt == 1) continue;
        throw const AppFailure(
          kind: FailureKind.timeout,
          message: 'The tutor is taking too long to answer.',
          detail: 'request timed out',
        );
      } on AppFailure {
        rethrow;
      } on http.ClientException catch (e) {
        if (attempt == 1) continue;
        throw AppFailure(
          kind: FailureKind.offline,
          message: 'No connection right now.',
          detail: e.message,
        );
      } on FormatException catch (e) {
        throw AppFailure(
          kind: FailureKind.parse,
          message: 'The response could not be read.',
          detail: e.message,
          recoverable: false,
        );
      }
    }
  }

  Future<Map<String, String>> _headers() async {
    final token = _tokens.accessToken;
    return {
      'Accept': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  Map<String, dynamic> _decode(http.Response response) {
    final status = response.statusCode;
    if (status >= 200 && status < 300) {
      if (response.body.isEmpty) return const {};
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) return decoded;
      return const {'data': null};
    }
    throw _mapStatus(status, response.body);
  }

  AppFailure _mapStatus(int status, String body) {
    final serverMessage = _safeServerMessage(body);
    final kind = switch (status) {
      401 => FailureKind.unauthorized,
      403 => FailureKind.forbidden,
      404 => FailureKind.notFound,
      409 => FailureKind.conflict,
      429 => FailureKind.rateLimited,
      >= 500 => FailureKind.unknown,
      _ => FailureKind.unknown,
    };
    return AppFailure(
      kind: kind,
      message: switch (kind) {
        FailureKind.unauthorized => 'Please sign in again.',
        FailureKind.forbidden => 'That is not available on this plan.',
        FailureKind.rateLimited => 'A few too many requests — try again soon.',
        FailureKind.notFound => 'We could not find that.',
        FailureKind.unknown when status >= 500 =>
          'Our servers are having a moment.',
        _ => 'That did not work.',
      },
      detail: serverMessage ?? 'HTTP $status',
    );
  }

  String? _safeServerMessage(String body) {
    if (body.isEmpty) return null;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['message'] is String) {
        return decoded['message'] as String;
      }
    } on FormatException {
      return null;
    }
    return null;
  }
}

class ApiNotConfiguredFailure extends AppFailure {
  const ApiNotConfiguredFailure()
    : super(
        kind: FailureKind.offline,
        message: 'PhonicsAI is running on this device only right now.',
        detail: 'AppConfig.apiBaseUrl is empty (mock mode)',
      );
}

/// Streams a response body so the AI tutor can show tokens as they arrive.
class ApiSseStream {
  const ApiSseStream(this.config, this._http, this._tokens);

  final AppConfig config;
  final http.Client _http;
  final AuthTokenProvider _tokens;

  /// Emits `data:` payload strings. Completes on `[DONE]` or stream end.
  Stream<String> lines(String path, {Map<String, Object?>? body}) async* {
    if (!config.hasBackend) throw const ApiNotConfiguredFailure();
    final request = http.Request('POST', Uri.parse('${config.apiBaseUrl}$path'))
      ..headers.addAll({
        'Accept': 'text/event-stream',
        'Content-Type': 'application/json',
        if (_tokens.accessToken case final token? when token.isNotEmpty)
          'Authorization': 'Bearer $token',
      })
      ..body = jsonEncode(body ?? const {});
    final response = await _http.send(request);
    if (response.statusCode >= 400) {
      throw AppFailure(
        kind: FailureKind.unknown,
        message: 'The tutor could not answer that.',
        detail: 'HTTP ${response.statusCode}',
      );
    }
    final buffer = <int>[];
    await for (final chunk in response.stream) {
      buffer.addAll(chunk);
      while (buffer.contains(10)) {
        final index = buffer.indexOf(10);
        final line = utf8.decode(buffer.sublist(0, index), allowMalformed: true)
            .trimRight();
        buffer.removeRange(0, index + 1);
        if (line.startsWith('data:')) {
          final payload = line.substring(5).trim();
          if (payload == '[DONE]') return;
          if (payload.isNotEmpty) yield payload;
        }
      }
    }
  }
}
