import 'package:flutter/material.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/badge_pill.dart';
import '../../../../theme/app_colors.dart';
import '../../../../theme/app_dimens.dart';
import '../../domain/daily_mission.dart';

/// Today's mission. Four small goals, each one a jump straight into the work —
/// a card that only *shows* a number would be a wasted tap.
class MissionCard extends StatelessWidget {
  const MissionCard({
    required this.mission,
    required this.onGoalTap,
    super.key,
  });

  final DailyMission mission;
  final void Function(MissionGoal goal) onGoalTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    return AppCard(
      radius: 28,
      padding: const EdgeInsets.all(AppSpacing.lg),
      gradient: mission.isComplete
          ? LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                colors.success.withValues(alpha: 0.16),
                colors.surface,
              ],
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.homeDailyMission,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    Text(
                      mission.isComplete
                          ? l10n.homeAllDone
                          : '${mission.doneCount} of ${mission.goals.length} done',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              BadgePill(
                label: '+${mission.xpReward}',
                icon: Icons.star_rounded,
                tone: BadgeTone.sun,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: mission.fraction),
              duration: AppMotion.slow,
              builder: (context, value, _) => LinearProgressIndicator(
                value: value,
                minHeight: 10,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          for (final goal in mission.goals)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: _GoalRow(
                goal: goal,
                onTap: () => onGoalTap(goal),
              ),
            ),
        ],
      ),
    );
  }
}

class _GoalRow extends StatelessWidget {
  const _GoalRow({required this.goal, required this.onTap});

  final MissionGoal goal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return PressableCard(
      onTap: onTap,
      radius: 18,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.md,
      ),
      color: goal.isDone ? colors.success.withValues(alpha: 0.1) : null,
      borderColor: goal.isDone ? colors.success.withValues(alpha: 0.5) : null,
      child: Row(
        children: [
          Text(goal.emoji, style: const TextStyle(fontSize: 26)),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  goal.label,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        decoration:
                            goal.isDone ? TextDecoration.lineThrough : null,
                        color: goal.isDone ? colors.inkMuted : null,
                      ),
                ),
                if (!goal.isDone && goal.target > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: goal.fraction,
                        minHeight: 5,
                        backgroundColor: colors.surfaceMuted,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          if (goal.isDone)
            Icon(Icons.check_circle_rounded, color: colors.success, size: 24)
          else
            Text(
              '${goal.current}/${goal.target}',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
          const Icon(Icons.chevron_right_rounded, size: 20),
        ],
      ),
    );
  }
}
