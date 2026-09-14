import 'dart:async';

import '../../../core/domain/learner_profile.dart';
import '../../../core/domain/reading_level.dart';
import '../../../core/error/failure.dart';
import '../../../core/result/result.dart';
import '../../../core/storage/collection_store.dart';
import '../../../core/storage/key_value_store.dart';
import '../../../core/util/ids.dart';
import '../domain/profile_repository.dart';

/// Local, offline-first implementation: profiles live in the device store.
///
/// This is *real* persistence (it survives restarts), not demo data. When the
/// PhonicsAI accounts API exists, `RemoteProfileRepository` becomes the default
/// and this class stays as its cache + offline writer — no UI changes.
class LocalProfileRepository implements ProfileRepository {
  LocalProfileRepository({required KeyValueStore store})
    : _collection = CollectionStore<LearnerProfile>(
        store: store,
        namespace: namespace,
        fromJson: LearnerProfile.fromJson,
        toJson: (profile) => profile.toJson(),
      );

  static const namespace = 'phonicsai.profiles';

  final CollectionStore<LearnerProfile> _collection;

  @override
  Future<void> warmUp() => _collection.load();

  /// Cancellation-safe on purpose: `StreamProvider` (and any test) cancels this
  /// stream on dispose, and an `async*` + `await for` pair would wait forever
  /// for a broadcast stream that never closes.
  @override
  Stream<List<LearnerProfile>> watchAll() {
    late final StreamController<List<LearnerProfile>> controller;
    StreamSubscription<void>? changes;
    var cancelled = false;

    controller = StreamController<List<LearnerProfile>>(
      onListen: () async {
        await _collection.load();
        if (cancelled) return;
        controller.add(_snapshot());
        changes = _collection.changes.listen((_) {
          if (!controller.isClosed) controller.add(_snapshot());
        });
      },
      onCancel: () async {
        cancelled = true;
        await changes?.cancel();
      },
    );
    return controller.stream;
  }

  @override
  List<LearnerProfile> readAllSync() => _snapshot();

  @override
  LearnerProfile? findById(String id) {
    if (!_collection.isLoaded) return null;
    return _collection.byId(id);
  }

  @override
  Future<Result<LearnerProfile>> create({
    required String displayName,
    required int ageMonths,
    required String avatarId,
    required ReadingLevelSeed level,
    String homeLanguageCode = 'en',
    bool runAssessment = true,
  }) async {
    final name = displayName.trim();
    if (name.isEmpty) return const Result.fail(ProfileFailures.nameRequired);

    await _collection.load();
    final profile = LearnerProfile(
      id: Ids.namespaced('learner'),
      displayName: name,
      ageMonths: ReadingLevel.clampAgeMonths(ageMonths),
      avatarId: avatarId,
      // A learner who skips the test starts at the default band with the
      // assessment flag left off, so Home keeps offering it.
      level: level == ReadingLevelSeed.takeTest
          ? ReadingLevel.letterSounds
          : ReadingLevel.preReader,
      createdAt: DateTime.now(),
      homeLanguageCode: homeLanguageCode,
      isAssessmentComplete: level == ReadingLevelSeed.manual,
    );
    await _collection.put(profile.id, profile);
    return Result.ok(profile);
  }

  @override
  Future<Result<LearnerProfile>> update(LearnerProfile profile) async {
    if (profile.displayName.trim().isEmpty) {
      return const Result.fail(ProfileFailures.nameRequired);
    }
    await _collection.load();
    await _collection.put(profile.id, profile);
    return Result.ok(profile);
  }

  @override
  Future<Result<void>> delete(String profileId) async {
    await _collection.load();
    if (_collection.byId(profileId) == null) {
      return const Result.fail(ProfileFailures.missing);
    }
    await _collection.remove(profileId);
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> addStars({
    required String profileId,
    required int amount,
  }) async {
    await _collection.load();
    final existing = _collection.byId(profileId);
    if (existing == null) return const Result.fail(ProfileFailures.missing);
    await _collection.put(
      profileId,
      existing.copyWith(starsBalance: existing.starsBalance + amount),
    );
    return const Result.ok(null);
  }

  List<LearnerProfile> _snapshot() => _collection.sorted(
    (a, b) => a.createdAt.compareTo(b.createdAt),
  );

  Future<void> dispose() => _collection.dispose();
}

/// Errors this repository can produce, expressed with the shared [AppFailure]
/// type so any screen can render them without feature-specific classes.
abstract final class ProfileFailures {
  static const missing = AppFailure(
    kind: FailureKind.notFound,
    message: 'That profile is not on this device.',
    detail: 'profile repository: unknown id',
  );

  static const nameRequired = AppFailure.validation(
    'A name is needed so the tutor can say it.',
  );
}
