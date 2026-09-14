import '../../../core/error/failure.dart';
import '../../../core/result/result.dart';
import 'tutor_models.dart';

/// The AI tutor boundary.
///
/// The client sends *text about phonics* plus a learner context (level, recent
/// sounds, error patterns) to our backend, which holds the model credentials and
/// the system prompt. Nothing here can talk to a model provider directly — that
/// is deliberate: it keeps keys off devices and lets us enforce the child-safety
/// policy on the server where it can be updated without an app release.
abstract interface class TutorService {
  Future<Result<TutorReply>> reply({
    required String message,
    required TutorContext context,
    void Function(String partial)? onToken,
  });

  Future<Result<List<String>>> suggestedStarters(TutorContext context);
}

class TutorContext {
  const TutorContext({
    required this.learnerName,
    required this.ageYears,
    required this.levelLabel,
    required this.recentPhonemes,
    required this.strugglingPhonemes,
    this.instructionLanguageCode = 'en',
    this.openChatAllowed = true,
  });

  final String learnerName;
  final int ageYears;
  final String levelLabel;
  final List<String> recentPhonemes;
  final List<String> strugglingPhonemes;
  final String instructionLanguageCode;

  /// Parent control: when false, free-form typing is disabled and only the
  /// scripted chips are offered.
  final bool openChatAllowed;
}

/// Local pedagogical responder used in mock mode, tests and offline.
///
/// It is a real rule engine, not a canned loop: it reads the learner's current
/// sounds and answers the five questions PhonicsAI learners actually ask. It is
/// intentionally limited — anything outside phonics gets the safe refusal, which
/// is exactly the behaviour the remote tutor must match.
class PhonicsRuleTutor implements TutorService {
  const PhonicsRuleTutor({this.latency = const Duration(milliseconds: 320)});

  final Duration latency;

  static const _blockedTopics = [
    'game cheat',
    'password',
    'address',
    'phone number',
    'buy',
    'money',
    'kill',
    'scary',
    'boyfriend',
    'girlfriend',
  ];

