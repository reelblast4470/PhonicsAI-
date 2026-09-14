import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';

/// 0..3 reward stars with a pop-in animation (skipped when reduce-motion is on).
class StarRow extends StatelessWidget {
  const StarRow({
    required this.earned,
    this.total = 3,
    this.size = 28,
    this.spacing = AppSpacing.xs,
    this.animate = true,
    super.key,
  });

  final int earned;
  final int total;
  final double size;
  final double spacing;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final motionOff = animate && AppMotion.disabled(context);
    return Semantics(
      label: '$earned of $total stars',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < total; i++)
            Padding(
              padding: EdgeInsets.only(right: i == total - 1 ? 0 : spacing),
              child: AnimatedScale(
                scale: i < earned ? 1 : 0.86,
                duration: motionOff ? Duration.zero : AppMotion.celebrate,
                curve: Curves.easeOutBack,
                child: Icon(
                  i < earned ? Icons.star_rounded : Icons.star_outline_rounded,
                  size: size,
                  color: i < earned ? colors.gold : colors.inkMuted.withValues(alpha: 0.4),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
