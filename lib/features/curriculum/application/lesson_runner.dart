import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../progress/application/progress_providers.dart';
import '../../progress/domain/progress_repository.dart';
import '../data/live_lesson_service.dart';
import '../domain/lesson.dart';
import 'curriculum_providers.dart';

enum ItemOutcome { unanswered, correct, wrong }

/// State machine for one lesson attempt.
///
/// All ten stages run through this one class, so the stage widgets stay dumb
/// and the *rules* (what counts as done, how stars are awarded, when progress
/// is saved) are unit-testable without a single widget.
@immutable
class LessonRunState {
  const LessonRunState({
    required this.lesson,
    required this.stageIndex,
    required this.outcomes,
    required this.startedAt,
    this.isStageClosing = false,
    this.isFinished = false,
    this.isSaving = false,
    this.savedStars,
    this.buildAttempts = const {},
    this.errorMessage,
    this.revealedCorrectIndex = const {},
  });

  final PhonicsLesson lesson;
  final int stageIndex;

  /// itemId -> result, for the current attempt.
  final Map<String, ItemOutcome> outcomes;
  final DateTime startedAt;

  /// Short pause after the last item of a stage, before auto-advance.
  final bool isStageClosing;
  final bool isFinished;
  final bool isSaving;
  final int? savedStars;
  final Map<String, List<String>> buildAttempts;
  final String? errorMessage;

  /// itemId -> the correct option index, revealed by the SERVER after the
  /// answer was graded (remote-graded items have no local `correctIndex`).
  final Map<String, int> revealedCorrectIndex;

  LessonStage get stage => lesson.stages[stageIndex];
  bool get isLastStage => stageIndex == lesson.stageCount - 1;
  double get fraction => (stageIndex + (isFinished ? 1 : 0)) / lesson.stageCount;

  ItemOutcome outcomeOf(String itemId) =>
      outcomes[itemId] ?? ItemOutcome.unanswered;

  bool get stageItemsAllCorrect =>
      stage.items.isEmpty ||
      stage.items.every((item) => outcomeOf(item.id) == ItemOutcome.correct);

  int get correctCount =>
      outcomes.values.where((o) => o == ItemOutcome.correct).length;

  int get answeredCount =>
      outcomes.values.where((o) => o != ItemOutcome.unanswered).length;

  double get accuracy {
    final answered = answeredCount;
    if (answered == 0) return 1; // a walk-through with no misses is not a fail
    return correctCount / answered;
  }

  int get stars => switch (accuracy) {
    >= 0.85 => 3,
    >= 0.6 => 2,
    _ => 1,
  };

  LessonRunState copyWith({
    int? stageIndex,
    Map<String, ItemOutcome>? outcomes,
    bool? isStageClosing,
    bool? isFinished,
    bool? isSaving,
    int? savedStars,
    Map<String, List<String>>? buildAttempts,
    String? errorMessage,
    Map<String, int>? revealedCorrectIndex,
  }) {
    return LessonRunState(
      lesson: lesson,
      stageIndex: stageIndex ?? this.stageIndex,
      outcomes: outcomes ?? this.outcomes,
      startedAt: startedAt,
      isStageClosing: isStageClosing ?? this.isStageClosing,
      isFinished: isFinished ?? this.isFinished,
      isSaving: isSaving ?? this.isSaving,
      savedStars: savedStars ?? this.savedStars,
      buildAttempts: buildAttempts ?? this.buildAttempts,
      errorMessage: errorMessage,
    
      revealedCorrectIndex:
          revealedCorrectIndex ?? this.revealedCorrectIndex,);
  }
}

class LessonRunner extends FamilyNotifier<LessonRunState?, String> {
  /// Guards the one-way door: a finished lesson is written exactly once per
  /// run, so a double tap (or a "Next" that races the auto-advance) can never
  /// award stars or lessons twice.
  bool _completionPersisted = false;
  /// The lesson id arrives through `build` (Riverpod's family contract) and is
  /// kept in a field so every method reads like ordinary code.
  late final String lessonId;

  ProgressRepository get _progress =>
      ref.read(progressRepositoryProvider);
  String? get _profileId => ref.read(activeProfileIdProvider);

