import '../../../core/domain/learner_profile.dart';
import '../../../core/result/result.dart';

/// How profiles are read and written. Two shapes on purpose:
/// `watch` streams so every screen refreshes when a sibling changes the data,
/// and `Future<Result<>>` mutations so the UI can show a real failure.
abstract interface class ProfileRepository {
  Future<void> warmUp();

  Stream<List<LearnerProfile>> watchAll();

  List<LearnerProfile> readAllSync();

  LearnerProfile? findById(String id);

  Future<Result<LearnerProfile>> create({
    required String displayName,
    required int ageMonths,
    required String avatarId,
    required ReadingLevelSeed level,
    String homeLanguageCode,
    bool runAssessment,
  });

  Future<Result<LearnerProfile>> update(LearnerProfile profile);

  Future<Result<void>> delete(String profileId);

  Future<Result<void>> addStars({
    required String profileId,
    required int amount,
  });
}

/// Level choice at creation time: either the placement test decides, or the
/// adult picks a band directly.
enum ReadingLevelSeed {
  takeTest,
  manual;

  static ReadingLevelSeed fromCode(String? code) =>
      code == 'manual' ? ReadingLevelSeed.manual : ReadingLevelSeed.takeTest;
}
