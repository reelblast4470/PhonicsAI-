import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/infrastructure.dart';
import '../../../core/storage/key_value_store.dart';
import '../../curriculum/data/phonics_program.dart';
import '../domain/writing_models.dart';

enum WritingMode { trace, spell }

@immutable
sealed class WritingState {
  const WritingState();
}

class WritingStateLoading extends WritingState {
  const WritingStateLoading();
}

class WritingStateMissing extends WritingState {
  const WritingStateMissing();
}

class WritingReady extends WritingState {
  const WritingReady({
    required this.glyph,
    required this.spelling,
    required this.mode,
    required this.tiles,
    required this.picked,
    required this.bestTrace,
    this.isChecked = false,
  });

  /// Letter being traced (upper case guide, the shape is the same).
  final String glyph;
  final SpellingTarget spelling;
  final WritingMode mode;
  final List<String> tiles;
  final List<int> picked;
  final double bestTrace;
  final bool isChecked;

  bool get isSpellingCorrect =>
      picked.map((index) => tiles[index]).join().toUpperCase() ==
      spelling.word.toUpperCase();
  WritingReady copyWith({
    WritingMode? mode,
    List<int>? picked,
    double? bestTrace,
    bool? isChecked,
  }) {
    return WritingReady(
      glyph: glyph,
      spelling: spelling,
      mode: mode ?? this.mode,
      tiles: tiles,
      picked: picked ?? this.picked,
      bestTrace: bestTrace ?? this.bestTrace,
      isChecked: isChecked ?? this.isChecked,
    );
  }
}

/// Drives one writing target. The target can be addressed as a phoneme
/// (`s`), a word (`sun`) or a lesson sound (`unit_satpin_l1`), which is what
/// lets the lesson player deep-link straight into practice.
class WritingController extends FamilyNotifier<WritingState, String> {
  late String targetId;

  @override
  WritingState build(String argument) {
    targetId = argument;
    final resolved = _resolve(argument);
    if (resolved == null) return const WritingStateMissing();
    return WritingReady(
      glyph: resolved.glyph,
      spelling: resolved.spelling,
      mode: WritingMode.trace,
      tiles: resolved.spelling.tilesFor(argument.hashCode),
      picked: const [],
      bestTrace: 0,
    );
  }

  _WritingTarget? _resolve(String id) {
    final normalised = id.toLowerCase().trim();
    if (normalised.isEmpty) return null;

    // Single letter or digraph.
    if (normalised.length <= 5 && RegExp(r'^[a-z_]+$').hasMatch(normalised)) {
      final grapheme = normalised.replaceAll('_', '');
      return _WritingTarget(
        glyph: grapheme.isEmpty ? 'A' : grapheme[0].toUpperCase(),
        spelling: SpellingTarget(
          word: _wordFor(grapheme) ?? grapheme,
          emoji: PhonicsProgram.emojiFor(_wordFor(grapheme) ?? grapheme) ?? '✏️',
          prompt: 'Spell the word',
          distractors: const ['e', 'r', 's'],
        ),
      );
    }

    // A word.
    if (RegExp(r'^[a-z]+$').hasMatch(normalised)) {
      return _WritingTarget(
        glyph: normalised[0].toUpperCase(),
        spelling: SpellingTarget(
          word: normalised,
          emoji: PhonicsProgram.emojiFor(normalised) ?? '✏️',
          prompt: 'Build "$normalised"',
          distractors: const ['a', 'e', 't', 's'],
        ),
      );
    }

    // A lesson id: use its first phoneme.
    for (final unit in PhonicsProgram.build()) {
      for (final lesson in unit.lessons) {
        if (lesson.id != id) continue;
        final phoneme = lesson.phonemes.isEmpty ? 'a' : lesson.phonemes.first;
        return _WritingTarget(
          glyph: phoneme.replaceAll('_', '').toUpperCase(),
          spelling: SpellingTarget(
            word: _wordFor(phoneme) ?? 'sun',
            emoji: PhonicsProgram.emojiFor(_wordFor(phoneme) ?? 'sun') ?? '✏️',
            prompt: 'Spell the word',
            distractors: const ['m', 'm'],
          ),
        );
      }
    }
    return null;
  }

  static String? _wordFor(String grapheme) {
    final key = grapheme.replaceAll('_', '');
    if (key.isEmpty) return null;
    for (final unit in PhonicsProgram.build()) {
      for (final phoneme in unit.phonemes) {
        if (phoneme.grapheme == grapheme && phoneme.words.isNotEmpty) {
          return phoneme.words.first;
        }
      }
    }
    for (final word in PhonicsProgram.pictures.keys) {
      if (word.startsWith(key)) return word;
    }
    return null;
  }

  void setMode(WritingMode mode) {
    final current = state;
    if (current is WritingReady) state = current.copyWith(mode: mode);
  }

  void recordTrace(WritingScore score) {
    final current = state;
    if (current is! WritingReady) return;
    state = current.copyWith(
      bestTrace: score.overall > current.bestTrace
          ? score.overall
          : current.bestTrace,
    );
  }

  void pickTile(int tileIndex) {
    final current = state;
    if (current is! WritingReady) return;
    if (current.picked.contains(tileIndex)) return;
    if (current.picked.length >= current.spelling.word.length) return;
    state = current.copyWith(picked: [...current.picked, tileIndex], isChecked: false);
  }

  void unpick(int slotIndex) {
    final current = state;
    if (current is! WritingReady) return;
    if (slotIndex >= current.picked.length) return;
    final picked = [...current.picked]..removeAt(slotIndex);
    state = current.copyWith(picked: picked, isChecked: false);
  }

  void checkSpelling() {
    final current = state;
    if (current is! WritingReady) return;
    state = current.copyWith(isChecked: true);
  }

  /// Persists the attempt locally (stars are awarded by the caller that knows
  /// the lesson context, e.g. the lesson runner).
  Future<void> save() async {
    final current = state;
    if (current is! WritingReady) return;
    final store = ref.read(keyValueStoreProvider);
    final profileId = store.getString('phonicsai.active_profile') ?? 'default';
    await store.setJson(
      'phonicsai.writing_attempts.$profileId-$targetId',
      {
        'glyph': current.glyph,
        'word': current.spelling.word,
        'trace': current.bestTrace,
        'spelling_ok': current.isSpellingCorrect,
        'at': DateTime.now().toIso8601String(),
      },
    );
  }
}

class _WritingTarget {
  const _WritingTarget({required this.glyph, required this.spelling});
  final String glyph;
  final SpellingTarget spelling;
}

final writingControllerProvider =
    NotifierProvider.family<WritingController, WritingState, String>(
  WritingController.new,
);
