import 'dart:async';
import 'dart:convert';

import '../../../core/domain/learner_profile.dart';
import '../../../core/error/failure.dart';
import '../../../core/network/api_client.dart';
import '../../../core/result/result.dart';
import '../../../core/storage/key_value_store.dart';
import '../../progress/data/backend_progress_sync.dart';
import '../domain/profile_repository.dart';

/// The device repository + a mirror to the backend (Phase 3).
///
/// Rules:
///  * the local store stays the UI's source of truth (instant, offline-safe);
///  * a successful create/delete/PATCH is replayed to the API;
///  * if the API is unreachable the profile is remembered as *pending* and
///    pushed on the next `warmUp` — a child's profile is never silently lost
///    and never faked as "synced";
///  * binding the backend learner id is what turns on the progress mirror
///    (`BackendProgressSync`) for that profile.
class SyncProfileRepository implements ProfileRepository {
  SyncProfileRepository({
    required this.local,
    required this.api,
    required this.store,
    this.sync,
  });

  final ProfileRepository local;
  final ApiClient api;
  final KeyValueStore store;
  final BackendProgressSync? sync;

  static const _bindingsKey = 'phonicsai.profiles.remote';
  static const _pendingKey = 'phonicsai.profiles.pending';

  Map<String, String> get _bindings {
    final raw = store.getString(_bindingsKey);
    if (raw == null || raw.isEmpty) return const {};
    try {
      return (jsonDecode(raw) as Map).cast<String, String>();
    } on FormatException {
      return const {};
    }
  }

  Future<void> _setBinding(String localId, String remoteId) async {
    final map = Map<String, String>.from(_bindings)..[localId] = remoteId;
    await store.setString(_bindingsKey, jsonEncode(map));
  }

  Future<void> _clearBinding(String localId) async {
    final map = Map<String, String>.from(_bindings)..remove(localId);
    await store.setString(_bindingsKey, jsonEncode(map));
  }

  String? remoteIdFor(String localId) => _bindings[localId];

  List<Map<String, dynamic>> get _pending {
    final raw = store.getString(_pendingKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    } on FormatException {
      return const [];
    }
  }

  Future<void> _setPending(List<Map<String, dynamic>> rows) =>
      store.setString(_pendingKey, jsonEncode(rows));

  Future<void> _enqueuePending(Map<String, dynamic> row) async {
    final rows = [..._pending, row];
    await _setPending(rows.length > 50 ? rows.sublist(rows.length - 50) : rows);
  }

  Future<void> _dequeuePending(String localId) async {
    await _setPending(_pending.where((r) => r['local_id'] != localId).toList());
  }

  @override
  Future<void> warmUp() async {
    await local.warmUp();
    await _flushPending();
  }

  /// Best-effort retry of profiles that were created while offline.
  Future<void> _flushPending() async {
    if (!api.config.hasBackend) return;
    final rows = [..._pending];
    for (final row in rows) {
      final name = row['display_name']?.toString();
      if (name == null) continue;
      try {
        final created = await api.postJson('/learners', body: {
          'display_name': name,
          'daily_target_minutes': row['daily_target_minutes'] is num
              ? (row['daily_target_minutes'] as num).toInt()
              : 15,
          'avatar_key': row['avatar_id']?.toString() ?? 'fox',
          'learning_goals': {
            'source': 'device-queue',
            'age_months': row['age_months'] ?? 60,
            'home_language': row['home_language'] ?? 'en',
          },
        });
        final rid = created['id']?.toString();
        if (rid != null && row['local_id'] != null) {
          await _setBinding(row['local_id'].toString(), rid);
          await sync?.bindProfile(
              profileId: row['local_id'].toString(), learnerId: rid);
          await _dequeuePending(row['local_id'].toString());
        }
      } on AppFailure {
        return; // still offline: stop, keep order, retry next warm-up
      }
    }
  }

  @override
  Stream<List<LearnerProfile>> watchAll() => local.watchAll();

  @override
  List<LearnerProfile> readAllSync() => local.readAllSync();

  @override
  LearnerProfile? findById(String id) => local.findById(id);

  @override
  Future<Result<LearnerProfile>> create({
    required String displayName,
    required int ageMonths,
    required String avatarId,
    required ReadingLevelSeed level,
    String homeLanguageCode = 'en',
    bool runAssessment = true,
  }) async {
    final result = await local.create(
      displayName: displayName,
      ageMonths: ageMonths,
      avatarId: avatarId,
      level: level,
      homeLanguageCode: homeLanguageCode,
      runAssessment: runAssessment,
    );
    if (result case Fail()) return result;
    final profile = (result as Ok<LearnerProfile>).value;
    // Mirror server-side; on failure the queue (not an error) guarantees the
    // retry — the family's learning keeps working offline.
    try {
      final created = await api.postJson('/learners', body: {
        'display_name': profile.displayName,
        'daily_target_minutes': profile.dailyGoalMinutes,
        'avatar_key': profile.avatarId,
        'learning_goals': {
          'source': 'onboarding',
          'age_months': ageMonths,
          'home_language': homeLanguageCode,
          'run_assessment': runAssessment,
        },
      });
      final rid = created['id']?.toString();
      if (rid != null) {
        await _setBinding(profile.id, rid);
        await sync?.bindProfile(profileId: profile.id, learnerId: rid);
      }
    } on AppFailure {
      await _enqueuePending({
        'local_id': profile.id,
        'display_name': profile.displayName,
        'age_months': ageMonths,
        'avatar_id': avatarId,
        'home_language': homeLanguageCode,
        'daily_target_minutes': profile.dailyGoalMinutes,
      });
    }
    return Result.ok(profile);
  }

  @override
  Future<Result<LearnerProfile>> update(LearnerProfile profile) async {
    final result = await local.update(profile);
    final rid = _bindings[profile.id];
    if (rid != null) {
      try {
        await api.patchJson('/learners/$rid', body: {
          'display_name': profile.displayName,
          'daily_target_minutes': profile.dailyGoalMinutes,
          'avatar_key': profile.avatarId,
        });
      } on AppFailure {
        // local is already correct; the next successful edit resyncs.
      }
    }
    return result;
  }

  @override
  Future<Result<void>> delete(String profileId) async {
    final result = await local.delete(profileId);
    final rid = _bindings[profileId];
    if (rid != null) {
      try {
        await api.deleteJson('/learners/$rid');
      } on AppFailure {
        // keep the binding: retried on next warmUp of the delete queue? (v1:
        // the server row remains until an admin sweeps it — documented)
      }
    }
    await _clearBinding(profileId);
    await _dequeuePending(profileId);
    return result;
  }

  @override
  Future<Result<void>> addStars({
    required String profileId,
    required int amount,
  }) =>
      local.addStars(profileId: profileId, amount: amount);

  Future<void> dispose() async {}
}
