import 'package:flutter/widgets.dart';

import 'reading_level.dart';

/// A child's learning identity. Everything in the app (progress, missions,
/// tutor memory) is scoped to one of these, which is what makes multi-child
/// households work on a single tablet.
@immutable
class LearnerProfile {
  const LearnerProfile({
    required this.id,
    required this.displayName,
    required this.ageMonths,
    required this.avatarId,
    required this.level,
    required this.createdAt,
    this.homeLanguageCode = 'en',
    this.interfaceLanguageCode,
    this.isAssessmentComplete = false,
    this.dailyGoalMinutes = 15,
    this.starsBalance = 0,
    this.draftName = '',
  });

  final String id;
  final String displayName;
  final int ageMonths;

  /// Key into [LearnerAvatar.catalog] — emoji first so the app ships with zero
  /// image payload and stays fast on low-end devices.
  final String avatarId;
  final ReadingLevel level;
  final DateTime createdAt;

  /// Language spoken at home: the tutor may translate instructions into it.
  final String homeLanguageCode;

  /// Overrides the device locale for this learner (null = device default).
  final String? interfaceLanguageCode;
  final bool isAssessmentComplete;
  final int dailyGoalMinutes;
  final int starsBalance;

  /// Transient UI-only field for the profile editor (not persisted).
  final String draftName;

  int get ageYears => (ageMonths / 12).floor();

  String get initials {
    final name = displayName.trim();
    if (name.isEmpty) return '?';
    final parts = name.split(RegExp(r'\s+'));
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first)
        .toUpperCase();
  }

  LearnerAvatar get avatar => LearnerAvatar.byId(avatarId);

  LearnerProfile copyWith({
    String? displayName,
    int? ageMonths,
    String? avatarId,
    ReadingLevel? level,
    String? homeLanguageCode,
    Object? interfaceLanguageCode = _sentinel,
    bool? isAssessmentComplete,
    int? dailyGoalMinutes,
    int? starsBalance,
    String? draftName,
  }) {
    return LearnerProfile(
      id: id,
      displayName: displayName ?? this.displayName,
      ageMonths: ageMonths ?? this.ageMonths,
      avatarId: avatarId ?? this.avatarId,
      level: level ?? this.level,
      createdAt: createdAt,
      homeLanguageCode: homeLanguageCode ?? this.homeLanguageCode,
      interfaceLanguageCode: interfaceLanguageCode == _sentinel
          ? this.interfaceLanguageCode
          : interfaceLanguageCode as String?,
      isAssessmentComplete: isAssessmentComplete ?? this.isAssessmentComplete,
      dailyGoalMinutes: dailyGoalMinutes ?? this.dailyGoalMinutes,
      starsBalance: starsBalance ?? this.starsBalance,
      draftName: draftName ?? this.draftName,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': displayName,
        'age_months': ageMonths,
        'avatar': avatarId,
        'level': level.code,
        'created_at': createdAt.toIso8601String(),
        'home_language': homeLanguageCode,
        if (interfaceLanguageCode != null) 'language': interfaceLanguageCode,
        'assessed': isAssessmentComplete,
        'goal_minutes': dailyGoalMinutes,
        'stars': starsBalance,
      };

  factory LearnerProfile.fromJson(Map<String, dynamic> json) {
    final created = DateTime.tryParse(json['created_at'] as String? ?? '');
    return LearnerProfile(
      id: json['id'] as String,
      displayName: json['name'] as String? ?? 'Learner',
      ageMonths: (json['age_months'] as num?)?.toInt() ?? 60,
      avatarId: json['avatar'] as String? ?? 'fox',
      level: ReadingLevel.fromCode(json['level'] as String?),
      createdAt: created ?? DateTime.now(),
      homeLanguageCode: json['home_language'] as String? ?? 'en',
      interfaceLanguageCode: json['language'] as String?,
      isAssessmentComplete: json['assessed'] as bool? ?? false,
      dailyGoalMinutes: (json['goal_minutes'] as num?)?.toInt() ?? 15,
      starsBalance: (json['stars'] as num?)?.toInt() ?? 0,
    );
  }

  static const Object _sentinel = Object();

  @override
  bool operator ==(Object other) =>
      other is LearnerProfile &&
      other.id == id &&
      other.displayName == displayName &&
      other.ageMonths == ageMonths &&
      other.avatarId == avatarId &&
      other.level == level &&
      other.homeLanguageCode == homeLanguageCode &&
      other.interfaceLanguageCode == interfaceLanguageCode &&
      other.isAssessmentComplete == isAssessmentComplete &&
      other.dailyGoalMinutes == dailyGoalMinutes &&
      other.starsBalance == starsBalance;

  @override
  int get hashCode => Object.hash(
        id,
        displayName,
        ageMonths,
        avatarId,
        level,
        homeLanguageCode,
        interfaceLanguageCode,
        isAssessmentComplete,
        dailyGoalMinutes,
        starsBalance,
      );
}

/// The buddy avatars shipped with the app. Emoji keeps the first install under
/// a megabyte; Stitch art can replace one lookup without touching screens.
@immutable
class LearnerAvatar {
  const LearnerAvatar({
    required this.id,
    required this.emoji,
    required this.name,
    required this.tint,
  });

  final String id;
  final String emoji;
  final String name;
  final Color tint;

  static const List<LearnerAvatar> catalog = [
    LearnerAvatar(id: 'fox', emoji: '🦊', name: 'Foxy', tint: Color(0xFFFF8A4D)),
    LearnerAvatar(id: 'panda', emoji: '🐼', name: 'Panda', tint: Color(0xFF8E9BE8)),
    LearnerAvatar(id: 'owl', emoji: '🦉', name: 'Ollie', tint: Color(0xFFB07C4F)),
    LearnerAvatar(id: 'frog', emoji: '🐸', name: 'Hop', tint: Color(0xFF3FBF6B)),
    LearnerAvatar(id: 'bee', emoji: '🐝', name: 'Buzz', tint: Color(0xFFFFC83D)),
    LearnerAvatar(id: 'whale', emoji: '🐳', name: 'Wade', tint: Color(0xFF39A0FF)),
    LearnerAvatar(id: 'unicorn', emoji: '🦄', name: 'Uni', tint: Color(0xFF9B5CFF)),
    LearnerAvatar(id: 'dino', emoji: '🦕', name: 'Rex', tint: Color(0xFF22C9A0)),
    LearnerAvatar(id: 'cat', emoji: '🐱', name: 'Kit', tint: Color(0xFFF7A8B8)),
    LearnerAvatar(id: 'robot', emoji: '🤖', name: 'Beep', tint: Color(0xFF7C8AA5)),
    LearnerAvatar(id: 'lion', emoji: '🦁', name: 'Leo', tint: Color(0xFFE8912A)),
    LearnerAvatar(id: 'penguin', emoji: '🐧', name: 'Pip', tint: Color(0xFF5B7C99)),
  ];

  static LearnerAvatar byId(String id) => catalog.firstWhere(
        (avatar) => avatar.id == id,
        orElse: () => catalog.first,
      );
}
