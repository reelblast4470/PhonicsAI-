import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/app_routes.dart';
import '../../../../core/responsive/responsive.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/badge_pill.dart';
import '../../../../shared/widgets/word_builder.dart';
import '../../../../theme/app_colors.dart';
import '../../../../theme/app_dimens.dart';
import '../../../audio/tts_bridge.dart';
import '../../../games/domain/game_models.dart';
import '../../../pronunciation/presentation/widgets/say_it_card.dart';
import '../../../reading/data/reading_library.dart';
import '../../../reading/presentation/widgets/read_along_card.dart';
import '../../application/lesson_runner.dart';
import '../../data/phonics_program.dart';
import '../../domain/lesson.dart';

/// One widget per stage kind. They receive the run state and call the runner;
/// no stage owns business rules, which is what keeps all ten consistent (and
/// lets a stage be reordered or dropped in content without a UI change).
class StageRenderer extends ConsumerWidget {
  const StageRenderer({required this.state, super.key});

  final LessonRunState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final runner = ref.read(lessonRunProvider(state.lesson.id).notifier);
    final stage = state.stage;

    return switch (stage.kind) {
      StageKind.discover => _Discover(stage: stage, runner: runner),
      StageKind.hear => _Choices(stage: stage, state: state, runner: runner),
      StageKind.recall => _Choices(
          stage: stage,
          state: state,
          runner: runner,
          mode: _ChoiceMode.flashcard,
        ),
      StageKind.see => _See(stage: stage, runner: runner),
      StageKind.understand => _Understand(stage: stage),
      StageKind.practice => _Practice(stage: stage, state: state, runner: runner),
      StageKind.play => _Play(state: state),
      StageKind.speak => _Speak(stage: stage, state: state, runner: runner),
      StageKind.read => _Read(stage: stage, state: state, runner: runner),
      StageKind.review => _Review(stage: stage, state: state),
    };
  }
}

class _StagePrompt extends StatelessWidget {
  const _StagePrompt({required this.text, this.canListen = false});

  final String text;
  final bool canListen;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                ),
          ),
        ),
        if (canListen)
          IconButton(
            // Fire-and-forget: audio is never on the critical path of a tap.
            onPressed: () => ProviderScope.containerOf(context)
                .read(ttsBridgeProvider)
                .say(text)
                .ignore(),
            icon: const Icon(Icons.volume_up_rounded),
            tooltip: 'Hear it',
          ),
      ],
    );
  }
}

class _Discover extends StatelessWidget {
  const _Discover({required this.stage, required this.runner});

