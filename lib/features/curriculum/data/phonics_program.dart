import '../../../core/domain/reading_level.dart';
import '../domain/lesson.dart';
import '../domain/phoneme.dart';

/// The PhonicsAI program, expressed as content.
///
/// Letters and Sounds / "synthetic phonics" order — the sequence research and
/// most school systems use — because the order *is* the pedagogy: s a t p i n
/// first lets a child read real words ("sat", "pin", "naps") inside a week.
///
/// Screens never hard-code a single sound or word: everything they show comes
/// from here, so a content update is a data change and the app can ship a new
/// program without a rebuild (later, from the content API).
abstract final class PhonicsProgram {
  static const Map<String, String> pictures = {
    'sun': '☀️',
    'sock': '🧦',
    'sand': '🏖️',
    'snake': '🐍',
    'soup': '🍲',
    'ant': '🐜',
    'apple': '🍎',
    'ax': '🪓',
    'ink': '🖋️',
    'insect': '🐜',
    'tap': '🚰',
    'pin': '📌',
    'pan': '🍳',
    'net': '🕸️',
    'cat': '🐱',
    'cap': '🧢',
    'cup': '🥤',
    'kite': '🪁',
    'king': '🤴',
    'hen': '🐔',
    'hat': '🎩',
    'hip': '🐙',
    'red': '🔴',
    'rug': '🧶',
    'dog': '🐶',
    'dig': '⛏️',
    'drum': '🥁',
    'map': '🗺️',
    'mat': '🧘',
    'fin': '🐟',
    'fish': '🐟',
    'frog': '🐸',
    'fox': '🦊',
    'leaf': '🍃',
    'leg': '🦵',
    'lip': '👄',
    'ship': '🚢',
    'shop': '🏪',
    'shell': '🐚',
    'chin': '🧑',
    'chip': '🍟',
    'chest': '🧰',
    'thin': '🥢',
    'think': '🤔',
    'bath': '🛁',
    'duck': '🦆',
    'rock': '🪨',
    'ring': '💍',
    'queen': '👑',
    'quit': '🚪',
    'quick': '⚡',
    'cake': '🎂',
    'gate': '🚪',
    'bone': '🦴',
    'note': '📝',
    'cube': '🧊',
    'mule': '🐴',
    'rain': '🌧️',
    'tail': '🐒',
    'play': '🎮',
    'day': '☀️',
    'bee': '🐝',
    'see': '👀',
    'read': '📖',
    'team': '👥',
    'boat': '⛵',
    'coat': '🧥',
    'snow': '❄️',
    'grow': '🌱',
    'cow': '🐄',
    'owl': '🦉',
    'bird': '🐦',
    'nurse': '🧑‍⚕️',
    'her': '👩',
    'star': '⭐',
    'corn': '🌽',
    'for': '🔁',
    'car': '🚗',
    'farm': '🚜',
    'moon': '🌙',
    'book': '📕',
    'food': '🍚',
    'good': '👍',
    'house': '🏠',
    'mouse': '🐭',
    'cloud': '☁️',
    'loud': '📢',
    'night': '🌃',
    'light': '💡',
    'goat': '🐐',
    'feet': '🦶',
    'street': '🏙️',
    'green': '🟢',
    'sleep': '😴',
    'sheep': '🐑',
    'chat': '💬',
    'bell': '🔔',
    'ball': '⚽',
    'still': '🗿',
    'grass': '🌿',
    'kiss': '💋',
    'miss': '🎯',
    'buzz': '🐝',
    'fizz': '🥤',
    'jam': '🍓',
    'jar': '🫙',
    'gin': '🍸',
    'page': '📄',
    'cage': '🪤',
    'edge': '📏',
    'lane': '🛣️',
    'name': '🏷️',
    'wave': '🌊',
    'came': '🐫',
    'home': '🏡',
    'rope': '🪢',
    'use': '🛠️',
    'cute': '🐹',
    'tune': '🎵',
    'five': '🖐️',
    'hive': '🐝',
    'side': '📐',
    'rite': '📜',
    'robe': '🥻',
    'mop': '🧹',
    'hop': '🐇',
    'top': '🔝',
    'log': '🪵',
    'bud': '🌱',
    'bug': '🐛',
    'tub': '🛁',
    'bus': '🚌',
    'pup': '🐶',
    'nut': '🥜',
    'jut': '↗️',
    'rim': '🛞',
    'sip': '🥤',
    'tip': '👆',
    'nip': '✂️',
    'sad': '😞',
    'bad': '🙅',
    'dad': '👨',
    'man': '👨',
    'van': '🚐',
    'can': '🥫',
    'hand': '✋',
    'land': '🗺️',
    'stand': '🧍',
    'panda': '🐼',
  };

