import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';

/// Section title + optional trailing action, used by every hub screen so the
/// vertical rhythm stays identical.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    required this.title,
    this.subtitle,
    this.trailing,
    this.leadingIcon,
    this.padding = const EdgeInsets.only(bottom: AppSpacing.md),
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final IconData? leadingIcon;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (leadingIcon case final icon?) ...[
            Icon(icon, size: 20, color: colors.brand),
            const SizedBox(width: AppSpacing.sm),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
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
          if (trailing case final widget?) ...[
            const SizedBox(width: AppSpacing.sm),
            trailing is Text
                ? TextButton(
                    onPressed: () {},
                    child: widget,
                  )
                : widget,
          ],
        ],
      ),
    );
  }
}
