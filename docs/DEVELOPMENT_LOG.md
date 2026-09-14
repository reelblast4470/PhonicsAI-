# Development log — phase by phase

Every phase ended with `flutter analyze` clean and the full test suite
green (`flutter test`). "Errors fixed" lists real defects the tests or the
compiler found — kept because they're the best map of the tricky parts of the
codebase.

> **Design source note:** the brief referenced a Stitch project
> (`stitch.withgoogle.com/projects/10296312261291052213`); it redirects to a
> Google sign-in wall and was not fetchable from the build environment. The
> owner then approved "change the UX if better than Stitch", so the UI follows
> the brief's structure (kid-first, big targets, denser parent area) with the
> design system isolated in `lib/theme/*` for later token-for-token alignment.

## Phase 1 — Foundation: theming, core services, navigation skeleton

**Implemented**
- Design tokens: `theme/app_colors.dart` (ThemeExtension, light+dark, per-profile
  accent), `app_dimens.dart`, `app_typography.dart`, `app_theme.dart` (kid and
  parent themes).
- Core plumbing: sealed `Result<T>` + `AppFailure`; `Breakpoint`/`ContentLimits`/
  `ResponsiveValue`; `KeyValueStore` + `CollectionStore` over `shared_preferences`;
  `SecureVault` with in-memory impl + salted `PinHasher`; `ApiClient` +
  `AuthTokenProvider` (retry/timeouts, no secrets); analytics stub recorder;
  `AudioService`/`SpeechService` interfaces + mocks; `BillingGateway` +
  `ReminderScheduler` interfaces; env config with flavors and
  `BACKEND_MODE` via `--dart-define`.
- `app/bootstrap.dart` (migrations + global error handler), DI composition file
  `app/di/infrastructure.dart`, go_router with learner shell (Home·Learn·Games·
  Tutor·Progress) and parent shell (Dashboard·Child·Subscription·Settings),
  adaptive rail↔bar switch, splash + onboarding screens, l10n wiring
  (`l10n.yaml`, `app_en.arb`, generated accessors, `context.l10n`).
- Shared widget kit: `AppButton`, `AppCard`/`PressableCard`, `AppTextField`,
  `BadgePill`, `ConfettiBurst`, `KidScaffold`, `ProgressRing`, `SectionHeader`,
  `StarRow`, Loading/Error/Empty/`AsyncStateView`, `WordBuilder`, `AppToast`.

**Deps added:** flutter_riverpod 2.6.1, go_router, http, shared_preferences,
intl + flutter_localizations, flutter_lints. (Chose pinned Riverpod 2.x, no
freezed/codegen — build_runner churn on constrained CI; the code uses
`FamilyNotifier` arg via `build(arg)`.)

**Tests:** analyzer rules (`strict-casts`, `strict-raw-types`,
`require_trailing_commas`); harness scaffold.

**Errors fixed**
- `flutter create` web/android/ios/windows platform generation and Java/Gradle
  notice on the sandbox image (informational only).

## Phase 2 — Accounts: language, auth, profiles, assessment

**Implemented**
- Onboarding language screen (AppLanguage list, RTL-safe later), auth screen
  (sign-in/up form validation, offline-friendly), `AuthRepository` interface +
  `DeviceAccountRepository` mock (device-bound account, **marked mock, not
  presented as real auth**).
- Profile setup: multi-profile CRUD, avatar/name/age-birthmonth, kid/teen/adult
  density, `profilesProvider`, active-profile switching through app settings.
- English-level assessment: question bank, adaptive routing, scoring →
  `ReadingLevel` (stretched band), results summary + retake.

**Tests:** `features/local_profile_repository_test.dart`,
`features/assessment_scoring_test.dart`, `widget/onboarding_screens_test.dart`
(flow through language→auth→profiles→assessment at 4 sizes).

**Errors fixed**
- KidScaffold wrapped every body in `SingleChildScrollView` → `Expanded`
  children threw "non-zero flex but incoming height constraints are unbounded"
  on the assessment screen → added `scrollable` flag + `ScrollableColumn`.
