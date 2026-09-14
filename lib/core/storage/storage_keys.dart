/// Single place that owns every persisted key, so a migration can be written
/// once and no feature can invent a competing key name.
abstract final class StorageKeys {
  static const schemaVersion = 'phonicsai.schema_version';

  static const onboardingComplete = 'phonicsai.onboarding_complete';
  static const interfaceLocale = 'phonicsai.interface_locale';
  static const activeProfileId = 'phonicsai.active_profile';
  static const parentGatePin = 'phonicsai.parent_gate.pin';
  static const parentGatePinConfigured = 'phonicsai.parent_gate.configured';
  static const parentGateFailedAttempts = 'phonicsai.parent_gate.failures';

  /// Namespaced buckets (one row per record id).
  static const profiles = 'phonicsai.profiles';
  static const lessonProgress = 'phonicsai.lesson_progress';
  static const phonemeMastery = 'phonicsai.phoneme_mastery';
  static const sessionLog = 'phonicsai.session_log';
  static const attempts = 'phonicsai.attempts';
  static const achievements = 'phonicsai.achievements';
  static const reviewQueue = 'phonicsai.review_queue';
  static const missions = 'phonicsai.missions';
  static const tutorThreads = 'phonicsai.tutor_threads';
  static const wallet = 'phonicsai.star_wallet';
  static const pendingSync = 'phonicsai.pending_sync';
}
