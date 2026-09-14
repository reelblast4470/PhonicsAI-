// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'PhonicsAI';

  @override
  String get appTagline => 'Your reading buddy';

  @override
  String get navHome => 'Home';

  @override
  String get navLearn => 'Learn';

  @override
  String get navGames => 'Games';

  @override
  String get navTutor => 'Tutor';

  @override
  String get navProgress => 'Progress';

  @override
  String get navParent => 'Grown-ups';

  @override
  String get actionContinue => 'Continue';

  @override
  String get actionStart => 'Start';

  @override
  String get actionNext => 'Next';

  @override
  String get actionBack => 'Back';

  @override
  String get actionDone => 'Done';

  @override
  String get actionSkip => 'Skip';

  @override
  String get actionPlay => 'Play';

  @override
  String get actionListen => 'Listen';

  @override
  String get actionSayIt => 'Say it';

  @override
  String get actionTryAgain => 'Try again';

  @override
  String get actionRetry => 'Retry';

  @override
  String get actionClose => 'Close';

  @override
  String get actionSave => 'Save';

  @override
  String get actionCancel => 'Cancel';

  @override
  String get actionEdit => 'Edit';

  @override
  String get actionAdd => 'Add';

  @override
  String get actionDelete => 'Delete';

  @override
  String get actionFinish => 'Finish';

  @override
  String get actionUnlock => 'Unlock';

  @override
  String get actionRestore => 'Restore purchases';

  @override
  String get actionSignUp => 'Create account';

  @override
  String get actionSignIn => 'Sign in';

  @override
  String get actionSignOut => 'Sign out';

  @override
  String get actionGetStarted => 'Get started';

  @override
  String get actionLater => 'Maybe later';

  @override
  String get actionOK => 'OK';

  @override
  String get actionCheck => 'Check';

  @override
  String get actionHint => 'Hint';

  @override
  String get actionFreePlay => 'Free play';

  @override
  String get stateLoading => 'Getting things ready…';

  @override
  String get stateEmptyGeneric => 'Nothing here yet.';

  @override
  String get stateOffline => 'Offline — work saved on this device';

  @override
  String get stateErrorGeneric =>
      'That did not work. Check the connection and try again.';

  @override
  String get profileAdd => 'Add a learner';

  @override
  String get profileSwitch => 'Switch learner';

  @override
  String get profileWhosLearning => 'Who is learning?';

  @override
  String get profileName => 'First name';

  @override
  String get profileAge => 'Age';

  @override
  String profileAgeYears(int years) {
    return '$years years';
  }

  @override
  String get profileCreateTitle => 'New learner';

  @override
  String get profileNameHint => 'e.g. Aarav';

  @override
  String get profileNameError => 'Please type a name.';

  @override
  String get profileLevel => 'Reading level';

  @override
  String get profileAvatar => 'Pick a buddy';

  @override
  String profileDeleteConfirm(String name) {
    return 'Remove $name\'s profile from this device?';
  }

  @override
  String get profileDeleted => 'Profile removed';

  @override
  String get languageTitle => 'Which language helps you learn best?';

  @override
  String get languageSubtitle =>
      'The tutor gives instructions in this language. Sounds are always English.';

  @override
  String get languageInterface => 'App language';

  @override
  String get languageHome => 'Language at home';

  @override
  String get assessmentTitle => 'Quick check-up';

  @override
  String get assessmentSubtitle =>
      'Five friendly cards. No pressure — just listening.';

  @override
  String assessmentQuestionOf(int index, int total) {
    return 'Card $index of $total';
  }

  @override
  String assessmentResult(String level) {
    return 'Starting level: $level';
  }

  @override
  String get assessmentSkip => 'Skip the check-up';

  @override
  String homeGreeting(String name) {
    return 'Hi $name!';
  }

  @override
  String homeStreak(int days) {
    return '$days-day streak';
  }

  @override
  String get homeDailyMission => 'Today\'s mission';

  @override
  String get homeContinue => 'Pick up where you left off';

  @override
  String homeStars(int count) {
    return '$count stars';
  }

  @override
  String homeLevelBadge(String level) {
    return 'Level $level';
  }

  @override
  String homeMinutesGoal(int minutes) {
    return '$minutes min goal';
  }

  @override
  String get homeAllDone => 'Mission complete! Come back tomorrow.';

  @override
  String get learnTitle => 'Phonics journey';

  @override
  String learnUnitProgress(int done, int total) {
    return '$done of $total lessons';
  }

  @override
  String get learnLocked => 'Finish the previous level to unlock';

  @override
  String get learnStageDiscover => 'Discover';

  @override
  String get learnStageHear => 'Hear';

  @override
  String get learnStageSee => 'See';

  @override
  String get learnStageUnderstand => 'Understand';

  @override
  String get learnStagePractice => 'Practice';

  @override
  String get learnStagePlay => 'Play';

  @override
  String get learnStageRecall => 'Recall';

  @override
  String get learnStageSpeak => 'Speak';

  @override
  String get learnStageRead => 'Read';

  @override
  String get learnStageReview => 'Review';

  @override
  String get learnLessonComplete => 'Lesson complete!';

  @override
  String learnXpEarned(int xp) {
    return '+$xp stars';
  }

  @override
  String get gamesTitle => 'Play & practice';

  @override
  String gamesHighScore(int score) {
    return 'Best: $score';
  }

  @override
  String get gamesPickOne => 'Choose a game';

  @override
  String get gamesRoundOver => 'Round over';

  @override
  String get gamesScore => 'Score';

  @override
  String gamesStarsEarned(int count) {
    return '$count stars earned';
  }

  @override
  String get gamesPlayAgain => 'Play again';

  @override
  String get tutorTitle => 'Aria, your tutor';

  @override
  String get tutorHint => 'Ask me anything about sounds and words!';

  @override
  String get tutorInputPlaceholder => 'Type or tap the mic';

  @override
  String get tutorListening => 'Listening…';

  @override
  String get tutorThinking => 'Aria is thinking…';

  @override
  String get tutorVoiceOnly => 'Tap a word to hear it';

  @override
  String get tutorMicDenied =>
      'I need the microphone to hear you. You can type instead.';

  @override
  String get tutorSuggestionWords => 's / sh';

  @override
  String get tutorSuggestionRead => 'Help me read this';

  @override
  String get tutorSuggestionStuck => 'I\'m stuck on a word';

  @override
  String get tutorSafetyNote => 'Aria only helps with reading and writing.';

  @override
  String get pronunciationTitle => 'Say it out loud';

  @override
  String get pronunciationTapMic => 'Tap the mic when you are ready';

  @override
  String get pronunciationHeard => 'I heard';

  @override
  String pronunciationScore(int score) {
    return '$score% match';
  }

  @override
  String get pronunciationTip => 'Tip';

  @override
  String get pronunciationNoSpeech => 'I did not hear anything. Try again!';

  @override
  String get pronunciationMicNeeded => 'Microphone not available';

  @override
  String get readingTitle => 'Reading practice';

  @override
  String get readingPassages => 'Decodable books';

  @override
  String get readingStarted => 'Started reading';

  @override
  String readingWpm(int wpm) {
    return '$wpm words/min';
  }

  @override
  String readingAccuracy(int percent) {
    return '$percent% accurate';
  }

  @override
  String readingSelfCorrect(int count) {
    return '$count self-corrections';
  }

  @override
  String get readingFinished => 'Nice reading!';

  @override
  String get writingTitle => 'Write it';

  @override
  String get writingTrace => 'Trace the letter';

  @override
  String get writingErase => 'Erase';

  @override
  String get writingSpelling => 'Build the word';

  @override
  String get writingCorrect => 'Perfect!';

  @override
  String get writingNearMiss => 'Almost — check that sound';

  @override
  String get writingStrokesSaved => 'Saved to your writing book';

  @override
  String get progressTitle => 'My progress';

  @override
  String get progressThisWeek => 'This week';

  @override
  String progressMinutes(int minutes) {
    return '$minutes minutes';
  }

  @override
  String progressLessons(int count) {
    return '$count lessons';
  }

  @override
  String progressAccuracy(int percent) {
    return '$percent% accurate';
  }

  @override
  String get progressMastery => 'Sound mastery';

  @override
  String get progressMastered => 'Mastered';

  @override
  String get progressLearning => 'Learning';

  @override
  String get progressNotStarted => 'Not started';

  @override
  String progressDueForReview(int count) {
    return '$count to review today';
  }

  @override
  String get progressEmpty => 'Finish a lesson to start your chart!';

  @override
  String get rewardsTitle => 'Badges & stars';

  @override
  String get rewardsUnlocked => 'Unlocked!';

  @override
  String get rewardsLocked => 'Keep going to unlock';

  @override
  String rewardsProgress(int done, int target) {
    return '$done/$target';
  }

  @override
  String get parentTitle => 'Grown-up area';

  @override
  String get parentGateTitle => 'Ask a grown-up';

  @override
  String get parentGateSubtitle => 'Type your 4-digit code to continue.';

  @override
  String get parentGateCreate => 'Create a 4-digit code';

  @override
  String get parentGateConfirm => 'Type it again';

  @override
  String get parentGateWrong => 'That code does not match. Try again.';

  @override
  String parentGateLocked(int seconds) {
    return 'Too many tries. Wait ${seconds}s.';
  }

  @override
  String get parentTimeToday => 'Today';

  @override
  String get parentTimeWeek => 'This week';

  @override
  String get parentStrengths => 'Going well';

  @override
  String get parentNeedsHelp => 'Needs practice';

  @override
  String get parentWeeklyReport => 'Weekly report';

  @override
  String get parentShareReport => 'Share report';

  @override
  String get parentManageSubscription => 'Manage subscription';

  @override
  String get parentContentControls => 'Content controls';

  @override
  String get parentDailyLimit => 'Daily practice limit';

  @override
  String get parentAllowVoice => 'Allow microphone for pronunciation practice';

  @override
  String get parentAllowChat => 'Allow the AI tutor to answer open questions';

  @override
  String get parentDataPrivacy => 'Data & privacy';

  @override
  String get subscriptionTitle => 'PhonicsAI Plus';

  @override
  String get subscriptionHeadline =>
      'More stories, more practice, no ads — ever.';

  @override
  String get subscriptionPerMonth => '/month';

  @override
  String get subscriptionPerYear => '/year';

  @override
  String get subscriptionOneTime => 'one-time';

  @override
  String subscriptionTrial(int days) {
    return '$days-day free trial';
  }

  @override
  String get subscriptionCurrent => 'Current plan';

  @override
  String get subscriptionFree => 'Free';

  @override
  String get subscriptionPlus => 'Plus';

  @override
  String get subscriptionFeatureStories => '1,200+ decodable stories';

  @override
  String get subscriptionFeatureTutor => 'Unlimited AI tutor sessions';

  @override
  String get subscriptionFeatureReports => 'Detailed progress reports';

  @override
  String get subscriptionFeatureOffline => 'Offline lessons';

  @override
  String get subscriptionFeatureAds => 'Zero advertising, always';

  @override
  String get subscriptionBillingNote =>
      'Billed by Google Play / Apple. Manage or cancel in your store account.';

  @override
  String get subscriptionUnavailable => 'Store not available on this device.';

  @override
  String subscriptionActiveMessage(String date) {
    return 'Plus is active until $date.';
  }

  @override
  String get subscriptionRestored => 'Purchases restored';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsLearner => 'Learner';

  @override
  String get settingsAppearance => 'Appearance';

  @override
  String get settingsThemeSystem => 'Follow system';

  @override
  String get settingsThemeLight => 'Light';

  @override
  String get settingsThemeDark => 'Dark';

  @override
  String get settingsTextSize => 'Text size';

  @override
  String get settingsSound => 'Sound effects';

  @override
  String get settingsReminders => 'Practice reminders';

  @override
  String get settingsRemindersTime => 'Reminder time';

  @override
  String get settingsLanguage => 'App language';

  @override
  String get settingsHelp => 'Help & support';

  @override
  String get settingsAbout => 'About PhonicsAI';

  @override
  String get settingsLegal => 'Privacy policy & terms';

  @override
  String get settingsDeleteAccount => 'Delete account & data';

  @override
  String get settingsExportData => 'Export my child\'s data';

  @override
  String get settingsConsent => 'Consent';

  @override
  String get settingsAccount => 'Account';

  @override
  String get settingsSignOutConfirm => 'Sign out of PhonicsAI on this device?';

  @override
  String settingsVersion(String version) {
    return 'Version $version';
  }

  @override
  String get helpTitle => 'Help & support';

  @override
  String get helpSearchHint => 'Search help topics';

  @override
  String get helpFaq => 'Common questions';

  @override
  String get helpContact => 'Contact support';

  @override
  String get helpContactBody => 'support@phonicsai.example.com';

  @override
  String get helpEmpty =>
      'No topic matched. Try \"mic\", \"streak\" or \"refund\".';

  @override
  String get helpSend => 'Send us a message';

  @override
  String get helpSent => 'Thanks! We reply within one school day.';

  @override
  String get helpNoConnection => 'Support form needs a connection.';

  @override
  String get privacyTitle => 'Privacy for little learners';

  @override
  String get privacySummary =>
      'Children\'s data stays on this device unless you turn on sync.';

  @override
  String get privacyRecording =>
      'Audio is transcribed on-device and never stored raw.';

  @override
  String get privacyNoAds =>
      'No advertising, no behavioural analytics, no third-party trackers.';

  @override
  String get privacyExport => 'Export or delete everything any time.';

  @override
  String get privacyCoppa =>
      'Compliant with COPPA / GDPR-K; verifiable parental consent is required for cloud sync.';

  @override
  String get privacyTurnOnSync => 'Turn on cloud sync';

  @override
  String get privacyTurnOffSync => 'Turn off cloud sync';

  @override
  String get privacyDeleted => 'All local data deleted';

  @override
  String get privacyDeleteWarning =>
      'This removes profiles, progress and stars from this device. It cannot be undone.';
}
