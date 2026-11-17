import 'dart:convert';

import '../../../core/error/failure.dart';
import '../../../core/network/api_client.dart';
import '../../../core/result/result.dart';
import '../domain/tutor_models.dart';
import '../domain/tutor_service.dart';

/// Live tutor adapter — talks ONLY to our own backend
/// (`/learners/{id}/tutor/reply`), never to a model provider.
///
/// Deliberate omissions, both tested on the server:
///  * no learner context is sent. Names, age, level and struggling sounds are
///    derived server-side from the learner binding; the child's message is
///    the only content that leaves the device. (TutorContext contributes the
///    parent-gate openChatAllowed switch and nothing else.)
///  * When the caller wants tokens (`onToken`), the answer is read as SSE from
///    `?sse=true`: each `token` event extends the partial text, and the
///    `final` event carries the complete reply (chips, action, flag). Without
///    `onToken` the single JSON answer (`?sse=false`) is used.
class ApiTutorService implements TutorService {
  const ApiTutorService({required this.api, required this.learnerId});

  final ApiClient api;
  final String learnerId;

  @override
  Future<Result<TutorReply>> reply({
    required String message,
    required TutorContext context,
    void Function(String partial)? onToken,
  }) async {
    final body = <String, Object?>{
      'message': message,
      'open_chat_allowed': context.openChatAllowed,
    };
    if (onToken != null) {
      return _streamReply(body, onToken);
    }
    try {
      final json = await api.postJson(
        '/learners/$learnerId/tutor/reply?sse=false',
        body: body,
      );
      return Result.ok(_replyFromJson(json));
    } on AppFailure catch (failure) {
      return Result.fail(failure);
    } catch (error) {
      return Result.fail(
        AppFailure.unknown('The tutor answer could not be read: $error'),
      );
    }
  }

  Future<Result<TutorReply>> _streamReply(
    Map<String, Object?> body,
    void Function(String partial) onToken,
  ) async {
    final streamed = StringBuffer();
    TutorReply? finalReply;
    try {
      await for (final event in api.postEvents(
        '/learners/$learnerId/tutor/reply?sse=true',
        body: body,
      )) {
        if (event.event == 'token') {
          final chunk = _object(event.data)['text']?.toString() ?? '';
          streamed.write(chunk);
          onToken(streamed.toString());
        } else if (event.event == 'final') {
          finalReply = _replyFromJson(_object(event.data));
        }
      }
    } on AppFailure catch (failure) {
      return Result.fail(failure);
    } catch (error) {
      return Result.fail(
        AppFailure.unknown('The tutor answer could not be read: $error'),
      );
    }
    final reply = finalReply;
    if (reply == null) {
      return const Result.fail(
        AppFailure(
          kind: FailureKind.unknown,
          message: 'The tutor answer was cut short. Please try again.',
          detail: 'stream ended without a final event',
        ),
      );
    }
    // The final text is authoritative: make sure the UI shows exactly it.
    if (reply.text != streamed.toString()) onToken(reply.text);
    return Result.ok(reply);
  }

  static Map<String, dynamic> _object(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) return decoded;
    throw const FormatException('expected a JSON object');
  }

  @override
  Future<Result<List<String>>> suggestedStarters(TutorContext context) async {
    try {
      final json = await api.getJson('/learners/$learnerId/tutor/starters');
      return Result.ok([
        for (final s in (json['starters'] as List? ?? const [])) s.toString(),
      ]);
    } on AppFailure catch (failure) {
      return Result.fail(failure);
    }
  }

  static TutorReply _replyFromJson(Map<String, dynamic> json) {
    final raw = json['action'];
    TutorAction? action;
    if (raw is Map) {
      final kind = TutorActionKind.values.firstWhere(
        (k) => k.name == raw['kind'],
        orElse: () => TutorActionKind.none,
      );
      if (kind != TutorActionKind.none) {
        action = TutorAction(
          kind: kind,
          target: raw['target']?.toString() ?? '',
          label: raw['label']?.toString(),
        );
      }
    }
    return TutorReply(
      text: json['text'] as String? ?? '',
      chips: [
        for (final c in (json['chips'] as List? ?? const [])) c.toString(),
      ],
      action: action,
      flagged: json['flagged'] as bool? ?? false,
    );
  }
}
