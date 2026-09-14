import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../core/responsive/responsive.dart';
import '../../../core/util/date_util.dart';
import '../../../shared/l10n_context.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/kid_scaffold.dart';
import '../../../shared/widgets/progress_ring.dart';
import '../../../shared/widgets/section_header.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_dimens.dart';
import '../../profile/application/profile_providers.dart';
import '../../rewards/domain/achievements.dart';
import '../application/progress_providers.dart';
import '../domain/progress_models.dart';
import '../domain/progress_repository.dart';
import 'widgets/mini_charts.dart';

/// Progress, in two registers: pictures and stars for the learner, real numbers
/// for whoever is sitting with them.
class ProgressScreen extends ConsumerWidget {
  const ProgressScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final colors = AppColors.of(context);
    final snapshot = ref.watch(profileProgressProvider).valueOrNull;
    final profile = ref.watch(activeProfileProvider);
    final streak = ref.watch(streakProvider);
    final isWide = !context.breakpoint.isCompact;

    if (profile == null) {
      return KidScaffold(
        title: l10n.progressTitle,
        body: const Center(child: Text('Add a learner to see progress.')),
      );
    }

    if (snapshot == null || snapshot.lessons.isEmpty) {
      return KidScaffold(
        title: l10n.progressTitle,
        body: Column(
          children: [
            AppCard(
              padding: const EdgeInsets.all(AppSpacing.xxl),
              child: Column(
                children: [
                  const Text('🌱', style: TextStyle(fontSize: 56)),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    l10n.progressEmpty,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  AppButton(
                    label: l10n.navLearn,
                    icon: Icons.menu_book_rounded,
                    isCompact: true,
                    onPressed: () => context.go(AppRoutes.learn),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final minutes = _minutesByDay(snapshot);
    final unlocked = Achievements.evaluate(snapshot, streakDays: streak)
        .where((a) => a.unlocked)
        .length;

    return KidScaffold(
      title: l10n.progressTitle,
      actions: [
        IconButton(
          onPressed: () => context.push(AppRoutes.rewards),
          icon: const Icon(Icons.emoji_events_outlined),
          tooltip: l10n.rewardsTitle,
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _StatTile(
                  label: l10n.progressLessons(snapshot.lessonsCompleted),
                  emoji: '📖',
                  accent: colors.brand,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _StatTile(
                  label: '${snapshot.today.minutes} min',
                  caption: l10n.progressThisWeek,
                  value: '${snapshot.minutesThisWeek} min',
                  emoji: '⏱️',
                  accent: colors.mint,
                ),
              ),
              if (isWide) ...[
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _StatTile(
                    label: '${(snapshot.averageAccuracy * 100).round()}%',
                    caption: l10n.progressAccuracy(
                      (snapshot.averageAccuracy * 100).round(),
                    ),
                    emoji: '🎯',
                    accent: colors.sunshine,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionHeader(
                  title: 'Every day this week',
                  leadingIcon: Icons.bar_chart_rounded,
                ),
                WeeklyBars(
                  minutesByDay: minutes,
                  goalMinutes: profile.dailyGoalMinutes,
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Goal: ${profile.dailyGoalMinutes} minutes a day',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: AppSpacing.lg),
                const SectionHeader(title: 'Last two weeks', leadingIcon: Icons.grid_view_rounded),
                PracticeHeatmap(minutesByDay: _last14(snapshot)),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (snapshot.dueForReview.isNotEmpty)
            AppCard(
              color: colors.sunshine.withValues(alpha: 0.14),
              borderColor: colors.sunshine.withValues(alpha: 0.5),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.progressDueForReview(snapshot.dueForReview.length),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          snapshot.dueForReview
                              .take(4)
                              .map((m) => m.phoneme.split('__').last)
                              .join('  ·  '),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  AppButton(
                    label: l10n.actionPlay,
                    icon: Icons.sports_esports_rounded,
                    isCompact: true,
                    onPressed: () => context.push(
                      AppRoutes.gameSession('sound_match'),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: AppSpacing.lg),
          const SectionHeader(
            title: 'Sound mastery',
            leadingIcon: Icons.hearing_rounded,
          ),
          _MasteryGrid(snapshot: snapshot),
          const SizedBox(height: AppSpacing.lg),
          AppCard(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.rewardsTitle,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        '$unlocked of ${Achievements.catalog.length} badges',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                IconButton.filledTonal(
                  onPressed: () => context.push(AppRoutes.rewards),
                  icon: const Icon(Icons.chevron_right_rounded),
                  tooltip: 'Open badges',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static List<int> _minutesByDay(ProfileSnapshot snapshot) {
    final weekStart = DateUtil.weekStart(DateTime.now());
    return [
      for (var i = 0; i < 7; i++)
        snapshot.sessionOn(DateUtil.addDays(weekStart, i)).minutes,
    ];
  }

  static List<int> _last14(ProfileSnapshot snapshot) {
    final today = DateUtil.startOfDay(DateTime.now());
    return [
      for (var i = 13; i >= 0; i--)
        snapshot.sessionOn(DateUtil.addDays(today, -i)).minutes,
    ];
  }
}

class _MasteryGrid extends ConsumerWidget {
  const _MasteryGrid({required this.snapshot});

  final ProfileSnapshot snapshot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sounds = snapshot.mastery.values.toList()
      ..sort((a, b) => a.accuracy.compareTo(b.accuracy));
    if (sounds.isEmpty) {
      return AppCard(
        child: Text(
          'Sounds you have practised will show up here.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }
    final columns = context.breakpoint.gridColumns;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: sounds.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisSpacing: AppSpacing.sm,
        crossAxisSpacing: AppSpacing.sm,
        childAspectRatio: 1.25,
      ),
      itemBuilder: (context, index) {
        final mastery = sounds[index];
        final label = mastery.phoneme.split('__').last;
        final color = switch (mastery.status) {
          MasteryStatus.mastered => AppColors.of(context).success,
          MasteryStatus.secure => AppColors.of(context).mint,
          MasteryStatus.learning => AppColors.of(context).warning,
          MasteryStatus.fresh => AppColors.of(context).inkMuted,
        };
        return AppCard(
          radius: 20,
          padding: const EdgeInsets.all(AppSpacing.sm),
          borderColor: color.withValues(alpha: 0.45),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const Spacer(),
              ProgressRing(
                value: mastery.accuracy,
                size: 38,
                strokeWidth: 4,
                color: color,
                label: '${(mastery.accuracy * 100).round()}',
              ),
              const SizedBox(height: 2),
              Text(
                switch (mastery.status) {
                  MasteryStatus.mastered => 'mastered',
                  MasteryStatus.secure => 'secure',
                  MasteryStatus.learning => 'learning',
                  MasteryStatus.fresh => 'new',
                },
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.emoji,
    required this.accent,
    this.caption,
    this.value,
  });

  final String label;
  final String? caption;
  final String? value;
  final String emoji;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      radius: 20,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 22)),
          const SizedBox(height: AppSpacing.xs),
          Text(
            value ?? label,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          if (caption != null)
            Text(
              caption!,
              maxLines: 2,
              style: Theme.of(context).textTheme.labelSmall,
            ),
        ],
      ),
    );
  }
}
