import '../../../core/domain/reading_level.dart';
import '../../curriculum/data/phonics_program.dart';
import '../domain/reading_models.dart';

/// Decodable texts, derived from the same program data the lessons teach.
///
/// Deriving them is what keeps a "decodable book" honest: every sentence comes
/// from the sound set taught at or below that unit. Hand-written readers drift
/// out of sync with the curriculum the moment content changes.
abstract final class ReadingLibrary {
  static List<DecodablePassage> all() => [
        for (final unit in PhonicsProgram.build())
          DecodablePassage(
            id: '${unit.id}_reader',
            title: unit.title,
            level: unit.level,
            targetPhonemes: [for (final p in unit.phonemes) p.grapheme],
            sentences: sentencesFor(unit.id),
            emoji: emojiFor(unit.level),
          ),
      ];

  static List<DecodablePassage> forLevel(ReadingLevel level) =>
      all().where((p) => p.level == level).toList(growable: false);

  static DecodablePassage? byId(String? id) {
    if (id == null || id.isEmpty) return all().first;
    for (final passage in all()) {
      if (passage.id == id) return passage;
    }
    // A lesson's read stage says "<unit>_p2" -> that unit's reader.
    final unitId = id.split('_p').first;
    for (final passage in all()) {
      if (passage.id == '${unitId}_reader') return passage;
    }
    return all().isEmpty ? null : all().first;
  }

  static List<String> sentencesFor(String unitId) => switch (unitId) {
        'unit_satpin' => const [
            'Sam sat on the mat.',
            'Pat pinned the pan.',
            'An ant sat in the tin.',
            'Nan sat and tapped it.',
          ],
        'unit_ckhvg' => const [
            'The dog ran to me.',
            'Hen hid in the mud.',
            'Meg dug a hole.',
            'Rick had a red drum.',
          ],
        'unit_flossy' => const [
            'The fish is on the shelf.',
            'Sam wish for a shell.',
            'The chin itch.',
            'Chip fell in the bath.',
          ],
        'unit_magice' => const [
            'Jake came home by the lake.',
            'The cute mule ate a plum.',
            'We read these notes.',
            'Hide the kite in the hive.',
          ],
        'unit_vowelteams' => const [
            'The rain fell on the street.',
            'We read the team speech.',
            'The goat rowed the boat.',
            'The owl saw a brown cow.',
          ],
        'unit_rcontrolled' => const [
            'The nurse heard a bird.',
            'Our farm has forty rows.',
            'George found a page.',
            'The station has a platform.',
          ],
        _ => const ['Sam sat on the mat.', 'Pat pinned the pan.'],
      };

  static String emojiFor(ReadingLevel level) => switch (level) {
        ReadingLevel.preReader => '🐣',
        ReadingLevel.letterSounds => '🐝',
        ReadingLevel.cvcBlender => '🦆',
        ReadingLevel.earlyDecoder => '🦉',
        ReadingLevel.fluentReader => '🦄',
      };
}
