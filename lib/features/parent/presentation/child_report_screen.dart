import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/state/app_settings_controller.dart';
import '../../../core/domain/learner_profile.dart';
import '../../../core/responsive/responsive.dart';
import '../../../core/util/date_util.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/feedback/app_toast.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/badge_pill.dart';
import '../../../shared/widgets/section_header.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_dimens.dart';
import '../../profile/application/profile_providers.dart';
import '../../progress/application/progress_providers.dart';
import '../../progress/domain/progress_models.dart';
import '../../progress/domain/progress_repository.dart';
import '../../rewards/domain/achievements.dart';
import '../../subscription/application/subscription_providers.dart';
import '../../subscription/domain/subscription_models.dart';

/// The detailed per-child report — what a teacher would ask for.
///
/// Copy/export is a plain-text summary (clipboard + share sheet later), which is
/// also the "export my data" path the privacy screen points at: one format, one
/// source of truth.
class ChildReportScreen extends ConsumerWidget {
  const ChildReportScreen({this.profileId, this.isStandalone = false, super.key});

  final String? profileId;
  final bool isStandalone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final profiles = ref.watch(profilesProvider).valueOrNull ?? const <LearnerProfile>[];
    final activeId = profileId ??
        ref.watch(appSettingsProvider).activeProfileId ??
        (profiles.isEmpty ? null : profiles.first.id);
    final profile = profiles.where((p) => p.id == activeId).firstOrNull;
    final snapshot = ref.watch(profileProgressProvider).valueOrNull;
    final isWide = context.breakpoint.index >= Breakpoint.expanded.index;

