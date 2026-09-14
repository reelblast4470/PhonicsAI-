import 'dart:async';

/// Product analytics seam. The app calls semantic events only
/// (`lessonCompleted`, not "POST /events"), so Firebase/Mixpanel/Amplitude can
/// be dropped in without touching features. No PII leaves this contract —
/// events carry ids and scores, never names or audio.
abstract interface class AnalyticsService {
  void logEvent(String name, [Map<String, Object?> parameters = const {}]);
  void setUser(String? id, {Map<String, Object?> attributes = const {}});
  void screenView(String routeName);
  Future<void> flush();
}

/// Default implementation in every flavor that has no analytics SDK linked.
class LoggingAnalyticsService implements AnalyticsService {
  LoggingAnalyticsService({this.enabled = true, void Function(String)? sink})
    : _sink = sink ?? _debugPrint;

  final bool enabled;
  final void Function(String) _sink;
  final _pending = <String>[];
  String? _userId;

  @override
  void logEvent(String name, [Map<String, Object?> parameters = const {}]) {
    if (!enabled) return;
    final rendered = parameters.isEmpty
        ? name
        : '$name ${parameters.entries.map((e) => '${e.key}=${e.value}').join(' ')}';
    if (_pending.length < 200) _pending.add(rendered);
    _sink('analytics: $_userId $rendered');
  }

  @override
  void setUser(String? id, {Map<String, Object?> attributes = const {}}) {
    _userId = id;
  }

  @override
  void screenView(String routeName) => logEvent('screen_view', {'route': routeName});

  @override
  Future<void> flush() async {
    _pending.clear();
  }

  static void _debugPrint(String message) {
    assert(() {
      // ignore: avoid_print
      print(message);
      return true;
    }());
  }
}
