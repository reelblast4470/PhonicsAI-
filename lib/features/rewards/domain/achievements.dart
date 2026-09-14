import 'package:flutter/foundation.dart';

import '../../../core/util/date_util.dart';
import '../../progress/domain/progress_repository.dart';

enum AchievementKind {
  firstLesson,
  streak,
  stars,
  soundsMastered,
  readingMinutes,
  gamesPlayed,
  perfectLesson,
  braveSpeaker,
}

@immutable
class Achievement {
  const Achievement({
    required this.kind,
    required this.title,
    required this.description,
    required this.emoji,
    required this.target,
    this.rewardStars = 0,
  });

  final AchievementKind kind;
  final String title;
  final String description;
  final String emoji;

  /// Value at which it unlocks (0 = event-based, not count-based).
  final int target;
  final int rewardStars;
}

@immutable
class AchievementStatus {
  const AchievementStatus({
    required this.achievement,
    required this.progress,
    required this.unlocked,
    this.unlockedAt,
  });

  final Achievement achievement;
  final int progress;
  final bool unlocked;
  final DateTime? unlockedAt;

  double get fraction => achievement.target <= 0
      ? (unlocked ? 1 : 0)
      : (progress / achievement.target).clamp(0.0, 1.0);
}

/// The badge set. Rewards are earned only by *doing the thing* — every number
/// here comes from recorded progress, never from a timer or a purchase.
abstract final class Achievements {
  static const List<Achievement> catalog = [
    Achievement(
      kind: AchievementKind.firstLesson,
      title: 'First story',
      description: 'Finish one whole lesson',
      emoji: '🌱',
      target: 1,
      rewardStars: 5,
    ),
    Achievement(
      kind: AchievementKind.streak,
      title: 'Three days running',
      description: 'Practise three days in a row',
      emoji: '🔥',
      target: 3,
      rewardStars: 10,
    ),
    Achievement(
      kind: AchievementKind.stars,
      title: 'Star jar',
      description: 'Collect 50 stars',
      emoji: '⭐',
      target: 50,
      rewardStars: 5,
    ),
    Achievement(
      kind: AchievementKind.soundsMastered,
      title: 'Sound wizard',
      description: 'Master five sounds',
      emoji: '🧙',
      target: 5,
      rewardStars: 15,
    ),
    Achievement(
      kind: AchievementKind.readingMinutes,
      title: 'Reading hour',
      description: 'Read out loud for 60 minutes',
      emoji: '📚',
      target: 60,
      rewardStars: 20,
    ),
    Achievement(
      kind: AchievementKind.gamesPlayed,
      title: 'Game champion',
      description: 'Play ten sound games',
      emoji: '🎮',
      target: 10,
      rewardStars: 10,
    ),
    Achievement(
      kind: AchievementKind.perfectLesson,
      title: 'Flawless',
      description: 'Finish a lesson with three stars',
      emoji: '🏅',
      target: 1,
      rewardStars: 10,
    ),
    Achievement(
      kind: AchievementKind.braveSpeaker,
      title: 'Brave voice',
      description: 'Say twenty words out loud',
      emoji: '🎤',
      target: 20,
      rewardStars: 10,
    ),
  ];

  /// Pure function of the learner's record → what they have earned. Because it
  /// is derived, a badge can never be "granted" inconsistently by a screen.
  static List<AchievementStatus> evaluate(
    ProfileSnapshot snapshot, {
    required int streakDays,
    Map<String, DateTime> unlockedAt = const {},
  }) {
    final mastered = snapshot.mastery.values
        .where((m) => m.status.name == 'mastered' || m.accuracy >= 0.9 && m.reps >= 4)
        .length;
    final perfectLessons =
        snapshot.lessons.values.where((l) => l.stars >= 3).length;
    final gamePlays = snapshot.gameRecords.values.fold<int>(
      0,
      (sum, record) => sum + record.plays,
    );
    final readMinutes = snapshot.sessions.fold<int>(
      0,
      (sum, session) => sum + session.minutesReadAloud,
    );
    final speakCount = snapshot.lessons.values.fold<int>(
      0,
      (sum, lesson) => sum + lesson.attempts,
    );

    final progress = <AchievementKind, int>{
      AchievementKind.firstLesson: snapshot.lessonsCompleted,
      AchievementKind.streak: streakDays,
      AchievementKind.stars: snapshot.starsTotal,
      AchievementKind.soundsMastered: mastered,
      AchievementKind.readingMinutes: readMinutes,
      AchievementKind.gamesPlayed: gamePlays,
      AchievementKind.perfectLesson: perfectLessons,
      AchievementKind.braveSpeaker: speakCount,
    };

    return [
      for (final achievement in catalog)
        () {
          final value = progress[achievement.kind] ?? 0;
          final unlocked = achievement.target <= 0
              ? value > 0
              : value >= achievement.target;
          return AchievementStatus(
            achievement: achievement,
            progress: value,
            unlocked: unlocked,
            unlockedAt: unlockedAt[achievement.kind.name],
          );
        }(),
    ];
  }

  static String weekLabel(DateTime day) {
    final week = DateUtil.isoWeek(day);
    return 'Week $week';
  }
}
