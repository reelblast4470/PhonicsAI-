import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/responsive/responsive.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/feedback/app_toast.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/kid_scaffold.dart';
import '../../../shared/widgets/word_builder.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_dimens.dart';
import '../../audio/tts_bridge.dart';
import '../../progress/application/progress_providers.dart';
import '../application/writing_controller.dart';
import 'widgets/tracing_board.dart';

/// Write it — trace the letter, then build the word. Two halves of the same
/// lesson: fine motor practice and sound-to-spelling recall.
class WritingScreen extends ConsumerWidget {
  const WritingScreen({required this.targetId, super.key});

  final String targetId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(writingControllerProvider(targetId));
    final controller = ref.read(writingControllerProvider(targetId).notifier);

    return KidScaffold(
      title: l10n.writingTitle,
      actions: [
        IconButton(
          onPressed: () async {
            await controller.save();
            if (context.mounted) {
              AppToast.show(context, l10n.writingStrokesSaved,
                  icon: Icons.bookmark_added_rounded);
              context.pop();
            }
          },
          icon: const Icon(Icons.check_rounded),
          tooltip: l10n.actionDone,
        ),
      ],
      body: switch (state) {
        WritingStateLoading() => const Center(child: CircularProgressIndicator()),
        WritingStateMissing() => AppCard(
            child: Column(
              children: [
                const Icon(Icons.help_outline_rounded, size: 34),
                const SizedBox(height: AppSpacing.md),
                Text('We could not find "$targetId" in your lesson.'),
                const SizedBox(height: AppSpacing.lg),
                AppButton(
                  label: l10n.actionBack,
                  isCompact: true,
                  onPressed: () => context.pop(),
                ),
              ],
            ),
          ),
        final WritingReady ready => _ReadyView(
            ready: ready,
            controller: controller,
            l10n: l10n,
          ),
      },
    );
  }
}

class _ReadyView extends ConsumerWidget {
  const _ReadyView({
    required this.ready,
    required this.controller,
    required this.l10n,
  });

  final WritingReady ready;
  final WritingController controller;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: SegmentedButton<WritingMode>(
                segments: const [
                  ButtonSegment(
                    value: WritingMode.trace,
                    label: Text('Trace'),
                    icon: Icon(Icons.draw_rounded),
                  ),
                  ButtonSegment(
                    value: WritingMode.spell,
                    label: Text('Build'),
                    icon: Icon(Icons.view_quilt_rounded),
                  ),
                ],
                selected: {ready.mode},
                showSelectedIcon: false,
                onSelectionChanged: (values) => controller.setMode(values.first),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        if (ready.mode == WritingMode.trace) ...[
          Text(
            l10n.writingTrace,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.sm),
          TracingBoard(
            glyph: ready.glyph,
            wordHint: ready.spelling.word,
            height: context.breakpoint.isCompact ? 240 : 320,
            onScore: (score) {
              controller.recordTrace(score);
              if (score.passed) {
                unawaited(ref.read(ttsBridgeProvider).celebrate());
                unawaited(
                  ref.read(progressRepositoryProvider).recordSoundReview(
                    profileId: ref.read(activeProfileIdProvider) ?? '',
                    phoneme: ready.glyph.toLowerCase(),
                    grade: 4,
                  ),
                );
              }
            },
          ),
        ] else ...[
          AppCard(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              children: [
                Text(
                  ready.spelling.emoji,
                  style: const TextStyle(fontSize: 56),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  ready.spelling.prompt,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.lg),
                WordBuilder(
                  target: ready.spelling.word,
                  tiles: ready.tiles,
                  selected: ready.picked,
                  isChecked: ready.isChecked,
                  isCorrect: ready.isSpellingCorrect,
                  onTileTapped: controller.pickTile,
                  onSlotTapped: controller.unpick,
                ),
                const SizedBox(height: AppSpacing.lg),
                Row(
                  children: [
                    Expanded(
                      child: AppButton(
                        label: l10n.actionCheck,
                        tone: AppButtonTone.sun,
                        isExpanded: true,
                        isCompact: true,
                        onPressed: ready.picked.length ==
                                ready.spelling.word.length
                            ? controller.checkSpelling
                            : null,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    IconButton(
                      onPressed: () => ref
                          .read(ttsBridgeProvider)
                          .say(ready.spelling.word),
                      icon: const Icon(Icons.volume_up_rounded, size: 28),
                      tooltip: l10n.actionListen,
                    ),
                  ],
                ),
                if (ready.isChecked)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.md),
                    child: Text(
                      ready.isSpellingCorrect
                          ? l10n.writingCorrect
                          : '${l10n.writingNearMiss} — the letters are '
                              '${ready.spelling.word.split('').join(' ')}',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: ready.isSpellingCorrect
                                ? colors.success
                                : colors.warning,
                          ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
