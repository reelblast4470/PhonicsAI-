import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

import 'package:flutter/foundation.dart' show immutable;

/// One continuous pen path (finger or mouse) in normalised 0..1 canvas space.
@immutable
class TracedStroke {
  const TracedStroke(this.points);

  final List<Offset> points;

  int get length => points.length;

  double get pathLength {
    var total = 0.0;
    for (var i = 1; i < points.length; i++) {
      total += (points[i] - points[i - 1]).distance;
    }
    return total;
  }

  bool get isTooShort => points.length < 3 || pathLength < 0.08;

  Map<String, dynamic> toJson() => {
        'points': [
          for (final point in points) [
            (point.dx * 100).round(),
            (point.dy * 100).round(),
          ],
        ],
      };
}

enum WritingFeedback {
  tooShort('Draw the whole letter in one go.'),
  offTarget('Start inside the dotted letter.'),
  good('Nice lines! Try to stay on the path.'),
  great('That letter is on the line — beautiful!');

  const WritingFeedback(this.copy);
  final String copy;
}

/// Grades a set of strokes against a letter cell.
///
/// Three signals, all cheap enough to run on a low-end Android tablet while the
/// child is still lifting their finger:
///  * **ink kept in the cell** — points outside the guide are wasted motion
///  * **path coverage** — how much of the cell the pen travelled across
///  * **smoothness** — a shaky, over-traced path is a fine motor sign, not a
///    correctness failure, so it only nudges the score.
///
/// The precise "did you cover the glyph" check needs a rasterised mask; that is
/// behind [LetterMaskSampler] so it can be turned on per platform without
/// touching this function.
abstract final class TracingScoring {
  static const double passThreshold = 0.6;

  static WritingScore score({
    required List<TracedStroke> strokes,
    double? glyphCoverage,
  }) {
    final all = [for (final stroke in strokes) ...stroke.points];
    if (all.isEmpty) {
      return const WritingScore(
        coverage: 0,
        insideRatio: 0,
        smoothness: 0,
        feedback: WritingFeedback.tooShort,
      );
    }

    var inside = 0;
    for (final point in all) {
      if (point.dx >= 0.05 &&
          point.dx <= 0.95 &&
          point.dy >= 0.02 &&
          point.dy <= 0.98) {
        inside++;
      }
    }
    final insideRatio = inside / all.length;

    // Grid coverage: how many of the 5x7 cells of the letter box were visited.
    const columns = 5;
    const rows = 7;
    final visited = <int>{};
    for (final point in all) {
      final cx = (point.dx.clamp(0.0, 0.999) * columns).floor();
      final cy = (point.dy.clamp(0.0, 0.999) * rows).floor();
      visited.add(cy * columns + cx);
    }
    final gridCoverage = visited.length / (columns * rows);
    final coverage = glyphCoverage == null
        ? gridCoverage
        : math.max(gridCoverage * 0.5, glyphCoverage);

    var directionChanges = 0;
    double travelled = 0;
    for (final stroke in strokes) {
      for (var i = 2; i < stroke.points.length; i++) {
        final a = stroke.points[i - 1] - stroke.points[i - 2];
        final b = stroke.points[i] - stroke.points[i - 1];
        final dot = a.dx * b.dx + a.dy * b.dy;
        if (dot < 0) directionChanges++;
        travelled += b.distance;
      }
    }
    final smoothness = coverage <= 0
        ? 0.0
        : (1 - (directionChanges / math.max(travelled * 6, 1))).clamp(0.0, 1.0);

    final overall = (coverage * 0.55) + (insideRatio * 0.3) + (smoothness * 0.15);
    final feedback = switch (overall) {
      < 0.25 => WritingFeedback.tooShort,
      < 0.45 when insideRatio < 0.7 => WritingFeedback.offTarget,
      < passThreshold => WritingFeedback.offTarget,
      < 0.82 => WritingFeedback.good,
      _ => WritingFeedback.great,
    };

    return WritingScore(
      coverage: coverage,
      insideRatio: insideRatio,
      smoothness: smoothness,
      overall: overall,
      feedback: feedback,
      passed: overall >= passThreshold,
    );
  }
}

@immutable
class WritingScore {
  const WritingScore({
    required this.coverage,
    required this.insideRatio,
    required this.smoothness,
    this.overall = 0,
    required this.feedback,
    this.passed = false,
  });

  final double coverage;
  final double insideRatio;
  final double smoothness;
  final double overall;
  final WritingFeedback feedback;
  final bool passed;

  int get percent => (overall.clamp(0, 1) * 100).round();
}

/// Adapter point for exact glyph-mask scoring (needs one rasterisation per
/// letter, cached). When unavailable the heuristic above is used instead.
abstract interface class LetterMaskSampler {
  /// 0..1 fraction of the letter's ink covered by [strokes].
  Future<double?> coverageFor({
    required String glyph,
    required List<TracedStroke> strokes,
    required Size size,
  });
}

class UnavailableLetterMaskSampler implements LetterMaskSampler {
  const UnavailableLetterMaskSampler();

  @override
  Future<double?> coverageFor({
    required String glyph,
    required List<TracedStroke> strokes,
    required Size size,
  }) async =>
      null;
}

/// A word to spell with letter tiles. `distractors` are extra letters, which is
/// what turns "copy the word" into "recall the sounds".
@immutable
class SpellingTarget {
  const SpellingTarget({
    required this.word,
    required this.emoji,
    required this.prompt,
    this.distractors = const [],
  });

  final String word;
  final String emoji;
  final String prompt;
  final List<String> distractors;

  List<String> get letters => word.toUpperCase().split('');

  /// Tiles are shuffled deterministically from the word so a retry looks the
  /// same — a changing board is unfair for a 5-year-old.
  List<String> tilesFor(int seed) {
    final tiles = [...letters, ...distractors];
    if (tiles.isEmpty) return tiles;
    // Fisher-Yates with a fixed seed.
    var state = seed & 0x7FFFFFFF;
    int next() {
      state = (state * 1103515245 + 12345) & 0x7FFFFFFF;
      return state;
    }

    for (var i = tiles.length - 1; i > 0; i--) {
      final j = next() % (i + 1);
      final tmp = tiles[i];
      tiles[i] = tiles[j];
      tiles[j] = tmp;
    }
    return tiles;
  }
}
