import '../../../core/util/date_util.dart';
import 'progress_models.dart';

/// A deliberately small SM-2 variant.
///
/// Grades: 0 = forgot, 3 = hard, 5 = easy. Two rules matter for 5-year-olds:
/// a lapse sends the sound back to *tomorrow* (never a week), and nothing is
/// ever scheduled further out than 21 days, because a phonics learner needs
/// frequent contact far more than a medical student does.
class SrsResult {
  const SrsResult({required this.mastery, required this.dueTomorrow});
  final PhonemeMastery mastery;
  final bool dueTomorrow;
}

abstract final class SpacedRepetition {
  static const maxIntervalDays = 21.0;
  static const minEase = 1.3;
  static const maxEase = 3.0;

  static PhonemeMastery review(
    PhonemeMastery current, {
    required int grade,
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    final clamped = grade.clamp(0, 5);
    final forgot = clamped < 2;

    final ease = (current.ease +
            (0.1 - (5 - clamped) * (0.08 + (5 - clamped) * 0.02)))
        .clamp(minEase, maxEase);

    double interval;
    final reps = current.reps + 1;
    if (forgot) {
      interval = 0; // same day / tomorrow
    } else if (reps == 1) {
      interval = 1;
    } else if (reps == 2) {
      interval = 3;
    } else {
      interval = (current.intervalDays * ease).clamp(2.0, maxIntervalDays);
    }

    final correct = current.correct + (clamped >= 3 ? 1 : 0);
    final lapses = current.lapses + (forgot ? 1 : 0);
    final ratio = reps == 0 ? 0.0 : correct / reps;

    return PhonemeMastery(
      phoneme: current.phoneme,
      status: _statusFor(ratio, reps, lapses),
      reps: reps,
      correct: correct,
      lapses: lapses,
      ease: ease,
      intervalDays: interval,
      dueAt: DateUtil.addDays(at, interval.round() == 0 ? 1 : interval.round()),
      lastSeenAt: at,
    );
  }

  static MasteryStatus _statusFor(double ratio, int reps, int lapses) {
    if (reps < 2) return MasteryStatus.learning;
    if (ratio >= 0.92 && lapses == 0 && reps >= 4) return MasteryStatus.mastered;
    if (ratio >= 0.8) return MasteryStatus.secure;
    if (lapses >= 2) return MasteryStatus.learning;
    return ratio >= 0.5 ? MasteryStatus.learning : MasteryStatus.fresh;
  }

  /// Sounds to practise today, oldest-due first, capped so a session stays
  /// short enough for a 4-year-old's attention span.
  static List<PhonemeMastery> dueQueue(
    Iterable<PhonemeMastery> all, {
    int limit = 5,
  }) {
    final due = all.where((m) => m.isDue).toList()
      ..sort((a, b) {
        final byLapse = b.lapses.compareTo(a.lapses);
        if (byLapse != 0) return byLapse;
        return a.accuracy.compareTo(b.accuracy);
      });
    return due.take(limit).toList(growable: false);
  }
}
