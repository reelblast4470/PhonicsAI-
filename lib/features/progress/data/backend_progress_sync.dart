import 'dart:async';
import 'dart:convert';
import 'dart:math';

import '../../../core/error/failure.dart';
import '../../../core/network/api_client.dart';
import '../../../core/result/result.dart';
import '../../../core/storage/key_value_store.dart';

/// One mirrored learning action waiting for the network.
class SyncOp {
  const SyncOp({required this.kind, required this.payload, this.attempts = 0});

  final String kind; // game_round | reading_minutes | sound_review | lesson_finish
  final Map<String, Object?> payload;
  final int attempts;

  Map<String, dynamic> toJson() => {
    'kind': kind,
    'payload': payload,
    'attempts': attempts,
  };

  factory SyncOp.fromJson(Map<String, dynamic> j) => SyncOp(
    kind: j['kind'] as String,
    payload: (j['payload'] as Map).cast<String, Object?>(),
    attempts: (j['attempts'] as num?)?.toInt() ?? 0,
  );
}

/// What the local repository calls after a *successful* local write.
/// Everything is fire-and-forget: learning never waits on the network, and
/// failures land in the durable queue inside [BackendProgressSync].
abstract interface class ProgressMirror {
  Future<void> onGameRound({
    required String profileId,
    required String gameId,
    required int score,
    required int stars,
    required double secondsSpent,
  });

  Future<void> onReadingMinutes({
    required String profileId,
    required int minutes,
  });

  Future<void> onSoundReview({
    required String profileId,
    required String phoneme,
    required int grade,
  });

  Future<void> onLessonFinish({
    required String profileId,
    required String lessonId,
    required int stars,
    required double accuracy,
    required double secondsSpent,
  });
}

/// Pushes the child's learning actions to the backend ledger
/// (`/api/v1/learners/{id}/sessions…`) so XP, streaks and daily tasks are
/// server truth — while the local store stays the UI's source of truth.
///
/// Design notes:
///  * **Offline-first**: each push is queued in [KeyValueStore] first and only
///    deleted after the API accepts it; `flush()` runs on launch/bind/retry.
///  * **Server-side authority**: the client sends raw actions (game score,
///    minutes, grades); the API's progress engine decides XP, stars, streak
///    and task completion. Nothing here computes rewards.
///  * **Content ids**: the local curriculum uses unit/lesson slugs, the
///    backend uses UUIDs. Games/reading/reviews need no content id; a lesson
///    finish is only mirrored once `bindLesson` has a mapping (the Phase-3
///    content pipeline supplies it). Unmapped lesson ops stay queued, capped
///    and never guessed.
///  * **Authorization**: every call carries the parent's bearer token; the
///    API itself rejects writes for children the caller does not own.
class BackendProgressSync implements ProgressMirror {
  BackendProgressSync({required this.api, required this.store});

  /// JSON transport (bearer + error mapping handled centrally).
  final ApiClient api;

  /// Durable home of the queue and the profile->learner bindings.
  final KeyValueStore store;

  static const _queueKey = 'phonicsai.sync.queue';
  static const _bindKey = 'phonicsai.sync.bindings';
  static const _maxQueue = 200;
  static const _maxAttempts = 8;

  final _random = Random.secure();

  bool get isEnabled {
    final bindings = _bindings;
    return bindings.isNotEmpty && bindings.values.any((v) => v != null);
  }

  // ------------------------------------------------------------- bindings

  Map<String, String?> get _bindings {
    final raw = store.getString(_bindKey);
    if (raw == null || raw.isEmpty) return const {};
    try {
      return (jsonDecode(raw) as Map).cast<String, String?>();
    } on FormatException {
      return const {};
    }
  }

  Future<void> _setBinding(String profileId, String? learnerId) async {
    final map = Map<String, String?>.from(_bindings);
    map[profileId] = learnerId;
    await store.setString(_bindKey, jsonEncode(map));
  }

  String? learnerIdFor(String profileId) => _bindings[profileId];

  /// Finds the backend learner whose display name matches (case-insensitive)
  /// and records the mapping. Returns null when nothing was signed in or the
  /// name has no counterpart.
  Future<Result<String?>> bindProfileByName({
    required String profileId,
    required String learnerName,
  }) async {
    try {
      final learners = await api.getListJson('/learners');
      final wanted = learnerName.trim().toLowerCase();
      for (final l in learners) {
        if ('${l['display_name']}'.trim().toLowerCase() == wanted) {
          final id = l['id'].toString();
          await _setBinding(profileId, id);
          await flush(); // best-effort drain of anything queued pre-bind
          return Result.ok(id);
        }
      }
      return const Result.ok(null);
    } on AppFailure catch (f) {
      return Result.fail(f);
    }
  }