    if (profile == null) {
      return Scaffold(
        body: Center(
          child: Text(
            'No learner selected yet.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      );
    }

    final week = _weekMinutes(snapshot);
    final statuses = Achievements.evaluate(
      snapshot ?? ProfileSnapshot.empty(profile.id),
      streakDays: ref.watch(streakProvider),
    );
    final mastered = snapshot?.mastery.values
            .where((m) => m.status == MasteryStatus.mastered)
            .map((m) => m.phoneme.split('__').last)
            .toList() ??
        const <String>[];
    final shaky = (snapshot?.dueForReview ?? const <PhonemeMastery>[])
        .map((m) => m.phoneme.split('__').last)
        .toList();
    final entitlements = ref.watch(subscriptionProvider);

    final report = _ReportModel(
      profile: profile,
      snapshot: snapshot,
      weekMinutes: week,
      mastered: mastered,
      shaky: shaky,
      badges: statuses.where((s) => s.unlocked).length,
    );

    return Scaffold(
      appBar: isStandalone
          ? AppBar(title: Text('${profile.displayName} · report'))
          : null,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.xxxl,
          ),
          child: ContentLimits(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: profile.avatar.tint.withValues(alpha: 0.2),
                      child: Text(profile.avatar.emoji,
                          style: const TextStyle(fontSize: 24)),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Text(
                        '${profile.displayName} · ${profile.level.label}',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    if (entitlements.has(Entitlement.detailedReports))
                      const BadgePill(
                        label: 'Plus report',
                        icon: Icons.workspace_premium_rounded,
                        tone: BadgeTone.sun,
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                isWide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: _NumbersCard(report: report)),
                          const SizedBox(width: AppSpacing.lg),
                          Expanded(child: _SoundsCard(report: report)),
                        ],
                      )
                    : Column(
                        children: [
                          _NumbersCard(report: report),
                          const SizedBox(height: AppSpacing.md),
                          _SoundsCard(report: report),
                        ],
                      ),
                const SizedBox(height: AppSpacing.md),
                _SessionsCard(report: report),
                const SizedBox(height: AppSpacing.lg),
                Row(
                  children: [
                    Expanded(
                      child: AppButton(
                        label: l10n.parentShareReport,
                        icon: Icons.ios_share_rounded,
                        isCompact: true,
                        tone: AppButtonTone.neutral,
                        isExpanded: true,
                        onPressed: () async {
                          await Clipboard.setData(
                            ClipboardData(text: report.asText()),
                          );
                          if (context.mounted) {
                            AppToast.show(
                              context,
                              'Copied. Paste it into a message to the school.',
                              icon: Icons.copy_rounded,
                            );
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: AppButton(
                        label: 'Export JSON',
                        icon: Icons.download_rounded,
                        isCompact: true,
                        tone: AppButtonTone.neutral,
                        isExpanded: true,
                        onPressed: () async {
                          await Clipboard.setData(
                            ClipboardData(text: report.asJson()),
                          );
                          if (context.mounted) {
                            AppToast.show(
                              context,
                              'JSON copied to the clipboard.',
                              icon: Icons.data_object_rounded,
                            );
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Nothing here is sent anywhere unless cloud sync is on. '
                  'Screenshots are yours to share.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelSmall
                      ?.copyWith(color: colors.inkMuted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static List<int> _weekMinutes(ProfileSnapshot? snapshot) {
    if (snapshot == null) return List<int>.filled(7, 0);
    final start = DateUtil.weekStart(DateTime.now());
    return [
      for (var i = 0; i < 7; i++) snapshot.sessionOn(DateUtil.addDays(start, i)).minutes,
    ];
  }
}

class _ReportModel {
  const _ReportModel({
    required this.profile,
    required this.snapshot,
    required this.weekMinutes,
    required this.mastered,
    required this.shaky,
    required this.badges,
  });

  final LearnerProfile profile;
  final ProfileSnapshot? snapshot;
  final List<int> weekMinutes;
  final List<String> mastered;
  final List<String> shaky;
  final int badges;

  int get totalWeek => weekMinutes.fold(0, (a, b) => a + b);

  String asText() {
    final buffer = StringBuffer()
      ..writeln('PhonicsAI report — ${profile.displayName}')
      ..writeln('Level: ${profile.level.label}  ·  Age ${profile.ageYears}')
      ..writeln('Generated: ${DateTime.now().toIso8601String()}')
      ..writeln('')
      ..writeln('This week: $totalWeek minutes, '
          '${snapshot?.lessonsCompleted ?? 0} lessons, '
          '${((snapshot?.averageAccuracy ?? 0) * 100).round()}% accuracy')
      ..writeln('Mastered sounds: ${mastered.isEmpty ? 'not yet' : mastered.join(', ')}')
      ..writeln('Needs practice: ${shaky.isEmpty ? 'nothing flagged' : shaky.join(', ')}')
      ..writeln('Badges: $badges');
    return buffer.toString();
  }

  String asJson() => jsonEncode({
        'learner': profile.displayName,
        'level': profile.level.code,
        'age_months': profile.ageMonths,
        'week_minutes': weekMinutes,
        'lessons_completed': snapshot?.lessonsCompleted ?? 0,
        'average_accuracy': snapshot?.averageAccuracy ?? 0,
        'mastered_sounds': mastered,
        'needs_practice': shaky,
        'badges': badges,
        'generated_at': DateTime.now().toIso8601String(),
      });
}

class _NumbersCard extends ConsumerWidget {
  const _NumbersCard({required this.report});

  final _ReportModel report;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(
            title: 'This week',
            leadingIcon: Icons.insights_rounded,
          ),
          Row(
            children: [
              _Number(
                label: l10n.parentTimeWeek,
                value: '${report.totalWeek}',
                unit: 'min',
              ),
              _Number(
                label: 'Lessons',
                value: '${report.snapshot?.lessonsCompleted ?? 0}',
                unit: 'done',
              ),
              _Number(
                label: 'Accuracy',
                value:
                    '${((report.snapshot?.averageAccuracy ?? 0) * 100).round()}',
                unit: '%',
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('Minutes per day', style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: AppSpacing.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 74,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final minutes in report.weekMinutes)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: Tooltip(
                          message: '$minutes min',
                          child: Container(
                            height: (minutes * 3.2).clamp(6.0, 74.0),
                            decoration: BoxDecoration(
                              color: AppColors.of(context).brand,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Number extends StatelessWidget {
  const _Number({required this.label, required this.value, required this.unit});

  final String label;
  final String value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          Text('$unit · $label', style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }
}

class _SoundsCard extends StatelessWidget {
  const _SoundsCard({required this.report});

  final _ReportModel report;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(
            title: 'Sounds',
            leadingIcon: Icons.hearing_rounded,
          ),
          Text('Mastered', style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final sound in report.mastered)
                _SoundChip(label: sound, color: colors.success),
              if (report.mastered.isEmpty)
                Text('None yet — that is normal in week one.',
                    style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text('Needs practice', style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final sound in report.shaky)
                _SoundChip(label: sound, color: colors.warning),
              if (report.shaky.isEmpty)
                Text('Nothing flagged.',
                    style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ],
      ),
    );
  }
}

class _SoundChip extends StatelessWidget {
  const _SoundChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontWeight: FontWeight.w800,
          color: color,
          fontSize: 13,
        ),
      ),
    );
  }
}

class _SessionsCard extends StatelessWidget {
  const _SessionsCard({required this.report});

  final _ReportModel report;

  @override
  Widget build(BuildContext context) {
    final sessions = (report.snapshot?.sessions ?? const <DaySession>[])
        .reversed
        .take(7)
        .toList();
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(
            title: 'Last sessions',
            leadingIcon: Icons.history_rounded,
          ),
          if (sessions.isEmpty)
            Text('No practice recorded yet.',
                style: Theme.of(context).textTheme.bodySmall)
          else
            for (final session in sessions)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Text(
                      '${session.date.day}/${session.date.month}',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Text(
                        '${session.minutes} min · ${session.lessonsCompleted} lessons'
                        '${session.gamesPlayed > 0 ? ' · ${session.gamesPlayed} games' : ''}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    BadgePill.stars('${session.stars}'),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}
