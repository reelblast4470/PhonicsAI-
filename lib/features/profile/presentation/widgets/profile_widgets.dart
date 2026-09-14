import 'package:flutter/material.dart';

import '../../../../core/domain/learner_profile.dart';
import '../../../../core/domain/reading_level.dart';
import '../../../../core/responsive/responsive.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../theme/app_colors.dart';
import '../../../../theme/app_dimens.dart';

/// The buddy picker: a grid of emoji faces sized for small fingers.
class AvatarPicker extends StatelessWidget {
  const AvatarPicker({
    required this.selectedId,
    required this.onSelected,
    this.columns,
    super.key,
  });

  final String selectedId;
  final ValueChanged<String> onSelected;
  final int? columns;

  @override
  Widget build(BuildContext context) {
    final count = columns ??
        (context.breakpoint.isCompact
            ? 4
            : context.breakpoint.index >= Breakpoint.expanded.index
            ? 6
            : 5);
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      itemCount: LearnerAvatar.catalog.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: count,
        mainAxisSpacing: AppSpacing.sm,
        crossAxisSpacing: AppSpacing.sm,
      ),
      itemBuilder: (context, index) {
        final avatar = LearnerAvatar.catalog[index];
        final isSelected = avatar.id == selectedId;
        return Semantics(
          button: true,
          selected: isSelected,
          label: '${avatar.name}${isSelected ? ', selected' : ''}',
          child: PressableCard(
            onTap: () => onSelected(avatar.id),
            radius: 20,
            padding: EdgeInsets.zero,
            borderColor: isSelected ? avatar.tint : null,
            color: isSelected
                ? avatar.tint.withValues(alpha: 0.18)
                : AppColors.of(context).surfaceMuted,
            child: Center(
              child: Text(avatar.emoji, style: const TextStyle(fontSize: 32)),
            ),
          ),
        );
      },
    );
  }
}

/// Birthday-free age input: a big +/− stepper. A parent of a 3-year-old should
/// not have to fight a date picker.
class AgeStepper extends StatelessWidget {
  const AgeStepper({
    required this.ageMonths,
    required this.onChanged,
    super.key,
  });

  final int ageMonths;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final years = ReadingLevel.ageYearsFromMonths(ageMonths);
    final months = ageMonths % 12;
    return Row(
      children: [
        _StepButton(
          icon: Icons.remove_rounded,
          tooltip: 'Younger',
          onPressed: ageMonths <= 24 ? null : () => onChanged(ageMonths - 6),
        ),
        Expanded(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  months == 0 ? '$years' : '$years.$months',
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: colors.ink,
                      ),
                ),
                Text(
                  years == 1 ? 'year old' : 'years old',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        _StepButton(
          icon: Icons.add_rounded,
          tooltip: 'Older',
          onPressed: ageMonths >= 144 ? null : () => onChanged(ageMonths + 6),
        ),
      ],
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AppSizes.kidTapTarget,
      width: AppSizes.kidTapTarget,
      child: IconButton.filledTonal(
        onPressed: onPressed,
        iconSize: 30,
        tooltip: tooltip,
        icon: Icon(icon),
      ),
    );
  }
}

/// A learner row used by the chooser and by the parent area.
class ProfileTile extends StatelessWidget {
  const ProfileTile({
    required this.profile,
    this.isActive = false,
    this.onTap,
    this.onLongPress,
    this.trailing,
    this.compact = false,
    super.key,
  });

  final LearnerProfile profile;
  final bool isActive;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Widget? trailing;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final avatarSize = compact ? 44.0 : 60.0;
    return PressableCard(
      onTap: onTap,
      onLongPress: onLongPress,
      radius: 22,
      padding: const EdgeInsets.all(AppSpacing.md),
      borderColor: isActive ? colors.brand : null,
      color: isActive ? colors.brand.withValues(alpha: 0.06) : null,
      child: Row(
        children: [
          Container(
            height: avatarSize,
            width: avatarSize,
            decoration: BoxDecoration(
              color: profile.avatar.tint.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(avatarSize * 0.32),
            ),
            alignment: Alignment.center,
            child: Text(
              profile.avatar.emoji,
              style: TextStyle(fontSize: avatarSize * 0.56),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  profile.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${profile.ageYears} · ${profile.level.label}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          if (isActive) ...[
            const SizedBox(width: AppSpacing.sm),
            Icon(Icons.check_circle_rounded, color: colors.brand, size: 24),
          ],
          ?trailing,
        ],
      ),
    );
  }
}

/// Level selector used when a family skips the placement check-up.
class LevelPicker extends StatelessWidget {
  const LevelPicker({
    required this.selected,
    required this.onSelected,
    this.suggested,
    super.key,
  });

  final ReadingLevel selected;
  final ValueChanged<ReadingLevel> onSelected;
  final ReadingLevel? suggested;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final level in ReadingLevel.values)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: _LevelRow(
              level: level,
              isSelected: level == selected,
              isSuggested: level == suggested,
              onTap: () => onSelected(level),
            ),
          ),
      ],
    );
  }
}

class _LevelRow extends StatelessWidget {
  const _LevelRow({
    required this.level,
    required this.isSelected,
    required this.isSuggested,
    required this.onTap,
  });

  final ReadingLevel level;
  final bool isSelected;
  final bool isSuggested;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return PressableCard(
      onTap: onTap,
      radius: 18,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      borderColor: isSelected ? colors.brand : null,
      child: Row(
        children: [
          Container(
            height: 26,
            width: 26,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isSelected ? colors.brand : Colors.transparent,
              border: Border.all(
                color: isSelected ? colors.brand : colors.inkMuted,
                width: 2,
              ),
            ),
            child: isSelected
                ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
                : null,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        level.label,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    if (isSuggested) ...[
                      const SizedBox(width: AppSpacing.sm),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: colors.mint.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'suggested',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: colors.mint,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                Text(
                  level.blurb,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
