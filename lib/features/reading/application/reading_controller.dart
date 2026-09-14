import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../progress/application/progress_providers.dart';
import '../domain/reading_models.dart';

/// Keeps the read-aloud history for one passage during a session and mirrors
/// the *minutes* into progress (the number the parent report and the daily
/// mission both use).
class ReadingController extends FamilyNotifier<List<ReadingAttempt>, String> {
  late String passageId;

  @override
  List<ReadingAttempt> build(String argument) {
    passageId = argument;
    return const [];
  }

  Future<void> recordAttempt(ReadingAttempt attempt) async {
    state = [...state, attempt];
    final profileId = ref.read(activeProfileIdProvider);
    if (profileId == null) return;
    final minutes = attempt.minutesTowardGoal;
    if (minutes <= 0) return;
    await ref
        .read(progressRepositoryProvider)
        .addReadingMinutes(profileId: profileId, minutes: minutes);
  }

  double get bestAccuracy =>
      state.isEmpty ? 0 : state.map((a) => a.accuracy).reduce((a, b) => a > b ? a : b);
}

final readingControllerProvider =
    NotifierProvider.family<ReadingController, List<ReadingAttempt>, String>(
  ReadingController.new,
);