- `IconButtonThemeData(minimumSize: Size.fromHeight(72))` → infinite-width
  crash in AppBar actions → square `Size(72, 72)`.

## Phase 3 — Curriculum + progress data layer

**Implemented**
- `features/curriculum/data/phonics_program.dart`: 6 real SATPIN-first units
  through r-controlled vowels; `LessonStageBuilder` generating the 10 learning
  loop stages per lesson; 149-entry picture (emoji) map; `distractorsFor()`
  guaranteeing distractors never contain the target sound.
- Progress domain: XP, accuracy, streaks, SRS review schedule (Leitner-style
  boxes), mastery per grapheme; `LocalProgressRepository` over `CollectionStore`;
  daily-mission derivation from due items + curriculum position.

**Tests:** `core/collection_store_test.dart`, `core/util_test.dart`,
`features/learning_loop_test.dart` (stage sequencing/XP awarding),
`features/skills_and_rewards_test.dart` (SRS, streak edge cases).

## Phase 4 — Learn + Lesson player + Home

**Implemented**
- Curriculum screen (unit list, lock logic from progress), lesson player
  (stage-by-stage runner over `LessonSession` controller: audio cues through
  `TtsBridge`, word building, exit confirmation that saves first), learn hub
  with next-up card, home dashboard with greeting, daily mission card, streak
  ring, quick-start, offline banner.

**Tests:** lesson open/advance/leave covered in `widget/app_flow_test.dart`
(all 4 window sizes).

**Errors fixed**
- Text-heavy rows (badge pills, headers) overflowed under the Ahem test font
  at 360 dp → `Flexible`+ellipsis in `BadgePill`, `Wrap` for pill rows.
- ConfettiBurst read `MediaQuery` in `initState` → assertion → restructured to
  record the trigger, read prefs in `didChangeDependencies` path.

## Phase 5 — Games

**Implemented**
- Game model + catalog + factory + a real round engine (state machine, timing,
  scoring) with boards: Sound Match, Blend Builder, Word Snap, Rhyme Race,
  Sound Safari; games hub with kid-size cards; `game_play_screen` drives any
  engine through one widget; long-press "how to play" (`AppCard.onLongPress`).

**Tests:** engine round-trips in `features/learning_loop_test.dart` family +
game round interaction test in `app_flow_test.dart`.

**Errors fixed**
- Hub's `GridView` of fixed-height cards overflowed with dense fonts → natural
  height + `Wrap`.
- `x ?? const []` inside generics inferred `List<dynamic>` (CFE-only error the
  analyzer missed) → explicit `const <String>[]`.

## Phase 6 — AI tutor (Aria)

**Implemented**
- `TutorService` interface + `PhonicsRuleTutor` (deterministic, kid-safe rule
  engine; **labelled offline mock**; `TODO(backend)` for the real endpoint);
  streaming simulation path (`onToken`) so the SSE UI works before a backend;
  tutor controller (thread persistence, 40-message cap, thinking state, error
  state with retry/clear); tutor screen: mic-primary input, picture-chip
  starters, safety note, action chips that deep-link to lesson/practice routes;
  parent control `allowOpenChat` gates open text entry.

**Tests:** `features/tutor_rules_test.dart` (9: rule responses, safety
fallbacks, chips/actions), tutor round-trip in `app_flow_test.dart`.

## Phase 7 — Speak · Read · Write

**Implemented**
- Pronunciation: `SayItCard` (record→score→feedback loop over
  `MockSpeechService` + `LexicalPronunciationScorer`; marks the seam for real
  on-device ASR), practice routes `/practice/pronunciation/<phoneme>`.
- Reading: graded mini-library (`ReadAlongCard`, per-word highlight synced to
  TTS), reading tally feeding `ReadingLevel` progression.
- Writing/spelling: `TracingBoard` (stroke capture, coverage scoring) + letter
  spelling rounds feeding the same SRS; `writing_screen`.

