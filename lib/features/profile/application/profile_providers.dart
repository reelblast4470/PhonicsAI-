import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/infrastructure.dart';
import '../../../app/state/app_settings_controller.dart';
import '../../../core/domain/learner_profile.dart';
import '../../../core/env/app_config.dart';
import '../../../core/error/failure.dart';
import '../../progress/application/progress_providers.dart';
import '../data/local_profile_repository.dart';
import '../data/sync_profile_repository.dart';
import '../domain/profile_repository.dart';

/// Mock mode: device-only. Live/offline-first (Phase 3): the same local
/// repository plus a best-effort mirror to `POST /learners` (with a durable
/// pending queue) and the binding that arms the progress mirror.
final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  final local = LocalProfileRepository(
    store: ref.watch(keyValueStoreProvider),
  );
  final config = ref.watch(appConfigProvider);
  if (config.backendMode == BackendMode.mock || !config.hasBackend) {
    ref.onDispose(local.dispose);
    return local;
  }
  final repository = SyncProfileRepository(
    local: local,
    api: ref.watch(apiClientProvider),
    store: ref.watch(keyValueStoreProvider),
    sync: ref.watch(backendProgressSyncProvider),
  );
  ref.onDispose(() async {
    await repository.dispose();
    await local.dispose();
  });
  return repository;
});

/// The single reactive source for "which learners exist".
final profilesProvider = StreamProvider<List<LearnerProfile>>(
  (ref) => ref.watch(profileRepositoryProvider).watchAll(),
);

/// The learner every screen is scoped to. `null` => the profile chooser.
final activeProfileProvider = Provider<LearnerProfile?>((ref) {
  final id = ref.watch(appSettingsProvider.select((s) => s.activeProfileId));
  if (id == null) return null;
  final profiles = ref.watch(profilesProvider).valueOrNull;
  if (profiles == null) return null;
  return profiles.where((p) => p.id == id).firstOrNull;
});

/// In-flight state for the profile editor. Deliberately separate from the
/// stream above so a save never blanks the list while it is writing.
class ProfileMutationState {
  const ProfileMutationState({this.isBusy = false, this.failure});

  final bool isBusy;
  final AppFailure? failure;

  ProfileMutationState copyWith({bool? isBusy, AppFailure? failure}) =>
      ProfileMutationState(
        isBusy: isBusy ?? this.isBusy,
        failure: failure,
      );
}

class ProfileController extends Notifier<ProfileMutationState> {
  @override
  ProfileMutationState build() => const ProfileMutationState();

  ProfileRepository get _repository => ref.read(profileRepositoryProvider);
  AppSettingsController get _settings =>
      ref.read(appSettingsProvider.notifier);

  Future<LearnerProfile?> create({
    required String displayName,
    required int ageMonths,
    required String avatarId,
    required ReadingLevelSeed level,
    String homeLanguageCode = 'en',
    bool runAssessment = true,
    bool activate = true,
  }) async {
    state = const ProfileMutationState(isBusy: true);
    final result = await _repository.create(
      displayName: displayName,
      ageMonths: ageMonths,
      avatarId: avatarId,
      level: level,
      homeLanguageCode: homeLanguageCode,
      runAssessment: runAssessment,
    );
    return result.fold(
      ok: (profile) async {
        if (activate) await _settings.setActiveProfile(profile.id);
        state = const ProfileMutationState();
        return profile;
      },
      fail: (failure) {
        state = ProfileMutationState(failure: failure);
        return null;
      },
    );
  }

  Future<LearnerProfile?> update(LearnerProfile profile) async {
    state = const ProfileMutationState(isBusy: true);
    final result = await _repository.update(profile);
    return result.fold(
      ok: (updated) {
        state = const ProfileMutationState();
        return updated;
      },
      fail: (failure) {
        state = ProfileMutationState(failure: failure);
        return null;
      },
    );
  }

  Future<bool> delete(String profileId) async {
    state = const ProfileMutationState(isBusy: true);
    final result = await _repository.delete(profileId);
    final active = ref.read(appSettingsProvider).activeProfileId;
    if (result.isOk && active == profileId) {
      final remaining = _repository.readAllSync();
      await _settings.setActiveProfile(remaining.firstOrNull?.id);
    }
    state = result.fold(
      ok: (_) => const ProfileMutationState(),
      fail: (failure) => ProfileMutationState(failure: failure),
    );
    return result.isOk;
  }

  Future<void> activate(String profileId) =>
      _settings.setActiveProfile(profileId);

  Future<void> addStars(String profileId, int amount) =>
      _repository.addStars(profileId: profileId, amount: amount);

  void clearError() => state = const ProfileMutationState();
}

final profileControllerProvider =
    NotifierProvider<ProfileController, ProfileMutationState>(
  ProfileController.new,
);
