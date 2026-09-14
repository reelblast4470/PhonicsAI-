import '../../../core/domain/reading_level.dart';
import 'assessment_content.dart';

/// Deterministic, explainable placement.
///
/// Not a psychometric instrument and deliberately not an "AI" decision: five
/// ordered prerequisites, one correct answer advances one band. A wrong answer
/// *above* a right answer reduces confidence instead of silently promoting,
/// because a lucky tap on the last card is the classic false positive.
class AssessmentScoring {
  const AssessmentScoring({this.questions = AssessmentContent.questions});

  final List<AssessmentQuestion> questions;

  AssessmentOutcome evaluate(List<int?> selectedOptions) {
    if (selectedOptions.length != questions.length) {
      throw ArgumentError(
        'evaluate() needs one answer slot per question '
        '(${questions.length} expected, got ${selectedOptions.length})',
      );
    }

    final results = <AssessmentResult>[];
    var correct = 0;
    var highestCorrectRank = -1;
    var lowestWrongRank = questions.length + 1;

    for (var i = 0; i < questions.length; i++) {
      final question = questions[i];
      final chosen = selectedOptions[i];
      final isCorrect = chosen == question.correctIndex;
      if (isCorrect) {
        correct++;
        highestCorrectRank =
            question.targetsLevel.rank > highestCorrectRank
            ? question.targetsLevel.rank
            : highestCorrectRank;
      } else if (question.targetsLevel.rank < lowestWrongRank) {
        lowestWrongRank = question.targetsLevel.rank;
      }
      results.add(
        AssessmentResult(
          question: question,
          selectedIndex: chosen,
          isCorrect: isCorrect,
        ),
      );
    }

    // A miss on an easier card than the best hit means the ladder has a hole:
    // start below it so nothing is taught on sand.
    var level = highestCorrectRank < 0
        ? ReadingLevel.preReader
        : ReadingLevel.values[highestCorrectRank];
    if (lowestWrongRank <= highestCorrectRank) {
      level = ReadingLevel.values[lowestWrongRank == 0
          ? 0
          : (lowestWrongRank - 1).clamp(0, ReadingLevel.values.length - 1)];
    }

    final missedEasy =
        lowestWrongRank >= 0 && lowestWrongRank <= highestCorrectRank;
    final confidence = switch ((correct, questions.length)) {
      (0, _) => 0.4,
      _ when missedEasy => 0.6,
      _ when correct == questions.length => 0.95,
      _ => 0.5 + 0.45 * correct / questions.length,
    };

    return AssessmentOutcome(
      level: level,
      results: results,
      confidence: confidence.clamp(0, 1),
      notes: _notes(results, level),
    );
  }

  List<String> _notes(List<AssessmentResult> results, ReadingLevel level) {
    final notes = <String>[
      'Start at ${level.label}: ${level.blurb}.',
    ];
    final missedSkills = results
        .where((r) => !r.isCorrect)
        .map((r) => r.question.skill)
        .toSet();
    for (final skill in missedSkills) {
      notes.add('Warm up: ${skill.description}.');
    }
    if (missedSkills.isEmpty) {
      notes.add('Everything landed — the first unit will feel easy on purpose.');
    }
    return notes;
  }
}

class AssessmentOutcome {
  const AssessmentOutcome({
    required this.level,
    required this.results,
    required this.confidence,
    required this.notes,
  });

  final ReadingLevel level;
  final List<AssessmentResult> results;
  final double confidence;
  final List<String> notes;

  int get correctCount => results.where((r) => r.isCorrect).length;
  int get total => results.length;

  bool get isConfident => confidence >= 0.8;
}

class AssessmentResult {
  const AssessmentResult({
    required this.question,
    required this.selectedIndex,
    required this.isCorrect,
  });

  final AssessmentQuestion question;
  final int? selectedIndex;
  final bool isCorrect;

  bool get skipped => selectedIndex == null;
}
