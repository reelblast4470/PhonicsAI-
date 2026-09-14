import 'dart:math' as math;

import '../../../core/domain/reading_level.dart';
import '../../curriculum/data/phonics_program.dart';
import '../../curriculum/domain/phoneme.dart';
import '../domain/game_models.dart';

/// Builds a round from the sounds the learner is currently learning.
///
/// That is the whole point of the games: they are not generic "kids games",
/// they drill the exact phonemes from the last two lessons plus one recycled
/// sound from further back (interleaving — the effect that makes recall stick).
abstract final class GameRoundFactory {
  static List<GameItem> build({
    required GameKind kind,
    required List<String> focusPhonemes,
    required int count,
    ReadingLevel level = ReadingLevel.letterSounds,
    int seed = 0,
  }) {
    final pool = _phonemePool(focusPhonemes);
    final rng = math.Random(seed + kind.index);
    final items = <GameItem>[];
    for (var i = 0; i < count; i++) {
      final phoneme = pool[i % pool.length];
      items.add(switch (kind) {
        GameKind.soundMatch => _matchRound(phoneme, i),
        GameKind.bubblePop => _bubbleRound(phoneme, i, rng),
        GameKind.rhymeRanger => _rhymeRound(phoneme, i, rng),
        GameKind.spellBuilder => _spellRound(phoneme, i),
      });
    }
    return items;
  }

  static List<Phoneme> _phonemePool(List<String> focusPhonemes) {
    final all = [for (final unit in PhonicsProgram.build()) ...unit.phonemes];
    final byGrapheme = {for (final p in all) p.grapheme: p};
    final picked = <Phoneme>[];
    for (final grapheme in focusPhonemes) {
      final match = byGrapheme[grapheme];
      if (match != null) picked.add(match);
    }
    if (picked.isEmpty) picked.addAll(all.take(4));
    // Interleave one older sound when the learner already has focus sounds.
    if (focusPhonemes.isNotEmpty && picked.length < 3) {
      for (final candidate in all.reversed) {
        if (picked.length >= 3) break;
        if (!picked.any((p) => p.grapheme == candidate.grapheme)) {
          picked.add(candidate);
        }
      }
    }
    return picked;
  }

  static GameItem _matchRound(Phoneme phoneme, int index) {
    final word = phoneme.words[index % phoneme.words.length];
    final other = _distractorWord(phoneme);
    final choices = [
      GameChoice(id: 'p_$word', label: PhonicsProgram.emojiFor(word) ?? '🖼️', pairId: word),
      GameChoice(id: 'w_$word', label: word, pairId: word),
      GameChoice(id: 'p_$other', label: PhonicsProgram.emojiFor(other) ?? '🖼️', pairId: other),
      GameChoice(id: 'w_$other', label: other, pairId: other),
    ];
    return GameItem(
      id: 'match_${phoneme.grapheme}_$index',
      prompt: 'Match ${PhonicsProgram.emojiFor(word) ?? 'the picture'} to its word',
      choices: choices,
      // Sound Match validates pairs itself; correctId is the target word.
      correctId: 'w_$word',
      phoneme: phoneme.grapheme,
      hint: 'Say ${phoneme.say}, then find the word that starts with it.',
    );
  }

  static GameItem _bubbleRound(Phoneme phoneme, int index, math.Random rng) {
    final targets = phoneme.words.take(3).toList();
    final decoys = <String>[
      for (final other in PhonicsProgram.build().expand((u) => u.phonemes))
        if (other.grapheme != phoneme.grapheme)
          for (final word in other.words)
            if (!word.contains(phoneme.grapheme.replaceAll('_', ''))) word,
    ].take(6).toList();
    final choices = <GameChoice>[
      for (final word in targets)
        GameChoice(id: 'b_$word', label: word, emoji: PhonicsProgram.emojiFor(word)),
      for (final word in decoys.take(3))
        GameChoice(id: 'b_$word', label: word, emoji: PhonicsProgram.emojiFor(word)),
    ]..shuffle(rng);
    return GameItem(
      id: 'bubble_${phoneme.grapheme}_$index',
      prompt: 'Pop the bubbles with the ${phoneme.say} sound',
      choices: choices,
      correctId: 'b_${targets.first}',
      phoneme: phoneme.grapheme,
      hint: 'Say each word slowly. Do you hear ${phoneme.say}?',
    );
  }

  static GameItem _rhymeRound(Phoneme phoneme, int index, math.Random rng) {
    final base = phoneme.words[index % phoneme.words.length];
    final family = _rhymeFamily(base);
    final choices = [
      for (final word in family)
        GameChoice(id: 'r_$word', label: word, emoji: PhonicsProgram.emojiFor(word)),
      GameChoice(
        id: 'r_other',
        label: 'fish',
        emoji: PhonicsProgram.emojiFor('fish'),
      ),
    ]..shuffle(rng);
    return GameItem(
      id: 'rhyme_${base}_$index',
      prompt: 'Which one rhymes with "$base"?',
      choices: choices,
      correctId: 'r_$base',
      phoneme: phoneme.grapheme,
      hint: 'Say them both and listen to the end.',
    );
  }

  static GameItem _spellRound(Phoneme phoneme, int index) {
    final word = phoneme.words[index % phoneme.words.length];
    final letters = word.toUpperCase().split('');
    final distractors = ['E', 'R', 'S', 'M'].where((l) => !letters.contains(l)).take(2);
    final choices = [
      for (var i = 0; i < letters.length; i++)
        GameChoice(id: 'l$i', label: letters[i]),
      for (final d in distractors) GameChoice(id: 'd_$d', label: d),
    ];
    return GameItem(
      id: 'spell_${word}_$index',
      prompt: 'Build "$word"',
      choices: choices,
      correctId: 'l0',
      phoneme: phoneme.grapheme,
      hint: 'Say the first sound, then find its letter.',
    );
  }

  static String _distractorWord(Phoneme phoneme) {
    for (final unit in PhonicsProgram.build()) {
      for (final other in unit.phonemes) {
        if (other.grapheme == phoneme.grapheme) continue;
        final word = other.words.first;
        if (!word.contains(phoneme.grapheme.replaceAll('_', ''))) return word;
      }
    }
    return 'cat';
  }

  static List<String> _rhymeFamily(String word) {
    if (word.length < 3) return [word, 'cat', 'hat', 'bat'];
    final ending = word.substring(word.length - 2);
    final candidates = PhonicsProgram.pictures.keys
        .where((candidate) =>
            candidate.length >= 2 &&
            candidate.endsWith(ending) &&
            candidate != word)
        .take(3)
        .toList();
    return [word, ...candidates];
  }
}
