import '../../../core/result/result.dart';
import 'progress_models.dart';

/// Everything the app knows about one learner's learning, behind one door.
///
/// Reads are synchronous snapshots plus a change stream (the UI is driven by
/// the stream, never by polling); writes return [Result] so a failed save can
/// be shown instead of silently swallowed.
abstract interface class ProgressRepository {
  Future<void> warmUp(String profileId);

  Stream<ProfileSnapshot> watch(String profileId);

  ProfileSnapshot snapshot(String profileId);

  Future<Result<void>> completeStage({
    required String profileId,
    required String lessonId,
    required String stageId,
  });

  Future<Result<void>> finishLesson({
    required String profileId,
    required String lessonId,
    required int stars,
    required double accuracy,
    required int xp,
    required double secondsSpent,
    required List<String> phonemes,
  });

  Future<Result<void>> recordSoundReview({
    required String profileId,
    required String phoneme,
    required int grade,
  });

  Future<Result<void>> recordGameRound({
    required String profileId,
    required String gameId,
    required int score,
    required int stars,
    required double secondsSpent,
  });

  Future<Result<void>> addReadingMinutes({
    required String profileId,
    required int minutes,
  });

  Future<Result<void>> recordStageAnswer({
    required String profileId,
    required String stageKey,
    required bool isCorrect,
  });

  Future<Result<void>> reset(String profileId);
}

/// Aggregated, immutable view of a learner — the only thing screens read.
class ProfileSnapshot {
  const ProfileSnapshot({
    required this.profileId,
    this.lessons = const {},
    this.mastery = const {},
    this.sessions = const [],
    this.gameRecords = const {},
    this.starsEarned = 0,
  });

  factory ProfileSnapshot.empty(String profileId) =>
      ProfileSnapshot(profileId: profileId);

  final String profileId;
  final Map<String, LessonProgress> lessons;
  final Map<String, PhonemeMastery> mastery;
  final List<DaySession> sessions;
  final Map<String, GameRecord> gameRecords;
  final int starsEarned;

  LessonProgress lesson(String lessonId) =>
      lessons[lessonId] ?? LessonProgress(lessonId: lessonId, completedStages: const []);

  PhonemeMastery sound(String phoneme) =>
      mastery[phoneme] ?? PhonemeMastery(phoneme: phoneme);

  DaySession get today {
    final key = DaySession.keyFor(DateTime.now());
    return sessions.firstWhere(
      (s) => s.key == key,
      orElse: () => DaySession(date: DateTime.now()),
    );
  }

  DaySession sessionOn(DateTime day) {
    final key = DaySession.keyFor(day);
    return sessions.firstWhere(
      (s) => s.key == key,
      orElse: () => DaySession(date: day),
    );
  }

  int get lessonsCompleted =>
      lessons.values.where((l) => l.isComplete).length;

  int get starsTotal =>
      starsEarned + lessons.values.fold(0, (sum, l) => sum + l.stars);

  List<PhonemeMastery> get dueForReview {
    final due = mastery.values.where((m) => m.isDue).toList()
      ..sort((a, b) => a.accuracy.compareTo(b.accuracy));
    return List.unmodifiable(due);
  }

  int get minutesThisWeek {
    final weekStart = DateTime.now().subtract(
      Duration(days: DateTime.now().weekday - 1),
    );
    return sessions
        .where((s) => !s.date.isBefore(weekStart.subtract(const Duration(days: 0))))
        .fold<int>(0, (sum, s) => sum + s.minutes);
  }

  double get averageAccuracy {
    final values = lessons.values
        .where((l) => l.attempts > 0)
        .map((l) => l.bestAccuracy)
        .toList();
    if (values.isEmpty) return 0;
    return values.reduce((a, b) => a + b) / values.length;
  }
}
