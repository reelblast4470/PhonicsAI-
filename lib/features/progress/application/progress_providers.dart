import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/infrastructure.dart';
import '../../../core/env/app_config.dart';
import '../../curriculum/domain/lesson.dart';
import '../../home/domain/daily_mission.dart';
import '../data/backend_progress_sync.dart';
import '../data/local_progress_repository.dart';
import '../domain/progress_models.dart';
import '../domain/progress_repository.dart';

/// Backend mirror: enabled for live *and* offlineFirst modes (a queue absorbs
/// downtime there), null in mock mode so nothing changes for tests/previews.
final backendProgressSyncProvider = Provider<BackendProgressSync?>((ref) {
  final config = ref.watch(appConfigProvider);
  if (config.backendMode == BackendMode.mock || !config.hasBackend) {
    return null;
  }
  final sync = BackendProgressSync(
    api: ref.watch(apiClientProvider),
    store: ref.watch(keyValueStoreProvider),
  );
  ref.onDispose(sync.dispose);
  return sync;
});

final progressRepositoryProvider = Provider<ProgressRepository>((ref) {
  final repository = LocalProgressRepository(
    store: ref.watch(keyValueStoreProvider),
    mirror: ref.watch(backendProgressSyncProvider),
  );
  ref.onDispose(repository.dispose);
  return repository;
});

/// The learner's live learning state. Screens read *only* this (plus the
/// curriculum), which is what keeps Home, Learn, Progress and the parent
/// dashboard showing identical numbers.
final profileProgressProvider = StreamProvider<ProfileSnapshot?>((ref) async* {
  final profileId = ref.watch(activeProfileIdProvider);
  if (profileId == null) {
    yield null;
    return;
  }
  final repository = ref.watch(progressRepositoryProvider);
  yield* repository.watch(profileId);
});

final activeProfileIdProvider = Provider<String?>((ref) {
  // Kept separate so progress does not depend on the profile feature's stream.
  final store = ref.watch(keyValueStoreProvider);
  return store.getString('phonicsai.active_profile');
});

/// Streak + today's counters, derived from the snapshot (pure, testable).
final streakProvider = Provider<int>((ref) {
  final snapshot = ref.watch(profileProgressProvider).valueOrNull;
  if (snapshot == null) return 0;
  return StreakCalculator.current(snapshot.sessions);
});

final dailyMissionProvider = Provider<DailyMission>((ref) {
  final snapshot = ref.watch(profileProgressProvider).valueOrNull;
  final lessons = snapshot?.lessons ?? const {};
  final today = snapshot?.today ?? DaySession(date: DateTime.now());
  final due = snapshot?.dueForReview.length ?? 0;
  final now = DateTime.now();

  return DailyMission.build(
    date: now,
    lessonsCompletedToday: today.lessonsCompleted,
    gamesPlayedToday: today.gamesPlayed,
    minutesReadAloudToday: today.minutesReadAloud,
    dueReviews: due,
    streakDays: snapshot == null
        ? 0
        : StreakCalculator.current(snapshot.sessions),
    isVeryNewLearner: lessons.isEmpty,
  );
});

/// Convenience selectors so widgets never recompute.
final minutesTodayProvider = Provider<int>((ref) {
  final snapshot = ref.watch(profileProgressProvider).valueOrNull;
  return snapshot?.today.minutes ?? 0;
});

final lessonsCompletedProvider = Provider<int>((ref) {
  final snapshot = ref.watch(profileProgressProvider).valueOrNull;
  return snapshot?.lessonsCompleted ?? 0;
});

/// The progress graph is a chain: curriculum knows the lesson, progress knows
/// how far through it the learner is.
extension LessonProgressX on ProfileSnapshot {
  double lessonFraction(PhonicsLesson item) =>
      lesson(item.id).fractionOf(item.stageCount);

  bool lessonIsComplete(PhonicsLesson item) =>
      lesson(item.id).isComplete || lessonFraction(item) >= 1;

  /// Where to press "Continue": first unfinished lesson in teaching order.
  PhonicsLesson? nextLesson(List<PhonicsLesson> ordered) {
    for (final item in ordered) {
      if (!lessonIsComplete(item)) return item;
    }
    return ordered.isEmpty ? null : ordered.last;
  }
}
