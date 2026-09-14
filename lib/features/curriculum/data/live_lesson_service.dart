import 'dart:async';

import '../../../core/error/failure.dart';
import '../../../core/network/api_client.dart';

/// The server verdict for one question tap (Phase 3: the backend decides
/// correctness; the client only *reveals* it afterwards).
class LessonVerdict {
  const LessonVerdict({
    required this.correct,
    this.correctAnswerId,
    this.explanation,
    this.chosenFeedback,
    this.xpAwarded = 0,
  });

  final bool correct;
  final String? correctAnswerId;
  final String? explanation;
  final String? chosenFeedback;
  final int xpAwarded;
}

class LessonRunResult {
  const LessonRunResult({required this.stars, required this.xpAwarded});
  final int stars;
  final int xpAwarded;
}

/// Owns the live half of a lesson run: one learning session per lesson,
/// server-graded question events, step events and the completion call.
///
/// Failure policy (kid-first): every call is best-effort. The local-first
/// repository already persisted the child's progress; a dead backend must
/// never block or fail a lesson. Unavailable grading falls back to whatever
/// key the client has (static content), or "unanswered" for remote items —
/// and the durable [BackendProgressSync] queue still mirrors the finish.
String _dedupeId(String raw) {
  // 8..64 chars per the API contract; hash keeps short ids legal.
  final base = raw.length >= 8 ? raw : '$raw-hash';
  return base.length <= 64 ? base : base.substring(0, 64);
}

class LiveLessonService {
  LiveLessonService({required this._api, required this.learnerIdResolver});

  final ApiClient _api;

  /// Resolves the active profile's backend learner id at call time (bindings
  /// can appear after start-up, e.g. right after a profile is created).
  final String? Function() learnerIdResolver;

  final Map<String, String> _sessionByLesson = {};
  final Map<String, Future<String?>> _starting = {};

  bool get enabled => learnerIdResolver() != null;

  Future<String?> sessionFor(String lessonCode, String lessonUuid) {
    final existing = _sessionByLesson[lessonCode];
    if (existing != null) return Future.value(existing);
    return _starting.putIfAbsent(lessonCode, () async {
      final lid = learnerIdResolver();
      if (lid == null) return null;
      try {
        final res = await _api.postJson('/learners/$lid/sessions',
            body: {'kind': 'lesson', 'ref_id': lessonUuid});
        final sid = res['id']?.toString();
        if (sid != null) _sessionByLesson[lessonCode] = sid;
        return sid;
      } on AppFailure {
        return null;
      } finally {
        unawaited(_starting.remove(lessonCode));
      }
    });
  }

  /// Question grading round-trip. `answerId` is what the child picked; the
  /// server compares against its own key and returns the verdict + feedback.
  Future<LessonVerdict?> grade({
    required String lessonCode,
    required String questionId,
    required String answerId,
    String? phoneme,
  }) async {
    final lid = learnerIdResolver();
    final sid = _sessionByLesson[lessonCode];
    if (sid == null || lid == null) return null;
    try {
      final res = await _api.postJson(
        '/learners/$lid/sessions/$sid/events',
        body: {
          'event_type': 'question_answered',
          'payload': {
            'question_id': questionId,
            'answer_id': answerId,
            'phoneme': ?phoneme,
          },
          // stable per (question, option) so a retry cannot double-count,
          // while a *changed* answer is a new attempt.
          'client_event_id': _dedupeId(
            'g-$lessonCode-$questionId-${answerId.hashCode}',
          ),
        },
      );
      if (res['correct'] == null) return null;
      return LessonVerdict(
        correct: res['correct'] == true,
        correctAnswerId: res['correct_answer_id']?.toString(),
        explanation: res['explanation']?.toString(),
        chosenFeedback: res['chosen_feedback']?.toString(),
        xpAwarded: (res['xp_awarded'] as num?)?.toInt() ?? 0,
      );
    } on AppFailure {
      return null;
    }
  }

  Future<void> markStep({
    required String lessonCode,
    required int position,
    required String stepType,
  }) async {
    final sid = _sessionByLesson[lessonCode];
    if (sid == null) return;
    final lid = learnerIdResolver();
    if (lid == null) return;
    try {
      await _api.postJson(
        '/learners/$lid/sessions/$sid/events',
        body: {
          'event_type': 'lesson_step_completed',
          'payload': {'step': stepType, 'position': position},
          'client_event_id': _dedupeId('s-$lessonCode-$position'),
        },
      );
    } on AppFailure {
      // step events are the cheapest to lose; the completion still grades
    }
  }

  Future<LessonRunResult?> complete({
    required String lessonCode,
    required int stars,
    required double accuracy,
    required int secondsSpent,
    required List<String> phonemes,
  }) async {
    final sid = _sessionByLesson.remove(lessonCode);
    if (sid == null) return null;
    final lid = learnerIdResolver();
    if (lid == null) return null;
    try {
      final res = await _api.postJson(
        '/learners/$lid/sessions/$sid/complete',
        body: {
          'stars': stars,
          'accuracy': accuracy,
          'seconds_spent': secondsSpent,
          'phonemes': phonemes,
        },
      );
      return LessonRunResult(
        stars: (res['stars'] as num?)?.toInt() ?? stars,
        xpAwarded: (res['xp_awarded'] as num?)?.toInt() ?? 0,
      );
    } on AppFailure {
      return null;
    }
  }

  Future<void> abandon(String lessonCode) async {
    final sid = _sessionByLesson.remove(lessonCode);
    if (sid == null) return;
    final lid = learnerIdResolver();
    if (lid == null) return;
    try {
      await _api.postJson('/learners/$lid/sessions/$sid/abandon');
    } on AppFailure {
      // ignore
    }
  }
}
