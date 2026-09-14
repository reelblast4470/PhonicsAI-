import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';

/// Dependency-free celebration: a fixed number of particles drawn on one
/// canvas, auto-removed, and skipped entirely when the OS asks to reduce
/// motion. Cheaper than a package and safe on the low-end Android devices this
/// app targets.
class ConfettiBurst extends StatefulWidget {
  const ConfettiBurst({
    required this.trigger,
    this.particleCount = 36,
    this.duration = const Duration(milliseconds: 1200),
    super.key,
  });

  /// Bump this value to fire a burst; the same value never re-fires.
  final int trigger;
  final int particleCount;
  final Duration duration;

  @override
  State<ConfettiBurst> createState() => ConfettiBurstState();
}

@visibleForTesting
class ConfettiBurstState extends State<ConfettiBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  List<_Particle> _particles = const [];
  int _lastTrigger = -1;

  @override
  void initState() {
    super.initState();
    // Recorded only. Reading MediaQuery (for reduce-motion) during initState is
    // illegal, and a burst fired before the first frame would be invisible.
    _lastTrigger = widget.trigger;
  }

  @override
  void didUpdateWidget(ConfettiBurst oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.trigger != widget.trigger) _fire();
  }

  void _fire() {
    if (_lastTrigger == widget.trigger) return;
    _lastTrigger = widget.trigger;
    if (AppMotion.disabled(context)) return;
    final rng = math.Random();
    setState(() {
      _particles = List<_Particle>.generate(
        widget.particleCount,
        (_) => _Particle(rng),
        growable: false,
      );
    });
    controller.forward(from: 0);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          if (_particles.isEmpty) return const SizedBox.shrink();
          return CustomPaint(
            painter: _ConfettiPainter(
              particles: _particles,
              progress: Curves.easeOutCubic.transform(controller.value),
              palette: [
                colors.brand,
                colors.sunshine,
                colors.mint,
                colors.sky,
                colors.coral,
              ],
              fieldSize: MediaQuery.sizeOf(context),
            ),
            size: Size.infinite,
          );
        },
      ),
    );
  }
}

class _Particle {
  _Particle(math.Random rng)
    : angle = -math.pi / 2 + (rng.nextDouble() - 0.5) * 2.3,
      speed = 240 + rng.nextDouble() * 420,
      size = 6 + rng.nextDouble() * 8,
      spin = (rng.nextDouble() - 0.5) * 12,
      hue = rng.nextInt(5),
      gravity = 620 + rng.nextDouble() * 260;

  final double angle;
  final double speed;
  final double size;
  final double spin;
  final int hue;
  final double gravity;
}

class _ConfettiPainter extends CustomPainter {
  const _ConfettiPainter({
    required this.particles,
    required this.progress,
    required this.palette,
    required this.fieldSize,
  });

  final List<_Particle> particles;
  final double progress;
  final List<Color> palette;
  final Size fieldSize;

  @override
  void paint(Canvas canvas, Size size) {
    if (fieldSize.isEmpty) return;
    final origin = Offset(fieldSize.width / 2, fieldSize.height * 0.42);
    final t = progress;
    final alpha = (1 - t).clamp(0.0, 1.0);
    for (final p in particles) {
      final dx = origin.dx + math.cos(p.angle) * p.speed * t;
      final dy = origin.dy +
          math.sin(p.angle) * p.speed * t +
          0.5 * p.gravity * t * t;
      final paint = Paint()
        ..color = palette[p.hue % palette.length].withValues(alpha: alpha);
      canvas
        ..save()
        ..translate(dx, dy)
        ..rotate(p.spin * t)
        ..drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset.zero,
              width: p.size,
              height: p.size * 0.6,
            ),
            const Radius.circular(2),
          ),
          paint,
        )
        ..restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.fieldSize != fieldSize ||
      oldDelegate.particles != particles;
}
