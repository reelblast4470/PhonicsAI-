import 'package:flutter/material.dart';

import '../../../../theme/app_colors.dart';
import '../../../../theme/app_dimens.dart';
import '../../domain/writing_models.dart';

/// Finger/mouse tracing surface.
///
/// The guide glyph is real text at low opacity (not an image), so it scales with
/// the OS font size, works on every platform, and costs no assets. Strokes are
/// stored in normalised coordinates so a score computed on a 360dp phone means
/// the same thing on a 27" monitor.
class TracingBoard extends StatefulWidget {
  const TracingBoard({
    required this.glyph,
    required this.onScore,
    this.height = 260,
    this.showMidline = true,
    this.wordHint,
    super.key,
  });

  final String glyph;
  final ValueChanged<WritingScore> onScore;
  final double height;
  final bool showMidline;
  final String? wordHint;

  @override
  State<TracingBoard> createState() => TracingBoardState();
}

class TracingBoardState extends State<TracingBoard> {
  final List<TracedStroke> _strokes = [];
  List<Offset>? _current;
  WritingScore? _lastScore;

  WritingScore? get lastScore => _lastScore;

  void _reset() => setState(() {
        _strokes.clear();
        _current = null;
        _lastScore = null;
      });

  void _score() {
    if (_strokes.isEmpty) return;
    final score = TracingScoring.score(strokes: _strokes);
    setState(() => _lastScore = score);
    widget.onScore(score);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Column(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth.isFinite
                ? constraints.maxWidth
                : 320.0;
            return SizedBox(
              height: widget.height,
              width: width,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: ColoredBox(
                  color: colors.surface,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: (event) => setState(() {
                      _current = [
                        _normalise(event.localPosition, width, widget.height),
                      ];
                      _lastScore = null;
                    }),
                    onPanUpdate: (event) => setState(() {
                      _current?.add(
                        _normalise(event.localPosition, width, widget.height),
                      );
                    }),
                    onPanEnd: (_) => setState(() {
                      if (_current != null && _current!.length > 2) {
                        _strokes.add(TracedStroke(List.of(_current!)));
                      }
                      _current = null;
                      _score();
                    }),
                    child: CustomPaint(
                      painter: _TracingPainter(
                        strokes: _strokes,
                        live: _current,
                        guideColor: colors.brand.withValues(alpha: 0.18),
                        inkColor: colors.brand,
                        gridColor: colors.inkMuted.withValues(alpha: 0.16),
                        showMidline: widget.showMidline,
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          IgnorePointer(
                            child: Text(
                              widget.glyph,
                              style: TextStyle(
                                fontSize: widget.height * 0.78,
                                fontWeight: FontWeight.w700,
                                color: colors.ink.withValues(alpha: 0.12),
                                height: 1,
                              ),
                            ),
                          ),
                          if (widget.wordHint case final hint?)
                            Positioned(
                              bottom: 8,
                              child: Text(
                                hint,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            TextButton.icon(
              onPressed: _strokes.isEmpty ? null : _reset,
              icon: const Icon(Icons.layers_clear_rounded),
              label: const Text('Erase'),
            ),
            const Spacer(),
            if (_lastScore case final score?)
              Text(
                score.feedback.copy,
                textAlign: TextAlign.end,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: score.passed ? colors.success : colors.inkMuted,
                      fontWeight: FontWeight.w700,
                    ),
              ),
          ],
        ),
      ],
    );
  }

  static Offset _normalise(Offset point, double width, double height) => Offset(
        (point.dx / width).clamp(0.0, 1.0),
        (point.dy / height).clamp(0.0, 1.0),
      );
}

class _TracingPainter extends CustomPainter {
  _TracingPainter({
    required this.strokes,
    required this.live,
    required this.guideColor,
    required this.inkColor,
    required this.gridColor,
    required this.showMidline,
  });

  final List<TracedStroke> strokes;
  final List<Offset>? live;
  final Color guideColor;
  final Color inkColor;
  final Color gridColor;
  final bool showMidline;

  @override
  void paint(Canvas canvas, Size size) {
    void line(Offset from, Offset to, double width, Color color) => canvas.drawLine(
          Offset(from.dx * size.width, from.dy * size.height),
          Offset(to.dx * size.width, to.dy * size.height),
          Paint()
            ..color = color
            ..strokeWidth = width
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round,
        );

    // handwriting guide lines
    final rules = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (final fraction in [0.2, 0.5, 0.8]) {
      canvas.drawLine(
        Offset(0, size.height * fraction),
        Offset(size.width, size.height * fraction),
        rules,
      );
    }
    if (showMidline) {
      canvas.drawLine(
        Offset(size.width / 2, 0),
        Offset(size.width / 2, size.height),
        Paint()
          ..color = gridColor
          ..strokeWidth = 1,
      );
    }

    for (final stroke in strokes) {
      _paintStroke(stroke.points, line, size);
    }
    if (live case final points?) {
      _paintStroke(points, line, size);
    }
  }

  void _paintStroke(
    List<Offset> points,
    void Function(Offset, Offset, double, Color) draw,
    Size size,
  ) {
    for (var i = 1; i < points.length; i++) {
      draw(points[i - 1], points[i], 12, inkColor);
    }
    for (var i = 1; i < points.length; i++) {
      draw(points[i - 1], points[i], 5, Colors.white.withValues(alpha: 0.6));
    }
  }

  @override
  bool shouldRepaint(_TracingPainter old) =>
      old.strokes.length != strokes.length ||
      old.live?.length != live?.length ||
      old.showMidline != showMidline;
}
