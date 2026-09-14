import 'dart:async';
import 'dart:convert';

/// Small key-value abstraction so feature code never imports a plugin.
///
/// Implementations: [SharedPreferencesKeyValueStore] (persisted) and
/// [InMemoryKeyValueStore] (tests, previews).
abstract interface class KeyValueStore {
  String? getString(String key);
  Future<void> setString(String key, String value);
  bool getBool(String key, {bool defaultValue = false});
  Future<void> setBool(String key, bool value);
  double getDouble(String key, {double defaultValue = 0});
  Future<void> setDouble(String key, double value);
  int getInt(String key, {int defaultValue = 0});
  Future<void> setInt(String key, int value);
  Future<void> remove(String key);
  Future<void> clear();
  Set<String> keysStartingWith(String prefix);

  /// Fires whenever any key changes; used by repositories to stay in sync.
  Stream<String> get changes;

  Future<void> dispose();
}

extension KeyValueStoreJson on KeyValueStore {
  T? getJson<T>(String key, T Function(Map<String, dynamic> json) fromJson) {
    final raw = getString(key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return fromJson(decoded);
    } on FormatException {
      return null;
    }
    return null;
  }

  Future<void> setJson(String key, Object? value) =>
      setString(key, jsonEncode(value));
}

class InMemoryKeyValueStore implements KeyValueStore {
  InMemoryKeyValueStore([Map<String, Object?>? seed])
    : _data = {...?seed};

  final Map<String, Object?> _data;
  final _controller = StreamController<String>.broadcast();

  @override
  Stream<String> get changes => _controller.stream;

  void _emit(String key) => _controller.add(key);

  @override
  String? getString(String key) {
    final value = _data[key];
    return value is String ? value : null;
  }

  @override
  Future<void> setString(String key, String value) =>
      _write(key, value);

  @override
  bool getBool(String key, {bool defaultValue = false}) {
    final value = _data[key];
    return value is bool ? value : defaultValue;
  }

  @override
  Future<void> setBool(String key, bool value) => _write(key, value);

  @override
  double getDouble(String key, {double defaultValue = 0}) {
    final value = _data[key];
    return value is double ? value : defaultValue;
  }

  @override
  Future<void> setDouble(String key, double value) => _write(key, value);

  @override
  int getInt(String key, {int defaultValue = 0}) {
    final value = _data[key];
    return value is int ? value : defaultValue;
  }

  @override
  Future<void> setInt(String key, int value) => _write(key, value);

  @override
  Future<void> remove(String key) => _write(key, null);

  @override
  Future<void> clear() async {
    _data.clear();
    _emit('*');
  }

  @override
  Set<String> keysStartingWith(String prefix) => _data.keys
      .where((k) => k.startsWith(prefix) && _data[k] != null)
      .toSet();

  Future<void> _write(String key, Object? value) async {
    if (value == null) {
      _data.remove(key);
    } else {
      _data[key] = value;
    }
    _emit(key);
  }

  @override
  Future<void> dispose() => _controller.close();
}