  final LessonStage stage;
  final LessonRunner runner;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final item = stage.items.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (stage.introText case final intro?)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Text(intro, style: Theme.of(context).textTheme.bodyMedium),
          ),
        AppCard(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          color: colors.surface,
          child: Column(
            children: [
              Text(
                item.emoji ?? '🔎',
                style: TextStyle(fontSize: 96 * context.displayScale),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                item.text ?? '',
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                    ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                item.prompt,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.lg),
              AppButton(
                label: 'Hear them',
                icon: Icons.volume_up_rounded,
                tone: AppButtonTone.sun,
                isCompact: true,
                onPressed: () =>
                    runner.markItemCorrect(item.id).ignore(),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

enum _ChoiceMode { direct, flashcard }

class _Choices extends ConsumerStatefulWidget {
  const _Choices({
    required this.stage,
    required this.state,
    required this.runner,
    this.mode = _ChoiceMode.direct,
  });

  final LessonStage stage;
  final LessonRunState state;
  final LessonRunner runner;
  final _ChoiceMode mode;

  @override
  ConsumerState<_Choices> createState() => _ChoicesState();
}

class _ChoicesState extends ConsumerState<_Choices> {
  int _flippedIndex = -1;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final items = widget.stage.items;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.xl),
          _StagePrompt(text: items[i].prompt, canListen: true),
          const SizedBox(height: AppSpacing.md),
          if (widget.mode == _ChoiceMode.flashcard && _flippedIndex != i)
            PressableCard(
              onTap: () => setState(() => _flippedIndex = i),
              radius: 26,
              padding: const EdgeInsets.all(AppSpacing.xxxl),
              color: colors.brand.withValues(alpha: 0.06),
              child: Center(
                child: Column(
                  children: [
                    Text(
                      items[i].text ?? '?',
                      style: TextStyle(
                        fontSize: 72 * context.displayScale,
                        fontWeight: FontWeight.w900,
                        color: colors.ink,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text('Tap to flip',
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            )
          else
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.md,
              children: [
                for (var choice = 0; choice < items[i].options.length; choice++)
                  _AnswerButton(
                    label: items[i].options[choice],
                    emoji: PhonicsProgram.emojiFor(items[i].options[choice]),
                    outcome: widget.state.outcomeOf(items[i].id),
                    isChosen: _isChosen(items[i].id, choice),
                    isCorrectChoice:
                        (widget.state.revealedCorrectIndex[items[i].id] ??
                                items[i].correctIndex) ==
                            choice,
                    onTap: () {
                      widget.runner
                          .answerChoice(items[i].id, choice)
                          .ignore();
                    },
                    onRetry: () =>
                        widget.runner.retryItem(items[i].id).ignore(),
                  ),
              ],
            ),
        ],
        if (items.isEmpty) Text(l10n.stateEmptyGeneric),
      ],
    );
  }

  bool _isChosen(String itemId, int choice) {
    // The runner stores correctness, not indices; the flashcard path only needs
    // "answered" to grey the card out.
    return widget.state.outcomeOf(itemId) != ItemOutcome.unanswered;
  }
}

class _AnswerButton extends StatelessWidget {
  const _AnswerButton({
    required this.label,
    required this.outcome,
    required this.isChosen,
    required this.isCorrectChoice,
    required this.onTap,
    required this.onRetry,
    this.emoji,
  });

  final String label;
  final String? emoji;
  final ItemOutcome outcome;
  final bool isChosen;
  final bool isCorrectChoice;
  final VoidCallback onTap;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final revealed = outcome != ItemOutcome.unanswered;
    final showRight = revealed && isCorrectChoice;
    final showWrong = revealed && isChosen && !isCorrectChoice;

    return SizedBox(
      width: 168,
      height: 96,
      child: PressableCard(
        onTap: showWrong ? onRetry : (revealed ? () {} : onTap),
        radius: 22,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        borderColor: showRight
            ? colors.success
            : showWrong
            ? colors.warning
            : null,
        color: showRight
            ? colors.success.withValues(alpha: 0.14)
            : showWrong
            ? colors.warning.withValues(alpha: 0.14)
            : null,
        child: Row(
          children: [
            if (emoji case final e?) ...[
              Text(e, style: const TextStyle(fontSize: 30)),
              const SizedBox(width: AppSpacing.sm),
            ],
            Expanded(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ),
            if (showRight) const Icon(Icons.check_circle_rounded),
            if (showWrong) const Icon(Icons.restart_alt_rounded),
          ],
        ),
      ),
    );
  }
}

class _See extends StatelessWidget {
  const _See({required this.stage, required this.runner});

  final LessonStage stage;
  final LessonRunner runner;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (stage.introText case final intro?)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Text(intro, style: Theme.of(context).textTheme.bodyMedium),
          ),
        for (final item in stage.items)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: AppCard(
              child: Row(
                children: [
                  Container(
                    height: 92,
                    width: 92,
                    decoration: BoxDecoration(
                      color: colors.surfaceMuted,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          item.text ?? '',
                          style: const TextStyle(
                            fontSize: 44,
                            fontWeight: FontWeight.w900,
                            height: 1,
                          ),
                        ),
                        Text(
                          (item.text ?? '').toLowerCase(),
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(
                    child: Text(
                      item.prompt,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton.filledTonal(
                    onPressed: () {
                      runner.markItemCorrect(item.id).ignore();
                      context.push(AppRoutes.writingTrace(item.text ?? ''));
                    },
                    icon: const Icon(Icons.edit_rounded),
                    tooltip: 'Trace it',
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _Understand extends StatelessWidget {
  const _Understand({required this.stage});

  final LessonStage stage;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final item = stage.items.first;
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [colors.sky.withValues(alpha: 0.14), colors.surface],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const BadgePill(label: 'The rule', tone: BadgeTone.sky),
          const SizedBox(height: AppSpacing.lg),
          Text(
            item.prompt,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  height: 1.25,
                ),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (item.text case final examples?)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: colors.surfaceMuted,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                examples,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      letterSpacing: 0.5,
                    ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Practice extends ConsumerWidget {
  const _Practice({
    required this.stage,
    required this.state,
    required this.runner,
  });

  final LessonStage stage;
  final LessonRunState state;
  final LessonRunner runner;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = stage.items[state.stageItemsAllCorrect ? 0 : _activeIndex];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StagePrompt(
          text: '${item.prompt}  ${item.emoji ?? ''}',
          canListen: true,
        ),
        const SizedBox(height: AppSpacing.lg),
        WordBuilder(
          target: item.targetWord?.toUpperCase() ?? '',
          tiles: item.letters ?? const <String>[],
          selected: (state.buildAttempts[item.id] ?? const <String>[])
              .map((letter) => (item.letters ?? const <String>[]).indexOf(letter))
              .where((index) => index >= 0)
              .toList(),
          isChecked: state.outcomeOf(item.id) != ItemOutcome.unanswered,
          isCorrect: state.outcomeOf(item.id) == ItemOutcome.correct,
          onTileTapped: (index) {
            final letter = (item.letters ?? const <String>[])[index];
            runner.toggleLetter(item.id, letter);
          },
          onSlotTapped: (slotIndex) {
            final picked = state.buildAttempts[item.id] ?? const <String>[];
            if (slotIndex < picked.length) {
              runner.toggleLetter(item.id, picked[slotIndex]);
            }
          },
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            Expanded(
              child: AppButton(
                label: 'Check',
                tone: AppButtonTone.sun,
                isExpanded: true,
                isCompact: true,
                onPressed: () => runner.checkBuild(item.id).ignore(),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            AppButton(
              label: 'Next word',
              icon: Icons.arrow_forward_rounded,
              tone: AppButtonTone.neutral,
              isCompact: true,
              onPressed: () => _advance(),
            ),
          ],
        ),
        if (state.stage.items.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.md),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < state.stage.items.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Container(
                      height: 8,
                      width: i == _activeIndex ? 22 : 8,
                      decoration: BoxDecoration(
                        color: state.outcomeOf(state.stage.items[i].id) ==
                                ItemOutcome.correct
                            ? AppColors.of(context).success
                            : i == _activeIndex
                                ? AppColors.of(context).brand
                                : AppColors.of(context).inkMuted
                                    .withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  int get _activeIndex {
    final items = state.stage.items;
    for (var i = 0; i < items.length; i++) {
      if (state.outcomeOf(items[i].id) != ItemOutcome.correct) return i;
    }
    return items.length - 1;
  }

  void _advance() {
    if (_activeIndex >= state.stage.items.length - 1) {
      runner.nextStage().ignore();
    } else {
      runner.markItemCorrect(state.stage.items[_activeIndex].id).ignore();
    }
  }
}

class _Play extends ConsumerWidget {
  const _Play({required this.state});

  final LessonRunState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final games = GameDefinition.catalog.take(3).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.stage.introText case final intro?)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Text(intro, style: Theme.of(context).textTheme.bodyMedium),
          ),
        for (final game in games)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: PressableCard(
              onTap: () async {
                await context.push(
                  AppRoutes.gameSession(game.kind.name),
                );
                if (context.mounted) {
                  ref
                      .read(lessonRunProvider(state.lesson.id).notifier)
                      .markItemCorrect('game_done')
                      .ignore();
                }
              },
              radius: 20,
              child: Row(
                children: [
                  Text(game.emoji, style: const TextStyle(fontSize: 32)),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(game.title,
                            style: Theme.of(context).textTheme.titleMedium),
                        Text(game.blurb,
                            style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                  const Icon(Icons.play_circle_fill_rounded, size: 28),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _Speak extends ConsumerWidget {
  const _Speak({required this.stage, required this.state, required this.runner});

  final LessonStage stage;
  final LessonRunState state;
  final LessonRunner runner;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final words = stage.items
        .map((item) => item.targetWord ?? item.text ?? '')
        .where((word) => word.isNotEmpty)
        .toList();
    final target = words.isEmpty ? (stage.wordId ?? 'sun') : words.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (stage.introText case final intro?)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Text(intro, style: Theme.of(context).textTheme.bodyMedium),
          ),
        SayItCard(
          targetWord: target,
          onScored: (score) {
            if (score.overall >= 0.5) {
              runner.markItemCorrect(target).ignore();
            }
          },
        ),
        if (words.length > 1) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            'Then try: ${words.skip(1).join(', ')}',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}

class _Read extends ConsumerWidget {
  const _Read({required this.stage, required this.state, required this.runner});

  final LessonStage stage;
  final LessonRunState state;
  final LessonRunner runner;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final passage = ReadingLibrary.byId(stage.passageId);
    if (passage == null) {
      return AppCard(
        child: Column(
          children: [
            const Text('This story is still on its way to the device.'),
            const SizedBox(height: AppSpacing.md),
            AppButton(
              label: 'Skip for now',
              isCompact: true,
              onPressed: () => runner.nextStage().ignore(),
            ),
          ],
        ),
      );
    }
    return ReadAlongCard(
      passage: passage,
      autoAdvance: true,
      onAttempt: (attempt) {
        if (attempt.accuracy >= 0.7) {
          runner.markItemCorrect('read_sentence').ignore();
        }
      },
    );
  }
}

class _Review extends StatelessWidget {
  const _Review({required this.stage, required this.state});

  final LessonStage stage;
  final LessonRunState state;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final l10n = AppLocalizations.of(context);
    final item = stage.items.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Column(
            children: [
              Text(
                l10n.learnStageReview,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: colors.inkMuted,
                    ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                item.prompt,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                item.text ?? '',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.lg),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: AppSpacing.sm,
                children: [
                  for (final phoneme in state.lesson.phonemes)
                    BadgePill(
                      label: phoneme,
                      icon: Icons.record_voice_over_outlined,
                      tone: BadgeTone.brand,
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'You answered ${state.correctCount} of ${state.answeredCount} right.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