  static String? emojiFor(String word) => pictures[word.toLowerCase()];

  // --------------------------------------------------------------- unit specs
  static const List<_UnitSpec> _specs = [
    _UnitSpec(
      id: 'unit_satpin',
      title: 'First six sounds',
      blurb: 's a t p i n — enough to read real words in week one',
      level: ReadingLevel.preReader,
      sentences: [
        'Sam sat on the mat.',
        'Pat pinned the net.',
        'An ant sat in the pan.',
        'Nan tap­ped the tin.',
      ],
      groups: [
        [
          Phoneme(grapheme: 's', ipa: '/s/', words: ['sun', 'sock', 'sand', 'snake'], mnemonic: 'long hissing snake'),
          Phoneme(grapheme: 'a', ipa: '/æ/', words: ['ant', 'apple', 'ax', 'pan'], mnemonic: 'open-mouth a as in apple'),
        ],
        [
          Phoneme(grapheme: 't', ipa: '/t/', words: ['tap', 'tin', 'net', 'cat'], mnemonic: 'tongue taps the ridge'),
          Phoneme(grapheme: 'p', ipa: '/p/', words: ['pin', 'pan', 'cup', 'cap'], mnemonic: 'a puff of air'),
        ],
        [
          Phoneme(grapheme: 'i', ipa: '/ɪ/', words: ['ink', 'pin', 'fish', 'lip'], mnemonic: 'short i in pin'),
          Phoneme(grapheme: 'n', ipa: '/n/', words: ['net', 'sun', 'fan', 'nine'], mnemonic: 'nose sound'),
        ],
      ],
    ),
    _UnitSpec(
      id: 'unit_ckhvg',
      title: 'More letters, longer words',
      blurb: 'c k e h r m d g plus short vowels',
      level: ReadingLevel.letterSounds,
      sentences: [
        'The dog ran to me.',
        'Hen hid in the mud.',
        'Meg dug a big hole.',
        'Rick had a red drum.',
      ],
      groups: [
        [
          Phoneme(grapheme: 'c', ipa: '/k/', words: ['cat', 'cap', 'cup', 'ice'], mnemonic: 'hard c before a, o, u'),
          Phoneme(grapheme: 'k', ipa: '/k/', words: ['kite', 'king', 'milk', 'duck'], mnemonic: 'same sound, usually not at the start'),
        ],
        [
          Phoneme(grapheme: 'e', ipa: '/ɛ/', words: ['hen', 'net', 'red', 'bed'], mnemonic: 'short e in hen'),
          Phoneme(grapheme: 'h', ipa: '/h/', words: ['hat', 'hip', 'hen', 'house'], mnemonic: 'a breath out'),
        ],
        [
          Phoneme(grapheme: 'r', ipa: '/r/', words: ['rug', 'rat', 'red', 'farm'], mnemonic: 'growling r'),
          Phoneme(grapheme: 'm', ipa: '/m/', words: ['map', 'moon', 'mop', 'man'], mnemonic: 'lips closed, mm'),
        ],
        [
          Phoneme(grapheme: 'd', ipa: '/d/', words: ['dog', 'dig', 'drum', 'bed'], mnemonic: 'tongue tap, voiced'),
          Phoneme(grapheme: 'g', ipa: '/ɡ/', words: ['goat', 'gate', 'leg', 'bag'], mnemonic: 'hard g before a, o, u'),
        ],
      ],
    ),
    _UnitSpec(
      id: 'unit_flossy',
      title: 'Two letters, one sound',
      blurb: 'f l ss sh ch th — digraphs and doubled ends',
      level: ReadingLevel.cvcBlender,
      sentences: [
        'The fish is on the shelf.',
        'Shop and chin both end in a sound.',
        'Throw the ball to my brother.',
        'Chips and fish at the shop.',
      ],
      groups: [
        [
          Phoneme(grapheme: 'f', ipa: '/f/', words: ['fin', 'fish', 'leaf', 'frog'], isDigraph: false, mnemonic: 'teeth on lip'),
          Phoneme(grapheme: 'ff', ipa: '/f/', words: ['muff', 'puff', 'fluff'], isDigraph: true, mnemonic: 'f at the end of a short-vowel word doubles'),
        ],
        [
          Phoneme(grapheme: 'l', ipa: '/l/', words: ['leg', 'lip', 'bell', 'ball'], mnemonic: 'tongue up'),
          Phoneme(grapheme: 'll', ipa: '/l/', words: ['fill', 'ball', 'still', 'bell'], isDigraph: true, mnemonic: 'll ends words like -ff'),
        ],
        [
          Phoneme(grapheme: 'sh', ipa: '/ʃ/', words: ['ship', 'shell', 'shop', 'fish'], isDigraph: true, mnemonic: 'be quiet: shhh'),
          Phoneme(grapheme: 'ch', ipa: '/tʃ/', words: ['chat', 'chip', 'chest', 'chin'], isDigraph: true, mnemonic: 'a train chuff'),
        ],
        [
          Phoneme(grapheme: 'th', ipa: '/θ/', words: ['thin', 'bath', 'think', 'teeth'], isDigraph: true, mnemonic: 'tongue between teeth'),
          Phoneme(grapheme: 'ss', ipa: '/s/', words: ['kiss', 'miss', 'grass'], isDigraph: true, mnemonic: 'ss ends words like -ff'),
        ],
      ],
    ),
    _UnitSpec(
      id: 'unit_magice',
      title: 'Magic e',
      blurb: 'a_e i_e o_e u_e — the silent e that changes the vowel',
      level: ReadingLevel.earlyDecoder,
      sentences: [
        'Jake came home by the lake.',
        'The cute mule ate a huge plum.',
        'We read these notes on the phone.',
        'Hide the kite inside the hive.',
      ],
      groups: [
        [
          Phoneme(grapheme: 'a_e', ipa: '/eɪ/', words: ['cake', 'gate', 'name', 'lake'], longVariant: 'a', mnemonic: 'a says its name'),
          Phoneme(grapheme: 'i_e', ipa: '/aɪ/', words: ['kite', 'five', 'hive', 'side'], longVariant: 'i', mnemonic: 'i says its name'),
        ],
        [
          Phoneme(grapheme: 'o_e', ipa: '/oʊ/', words: ['bone', 'note', 'home', 'rope'], longVariant: 'o', mnemonic: 'o says its name'),
          Phoneme(grapheme: 'u_e', ipa: '/juː/', words: ['cube', 'mule', 'cute', 'tune'], longVariant: 'u', mnemonic: 'u says its name'),
        ],
        [
          Phoneme(grapheme: 'ck', ipa: '/k/', words: ['duck', 'rock', 'sock', 'truck'], isDigraph: true, mnemonic: 'ck after a short vowel'),
          Phoneme(grapheme: 'ng', ipa: '/ŋ/', words: ['ring', 'king', 'sing', 'long'], isDigraph: true, mnemonic: 'nose hum at the end'),
        ],
      ],
    ),
    _UnitSpec(
      id: 'unit_vowelteams',
      title: 'Vowel teams',
      blurb: 'ai ay ee ea oa ow ai — when two vowels hold hands',
      level: ReadingLevel.earlyDecoder,
      sentences: [
        'The rain fell on the green street.',
        'We read the team\'s speech at noon.',
        'The goat rowed the boat in the snow.',
        'The owl saw a brown cow down.',
      ],
      groups: [
        [
          Phoneme(grapheme: 'ai', ipa: '/eɪ/', words: ['rain', 'tail', 'train', 'snail'], isDigraph: true, mnemonic: 'when two vowels go walking, the first one talks'),
          Phoneme(grapheme: 'ay', ipa: '/eɪ/', words: ['play', 'day', 'way', 'spray'], isDigraph: true, mnemonic: 'ay never starts a word'),
        ],
        [
          Phoneme(grapheme: 'ee', ipa: '/iː/', words: ['bee', 'feet', 'tree', 'green'], isDigraph: true, mnemonic: 'long e in the middle'),
          Phoneme(grapheme: 'ea', ipa: '/iː/', words: ['read', 'team', 'leaf', 'dream'], isDigraph: true, mnemonic: 'long e in the middle too'),
        ],
        [
          Phoneme(grapheme: 'oa', ipa: '/oʊ/', words: ['boat', 'coat', 'road', 'goat'], isDigraph: true, mnemonic: 'long o in the middle'),
          Phoneme(grapheme: 'ow', ipa: '/oʊ/', words: ['snow', 'grow', 'show', 'window'], isDigraph: true, mnemonic: 'ow at the end says oh'),
        ],
        [
          Phoneme(grapheme: 'ou', ipa: '/aʊ/', words: ['out', 'cloud', 'shout', 'trout'], isDigraph: true, mnemonic: 'ou in the middle says ow'),
          Phoneme(grapheme: 'oo', ipa: '/uː/', words: ['moon', 'food', 'zoo', 'cool'], isDigraph: true, mnemonic: 'oo like a hoot'),
        ],
      ],
    ),
    _UnitSpec(
      id: 'unit_rcontrolled',
      title: 'R changes the vowel',
      blurb: 'ar er ir or ur, soft c and g, and the -tion tail',
      level: ReadingLevel.fluentReader,
      sentences: [
        'The nurse heard a bird in the park.',
        'Our farm has forty corn rows.',
        'George found a page about magic.',
        'The station has a big platform.',
      ],
      groups: [
        [
          Phoneme(grapheme: 'ar', ipa: '/ɑː/', words: ['star', 'car', 'farm', 'park'], isDigraph: true, mnemonic: 'r growls the a'),
          Phoneme(grapheme: 'or', ipa: '/ɔː/', words: ['corn', 'fork', 'sport', 'for'], isDigraph: true, mnemonic: 'r rounds the o'),
        ],
        [
          Phoneme(grapheme: 'er', ipa: '/ɜː/', words: ['her', 'never', 'sister', 'letter'], isDigraph: true, mnemonic: 'the tired little r sound'),
          Phoneme(grapheme: 'ir', ipa: '/ɜː/', words: ['bird', 'first', 'shirt', 'girl'], isDigraph: true, mnemonic: 'same sound as er'),
        ],
        [
          Phoneme(grapheme: 'ur', ipa: '/ɜː/', words: ['nurse', 'turn', 'burn', 'hurt'], isDigraph: true, mnemonic: 'same sound again, spelling by place'),
          Phoneme(grapheme: 'air', ipa: '/ɛə/', words: ['chair', 'hair', 'pair', 'fair'], isDigraph: true, mnemonic: 'three letters, one sound'),
        ],
        [
          Phoneme(grapheme: 'tion', ipa: '/ʃən/', words: ['station', 'action', 'lion', 'nation'], isDigraph: true, mnemonic: 'the tail that ends a lot of words'),
          Phoneme(grapheme: 'soft_c', ipa: '/s/', words: ['ice', 'city', 'centre', 'dance'], isDigraph: true, mnemonic: 'c is soft before e, i, y'),
        ],
      ],
    ),
  ];

