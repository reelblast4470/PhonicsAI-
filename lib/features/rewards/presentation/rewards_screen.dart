import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/kid_scaffold.dart';
import '../../../shared/widgets/progress_ring.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_dimens.dart';
import '../../profile/application/profile_providers.dart';
import '../../progress/application/progress_providers.dart';
import '../../progress/domain/progress_repository.dart';
import '../domain/achievements.dart';

/// Badges and stars. Locked badges show *how far* to go, because "keep going"
/// without a number is not motivating to a 5-year-old or honest to a parent.
class RewardsScreen extends ConsumerWidget {
  const RewardsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final snapshot = ref.watch(profileProgressProvider).valueOrNull;
    final profile = ref.watch(activeProfileProvider);
    final statuses = Achievements.evaluate(
      snapshot ?? ProfileSnapshot.empty(''),
      streakDays: ref.watch(streakProvider),
    );
    final unlocked = statuses.where((s) => s.unlocked).toList();
    final nextBest = statuses
        .where((s) => !s.unlocked)
        .toList()
      ..sort((a, b) => b.fraction.compareTo(a.fraction));

    return KidScaffold(
      title: l10n.rewardsTitle,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppCard(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [colors.gold.withValues(alpha: 0.22), colors.surface],
            ),
            child: Row(
              children: [
                const Text('⭐', style: TextStyle(fontSize: 44)),
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${profile?.starsBalance ?? snapshot?.starsTotal ?? 0} stars',
                        style: Theme.of(context).textTheme.displaySmall
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      Text(
                        'Stars are earned by practising. They never cost money.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          if (unlocked.isNotEmpty) ...[
            Text(
              l10n.rewardsUnlocked,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: AppSpacing.sm),
            _BadgeGrid(statuses: unlocked, isUnlockedSet: true),
            const SizedBox(height: AppSpacing.xl),
          ],
          Text(
            'Still on the way',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (nextBest.isEmpty)
            AppCard(
              child: Text(
                'Every badge earned. Wow.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            )
          else
            _BadgeGrid(statuses: nextBest, isUnlockedSet: false),
          const SizedBox(height: AppSpacing.lg),
          AppCard(
            color: colors.surfaceMuted,
            child: Row(
              children: [
                Icon(Icons.emoji_events_rounded, color: colors.gold),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    'Badges never expire and nothing here can be bought. '
                    'A badge means the practice really happened.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BadgeGrid extends StatelessWidget {
  const _BadgeGrid({required this.statuses, required this.isUnlockedSet});

  final List<AchievementStatus> statuses;
  final bool isUnlockedSet;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: statuses.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: AppSpacing.md,
        crossAxisSpacing: AppSpacing.md,
        childAspectRatio: 1.35,
      ),
      itemBuilder: (context, index) {
        final status = statuses[index];
        return AppCard(
          radius: 24,
          padding: const EdgeInsets.all(AppSpacing.md),
          borderColor: status.unlocked ? colors.gold : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Opacity(
                    opacity: status.unlocked ? 1 : 0.35,
                    child: Text(
                      status.achievement.emoji,
                      style: const TextStyle(fontSize: 34),
                    ),
                  ),
                  const Spacer(),
                  if (!status.unlocked)
                    ProgressRing(
                      value: status.fraction,
                      size: 40,
                      strokeWidth: 5,
                      label: '${(status.fraction * 100).round()}',
                    )
                  else
                    const Icon(Icons.verified_rounded, color: Color(0xFFFFB300)),
                ],
              ),
              const Spacer(),
              Text(
                status.achievement.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              Text(
                status.unlocked
                    ? '${status.achievement.rewardStars} stars earned'
                    : '${status.achievement.description} · '
                        '${status.progress}/${status.achievement.target}',
                maxLines: 2,
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
