import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import 'key_value_store.dart';

/// Production [KeyValueStore] on top of `shared_preferences`.
///
/// SharedPreferences is fine for settings, ids and small learning records.
/// Anything sensitive (session tokens, parent PIN hashes) goes through
/// `SecureVault`, which is backed by EncryptedSharedPreferences / Keychain.
class SharedPreferencesKeyValueStore implements KeyValueStore {
  SharedPreferencesKeyValueStore(this._prefs);

  final SharedPreferences _prefs;
  final _controller = StreamController<String>.broadcast();

  static Future<SharedPreferencesKeyValueStore> create() async {
    final prefs = await SharedPreferences.getInstance();
    return SharedPreferencesKeyValueStore(prefs);
  }

  @override
  Stream<String> get changes => _controller.stream;

  void _emit(String key) => _controller.add(key);

  @override
  String? getString(String key) => _prefs.getString(key);

  @override
  Future<void> setString(String key, String value) async {
    await _prefs.setString(key, value);
    _emit(key);
  }

  @override
  bool getBool(String key, {bool defaultValue = false}) =>
      _prefs.getBool(key) ?? defaultValue;

  @override
  Future<void> setBool(String key, bool value) async {
    await _prefs.setBool(key, value);
    _emit(key);
  }

  @override
  double getDouble(String key, {double defaultValue = 0}) =>
      _prefs.getDouble(key) ?? defaultValue;

  @override
  Future<void> setDouble(String key, double value) async {
    await _prefs.setDouble(key, value);
    _emit(key);
  }

  @override
  int getInt(String key, {int defaultValue = 0}) =>
      _prefs.getInt(key) ?? defaultValue;

  @override
  Future<void> setInt(String key, int value) async {
    await _prefs.setInt(key, value);
    _emit(key);
  }

  @override
  Future<void> remove(String key) async {
    await _prefs.remove(key);
    _emit(key);
  }

  @override
  Future<void> clear() async {
    await _prefs.clear();
    _emit('*');
  }

  @override
  Set<String> keysStartingWith(String prefix) => _prefs.getKeys()
      .where((k) => k.startsWith(prefix))
      .toSet();

  @override
  Future<void> dispose() => _controller.close();
}
