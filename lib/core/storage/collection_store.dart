import 'dart:async';
import 'dart:convert';

import 'key_value_store.dart';

/// Offline-first store for lists of records (lesson progress, attempts,
/// achievements…). Records are addressed by id inside one namespaced bucket.
///
/// Deliberately tiny and synchronous after a one-time load, so lesson/game
/// screens never await I/O while a child is tapping. When a real database
/// (drift/sqflite) or the backend arrives, only this class is replaced —
/// repositories keep the same contract.
class CollectionStore<T> {
  CollectionStore({
    required this.store,
    required this.namespace,
    required this.fromJson,
    required this.toJson,
  });

  final KeyValueStore store;
  final String namespace;
  final T Function(Map<String, dynamic> json) fromJson;
  final Map<String, dynamic> Function(T value) toJson;

  final Map<String, Map<String, dynamic>> _records = {};
  final StreamController<void> _controller = StreamController<void>.broadcast();
  bool _loaded = false;

  Stream<void> get changes => _controller.stream;
  bool get isLoaded => _loaded;

  Future<void> load() async {
    if (_loaded) return;
    _records.clear();
    final prefix = '$namespace.';
    for (final key in store.keysStartingWith(prefix)) {
      final raw = store.getString(key);
      if (raw == null || raw.isEmpty) continue;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          _records[key.substring(prefix.length)] = decoded;
        }
      } on FormatException {
        // A corrupt row must not brick a whole profile: drop and move on.
        await store.remove(key);
      }
    }
    _loaded = true;
  }

  List<T> get all =>
      _records.values.map(fromJson).toList(growable: false);

  List<T> sorted(int Function(T a, T b) compare) {
    final list = all;
    list.sort(compare);
    return list;
  }

  Iterable<T> where(bool Function(T value) test) => all.where(test);

  int countWhere(bool Function(T value) test) => all.where(test).length;

  T? byId(String id) {
    final raw = _records[id];
    return raw == null ? null : fromJson(raw);
  }

  Future<void> put(String id, T value) => putAll([value], (_) => id);

  Future<void> putAll(Iterable<T> values, String Function(T value) idOf) async {
    for (final value in values) {
      final id = idOf(value);
      final encoded = toJson(value);
      _records[id] = encoded;
      await store.setString('$namespace.$id', jsonEncode(encoded));
    }
    _notify();
  }

  /// Read-modify-write of one record; a no-op when the id is unknown.
  Future<void> update(String id, T Function(T current) transform) async {
    final existing = byId(id);
    if (existing == null) return;
    await put(id, transform(existing));
  }

  Future<void> remove(String id) async {
    _records.remove(id);
    await store.remove('$namespace.$id');
    _notify();
  }

  Future<void> clear() async {
    _records.clear();
    for (final key in store.keysStartingWith('$namespace.').toList()) {
      await store.remove(key);
    }
    _notify();
  }

  void _notify() {
    if (!_controller.isClosed) _controller.add(null);
  }

  Future<void> dispose() async {
    _loaded = false;
    await _controller.close();
  }
}