  /// Server-backed grading + sessions (Phase 3). Null in mock mode, so every
  /// existing test and offline path is untouched.
  LiveLessonService? get _live => ref.read(liveLessonServiceProvider);
  bool get _remoteRun =>
      _live != null && state?.lesson.remoteId != null && _live!.enabled;

  @override
  LessonRunState? build(String argument) {
    lessonId = argument;
    _completionPersisted = false;
    final lesson = ref.read(lessonByIdProvider)[lessonId];
    if (lesson == null) return null;
    final live = _live;
    if (lesson.remoteId != null && live?.enabled == true) {
      // Open the server-side learning session in the background; every live
      // call below degrades to local behaviour if it never lands.
      unawaited(live!.sessionFor(lessonId, lesson.remoteId!));
      // Capture the instance: providers are unreadable once the container
      // tears down mid-run (child closed the app, route popped, …).
      ref.onDispose(() => unawaited(live.abandon(lessonId)));
    }
    return LessonRunState(
      lesson: lesson,
      stageIndex: 0,
      outcomes: const {},
      startedAt: DateTime.now(),
    );
  }

  Future<void> answerChoice(String itemId, int optionIndex) async {
    final current = state;
    if (current == null || current.isStageClosing) return;
    final item = current.stage.items.firstWhere((i) => i.id == itemId);

    // ---- live path: the server holds the answer key and returns the verdict
    bool isCorrect;
    Map<String, int>? revealed;
    if (item.remoteQuestionId != null && _remoteRun) {
      final answerId = optionIndex < item.optionIds.length
          ? item.optionIds[optionIndex]
          : null;
      if (answerId == null) return;
      final verdict = await _live!.grade(
        lessonCode: lessonId,
        questionId: item.remoteQuestionId!,
        answerId: answerId,
        phoneme: _phonemeForItem(item),
      );
      if (verdict == null) {
        if (item.correctIndex == null) {
          // Remote question but server unreachable: leave the item unanswered
          // (we refuse to fake a grade) and let the stage advance by hand.
          state = current.copyWith(
            errorMessage:
                'Grading is offline — this answer will count when we are '
                'back online.',
          );
          return;
        }
        isCorrect = item.correctIndex == optionIndex;
      } else {
        isCorrect = verdict.correct;
        final correctId = verdict.correctAnswerId;
        if (correctId != null) {
          final idx = item.optionIds.indexOf(correctId);
          if (idx >= 0) revealed = {itemId: idx};
        }
      }
    } else {
      isCorrect = item.correctIndex == optionIndex;
    }

    final outcomes = {...current.outcomes, itemId: isCorrect ? ItemOutcome.correct : ItemOutcome.wrong};

    state = current.copyWith(outcomes: outcomes, revealedCorrectIndex: revealed);
    final profileId = _profileId;
    if (profileId != null) {
      unawaited(
        _progress.recordStageAnswer(
          profileId: profileId,
          stageKey: '${profileId}__${_phonemeForItem(item)}',
          isCorrect: isCorrect,
        ),
      );
    }
    if (_allItemsAnswered(isCorrectOnly: false)) {
      await _closeStage();
    }
  }

  /// Retrying a wrong item is allowed and encouraged: it clears the miss so a
  /// child is not punished for the first guess.
  Future<void> retryItem(String itemId) async {
    final current = state;
    if (current == null) return;
    final outcomes = {...current.outcomes}..remove(itemId);
    state = current.copyWith(outcomes: outcomes);
  }

  void toggleLetter(String itemId, String letter) {
    final current = state;
    if (current == null) return;
    final built = <String>[...(current.buildAttempts[itemId] ?? const <String>[])];
    if (built.contains(letter)) {
      built.remove(letter);
    } else {
      built.add(letter);
    }
    state = current.copyWith(
      buildAttempts: {...current.buildAttempts, itemId: built},
    );
  }

  Future<void> checkBuild(String itemId) async {
    final current = state;
    if (current == null) return;
    final item = current.stage.items.firstWhere((i) => i.id == itemId);
    final target = (item.targetWord ?? '').toUpperCase();
    final built = (current.buildAttempts[itemId] ?? const <String>[]).join();
    final isCorrect = built == target;
    state = current.copyWith(
      outcomes: {...current.outcomes, itemId: isCorrect ? ItemOutcome.correct : ItemOutcome.wrong},
    );
    if (isCorrect && _allItemsAnswered(isCorrectOnly: false)) {
      await _closeStage();
    }
  }