  static List<CurriculumUnit> build() {
    final units = <CurriculumUnit>[];
    for (var u = 0; u < _specs.length; u++) {
      units.add(_specs[u].toUnit(order: u));
    }
    return List.unmodifiable(units);
  }

  /// Words from other sounds, used as distractors that cannot accidentally
  /// contain the target phoneme.
  static List<String> distractorsFor(Phoneme target, {int count = 2}) {
    final forbidden = target.grapheme.replaceAll('_', '').replaceAll('soft_c', 'c');
    final pool = <String>[];
    for (final unit in _specs) {
      for (final group in unit.groups) {
        for (final phoneme in group) {
          if (phoneme.grapheme == target.grapheme) continue;
          for (final word in phoneme.words) {
            if (!word.contains(forbidden)) pool.add(word);
          }
        }
      }
    }
    pool.sort((a, b) => a.length.compareTo(b.length));
    return pool.take(count * 3).toSet().take(count + 1).toList();
  }
}

class _UnitSpec {
  const _UnitSpec({
    required this.id,
    required this.title,
    required this.blurb,
    required this.level,
    required this.sentences,
    required this.groups,
  });

  final String id;
  final String title;
  final String blurb;
  final ReadingLevel level;
  final List<String> sentences;

  /// One lesson per group of two phonemes.
  final List<List<Phoneme>> groups;

