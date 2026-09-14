import 'package:flutter/material.dart';

import '../../../../shared/widgets/app_card.dart';
import '../../../../theme/app_colors.dart';
import '../../../../theme/app_dimens.dart';

/// A radio-style row that is big enough for a child-sized finger but calm
/// enough for a settings list.
class LanguageOption extends StatelessWidget {
  const LanguageOption({
    required this.title,
    required this.isSelected,
    required this.onTap,
    this.subtitle,
    super.key,
  });

  final String title;
  final String? subtitle;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: PressableCard(
        onTap: onTap,
        radius: 18,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        borderColor: isSelected ? colors.brand : null,
        color: isSelected ? colors.brand.withValues(alpha: 0.07) : null,
        semanticLabel: '$title${isSelected ? ', selected' : ''}',
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (subtitle case final sub?) ...[
                    const SizedBox(height: 2),
                    Text(
                      sub,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
            AnimatedContainer(
              duration: AppMotion.fast,
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
                  ? const Icon(Icons.check_rounded, size: 18, color: Colors.white)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
