import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/domain/reading_level.dart';
import '../../../core/util/ids.dart';
import '../../curriculum/data/phonics_program.dart';
import '../../profile/application/profile_providers.dart';
import '../../progress/application/progress_providers.dart';
import '../../progress/domain/progress_repository.dart';
import '../data/game_round_factory.dart';
import '../domain/game_models.dart';

@immutable
class GameItemResult {
  const GameItemResult({
    required this.itemId,
    required this.chosenId,
    required this.isCorrect,
    required this.points,
  });

  final String itemId;
  final String chosenId;
  final bool isCorrect;
  final int points;
}

@immutable
class GameSession {
  const GameSession({
    required this.definition,
    required this.items,
    required this.index,
    required this.score,
    required this.streak,
    required this.results,
    required this.startedAt,
    this.selected = const [],
    this.isPaused = false,
    this.isOver = false,
    this.lastGain,
  });

  final GameDefinition definition;
  final List<GameItem> items;
  final int index;
  final int score;
  final int streak;
  final List<GameItemResult> results;
  final DateTime startedAt;

  /// Multi-tap games (Spell Builder, Sound Match) accumulate picks here.
  final List<String> selected;
  final bool isPaused;
  final bool isOver;
  final int? lastGain;

  GameItem get current => items[index];
  bool get isLast => index == items.length - 1;
  int get correctCount => results.where((r) => r.isCorrect).length;
  double get accuracy => results.isEmpty ? 1 : correctCount / results.length;
  int get stars => GameScoring.starsFor(correct: correctCount, total: items.length);
  Duration get elapsed => DateTime.now().difference(startedAt);

  GameSession copyWith({
    int? index,
    int? score,
    int? streak,
    List<GameItemResult>? results,
    List<String>? selected,
    bool? isPaused,
    bool? isOver,
    int? lastGain,
  }) {
    return GameSession(
      definition: definition,
      items: items,
      index: index ?? this.index,
      score: score ?? this.score,
      streak: streak ?? this.streak,
      results: results ?? this.results,
      startedAt: startedAt,
      selected: selected ?? this.selected,
      isPaused: isPaused ?? this.isPaused,
      isOver: isOver ?? this.isOver,
      lastGain: lastGain ?? this.lastGain,
    );
  }
}

/// Runs one round of one game.
///
/// Scoring lives here (not in the widgets) so a game can be added by writing a
/// board and nothing else, and so "how did my child score" has one answer.
class GameController extends FamilyNotifier<GameSession?, GameKind> {
  late GameKind kind;

  @override
  GameSession? build(GameKind argument) {
    kind = argument;
    final definition = GameDefinition.of(argument);
    final profile = ref.read(activeProfileProvider);
    final level = profile?.level ?? ReadingLevel.letterSounds;
    final focus = _focusPhonemes(level, ref.read(profileProgressProvider).valueOrNull);
    final items = GameRoundFactory.build(
      kind: argument,
      focusPhonemes: focus,
      count: definition.itemsPerRound,
      level: level,
      seed: DateTime.now().minute,
    );
    return GameSession(
      definition: definition,
      items: items,
      index: 0,
      score: 0,
      streak: 0,
      results: const [],
      startedAt: DateTime.now(),
    );
  }

  /// Sounds the games should drill: the learner's current unit sounds, then the
  /// trickiest ones from their mastery record. Games must never run ahead of
  /// the lesson, and never fall behind it either.
  List<String> _focusPhonemes(ReadingLevel level, ProfileSnapshot? snapshot) {
    final unitPhonemes = PhonicsProgram.build()
        .where((unit) => unit.level == level)
        .expand((unit) => unit.phonemes)
        .map((phoneme) => phoneme.grapheme)
        .toList();
    final tricky = [
      for (final mastery in snapshot?.mastery.values ?? const <Never>[])
        if (mastery.reps > 0 && mastery.accuracy < 0.7)
          mastery.phoneme.split('__').last,
    ];
    final combined = <String>[...unitPhonemes, ...tricky]
      ..removeWhere((item) => item.isEmpty);
    return combined.isEmpty ? const ['s', 'a', 't', 'p', 'i', 'n'] : combined;
  }

