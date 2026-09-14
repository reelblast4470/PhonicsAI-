import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

/// Circular mastery ring. CustomPaint (not `CircularProgressIndicator`) so it
/// can animate toward a target value and draw per-lesson tick marks.
class ProgressRing extends StatelessWidget {
  const ProgressRing({
    required this.value,
    this.size = 88,
    this.strokeWidth = 10,
    this.label,
    this.subLabel,
    this.color,
    this.segments,
    super.key,
  });

  /// 0..1
  final double value;
  final double size;
  final double strokeWidth;
  final String? label;
  final String? subLabel;
  final Color? color;

  /// Optional tick marks around the ring (e.g. one per lesson in a unit).
  final int? segments;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final clamped = value.clamp(0.0, 1.0);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: clamped),
      duration: const Duration(milliseconds: 520),
      curve: Curves.easeOutCubic,
      builder: (context, animated, _) => SizedBox(
        height: size,
        width: size,
        child: CustomPaint(
          painter: _RingPainter(
            value: animated,
            color: color ?? colors.brand,
            track: colors.surfaceMuted,
            strokeWidth: strokeWidth,
            segments: segments,
            segmentColor: colors.brand.withValues(alpha: 0.35),
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label ?? '${(clamped * 100).round()}%',
                  style: TextStyle(
                    fontSize: size * 0.24,
                    fontWeight: FontWeight.w800,
                    color: colors.ink,
                    height: 1.05,
                  ),
                ),
                if (subLabel case final sub?)
                  Text(
                    sub,
                    style: TextStyle(
                      fontSize: size * 0.11,
                      fontWeight: FontWeight.w600,
                      color: colors.inkMuted,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.value,
    required this.color,
    required this.track,
    required this.strokeWidth,
    required this.segments,
    required this.segmentColor,
  });

  final double value;
  final Color color;
  final Color track;
  final double strokeWidth;
  final int? segments;
  final Color segmentColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (math.min(size.width, size.height) - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    canvas.drawArc(
      rect,
      0,
      2 * math.pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..color = track,
    );

    if (value > 0) {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        2 * math.pi * value,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round
          ..color = color,
      );
    }

    if (segments case final count? when count > 1) {
      final tick = Paint()
        ..color = segmentColor
        ..strokeWidth = 2;
      for (var i = 0; i < count; i++) {
        final angle = (2 * math.pi * i / count) - math.pi / 2;
        final outer = radius + strokeWidth / 2 + 2;
        final inner = outer + 5;
        canvas.drawLine(
          center + Offset(math.cos(angle) * outer, math.sin(angle) * outer),
          center + Offset(math.cos(angle) * inner, math.sin(angle) * inner),
          tick,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value ||
      old.color != color ||
      old.segments != segments ||
      old.track != track;
}
