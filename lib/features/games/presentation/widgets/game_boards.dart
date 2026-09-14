import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../shared/widgets/app_card.dart';
import '../../../../theme/app_colors.dart';
import '../../../../theme/app_dimens.dart';
import '../../domain/game_models.dart';

/// The four boards. One widget, four layouts: every game asks the same question
/// ("which choice, and was it right?"), only the *geometry* changes, so a new
/// game is a new layout, not a new state machine.
class GameBoard extends StatelessWidget {
  const GameBoard({
    required this.kind,
    required this.choices,
    required this.selected,
    required this.onPick,
    this.feedbackFor,
    super.key,
  });

  final GameKind kind;
  final List<GameChoice> choices;
  final List<String> selected;
  final ValueChanged<String> onPick;

  /// Marks a choice right/wrong while the round pauses on it.
  final GameChoiceState? Function(GameChoice choice)? feedbackFor;

  @override
  Widget build(BuildContext context) {
    return switch (kind) {
      GameKind.soundMatch => _grid(context, columns: 2, ratio: 1.35),
      GameKind.rhymeRanger => _grid(context, columns: 3, ratio: 0.85),
      GameKind.spellBuilder => _tilesRow(context),
      GameKind.bubblePop => _bubbles(context),
    };
  }

  Widget _grid(BuildContext context, {required int columns, required double ratio}) {
    return GridView.count(
      crossAxisCount: columns,
      mainAxisSpacing: AppSpacing.md,
      crossAxisSpacing: AppSpacing.md,
      childAspectRatio: ratio,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        for (final choice in choices)
          _ChoiceTile(
            choice: choice,
            isSelected: selected.contains(choice.id),
            state: feedbackFor?.call(choice),
            showEmoji: true,
            onTap: () => onPick(choice.id),
          ),
      ],
    );
  }

  Widget _tilesRow(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.md,
      children: [
        for (final choice in choices)
          _ChoiceTile(
            choice: choice,
            isSelected: selected.contains(choice.id),
            state: feedbackFor?.call(choice),
            showEmoji: false,
            onTap: () => onPick(choice.id),
            fixedSize: const Size(64, 72),
          ),
      ],
    );
  }

  Widget _bubbles(BuildContext context) {
    final rng = math.Random(choices.length);
    return SizedBox(
      height: 260,
      child: Stack(
        children: [
          for (var i = 0; i < choices.length; i++)
            Positioned(
              left: 8.0 + (i.isEven ? 0 : 96) + rng.nextInt(40),
              top: 12.0 + (i % 3) * 78 + rng.nextInt(24),
              child: _ChoiceTile(
                choice: choices[i],
                isSelected: selected.contains(choices[i].id),
                state: feedbackFor?.call(choices[i]),
                showEmoji: true,
                isRound: true,
                fixedSize: const Size(150, 68),
                onTap: () => onPick(choices[i].id),
              ),
            ),
        ],
      ),
    );
  }
}

enum GameChoiceState { idle, correct, wrong }

class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.choice,
    required this.isSelected,
    required this.onTap,
    this.state,
    this.showEmoji = true,
    this.isRound = false,
    this.fixedSize,
  });

  final GameChoice choice;
  final bool isSelected;
  final VoidCallback onTap;
  final GameChoiceState? state;
  final bool showEmoji;
  final bool isRound;
  final Size? fixedSize;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final highlighted = state == GameChoiceState.correct
        ? colors.success
        : state == GameChoiceState.wrong
        ? colors.warning
        : isSelected
        ? colors.brand
        : null;

    final tile = AnimatedContainer(
      duration: AppMotion.fast,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(isRound ? 999 : 20),
        border: Border.all(
          color: highlighted ?? colors.inkMuted.withValues(alpha: 0.16),
          width: highlighted == null ? 1 : 3,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (showEmoji && choice.emoji != null) ...[
            Text(choice.emoji!, style: const TextStyle(fontSize: 30)),
            const SizedBox(width: AppSpacing.sm),
          ],
          Flexible(
            child: Text(
              choice.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: showEmoji ? 18 : 28,
                fontWeight: FontWeight.w800,
                color: colors.ink,
              ),
            ),
          ),
        ],
      ),
    );

    return Semantics(
      button: true,
      selected: isSelected,
      label: choice.label,
      child: PressableCard(
        onTap: onTap,
        radius: isRound ? 999 : 20,
        padding: EdgeInsets.zero,
        color: Colors.transparent,
        borderColor: Colors.transparent,
        child: fixedSize == null ? tile : SizedBox(width: fixedSize!.width, height: fixedSize!.height, child: Center(child: tile)),
      ),
    );
  }
}
