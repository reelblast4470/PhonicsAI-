import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/badge_pill.dart';
import '../../../shared/widgets/confetti_burst.dart';
import '../../../shared/widgets/kid_scaffold.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_dimens.dart';
import '../application/assessment_controller.dart';
import '../domain/assessment_content.dart';

/// The placement check-up. Five spoken cards, no typing, no reading, and no
/// "wrong" — a wrong tap is a teaching moment, then the next card.
class AssessmentScreen extends ConsumerWidget {
  const AssessmentScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(assessmentProvider);
    return KidScaffold(
      scrollable: false,
      title: state.phase == AssessmentPhase.intro
          ? AppLocalizations.of(context).assessmentTitle
          : null,
      showBack: false,
      body: switch (state.phase) {
        AssessmentPhase.intro => const _IntroStep(),
        AssessmentPhase.questions => const _QuestionStep(),
        AssessmentPhase.result => const _ResultStep(),
      },
    );
  }
}

class _IntroStep extends ConsumerWidget {
  const _IntroStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.md),
        AppCard(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Column(
            children: [
              const Text('🎧', style: TextStyle(fontSize: 64)),
              const SizedBox(height: AppSpacing.lg),
              Text(
                l10n.assessmentSubtitle,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Aria asks, your learner taps a picture. It takes about two '
                'minutes.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        AppButton(
          label: l10n.actionStart,
          icon: Icons.play_arrow_rounded,
          isExpanded: true,
          onPressed: () => ref.read(assessmentProvider.notifier).begin(),
        ),
        Center(
          child: TextButton(
            onPressed: () async {
              await ref.read(assessmentProvider.notifier).skipAll();
              if (context.mounted) context.go(AppRoutes.home);
            },
            child: Text(l10n.assessmentSkip),
          ),
        ),
      ],
    );
  }
}

class _QuestionStep extends ConsumerStatefulWidget {
  const _QuestionStep();

  @override
  ConsumerState<_QuestionStep> createState() => _QuestionStepState();
}

class _QuestionStepState extends ConsumerState<_QuestionStep> {
  int _burst = 0;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(assessmentProvider);
    final controller = ref.read(assessmentProvider.notifier);
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final question = state.question;
    final chosen = state.answers[state.index];
    final revealed = chosen != null;

    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.assessmentQuestionOf(state.index + 1, state.total),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                BadgePill(
                  label: question.skill.name,
                  icon: Icons.hearing_rounded,
                  tone: BadgeTone.sky,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: (state.index + (revealed ? 1 : 0)) / state.total,
                minHeight: 8,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            AppCard(
              padding: const EdgeInsets.all(AppSpacing.xl),
              color: colors.brand.withValues(alpha: 0.07),
              borderColor: colors.brand.withValues(alpha: 0.22),
              child: Row(
                children: [
                  _SpeakButton(
                    isLoading: state.isPlayingPrompt,
                    onPressed: controller.playPrompt,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Aria asks',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          question.spokenPrompt,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Expanded(
              child: GridView.count(
                crossAxisCount: 1,
                mainAxisSpacing: AppSpacing.md,
                childAspectRatio: 3.1,
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                physics: const ClampingScrollPhysics(),
                children: [
                  for (var i = 0; i < question.options.length; i++)
                    _OptionTile(
                      option: question.options[i],
                      isChosen: chosen == i,
                      isCorrect: revealed && i == question.correctIndex,
                      isWrongChoice: revealed &&
                          chosen == i &&
                          i != question.correctIndex,
                      onTap: revealed ? null : () => controller.answer(i),
                    ),
                ],
              ),
            ),
            AnimatedSize(
              duration: AppMotion.normal,
              child: revealed
                  ? Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.md),
                      child: Column(
                        children: [
                          Text(
                            chosen == question.correctIndex
                                ? 'Yes! ${question.options[chosen].word}'
                                : question.hintForWrong ??
                                    'Listen again and try one more.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(
                                  color: chosen == question.correctIndex
                                      ? colors.success
                                      : colors.inkMuted,
                                ),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          AppButton(
                            label: state.isOnLastQuestion
                                ? l10n.actionFinish
                                : l10n.actionNext,
                            icon: state.isOnLastQuestion
                                ? Icons.celebration_rounded
                                : Icons.arrow_forward_rounded,
                            isExpanded: true,
                            onPressed: () async {
                              if (chosen == question.correctIndex) {
                                setState(() => _burst++);
                              }
                              if (state.isOnLastQuestion) {
                                await controller.finish();
                              } else {
                                await controller.next();
                              }
                            },
                          ),
                        ],
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ],
        ),
        Positioned.fill(child: ConfettiBurst(trigger: _burst)),
      ],
    );
  }
}

