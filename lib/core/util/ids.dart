import 'dart:math';

/// Dependency-free id generator (keeps a uuid package off the hot path and out
/// of the app size budget). Ids only need to be locally unique + sortable.
abstract final class Ids {
  static final _rng = Random.secure();
  static const _alphabet =
      'abcdefghijklmnopqrstuvwxyz0123456789';

  static String short([int length = 12]) {
    final buffer = StringBuffer();
    for (var i = 0; i < length; i++) {
      buffer.write(_alphabet[_rng.nextInt(_alphabet.length)]);
    }
    return buffer.toString();
  }

  static String namespaced(String prefix) =>
      '${prefix}_${DateTime.now().microsecondsSinceEpoch}_${short(6)}';
}
