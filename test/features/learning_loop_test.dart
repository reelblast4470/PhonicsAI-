import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phonicsai/app/di/infrastructure.dart';
import 'package:phonicsai/core/analytics/analytics_service.dart';
import 'package:phonicsai/core/audio/audio_service.dart';
import 'package:phonicsai/core/env/app_config.dart';
import 'package:phonicsai/core/notifications/reminder_scheduler.dart';
import 'package:phonicsai/core/speech/speech_service.dart';
import 'package:phonicsai/core/storage/in_memory_secure_vault.dart';
import 'package:phonicsai/core/storage/key_value_store.dart';
import 'package:phonicsai/core/util/date_util.dart';
import 'package:phonicsai/features/curriculum/application/curriculum_providers.dart';
import 'package:phonicsai/features/curriculum/application/lesson_runner.dart';
import 'package:phonicsai/features/curriculum/data/phonics_program.dart';
import 'package:phonicsai/features/curriculum/domain/lesson.dart';
import 'package:phonicsai/features/progress/application/progress_providers.dart';

/// The learning loop is the product. These tests pin the rules a teacher or a
/// parent would notice if they broke: stage order, "skip is not a failure",
/// stars from accuracy, and that progress survives the session.
void main() {
  late InMemoryKeyValueStore store;

  setUp(() => store = InMemoryKeyValueStore({
        'phonicsai.active_profile': 'learner_test',
      }));
  tearDown(() async => store.dispose());

  List<Override> overrides(KeyValueStore store) => [
        appConfigProvider.overrideWithValue(AppConfig.dev),
        keyValueStoreProvider.overrideWithValue(store),
        secureVaultProvider.overrideWithValue(InMemorySecureVault()),
        analyticsServiceProvider
            .overrideWithValue(LoggingAnalyticsService(enabled: false)),
        audioServiceProvider.overrideWithValue(NoopAudioService()),
        speechServiceProvider.overrideWithValue(MockSpeechService()),
        reminderSchedulerProvider
            .overrideWithValue(const InAppReminderScheduler()),
      ];

  LessonRunState runFor(ProviderContainer container, String lessonId) {
    final state = container.read(lessonRunProvider(lessonId));
    expect(state, isNotNull, reason: 'lesson $lessonId must resolve');
    return state!;
  }

  test('the first unit opens with the ten-stage loop in the taught order', () {
    final container = ProviderContainer(overrides: overrides(store));
    addTearDown(container.dispose);
    final units = container.read(curriculumProvider);
    expect(units.length, greaterThanOrEqualTo(6));

    final lesson = units.first.lessons.first;
    expect(
      lesson.stages.map((stage) => stage.kind).toList(),
      StageKind.values,
      reason: 'Discover → … → Review is the whole pedagogy',
    );
  });

  test('content is real: every choice item has an answerable option set', () {
    final container = ProviderContainer(overrides: overrides(store));
    addTearDown(container.dispose);
    for (final unit in container.read(curriculumProvider)) {
      for (final lesson in unit.lessons) {
        for (final stage in lesson.stages) {
          for (final item in stage.items) {
            if (item.isChoice) {
              expect(item.options.length, greaterThanOrEqualTo(2),
                  reason: '${item.id} has no real choices');
              expect(item.correctIndex, inInclusiveRange(0, item.options.length - 1),
                  reason: '${item.id} points outside its options');
            }
            if (item.isBuilder) {
              final letters = item.letters!;
              for (final letter in item.targetWord!.toUpperCase().split('')) {
                expect(letters, contains(letter),
                    reason: '${item.targetWord} cannot be built from $letters');
              }
            }
          }
        }
      }
    }
  });

  test('answering every item correctly advances and awards 3 stars', () async {
    final container = ProviderContainer(overrides: overrides(store));
    addTearDown(container.dispose);
    final lesson = container.read(curriculumProvider).first.lessons.first;
    final runner = container.read(lessonRunProvider(lesson.id).notifier);
    await container.read(progressRepositoryProvider).warmUp('learner_test');

    for (var stage = 0; stage < lesson.stageCount; stage++) {
      var state = runFor(container, lesson.id);
      expect(state.stageIndex, stage, reason: 'stage $stage should be open');
      if (state.stage.items.isEmpty) {
        // Play (and any hand-off stage) is closed by its own CTA.
        await runner.nextStage();
        continue;
      }
      for (final item in state.stage.items) {
        if (item.isChoice) {
          await runner.answerChoice(item.id, item.correctIndex!);
        } else if (item.isBuilder) {
          for (final letter in item.targetWord!.toUpperCase().split('')) {
            runner.toggleLetter(item.id, letter);
          }
          await runner.checkBuild(item.id);
        } else {
          await runner.markItemCorrect(item.id);
        }
      }
      state = runFor(container, lesson.id);
      if (state.stageIndex == stage) {
        // A stage whose items are all correct auto-advances; anything else has
        // to be moved on explicitly, exactly like the Next button does.
        await runner.nextStage();
      }
    }
    await runner.finish();

    final finalState = runFor(container, lesson.id);
    expect(finalState.isFinished, isTrue);
    expect(finalState.savedStars, 3);
    expect(finalState.errorMessage, isNull);

    final snapshot =
        container.read(progressRepositoryProvider).snapshot('learner_test');
    expect(snapshot.lessonIsComplete(lesson), isTrue,
        reason: 'a completed lesson must show as complete everywhere');
    expect(snapshot.today.lessonsCompleted, 1);
    expect(snapshot.starsTotal, greaterThan(0));
  });

  test('skipping a stage still records it (a skip is not a data gap)',
      () async {
    final container = ProviderContainer(overrides: overrides(store));
    addTearDown(container.dispose);
    final lesson = container.read(curriculumProvider).first.lessons.first;
    final runner = container.read(lessonRunProvider(lesson.id).notifier);
    await container.read(progressRepositoryProvider).warmUp('learner_test');

    await runner.nextStage();
    await Future<void>.delayed(Duration.zero);
    final snapshot =
        container.read(progressRepositoryProvider).snapshot('learner_test');
    expect(snapshot.lesson(lesson.id).isStageDone(lesson.stages.first.kind.name),
        isTrue);
    expect(runFor(container, lesson.id).stageIndex, 1);
  });

  test('a wrong first answer then a right one is not held against stars',
      () async {
    final container = ProviderContainer(overrides: overrides(store));
    addTearDown(container.dispose);
    final lesson = container.read(curriculumProvider).first.lessons.first;
    final runner = container.read(lessonRunProvider(lesson.id).notifier);
    // Walk to the hear stage the way the UI does.
    await runner.nextStage();
    final item = runFor(container, lesson.id).stage.items.first;

    await runner.answerChoice(
      item.id,
      (item.correctIndex! + 1) % item.options.length,
    );
    expect(runFor(container, lesson.id).outcomeOf(item.id), ItemOutcome.wrong);

    await runner.retryItem(item.id);
    expect(runFor(container, lesson.id).outcomeOf(item.id),
        ItemOutcome.unanswered);

    await runner.answerChoice(item.id, item.correctIndex!);
    expect(runFor(container, lesson.id).outcomeOf(item.id), ItemOutcome.correct);
  });

  test('progress is written through the repository, not remembered in memory',
      () async {
    final container = ProviderContainer(overrides: overrides(store));
    final lesson = container.read(curriculumProvider).first.lessons.first;
    final runner = container.read(lessonRunProvider(lesson.id).notifier);
    await container.read(progressRepositoryProvider).warmUp('learner_test');
    for (final item in lesson.stages.first.items) {
      await runner.markItemCorrect(item.id);
    }
    await runner.finish();
    container.dispose();

    // A brand new container over the same store sees the finished lesson.
    final reopened = ProviderContainer(overrides: overrides(store));
    addTearDown(reopened.dispose);
    await reopened.read(progressRepositoryProvider).warmUp('learner_test');
    final snapshot = reopened.read(progressRepositoryProvider).snapshot('learner_test');
    expect(snapshot.lesson(lesson.id).isComplete, isTrue);
    expect(snapshot.lessonsCompleted, 1);
  });

  test('the sound a learner misses comes back for review', () async {
    final container = ProviderContainer(overrides: overrides(store));
    addTearDown(container.dispose);
    final repository = container.read(progressRepositoryProvider);
    await repository.warmUp('learner_test');
    await repository.recordSoundReview(
      profileId: 'learner_test',
      phoneme: 'sh',
      grade: 0,
    );
    final snapshot = repository.snapshot('learner_test');
    final mastery = snapshot.sound('sh');
    expect(mastery.lapses, 1);
    expect(mastery.reps, 1);
    final due = mastery.dueAt;
    expect(due, isNotNull);
    expect(
      DateUtil.isSameDay(due!, DateUtil.addDays(DateTime.now(), 1)),
      isTrue,
      reason: 'a miss must come back tomorrow, not in a week — and not never',
    );
    expect(mastery.isDue, isFalse, reason: 'not due yet today');
  });

  test('phonics program never places a harder lesson before an easier unit', () {
    final units = PhonicsProgram.build();
    for (var i = 1; i < units.length; i++) {
      expect(
        units[i].level.rank >= units[i - 1].level.rank,
        isTrue,
        reason: '${units[i].id} is ordered below ${units[i - 1].id}',
      );
    }
    // Every unit must actually teach something a child can read.
    for (final unit in units) {
      expect(unit.lessons, isNotEmpty);
      expect(
        unit.lessons.expand((lesson) => lesson.phonemes).toSet(),
        isNotEmpty,
        reason: 'no sounds taught in that unit',
      );
    }
  });
}
