/// Every path in one file. Screens use these constants (never raw strings) so a
/// deep link or a rename can't silently break navigation.
abstract final class AppRoutes {
  static const splash = '/splash';

  static const onboarding = '/onboarding';
  static const onboardingLanguage = '/onboarding/language';
  static const onboardingAuth = '/onboarding/auth';
  static const onboardingProfiles = '/onboarding/profiles';
  static const onboardingAssessment = '/onboarding/assessment';

  // Learner shell branches.
  static const home = '/home';
  static const learn = '/learn';
  static const games = '/games';
  static const tutor = '/tutor';
  static const progress = '/progress';

  // Immersive full-screen flows (they must cover the bottom bar).
  static const lesson = '/lesson';
  static const game = '/game';
  static const pronunciation = '/practice/pronunciation';
  static const reading = '/practice/reading';
  static const writing = '/practice/writing';
  static const rewards = '/rewards';
  static const profileEditor = '/profile';
  static const profileNew = '/profile/new';

  // Parent area (gated).
  static const parent = '/parent';
  /// Kept outside the `/parent` prefix on purpose: a path that is a child of a
  /// shell's own route competes with it during matching. The gate is the door,
  /// not a room inside the parent area.
  static const parentUnlock = '/grown-ups-gate';
  static const parentChild = '/parent/child';
  static const parentReports = '/parent/reports';
  static const parentSubscription = '/parent/subscription';
  static const parentSettings = '/parent/settings';
  static const parentHelp = '/parent/help';
  static const parentPrivacy = '/parent/privacy';

  static String lessonFor(String lessonId) => '$lesson/$lessonId';
  static String gameSession(String gameId) => '$game/$gameId';
  static String readingPassage(String passageId) => '$reading/$passageId';
  static String writingTrace(String targetId) => '$writing/$targetId';
  static String childReport(String profileId) => '$parentChild/$profileId';

  static const learnerBranches = <String>[
    home,
    learn,
    games,
    tutor,
    progress,
  ];

  static const parentBranches = <String>[
    parent,
    parentSubscription,
    parentSettings,
  ];

  static bool isParentArea(String location) => location.startsWith(parent);
}
