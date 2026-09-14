import 'package:flutter/foundation.dart';

import '../../../core/util/date_util.dart';
import '../../../core/util/math_util.dart';

/// One lesson's state for one learner.
@immutable
class LessonProgress {
  const LessonProgress({
    required this.lessonId,
    required this.completedStages,
    this.stars = 0,
    this.attempts = 0,
    this.bestAccuracy = 0,
    this.updatedAt,
  });

  final String lessonId;
  final List<String> completedStages;
  final int stars;
  final int attempts;
  final double bestAccuracy;
  final DateTime? updatedAt;

  bool isStageDone(String stageId) => completedStages.contains(stageId);
  int get doneCount => completedStages.length;
  double fractionOf(int totalStages) =>
      totalStages <= 0 ? 0 : MathUtil.ratio(doneCount, totalStages);
  bool get isComplete => started && fractionOf(10) >= 1;
  bool get started => completedStages.isNotEmpty || attempts > 0;

  LessonProgress withStage(String stageId) => completedStages.contains(stageId)
      ? this
      : LessonProgress(
          lessonId: lessonId,
          completedStages: [...completedStages, stageId],
          stars: stars,
          attempts: attempts,
          bestAccuracy: bestAccuracy,
          updatedAt: DateTime.now(),
        );

  Map<String, dynamic> toJson() => {
        'lesson_id': lessonId,
        'stages': completedStages,
        'stars': stars,
        'attempts': attempts,
        'accuracy': bestAccuracy,
        'updated_at': updatedAt?.toIso8601String(),
      };

  factory LessonProgress.fromJson(Map<String, dynamic> json) => LessonProgress(
        lessonId: json['lesson_id'] as String,
        completedStages: [
          for (final item in (json['stages'] as List? ?? const [])) item as String,
        ],
        stars: (json['stars'] as num?)?.toInt() ?? 0,
        attempts: (json['attempts'] as num?)?.toInt() ?? 0,
        bestAccuracy: (json['accuracy'] as num?)?.toDouble() ?? 0,
        updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? ''),
      );
}

enum MasteryStatus { fresh, learning, secure, mastered }

/// Per-sound mastery. `intervalDays`/`ease` drive the review queue, so a sound
/// that keeps going wrong comes back tomorrow and one that is nailed comes back
/// in three weeks.
@immutable
class PhonemeMastery {
  const PhonemeMastery({
    required this.phoneme,
    this.status = MasteryStatus.fresh,
    this.reps = 0,
    this.correct = 0,
    this.lapses = 0,
    this.ease = 2.5,
    this.intervalDays = 0,
    this.dueAt,
    this.lastSeenAt,
  });

  final String phoneme;
  final MasteryStatus status;
  final int reps;
  final int correct;
  final int lapses;
  final double ease;
  final double intervalDays;
  final DateTime? dueAt;
  final DateTime? lastSeenAt;

  double get accuracy => MathUtil.ratio(correct, reps);
  bool get isDue =>
      dueAt == null || !DateTime.now().isBefore(DateUtil.startOfDay(dueAt!));

  PhonemeMastery copyWith({
    MasteryStatus? status,
    int? reps,
    int? correct,
    int? lapses,
    double? ease,
    double? intervalDays,
    DateTime? dueAt,
    DateTime? lastSeenAt,
  }) {
    return PhonemeMastery(
      phoneme: phoneme,
      status: status ?? this.status,
      reps: reps ?? this.reps,
      correct: correct ?? this.correct,
      lapses: lapses ?? this.lapses,
      ease: ease ?? this.ease,
      intervalDays: intervalDays ?? this.intervalDays,
      dueAt: dueAt ?? this.dueAt,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'phoneme': phoneme,
        'status': status.name,
        'reps': reps,
        'correct': correct,
        'lapses': lapses,
        'ease': ease,
        'interval': intervalDays,
        'due_at': dueAt?.toIso8601String(),
        'last_seen': lastSeenAt?.toIso8601String(),
      };

  factory PhonemeMastery.fromJson(Map<String, dynamic> json) => PhonemeMastery(
        phoneme: json['phoneme'] as String,
        status: MasteryStatus.values.firstWhere(
          (s) => s.name == json['status'],
          orElse: () => MasteryStatus.fresh,
        ),
        reps: (json['reps'] as num?)?.toInt() ?? 0,
        correct: (json['correct'] as num?)?.toInt() ?? 0,
        lapses: (json['lapses'] as num?)?.toInt() ?? 0,
        ease: (json['ease'] as num?)?.toDouble() ?? 2.5,
        intervalDays: (json['interval'] as num?)?.toDouble() ?? 0,
        dueAt: DateTime.tryParse(json['due_at'] as String? ?? ''),
        lastSeenAt: DateTime.tryParse(json['last_seen'] as String? ?? ''),
      );
}

/// One day of practice, aggregated for charts and the parent report.
@immutable
class DaySession {
  const DaySession({
    required this.date,
    this.seconds = 0,
    this.stars = 0,
    this.lessonsCompleted = 0,
    this.gamesPlayed = 0,
    this.minutesReadAloud = 0,
  });

  final DateTime date;
  final int seconds;
  final int stars;
  final int lessonsCompleted;
  final int gamesPlayed;
  final int minutesReadAloud;

  int get minutes => (seconds / 60).round();

  DaySession merge(DaySession other) => DaySession(
        date: date,
        seconds: seconds + other.seconds,
        stars: stars + other.stars,
        lessonsCompleted: lessonsCompleted + other.lessonsCompleted,
        gamesPlayed: gamesPlayed + other.gamesPlayed,
        minutesReadAloud: minutesReadAloud + other.minutesReadAloud,
      );

  static String keyFor(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';

  String get key => keyFor(date);

  Map<String, dynamic> toJson() => {
        'date': key,
        'seconds': seconds,
        'stars': stars,
        'lessons': lessonsCompleted,
        'games': gamesPlayed,
        'read_minutes': minutesReadAloud,
      };

  factory DaySession.fromJson(Map<String, dynamic> json) => DaySession(
        date: DateTime.tryParse(json['date'] as String? ?? '') ??
            DateUtil.startOfDay(DateTime.now()),
        seconds: (json['seconds'] as num?)?.toInt() ?? 0,
        stars: (json['stars'] as num?)?.toInt() ?? 0,
        lessonsCompleted: (json['lessons'] as num?)?.toInt() ?? 0,
        gamesPlayed: (json['games'] as num?)?.toInt() ?? 0,
        minutesReadAloud: (json['read_minutes'] as num?)?.toInt() ?? 0,
      );
}

/// A game's personal best, per learner.
@immutable
class GameRecord {
  const GameRecord({required this.gameId, this.bestScore = 0, this.plays = 0});

  final String gameId;
  final int bestScore;
  final int plays;

  GameRecord betterThan(GameRecord other) =>
      bestScore >= other.bestScore ? this : other;

  Map<String, dynamic> toJson() =>
      {'game_id': gameId, 'best': bestScore, 'plays': plays};

  factory GameRecord.fromJson(Map<String, dynamic> json) => GameRecord(
        gameId: json['game_id'] as String,
        bestScore: (json['best'] as num?)?.toInt() ?? 0,
        plays: (json['plays'] as num?)?.toInt() ?? 0,
      );
}
