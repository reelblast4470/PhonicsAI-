import 'package:flutter/foundation.dart';

import '../../../core/domain/reading_level.dart';

enum GameKind { soundMatch, bubblePop, rhymeRanger, spellBuilder }

@immutable
class GameChoice {
  const GameChoice({
    required this.id,
    required this.label,
    this.emoji,
    this.pairId,
  });

  final String id;
  final String label;
  final String? emoji;

  /// Sound Match pairs a picture with its word via this id.
  final String? pairId;
}

@immutable
class GameItem {
  const GameItem({
    required this.id,
    required this.prompt,
    required this.choices,
    required this.correctId,
    required this.phoneme,
    this.hint,
  });

  final String id;
  final String prompt;
  final List<GameChoice> choices;
  final String correctId;
  final String phoneme;
  final String? hint;

  GameChoice get answer =>
      choices.firstWhere((c) => c.id == correctId, orElse: () => choices.first);
}

@immutable
class GameDefinition {
  const GameDefinition({
    required this.kind,
    required this.title,
    required this.blurb,
    required this.emoji,
    required this.skillLabel,
    required this.minLevel,
    required this.itemsPerRound,
    this.needsBoard = true,
  });

  GameKind get id => kind;

  final GameKind kind;
  final String title;
  final String blurb;
  final String emoji;
  final String skillLabel;
  final ReadingLevel minLevel;
  final int itemsPerRound;
  final bool needsBoard;

  static const List<GameDefinition> catalog = [
    GameDefinition(
      kind: GameKind.soundMatch,
      title: 'Sound Match',
      blurb: 'Pair each picture with the word that says it',
      emoji: '🎴',
      skillLabel: 'sound ↔ spelling',
      minLevel: ReadingLevel.preReader,
      itemsPerRound: 4,
    ),
    GameDefinition(
      kind: GameKind.bubblePop,
      title: 'Bubble Pop',
      blurb: 'Pop every bubble that hides the sound',
      emoji: '🫧',
      skillLabel: 'hearing sounds in words',
      minLevel: ReadingLevel.letterSounds,
      itemsPerRound: 6,
    ),
    GameDefinition(
      kind: GameKind.rhymeRanger,
      title: 'Rhyme Ranger',
      blurb: 'Ride the rhyme trail and pick the match',
      emoji: '🐎',
      skillLabel: 'rhyme and word families',
      minLevel: ReadingLevel.cvcBlender,
      itemsPerRound: 5,
    ),
    GameDefinition(
      kind: GameKind.spellBuilder,
      title: 'Spell Builder',
      blurb: 'Stack the letters to build real words',
      emoji: '🧱',
      skillLabel: 'segmenting and spelling',
      minLevel: ReadingLevel.cvcBlender,
      itemsPerRound: 3,
    ),
  ];

  static GameDefinition of(GameKind kind) =>
      catalog.firstWhere((game) => game.kind == kind);

  static GameDefinition? byId(String? id) {
    for (final game in catalog) {
      if (game.kind.name == id) return game;
    }
    return null;
  }
}

/// Scoring rules, kept as data so the same numbers are used by the round
/// screen, the summary and the parent report.
abstract final class GameScoring {
  static const basePoints = 10;
  static const streakBonus = 5;
  static const maxStreakBonus = 25;

  static int pointsFor({
    required bool isCorrect,
    required int streakBefore,
  }) {
    if (!isCorrect) return 0;
    final bonus = streakBefore >= 2
        ? (streakBefore * streakBonus).clamp(0, maxStreakBonus)
        : 0;
    return basePoints + bonus;
  }

  static int starsFor({required int correct, required int total}) {
    if (total <= 0) return 0;
    final ratio = correct / total;
    if (ratio >= 0.9) return 3;
    if (ratio >= 0.6) return 2;
    return 1;
  }
}
