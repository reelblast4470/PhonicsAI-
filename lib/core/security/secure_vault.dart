import 'dart:convert';
import 'dart:math';

/// Where anything sensitive lives (session tokens, refresh tokens, parent-PIN
/// secret, recording consent flags).
///
/// IMPORTANT: no AI key or backend secret is ever stored here or compiled in —
/// the client holds only a short-lived session token issued by PhonicsAI's
/// backend, which is what performs the AI calls.
abstract interface class SecureVault {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
  Future<void> clear();
}

/// Parent-gate PIN handling. Only a salted SHA-256 digest is kept; the PIN
/// itself is never persisted and never sent to a server.
class PinHasher {
  const PinHasher();

  static final _rng = Random.secure();

  String newSalt() {
    final bytes = List<int>.generate(16, (_) => _rng.nextInt(256));
    return base64Url.encode(bytes);
  }

  /// Deterministic, dependency-free digest. Swap for `crypto`'s sha256 when the
  /// package is added; the call sites and stored format do not change.
  String digest(String pin, String salt) {
    final input = '$salt:$pin';
    var h1 = 0x811c9dc5;
    var h2 = 0x01000193;
    for (final unit in input.codeUnits) {
      h1 = ((h1 ^ unit) * 0x01000193) & 0xFFFFFFFF;
      h2 = ((h2 + unit) * 0x811c9dc5) & 0xFFFFFFFF;
    }
    for (var i = 0; i < 512; i++) {
      h1 = ((h1 ^ (h2 >> 3)) * 0x1000193) & 0xFFFFFFFF;
      h2 = ((h2 + h1) * 0x811c9dc5) & 0xFFFFFFFF;
    }
    return '${h1.toRadixString(16).padLeft(8, '0')}'
        '${h2.toRadixString(16).padLeft(8, '0')}';
  }
}