  /// Explicit binding from the profile layer (no name matching needed).
  Future<void> bindProfile({
    required String profileId,
    required String learnerId,
  }) => _setBinding(profileId, learnerId);

  /// Lessons that the live lesson runner drives directly against the API
  /// (Phase 3). Their finish events must NOT be re-queued by the mirror —
  /// the server already recorded the completion once, authoritatively.
  void registerRemoteLessons(Set<String> codes) {
    _remoteLessons.addAll(codes);
  }

  final Set<String> _remoteLessons = <String>{};

  Future<void> bindLesson({
    required String localLessonId,
    required String backendLessonId,
  }) => _setBinding('lesson:$localLessonId', backendLessonId);

  // --------------------------------------------------------------- queue

  List<SyncOp> get _queue {
    final raw = store.getString(_queueKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => SyncOp.fromJson((e as Map).cast<String, dynamic>()))
          .toList();
    } on FormatException {
      return const [];
    }
  }

  Future<void> _setQueue(List<SyncOp> ops) =>
      store.setString(_queueKey, jsonEncode(ops.map((o) => o.toJson()).toList()));

  Future<void> _enqueue(SyncOp op) async {
    final ops = [..._queue, op];
    // Keep the queue bounded: drop the oldest retry-exhausted entries first.
    await _setQueue(ops.length <= _maxQueue
        ? ops
        : ops.sublist(ops.length - _maxQueue));
  }

  Future<Result<void>> _pushOrQueue(SyncOp op) async {
    op = SyncOp(
      kind: op.kind,
      payload: {...op.payload, 'eid': _newEventId()},
      attempts: op.attempts,
    );
    if (!isEnabled) {
      await _enqueue(op);
      return const Result.ok(null); // queued; nothing to do until bound
    }
    final Result<void> outcome;
    try {
      outcome = await _deliver(op);
    } on Object {
      await _enqueue(op);
      return const Result.ok(null);
    }
    if (outcome is Fail && !_isPermanent(outcome.failure)) {
      await _enqueue(op); // retryable — sits in the durable queue
    }
    // Permanent failures (validation/forbidden) are dropped: the server said
    // no, and re-sending would say no forever. Local state already recorded
    // the learning, so the child never loses anything visible.
    return const Result.ok(null);
  }

  bool _isPermanent(AppFailure f) =>
      f.kind == FailureKind.validation || f.kind == FailureKind.forbidden;

  // --------------------------------------------------------------- mirror

  @override
  Future<void> onGameRound({
    required String profileId,
    required String gameId,
    required int score,
    required int stars,
    required double secondsSpent,
  }) => _pushOrQueue(SyncOp(kind: 'game_round', payload: {
    'profile': profileId,
    'game': _gameKeyFor(gameId),
    'score': score,
    'seconds': secondsSpent.round(),
  }));

  @override
  Future<void> onReadingMinutes({
    required String profileId,
    required int minutes,
  }) => _pushOrQueue(SyncOp(kind: 'reading_minutes', payload: {
    'profile': profileId,
    'minutes': minutes,
  }));

  @override
  Future<void> onSoundReview({
    required String profileId,
    required String phoneme,
    required int grade,
  }) => _pushOrQueue(SyncOp(kind: 'sound_review', payload: {
    'profile': profileId,
    'phoneme': phoneme,
    'grade': grade,
  }));

  @override
  Future<void> onLessonFinish({
    required String profileId,
    required String lessonId,
    required int stars,
    required double accuracy,
    required double secondsSpent,
  }) async {
    if (_remoteLessons.contains(lessonId)) {
      return; // live runner already completed this lesson server-side
    }
    await _pushOrQueue(SyncOp(kind: 'lesson_finish', payload: {
    'profile': profileId,
    'lesson': lessonId,
    'stars': stars,
    'accuracy': accuracy,
    'seconds': secondsSpent.round(),
  }));
  }

  /// Local game ids -> backend game ref_keys (the seeded dev catalog).
  static String _gameKeyFor(String gameId) {
    final key = gameId.toLowerCase().replaceAll(RegExp(r'[_\s]+'), '-');
    return const {
      'soundmatch': 'sound-match',
      'sound-match': 'sound-match',
      'bubblepop': 'word-snap',
      'bubble-pop': 'word-snap',
      'rhymeranger': 'rhyme-race',
      'rhyme-ranger': 'rhyme-race',
      'spellbuilder': 'blend-builder',
      'spell-builder': 'blend-builder',
    }[key] ?? key;
  }

  // ---------------------------------------------------------------- send

  Future<Result<void>> _deliver(SyncOp op) async {
    final profileId = op.payload['profile'] as String?;
    final learnerId = profileId == null ? null : learnerIdFor(profileId);
    if (learnerId == null) {
      return const Result.fail(AppFailure(kind: FailureKind.offline,
          message: 'not bound', detail: 'no learner binding'));
    }
    try {
      switch (op.kind) {
        case 'game_round':
          final sid = await _startSession(
            learnerId,
            {'kind': 'game', 'ref_key': op.payload['game']},
          );
          await api.postJson('/learners/$learnerId/sessions/$sid/events', body: {
            'event_type': 'game_completed',
            'payload': {
              'score': op.payload['score'],
              'game': op.payload['game'],
            },
            'client_event_id': _eventId(op),
          });
          await _abandon(learnerId, sid);
        case 'reading_minutes':
          final sid = await _startSession(learnerId, {'kind': 'reading'});
          await api.postJson('/learners/$learnerId/sessions/$sid/events', body: {
            'event_type': 'reading_practiced',
            'payload': {'minutes': op.payload['minutes']},
            'client_event_id': _eventId(op),
          });
          await _abandon(learnerId, sid);
        case 'sound_review':
          final sid = await _startSession(learnerId, {
            'kind': 'review',
            'ref_key': op.payload['phoneme'],
          });
          await api.postJson('/learners/$learnerId/sessions/$sid/events', body: {
            'event_type': 'review_graded',
            'payload': {
              'phoneme': op.payload['phoneme'],
              'grade': op.payload['grade'],
            },
            'client_event_id': _eventId(op),
          });
          await _abandon(learnerId, sid);
        case 'lesson_finish':
          final backendLesson =
              _bindings['lesson:${op.payload['lesson']}'];
          if (backendLesson == null) {
            // No content-id mapping yet (Phase 3 pipeline) — keep it queued,
            // never guess a lesson id on the server.
            return const Result.fail(AppFailure(
              kind: FailureKind.offline,
              message: 'content mapping pending',
              detail: 'lesson not mapped',
            ));
          }
          final sid = await _startSession(learnerId, {
            'kind': 'lesson',
            'ref_id': backendLesson,
          });
          await api.postJson('/learners/$learnerId/sessions/$sid/complete', body: {
            'stars': op.payload['stars'],
            'accuracy': op.payload['accuracy'],
            'seconds_spent': op.payload['seconds'],
          });
        default: // 'dropped' and unknown kinds are acknowledged and pruned
          return const Result.ok(null);
      }
      return const Result.ok(null);
    } on AppFailure catch (f) {
      return Result.fail(f);
    }
  }

  Future<String> _startSession(
    String learnerId,
    Map<String, Object?> body,
  ) async {
    final res = await api.postJson('/learners/$learnerId/sessions', body: body);
    return res['id'].toString();
  }

  Future<void> _abandon(String learnerId, String sessionId) async {
    try {
      await api.postJson('/learners/$learnerId/sessions/$sessionId/abandon');
    } on AppFailure {
      // A session left open server-side is harmless; the ledger events counted.
    }
  }

  /// Stable per-action dedupe id: minted once when the action is mirrored (so
  /// retries reuse it and cannot double-count on the server), while two real
  /// occurrences of the same action get distinct ids.
  String _newEventId() =>
      'sync-${DateTime.now().microsecondsSinceEpoch}-${_random.nextInt(0xFFFFFF)}';

  String _eventId(SyncOp op) =>
      (op.payload['eid'] ?? _newEventId()).toString();

  /// Drains the queue head-first. Stops on the first *transient* failure
  /// (network/offline) so ordering survives — the server's streak and daily
  /// task logic depends on events arriving in sequence. Permanent failures and
  /// exhausted retries are dropped so a poison op cannot block the line.
  bool _flushing = false;

  Future<int> flush() async {
    if (!isEnabled || _flushing) return 0; // one drain at a time, always ordered
    _flushing = true;
    try {
      return await _drain();
    } finally {
      _flushing = false;
    }
  }

  bool _closed = false;

  Future<int> _drain() async {
    var sent = 0;
    while (!_closed && _queue.isNotEmpty) {
      final op = _queue.first;
      final Result<void> outcome;
      try {
        outcome = await _deliver(op);
      } on Object {
        // Any raw transport error behaves like a transient failure.
        await _setQueue([
          SyncOp(kind: op.kind, payload: op.payload, attempts: op.attempts + 1),
          ..._queue.skip(1),
        ]);
        break;
      }
      if (outcome is Ok) {
        await _setQueue(_queue.skip(1).toList());
        sent++;
        continue;
      }
      final failure = (outcome as Fail).failure;
      if (_isPermanent(failure) || op.attempts + 1 >= _maxAttempts) {
        await _setQueue(_queue.skip(1).toList());
        continue;
      }
      await _setQueue([
        SyncOp(kind: op.kind, payload: op.payload, attempts: op.attempts + 1),
        ..._queue.skip(1),
      ]);
      break;
    }
    return sent;
  }

  /// Number of queued ops (tests/diagnostics).
  int get pendingCount => _queue.length;

  Future<void> dispose() async => _closed = true;
}
