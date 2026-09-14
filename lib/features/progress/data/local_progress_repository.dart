import 'dart:async';

import '../../../core/error/failure.dart';
import '../../../core/result/result.dart';
import '../../../core/storage/collection_store.dart';
import '../../../core/storage/key_value_store.dart';
import '../../../core/util/date_util.dart';
import '../../../features/progress/domain/spaced_repetition.dart';
import '../domain/progress_models.dart';
import '../domain/progress_repository.dart';

/// Offline-first progress. Every tap in a lesson writes here *immediately*, so
/// a tablet that dies mid-lesson loses at most the current stage.
///
/// The backend mirror (when it exists) is a queue: writes go local-first and
/// `pendingSync` rows are pushed opportunistically — the UI never waits on the
/// network to show progress.
class LocalProgressRepository implements ProgressRepository {
  LocalProgressRepository({required KeyValueStore store})
    : _lessons = CollectionStore<LessonProgress>(
        store: store,
        namespace: lessonNamespace,
        fromJson: LessonProgress.fromJson,
        toJson: (value) => value.toJson(),
      ),
      _mastery = CollectionStore<PhonemeMastery>(
        store: store,
        namespace: masteryNamespace,
        fromJson: PhonemeMastery.fromJson,
        toJson: (value) => value.toJson(),
      ),
      _sessions = CollectionStore<DaySession>(
        store: store,
        namespace: sessionNamespace,
        fromJson: DaySession.fromJson,
        toJson: (value) => value.toJson(),
      ),
      _games = CollectionStore<GameRecord>(
        store: store,
        namespace: gameNamespace,
        fromJson: GameRecord.fromJson,
        toJson: (value) => value.toJson(),
      ),
      _wallet = CollectionStore<_Wallet>(
        store: store,
        namespace: walletNamespace,
        fromJson: _Wallet.fromJson,
        toJson: (value) => value.toJson(),
      );

  static const lessonNamespace = 'phonicsai.lesson_progress';
  static const masteryNamespace = 'phonicsai.phoneme_mastery';
  static const sessionNamespace = 'phonicsai.session_log';
  static const gameNamespace = 'phonicsai.game_records';
  static const walletNamespace = 'phonicsai.wallet';

  final CollectionStore<LessonProgress> _lessons;
  final CollectionStore<PhonemeMastery> _mastery;
  final CollectionStore<DaySession> _sessions;
  final CollectionStore<GameRecord> _games;
  final CollectionStore<_Wallet> _wallet;

  final _changed = StreamController<void>.broadcast();
  final _snapshots = <String, ProfileSnapshot>{};
  bool _loaded = false;

  @override
  Future<void> warmUp(String profileId) => _load();

  Future<void> _load() async {
    if (_loaded) return;
    await Future.wait([
      _lessons.load(),
      _mastery.load(),
      _sessions.load(),
      _games.load(),
      _wallet.load(),
    ]);
    for (final stream in [
      _lessons.changes,
      _mastery.changes,
      _sessions.changes,
      _games.changes,
      _wallet.changes,
    ]) {
      stream.listen((_) => _notify());
    }
    _loaded = true;
  }

  void _notify() {
    _snapshots.clear();
    if (!_changed.isClosed) _changed.add(null);
  }

  @override
  Stream<ProfileSnapshot> watch(String profileId) {
    late final StreamController<ProfileSnapshot> controller;
    StreamSubscription<void>? sub;
    controller = StreamController<ProfileSnapshot>(
      onListen: () async {
        await _load();
        if (controller.isClosed) return;
        controller.add(snapshot(profileId));
        sub = _changed.stream.listen((_) {
          if (!controller.isClosed) controller.add(snapshot(profileId));
        });
      },
      onCancel: () async => sub?.cancel(),
    );
    return controller.stream;
  }

