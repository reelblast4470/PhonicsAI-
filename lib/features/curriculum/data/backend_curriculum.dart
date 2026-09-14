import '../../../core/domain/reading_level.dart';
import '../domain/lesson.dart';
import '../domain/phoneme.dart';

/// Maps the backend `GET /content/curriculum` payload into the app's domain
/// objects. Pure function — no I/O — so it is unit-testable against fixtures
/// and the shape stays honest to the API (see `api/app/routers/content.py`).
///
/// Identity rules:
///  * lesson ids are the stable curriculum *codes* (`letter-s`, `family-at`),
///    so local progress rows keep the same key across refreshes;
///  * `remoteId` carries the backend UUID used to open sessions;
///  * question options never contain the answer key: `correctIndex` stays
///    null and correctness is decided server-side per tap (Phase 3 rule).
class BackendCurriculum {
  BackendCurriculum(this.units, this.lessonUuids, this.stepUuids, this.version);

  final List<CurriculumUnit> units;

  /// code -> lesson UUID
  final Map<String, String> lessonUuids;

  /// "lessonCode:stepPosition" -> lesson_step UUID (for step events)
  final Map<String, String> stepUuids;
  final String? version;

  static BackendCurriculum fromJson(Map<String, dynamic> json) {
    final units = <CurriculumUnit>[];
    final lessonUuids = <String, String>{};
    final stepUuids = <String, String>{};
    for (final course in (json['courses'] as List? ?? const [])) {
      final modules = (course['modules'] as List? ?? const [])
          .cast<Map<String, dynamic>>();
      for (final m in modules) {
        final position = (m['position'] as num).toInt();
        final moduleLessons = (m['lessons'] as List? ?? const [])
            .cast<Map<String, dynamic>>();
        final lessons = <PhonicsLesson>[];
        final phonemes = <Phoneme>[];
        for (final l in moduleLessons) {
          final code = l['code']?.toString() ?? l['id'].toString();
          lessonUuids[code] = l['id'].toString();
          final steps = (l['steps'] as List? ?? const [])
              .cast<Map<String, dynamic>>();
          final stages = <LessonStage>[];
          final taught = <String>{};
          for (final st in steps) {
            final pos = (st['position'] as num).toInt();
            stepUuids['$code:$pos'] = st['id'].toString();
            final kind = _stageKind(st['step_type'].toString());
            final payload = (st['payload'] as Map? ?? const {})
                .cast<String, dynamic>();
            final questions = (st['questions'] as List? ?? const [])
                .cast<Map<String, dynamic>>();
            final items = <StageItem>[];
            if (questions.isNotEmpty) {
              items.addAll([
                for (final q in questions)
                  _choiceItem(code, st['position'], q),
              ]);
            }
            final builder = payload['builder'];
            if (builder is Map && builder['letters'] != null) {
              items.add(StageItem(
                id: '$code:$pos:build',
                prompt: 'Build the word',
                letters: (builder['letters'] as List).cast<String>(),
                targetWord: builder['word']?.toString(),
              ));
            }
            if (items.isEmpty) {
              final text = _stepText(kind, payload);
              if (text != null) {
                items.add(StageItem(
                  id: '$code:$pos:text',
                  prompt: kind == StageKind.discover
                      ? text.prompt
                      : kind == StageKind.read
                          ? 'Read it out loud'
                          : _shortPrompt(kind),
                  emoji: payload['emoji']?.toString(),
                  text: text.body,
                  audioText: payload['tts']?.toString(),
                  targetWord: payload['word']?.toString() ??
                      payload['target']?.toString(),
                ));
              }
            } else {
              // keep the step's friendly prompt on the first choice item
              final first = items.first;
              items[0] = StageItem(
                id: first.id,
                prompt: _promptFor(kind, payload, first.prompt),
                emoji: payload['emoji']?.toString(),
                options: first.options,
                optionIds: first.optionIds,
                remoteQuestionId: first.remoteQuestionId,
                audioText: payload['tts']?.toString(),
                letters: first.letters,
                targetWord: first.targetWord ??
                    payload['word']?.toString(),
              );
            }
            for (final p in [payload['phoneme'], payload['grapheme']]) {
              if (p is String && p.isNotEmpty) taught.add(p);
            }
            stages.add(LessonStage(
              kind: kind,
              items: items,
              introText: payload['tip']?.toString(),
              gameId: payload['game']?.toString(),
              wordId: payload['word']?.toString(),
            ));
          }
          final phonemeList = taught.toList();
          lessons.add(PhonicsLesson(
            id: code,
            unitId: m['id'].toString(),
            title: l['title'].toString(),
            subtitle: (l['summary'] ?? '').toString(),
            indexInUnit: (l['position'] as num).toInt(),
            stages: stages,
            phonemes: phonemeList.isEmpty ? const ['review'] : phonemeList,
            xp: (l['xp_reward'] as num?)?.toInt() ?? 20,
            remoteId: l['id'].toString(),
          ));
          for (final p in phonemeList) {
            phonemes.add(Phoneme(grapheme: p, ipa: p, words: const []));
          }
        }
        units.add(CurriculumUnit(
          id: 'mod-$position',
          title: m['title'].toString(),
          blurb: lessons.isEmpty
              ? 'Coming soon'
              : '${lessons.length} lessons, taught in order',
          level: _levelForModule(position),
          order: position,
          lessons: lessons,
          phonemes: phonemes,
        ));
      }
    }
    return BackendCurriculum(
      units, lessonUuids, stepUuids, json['version']?.toString());
  }