  @override
  Future<Result<TutorReply>> reply({
    required String message,
    required TutorContext context,
    void Function(String partial)? onToken,
  }) async {
    if (!context.openChatAllowed) {
      return const Result.fail(
        AppFailure(
          kind: FailureKind.forbidden,
          message: 'A grown-up turned off open questions. Tap a suggestion '
              'instead — those still work.',
        ),
      );
    }
    await Future<void>.delayed(latency);
    final lower = message.toLowerCase();

    if (_blockedTopics.any(lower.contains)) {
      return Result.ok(
        TutorReply(
          text: 'I only know things about sounds, words and reading! '
              'Let us practise ${context.recentPhonemes.isNotEmpty ? context.recentPhonemes.first : 'a sound'} instead.',
          chips: const ['Hear it again', 'Show the letters'],
          flagged: true,
        ),
      );
    }

    final reply = _respond(lower, context);
    if (onToken != null) {
      // Simulated streaming so the UI path is exercised offline too.
      final words = reply.text.split(' ');
      for (var i = 0; i < words.length; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 28));
        onToken(words.take(i + 1).join(' '));
      }
    }
    return Result.ok(reply);
  }

  TutorReply _respond(String text, TutorContext context) {
    final focus = context.recentPhonemes.isEmpty
        ? 's'
        : context.recentPhonemes.first;

    if (_hasAny(text, ['stuck', 'cannot read', "can't read", 'help me', 'hard'])) {
      return TutorReply(
        text: 'Let us break it up. Say each sound slowly, then slide them '
            'together: $focus … aaaaa … ${focus}a. ${context.learnerName}, '
            'you read that one!',
        chips: const ['Hear it again', 'Slowly please', 'Practise this sound'],
        action: TutorAction(
          kind: TutorActionKind.openPronunciation,
          target: focus,
          label: 'Practise this sound',
        ),
      );
    }

    if (_hasAny(text, ['what sound', 'say', 'hear', 'sound like'])) {
      return TutorReply(
        text: 'focus says focus — like in ${_exampleFor(focus)}. '
            'Put your ${_mouthHint(focus)} and try.',
        chips: const ['Again, slower', 'Show the letters', 'My turn'],
      );
    }

    if (_hasAny(text, ['letter', 'write', 'spell', 'tricky'])) {
      return TutorReply(
        text: 'Good question. focus is written with the letters '
            '${focus.split('').join(' + ')}. ${_spellTip(focus)}',
        chips: const ['Trace it', 'Build a word'],
        action: const TutorAction(
          kind: TutorActionKind.openLesson,
          target: '',
          label: 'Practise writing',
        ),
      );
    }

    if (_hasAny(text, ['rhyme', 'word with', 'same end'])) {
      return TutorReply(
        text: 'Words that rhyme with focus: ${_rhymesFor(focus)}. '
            'Do they end with the same sound?',
        chips: const ['One more', 'Play a rhyme game'],
        action: const TutorAction(
          kind: TutorActionKind.openGame,
          target: 'rhyme_ranger',
          label: 'Play a rhyme game',
        ),
      );
    }

    if (_hasAny(text, ['story', 'book', 'read to me', 'fairy'])) {
      return TutorReply(
        text: 'I have a tiny story with the $focus sound: '
            '${_storyFor(focus)}. Read it with me — tap any word to hear it.',
        chips: const ['Read it to me', 'I will read'],
        action: TutorAction(
          kind: TutorActionKind.openReading,
          target: '',
          label: 'Open my reader',
        ),
      );
    }

    if (_hasAny(text, ['game', 'play'])) {
      return TutorReply(
        text: 'Games make sounds stick. Play Sound Match — you have '
            'the $focus sound right now.',
        chips: const ['Bubble Pop', 'Spell Builder'],
        action: const TutorAction(
          kind: TutorActionKind.openGame,
          target: 'sound_match',
          label: 'Play Sound Match',
        ),
      );
    }

    if (_hasAny(text, ['hi', 'hello', 'hey', 'sad', 'tired', 'mum', 'dad'])) {
      return TutorReply(
        text: 'Hi ${context.learnerName}! I am Aria. You are on '
            '"${context.levelLabel}" today. Shall we teach one sound?',
        chips: const ['What sound is this?', 'Help me read this', 'Play a game'],
      );
    }

    return TutorReply(
      text: 'Let us keep it about reading. ${focus == 's' ? 'sss' : focus} — '
          'what word starts with that? Say one and I will check it.',
      chips: ['Hear focus', 'A word with $focus', 'Play a game'],
      action: TutorAction(
        kind: TutorActionKind.openPronunciation,
        target: focus,
      ),
    );
  }

  static bool _hasAny(String haystack, List<String> needles) =>
      needles.any(haystack.contains);

  static String _exampleFor(String phoneme) => switch (phoneme) {
        's' => 'sun',
        'a' => 'ant',
        't' => 'tin',
        'p' => 'pan',
        'i' => 'ink',
        'n' => 'net',
        'sh' => 'ship',
        'ch' => 'chip',
        'th' => 'thin',
        _ => '$phoneme…',
      };

  static String _mouthHint(String phoneme) => switch (phoneme) {
        's' || 'z' => 'tongue close behind your teeth',
        'f' || 'v' => 'top teeth on your bottom lip',
        'th' => 'tongue tip between your teeth',
        'm' || 'n' => 'lips together for m, tongue up for n',
        _ => 'mouth ready and say it long',
      };

  static String _spellTip(String phoneme) => switch (phoneme) {
        'sh' || 'ch' || 'th' || 'wh' || 'ck' || 'ng' =>
          'Two letters, one sound — never say "shuh", just "shhh".',
        _ => 'Tap the letters in order as you say each sound.',
      };

  static String _rhymesFor(String phoneme) => switch (phoneme) {
        's' => 'sun, fun, bun, run',
        'a' => 'cat, hat, bat, mat',
        't' => 'hat, cat, bat, mat',
        'p' => 'cup, pup, sup, yup',
        'n' => 'sun, fun, bun, pin',
        _ => '$phoneme-at, $phoneme-ot, $phoneme-ig',
      };

  static String _storyFor(String phoneme) => switch (phoneme) {
        's' => 'Sam the snake sat on a big stone.',
        'a' => 'An ant and an ax had a nap.',
        't' => 'Pat the cat tapped ten tin tins.',
        _ => 'The $phoneme was in the pot, got, spot, not.',
      };

  @override
  Future<Result<List<String>>> suggestedStarters(TutorContext context) async {
    final starters = [
      'What sound is "${context.recentPhonemes.isEmpty ? 'sh' : context.recentPhonemes.first}"?',
      'Help me read this',
      'Give me a rhyme',
      'Play a game with me',
    ];
    if (context.strugglingPhonemes.isNotEmpty) {
      starters.insert(
        0,
        'Practise ${context.strugglingPhonemes.first} with me',
      );
    }
    return Result.ok(starters);
  }
}