  void toggleChoice(String choiceId) {
    final session = state;
    if (session == null || session.isOver) return;
    final selected = [...session.selected];
    if (selected.contains(choiceId)) {
      selected.remove(choiceId);
    } else {
      selected.add(choiceId);
    }
    state = session.copyWith(selected: selected);

    switch (session.definition.kind) {
      case GameKind.soundMatch:
        _evaluateMatchPairs(session);
      case GameKind.rhymeRanger:
      case GameKind.bubblePop:
        if (selected.length == 1) submitSingle(selected.first);
      case GameKind.spellBuilder:
        if (selected.length == session.current.answer.label.length) {
          submitSpelling();
        }
    }
  }

  void _evaluateMatchPairs(GameSession session) {
    if (session.selected.length != 2) return;
    final first = session.current.choices
        .firstWhere((c) => c.id == session.selected.first);
    final second = session.current.choices
        .firstWhere((c) => c.id == session.selected.last);
    final isPair = first.pairId != null && first.pairId == second.pairId;
    if (isPair) {
      _record(session, session.selected.last, true);
    } else {
      state = session.copyWith(streak: 0, selected: const []);
    }
  }

  void submitSingle(String choiceId) {
    final session = state;
    if (session == null) return;
    _record(session, choiceId, choiceId == session.current.correctId);
  }

  void submitSpelling() {
    final session = state;
    if (session == null) return;
    final target = session.current;
    final built = session.selected
        .map((id) => target.choices.firstWhere((c) => c.id == id).label)
        .join();
    _record(session, session.selected.join('+'), built == target.answer.label);
  }

  void _record(GameSession session, String chosenId, bool isCorrect) {
    final points = GameScoring.pointsFor(
      isCorrect: isCorrect,
      streakBefore: session.streak,
    );
    final results = [
      ...session.results,
      GameItemResult(
        itemId: session.current.id,
        chosenId: chosenId,
        isCorrect: isCorrect,
        points: points,
      ),
    ];
    final isOver = session.isLast;
    state = session.copyWith(
      index: isOver ? session.index : session.index + 1,
      score: session.score + points,
      streak: isCorrect ? session.streak + 1 : 0,
      results: results,
      selected: const [],
      isOver: isOver,
      lastGain: points,
    );
    if (isOver) unawaited(_persist());
  }

  Future<void> restart() async {
    final session = state;
    if (session == null) return;
    final items = GameRoundFactory.build(
      kind: session.definition.kind,
      focusPhonemes: session.items.map((item) => item.phoneme).toList(),
      count: session.definition.itemsPerRound,
      level: ref.read(activeProfileProvider)?.level ??
          ReadingLevel.letterSounds,
      seed: int.parse(Ids.short(4), radix: 36),
    );
    state = GameSession(
      definition: session.definition,
      items: items,
      index: 0,
      score: 0,
      streak: 0,
      results: const [],
      startedAt: DateTime.now(),
    );
  }

  void togglePause() {
    final session = state;
    if (session == null) return;
    state = session.copyWith(isPaused: !session.isPaused);
  }

  Future<void> _persist() async {
    final session = state;
    final profileId = ref.read(activeProfileIdProvider);
    if (session == null || profileId == null || !session.isOver) return;
    await ref.read(progressRepositoryProvider).recordGameRound(
          profileId: profileId,
          gameId: session.definition.kind.name,
          score: session.score,
          stars: session.stars * 3,
          secondsSpent: session.elapsed.inSeconds.toDouble(),
        );
    for (final result in session.results) {
      final phoneme = session.items
          .firstWhere((item) => item.id == result.itemId)
          .phoneme;
      await ref.read(progressRepositoryProvider).recordSoundReview(
            profileId: profileId,
            phoneme: phoneme,
            grade: result.isCorrect ? 4 : 1,
          );
    }
  }
}

final gameProvider =
    NotifierProvider.family<GameController, GameSession?, GameKind>(
  GameController.new,
);
