import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/infrastructure.dart';
import '../../../core/domain/reading_level.dart';
import '../../../core/env/app_config.dart';
import '../../../core/error/failure.dart';
import '../../progress/application/progress_providers.dart';
import '../../progress/domain/progress_repository.dart';
import '../data/backend_curriculum.dart';
import '../data/live_lesson_service.dart';
import '../data/phonics_program.dart';
import '../domain/lesson.dart';

/// Live-mode content source (Phase 3): the backend curriculum is the real
/// program; the bundled `PhonicsProgram` remains (a) the mock-mode source and
/// (b) the offline fallback while the fetch is in flight or failed. No screen
/// changes: they keep watching the synchronous provider below.
final liveCurriculumProvider = FutureProvider<BackendCurriculum?>((ref) async {
  final config = ref.watch(appConfigProvider);
  if (config.backendMode == BackendMode.mock || !config.hasBackend) {
    return null;
  }
  try {
    final api = ref.watch(apiClientProvider);
    final json = await api.getJson('/content/curriculum');
    final mapped = BackendCurriculum.fromJson(json);
    // lesson codes become "remote-managed": the local mirror must not replay
    // their finish events (the live runner completes those directly).
    ref.read(backendProgressSyncProvider)?.registerRemoteLessons(
      mapped.lessonUuids.keys.toSet(),
    );
    return mapped;
  } on AppFailure {
    return null;
  }
});

final curriculumProvider = Provider<List<CurriculumUnit>>((ref) {
  final live = ref.watch(liveCurriculumProvider).valueOrNull;
  if (live != null && live.units.isNotEmpty) {
    return List.unmodifiable(live.units);
  }
  return List.unmodifiable(PhonicsProgram.build());
});

/// The active profile's backend learner UUID, via the sync bindings.
/// Stream-based on purpose: bindings appear at runtime (profile creation
/// while online), and every dependent provider must re-resolve then.
final liveLearnerIdProvider = StreamProvider<String?>((ref) async* {
  final store = ref.watch(keyValueStoreProvider);
  String? resolve() {
    final profileId = store.getString('phonicsai.active_profile');
    if (profileId == null) return null;
    return ref.read(backendProgressSyncProvider)?.learnerIdFor(profileId);
  }

  yield resolve();
  await for (final _ in store.changes) {
    yield resolve();
  }
});

final liveLessonServiceProvider = Provider<LiveLessonService?>((ref) {
  final config = ref.watch(appConfigProvider);
  if (config.backendMode == BackendMode.mock || !config.hasBackend) {
    return null;
  }
  return LiveLessonService(
    api: ref.watch(apiClientProvider),
    learnerIdResolver: () => ref.read(backendProgressSyncProvider)
        ?.learnerIdFor(
            ref.read(keyValueStoreProvider).getString('phonicsai.active_profile') ??
                ''),
  );
});

/// Adaptive recommendation (Phase 3): next lesson / review payload straight
/// from the server engine. `null` in mock mode or when offline (fallback:
/// the local `snapshot.nextLesson` logic, unchanged).
class LiveRecommendation {
  const LiveRecommendation({
    required this.type,
    required this.reason,
    this.lessonCode,
    this.lessonId,
    this.lessonTitle,
    this.reviewsDue = 0,
  });

  final String type; // lesson | review | complete
  final String reason;
  final String? lessonCode;
  final String? lessonId;
  final String? lessonTitle;
  final int reviewsDue;
}

final liveRecommendationProvider = FutureProvider<LiveRecommendation?>((
  ref,
) async {
  final learnerId = ref.watch(liveLearnerIdProvider).valueOrNull;
  if (learnerId == null) return null;
  try {
    final json = await ref
        .watch(apiClientProvider)
        .getJson('/learners/$learnerId/recommendation');
    return LiveRecommendation(
      type: json['type']?.toString() ?? 'lesson',
      reason: json['reason']?.toString() ?? '',
      lessonCode: json['lesson_code']?.toString(),
      lessonId: json['lesson_id']?.toString(),
      lessonTitle: json['lesson_title']?.toString(),
      reviewsDue: (json['reviews'] as List?)?.length ?? 0,
    );
  } on AppFailure {
    return null;
  }
});

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
