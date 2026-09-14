import 'dart:async';

import '../security/secure_vault.dart';

/// Volatile secure-store stand-in: data lives only for the process.
///
/// Used by tests, the web preview and mock mode. On device the adapter backed
/// by Android EncryptedSharedPreferences / iOS Keychain replaces it in
/// `bootstrap()` — no other file changes.
class InMemorySecureVault implements SecureVault {
  InMemorySecureVault([Map<String, String>? seed]) : _data = {...?seed};

  final Map<String, String> _data;
  final _controller = StreamController<String>.broadcast();

  Stream<String> get changes => _controller.stream;

  @override
  Future<void> clear() async {
    _data.clear();
    _controller.add('*');
  }

  @override
  Future<void> delete(String key) async {
    _data.remove(key);
    _controller.add(key);
  }

  @override
  Future<String?> read(String key) async => _data[key];

  @override
  Future<void> write(String key, String value) async {
    _data[key] = value;
    _controller.add(key);
  }

  Future<void> dispose() => _controller.close();
}
