import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/responsive/responsive.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/badge_pill.dart';
import '../../../shared/widgets/confetti_burst.dart';
import '../../../shared/widgets/star_row.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_dimens.dart';
import '../../audio/tts_bridge.dart';
import '../../progress/application/progress_providers.dart';
import '../application/lesson_runner.dart';
import 'widgets/stage_renderers.dart';

/// The lesson. Full screen, one stage at a time, always showing where in the
/// Discover → Hear → See → … → Review loop the learner stands.
///
/// Leaving mid-lesson is safe: stage completions are written as they happen, so
/// the "Continue" card on Home lands on the exact stage the child stopped at.
class LessonPlayerScreen extends ConsumerStatefulWidget {
  const LessonPlayerScreen({required this.lessonId, super.key});

  final String lessonId;

  @override
  ConsumerState<LessonPlayerScreen> createState() => LessonPlayerScreenState();
}

class LessonPlayerScreenState extends ConsumerState<LessonPlayerScreen>
    with SingleTickerProviderStateMixin {
  int _burst = 0;
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: AppMotion.celebrate,
  );

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _confirmExit(LessonRunState state) async {
    if (state.isFinished) {
      if (mounted) context.pop();
      return;
    }
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave the lesson?'),
        content: const Text(
          'What you finished is saved. You can come back to this card.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep going'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Finish for now'),
          ),
        ],
      ),
    );
    if (leave ?? false) {
      await ref.read(lessonRunProvider(widget.lessonId).notifier).finish();
      if (mounted) context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(lessonRunProvider(widget.lessonId));

    if (state == null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: AppCard(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.search_off_rounded, size: 38),
                  const SizedBox(height: AppSpacing.md),
                  Text('Lesson "${widget.lessonId}" is not on this device.'),
                  const SizedBox(height: AppSpacing.lg),
                  AppButton(
                    label: l10n.actionBack,
                    isCompact: true,
                    onPressed: () => context.go('/learn'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmExit(state);
      },
      child: Scaffold(
        body: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  _LessonHeader(
                    state: state,
                    onClose: () => _confirmExit(state),
                  ),
                  Expanded(
                    child: ContentLimits(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.screenSidePadding,
                        ),
                        child: Column(
                          children: [
                            _StageTrack(state: state),
                            const SizedBox(height: AppSpacing.lg),
                            Expanded(
                              child: SingleChildScrollView(
                                child: StageRenderer(state: state),
                              ),
                            ),
                            _StageFooter(state: state),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (state.isFinished)
                Positioned.fill(
                  child: _LessonCompleteSheet(
                    state: state,
                    burst: _burst,
                    onFireBurst: () => setState(() => _burst++),
                  ),
                ),
              Positioned.fill(child: ConfettiBurst(trigger: _burst)),
            ],
          ),
        ),
      ),
    );
  }
}

class _LessonHeader extends ConsumerWidget {
  const _LessonHeader({required this.state, required this.onClose});

  final LessonRunState state;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.xs,
        AppSpacing.lg,
        0,
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded),
            tooltip: AppLocalizations.of(context).actionClose,
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  state.lesson.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                Text(
                  state.stage.kind.label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colors.brand,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                ),
              ],
            ),
          ),
          BadgePill.stars('${_starsSoFar(context, ref)}'),
          const SizedBox(width: AppSpacing.sm),
          BadgePill(
            label: '${(state.fraction * 100).round()}%',
            tone: BadgeTone.brand,
          ),
        ],
      ),
    );
  }

  int _starsSoFar(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(profileProgressProvider).valueOrNull;
    if (snapshot == null) return 0;
    return snapshot.lessons.values.fold<int>(
      0,
      (sum, lesson) => sum + lesson.stars,
    );
  }
}

/// Ten dots with the current stage named — the loop made visible. Older learners
/// see the label; a 3-year-old sees the colour and the count.
class _StageTrack extends StatelessWidget {
  const _StageTrack({required this.state});

  final LessonRunState state;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final showLabels = context.isDesktopLayout;
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < state.lesson.stages.length; i++)
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: AnimatedContainer(
                    duration: AppMotion.normal,
                    height: i == state.stageIndex ? 12 : 8,
                    decoration: BoxDecoration(
                      color: i < state.stageIndex
                          ? colors.success
                          : i == state.stageIndex
                          ? colors.brand
                          : colors.inkMuted.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
              ),
          ],
        ),
        if (showLabels) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            state.lesson.stages
                .map((stage) => stage.kind.label)
                .join('  ›  '),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colors.inkMuted,
                ),
          ),
        ],
      ],
    );
  }
}

class _StageFooter extends ConsumerWidget {
  const _StageFooter({required this.state});

  final LessonRunState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final runner = ref.read(lessonRunProvider(state.lesson.id).notifier);
    final isLast = state.isLastStage;

    // A stage is complete when its items are; "Next" is always available so a
    // child is never trapped by a stage they already understand.
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenSidePadding,
        AppSpacing.md,
        AppSpacing.screenSidePadding,
        AppSpacing.lg,
      ),
      child: Row(
        children: [
          if (state.stage.items.isNotEmpty)
            IconButton(
              onPressed: () => runner.nextStage().ignore(),
              icon: const Icon(Icons.skip_next_rounded),
              tooltip: l10n.actionSkip,
            ),
          const Spacer(),
          AppButton(
            label: isLast ? l10n.actionFinish : l10n.actionNext,
            icon: isLast ? Icons.celebration_rounded : Icons.arrow_forward_rounded,
            tone: isLast ? AppButtonTone.sun : AppButtonTone.brand,
            isLoading: state.isSaving,
            onPressed: () {
              if (isLast) {
                runner.finish().ignore();
              } else {
                runner.nextStage().ignore();
              }
            },
          ),
        ],
      ),
    );
  }
}

class _LessonCompleteSheet extends ConsumerWidget {
  const _LessonCompleteSheet({
    required this.state,
    required this.burst,
    required this.onFireBurst,
  });

  final LessonRunState state;
  final int burst;
  final VoidCallback onFireBurst;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final stars = state.savedStars ?? state.stars;
    final xp = state.lesson.xp * stars;

    return ColoredBox(
      color: colors.canvas.withValues(alpha: 0.96),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: AppCard(
              padding: const EdgeInsets.all(AppSpacing.xxxl),
              child: Column(
                children: [
                  Text(
                    state.errorMessage == null
                        ? l10n.learnLessonComplete
                        : 'Saved on this device',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    state.lesson.title,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colors.inkMuted,
                        ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0, end: 1),
                    duration: AppMotion.celebrate,
                    builder: (context, value, _) => Transform.scale(
                      scale: 0.8 + value * 0.2,
                      child: StarRow(earned: stars, size: 52),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  BadgePill(
                    label: l10n.learnXpEarned(xp),
                    icon: Icons.star_rounded,
                    tone: BadgeTone.sun,
                    isSolid: false,
                  ),
                  if (state.errorMessage case final error?) ...[
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      error,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: colors.warning),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.xxl),
                  AppButton(
                    label: 'Hooray!',
                    icon: Icons.celebration_rounded,
                    tone: AppButtonTone.sun,
                    isExpanded: true,
                    onPressed: () {
                      onFireBurst();
                      unawaited(ref.read(ttsBridgeProvider).celebrate());
                      context.pop();
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
