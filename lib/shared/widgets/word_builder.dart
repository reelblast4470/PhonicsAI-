import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';

/// Letter-tile word builder: tap tiles to fill the slots, tap a slot to pop the
/// letter back. Used by the lesson "practice" stage, the games and the writing
/// screen, so the interaction is learned exactly once.
class WordBuilder extends StatelessWidget {
  const WordBuilder({
    required this.target,
    required this.tiles,
    required this.selected,
    required this.onTileTapped,
    required this.onSlotTapped,
    this.isChecked = false,
    this.isCorrect = false,
    super.key,
  });

  final String target;
  final List<String> tiles;
  final List<int> selected;
  final void Function(int tileIndex) onTileTapped;
  final void Function(int slotIndex) onSlotTapped;
  final bool isChecked;
  final bool isCorrect;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final used = {...selected};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < target.length; i++)
              Padding(
                padding: const EdgeInsets.only(right: AppSpacing.sm),
                child: _Slot(
                  letter: i < selected.length ? tiles[selected[i]] : null,
                  isWrong: isChecked && !isCorrect,
                  isRight: isChecked && isCorrect,
                  onTap: () => onSlotTapped(i),
                ),
              ),
            if (isChecked)
              Icon(
                isCorrect ? Icons.check_circle_rounded : Icons.autorenew_rounded,
                color: isCorrect ? colors.success : colors.warning,
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (var i = 0; i < tiles.length; i++)
              Opacity(
                opacity: used.contains(i) ? 0.25 : 1,
                child: _Tile(
                  letter: tiles[i],
                  onTap: used.contains(i) ? null : () => onTileTapped(i),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _Slot extends StatelessWidget {
  const _Slot({
    required this.letter,
    required this.isWrong,
    required this.isRight,
    required this.onTap,
  });

  final String? letter;
  final bool isWrong;
  final bool isRight;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final background = isRight
        ? colors.success.withValues(alpha: 0.18)
        : isWrong
        ? colors.error.withValues(alpha: 0.16)
        : colors.surfaceMuted;
    return SizedBox(
      height: 58,
      width: 46,
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Center(
            child: letter == null
                ? Container(
                    height: 8,
                    width: 22,
                    decoration: BoxDecoration(
                      color: colors.inkMuted.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  )
                : Text(
                    letter!,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.letter, required this.onTap});

  final String letter;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return SizedBox(
      height: AppSizes.kidTapTarget,
      width: 56,
      child: FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: colors.surface,
          foregroundColor: colors.ink,
          elevation: 1,
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: colors.inkMuted.withValues(alpha: 0.25)),
          ),
        ),
        child: Text(
          letter,
          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}
