import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../theme/app_colors.dart';
import '../../../../theme/app_dimens.dart';

/// Hand-painted charts: three tiny painters instead of a charting package.
/// They scale with text size, respect reduced motion, and cost ~4KB of code.

/// Seven bars — minutes practised per day of the current week.
class WeeklyBars extends StatelessWidget {
  const WeeklyBars({
    required this.minutesByDay,
    this.goalMinutes = 15,
    super.key,
  });

  final List<int> minutesByDay;
  final int goalMinutes;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final max = math.max(goalMinutes, minutesByDay.fold<int>(0, (a, b) => math.max(a, b)));
    return SizedBox(
      height: 132,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < minutesByDay.length; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TweenAnimationBuilder<double>(
                      tween: Tween<double>(
                        begin: 0,
                        end: max == 0 ? 0 : minutesByDay[i] / max,
                      ),
                      duration: AppMotion.slow,
                      builder: (context, value, _) => Expanded(
                        child: Stack(
                          alignment: Alignment.bottomCenter,
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                color: colors.surfaceMuted,
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            FractionallySizedBox(
                              heightFactor: value.clamp(0.0, 1.0),
                              child: Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.bottomCenter,
                                    end: Alignment.topCenter,
                                    colors: [
                                      colors.brand,
                                      colors.grape.withValues(alpha: 0.8),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _dayLabels[i % 7],
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    Text(
                      '${minutesByDay[i]}',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  static const List<String> _dayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
}

/// Two-week practice heatmap, so a parent sees rhythm rather than averages.
class PracticeHeatmap extends StatelessWidget {
  const PracticeHeatmap({required this.minutesByDay, super.key});

  /// Oldest first, 14 entries.
  final List<int> minutesByDay;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Wrap(
      spacing: 5,
      runSpacing: 5,
      children: [
        for (var i = 0; i < minutesByDay.length; i++)
          Tooltip(
            message: '${minutesByDay[i]} min',
            child: Container(
              height: 22,
              width: 22,
              decoration: BoxDecoration(
                color: minutesByDay[i] == 0
                    ? colors.surfaceMuted
                    : colors.brand.withValues(
                        alpha: (0.25 + minutesByDay[i] / 40).clamp(0.25, 1.0),
                      ),
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
      ],
    );
  }
}

/// Accuracy over time for one skill (sound mastery sparkline).
class AccuracySparkline extends StatelessWidget {
  const AccuracySparkline({
    required this.values,
    this.height = 46,
    super.key,
  });

  /// 0..1 values, oldest first.
  final List<double> values;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (values.length < 2) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            'Not enough data yet',
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ),
      );
    }
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _SparklinePainter(
          values: values,
          lineColor: AppColors.of(context).brand,
          fillColor: AppColors.of(context).brand.withValues(alpha: 0.12),
        ),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  const _SparklinePainter({
    required this.values,
    required this.lineColor,
    required this.fillColor,
  });

  final List<double> values;
  final Color lineColor;
  final Color fillColor;

  @override
  void paint(Canvas canvas, Size size) {
    final step = size.width / (values.length - 1);
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final point = Offset(i * step, size.height * (1 - values[i].clamp(0.0, 1.0)));
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    canvas.drawPath(
      path
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close(),
      Paint()..color = fillColor,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_SparklinePainter old) => old.values != values;
}