  CurriculumUnit toUnit({required int order}) {
    final phonemes = [for (final g in groups) ...g];
    final lessons = <PhonicsLesson>[];
    for (var i = 0; i < groups.length; i++) {
      final group = groups[i];
      lessons.add(
        PhonicsLesson(
          id: '${id}_l${i + 1}',
          unitId: id,
          title: group.map((p) => p.grapheme.replaceAll('soft_c', 'c')).join(' + '),
          subtitle: group.first.mnemonic,
          indexInUnit: i,
          phonemes: [for (final p in group) p.grapheme],
          stages: LessonStageBuilder.build(
            lessonIndex: i,
            group: group,
            sentences: sentences,
            unitId: id,
          ),
        ),
      );
    }
    return CurriculumUnit(
      id: id,
      title: title,
      blurb: blurb,
      level: level,
      order: order,
      phonemes: phonemes,
      lessons: lessons,
    );
  }
}

/// Turns a group of phonemes into the ten-stage lesson.
abstract final class LessonStageBuilder {
  static List<LessonStage> build({
    required String unitId,
    required int lessonIndex,
    required List<Phoneme> group,
    required List<String> sentences,
  }) {
    final primary = group.first;
    final secondary = group.length > 1 ? group[1] : group.first;
    final words = [...primary.words, ...secondary.words];
    final sentence = sentences[lessonIndex % sentences.length];
    final target = words.first;

    List<StageItem> choices(Phoneme phoneme) {
      final correct = phoneme.words.first;
      final others = PhonicsProgram.distractorsFor(phoneme, count: 2);
      final options = [correct, ...others]..shuffle();
      return [
        StageItem(
          id: '${phoneme.grapheme}_choice',
          prompt: 'Which one starts with ${phoneme.say}?',
          options: options,
          correctIndex: options.indexOf(correct),
          audioText: 'Which one starts with ${phoneme.say}?',
        ),
      ];
    }

    return [
      LessonStage(
        kind: StageKind.discover,
        introText: 'Look closely. What can you hear?',
        items: [
          StageItem(
            id: '${unitId}_discover',
            prompt: 'These words all hide the same sound: ${primary.say} or ${secondary.say}.',
            emoji: PhonicsProgram.emojiFor(target),
            text: target,
            audioText: words.take(3).join(', '),
          ),
        ],
      ),
      LessonStage(
        kind: StageKind.hear,
        items: [
          ...choices(primary),
          ...choices(secondary),
        ],
      ),
      LessonStage(
        kind: StageKind.see,
        introText: 'This is how we write that sound.',
        items: [
          for (final phoneme in group)
            StageItem(
              id: 'see_${phoneme.grapheme}',
              prompt: phoneme.mnemonic.isEmpty
                  ? '${phoneme.grapheme} says ${phoneme.say}'
                  : '${phoneme.grapheme} says ${phoneme.say} — ${phoneme.mnemonic}',
              text: phoneme.grapheme.toUpperCase(),
              audioText: phoneme.say,
              letters: phoneme.grapheme
                  .replaceAll('_', '')
                  .split('')
                  .where((c) => c.isNotEmpty)
                  .toList(),
            ),
        ],
      ),
      LessonStage(
        kind: StageKind.understand,
        items: [
          StageItem(
            id: 'rule',
            prompt: switch (primary.longVariant) {
              final String? variant when variant != null =>
                'A magic $variant makes the ${primary.longVariant} say its name.',
              _ => '${primary.grapheme} and ${secondary.grapheme} are two letters that '
                  'make one sound. Do not add an "uh" after them.',
            },
            text: words.take(4).join(' · '),
            emoji: '💡',
          ),
        ],
      ),
      LessonStage(
        kind: StageKind.practice,
        items: [
          for (final word in words.take(3))
            StageItem(
              id: 'build_$word',
              prompt: 'Build the word',
              targetWord: word,
              letters: word
                  .toUpperCase()
                  .split('')
                  ..sort((a, b) => a.codeUnitAt(0).compareTo(b.codeUnitAt(0))),
              emoji: PhonicsProgram.emojiFor(word),
            ),
        ],
      ),
      LessonStage(
        kind: StageKind.play,
        introText: 'Pick a game — it practises the same sounds.',
        items: const [],
        gameId: 'sound_match',
      ),
      LessonStage(
        kind: StageKind.recall,
        items: [
          for (final phoneme in group)
            StageItem(
              id: 'recall_${phoneme.grapheme}',
              prompt: 'Quick! What sound is this?',
              text: phoneme.grapheme.toUpperCase(),
              options: [phoneme.say, ...PhonicsProgram.distractorsFor(phoneme, count: 2)],
              correctIndex: 0,
            ),
        ],
      ),
      LessonStage(
        kind: StageKind.speak,
        introText: 'Say the word out loud.',
        items: [
          for (final word in words.take(2))
            StageItem(
              id: 'say_$word',
              prompt: 'Say "$word"',
              text: word,
              emoji: PhonicsProgram.emojiFor(word),
              targetWord: word,
            ),
        ],
        wordId: target,
      ),
      LessonStage(
        kind: StageKind.read,
        items: [
          StageItem(
            id: 'read_sentence',
            prompt: sentence,
            text: sentence,
            audioText: sentence,
          ),
        ],
        passageId: '${unitId}_p${lessonIndex + 1}',
      ),
      LessonStage(
        kind: StageKind.review,
        introText: 'What you learnt today',
        items: [
          StageItem(
            id: 'review_summary',
            prompt: [
              for (final p in group) '${p.grapheme} → ${p.say}',
            ].join('   '),
            text: words.take(4).join(', '),
          ),
        ],
      ),
    ];
  }
}
