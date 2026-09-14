import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_es.dart';
import 'app_localizations_hi.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('es'),
    Locale('hi'),
  ];

  /// No description provided for @appName.
  ///
  /// In en, this message translates to:
  /// **'PhonicsAI'**
  String get appName;

  /// No description provided for @appTagline.
  ///
  /// In en, this message translates to:
  /// **'Your reading buddy'**
  String get appTagline;

  /// No description provided for @navHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get navHome;

  /// No description provided for @navLearn.
  ///
  /// In en, this message translates to:
  /// **'Learn'**
  String get navLearn;

  /// No description provided for @navGames.
  ///
  /// In en, this message translates to:
  /// **'Games'**
  String get navGames;

  /// No description provided for @navTutor.
  ///
  /// In en, this message translates to:
  /// **'Tutor'**
  String get navTutor;

  /// No description provided for @navProgress.
  ///
  /// In en, this message translates to:
  /// **'Progress'**
  String get navProgress;

  /// No description provided for @navParent.
  ///
  /// In en, this message translates to:
  /// **'Grown-ups'**
  String get navParent;

  /// No description provided for @actionContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get actionContinue;

  /// No description provided for @actionStart.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get actionStart;

  /// No description provided for @actionNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get actionNext;

  /// No description provided for @actionBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get actionBack;

  /// No description provided for @actionDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get actionDone;

  /// No description provided for @actionSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get actionSkip;

  /// No description provided for @actionPlay.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get actionPlay;

  /// No description provided for @actionListen.
  ///
  /// In en, this message translates to:
  /// **'Listen'**
  String get actionListen;

  /// No description provided for @actionSayIt.
  ///
  /// In en, this message translates to:
  /// **'Say it'**
  String get actionSayIt;

  /// No description provided for @actionTryAgain.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get actionTryAgain;

  /// No description provided for @actionRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get actionRetry;

  /// No description provided for @actionClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get actionClose;

  /// No description provided for @actionSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get actionSave;

  /// No description provided for @actionCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get actionCancel;

  /// No description provided for @actionEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get actionEdit;

  /// No description provided for @actionAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get actionAdd;

  /// No description provided for @actionDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get actionDelete;

  /// No description provided for @actionFinish.
  ///
  /// In en, this message translates to:
  /// **'Finish'**
  String get actionFinish;

  /// No description provided for @actionUnlock.
  ///
  /// In en, this message translates to:
  /// **'Unlock'**
  String get actionUnlock;

  /// No description provided for @actionRestore.
  ///
  /// In en, this message translates to:
  /// **'Restore purchases'**
  String get actionRestore;

  /// No description provided for @actionSignUp.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get actionSignUp;

  /// No description provided for @actionSignIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get actionSignIn;

  /// No description provided for @actionSignOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get actionSignOut;

  /// No description provided for @actionGetStarted.
  ///
  /// In en, this message translates to:
  /// **'Get started'**
  String get actionGetStarted;

  /// No description provided for @actionLater.
  ///
  /// In en, this message translates to:
  /// **'Maybe later'**
  String get actionLater;

  /// No description provided for @actionOK.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get actionOK;

  /// No description provided for @actionCheck.
  ///
  /// In en, this message translates to:
  /// **'Check'**
  String get actionCheck;

  /// No description provided for @actionHint.
  ///
  /// In en, this message translates to:
  /// **'Hint'**
  String get actionHint;

  /// No description provided for @actionFreePlay.
  ///
  /// In en, this message translates to:
  /// **'Free play'**
  String get actionFreePlay;

  /// No description provided for @stateLoading.
  ///
  /// In en, this message translates to:
  /// **'Getting things ready…'**
  String get stateLoading;

  /// No description provided for @stateEmptyGeneric.
  ///
  /// In en, this message translates to:
  /// **'Nothing here yet.'**
  String get stateEmptyGeneric;

  /// No description provided for @stateOffline.
  ///
  /// In en, this message translates to:
  /// **'Offline — work saved on this device'**
  String get stateOffline;

  /// No description provided for @stateErrorGeneric.
  ///
  /// In en, this message translates to:
  /// **'That did not work. Check the connection and try again.'**
  String get stateErrorGeneric;

  /// No description provided for @profileAdd.
  ///
  /// In en, this message translates to:
  /// **'Add a learner'**
  String get profileAdd;

  /// No description provided for @profileSwitch.
  ///
  /// In en, this message translates to:
  /// **'Switch learner'**
  String get profileSwitch;

  /// No description provided for @profileWhosLearning.
  ///
  /// In en, this message translates to:
  /// **'Who is learning?'**
  String get profileWhosLearning;

  /// No description provided for @profileName.
  ///
  /// In en, this message translates to:
  /// **'First name'**
  String get profileName;

  /// No description provided for @profileAge.
  ///
  /// In en, this message translates to:
  /// **'Age'**
  String get profileAge;

  /// No description provided for @profileAgeYears.
  ///
  /// In en, this message translates to:
  /// **'{years} years'**
  String profileAgeYears(int years);

  /// No description provided for @profileCreateTitle.
  ///
  /// In en, this message translates to:
  /// **'New learner'**
  String get profileCreateTitle;

  /// No description provided for @profileNameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Aarav'**
  String get profileNameHint;

  /// No description provided for @profileNameError.
  ///
  /// In en, this message translates to:
  /// **'Please type a name.'**
  String get profileNameError;

  /// No description provided for @profileLevel.
  ///
  /// In en, this message translates to:
  /// **'Reading level'**
  String get profileLevel;

  /// No description provided for @profileAvatar.
  ///
  /// In en, this message translates to:
  /// **'Pick a buddy'**
  String get profileAvatar;

  /// No description provided for @profileDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Remove {name}\'s profile from this device?'**
  String profileDeleteConfirm(String name);

  /// No description provided for @profileDeleted.
  ///
  /// In en, this message translates to:
  /// **'Profile removed'**
  String get profileDeleted;

  /// No description provided for @languageTitle.
  ///
  /// In en, this message translates to:
  /// **'Which language helps you learn best?'**
  String get languageTitle;

  /// No description provided for @languageSubtitle.
  ///
  /// In en, this message translates to:
  /// **'The tutor gives instructions in this language. Sounds are always English.'**
  String get languageSubtitle;

  /// No description provided for @languageInterface.
  ///
  /// In en, this message translates to:
  /// **'App language'**
  String get languageInterface;

  /// No description provided for @languageHome.
  ///
  /// In en, this message translates to:
  /// **'Language at home'**
  String get languageHome;

  /// No description provided for @assessmentTitle.
  ///
  /// In en, this message translates to:
  /// **'Quick check-up'**
  String get assessmentTitle;

  /// No description provided for @assessmentSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Five friendly cards. No pressure — just listening.'**
  String get assessmentSubtitle;

  /// No description provided for @assessmentQuestionOf.
  ///
  /// In en, this message translates to:
  /// **'Card {index} of {total}'**
  String assessmentQuestionOf(int index, int total);

  /// No description provided for @assessmentResult.
  ///
  /// In en, this message translates to:
  /// **'Starting level: {level}'**
  String assessmentResult(String level);

  /// No description provided for @assessmentSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip the check-up'**
  String get assessmentSkip;

  /// No description provided for @homeGreeting.
  ///
  /// In en, this message translates to:
  /// **'Hi {name}!'**
  String homeGreeting(String name);

  /// No description provided for @homeStreak.
  ///
  /// In en, this message translates to:
  /// **'{days}-day streak'**
  String homeStreak(int days);

  /// No description provided for @homeDailyMission.
  ///
  /// In en, this message translates to:
  /// **'Today\'s mission'**
  String get homeDailyMission;

  /// No description provided for @homeContinue.
  ///
  /// In en, this message translates to:
  /// **'Pick up where you left off'**
  String get homeContinue;

  /// No description provided for @homeStars.
  ///
  /// In en, this message translates to:
  /// **'{count} stars'**
  String homeStars(int count);

  /// No description provided for @homeLevelBadge.
  ///
  /// In en, this message translates to:
  /// **'Level {level}'**
  String homeLevelBadge(String level);

  /// No description provided for @homeMinutesGoal.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min goal'**
  String homeMinutesGoal(int minutes);

  /// No description provided for @homeAllDone.
  ///
  /// In en, this message translates to:
  /// **'Mission complete! Come back tomorrow.'**
  String get homeAllDone;

  /// No description provided for @learnTitle.
  ///
  /// In en, this message translates to:
  /// **'Phonics journey'**
  String get learnTitle;

  /// No description provided for @learnUnitProgress.
  ///
  /// In en, this message translates to:
  /// **'{done} of {total} lessons'**
  String learnUnitProgress(int done, int total);

  /// No description provided for @learnLocked.
  ///
  /// In en, this message translates to:
  /// **'Finish the previous level to unlock'**
  String get learnLocked;

  /// No description provided for @learnStageDiscover.
  ///
  /// In en, this message translates to:
  /// **'Discover'**
  String get learnStageDiscover;

  /// No description provided for @learnStageHear.
  ///
  /// In en, this message translates to:
  /// **'Hear'**
  String get learnStageHear;

  /// No description provided for @learnStageSee.
  ///
  /// In en, this message translates to:
  /// **'See'**
  String get learnStageSee;

  /// No description provided for @learnStageUnderstand.
  ///
  /// In en, this message translates to:
  /// **'Understand'**
  String get learnStageUnderstand;

  /// No description provided for @learnStagePractice.
  ///
  /// In en, this message translates to:
  /// **'Practice'**
  String get learnStagePractice;

  /// No description provided for @learnStagePlay.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get learnStagePlay;

  /// No description provided for @learnStageRecall.
  ///
  /// In en, this message translates to:
  /// **'Recall'**
  String get learnStageRecall;

  /// No description provided for @learnStageSpeak.
  ///
  /// In en, this message translates to:
  /// **'Speak'**
  String get learnStageSpeak;

  /// No description provided for @learnStageRead.
  ///
  /// In en, this message translates to:
  /// **'Read'**
  String get learnStageRead;

  /// No description provided for @learnStageReview.
  ///
  /// In en, this message translates to:
  /// **'Review'**
  String get learnStageReview;

  /// No description provided for @learnLessonComplete.
  ///
  /// In en, this message translates to:
  /// **'Lesson complete!'**
  String get learnLessonComplete;

  /// No description provided for @learnXpEarned.
  ///
  /// In en, this message translates to:
  /// **'+{xp} stars'**
  String learnXpEarned(int xp);

  /// No description provided for @gamesTitle.
  ///
  /// In en, this message translates to:
  /// **'Play & practice'**
  String get gamesTitle;

  /// No description provided for @gamesHighScore.
  ///
  /// In en, this message translates to:
  /// **'Best: {score}'**
  String gamesHighScore(int score);

  /// No description provided for @gamesPickOne.
  ///
  /// In en, this message translates to:
  /// **'Choose a game'**
  String get gamesPickOne;

  /// No description provided for @gamesRoundOver.
  ///
  /// In en, this message translates to:
  /// **'Round over'**
  String get gamesRoundOver;

  /// No description provided for @gamesScore.
  ///
  /// In en, this message translates to:
  /// **'Score'**
  String get gamesScore;

  /// No description provided for @gamesStarsEarned.
  ///
  /// In en, this message translates to:
  /// **'{count} stars earned'**
  String gamesStarsEarned(int count);

  /// No description provided for @gamesPlayAgain.
  ///
  /// In en, this message translates to:
  /// **'Play again'**
  String get gamesPlayAgain;

  /// No description provided for @tutorTitle.
  ///
  /// In en, this message translates to:
  /// **'Aria, your tutor'**
  String get tutorTitle;

  /// No description provided for @tutorHint.
  ///
  /// In en, this message translates to:
  /// **'Ask me anything about sounds and words!'**
  String get tutorHint;

  /// No description provided for @tutorInputPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Type or tap the mic'**
  String get tutorInputPlaceholder;

  /// No description provided for @tutorListening.
  ///
  /// In en, this message translates to:
  /// **'Listening…'**
  String get tutorListening;

  /// No description provided for @tutorThinking.
  ///
  /// In en, this message translates to:
  /// **'Aria is thinking…'**
  String get tutorThinking;

  /// No description provided for @tutorVoiceOnly.
  ///
  /// In en, this message translates to:
  /// **'Tap a word to hear it'**
  String get tutorVoiceOnly;

  /// No description provided for @tutorMicDenied.
  ///
  /// In en, this message translates to:
  /// **'I need the microphone to hear you. You can type instead.'**
  String get tutorMicDenied;

  /// No description provided for @tutorSuggestionWords.
  ///
  /// In en, this message translates to:
  /// **'s / sh'**
  String get tutorSuggestionWords;

  /// No description provided for @tutorSuggestionRead.
  ///
  /// In en, this message translates to:
  /// **'Help me read this'**
  String get tutorSuggestionRead;

  /// No description provided for @tutorSuggestionStuck.
  ///
  /// In en, this message translates to:
  /// **'I\'m stuck on a word'**
  String get tutorSuggestionStuck;

  /// No description provided for @tutorSafetyNote.
  ///
  /// In en, this message translates to:
  /// **'Aria only helps with reading and writing.'**
  String get tutorSafetyNote;

  /// No description provided for @pronunciationTitle.
  ///
  /// In en, this message translates to:
  /// **'Say it out loud'**
  String get pronunciationTitle;

  /// No description provided for @pronunciationTapMic.
  ///
  /// In en, this message translates to:
  /// **'Tap the mic when you are ready'**
  String get pronunciationTapMic;

  /// No description provided for @pronunciationHeard.
  ///
  /// In en, this message translates to:
  /// **'I heard'**
  String get pronunciationHeard;

  /// No description provided for @pronunciationScore.
  ///
  /// In en, this message translates to:
  /// **'{score}% match'**
  String pronunciationScore(int score);

  /// No description provided for @pronunciationTip.
  ///
  /// In en, this message translates to:
  /// **'Tip'**
  String get pronunciationTip;

  /// No description provided for @pronunciationNoSpeech.
  ///
  /// In en, this message translates to:
  /// **'I did not hear anything. Try again!'**
  String get pronunciationNoSpeech;

  /// No description provided for @pronunciationMicNeeded.
  ///
  /// In en, this message translates to:
  /// **'Microphone not available'**
  String get pronunciationMicNeeded;

  /// No description provided for @readingTitle.
  ///
  /// In en, this message translates to:
  /// **'Reading practice'**
  String get readingTitle;

  /// No description provided for @readingPassages.
  ///
  /// In en, this message translates to:
  /// **'Decodable books'**
  String get readingPassages;

  /// No description provided for @readingStarted.
  ///
  /// In en, this message translates to:
  /// **'Started reading'**
  String get readingStarted;

  /// No description provided for @readingWpm.
  ///
  /// In en, this message translates to:
  /// **'{wpm} words/min'**
  String readingWpm(int wpm);

  /// No description provided for @readingAccuracy.
  ///
  /// In en, this message translates to:
  /// **'{percent}% accurate'**
  String readingAccuracy(int percent);

  /// No description provided for @readingSelfCorrect.
  ///
  /// In en, this message translates to:
  /// **'{count} self-corrections'**
  String readingSelfCorrect(int count);

  /// No description provided for @readingFinished.
  ///
  /// In en, this message translates to:
  /// **'Nice reading!'**
  String get readingFinished;

  /// No description provided for @writingTitle.
  ///
  /// In en, this message translates to:
  /// **'Write it'**
  String get writingTitle;

  /// No description provided for @writingTrace.
  ///
  /// In en, this message translates to:
  /// **'Trace the letter'**
  String get writingTrace;

  /// No description provided for @writingErase.
  ///
  /// In en, this message translates to:
  /// **'Erase'**
  String get writingErase;

  /// No description provided for @writingSpelling.
  ///
  /// In en, this message translates to:
  /// **'Build the word'**
  String get writingSpelling;

  /// No description provided for @writingCorrect.
  ///
  /// In en, this message translates to:
  /// **'Perfect!'**
  String get writingCorrect;

  /// No description provided for @writingNearMiss.
  ///
  /// In en, this message translates to:
  /// **'Almost — check that sound'**
  String get writingNearMiss;

  /// No description provided for @writingStrokesSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved to your writing book'**
  String get writingStrokesSaved;

  /// No description provided for @progressTitle.
  ///
  /// In en, this message translates to:
  /// **'My progress'**
  String get progressTitle;

  /// No description provided for @progressThisWeek.
  ///
  /// In en, this message translates to:
  /// **'This week'**
  String get progressThisWeek;

  /// No description provided for @progressMinutes.
  ///
  /// In en, this message translates to:
  /// **'{minutes} minutes'**
  String progressMinutes(int minutes);

  /// No description provided for @progressLessons.
  ///
  /// In en, this message translates to:
  /// **'{count} lessons'**
  String progressLessons(int count);

  /// No description provided for @progressAccuracy.
  ///
  /// In en, this message translates to:
  /// **'{percent}% accurate'**
  String progressAccuracy(int percent);

  /// No description provided for @progressMastery.
  ///
  /// In en, this message translates to:
  /// **'Sound mastery'**
  String get progressMastery;

  /// No description provided for @progressMastered.
  ///
  /// In en, this message translates to:
  /// **'Mastered'**
  String get progressMastered;

  /// No description provided for @progressLearning.
  ///
  /// In en, this message translates to:
  /// **'Learning'**
  String get progressLearning;

  /// No description provided for @progressNotStarted.
  ///
  /// In en, this message translates to:
  /// **'Not started'**
  String get progressNotStarted;

  /// No description provided for @progressDueForReview.
  ///
  /// In en, this message translates to:
  /// **'{count} to review today'**
  String progressDueForReview(int count);

  /// No description provided for @progressEmpty.
  ///
  /// In en, this message translates to:
  /// **'Finish a lesson to start your chart!'**
  String get progressEmpty;

  /// No description provided for @rewardsTitle.
  ///
  /// In en, this message translates to:
  /// **'Badges & stars'**
  String get rewardsTitle;

  /// No description provided for @rewardsUnlocked.
  ///
  /// In en, this message translates to:
  /// **'Unlocked!'**
  String get rewardsUnlocked;

  /// No description provided for @rewardsLocked.
  ///
  /// In en, this message translates to:
  /// **'Keep going to unlock'**
  String get rewardsLocked;

  /// No description provided for @rewardsProgress.
  ///
  /// In en, this message translates to:
  /// **'{done}/{target}'**
  String rewardsProgress(int done, int target);

  /// No description provided for @parentTitle.
  ///
  /// In en, this message translates to:
  /// **'Grown-up area'**
  String get parentTitle;

  /// No description provided for @parentGateTitle.
  ///
  /// In en, this message translates to:
  /// **'Ask a grown-up'**
  String get parentGateTitle;

  /// No description provided for @parentGateSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Type your 4-digit code to continue.'**
  String get parentGateSubtitle;

  /// No description provided for @parentGateCreate.
  ///
  /// In en, this message translates to:
  /// **'Create a 4-digit code'**
  String get parentGateCreate;

  /// No description provided for @parentGateConfirm.
  ///
  /// In en, this message translates to:
  /// **'Type it again'**
  String get parentGateConfirm;

  /// No description provided for @parentGateWrong.
  ///
  /// In en, this message translates to:
  /// **'That code does not match. Try again.'**
  String get parentGateWrong;

  /// No description provided for @parentGateLocked.
  ///
  /// In en, this message translates to:
  /// **'Too many tries. Wait {seconds}s.'**
  String parentGateLocked(int seconds);

  /// No description provided for @parentTimeToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get parentTimeToday;

  /// No description provided for @parentTimeWeek.
  ///
  /// In en, this message translates to:
  /// **'This week'**
  String get parentTimeWeek;

  /// No description provided for @parentStrengths.
  ///
  /// In en, this message translates to:
  /// **'Going well'**
  String get parentStrengths;

  /// No description provided for @parentNeedsHelp.
  ///
  /// In en, this message translates to:
  /// **'Needs practice'**
  String get parentNeedsHelp;

  /// No description provided for @parentWeeklyReport.
  ///
  /// In en, this message translates to:
  /// **'Weekly report'**
  String get parentWeeklyReport;

  /// No description provided for @parentShareReport.
  ///
  /// In en, this message translates to:
  /// **'Share report'**
  String get parentShareReport;

  /// No description provided for @parentManageSubscription.
  ///
  /// In en, this message translates to:
  /// **'Manage subscription'**
  String get parentManageSubscription;

  /// No description provided for @parentContentControls.
  ///
  /// In en, this message translates to:
  /// **'Content controls'**
  String get parentContentControls;

  /// No description provided for @parentDailyLimit.
  ///
  /// In en, this message translates to:
  /// **'Daily practice limit'**
  String get parentDailyLimit;

  /// No description provided for @parentAllowVoice.
  ///
  /// In en, this message translates to:
  /// **'Allow microphone for pronunciation practice'**
  String get parentAllowVoice;

  /// No description provided for @parentAllowChat.
  ///
  /// In en, this message translates to:
  /// **'Allow the AI tutor to answer open questions'**
  String get parentAllowChat;

  /// No description provided for @parentDataPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Data & privacy'**
  String get parentDataPrivacy;

  /// No description provided for @subscriptionTitle.
  ///
  /// In en, this message translates to:
  /// **'PhonicsAI Plus'**
  String get subscriptionTitle;

  /// No description provided for @subscriptionHeadline.
  ///
  /// In en, this message translates to:
  /// **'More stories, more practice, no ads — ever.'**
  String get subscriptionHeadline;

  /// No description provided for @subscriptionPerMonth.
  ///
  /// In en, this message translates to:
  /// **'/month'**
  String get subscriptionPerMonth;

  /// No description provided for @subscriptionPerYear.
  ///
  /// In en, this message translates to:
  /// **'/year'**
  String get subscriptionPerYear;

  /// No description provided for @subscriptionOneTime.
  ///
  /// In en, this message translates to:
  /// **'one-time'**
  String get subscriptionOneTime;

  /// No description provided for @subscriptionTrial.
  ///
  /// In en, this message translates to:
  /// **'{days}-day free trial'**
  String subscriptionTrial(int days);

  /// No description provided for @subscriptionCurrent.
  ///
  /// In en, this message translates to:
  /// **'Current plan'**
  String get subscriptionCurrent;

  /// No description provided for @subscriptionFree.
  ///
  /// In en, this message translates to:
  /// **'Free'**
  String get subscriptionFree;

  /// No description provided for @subscriptionPlus.
  ///
  /// In en, this message translates to:
  /// **'Plus'**
  String get subscriptionPlus;

  /// No description provided for @subscriptionFeatureStories.
  ///
  /// In en, this message translates to:
  /// **'1,200+ decodable stories'**
  String get subscriptionFeatureStories;

  /// No description provided for @subscriptionFeatureTutor.
  ///
  /// In en, this message translates to:
  /// **'Unlimited AI tutor sessions'**
  String get subscriptionFeatureTutor;

  /// No description provided for @subscriptionFeatureReports.
  ///
  /// In en, this message translates to:
  /// **'Detailed progress reports'**
  String get subscriptionFeatureReports;

  /// No description provided for @subscriptionFeatureOffline.
  ///
  /// In en, this message translates to:
  /// **'Offline lessons'**
  String get subscriptionFeatureOffline;

  /// No description provided for @subscriptionFeatureAds.
  ///
  /// In en, this message translates to:
  /// **'Zero advertising, always'**
  String get subscriptionFeatureAds;

  /// No description provided for @subscriptionBillingNote.
  ///
  /// In en, this message translates to:
  /// **'Billed by Google Play / Apple. Manage or cancel in your store account.'**
  String get subscriptionBillingNote;

  /// No description provided for @subscriptionUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Store not available on this device.'**
  String get subscriptionUnavailable;

  /// No description provided for @subscriptionActiveMessage.
  ///
  /// In en, this message translates to:
  /// **'Plus is active until {date}.'**
  String subscriptionActiveMessage(String date);

  /// No description provided for @subscriptionRestored.
  ///
  /// In en, this message translates to:
  /// **'Purchases restored'**
  String get subscriptionRestored;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @settingsLearner.
  ///
  /// In en, this message translates to:
  /// **'Learner'**
  String get settingsLearner;

  /// No description provided for @settingsAppearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get settingsAppearance;

  /// No description provided for @settingsThemeSystem.
  ///
  /// In en, this message translates to:
  /// **'Follow system'**
  String get settingsThemeSystem;

  /// No description provided for @settingsThemeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get settingsThemeLight;

  /// No description provided for @settingsThemeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get settingsThemeDark;

  /// No description provided for @settingsTextSize.
  ///
  /// In en, this message translates to:
  /// **'Text size'**
  String get settingsTextSize;

  /// No description provided for @settingsSound.
  ///
  /// In en, this message translates to:
  /// **'Sound effects'**
  String get settingsSound;

  /// No description provided for @settingsReminders.
  ///
  /// In en, this message translates to:
  /// **'Practice reminders'**
  String get settingsReminders;

  /// No description provided for @settingsRemindersTime.
  ///
  /// In en, this message translates to:
  /// **'Reminder time'**
  String get settingsRemindersTime;

  /// No description provided for @settingsLanguage.
  ///
  /// In en, this message translates to:
  /// **'App language'**
  String get settingsLanguage;

  /// No description provided for @settingsHelp.
  ///
  /// In en, this message translates to:
  /// **'Help & support'**
  String get settingsHelp;

  /// No description provided for @settingsAbout.
  ///
  /// In en, this message translates to:
  /// **'About PhonicsAI'**
  String get settingsAbout;

  /// No description provided for @settingsLegal.
  ///
  /// In en, this message translates to:
  /// **'Privacy policy & terms'**
  String get settingsLegal;

  /// No description provided for @settingsDeleteAccount.
  ///
  /// In en, this message translates to:
  /// **'Delete account & data'**
  String get settingsDeleteAccount;

  /// No description provided for @settingsExportData.
  ///
  /// In en, this message translates to:
  /// **'Export my child\'s data'**
  String get settingsExportData;

  /// No description provided for @settingsConsent.
  ///
  /// In en, this message translates to:
  /// **'Consent'**
  String get settingsConsent;

  /// No description provided for @settingsAccount.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get settingsAccount;

  /// No description provided for @settingsSignOutConfirm.
  ///
  /// In en, this message translates to:
  /// **'Sign out of PhonicsAI on this device?'**
  String get settingsSignOutConfirm;

  /// No description provided for @settingsVersion.
  ///
  /// In en, this message translates to:
  /// **'Version {version}'**
  String settingsVersion(String version);

  /// No description provided for @helpTitle.
  ///
  /// In en, this message translates to:
  /// **'Help & support'**
  String get helpTitle;

  /// No description provided for @helpSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search help topics'**
  String get helpSearchHint;

  /// No description provided for @helpFaq.
  ///
  /// In en, this message translates to:
  /// **'Common questions'**
  String get helpFaq;

  /// No description provided for @helpContact.
  ///
  /// In en, this message translates to:
  /// **'Contact support'**
  String get helpContact;

  /// No description provided for @helpContactBody.
  ///
  /// In en, this message translates to:
  /// **'support@phonicsai.example.com'**
  String get helpContactBody;

  /// No description provided for @helpEmpty.
  ///
  /// In en, this message translates to:
  /// **'No topic matched. Try \"mic\", \"streak\" or \"refund\".'**
  String get helpEmpty;

  /// No description provided for @helpSend.
  ///
  /// In en, this message translates to:
  /// **'Send us a message'**
  String get helpSend;

  /// No description provided for @helpSent.
  ///
  /// In en, this message translates to:
  /// **'Thanks! We reply within one school day.'**
  String get helpSent;

  /// No description provided for @helpNoConnection.
  ///
  /// In en, this message translates to:
  /// **'Support form needs a connection.'**
  String get helpNoConnection;

  /// No description provided for @privacyTitle.
  ///
  /// In en, this message translates to:
  /// **'Privacy for little learners'**
  String get privacyTitle;

  /// No description provided for @privacySummary.
  ///
  /// In en, this message translates to:
  /// **'Children\'s data stays on this device unless you turn on sync.'**
  String get privacySummary;

  /// No description provided for @privacyRecording.
  ///
  /// In en, this message translates to:
  /// **'Audio is transcribed on-device and never stored raw.'**
  String get privacyRecording;

  /// No description provided for @privacyNoAds.
  ///
  /// In en, this message translates to:
  /// **'No advertising, no behavioural analytics, no third-party trackers.'**
  String get privacyNoAds;

  /// No description provided for @privacyExport.
  ///
  /// In en, this message translates to:
  /// **'Export or delete everything any time.'**
  String get privacyExport;

  /// No description provided for @privacyCoppa.
  ///
  /// In en, this message translates to:
  /// **'Compliant with COPPA / GDPR-K; verifiable parental consent is required for cloud sync.'**
  String get privacyCoppa;

  /// No description provided for @privacyTurnOnSync.
  ///
  /// In en, this message translates to:
  /// **'Turn on cloud sync'**
  String get privacyTurnOnSync;

  /// No description provided for @privacyTurnOffSync.
  ///
  /// In en, this message translates to:
  /// **'Turn off cloud sync'**
  String get privacyTurnOffSync;

  /// No description provided for @privacyDeleted.
  ///
  /// In en, this message translates to:
  /// **'All local data deleted'**
  String get privacyDeleted;

  /// No description provided for @privacyDeleteWarning.
  ///
  /// In en, this message translates to:
  /// **'This removes profiles, progress and stars from this device. It cannot be undone.'**
  String get privacyDeleteWarning;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'es', 'hi'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
    case 'hi':
      return AppLocalizationsHi();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