  @override
  ProfileSnapshot snapshot(String profileId) {
    final cached = _snapshots[profileId];
    if (cached != null) return cached;

    final prefix = '${profileId}__';
    final lessons = {
      for (final lesson
          in _lessons.all.where((l) => l.lessonId.startsWith(prefix)))
        lesson.lessonId.substring(prefix.length): lesson,
    };
    final mastery = {
      for (final entry in _mastery.all)
        if (entry.phoneme.startsWith(prefix))
          entry.phoneme.substring(prefix.length): entry,
    };
    final games = {
      for (final record in _games.all)
        if (record.gameId.startsWith(prefix))
          record.gameId.substring(prefix.length): record,
    };
    final sessions = _sessions.sorted((a, b) => a.date.compareTo(b.date));

    final snapshot = ProfileSnapshot(
      profileId: profileId,
      lessons: lessons,
      mastery: mastery,
      sessions: sessions,
      gameRecords: games,
      starsEarned: _wallet.byId(profileId)?.stars ?? 0,
    );
    _snapshots[profileId] = snapshot;
    return snapshot;
  }

  @override
  Future<Result<void>> completeStage({
    required String profileId,
    required String lessonId,
    required String stageId,
  }) async {
    await _load();
    final key = _key(profileId, lessonId);
    final current = _lessons.byId(key) ??
        LessonProgress(lessonId: key, completedStages: const []);
    await _lessons.put(key, current.withStage(stageId));
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> finishLesson({
    required String profileId,
    required String lessonId,
    required int stars,
    required double accuracy,
    required int xp,
    required double secondsSpent,
    required List<String> phonemes,
  }) async {
    await _load();
    final key = _key(profileId, lessonId);
    final current = _lessons.byId(key) ??
        LessonProgress(lessonId: key, completedStages: const []);
    await _lessons.put(
      key,
      LessonProgress(
        lessonId: key,
        // A finished lesson is complete regardless of how many stages were
        // clicked through — the review stage closes the loop.
        completedStages: const [
          'discover', 'hear', 'see', 'understand', 'practice', //
          'play', 'recall', 'speak', 'read', 'review',
        ],
        stars: stars > current.stars ? stars : current.stars,
        attempts: current.attempts + 1,
        bestAccuracy:
            accuracy > current.bestAccuracy ? accuracy : current.bestAccuracy,
        updatedAt: DateTime.now(),
      ),
    );

    await _bumpWallet(profileId, xp);
    await _bumpToday(
      profileId,
      DaySession(
        date: DateTime.now(),
        seconds: secondsSpent.round(),
        stars: xp,
        lessonsCompleted: 1,
      ),
    );
    for (final phoneme in phonemes) {
      await recordSoundReview(
        profileId: profileId,
        phoneme: phoneme,
        grade: accuracy >= 0.85 ? 5 : (accuracy >= 0.6 ? 3 : 1),
      );
    }
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> recordSoundReview({
    required String profileId,
    required String phoneme,
    required int grade,
  }) async {
    if (phoneme.isEmpty) {
      return const Result.fail(
        AppFailure(
          kind: FailureKind.validation,
          message: 'No sound to review.',
        ),
      );
    }
    await _load();
    final key = _key(profileId, phoneme);
    final current = _mastery.byId(key) ?? PhonemeMastery(phoneme: key);
    final updated = SpacedRepetition.review(
      PhonemeMastery(
        phoneme: key,
        status: current.status,
        reps: current.reps,
        correct: current.correct,
        lapses: current.lapses,
        ease: current.ease,
        intervalDays: current.intervalDays,
        dueAt: current.dueAt,
        lastSeenAt: current.lastSeenAt,
      ),
      grade: grade,
    );
    await _mastery.put(key, updated);
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> recordGameRound({
    required String profileId,
    required String gameId,
    required int score,
    required int stars,
    required double secondsSpent,
  }) async {
    await _load();
    final key = _key(profileId, gameId);
    final current = _games.byId(key) ?? GameRecord(gameId: key);
    await _games.put(
      key,
      GameRecord(
        gameId: key,
        bestScore: score > current.bestScore ? score : current.bestScore,
        plays: current.plays + 1,
      ),
    );
    await _bumpWallet(profileId, stars);
    await _bumpToday(
      profileId,
      DaySession(
        date: DateTime.now(),
        seconds: secondsSpent.round(),
        stars: stars,
        gamesPlayed: 1,
      ),
    );
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> addReadingMinutes({
    required String profileId,
    required int minutes,
  }) async {
    await _load();
    await _bumpToday(
      profileId,
      DaySession(
        date: DateTime.now(),
        seconds: minutes * 60,
        minutesReadAloud: minutes,
      ),
    );
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> recordStageAnswer({
    required String profileId,
    required String stageKey,
    required bool isCorrect,
  }) async {
    await _load();
    await recordSoundReview(
      profileId: profileId,
      phoneme: stageKey,
      grade: isCorrect ? 4 : 0,
    );
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> reset(String profileId) async {
    await _load();
    final prefix = '${profileId}__';
    for (final key in _lessons.store.keysStartingWith('$lessonNamespace.$prefix')) {
      await _lessons.store.remove(key);
    }
    for (final key in _mastery.store.keysStartingWith('$masteryNamespace.$prefix')) {
      await _mastery.store.remove(key);
    }
    for (final key in _games.store.keysStartingWith('$gameNamespace.$prefix')) {
      await _games.store.remove(key);
    }
    for (final key in _sessions.store.keysStartingWith('$sessionNamespace.$prefix')) {
      await _sessions.store.remove(key);
    }
    await _wallet.remove(profileId);
    _notify();
    return const Result.ok(null);
  }

  Future<void> _bumpWallet(String profileId, int delta) async {
    final current = _wallet.byId(profileId) ??
        _Wallet(profileId: profileId, stars: 0);
    await _wallet.put(
      profileId,
      _Wallet(profileId: profileId, stars: current.stars + delta),
    );
  }

  Future<void> _bumpToday(String profileId, DaySession addition) async {
    final key = _key(profileId, addition.key);
    final existing = _sessions.byId(key);
    await _sessions.put(
      key,
      existing == null ? addition : existing.merge(addition),
    );
  }

  static String _key(String profileId, String suffix) => '${profileId}__$suffix';

  Future<void> dispose() async {
    await _changed.close();
    await Future.wait([
      _lessons.dispose(),
      _mastery.dispose(),
      _sessions.dispose(),
      _games.dispose(),
      _wallet.dispose(),
    ]);
  }
}

/// Practice streak: consecutive days with at least one logged second.
abstract final class StreakCalculator {
  static int current(List<DaySession> sessions, {DateTime? now}) {
    final today = DateUtil.startOfDay(now ?? DateTime.now());
    final activeDays = sessions
        .where((s) => s.seconds > 0)
        .map((s) => DateUtil.startOfDay(s.date))
        .toSet();
    if (!activeDays.contains(today) &&
        !activeDays.contains(DateUtil.addDays(today, -1))) {
      return 0;
    }
    var cursor = activeDays.contains(today)
        ? today
        : DateUtil.addDays(today, -1);
    var streak = 0;
    while (activeDays.contains(cursor)) {
      streak++;
      cursor = DateUtil.addDays(cursor, -1);
    }
    return streak;
  }

  static int longest(List<DaySession> sessions) {
    if (sessions.isEmpty) return 0;
    final days = sessions
        .where((s) => s.seconds > 0)
        .map((s) => DateUtil.startOfDay(s.date))
        .toSet();
    var best = 0;
    for (final day in days) {
      if (days.contains(DateUtil.addDays(day, -1))) continue;
      var length = 0;
      var cursor = day;
      while (days.contains(cursor)) {
        length++;
        cursor = DateUtil.addDays(cursor, 1);
      }
      if (length > best) best = length;
    }
    return best;
  }
}

class _Wallet {
  const _Wallet({required this.profileId, required this.stars});

  factory _Wallet.fromJson(Map<String, dynamic> json) => _Wallet(
        profileId: json['profile_id'] as String,
        stars: (json['stars'] as num?)?.toInt() ?? 0,
      );

  final String profileId;
  final int stars;

  Map<String, dynamic> toJson() =>
      {'profile_id': profileId, 'stars': stars};

  @override
  String toString() => profileId;
}
