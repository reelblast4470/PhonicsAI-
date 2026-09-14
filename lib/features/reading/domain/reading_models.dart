import 'package:flutter/foundation.dart';

import '../../../core/domain/reading_level.dart';
import '../../../core/util/math_util.dart';

@immutable
class DecodablePassage {
  const DecodablePassage({
    required this.id,
    required this.title,
    required this.level,
    required this.sentences,
    required this.targetPhonemes,
    this.emoji = '📖',
  });

  final String id;
  final String title;
  final ReadingLevel level;

  /// One entry per sentence. Words are split at render time so a learner can
  /// tap any single word of the text.
  final List<String> sentences;
  final List<String> targetPhonemes;
  final String emoji;

  List<String> get words => sentences
      .join(' ')
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .toList(growable: false);

  int get wordCount => words.length;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'level': level.code,
        'sentences': sentences,
        'phonemes': targetPhonemes,
      };
}

/// What one read-aloud measured. Accuracy credits self-corrections (OR-1
/// scoring, the convention teachers already use) instead of treating every
/// stumble as a failure.
@immutable
class ReadingAttempt {
  const ReadingAttempt({
    required this.passageId,
    required this.wordsRead,
    required this.errors,
    required this.selfCorrections,
    required this.duration,
    required this.at,
  });

  final String passageId;
  final int wordsRead;
  final int errors;
  final int selfCorrections;
  final Duration duration;
  final DateTime at;

  int get minutesTowardGoal => (duration.inSeconds / 60).ceil();

  int get wordsPerMinute => duration.inSeconds <= 0
      ? 0
      : (wordsRead / (duration.inSeconds / 60)).round();

  double get accuracy => wordsRead == 0
      ? 0
      : MathUtil.clamp(
          (wordsRead - errors + selfCorrections) / wordsRead,
          0,
          1,
        );

  static int fluencyFloorFor(ReadingLevel level) => switch (level) {
        ReadingLevel.preReader => 15,
        ReadingLevel.letterSounds => 25,
        ReadingLevel.cvcBlender => 40,
        ReadingLevel.earlyDecoder => 55,
        ReadingLevel.fluentReader => 70,
      };

  bool isFluentFor(ReadingLevel level) =>
      wordsPerMinute >= fluencyFloorFor(level) && accuracy >= 0.9;

  Map<String, dynamic> toJson() => {
        'passage_id': passageId,
        'words': wordsRead,
        'errors': errors,
        'self_corrections': selfCorrections,
        'seconds': duration.inSeconds,
        'at': at.toIso8601String(),
      };

  factory ReadingAttempt.fromJson(Map<String, dynamic> json) => ReadingAttempt(
        passageId: json['passage_id'] as String,
        wordsRead: (json['words'] as num?)?.toInt() ?? 0,
        errors: (json['errors'] as num?)?.toInt() ?? 0,
        selfCorrections: (json['self_corrections'] as num?)?.toInt() ?? 0,
        duration: Duration(seconds: (json['seconds'] as num?)?.toInt() ?? 0),
        at: DateTime.tryParse(json['at'] as String? ?? '') ?? DateTime.now(),
      );
}

/// Accumulates taps during a read-aloud and produces a [ReadingAttempt].
class ReadingTally {
  ReadingTally({required this.passage, required this.startedAt});

  final DecodablePassage passage;
  final DateTime startedAt;
  final Map<int, int> _errorsByWord = {};
  final Set<int> _selfCorrected = {};
  DateTime? _finishedAt;

  Duration? get duration => _finishedAt?.difference(startedAt);
  int get errorCount => _errorsByWord.values.fold(0, (a, b) => a + b);

  void markError(int wordIndex) =>
      _errorsByWord[wordIndex] = (_errorsByWord[wordIndex] ?? 0) + 1;

  /// "I fixed it myself" — a tap on a word that was already marked wrong.
  void markSelfCorrection(int wordIndex) {
    if ((_errorsByWord[wordIndex] ?? 0) > 0) _selfCorrected.add(wordIndex);
  }

  void finish() => _finishedAt = DateTime.now();

  ReadingAttempt toAttempt() => ReadingAttempt(
        passageId: passage.id,
        wordsRead: passage.wordCount,
        errors: errorCount,
        selfCorrections: _selfCorrected.length,
        duration: duration ?? Duration.zero,
        at: _finishedAt ?? DateTime.now(),
      );
}
