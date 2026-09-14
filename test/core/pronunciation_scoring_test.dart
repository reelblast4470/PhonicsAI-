import 'package:flutter_test/flutter_test.dart';
import 'package:phonicsai/core/speech/speech_service.dart';

void main() {
  const scorer = LexicalPronunciationScorer();

  PronunciationScore grade(String heard, {int ms = 900}) => scorer.score(
        expected: 'The cat sat on the mat',
        recognition: SpeechRecognition(
          transcript: heard,
          confidence: 0.9,
          words: const [],
          audioDuration: Duration(milliseconds: ms),
        ),
      );

  test('perfect repetition scores highest', () {
    expect(grade('the cat sat on the mat').overall,
        greaterThan(grade('the cat on the mat').overall));
  });

  test('silence is reported as silence, not as a zero score', () {
    final result = scorer.score(
      expected: 'cat',
      recognition: SpeechRecognition.empty,
    );
    expect(result.feedbackKey, 'feedback.silence');
    expect(result.overall, 0);
  });

  test('a substituted sound is caught as a phoneme error', () {
    final result = grade('the cat sat on the mat'.replaceAll('mat', 'map'));
    expect(result.perPhoneme['map'], isNot(1.0));
    expect(result.accuracy, lessThan(1));
  });

  test('score stays inside 0..1 even with a long ramble', () {
    final result = grade('cat cat cat cat cat cat cat cat dog dog', ms: 9000);
    expect(result.overall, inInclusiveRange(0, 1));
    expect(result.fluency, inInclusiveRange(0, 1));
  });

  test('feedback buckets are monotonic with accuracy', () {
    expect(grade('cat').feedbackKey, 'feedback.try_again');
    expect(grade('the cat sat on the').feedbackKey, isNot('feedback.silence'));
    expect(grade('the cat sat on the mat').feedbackKey,
        anyOf('feedback.great_job', 'feedback.nice'));
  });
}
