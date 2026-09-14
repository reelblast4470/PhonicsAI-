import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../core/responsive/responsive.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/badge_pill.dart';
import '../../../shared/widgets/kid_scaffold.dart';
import '../../../shared/widgets/progress_ring.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_dimens.dart';
import '../../curriculum/application/curriculum_providers.dart';
import '../../curriculum/domain/lesson.dart';
import '../../profile/application/profile_providers.dart';
import '../../progress/application/progress_providers.dart';
import '../../progress/domain/progress_repository.dart';
import '../domain/daily_mission.dart';
import 'widgets/mission_card.dart';

/// Home. Three things, in this order: who you are, what to do today, and the
/// single biggest button in the app. Nothing else competes — on a 5-year-old's
/// tablet, an uncluttered screen *is* the accessibility feature.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final profile = ref.watch(activeProfileProvider);
    final mission = ref.watch(dailyMissionProvider);
    final snapshot = ref.watch(profileProgressProvider).valueOrNull;
    final streak = ref.watch(streakProvider);
    final isWide = !context.breakpoint.isCompact;

    if (profile == null) {
      return KidScaffold(
        title: l10n.appName,
        showBack: false,
        body: Center(
          child: AppCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('🧒', style: TextStyle(fontSize: 54)),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Who is learning today?',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: AppSpacing.lg),
                AppButton(
                  label: l10n.profileAdd,
                  onPressed: () => context.push(AppRoutes.profileNew),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final next = _nextLesson(ref, snapshot);

    return KidScaffold(
      title: l10n.homeGreeting(profile.displayName),
      showBack: false,
      titleWidget: Row(
        children: [
          Container(
            height: 40,
            width: 40,
            decoration: BoxDecoration(
              color: profile.avatar.tint.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(
              child: Text(profile.avatar.emoji,
                  style: const TextStyle(fontSize: 22)),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              l10n.homeGreeting(profile.displayName),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          onPressed: () => context.go(AppRoutes.parent),
          icon: const Icon(Icons.shield_outlined),
          tooltip: l10n.parentTitle,
        ),
        const SizedBox(width: AppSpacing.xs),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              BadgePill(
                label: l10n.homeStreak(streak),
                icon: Icons.local_fire_department_rounded,
                tone: BadgeTone.flame,
                isSolid: streak > 0,
              ),
              BadgePill(
                label: l10n.homeStars(profile.starsBalance),
                icon: Icons.star_rounded,
                tone: BadgeTone.sun,
              ),
              BadgePill(
                label: l10n.homeLevelBadge(profile.level.label),
                icon: Icons.workspace_premium_outlined,
                tone: BadgeTone.brand,
              ),
              BadgePill(
                label: l10n.homeMinutesGoal(profile.dailyGoalMinutes),
                icon: Icons.timer_outlined,
                tone: BadgeTone.mint,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          MissionCard(
            mission: mission,
            onGoalTap: (goal) => _openFor(context, goal),
          ),
          const SizedBox(height: AppSpacing.xl),
          if (next != null) ...[
            Text(
              l10n.homeContinue,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: AppSpacing.sm),
            _ContinueLessonCard(lesson: next, snapshot: snapshot),
            const SizedBox(height: AppSpacing.xl),
          ],
          Text(
            'Jump to',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
            const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: _QuickTile(
                  emoji: '🎮',
                  label: l10n.navGames,
                  onTap: () => context.go(AppRoutes.games),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _QuickTile(
                  emoji: '🦉',
                  label: l10n.navTutor,
                  onTap: () => context.go(AppRoutes.tutor),
                ),
              ),
              if (isWide) ...[
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _QuickTile(
                    emoji: '📚',
                    label: 'My readers',
                    onTap: () => context.go(AppRoutes.progress),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          if (snapshot != null && snapshot.dueForReview.isNotEmpty)
            PressableCard(
              onTap: () => context.go(AppRoutes.progress),
              radius: 20,
              color: colors.sunshine.withValues(alpha: 0.14),
              child: Row(
                children: [
                  const Text('🔁', style: TextStyle(fontSize: 26)),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      l10n.progressDueForReview(
                        snapshot.dueForReview.length,
                      ),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
            ),
        ],
      ),
    );
  }

  PhonicsLesson? _nextLesson(WidgetRef ref, ProfileSnapshot? snapshot) {
    final ordered = ref.watch(orderedLessonsProvider);
    if (ordered.isEmpty) return null;
    // Live mode (Phase 3): the server engine owns "what's next" —
    // consolidate/review/advance rules all run there. Fall back to the local
    // rule when offline or in mock mode.
    final rec = ref.watch(liveRecommendationProvider).valueOrNull;
    final code = rec?.lessonCode;
    if (code != null) {
      for (final lesson in ordered) {
        if (lesson.id == code) return lesson;
      }
    }
    if (snapshot == null) return ordered.first;
    return snapshot.nextLesson(ordered);
  }

  void _openFor(BuildContext context, MissionGoal goal) {
    switch (goal.kind) {
      case MissionKind.lesson:
        context.go(AppRoutes.learn);
      case MissionKind.game:
        context.go(AppRoutes.games);
      case MissionKind.review:
        context.go(AppRoutes.progress);
      case MissionKind.readAloud:
        context.go(AppRoutes.tutor);
    }
  }
}

class _ContinueLessonCard extends ConsumerWidget {
  const _ContinueLessonCard({required this.lesson, required this.snapshot});

  final PhonicsLesson lesson;
  final ProfileSnapshot? snapshot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final accent = AppColors.accentFor(lesson.unitId);
    final progress = snapshot?.lesson(lesson.id);
    final fraction = snapshot?.lessonFraction(lesson) ?? 0;
    final resume = (progress?.doneCount ?? 0) > 0;

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      radius: 26,
      borderColor: accent.withValues(alpha: 0.35),
      child: Row(
        children: [
          ProgressRing(
            value: fraction,
            size: 64,
            strokeWidth: 7,
            color: accent,
            label: resume ? '${progress!.doneCount}' : '${lesson.stageCount}',
            subLabel: resume ? 'of ${lesson.stageCount}' : 'cards',
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  lesson.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                Text(
                  lesson.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: AppSpacing.sm),
                AppButton(
                  label: resume ? l10n.actionContinue : l10n.actionStart,
                  icon: Icons.play_arrow_rounded,
                  isCompact: true,
                  onPressed: () => context.push(AppRoutes.lessonFor(lesson.id)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickTile extends StatelessWidget {
  const _QuickTile({
    required this.emoji,
    required this.label,
    required this.onTap,
  });

  final String emoji;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableCard(
      onTap: onTap,
      radius: 22,
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
      semanticLabel: label,
      child: Column(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 34)),
          const SizedBox(height: AppSpacing.xs),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ],
      ),
    );
  }
}