**Tests:** scoring units in `core/pronunciation_scoring_test.dart`; screen
flows in app_flow/smoke.

## Phase 8 — Progress + rewards

**Implemented**
- Progress dashboard: mastery rings, accuracy/time trend mini-charts (custom
  painted, no chart dep), per-grapheme breakdown, "what to practise next".
- Achievements engine (badges with honest unlock rules) + rewards screen;
  stars/XP surfaced on home.

**Tests:** `features/skills_and_rewards_test.dart` extended (19 cases).

## Phase 9 — Grown-up area

**Implemented**
- `ParentGateScreen`: 4-digit PIN keypad over `SecureVault` + `PinHasher`
  (salted hash, lockout backoff, "create first code" flow); gate enforced in
  the router (deep links can't skip it); route `/grown-ups-gate`.
- Parent dashboard: per-child summary cards, content-controls card (mic on/off,
  open-chat on/off, daily time-limit picker, reminder switch), plan/status row;
  child report screen (sessions, sounds shaky, time on task, weekly list).

**Tests:** gate lock/unlock/backoff + "locks when stepping out" in
`app_flow_test.dart`/smoke.

## Phase 10 — Subscription · Settings · Help · Privacy

**Implemented**
- Subscription: plan catalog in `domain` (`PricingPlan`, billing periods,
  savings labels), `BillingGateway` interface + `MockBillingGateway`
  (never talks to a store; verification is `TODO(backend)` — Play Billing
  server-side per policy), paywall with plan cards, trial/restore, honest
  "stay free" exit, status surfaced on dashboard/profile.
- Settings: sound/voice prefs (TTS rate/pitch), reminders, profile management,
  language switch, theme, kid density.
- Help: 10-entry FAQ + contact form queued through `SupportService`
  (shows queued state; real send is `TODO(backend)`).
- Privacy/account: data inventory, export (writes JSON via store), deletion
  flow with typed confirmation; account section for the device account.

**Tests:** paywall + settings + help rendered at 4 sizes in app_flow.

## Phase 11 — Hardening pass (final)

**Fixed**
- Paywall `_PlanCard`: price + selection mark stacked in a Column (side-by-side
  overflowed a 360 dp card), title row → `Wrap` (title + savings + current
  pills no longer push 123 px off-screen).
- Tutor `_ThinkingBubble`: bubble was measured against the Row's *full* width
  (non-flex child + inner min-Row) → wrapped in `Flexible`, removing a 42 px
  overflow on phones.
- `ParentShell`: `NavigationRail(extended: true, labelType: all)` is an illegal
  combination (asserted at 1440) → labelType only when not extended; rail
  `leading` gets unbounded width from the framework, so the brand `Row` can
  never use flex → title only renders when extended, inside a bounded box.
- `ParentShell` used `ref` inside `dispose()` → Riverpod StateError → gate
  notifier captured in `initState` (provider is not autoDispose).
- `AppCard` now inserts a transparent `Material` between its coloured
  `DecoratedBox` and content: `ListTile` inks would otherwise be hidden (and
  Flutter asserts in tests since 3.27-ish).
- Test harness: `tapAndSettle` pumps until a pending `ensureVisible` reveal
  animation lands — taps were using stale geometry and hitting the widget the
  target was *passing under* (the tutor chip under the composer).
- Web release build on constrained CI (2 GB RAM): added swap +
  `--no-wasm-dry-run` (dart2js + dart2wasm dry-run double-compiles and OOM'd);
  documented.
- Removed now-unused `PlaceholderScreen` (every screen it stood in for shipped).

**Final check:** `flutter analyze` → No issues found. `flutter test` →
118 passing. `flutter build web --release --no-wasm-dry-run` → ✓ Built
build/web.

## Deliberate omissions (by design, not by accident)

- No real network calls: `live` mode compiles against `ApiClient` but no
  backend exists; everything user-visible is labelled mock or works offline.
- No secrets client-side: no AI keys, no Play Billing public keys embedded;
  verification is documented as server-side.
- Full es/hi translations deferred (structure + fallbacks are in place).
