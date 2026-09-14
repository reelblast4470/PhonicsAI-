import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../core/domain/reading_level.dart';
import '../../../core/responsive/responsive.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/l10n_context.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/badge_pill.dart';
import '../../../shared/widgets/kid_scaffold.dart';
import '../../../shared/widgets/progress_ring.dart';
import '../../../shared/widgets/star_row.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_dimens.dart';
import '../../profile/application/profile_providers.dart';
import '../../progress/application/progress_providers.dart';
import '../../progress/domain/progress_repository.dart';
import '../application/curriculum_providers.dart';
import '../domain/lesson.dart';

/// The phonics journey: units as a path, lessons as stops.
///
/// One deliberate UX change from a flat list: the *current* lesson is a single
/// big card at the top. A 4-year-old cannot scan a list, but they can tap the
/// one big thing — and the grown-up gets the full path below it.
class CurriculumScreen extends ConsumerWidget {
  const CurriculumScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final units = ref.watch(curriculumProvider);
    final profile = ref.watch(activeProfileProvider);
    final snapshot = ref.watch(profileProgressProvider).valueOrNull;
    if (profile == null || units.isEmpty) {
      return KidScaffold(title: l10n.learnTitle, body: const SizedBox.shrink());
    }

    final ordered = [
      for (final unit in [...units]..sort((a, b) => a.order.compareTo(b.order)))
        unit,
    ];
    final next = _nextLesson(ordered, snapshot);

    return KidScaffold(
      title: l10n.learnTitle,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (next != null)
            _ContinueCard(
              lesson: next.lesson,
              unit: next.unit,
              fraction: snapshot?.lessonFraction(next.lesson) ?? 0,
            ),
          const SizedBox(height: AppSpacing.xl),
          if (snapshot != null && snapshot.dueForReview.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: PressableCard(
                onTap: () => context.go(AppRoutes.progress),
                radius: 20,
                color: AppColors.of(context).sunshine.withValues(alpha: 0.16),
                borderColor: AppColors.of(context).sunshine,
                child: Row(
                  children: [
                    const Text('🔁', style: TextStyle(fontSize: 28)),
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
            ),
          for (final unit in ordered)
            _UnitSection(unit: unit, snapshot: snapshot),
        ],
      ),
    );
  }

  static ({CurriculumUnit unit, PhonicsLesson lesson})? _nextLesson(
    List<CurriculumUnit> units,
    ProfileSnapshot? snapshot,
  ) {
    for (final unit in units) {
      for (final lesson in unit.lessons) {
        if (snapshot == null || !snapshot.lessonIsComplete(lesson)) {
          return (unit: unit, lesson: lesson);
        }
      }
    }
    final last = units.last;
    return last.lessons.isEmpty
        ? null
        : (unit: last, lesson: last.lessons.last);
  }
}

class _ContinueCard extends StatelessWidget {
  const _ContinueCard({
    required this.lesson,
    required this.unit,
    required this.fraction,
  });

