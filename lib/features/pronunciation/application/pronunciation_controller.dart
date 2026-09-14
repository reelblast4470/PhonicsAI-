import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/speech/speech_service.dart';
import '../../curriculum/data/phonics_program.dart';

@immutable
class PronunciationTarget {
  const PronunciationTarget({
    required this.word,
    required this.emoji,
    required this.chunks,
    required this.tip,
  });

  final String word;
  final String emoji;

  /// Sound chunks for the "c-a-t" display.
  final List<String> chunks;
  final String tip;
}

@immutable
class PronunciationAttempt {
  const PronunciationAttempt({
    required this.word,
    required this.score,
    required this.at,
  });

  final String word;
  final PronunciationScore score;
  final DateTime at;

  int get stars => switch (score.overall) {
    >= 0.85 => 3,
    >= 0.6 => 2,
    > 0 => 1,
    _ => 0,
  };
}

/// Resolves whatever a caller passed (a word, a phoneme, a lesson id) into a
/// thing worth saying out loud, so no screen can dead-end on a bad deep link.
final pronunciationTargetProvider =
    Provider.family<PronunciationTarget?, String>((ref, id) {
  final normalised = id.trim().toLowerCase();
  if (normalised.isEmpty) return null;

  if (RegExp(r'^[a-z]+$').hasMatch(normalised) &&
      PhonicsProgram.pictures.containsKey(normalised)) {
    return PronunciationTarget(
      word: normalised,
      emoji: PhonicsProgram.emojiFor(normalised) ?? '🗣️',
      chunks: _chunks(normalised),
      tip: _tipFor(normalised),
    );
  }

  // A phoneme (or a lesson's first sound): pick a model word for it.
  for (final unit in PhonicsProgram.build()) {
    for (final phoneme in unit.phonemes) {
      if (phoneme.grapheme != normalised &&
          phoneme.grapheme.replaceAll('_', '') != normalised) {
        continue;
      }
      final word = phoneme.words.first;
      return PronunciationTarget(
        word: word,
        emoji: PhonicsProgram.emojiFor(word) ?? '🗣️',
        chunks: _chunks(word),
        tip: 'Start with ${phoneme.say} — ${phoneme.mnemonic.isEmpty ? 'nice and long' : phoneme.mnemonic}.',
      );
    }
  }

  if (RegExp(r'^[a-z]+$').hasMatch(normalised)) {
    return PronunciationTarget(
      word: normalised,
      emoji: '🗣️',
      chunks: _chunks(normalised),
      tip: 'Say each sound slowly, then push them together.',
    );
  }
  return null;
});

List<String> _chunks(String word) {
  if (word.length <= 1) return [word];
  final digraphs = ['sh', 'ch', 'th', 'wh', 'ck', 'ng', 'qu', 'ee', 'ea', 'oa', 'ai', 'ay', 'ow', 'ou', 'oo', 'ar', 'or', 'er', 'ir', 'ur'];
  final out = <String>[];
  var index = 0;
  while (index < word.length) {
    final pair = index + 1 < word.length ? word.substring(index, index + 2) : null;
    if (pair != null && digraphs.contains(pair)) {
      out.add(pair);
      index += 2;
    } else {
      out.add(word[index]);
      index++;
    }
  }
  return out;
}

String _tipFor(String word) {
  if (word.startsWith('sh')) return 'shhh — lips flat, no voice.';
  if (word.startsWith('ch')) return 'chch — a quick train puff.';
  if (word.startsWith('th')) return 'th — tongue tip gently between the teeth.';
  if (word.endsWith('e') && word.length > 3) {
    return 'The e at the end is silent — it makes the vowel say its name.';
  }
  return 'Stretch the first sound, then slide into the rest.';
}

final pronunciationControllerProvider =
    NotifierProvider.family<_PronunciationSession, List<PronunciationAttempt>, String>(
  _PronunciationSession.new,
);

/// Per-target session so a retry list does not mix words on the same screen.
class _PronunciationSession
    extends FamilyNotifier<List<PronunciationAttempt>, String> {
  @override
  List<PronunciationAttempt> build(String argument) => const [];

  void record(String word, PronunciationScore score) {
    state = [
      ...state,
      PronunciationAttempt(word: word, score: score, at: DateTime.now()),
    ];
  }
}
