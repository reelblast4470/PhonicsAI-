import 'package:flutter/foundation.dart';

import '../../../core/util/date_util.dart';
import '../../../core/util/math_util.dart';

enum MissionKind { lesson, game, review, readAloud }

@immutable
class MissionGoal {
  const MissionGoal({
    required this.kind,
    required this.label,
    required this.target,
    required this.current,
    this.emoji = '⭐',
  });

  final MissionKind kind;
  final String label;
  final int target;
  final int current;
  final String emoji;

  bool get isDone => current >= target;
  double get fraction => MathUtil.clamp(current / (target <= 0 ? 1 : target), 0, 1);
  int get remaining => (target - current).clamp(0, 1 << 30);

  MissionGoal withCurrent(int value) => MissionGoal(
        kind: kind,
        label: label,
        target: target,
        current: value,
        emoji: emoji,
      );
}

/// "Do three small things today" — the spine of the daily habit. Built from
/// real progress, so a learner who already played a game sees 1/2, not a lie.
@immutable
class DailyMission {
  const DailyMission({
    required this.date,
    required this.goals,
    required this.streakDays,
    required this.xpReward,
  });

  final DateTime date;
  final List<MissionGoal> goals;
  final int streakDays;
  final int xpReward;

  bool get isComplete => goals.every((g) => g.isDone);
  double get fraction => goals.isEmpty
      ? 0
      : goals.fold<double>(0, (sum, g) => sum + g.fraction) / goals.length;
  int get doneCount => goals.where((g) => g.isDone).length;

  String get titleDate {
    final days = DateUtil.daysBetween(date, DateTime.now());
    return switch (days) {
      0 => 'Today',
      1 => 'Yesterday',
      _ => '$days days ago',
    };
  }

  /// A mission is never "0 of 3 on a brand-new day" for a 3-year-old: the
  /// first goal is tiny on purpose so something goes green fast.
  static DailyMission build({
    required DateTime date,
    required int lessonsCompletedToday,
    required int gamesPlayedToday,
    required int minutesReadAloudToday,
    required int dueReviews,
    required int streakDays,
    required bool isVeryNewLearner,
  }) {
    return DailyMission(
      date: date,
      streakDays: streakDays,
      xpReward: 20 + (streakDays.clamp(0, 10) * 2),
      goals: [
        MissionGoal(
          kind: MissionKind.lesson,
          label: isVeryNewLearner ? 'Finish one tiny lesson' : 'Finish a lesson',
          target: 1,
          current: lessonsCompletedToday,
          emoji: '📖',
        ),
        MissionGoal(
          kind: MissionKind.game,
          label: 'Play a sound game',
          target: 1,
          current: gamesPlayedToday,
          emoji: '🎮',
        ),
        MissionGoal(
          kind: MissionKind.review,
          label: dueReviews == 0
              ? 'No reviews due — nice!'
              : 'Practise ${dueReviews.clamp(1, 5)} tricky sounds',
          target: dueReviews == 0 ? 0 : MathUtil.clampInt(dueReviews, 1, 5),
          current: dueReviews == 0 ? 1 : 0,
          emoji: '🔁',
        ),
        MissionGoal(
          kind: MissionKind.readAloud,
          label: 'Read out loud for 3 minutes',
          target: 3,
          current: minutesReadAloudToday,
          emoji: '🗣️',
        ),
      ],
    );
  }
}
