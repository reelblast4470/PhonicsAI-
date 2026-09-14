import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';

/// Small status chip: streaks, star counts, level badges, lock states.
class BadgePill extends StatelessWidget {
  const BadgePill({
    required this.label,
    this.icon,
    this.tone = BadgeTone.neutral,
    this.color,
    this.onTap,
    this.isSolid = false,
    super.key,
  });

  const BadgePill.stars(this.label, {super.key, this.icon = Icons.star_rounded})
    : tone = BadgeTone.sun,
      color = null,
      onTap = null,
      isSolid = false;

  final String label;
  final IconData? icon;
  final BadgeTone tone;
  final Color? color;
  final VoidCallback? onTap;
  final bool isSolid;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final base = color ??
        switch (tone) {
          BadgeTone.brand => colors.brand,
          BadgeTone.sun => colors.sunshine,
          BadgeTone.mint => colors.mint,
          BadgeTone.sky => colors.sky,
          BadgeTone.flame => colors.streakFlame,
          BadgeTone.neutral => colors.inkMuted,
          BadgeTone.danger => colors.error,
        };
    final bg = isSolid ? base : base.withValues(alpha: 0.14);
    final fg = isSolid ? AppColors.contrastOn(base) : base;

    final pill = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: 6,
      ),
      decoration: BoxDecoration(color: bg, borderRadius: AppRadius.pill),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon case final i?) ...[
            Icon(i, size: 16, color: fg),
            const SizedBox(width: 6),
          ],
          // Flexible, so a long label ellipsises instead of overflowing the
          // row it sits in (a 360dp phone finds out immediately).
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: fg,
                fontSize: 13,
                fontWeight: FontWeight.w800,
                height: 1.2,
              ),
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return Semantics(label: label, child: pill);
    return Material(
      color: Colors.transparent,
      borderRadius: AppRadius.pill,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.pill,
        child: pill,
      ),
    );
  }
}

enum BadgeTone { brand, sun, mint, sky, flame, neutral, danger }
