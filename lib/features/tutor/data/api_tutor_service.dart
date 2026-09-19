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
///  * SSE is not consumed here: the endpoint streams tokens for clients that
///    want them; the app takes the single JSON answer (`?sse=false`) and
///    feeds it through onToken as one increment. Streaming rendering is a
///    polish follow-up, not a correctness question.
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
    try {
      final json = await api.postJson(
        '/learners/$learnerId/tutor/reply?sse=false',
        body: {
          'message': message,
          'open_chat_allowed': context.openChatAllowed,
        },
      );
      final reply = _replyFromJson(json);
      onToken?.call(reply.text);
      return Result.ok(reply);
    } on AppFailure catch (failure) {
      return Result.fail(failure);
    } catch (error) {
      return Result.fail(
        AppFailure.unknown('The tutor answer could not be read: $error'),
      );
    }
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