class _SpeakButton extends StatelessWidget {
  const _SpeakButton({required this.onPressed, required this.isLoading});

  final VoidCallback onPressed;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return SizedBox(
      height: AppSizes.kidTapTarget,
      width: AppSizes.kidTapTarget,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: colors.brand,
          padding: EdgeInsets.zero,
          shape: const CircleBorder(),
        ),
        child: isLoading
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.volume_up_rounded, color: Colors.white),
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.option,
    required this.isChosen,
    required this.isCorrect,
    required this.isWrongChoice,
    required this.onTap,
  });

  final AssessmentOption option;
  final bool isChosen;
  final bool isCorrect;
  final bool isWrongChoice;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final border = isCorrect
        ? colors.success
        : isWrongChoice
        ? colors.warning
        : isChosen
        ? colors.brand
        : null;

    return PressableCard(
      onTap: onTap,
      radius: 22,
      borderColor: border,
      color: isCorrect
          ? colors.success.withValues(alpha: 0.12)
          : isWrongChoice
          ? colors.warning.withValues(alpha: 0.12)
          : null,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Row(
        children: [
          Text(option.emoji, style: const TextStyle(fontSize: 40)),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Text(
              option.word,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          AnimatedScale(
            duration: AppMotion.normal,
            curve: AppMotion.bouncy,
            scale: (isCorrect || isWrongChoice) ? 1 : 0,
            child: Icon(
              isCorrect ? Icons.check_circle_rounded : Icons.restart_alt_rounded,
              color: isCorrect ? colors.success : colors.warning,
              size: 30,
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultStep extends ConsumerWidget {
  const _ResultStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final state = ref.watch(assessmentProvider);
    final outcome = state.outcome;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.md),
        Text(
          outcome == null ? 'Ready when you are' : 'You are ready for…',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: colors.inkMuted,
              ),
        ),
        const SizedBox(height: AppSpacing.md),
        AppCard(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [colors.brand.withValues(alpha: 0.16), colors.surface],
          ),
          child: Column(
            children: [
              const Text('🏆', style: TextStyle(fontSize: 56)),
              const SizedBox(height: AppSpacing.md),
              Text(
                outcome?.level.label ?? 'Sounds & symbols',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              if (outcome != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  l10n.assessmentResult(outcome.level.label),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: AppSpacing.sm,
                  children: [
                    BadgePill(
                      label: '${outcome.correctCount}/${outcome.total}',
                      icon: Icons.task_alt_rounded,
                      tone: BadgeTone.mint,
                    ),
                    BadgePill(
                      label:
                          '${(outcome.confidence * 100).round()}% sure',
                      icon: Icons.psychology_alt_outlined,
                      tone: BadgeTone.brand,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                for (final note in outcome.notes)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                    child: Text(
                      note,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
              ],
            ],
          ),
        ),
        const Spacer(),
        AppButton(
          label: 'Start learning',
          icon: Icons.rocket_launch_rounded,
          isExpanded: true,
          onPressed: () async {
            await ref.read(assessmentProvider.notifier).completeOnboarding();
            if (context.mounted) context.go(AppRoutes.home);
          },
        ),
      ],
    );
  }
}
