import 'package:flutter_test/flutter_test.dart';
import 'package:phonicsai/core/storage/collection_store.dart';
import 'package:phonicsai/core/storage/key_value_store.dart';

void main() {
  CollectionStore<_Note> build(InMemoryKeyValueStore store) =>
      CollectionStore<_Note>(
        store: store,
        namespace: 'test.notes',
        fromJson: (json) => _Note(
          id: json['id'] as String,
          text: json['text'] as String,
          score: (json['score'] as num).toInt(),
        ),
        toJson: (note) => {'id': note.id, 'text': note.text, 'score': note.score},
      );

  test('put + byId round-trips through the key value store', () async {
    final store = InMemoryKeyValueStore();
    final collection = build(store);
    await collection.load();

    await collection.put('a', _Note(id: 'a', text: 'sun', score: 3));
    expect(collection.byId('a')?.text, 'sun');

    // A fresh store instance over the same backing data must see the record.
    final reopened = build(store);
    await reopened.load();
    expect(reopened.byId('a')?.score, 3);
  });

  test('corrupt rows are dropped instead of throwing', () async {
    final store = InMemoryKeyValueStore({'test.notes.bad': 'not json'});
    final collection = build(store);
    await collection.load();
    await collection.put('ok', _Note(id: 'ok', text: 'moon', score: 1));
    expect(collection.all.length, 1);
    expect(store.getString('test.notes.bad'), isNull);
  });

  test('update is a no-op for unknown ids and notifies listeners', () async {
    final store = InMemoryKeyValueStore();
    final collection = build(store);
    await collection.load();
    var notifications = 0;
    collection.changes.listen((_) => notifications++);

    await collection.update('missing', (n) => n.copyWith(score: 9));
    expect(notifications, 0);

    await collection.put('b', _Note(id: 'b', text: 'fox', score: 1));
    await collection.update('b', (n) => n.copyWith(score: 7));
    await Future<void>.delayed(Duration.zero);
    expect(collection.byId('b')?.score, 7);
    expect(notifications, greaterThanOrEqualTo(2));
  });

  test('clear removes every namespaced key only', () async {
    final store = InMemoryKeyValueStore({
      'test.notes.x': '{"id":"x","text":"a","score":1}',
      'other.key': 'keep me',
    });
    final collection = build(store);
    await collection.load();
    expect(collection.all.length, 1);
    await collection.clear();
    expect(collection.all, isEmpty);
    expect(store.getString('other.key'), 'keep me');
  });

  test('sorted uses the comparator, not insertion order', () async {
    final store = InMemoryKeyValueStore();
    final collection = build(store);
    await collection.load();
    await collection.putAll(
      [
        _Note(id: '1', text: 'c', score: 2),
        _Note(id: '2', text: 'a', score: 9),
        _Note(id: '3', text: 'b', score: 5),
      ],
      (n) => n.id,
    );
    final byScore = collection.sorted((a, b) => a.score.compareTo(b.score));
    expect(byScore.map((n) => n.score).toList(), [2, 5, 9]);
  });
}

class _Note {
  const _Note({required this.id, required this.text, required this.score});
  final String id;
  final String text;
  final int score;

  _Note copyWith({int? score}) =>
      _Note(id: id, text: text, score: score ?? this.score);
}
