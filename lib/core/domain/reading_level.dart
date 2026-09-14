import 'dart:math' as math;

/// The five placement bands PhonicsAI teaches in. A learner is placed here by
/// the assessment and can always be moved by a parent.
enum ReadingLevel {
  preReader(
    code: 'pre_reader',
    label: 'Sounds & symbols',
    blurb: 'Hears that words are made of sounds',
    minAgeMonths: 36,
  ),
  letterSounds(
    code: 'letter_sounds',
    label: 'Letter sounds',
    blurb: 'Knows most single-letter sounds',
    minAgeMonths: 42,
  ),
  cvcBlender(
    code: 'cvc_blender',
    label: 'Blending CVC',
    blurb: 'Blends c-a-t style words',
    minAgeMonths: 54,
  ),
  earlyDecoder(
    code: 'early_decoder',
    label: 'Digraphs & magic e',
    blurb: 'Reads sh, ch, ie, split digraphs',
    minAgeMonths: 66,
  ),
  fluentReader(
    code: 'fluent_reader',
    label: 'Fluent decoder',
    blurb: 'Reads multisyllable words with ease',
    minAgeMonths: 78,
  );

  const ReadingLevel({
    required this.code,
    required this.label,
    required this.blurb,
    required this.minAgeMonths,
  });

  final String code;
  final String label;
  final String blurb;

  /// Soft floor used to pre-highlight a suggestion; never enforced.
  final int minAgeMonths;

  static ReadingLevel fromCode(String? code) => values.firstWhere(
        (level) => level.code == code,
        orElse: () => letterSounds,
      );

  ReadingLevel get next =>
      this == values.last ? this : values[index + 1];
  ReadingLevel get previous =>
      index == 0 ? this : values[index - 1];

  int get rank => index;

  static int ageYearsFromMonths(int months) => (months / 12).floor();

  static int clampAgeMonths(int months) => math.min(math.max(months, 24), 144);
}