  final PhonicsLesson lesson;
  final CurriculumUnit unit;
  final double fraction;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final accent = AppColors.accentFor(unit.id);
    return AppCard(
      padding: EdgeInsets.zero,
      radius: 28,
      child: ColoredBox(
        color: accent.withValues(alpha: 0.1),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.homeContinue,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: colors.inkMuted,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.1,
                          ),
                    ),
                  ),
                  ProgressRing(
                    value: fraction,
                    size: 40,
                    strokeWidth: 5,
                    label: '${(fraction * 100).round()}',
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          lesson.title,
                          style: Theme.of(context).textTheme.displaySmall
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          unit.title,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  if (!context.breakpoint.isCompact)
                    StarRow(earned: 0, size: 22),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              AppButton(
                label: fraction > 0
                    ? l10n.actionContinue
                    : '${l10n.actionStart} · ${lesson.stageCount} cards',
                icon: Icons.play_arrow_rounded,
                isExpanded: true,
                onPressed: () =>
                    context.push(AppRoutes.lessonFor(lesson.id)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UnitSection extends ConsumerWidget {
  const _UnitSection({
    required this.unit,
    required this.snapshot,
  });

  final CurriculumUnit unit;
  final ProfileSnapshot? snapshot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final level = ref.watch(activeProfileProvider)?.level ??
        ReadingLevel.preReader;
    final access = ref.watch(
      unitAccessProvider(
        UnitAccessRequest(unitId: unit.id, level: level, snapshot: snapshot),
      ),
    );
    final accent = AppColors.accentFor(unit.id);
    final expanded = ref.watch(expandedUnitProvider) == unit.id;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: AppCard(
        padding: const EdgeInsets.all(AppSpacing.lg),
        borderColor: access.isUnlocked ? accent.withValues(alpha: 0.4) : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PressableCard(
              onTap: () =>
                  ref.read(expandedUnitProvider.notifier).toggle(unit.id),
              radius: 18,
              padding: EdgeInsets.zero,
              color: Colors.transparent,
              borderColor: Colors.transparent,
              child: Row(
                children: [
                  Container(
                    height: 52,
                    width: 52,
                    decoration: BoxDecoration(
                      color: access.isUnlocked
                          ? accent.withValues(alpha: 0.18)
                          : colors.surfaceMuted,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Center(
                      child: access.isUnlocked
                          ? ProgressRing(
                              value: access.fraction,
                              size: 42,
                              strokeWidth: 5,
                              label: '${access.completedLessons}',
                              subLabel: '${unit.lessons.length}',
                              color: accent,
                            )
                          : Icon(Icons.lock_rounded,
                              size: 20, color: colors.inkMuted),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          unit.title,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          access.isUnlocked
                              ? l10n.learnUnitProgress(
                                  access.completedLessons,
                                  unit.lessons.length,
                                )
                              : l10n.learnLocked,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                  ),
                ],
              ),
            ),
            AnimatedSize(
              duration: AppMotion.normal,
              alignment: Alignment.topCenter,
              child: expanded
                  ? Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.md),
                      child: Column(
                        children: [
                          for (final lesson in unit.lessons)
                            _LessonRow(
                              lesson: lesson,
                              isEnabled: access.isUnlocked,
                            ),
                          const SizedBox(height: AppSpacing.sm),
                          Wrap(
                            spacing: AppSpacing.xs,
                            runSpacing: AppSpacing.xs,
                            children: [
                              for (final phoneme in unit.phonemes)
                                BadgePill(
                                  label: phoneme.grapheme,
                                  tone: BadgeTone.neutral,
                                ),
                            ],
                          ),
                        ],
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ],
        ),
      ),
    );
  }
}

class _LessonRow extends ConsumerWidget {
  const _LessonRow({required this.lesson, required this.isEnabled});

  final PhonicsLesson lesson;
  final bool isEnabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AppColors.of(context);
    final snapshot = ref.watch(profileProgressProvider).valueOrNull;
    final progress = snapshot?.lesson(lesson.id);
    final isComplete = snapshot != null && snapshot.lessonIsComplete(lesson);
    final started = (progress?.doneCount ?? 0) > 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: PressableCard(
        onTap: isEnabled ? () => context.push(AppRoutes.lessonFor(lesson.id)) : null,
        radius: 16,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            Icon(
              isComplete
                  ? Icons.check_circle_rounded
                  : started
                      ? Icons.play_circle_outline_rounded
                      : Icons.radio_button_unchecked_rounded,
              color: isComplete
                  ? colors.success
                  : started
                  ? colors.brand
                  : colors.inkMuted,
              size: 26,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    lesson.title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  Text(
                    lesson.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            if (progress != null && progress.stars > 0)
              StarRow(earned: progress.stars, size: 15, animate: false),
          ],
        ),
      ),
    );
  }
}

/// Which unit is expanded on the Learn tab (one at a time, like a path).
class ExpandedUnit extends Notifier<String?> {
  @override
  String? build() => null;

  void toggle(String unitId) => state = state == unitId ? null : unitId;
}

final expandedUnitProvider = NotifierProvider<ExpandedUnit, String?>(
  ExpandedUnit.new,
);
