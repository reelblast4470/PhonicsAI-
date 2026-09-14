import '../../../core/domain/reading_level.dart';

/// One placement card. Children aged 3-6 cannot read instructions, so every
/// question is spoken (`spokenPrompt`) and answered by tapping a picture.
class AssessmentQuestion {
  const AssessmentQuestion({
    required this.id,
    required this.skill,
    required this.spokenPrompt,
    required this.displayPrompt,
    required this.options,
    required this.correctIndex,
    required this.targetsLevel,
    this.hintForWrong,
  });

  final String id;
  final PhonicsSkill skill;

  /// What the tutor says out loud.
  final String spokenPrompt;

  /// Visible short form for parents / accessibility text.
  final String displayPrompt;

  final List<AssessmentOption> options;
  final int correctIndex;

  /// A correct answer here is evidence the learner is *at least* at this band.
  final ReadingLevel targetsLevel;
  final String? hintForWrong;
}

class AssessmentOption {
  const AssessmentOption({required this.emoji, required this.word});

  final String emoji;
  final String word;
}

enum PhonicsSkill {
  initialSound('hearing the first sound'),
  letterSound('knowing letter names and sounds'),
  blending('sounding out and blending'),
  rhyming('hearing rhymes'),
  digraphs('blends, digraphs and magic e');

  const PhonicsSkill(this.description);
  final String description;
}

/// The fixed placement set. Content, not filler: each card isolates one
/// prerequisite, and the order is the order phonics is actually taught in.
abstract final class AssessmentContent {
  static const List<AssessmentQuestion> questions = [
    AssessmentQuestion(
      id: 'a1',
      skill: PhonicsSkill.initialSound,
      spokenPrompt: 'Which one starts with the sound sss?',
      displayPrompt: 'Starts with /s/',
      options: [
        AssessmentOption(emoji: '🐱', word: 'cat'),
        AssessmentOption(emoji: '🐍', word: 'snake'),
        AssessmentOption(emoji: '🐸', word: 'frog'),
      ],
      correctIndex: 1,
      targetsLevel: ReadingLevel.preReader,
      hintForWrong: 'Listen again: sssss like a snake.',
    ),
    AssessmentQuestion(
      id: 'a2',
      skill: PhonicsSkill.letterSound,
      spokenPrompt: 'Which picture begins with the letter b, buh?',
      displayPrompt: 'Begins with /b/',
      options: [
        AssessmentOption(emoji: '🍎', word: 'apple'),
        AssessmentOption(emoji: '🌙', word: 'moon'),
        AssessmentOption(emoji: '🐝', word: 'bee'),
      ],
      correctIndex: 2,
      targetsLevel: ReadingLevel.letterSounds,
      hintForWrong: 'b says buh. buh-ee is bee.',
    ),
    AssessmentQuestion(
      id: 'a3',
      skill: PhonicsSkill.blending,
      spokenPrompt: 'Push these sounds together: c - a - t. What is it?',
      displayPrompt: 'c - a - t',
      options: [
        AssessmentOption(emoji: '🐶', word: 'dog'),
        AssessmentOption(emoji: '🐱', word: 'cat'),
        AssessmentOption(emoji: '🐮', word: 'cow'),
      ],
      correctIndex: 1,
      targetsLevel: ReadingLevel.cvcBlender,
      hintForWrong: 'Say each sound slowly, then say them fast.',
    ),
    AssessmentQuestion(
      id: 'a4',
      skill: PhonicsSkill.rhyming,
      spokenPrompt: 'Which one rhymes with hat?',
      displayPrompt: 'Rhymes with hat',
      options: [
        AssessmentOption(emoji: '🚗', word: 'car'),
        AssessmentOption(emoji: '🌳', word: 'tree'),
        AssessmentOption(emoji: '🐀', word: 'rat'),
      ],
      correctIndex: 2,
      targetsLevel: ReadingLevel.cvcBlender,
      hintForWrong: 'hat… rat. Same ending sound.',
    ),
    AssessmentQuestion(
      id: 'a5',
      skill: PhonicsSkill.digraphs,
      spokenPrompt: 'Which word has the sh sound?',
      displayPrompt: 'Has /sh/',
      options: [
        AssessmentOption(emoji: '🚢', word: 'ship'),
        AssessmentOption(emoji: '🦴', word: 'bone'),
        AssessmentOption(emoji: '🎩', word: 'hat'),
      ],
      correctIndex: 0,
      targetsLevel: ReadingLevel.earlyDecoder,
      hintForWrong: 'shh — quiet. ship starts with sh.',
    ),
    AssessmentQuestion(
      id: 'a6',
      skill: PhonicsSkill.digraphs,
      spokenPrompt: 'Which word says the long sound a: ay?',
      displayPrompt: 'Long a: cake, gate',
      options: [
        AssessmentOption(emoji: '🛏️', word: 'bed'),
        AssessmentOption(emoji: '🎂', word: 'cake'),
        AssessmentOption(emoji: '🐢', word: 'turtle'),
      ],
      correctIndex: 1,
      targetsLevel: ReadingLevel.fluentReader,
      hintForWrong: 'A magic e at the end makes the a say its name: cak-e.',
    ),
  ];
}
