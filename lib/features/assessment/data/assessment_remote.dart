import '../../../core/domain/reading_level.dart';
import '../../../core/error/failure.dart';
import '../../../core/network/api_client.dart';
import '../../../core/result/result.dart';
import '../../assessment/domain/assessment_content.dart';
import '../../assessment/domain/assessment_scoring.dart';
import '../../curriculum/data/phonics_program.dart';

/// Drives the placement check against the real API (Phase 3):
/// 1. `POST /learners/{id}/assessments/{key}/start` — the server hands out the
///    question set *without* the answer key (never serialized client-side);
/// 2. `POST …/results/{result_id}/submit` — the server scores, bands, sets
///    `reading_level_key` on the learner and returns per-item verdicts.
///
/// `correctIndex == -1` on remote questions means "no on-the-spot reveal":
/// the child sees their choice recorded; the outcome arrives at the end,
/// computed by the server.
class AssessmentRemote {
  AssessmentRemote({required this._api, required this.learnerId});

  final ApiClient _api;
  final String learnerId;

  String? resultId;
  String? assessmentKey;
  List<List<String>> _optionIds = const [];
  List<AssessmentQuestion> questions = const [];

  bool get isReady => resultId != null;

  /// null => caller stays on the local flow (mock mode, offline, no learner).
  static Future<AssessmentRemote?> tryStart({
    required ApiClient api,
    required String? learnerId,
  }) async {
    if (learnerId == null) return null;
    final remote = AssessmentRemote(api: api, learnerId: learnerId);
    return (await remote.start()) ? remote : null;
  }

  Future<bool> start() async {
    try {
      final list = await _api.getListJson('/assessments');
      if (list.isEmpty) return false;
      assessmentKey = list.first['key'].toString();
      final res = await _api.postJson(
        '/learners/$learnerId/assessments/$assessmentKey/start',
      );
      resultId = res['result_id']?.toString();
      if (resultId == null) return false;
      final qs = (res['questions'] as List? ?? const [])
          .cast<Map<String, dynamic>>();
      // The API returns items pre-ordered; sort only when positions are
      // present (older payloads omit them — order is then authoritative).
      if (qs.every((q) => q['position'] is num)) {
        qs.sort((a, b) => (a['position'] as num).compareTo(b['position'] as num));
      }
      final mapped = <AssessmentQuestion>[];
      final optionIds = <List<String>>[];
      for (var i = 0; i < qs.length; i++) {
        final q = qs[i];
        final answers = (q['answers'] as List? ?? const [])
            .cast<Map<String, dynamic>>();
        if (answers.every((a) => a['position'] is num)) {
          answers.sort((a, b) =>
              (a['position'] as num).compareTo(b['position'] as num));
        }
        optionIds.add([for (final a in answers) a['id'].toString()]);
        final words = [for (final a in answers) a['text'].toString()];
        mapped.add(AssessmentQuestion(
          id: q['id'].toString(),
          skill: _skillOf((q['prompt'] as Map?)?['skill']),
          spokenPrompt: (q['prompt'] as Map?)?['text']?.toString() ?? '',
          displayPrompt: (q['prompt'] as Map?)?['text']?.toString() ?? '',
          options: [
            for (final w in words)
              AssessmentOption(
                emoji: PhonicsProgram.emojiFor(w) ?? '🔤',
                word: w,
              ),
          ],
          correctIndex: -1, // server decides; no on-the-spot reveal
          targetsLevel: ReadingLevel.preReader,
        ));
      }
      questions = mapped;
      _optionIds = optionIds;
      return mapped.isNotEmpty;
    } on AppFailure {
      return false;
    }
  }

  static PhonicsSkill _skillOf(Object? tag) => switch (tag?.toString()) {
        'initial-sound' => PhonicsSkill.initialSound,
        'letter-sound' => PhonicsSkill.letterSound,
        'blending' => PhonicsSkill.blending,
        'rhyming' => PhonicsSkill.rhyming,
        'digraphs' || 'segmenting' => PhonicsSkill.digraphs,
        _ => PhonicsSkill.letterSound,
      };

  /// Submit and translate the server result into the app's outcome shape.
  Future<Result<AssessmentOutcome>> submit(List<int?> selected) async {
    if (resultId == null) {
      return const Result.fail(
        AppFailure(
          kind: FailureKind.validation,
          message: 'The check-up did not start.',
          detail: 'no result id',
        ),
      );
    }
    final payload = <Map<String, Object?>>[];
    for (var i = 0; i < questions.length; i++) {
      final choice = selected[i];
      if (choice == null) continue;
      payload.add({
        'question_id': questions[i].id,
        'answer_id': _optionIds[i][choice],
      });
    }
    try {
      final res = await _api.postJson(
        '/learners/$learnerId/assessments/results/$resultId/submit',
        body: {'answers': payload},
      );
      final score = (res['score'] as num?)?.toInt() ?? 0;
      final maxScore = (res['score_max'] as num?)?.toInt() ??
          questions.length;
      final band = res['band_key']?.toString();
      final perQuestion = (res['per_question'] as List? ?? const [])
          .cast<Map<String, dynamic>>();
      final correctById = <String, bool>{
        for (final p in perQuestion)
          p['question_id'].toString(): p['correct'] == true,
      };
      return Result.ok(
        AssessmentOutcome(
          level: levelForBand(band),
          results: [
            for (var i = 0; i < questions.length; i++)
              AssessmentResult(
                question: questions[i],
                selectedIndex: selected[i],
                isCorrect: correctById[questions[i].id] ?? false,
              ),
          ],
          confidence: maxScore == 0 ? 0 : score / maxScore,
          notes: [
            'Placed at ${levelForBand(band).label} from the school '
                'check ($score/$maxScore).',
          ],
        ),
      );
    } on AppFailure catch (f) {
      return Result.fail(f);
    }
  }

  static ReadingLevel levelForBand(String? band) => switch (band) {
        'pre-reader' => ReadingLevel.preReader,
        'emerging' => ReadingLevel.letterSounds,
        'beginning' => ReadingLevel.cvcBlender,
        'progressing' => ReadingLevel.earlyDecoder,
        'proficient' || 'fluent' => ReadingLevel.fluentReader,
        _ => ReadingLevel.letterSounds,
      };
}