  static StageKind _stageKind(String type) => switch (type) {
        'discover' => StageKind.discover,
        'hear' => StageKind.hear,
        'see' => StageKind.see,
        'understand' => StageKind.understand,
        'practice' => StageKind.practice,
        'play' => StageKind.play,
        'recall' => StageKind.recall,
        'speak' => StageKind.speak,
        'read' => StageKind.read,
        _ => StageKind.review,
      };

  static ReadingLevel _levelForModule(int position) => position <= 5
      ? ReadingLevel.preReader
      : position == 6
          ? ReadingLevel.cvcBlender
          : position == 7
              ? ReadingLevel.cvcBlender
              : ReadingLevel.earlyDecoder;

  static String _shortPrompt(StageKind kind) => switch (kind) {
        StageKind.see => 'This is how it is written',
        StageKind.understand => 'Here is the trick',
        StageKind.speak => 'Say it out loud',
        StageKind.review => 'What we practised',
        _ => 'Look',
      };

  static String _promptFor(StageKind kind, Map<String, dynamic> payload, String fallback) =>
      switch (kind) {
        StageKind.discover =>
          payload['prompt']?.toString() ?? fallback,
        StageKind.hear => payload['tts'] != null
            ? 'Which one starts with the ${payload['tts']} sound?'
            : fallback,
        _ => fallback,
      };

  static _StepText? _stepText(StageKind kind, Map<String, dynamic> payload) {
    final body = payload['tip'] ?? payload['sentence'] ??
        payload['grapheme'] ?? payload['target'] ?? payload['prompt'];
    if (body == null) return null;
    return _StepText(
      prompt: kind == StageKind.discover
          ? (payload['prompt']?.toString() ?? 'What can you see?')
          : kind == StageKind.read
              ? (body.toString())
              : _shortPrompt(kind),
      body: kind == StageKind.read || kind == StageKind.see
          ? body.toString()
          : null,
    );
  }

  static StageItem _choiceItem(String code, dynamic stepPos,
      Map<String, dynamic> q) {
    final answers = (q['answers'] as List? ?? const [])
        .cast<Map<String, dynamic>>();
    answers.sort((a, b) =>
        (a['position'] as num).compareTo(b['position'] as num));
    return StageItem(
      id: '$code:$stepPos:q${q['position']}',
      prompt: (q['prompt'] as Map?)?['text']?.toString() ?? 'Choose one',
      // NOTE: correctIndex is deliberately null — the backend holds the key.
      options: [for (final a in answers) a['text'].toString()],
      optionIds: [for (final a in answers) a['id'].toString()],
      remoteQuestionId: q['id'].toString(),
    );
  }
}

class _StepText {
  const _StepText({required this.prompt, required this.body});
  final String prompt;
  final String? body;
}
