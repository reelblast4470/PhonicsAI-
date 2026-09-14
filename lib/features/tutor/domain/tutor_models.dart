import 'package:flutter/foundation.dart';

enum TutorRole { learner, tutor, system }

@immutable
class TutorMessage {
  const TutorMessage({
    required this.id,
    required this.role,
    required this.text,
    required this.at,
    this.isStreaming = false,
    this.chips = const [],
    this.action,
    this.flagged = false,
  });

  final String id;
  final TutorRole role;
  final String text;
  final DateTime at;

  /// True while tokens are still arriving (the bubble shows a caret).
  final bool isStreaming;

  /// Follow-up taps, e.g. ["hear it again", "show the letters"].
  final List<String> chips;
  final TutorAction? action;

  /// Blocked/off-topic: kept for the parent report, never shown as raw text.
  final bool flagged;

  TutorMessage copyWith({String? text, bool? isStreaming, List<String>? chips}) =>
      TutorMessage(
        id: id,
        role: role,
        text: text ?? this.text,
        at: at,
        isStreaming: isStreaming ?? this.isStreaming,
        chips: chips ?? this.chips,
        action: action,
        flagged: flagged,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'role': role.name,
        'text': text,
        'at': at.toIso8601String(),
        'chips': chips,
        'flagged': flagged,
      };

  factory TutorMessage.fromJson(Map<String, dynamic> json) => TutorMessage(
        id: json['id'] as String,
        role: TutorRole.values.firstWhere(
          (role) => role.name == json['role'],
          orElse: () => TutorRole.learner,
        ),
        text: json['text'] as String? ?? '',
        at: DateTime.tryParse(json['at'] as String? ?? '') ?? DateTime.now(),
        chips: [
          for (final chip in (json['chips'] as List? ?? const [])) chip as String,
        ],
        flagged: json['flagged'] as bool? ?? false,
      );
}

/// A tutor reply can ask the app to *do* something: open a lesson, play a
/// game, drill a sound. Keeping it as data makes the tutor testable and means a
/// model upgrade cannot inject arbitrary navigation.
@immutable
class TutorAction {
  const TutorAction({required this.kind, required this.target, this.label});

  final TutorActionKind kind;
  final String target;
  final String? label;
}

enum TutorActionKind { openLesson, openGame, openReading, openPronunciation, say, none }

@immutable
class TutorReply {
  const TutorReply({
    required this.text,
    this.chips = const [],
    this.action,
    this.flagged = false,
  });

  final String text;
  final List<String> chips;
  final TutorAction? action;
  final bool flagged;
}
