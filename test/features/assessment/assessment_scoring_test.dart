import 'package:flutter_test/flutter_test.dart';
import 'package:phonicsai/core/domain/reading_level.dart';
import 'package:phonicsai/features/assessment/domain/assessment_content.dart';
import 'package:phonicsai/features/assessment/domain/assessment_scoring.dart';

void main() {
  const questions = AssessmentContent.questions;
  const scoring = AssessmentScoring();

  /// Answer every card correctly except the ids in [wrongIds].
  List<int?> answers({Set<String> wrongIds = const {}}) => [
        for (final q in questions)
          wrongIds.contains(q.id)
              ? (q.correctIndex + 1) % q.options.length
              : q.correctIndex,
      ];

  test('all correct places the learner at the top band', () {
    final outcome = scoring.evaluate(answers());
    expect(outcome.correctCount, questions.length);
    expect(outcome.level, ReadingLevel.fluentReader);
    expect(outcome.confidence, greaterThan(0.9));
    expect(outcome.isConfident, isTrue);
  });

  test('nothing correct starts at the first band with low confidence', () {
    final outcome = scoring.evaluate(
      answers(wrongIds: questions.map((q) => q.id).toSet()),
    );
    expect(outcome.level, ReadingLevel.preReader);
    expect(outcome.confidence, lessThan(0.5));
    expect(outcome.isConfident, isFalse);
  });

  test('a hole in the ladder demotes instead of promoting', () {
    // Right on the hardest card but wrong on the easiest: cannot be placed at
    // the top band, because /s/ is not secure yet.
    final outcome = scoring.evaluate(answers(wrongIds: {'a1'}));
    expect(outcome.level.index, lessThan(ReadingLevel.fluentReader.index));
    expect(outcome.isConfident, isFalse);
  });

  test('blending only lands on the CVC band', () {
    final onlyBlending = [
      for (final q in questions)
        q.skill == PhonicsSkill.blending ? q.correctIndex : (q.correctIndex + 1) % q.options.length,
    ];
    final outcome = scoring.evaluate(onlyBlending);
    expect(outcome.level, ReadingLevel.preReader,
        reason: 'easier cards were missed, so start below blending');
    expect(outcome.notes.any((n) => n.contains('Warm up')), isTrue);
  });

  test('notes name every missed skill exactly once', () {
    final outcome = scoring.evaluate(answers(wrongIds: {'a1', 'a2'}));
    expect(
      outcome.notes.where((n) => n.startsWith('Warm up')).length,
      2,
      reason: 'two distinct skills were missed',
    );
  });

  test('skipping (null answers) is handled and never promotes', () {
    final outcome = scoring.evaluate(List<int?>.filled(questions.length, null));
    expect(outcome.correctCount, 0);
    expect(outcome.level, ReadingLevel.preReader);
    expect(outcome.results.every((r) => r.skipped), isTrue);
  });

  test('evaluate guards against a mismatched answer sheet', () {
    expect(() => scoring.evaluate(const [0, 1]), throwsA(isA<ArgumentError>()));
  });

  test('the content set is teachable in order', () {
    expect(questions.length, greaterThanOrEqualTo(5));
    for (var i = 1; i < questions.length; i++) {
      expect(
        questions[i].targetsLevel.rank >= questions[i - 1].targetsLevel.rank,
        isTrue,
        reason: '${questions[i].id} is easier than the card before it',
      );
    }
    for (final q in questions) {
      expect(q.correctIndex, inInclusiveRange(0, q.options.length - 1));
      expect(
        q.options[q.correctIndex].word.toLowerCase(),
        anyOf(contains('s'), contains('b'), contains('cat'), contains('rat'),
            contains('ship'), contains('cake')),
      );
    }
  });
}
