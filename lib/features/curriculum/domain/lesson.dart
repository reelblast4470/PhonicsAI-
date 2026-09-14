import 'package:flutter/foundation.dart';

import '../../../core/domain/reading_level.dart';
import 'phoneme.dart';

/// The PhonicsAI learning loop. Every lesson walks these stages in order; the
/// UI is one generic engine, so adding a unit is a content change, not a screen.
enum StageKind {
  discover('Discover', 'a picture, a question, no pressure'),
  hear('Hear', 'identify the sound by ear'),
  see('See', 'meet the letters that write that sound'),
  understand('Understand', 'the rule, shown with two examples'),
  practice('Practice', 'build and tap words'),
  play('Play', 'a game that drills the same sound'),
  recall('Recall', 'quick flash back — spaced memory'),
  speak('Speak', 'say it and get feedback'),
  read('Read', 'read real words and sentences'),
  review('Review', 'what stuck, and what comes next');

  const StageKind(this.label, this.purpose);
  final String label;
  final String purpose;

  bool get needsMic => this == StageKind.speak;
  bool get opensReading => this == StageKind.read;
}

/// A single tappable thing inside a stage. One flat shape keeps the renderer
/// generic (and the content builder tiny); `kind` decides which fields matter.
@immutable
class StageItem {
  const StageItem({
    required this.id,
    required this.prompt,
    this.emoji,
    this.text,
    this.options = const [],
    this.correctIndex,
    this.audioText,
    this.letters,
    this.targetWord,
    this.remoteQuestionId,
    this.optionIds = const [],
  });

  final String id;
  final String prompt;
  final String? emoji;
  final String? text;

  /// Multiple-choice options (hear / recall / discover).
  final List<String> options;
  final int? correctIndex;

  /// What the speaker says when the card is tapped.
  final String? audioText;

  /// Letter tiles for practice / spelling.
  final List<String>? letters;
  final String? targetWord;

  /// Live-mode grading handles (Phase 3): when set, correctness is decided by
  /// the server, not by `correctIndex`. `optionIds[i]` is the backend answer
  /// id for `options[i]`. Mock/static content leaves these null.
  final String? remoteQuestionId;
  final List<String> optionIds;
  bool get isRemoteGraded => remoteQuestionId != null;

  bool get isChoice => options.isNotEmpty && correctIndex != null;
  bool get isBuilder => letters != null && targetWord != null;
}

@immutable
class LessonStage {
  const LessonStage({
    required this.kind,
    required this.items,
    this.introText,
    this.gameId,
    this.passageId,
    this.wordId,
  });

  final StageKind kind;
  final List<StageItem> items;
  final String? introText;

  /// Stage payloads that hand off to another feature.
  final String? gameId;
  final String? passageId;
  final String? wordId;

  String get id => kind.name;
}

@immutable
class PhonicsLesson {
  const PhonicsLesson({
    required this.id,
    required this.unitId,
    required this.title,
    required this.subtitle,
    required this.indexInUnit,
    required this.stages,
    required this.phonemes,
    this.xp = 10,
    this.remoteId,
  });

  final String id;
  final String unitId;
  final String title;
  final String subtitle;
  final int indexInUnit;
  final List<LessonStage> stages;

  /// What this lesson teaches, used by progress + the tutor.
  final List<String> phonemes;
  final int xp;

  /// Backend UUID of this lesson when it came from the curriculum API
  /// (Phase 3). Null for bundled/static content — the lesson engine uses it
  /// to open learning sessions against `/learners/{id}/sessions`.
  final String? remoteId;

  int get stageCount => stages.length;
}

@immutable
class CurriculumUnit {
  const CurriculumUnit({
    required this.id,
    required this.title,
    required this.blurb,
    required this.level,
    required this.order,
    required this.lessons,
    required this.phonemes,
  });

  final String id;
  final String title;
  final String blurb;
  final ReadingLevel level;
  final int order;
  final List<PhonicsLesson> lessons;
  final List<Phoneme> phonemes;

  String get levelLabel => level.label;
}
