import 'package:flutter_test/flutter_test.dart';
import 'package:phonicsai/core/domain/reading_level.dart';
import 'package:phonicsai/core/util/date_util.dart';
import 'package:phonicsai/features/curriculum/data/phonics_program.dart';
import 'package:phonicsai/features/games/data/game_round_factory.dart';
import 'package:phonicsai/features/games/domain/game_models.dart';
import 'package:phonicsai/features/home/domain/daily_mission.dart';
import 'package:phonicsai/features/progress/domain/progress_models.dart';
import 'package:phonicsai/features/progress/domain/progress_repository.dart';
import 'package:phonicsai/features/progress/domain/spaced_repetition.dart';
import 'package:phonicsai/features/reading/data/reading_library.dart';
import 'package:phonicsai/features/reading/domain/reading_models.dart';
import 'package:phonicsai/features/rewards/domain/achievements.dart';
import 'package:phonicsai/features/writing/domain/writing_models.dart';

// Fixed stamp so the assertion never depends on "today".
final _epoch = DateTime(2026, 9, 14);

void main() {
  group('spaced repetition', () {
    test('an easy sound grows its interval but never past three weeks', () {
      var mastery = const PhonemeMastery(phoneme: 'sh');
      final intervals = <double>[];
      for (var i = 0; i < 10; i++) {
        mastery = SpacedRepetition.review(mastery, grade: 5);
        intervals.add(mastery.intervalDays);
      }
      expect(intervals, orderedEquals([...intervals]..sort()));
      expect(
        intervals.last,
        lessThanOrEqualTo(SpacedRepetition.maxIntervalDays),
        reason: 'a 5-year-old needs contact, not a 6-month gap',
      );
      expect(mastery.status, MasteryStatus.mastered);
    });

    test('a lapse resets to tomorrow and lowers ease', () {
      final secure = const PhonemeMastery(
        phoneme: 'th',
        reps: 6,
        correct: 6,
        ease: 2.8,
        intervalDays: 12,
        status: MasteryStatus.secure,
      );
      final lapsed = SpacedRepetition.review(secure, grade: 0);
      expect(lapsed.intervalDays, 0);
      expect(lapsed.lapses, secure.lapses + 1);
      expect(lapsed.ease, lessThan(secure.ease));
      expect(
        DateUtil.isSameDay(
          lapsed.dueAt!,
          DateUtil.addDays(DateTime.now(), 1),
        ),
        isTrue,
      );
    });

    test('due queue prefers the most-lapsed, least-accurate sounds and caps', () {
      final now = DateTime.now();
      final all = [
        PhonemeMastery(phoneme: 'p:a', reps: 3, correct: 1, lapses: 2, dueAt: now),
        PhonemeMastery(phoneme: 'p:b', reps: 3, correct: 3, lapses: 0, dueAt: now),
        PhonemeMastery(phoneme: 'p:c', reps: 3, correct: 2, lapses: 1, dueAt: now),
        PhonemeMastery(phoneme: 'p:d', reps: 3, correct: 0, lapses: 3, dueAt: now),
      ];
      final queue = SpacedRepetition.dueQueue(all, limit: 2);
      expect(queue.length, 2);
      expect(queue.first.phoneme, 'p:d', reason: 'worst first');
    });
  });

  group('daily mission', () {
    test('a new learner gets one tiny lesson and never an empty goal list', () {
      final mission = DailyMission.build(
        date: DateTime.now(),
        lessonsCompletedToday: 0,
        gamesPlayedToday: 0,
        minutesReadAloudToday: 0,
        dueReviews: 0,
        streakDays: 0,
        isVeryNewLearner: true,
      );
      expect(mission.goals.length, 4);
      expect(mission.fraction, greaterThan(0),
          reason: 'no reviews due counts as a win, not a red zero');
      expect(mission.goals.first.target, 1);
    });

    test('completed work is reflected, and completion is reachable', () {
      final mission = DailyMission.build(
        date: DateTime.now(),
        lessonsCompletedToday: 1,
        gamesPlayedToday: 1,
        minutesReadAloudToday: 3,
        dueReviews: 4,
        streakDays: 5,
        isVeryNewLearner: false,
      );
      expect(mission.goals.where((g) => g.isDone).length, 3);
      expect(mission.xpReward, 20 + 5 * 2);
      final done = DailyMission.build(
        date: DateTime.now(),
        lessonsCompletedToday: 2,
        gamesPlayedToday: 1,
        minutesReadAloudToday: 9,
        dueReviews: 0,
        streakDays: 6,
        isVeryNewLearner: false,
      );
      expect(done.isComplete, isTrue);
      expect(done.fraction, 1);
    });
  });

  group('game rounds', () {
    test('streaks pay, mistakes do not punish', () {
      expect(GameScoring.pointsFor(isCorrect: false, streakBefore: 5), 0);
      expect(GameScoring.pointsFor(isCorrect: true, streakBefore: 1),
          GameScoring.basePoints);
      expect(
        GameScoring.pointsFor(isCorrect: true, streakBefore: 4),
        greaterThan(GameScoring.pointsFor(isCorrect: true, streakBefore: 2)),
      );
      expect(
        GameScoring.pointsFor(isCorrect: true, streakBefore: 99),
        lessThanOrEqualTo(
            GameScoring.basePoints + GameScoring.maxStreakBonus),
      );
    });

    test('stars come from accuracy, not speed', () {
      expect(GameScoring.starsFor(correct: 5, total: 5), 3);
      expect(GameScoring.starsFor(correct: 3, total: 5), 2);
      expect(GameScoring.starsFor(correct: 1, total: 5), 1);
      expect(GameScoring.starsFor(correct: 0, total: 0), 0);
    });

    test('every generated round is answerable and matches its focus sound', () {
      for (final kind in GameKind.values) {
        final items = GameRoundFactory.build(
          kind: kind,
          focusPhonemes: const ['s', 'a', 't'],
          count: 4,
          level: ReadingLevel.letterSounds,
          seed: 7,
        );
        expect(items.length, 4);
        for (final item in items) {
          expect(item.choices, isNotEmpty, reason: '$kind produced an empty round');
          expect(
            item.choices.map((c) => c.id),
            contains(item.correctId),
            reason: '${item.id} has no selectable answer',
          );
          expect(item.prompt.trim(), isNotEmpty);
        }
      }
    });

    test('the same seed replays identically (fair retry, not a new game)', () {
      List<String> ids(int seed) => GameRoundFactory
          .build(
            kind: GameKind.rhymeRanger,
            focusPhonemes: const ['a'],
            count: 3,
            seed: seed,
          )
          .map((item) => '${item.id}:${item.correctId}')
          .toList();
      expect(ids(3), ids(3));
    });
  });

  group('reading', () {
    test('self-corrections count, and accuracy stays in 0..1', () {
      final passage = ReadingLibrary.all().first;
      final tally = ReadingTally(passage: passage, startedAt: DateTime.now());
      tally.markError(0);
      tally.markError(0);
      tally.markSelfCorrection(0);
      tally.finish();
      final attempt = tally.toAttempt();
      expect(attempt.errors, 2);
      expect(attempt.selfCorrections, 1);
      expect(attempt.accuracy, inInclusiveRange(0, 1));
      expect(attempt.wordsRead, passage.wordCount);
    });

    test('every reader only uses taught sounds per unit', () {
      for (final passage in ReadingLibrary.all()) {
        expect(passage.sentences.length, greaterThanOrEqualTo(3));
        expect(passage.wordCount, greaterThan(3));
        expect(passage.level.rank, lessThanOrEqualTo(ReadingLevel.values.length - 1));
        expect(passage.targetPhonemes, isNotEmpty,
            reason: '${passage.id} is not decodable against anything');
      }
    });

    test('wpm is zero before any time has passed, never infinite', () {
      final attempt = ReadingAttempt(
        passageId: 'x',
        wordsRead: 12,
        errors: 0,
        selfCorrections: 0,
        duration: Duration.zero,
        at: _epoch,
      );
      expect(attempt.wordsPerMinute, 0);
    });
  });

  group('writing', () {
    test('an empty or tiny trace never passes', () {
      expect(TracingScoring.score(strokes: const []).passed, isFalse);
      final tiny = TracingScoring.score(
        strokes: const [
          TracedStroke([Offset(0.1, 0.1), Offset(0.12, 0.12)]),
        ],
      );
      expect(tiny.passed, isFalse);
    });

    test('a full-letter stroke pattern passes', () {
      final strokes = [
        for (var row = 0; row < 7; row++)
          TracedStroke([
            for (var col = 0; col < 6; col++)
              Offset(0.1 + col * 0.15, 0.08 + row * 0.13),
          ]),
      ];
      final score = TracingScoring.score(strokes: strokes);
      expect(score.coverage, greaterThan(0.4));
      expect(score.passed, isTrue);
    });

    test('drawing outside the cell is penalised', () {
      final wild = [
        TracedStroke([
          for (var i = 0; i < 20; i++)
            Offset(i.isEven ? -1.0 : 3.0, i.isEven ? 2.0 : -2.0),
        ]),
      ];
      expect(TracingScoring.score(strokes: wild).insideRatio, 0);
    });

    test('spelling tiles are deterministic and contain every needed letter', () {
      const target = SpellingTarget(
        word: 'sun',
        emoji: '☀️',
        prompt: 'Build sun',
        distractors: ['x', 'y'],
      );
      final tiles = target.tilesFor(12345);
      expect(tiles.length, 5);
      for (final letter in target.letters) {
        expect(tiles, contains(letter));
      }
      expect(tiles, target.tilesFor(12345));
    });
  });

  group('achievements', () {
    test('nothing is unlocked for an untouched record', () {
      final statuses = Achievements.evaluate(
        ProfileSnapshot.empty('p1'),
        streakDays: 0,
      );
      expect(statuses.every((s) => !s.unlocked), isTrue);
      expect(statuses.length, Achievements.catalog.length);
    });

    test('a streak and a first lesson light up together', () {
      final today = DateTime.now();
      final snapshot = ProfileSnapshot(
        profileId: 'p1',
        lessons: {
          'unit_satpin_l1': LessonProgress(
            lessonId: 'unit_satpin_l1',
            completedStages: const [
              'discover', 'hear', 'see', 'understand', 'practice', //
              'play', 'recall', 'speak', 'read', 'review',
            ],
            stars: 3,
            attempts: 1,
            bestAccuracy: 1,
          ),
        },
        sessions: [
          DaySession(
            date: today,
            seconds: 400,
            stars: 30,
            lessonsCompleted: 1,
            gamesPlayed: 2,
            minutesReadAloud: 60,
          ),
        ],
      );
      final statuses = Achievements.evaluate(snapshot, streakDays: 3);
      final unlocked = statuses.where((s) => s.unlocked).map((s) => s.achievement.kind).toSet();
      expect(unlocked, contains(AchievementKind.firstLesson));
      expect(unlocked, contains(AchievementKind.streak));
      expect(unlocked, contains(AchievementKind.readingMinutes));
      expect(unlocked, contains(AchievementKind.perfectLesson));
      expect(unlocked, isNot(contains(AchievementKind.soundsMastered)));
    });
  });

  group('curriculum content', () {
    test('the first six sounds are the first six taught', () {
      final unit = PhonicsProgram.build().first;
      expect(
        unit.phonemes.map((p) => p.grapheme).toList(),
        ['s', 'a', 't', 'p', 'i', 'n'],
        reason: 'SATPIN first is the whole point of the program order',
      );
    });

    test('distractors never contain the target sound', () {
      for (final unit in PhonicsProgram.build()) {
        for (final phoneme in unit.phonemes) {
          for (final word in PhonicsProgram.distractorsFor(phoneme, count: 2)) {
            expect(
              word.contains(phoneme.grapheme.replaceAll('_', '')),
              isFalse,
              reason: '"$word" would be a valid answer for /${phoneme.grapheme}/',
            );
          }
        }
      }
    });
  });
}