  Future<void> markItemCorrect(String itemId) async {
    final current = state;
    if (current == null) return;
    state = current.copyWith(
      outcomes: {...current.outcomes, itemId: ItemOutcome.correct},
    );
    if (_allItemsAnswered(isCorrectOnly: false)) await _closeStage();
  }

  Future<void> nextStage() => _closeStage(force: true);

  Future<void> _closeStage({bool force = false}) async {
    final current = state;
    if (current == null || current.isFinished) return;
    // A forced skip still records the stage: the learner saw it, and progress
    // that hides that would make the parent report wrong.
    final profileId = _profileId;
    if (profileId != null) {
      unawaited(
        _progress.completeStage(
          profileId: profileId,
          lessonId: lessonId,
          stageId: current.stage.kind.name,
        ),
      );
    }
    if (_remoteRun) {
      unawaited(_live!.markStep(
        lessonCode: lessonId,
        position: current.stageIndex + 1,
        stepType: current.stage.kind.name,
      ));
    }

    if (current.isLastStage) {
      await finish();
      return;
    }
    state = current.copyWith(
      stageIndex: current.stageIndex + 1,
      isStageClosing: false,
    );
  }

  Future<void> finish() async {
    final current = state;
    if (current == null) return;
    if (_completionPersisted) {
      // Already saved this run: make the call idempotent instead of rewarding
      // the same lesson twice.
      state = current.copyWith(isFinished: true, isSaving: false);
      return;
    }
    _completionPersisted = true;
    state = current.copyWith(isFinished: true, isSaving: true);

    final profileId = _profileId;
    if (profileId == null) {
      state = state!.copyWith(isSaving: false, errorMessage: 'no active learner');
      return;
    }
    final seconds = DateTime.now().difference(current.startedAt).inSeconds;

    // Live mode: the server is the authority on the recorded completion
    // (XP, stars, mastery, pointer advance, next recommendation). Local
    // progress below still runs first so the UI is never blocked on the net.
    int? serverStars;
    if (_remoteRun) {
      final server = await _live!.complete(
        lessonCode: lessonId,
        stars: current.stars,
        accuracy: current.accuracy,
        secondsSpent: seconds,
        phonemes: current.lesson.phonemes,
      );
      if (server != null) {
        serverStars = server.stars;
        state = state!.copyWith(savedStars: server.stars);
        ref.invalidate(liveRecommendationProvider);
      }
    }

    final result = await _progress.finishLesson(
      profileId: profileId,
      lessonId: lessonId,
      stars: current.stars,
      accuracy: current.accuracy,
      xp: current.lesson.xp * current.stars,
      secondsSpent: seconds.toDouble(),
      phonemes: current.lesson.phonemes,
    );
    state = result.fold(
      ok: (_) => current.copyWith(
        isFinished: true,
        isSaving: false,
        savedStars: serverStars ?? current.stars,
      ),
      fail: (failure) => current.copyWith(
        isFinished: true,
        isSaving: false,
        errorMessage: failure.message,
      ),
    );
  }

  bool _allItemsAnswered({required bool isCorrectOnly}) {
    final current = state;
    if (current == null) return false;
    final items = current.stage.items;
    if (items.isEmpty) return false;
    return items.every((item) {
      final outcome = current.outcomes[item.id];
      if (outcome == null) return false;
      return isCorrectOnly ? outcome == ItemOutcome.correct : true;
    });
  }

  String _phonemeForItem(StageItem item) {
    final text = '${item.text ?? ''}${item.prompt}';
    for (final phoneme in state?.lesson.phonemes ?? const <String>[]) {
      if (text.toLowerCase().contains(phoneme.replaceAll('_', ''))) {
        return phoneme;
      }
    }
    return state?.lesson.phonemes.firstOrNull ?? 'review';
  }
}

/// One runner per lesson id, so returning to a lesson mid-way is coherent and
/// so the tutor can pre-seed a lesson without a global singleton.
final lessonRunProvider =
    NotifierProvider.family<LessonRunner, LessonRunState?, String>(
  LessonRunner.new,
);
