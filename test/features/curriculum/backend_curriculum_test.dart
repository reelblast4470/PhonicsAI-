import 'package:flutter_test/flutter_test.dart';
import 'package:phonicsai/core/domain/reading_level.dart';
import 'package:phonicsai/features/curriculum/data/backend_curriculum.dart';
import 'package:phonicsai/features/curriculum/domain/lesson.dart';

/// A faithful miniature of `GET /content/curriculum` (shape lives in
/// `api/app/routers/content.py::full_curriculum`; the live contract test in
/// test/live/ guards against drift).
Map<String, dynamic> samplePayload() => {
      'version': 'abc123',
      'courses': [
        {
          'id': 'course-1',
          'slug': 'phonics-foundations',
          'title': 'Phonics Foundations',
          'origin': 'seed:curriculum-v1',
          'modules': [
            {
              'id': 'mod-1',
              'title': 'First sounds: s a t p i n',
              'position': 1,
              'lessons': [
                {
                  'id': '11111111-1111-1111-1111-111111111111',
                  'code': 'letter-s',
                  'title': 'The sound of “s”',
                  'summary': 'Focus: s (/s/)',
                  'position': 1,
                  'est_seconds': 240,
                  'xp_reward': 20,
                  'steps': [
                    {
                      'id': 'step-1',
                      'position': 1,
                      'step_type': 'discover',
                      'payload': {
                        'prompt': "Let's chase the s sound today!",
                        'emoji': '☀️',
                      },
                      'questions': [],
                    },
                    {
                      'id': 'step-2',
                      'position': 2,
                      'step_type': 'hear',
                      'payload': {'tts': 's', 'word': 'sun'},
                      'questions': [
                        {
                          'id': 'q-1',
                          'position': 0,
                          'kind': 'multiple_choice',
                          'points': 5,
                          'explanation': 'sun starts with the /s/ sound.',
                          'prompt': {
                            'text': 'Which one starts with the /s/ sound?',
                          },
                          'answers': [
                            {'id': 'a-x', 'position': 0, 'text': 'cat'},
                            {'id': 'a-y', 'position': 1, 'text': 'sun'},
                            {'id': 'a-z', 'position': 2, 'text': 'bed'},
                          ],
                        },
                      ],
                    },
                    {
                      'id': 'step-5',
                      'position': 5,
                      'step_type': 'practice',
                      'payload': {
                        'builder': {
                          'letters': ['S', 'U', 'N'],
                          'word': 'sun',
                        },
                      },
                      'questions': [
                        {
                          'id': 'q-2',
                          'position': 0,
                          'kind': 'multiple_choice',
                          'points': 5,
                          'prompt': {'text': 'Which word is this?'},
                          'answers': [
                            {'id': 'b-1', 'position': 0, 'text': 'sun'},
                            {'id': 'b-2', 'position': 1, 'text': 'pot'},
                          ],
                        },
                      ],
                    },
                    {
                      'id': 'step-10',
                      'position': 10,
                      'step_type': 'review',
                      'payload': {
                        'phoneme': 's',
                        'grapheme': 's',
                      },
                      'questions': [],
                    },
                  ],
                },
              ],
            },
          ],
        },
      ],
    };

void main() {
  group('BackendCurriculum.fromJson', () {
    final mapped = BackendCurriculum.fromJson(samplePayload());
    final unit = mapped.units.single;
    final lesson = unit.lessons.single;

    test('units/lessons get stable code ids and remote uuids', () {
      expect(unit.id, 'mod-1');
      expect(unit.order, 1);
      expect(unit.level, ReadingLevel.preReader);
      expect(lesson.id, 'letter-s'); // progress keys stay stable across syncs
      expect(lesson.remoteId, '11111111-1111-1111-1111-111111111111');
      expect(mapped.lessonUuids['letter-s'], lesson.remoteId);
      expect(mapped.stepUuids['letter-s:2'], 'step-2');
      expect(mapped.version, 'abc123');
    });

    test('remote questions carry handles, never the answer key', () {
      final hear = lesson.stages.firstWhere((s) => s.kind == StageKind.hear);
      final item = hear.items.single;
      expect(item.remoteQuestionId, 'q-1');
      expect(item.optionIds, ['a-x', 'a-y', 'a-z']);
      expect(item.options, ['cat', 'sun', 'bed']);
      expect(item.correctIndex, isNull); // server decides
      expect(item.isRemoteGraded, isTrue);
    });

    test('practice merges the server question with the local builder', () {
      final practice =
          lesson.stages.firstWhere((s) => s.kind == StageKind.practice);
      expect(practice.items.any((i) => i.isBuilder), isTrue);
      expect(practice.items.where((i) => i.isRemoteGraded).single.optionIds,
          ['b-1', 'b-2']);
    });

    test('phonemes come from the review payload for SRS + display', () {
      expect(lesson.phonemes, contains('s'));
    });

    test('question order is by server position, options preserved', () {
      final hear = lesson.stages.firstWhere((s) => s.kind == StageKind.hear);
      expect(hear.items.single.options.first, 'cat');
    });
  });
}
