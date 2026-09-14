import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/domain/reading_level.dart';
import '../../progress/application/progress_providers.dart';
import '../../progress/domain/progress_repository.dart';
import '../data/phonics_program.dart';
import '../domain/lesson.dart';

/// The program itself. A `Provider` (not a FutureProvider) on purpose: the
/// bundled program is computed once and is always available offline. When the
/// content API arrives this becomes a cached remote source with this as the
/// fallback — the screens do not change.
final curriculumProvider = Provider<List<CurriculumUnit>>(
  (ref) => List.unmodifiable(PhonicsProgram.build()),
);

final curriculumByUnitProvider = Provider<Map<String, CurriculumUnit>>(
  (ref) => {for (final unit in ref.watch(curriculumProvider)) unit.id: unit},
);

final lessonByIdProvider = Provider<Map<String, PhonicsLesson>>((ref) {
  final all = <String, PhonicsLesson>{};
  for (final unit in ref.watch(curriculumProvider)) {
    for (final lesson in unit.lessons) {
      all[lesson.id] = lesson;
    }
  }
  return all;
});

/// All lessons in teaching order — the sequence used by "Continue".
final orderedLessonsProvider = Provider<List<PhonicsLesson>>((ref) {
  final units = [...ref.watch(curriculumProvider)]
    ..sort((a, b) => a.order.compareTo(b.order));
  return [for (final unit in units) ...unit.lessons];
});

/// A unit is open when the learner's placed level reaches it, or when the
/// previous unit is at least 80% done. Progress, not the calendar, unlocks.
class UnitAccess {
  const UnitAccess({
    required this.unit,
    required this.isUnlocked,
    required this.fraction,
    required this.completedLessons,
  });

  final CurriculumUnit unit;
  final bool isUnlocked;
  final double fraction;
  final int completedLessons;

  bool get isComplete => fraction >= 1;
}

final unitAccessProvider = Provider.family<UnitAccess, UnitAccessRequest>(
  (ref, request) {
    final units = [...ref.watch(curriculumProvider)]
      ..sort((a, b) => a.order.compareTo(b.order));
    final index = units.indexWhere((u) => u.id == request.unitId);
    if (index < 0) {
      throw StateError('unknown unit ${request.unitId}');
    }
    final unit = units[index];
    final snapshot = request.snapshot;

    var completed = 0;
    var total = 0;
    for (final lesson in unit.lessons) {
      total++;
      if (snapshot != null && snapshot.lessonIsComplete(lesson)) completed++;
    }
    final fraction = total == 0 ? 0.0 : completed / total;

    final byLevel = unit.level.rank <= request.level.rank;
    final previousDone = index == 0
        ? true
        : () {
            final previous = units[index - 1];
            if (snapshot == null) return false;
            var done = 0;
            for (final lesson in previous.lessons) {
              if (snapshot.lessonIsComplete(lesson)) done++;
            }
            return previous.lessons.isEmpty ||
                done / previous.lessons.length >= 0.8;
          }();

    return UnitAccess(
      unit: unit,
      isUnlocked: index == 0 || byLevel || previousDone,
      fraction: fraction,
      completedLessons: completed,
    );
  },
);

@immutable
class UnitAccessRequest {
  const UnitAccessRequest({
    required this.unitId,
    required this.level,
    this.snapshot,
  });

  final String unitId;
  final ReadingLevel level;
  final ProfileSnapshot? snapshot;
}
