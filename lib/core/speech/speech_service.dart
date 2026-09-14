import 'dart:async';
import 'dart:math' as math;

/// Speech recognition + pronunciation scoring seam.
///
/// Real implementations: on-device ASR (speech_to_text / Android
/// `RecognizerIntent` / iOS `SFSpeechRecognizer`) or the PhonicsAI
/// pronunciation gateway. The client never holds a cloud credential — audio is
/// uploaded with a short-lived token minted by our backend.
abstract interface class SpeechService {
  bool get isAvailable;
  SpeechPermission get permission;
  Future<SpeechPermission> requestPermission();

  /// One-shot capture used by every "say it" card.
  Future<SpeechRecognition> listenOnce({
    Duration maxDuration = const Duration(seconds: 6),
    List<String>? contextWords,
    void Function(double amplitude)? onLevel,
  });

  Future<void> cancel();
}

enum SpeechPermission { granted, denied, restricted, notDetermined }

class SpeechRecognition {
  const SpeechRecognition({
    required this.transcript,
    required this.confidence,
    required this.words,
    this.audioDuration = Duration.zero,
    this.timedOut = false,
  });

  static const empty = SpeechRecognition(
    transcript: '',
    confidence: 0,
    words: [],
  );

  final String transcript;
  final double confidence;
  final List<RecognizedWord> words;
  final Duration audioDuration;
  final bool timedOut;

  bool get isEmpty => transcript.trim().isEmpty;
}

class RecognizedWord {
  const RecognizedWord({
    required this.word,
    required this.confidence,
    this.score = 0,
    this.phonemeErrors = const [],
  });

  final String word;
  final double confidence;

  /// 0..1 pronunciation score for this word (only present when the scoring
  /// service is linked).
  final double score;
  final List<String> phonemeErrors;
}

class PronunciationScore {
  const PronunciationScore({
    required this.overall,
    required this.accuracy,
    required this.fluency,
    required this.perPhoneme,
    required this.feedbackKey,
  });

  final double overall;
  final double accuracy;
  final double fluency;
  final Map<String, double> perPhoneme;

  /// Stable key into the child-friendly feedback copy (never raw model text).
  final String feedbackKey;

  static const silence = PronunciationScore(
    overall: 0,
    accuracy: 0,
    fluency: 0,
    perPhoneme: {},
    feedbackKey: 'feedback.silence',
  );
}

/// Scores a transcript against the expected text without a backend, using a
/// normalised Levenshtein distance on phoneme-ish tokens. Production replaces
/// this with the forced-alignment service; the shape stays identical.
class LexicalPronunciationScorer {
  const LexicalPronunciationScorer();

  PronunciationScore score({
    required String expected,
    required SpeechRecognition recognition,
  }) {
    if (recognition.isEmpty) return PronunciationScore.silence;
    final target = _tokens(expected);
    final heard = _tokens(recognition.transcript);
    if (target.isEmpty) return PronunciationScore.silence;
    final distance = _levenshtein(target, heard);
    final accuracy = 1 - (distance / math.max(target.length, heard.length));

    // Fluency = did the pace look like reading rather than a single blur or a
    // stall? ~0.45s per word is the target for early readers; deviation both
    // ways costs, so "cat" shouted at a 6-word sentence never scores 1.
    final seconds = recognition.audioDuration.inMilliseconds / 1000;
    final expectedSeconds = target.length * 0.45;
    final fluency = seconds <= 0 || expectedSeconds <= 0
        ? 0.0
        : (1 - ((seconds - expectedSeconds).abs() / (expectedSeconds * 1.5)))
            .clamp(0.0, 1.0);
    final perPhoneme = {
      for (final token in target)
        token: heard.contains(token) ? 1.0 : 0.35,
    };
    final overall = (accuracy * 0.75) + (fluency * 0.25);
    return PronunciationScore(
      overall: overall.clamp(0, 1),
      accuracy: accuracy.clamp(0, 1),
      fluency: fluency.clamp(0, 1),
      perPhoneme: perPhoneme,
      feedbackKey: switch (overall) {
        < 0.35 => 'feedback.try_again',
        < 0.65 => 'feedback.getting_there',
        < 0.85 => 'feedback.nice',
        _ => 'feedback.great_job',
      },
    );
  }

  static List<String> _tokens(String text) => text
      .toLowerCase()
      .replaceAll(RegExp(r"[^a-z0-9']"), ' ')
      .split(RegExp(r'\s+'))
      .where((t) => t.isNotEmpty)
      .toList();

  static int _levenshtein(List<String> a, List<String> b) {
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    var previous = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 1; i <= a.length; i++) {
      final current = [i, ...List<int>.filled(b.length, 0)];
      for (var j = 1; j <= b.length; j++) {
        current[j] = math.min(
          math.min(current[j - 1] + 1, previous[j] + 1),
          previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1),
        );
      }
      previous = current;
    }
    return previous[b.length];
  }
}

/// Offline/no-microphone implementation used in mock mode, tests and emulators.
/// It "hears" the expected word back with a plausible, slightly noisy score so
/// pronunciation screens can be built and reviewed before ASR is linked.
class MockSpeechService implements SpeechService {
  MockSpeechService({this.latency = const Duration(milliseconds: 600)});

  final Duration latency;
  final _rng = math.Random();
  SpeechPermission _permission = SpeechPermission.granted;

  @override
  bool get isAvailable => true;

  @override
  SpeechPermission get permission => _permission;

  @override
  Future<SpeechPermission> requestPermission() async =>
      _permission = SpeechPermission.granted;

  @override
  Future<SpeechRecognition> listenOnce({
    Duration maxDuration = const Duration(seconds: 6),
    List<String>? contextWords,
    void Function(double amplitude)? onLevel,
  }) async {
    for (var i = 0; i < 6; i++) {
      await Future<void>.delayed(latency ~/ 6);
      onLevel?.call(0.25 + _rng.nextDouble() * 0.7);
    }
    final word = contextWords?.isNotEmpty == true
        ? contextWords!.first
        : 'sound';
    return SpeechRecognition(
      transcript: word,
      confidence: 0.82 + _rng.nextDouble() * 0.15,
      words: [
        RecognizedWord(
          word: word,
          confidence: 0.9,
          score: 0.72 + _rng.nextDouble() * 0.25,
        ),
      ],
      audioDuration: latency * 6,
    );
  }

  @override
  Future<void> cancel() async {}
}
