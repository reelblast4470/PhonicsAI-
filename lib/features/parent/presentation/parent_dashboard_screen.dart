import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../app/state/app_settings_controller.dart';
import '../../../core/domain/learner_profile.dart';
import '../../../core/responsive/responsive.dart';
import '../../../core/util/date_util.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/badge_pill.dart';
import '../../../shared/widgets/section_header.dart';
import '../../../shared/widgets/status_views.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_dimens.dart';
import '../../profile/application/profile_providers.dart';
import '../../progress/application/progress_providers.dart';
import '../../progress/domain/progress_repository.dart';
import '../../rewards/domain/achievements.dart';
import '../../subscription/application/subscription_providers.dart';
import '../application/parent_controls_controller.dart';
import 'widgets/report_card.dart';

/// Parent dashboard: the honest summary. Everything on this screen is derived
/// from recorded practice — time on task, accuracy, which sounds are shaky — and
/// nothing is rounded up to look better than the data says.
class ParentDashboardScreen extends ConsumerWidget {
  const ParentDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final profiles = ref.watch(profilesProvider);
    final plan = ref.watch(subscriptionProvider);
    final isWide = context.breakpoint.index >= Breakpoint.expanded.index;

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.xxxl,
        ),
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.parentTitle,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    Text(
                      plan.isPlus
                          ? 'PhonicsAI Plus · ${plan.renewsLabel}'
                          : 'Free plan · ${l10n.subscriptionFeatureAds}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: plan.isPlus ? colors.mint : null,
                          ),
                    ),
                  ],
                ),
              ),
              AppIconButton(
                icon: Icons.card_membership_rounded,
                tooltip: l10n.parentManageSubscription,
                onPressed: () => context.go(AppRoutes.parentSubscription),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          AsyncStateView<List<LearnerProfile>>(
            value: profiles,
            loadingMessage: l10n.stateLoading,
            emptyTitle: 'No learners yet',
            emptyMessage: 'Add a reader in the kid area first.',
            builder: (context, list) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (list.length > 1)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: SizedBox(
                      height: 44,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: list.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(width: AppSpacing.sm),
                        itemBuilder: (context, index) {
                          final profile = list[index];
                          final isActive = ref.watch(appSettingsProvider)
                                  .activeProfileId ==
                              profile.id;
                          return ChoiceChip(
                            selected: isActive,
                            label: Text(
                              '${profile.avatar.emoji} ${profile.displayName}',
                            ),
                            onSelected: (_) => ref
                                .read(profileControllerProvider.notifier)
                                .activate(profile.id),
                          );
                        },
                      ),
                    ),
                  ),
                for (final profile in list)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: _ChildSummaryCard(
                      profile: profile,
                      onTap: () => context.push(
                        AppRoutes.childReport(profile.id),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          const _QuickActionsRow(),
          const SizedBox(height: AppSpacing.xl),
          const SectionHeader(
            title: 'Content controls',
            leadingIcon: Icons.tune_rounded,
          ),
          const _ControlsCard(),
          const SizedBox(height: AppSpacing.lg),
          AppCard(
            color: colors.surfaceMuted,
            child: Row(
              children: [
                Icon(Icons.workspace_premium_outlined, color: colors.brand),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    isWide
                        ? 'Plus unlocks 1,200+ decodable readers, unlimited tutor '
                            'sessions and detailed reports. Billing is handled by '
                            'the store, never by PhonicsAI.'
                        : 'Plus: more readers, unlimited tutor, detailed reports.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                TextButton(
                  onPressed: () => context.go(AppRoutes.parentSubscription),
                  child: Text(l10n.actionUnlock),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChildSummaryCard extends ConsumerWidget {
  const _ChildSummaryCard({required this.profile, required this.onTap});

  final LearnerProfile profile;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final snapshot = ref.watch(profileProgressProvider).valueOrNull;
    final controls = ref.watch(parentControlsProvider);
    final minutesToday = snapshot?.today.minutes ?? 0;
    final limitReached =
        controls.hasDailyLimit && minutesToday >= controls.dailyLimitMinutes;
    final unlockedCount = snapshot == null
        ? 0
        : Achievements.evaluate(
              snapshot,
              streakDays: ref.watch(streakProvider),
            )
            .where((a) => a.unlocked)
            .length;

    return PressableCard(
      onTap: onTap,
      radius: 24,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                height: 46,
                width: 46,
                decoration: BoxDecoration(
                  color: profile.avatar.tint.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: Text(profile.avatar.emoji,
                      style: const TextStyle(fontSize: 24)),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.displayName,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    Text(
                      '${profile.level.label} · age ${profile.ageYears}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (limitReached)
                const BadgePill(
                  label: 'Daily limit reached',
                  tone: BadgeTone.danger,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              _MiniStat(
                label: l10n.parentTimeToday,
                value: '$minutesToday min',
                emoji: '⏱️',
              ),
              _MiniStat(
                label: 'Lessons',
                value: '${snapshot?.lessonsCompleted ?? 0} done',
                emoji: '📖',
              ),
              _MiniStat(
                label: 'Accuracy',
                value: '${((snapshot?.averageAccuracy ?? 0) * 100).round()}%',
                emoji: '🎯',
              ),
              _MiniStat(
                label: 'Badges',
                value: '$unlockedCount',
                emoji: '🏅',
              ),
            ],
          ),
          if (snapshot != null) ...[
            const SizedBox(height: AppSpacing.md),
            ReportBars(
              strengths: _topSounds(snapshot, best: true),
              needsWork: _topSounds(snapshot, best: false),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Week of ${DateUtil.weekStart(DateTime.now()).day}/'
                  '${DateUtil.weekStart(DateTime.now()).month}',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
              TextButton(
                onPressed: onTap,
                child: Text(l10n.parentWeeklyReport),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static List<String> _topSounds(ProfileSnapshot snapshot, {required bool best}) {
    final items = snapshot.mastery.entries.toList()
      ..sort((a, b) => best
          ? b.value.accuracy.compareTo(a.value.accuracy)
          : a.value.accuracy.compareTo(b.value.accuracy));
    return items
        .where((entry) => entry.value.reps > 0)
        .take(3)
        .map((entry) =>
            '${entry.key.split('__').last} ${((entry.value.accuracy) * 100).round()}%')
        .toList(growable: false);
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.label,
    required this.value,
    required this.emoji,
  });

  final String label;
  final String value;
  final String emoji;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 84,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(height: 2),
          Text(
            value,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          Text(label, style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }
}

class _QuickActionsRow extends ConsumerWidget {
  const _QuickActionsRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final actions = [
      ('📊', l10n.parentWeeklyReport, AppRoutes.parentReports),
      ('💳', l10n.parentManageSubscription, AppRoutes.parentSubscription),
      ('⚙️', l10n.settingsTitle, AppRoutes.parentSettings),
      ('🛟', l10n.settingsHelp, '${AppRoutes.parentSettings}/help'),
    ];
    // 2-up on a phone, 4-up when there is room: fixed 4-across would give the
    // labels 76px and clip.
    final columns = context.breakpoint.index >= Breakpoint.large.index ? 4 : 2;
    final gap = AppSpacing.sm;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width =
            (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final action in actions)
              SizedBox(
                width: width,
                child: PressableCard(
                  onTap: () => context.push(action.$3),
                  radius: 18,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.md,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(action.$1, style: const TextStyle(fontSize: 22)),
                      const SizedBox(height: 4),
                      Text(
                        action.$2,
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ControlsCard extends ConsumerWidget {
  const _ControlsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final controls = ref.watch(parentControlsProvider);
    final controller = ref.read(parentControlsProvider.notifier);

    return AppCard(
      child: Column(
        children: [
          SwitchListTile.adaptive(
            value: controls.allowMicrophone,
            onChanged: controller.setAllowMicrophone,
            title: Text(l10n.parentAllowVoice),
            subtitle: Text(
              'Audio is transcribed on-device. We do not store recordings.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          SwitchListTile.adaptive(
            value: controls.allowOpenChat,
            onChanged: controller.setAllowOpenChat,
            title: Text(l10n.parentAllowChat),
            subtitle: Text(
              'Off: the tutor answers only the on-screen suggestions.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const Divider(height: AppSpacing.xxl),
          ListTile(
            leading: const Icon(Icons.hourglass_bottom_rounded),
            title: Text(l10n.parentDailyLimit),
            trailing: DropdownButton<int>(
              value: controls.dailyLimitMinutes,
              underline: const SizedBox.shrink(),
              items: [
                for (final minutes in const [0, 10, 15, 20, 25, 30, 45])
                  DropdownMenuItem(
                    value: minutes,
                    child: Text(minutes == 0 ? 'No limit' : '$minutes min'),
                  ),
              ],
              onChanged: (value) {
                if (value != null) controller.setDailyLimit(value);
              },
            ),
          ),
          ListTile(
            leading: const Icon(Icons.notifications_active_outlined),
            title: Text(l10n.settingsReminders),
            subtitle: Text(controls.remindersEnabled
                ? 'Daily at ${controls.reminderTime.label}'
                : 'Off'),
            trailing: Switch(
              value: controls.remindersEnabled,
              onChanged: (value) =>
                  controller.setReminders(enabled: value),
            ),
          ),
        ],
      ),
    );
  }
}
