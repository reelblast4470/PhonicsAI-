import 'package:flutter/foundation.dart';

/// One sound-spelling pair. `grapheme` is what is printed, `sound` is what is
/// said — the difference is the whole reason phonics has to be taught.
@immutable
class Phoneme {
  const Phoneme({
    required this.grapheme,
    required this.ipa,
    required this.words,
    this.isDigraph = false,
    this.longVariant,
    this.mnemonic = '',
  });

  final String grapheme;
  final String ipa;

  /// 3-5 decodable words, always in sound order for the taught grapheme.
  final List<String> words;
  final bool isDigraph;

  /// Magic-e form, e.g. `a` → `a_e` (cake).
  final String? longVariant;
  final String mnemonic;

  String get id => grapheme;

  /// Text the audio layer should say for this grapheme.
  String get say => switch (grapheme) {
    'sh' => 'shhh',
    'ch' => 'chch',
    'th' => 'thhh',
    'wh' => 'whuu',
    'ck' => 'k',
    'ng' => 'nggg',
    'qu' => 'kw',
    _ => grapheme,
  };

  /// Words used for the "which one starts with…" cards, filtered so a distractor
  /// never accidentally contains the target sound.
  List<String> get decodableWords => words;

  @override
  bool operator ==(Object other) =>
      other is Phoneme && other.grapheme == grapheme && other.ipa == ipa;

  @override
  int get hashCode => Object.hash(grapheme, ipa);
}
