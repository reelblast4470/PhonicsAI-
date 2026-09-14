import 'dart:math' as math;

/// Small, dependency-free numeric helpers shared by scoring/analytics code.
abstract final class MathUtil {
  static double clamp(double v, double min, double max) =>
      v < min ? min : (v > max ? max : v);

  static int clampInt(int v, int min, int max) =>
      v < min ? min : (v > max ? max : v);

  /// 0..1 accuracy helper that survives empty denominators.
  static double ratio(int numerator, int denominator) =>
      denominator <= 0 ? 0 : clamp(numerator / denominator, 0, 1);

  static int percentRound(double r) => (clamp(r, 0, 1) * 100).round();

  /// Exponential moving average used for accuracy trends.
  static double ema(List<double> samples, {double alpha = 0.35}) {
    if (samples.isEmpty) return 0;
    var acc = samples.first;
    for (var i = 1; i < samples.length; i++) {
      acc = alpha * samples[i] + (1 - alpha) * acc;
    }
    return acc;
  }

  static double mean(List<double> xs) => xs.isEmpty
      ? 0
      : xs.reduce((a, b) => a + b) / xs.length;

  static double stdDev(List<double> xs) {
    if (xs.length < 2) return 0;
    final m = mean(xs);
    final variance =
        xs.map((x) => (x - m) * (x - m)).reduce((a, b) => a + b) /
            (xs.length - 1);
    return math.sqrt(variance);
  }
}
