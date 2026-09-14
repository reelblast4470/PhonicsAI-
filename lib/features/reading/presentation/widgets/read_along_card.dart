import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/badge_pill.dart';
import '../../../../theme/app_colors.dart';
import '../../../../theme/app_dimens.dart';
import '../../../audio/tts_bridge.dart';
import '../../domain/reading_models.dart';

/// The read-aloud card: tap a word you stumbled on, then read it again.
///
/// Deliberately microphone-optional. Forced speech is a bad fit for a shy
/// 4-year-old and for shared family tablets, so the adult can mark stumbles by
/// tapping; the mic path ([SayItCard]) is used where a learner wants it.
class ReadAlongCard extends ConsumerStatefulWidget {
  const ReadAlongCard({
    required this.passage,
    this.onAttempt,
    this.autoAdvance = false,
    super.key,
  });

  final DecodablePassage passage;
  final void Function(ReadingAttempt attempt)? onAttempt;

  /// Lesson stages finish themselves; the standalone reader shows a summary.
  final bool autoAdvance;

  @override
  ConsumerState<ReadAlongCard> createState() => ReadAlongCardState();
}

@visibleForTesting
class ReadAlongCardState extends ConsumerState<ReadAlongCard> {
  late final ReadingTally _tally =
      ReadingTally(passage: widget.passage, startedAt: DateTime.now());
  final Map<int, int> _marks = {};
  int? _highlighted;
  bool _finished = false;
  ReadingAttempt? _result;

  @override
  void dispose() {
    super.dispose();
  }

  void _tapWord(int index, String word) {
    unawaited(ref.read(ttsBridgeProvider).say(word));
    setState(() {
      _highlighted = index;
      _marks[index] = (_marks[index] ?? 0) + 1;
      if (_marks[index]! > 1) {
        _tally.markSelfCorrection(index);
      } else {
        _tally.markError(index);
      }
    });
  }

  void _finish() {
    _tally.finish();
    final attempt = _tally.toAttempt();
    setState(() {
      _finished = true;
      _result = attempt;
    });
    widget.onAttempt?.call(attempt);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final words = widget.passage.words;

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                widget.passage.emoji,
                style: const TextStyle(fontSize: 28),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  widget.passage.title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              BadgePill(
                label: '${words.length} words',
                icon: Icons.text_fields_rounded,
                tone: BadgeTone.neutral,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          for (var sentence = 0; sentence < widget.passage.sentences.length; sentence++)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Wrap(
                spacing: 10,
                runSpacing: 12,
                alignment: WrapAlignment.start,
                children: [
                  for (var i = _startOf(sentence);
                      i < _startOf(sentence + 1);
                      i++) ...[
                    _WordChip(
                      word: words[i],
                      isMarked: (_marks[i] ?? 0) > 0,
                      isCurrent: _highlighted == i,
                      onTap: () => _tapWord(i, words[i]),
                    ),
                  ],
                ],
              ),
            ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Tap a word you stumbled on, then tap it again when you fix it.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (_result case final attempt?) ...[
            const SizedBox(height: AppSpacing.lg),
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: colors.surfaceMuted,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  Text(
                    l10n.readingFinished,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      BadgePill(
                        label: l10n.readingWpm(attempt.wordsPerMinute),
                        icon: Icons.speed_rounded,
                        tone: BadgeTone.brand,
                      ),
                      BadgePill(
                        label: l10n.readingAccuracy(
                          (attempt.accuracy * 100).round(),
                        ),
                        icon: Icons.check_circle_outline_rounded,
                        tone: BadgeTone.mint,
                      ),
                      if (attempt.selfCorrections > 0)
                        BadgePill(
                          label: l10n.readingSelfCorrect(
                            attempt.selfCorrections,
                          ),
                          icon: Icons.restart_alt_rounded,
                          tone: BadgeTone.sun,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          if (!_finished)
            AppButton(
              label: l10n.actionFinish,
              icon: Icons.done_all_rounded,
              isExpanded: true,
              isCompact: !widget.autoAdvance,
              onPressed: _finish,
            )
          else
            AppButton(
              label: l10n.actionTryAgain,
              icon: Icons.refresh_rounded,
              tone: AppButtonTone.neutral,
              isExpanded: true,
              isCompact: true,
              onPressed: () => setState(() {
                _marks.clear();
                _finished = false;
                _result = null;
              }),
            ),
        ],
      ),
    );
  }

  int _startOf(int sentenceIndex) {
    var count = 0;
    for (var i = 0; i < sentenceIndex; i++) {
      count += widget.passage.sentences[i].split(' ').length;
    }
    return count;
  }
}

class _WordChip extends StatelessWidget {
  const _WordChip({
    required this.word,
    required this.isMarked,
    required this.isCurrent,
    required this.onTap,
  });

  final String word;
  final bool isMarked;
  final bool isCurrent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Material(
      color: isMarked
          ? colors.warning.withValues(alpha: 0.18)
          : isCurrent
          ? colors.brand.withValues(alpha: 0.12)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: Text(
            word,
            style: TextStyle(
              fontSize: 26,
              fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w600,
              color: colors.ink,
              decoration: isMarked
                  ? TextDecoration.underline
                  : TextDecoration.none,
              decorationColor: colors.warning,
            ),
          ),
        ),
      ),
    );
  }
}
