import 'dart:async';

/// Daily-practice reminders. The Flutter side only *requests* and *cancels*;
/// scheduling lives in the platform (Android AlarmManager/exact permission,
/// iOS UNNotification, Windows toast) behind one adapter.
abstract interface class ReminderScheduler {
  Future<bool> requestPermissions();
  Future<void> scheduleDaily({
    required String id,
    required TimeOfDay24 at,
    required String title,
    required String body,
  });
  Future<void> cancel(String id);
  Future<void> cancelAll();
}

class TimeOfDay24 {
  const TimeOfDay24(this.hour, this.minute);
  static const defaultReminder = TimeOfDay24(17, 30);

  final int hour;
  final int minute;

  bool get isValid => hour >= 0 && hour < 24 && minute >= 0 && minute < 60;

  String get label {
    final suffix = hour < 12 ? 'AM' : 'PM';
    final h = hour % 12 == 0 ? 12 : hour % 12;
    return '$h:${minute.toString().padLeft(2, '0')} $suffix';
  }

  @override
  String toString() => label;
}

/// Adapter used before flutter_local_notifications is linked (and on desktop,
/// where the app keeps reminders in-app instead).
class InAppReminderScheduler implements ReminderScheduler {
  const InAppReminderScheduler();

  @override
  Future<bool> requestPermissions() async => false;

  @override
  Future<void> cancel(String id) async {}

  @override
  Future<void> cancelAll() async {}

  @override
  Future<void> scheduleDaily({
    required String id,
    required TimeOfDay24 at,
    required String title,
    required String body,
  }) async {}
}
