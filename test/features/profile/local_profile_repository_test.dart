import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:phonicsai/core/domain/reading_level.dart';
import 'package:phonicsai/core/storage/key_value_store.dart';
import 'package:phonicsai/features/profile/data/local_profile_repository.dart';
import 'package:phonicsai/features/profile/domain/profile_repository.dart';

void main() {
  late InMemoryKeyValueStore store;
  late LocalProfileRepository repository;

  setUp(() {
    store = InMemoryKeyValueStore();
    repository = LocalProfileRepository(store: store);
  });

  tearDown(() async {
    await repository.dispose();
    await store.dispose();
  });

  Future<void> open() => repository.warmUp();

  test('create persists a readable profile', () async {
    await open();
    final result = await repository.create(
      displayName: ' Aarav ',
      ageMonths: 60,
      avatarId: 'fox',
      level: ReadingLevelSeed.takeTest,
    );

    expect(result.isOk, isTrue);
    final profile = result.requireValue;
    expect(profile.displayName, 'Aarav', reason: 'names are trimmed');
    expect(profile.level, ReadingLevel.letterSounds);
    expect(profile.isAssessmentComplete, isFalse,
        reason: 'a learner who will take the test is not assessed yet');

    // Same backing store, new repository => the data really is persisted.
    final reopened = LocalProfileRepository(store: store);
    await reopened.warmUp();
    expect(reopened.findById(profile.id)?.avatarId, 'fox');
    await reopened.dispose();
  });

  test('manual level marks the learner as assessed', () async {
    await open();
    final result = await repository.create(
      displayName: 'Meera',
      ageMonths: 80,
      avatarId: 'owl',
      level: ReadingLevelSeed.manual,
    );
    expect(result.requireValue.isAssessmentComplete, isTrue);
  });

  test('a blank name is a validation failure, not an exception', () async {
    await open();
    final result = await repository.create(
      displayName: '   ',
      ageMonths: 60,
      avatarId: 'fox',
      level: ReadingLevelSeed.takeTest,
    );
    expect(result.isFailure, isTrue);
    expect(result.failureOrNull!.message, contains('name'));
    expect(repository.readAllSync(), isEmpty);
  });

  test('age is clamped to the supported range', () async {
    await open();
    final young = await repository.create(
      displayName: 'Tiny',
      ageMonths: 12,
      avatarId: 'bee',
      level: ReadingLevelSeed.takeTest,
    );
    expect(young.requireValue.ageMonths, 24);
  });

  test('addStars accumulates; unknown profile fails cleanly', () async {
    await open();
    final created = await repository.create(
      displayName: 'Rhea',
      ageMonths: 66,
      avatarId: 'cat',
      level: ReadingLevelSeed.manual,
    );
    final id = created.requireValue.id;

    await repository.addStars(profileId: id, amount: 5);
    await repository.addStars(profileId: id, amount: 3);
    expect(repository.findById(id)!.starsBalance, 8);

    expect((await repository.addStars(profileId: 'nope', amount: 1)).isFailure,
        isTrue);
  });

  test('delete removes only that learner', () async {
    await open();
    final a = await repository.create(
      displayName: 'A',
      ageMonths: 60,
      avatarId: 'fox',
      level: ReadingLevelSeed.manual,
    );
    final b = await repository.create(
      displayName: 'B',
      ageMonths: 72,
      avatarId: 'owl',
      level: ReadingLevelSeed.manual,
    );

    expect((await repository.delete(a.requireValue.id)).isOk, isTrue);
    expect(repository.readAllSync().map((p) => p.id), [b.requireValue.id]);
    expect((await repository.delete(a.requireValue.id)).isFailure, isTrue);
  });

  test('watchAll emits the current list, then re-emits on every write',
      () async {
    await open();
    final emissions = <int>[];
    final subscription =
        repository.watchAll().listen((list) => emissions.add(list.length));

    // Let the initial snapshot land before mutating, so the sequence is
    // deterministic instead of racing the stream's first event.
    await Future<void>.delayed(Duration.zero);
    expect(emissions, [0]);

    await repository.create(
      displayName: 'New',
      ageMonths: 60,
      avatarId: 'fox',
      level: ReadingLevelSeed.manual,
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await subscription.cancel();
    expect(emissions.last, 1, reason: 'a write must push a new list');
  });

  test('a corrupt record is ignored rather than crashing the list', () async {
    await store.setString('phonicsai.profiles.oops', 'not-json');
    await repository.warmUp();
    expect(repository.readAllSync(), isEmpty);
    expect(jsonDecode('{"ok":true}'), isNotNull);
  });
}
