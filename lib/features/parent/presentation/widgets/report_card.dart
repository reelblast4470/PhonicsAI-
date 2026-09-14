import 'package:flutter/material.dart';

import '../../../../theme/app_colors.dart';
import '../../../../theme/app_dimens.dart';

/// Two labelled bars: what is going well, what needs practice. The parent
/// report is the one screen where density is the right call.
class ReportBars extends StatelessWidget {
  const ReportBars({required this.strengths, required this.needsWork, super.key});

  final List<String> strengths;
  final List<String> needsWork;

  @override
  Widget build(BuildContext context) {
    if (strengths.isEmpty && needsWork.isEmpty) {
      return Text(
        'Practise a few lessons and this fills in.',
        style: Theme.of(context).textTheme.bodySmall,
      );
    }
    final colors = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (strengths.isNotEmpty)
          _Group(
            title: 'Going well',
            items: strengths,
            color: colors.success,
            icon: Icons.thumb_up_alt_outlined,
          ),
        if (needsWork.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: _Group(
              title: 'Needs practice',
              items: needsWork,
              color: colors.warning,
              icon: Icons.build_outlined,
            ),
          ),
      ],
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({
    required this.title,
    required this.items,
    required this.color,
    required this.icon,
  });

  final String title;
  final List<String> items;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(title, style: Theme.of(context).textTheme.labelMedium),
          ],
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final item in items)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  item,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
