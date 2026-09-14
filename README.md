# PhonicsAI

A production-architecture Flutter client for a kids' phonics learning app with an
AI tutor: **Android, iOS, Windows, and responsive web**, for readers aged 3–10.

> **Status:** all 22 screens are implemented with real interaction logic. Every
> external system (auth, database, AI, speech, payments, notifications) sits
> behind a clean interface with a clearly-labelled mock/offline adapter —
> nothing is faked as if it were real. See [Integration readiness](#integration-readiness).

## What's in the app

| Area | Screens |
|---|---|
| **Onboarding & accounts** | Splash · Onboarding (language selection) · Sign in / up · Profile setup |
| **Assessment** | English-level placement assessment (adaptive, scored) |
| **Learn** | Home dashboard · Daily mission · Phonics curriculum (6 real units, SATPIN → r-controlled) · 10-stage lesson player |
| **Practice loop** | Games hub + game engine (Sound Match, Blend Builder, …) · Say-it-aloud pronunciation · Read-along library · Letter/word tracing & spelling |
| **AI tutor** | "Aria" chat with mic input (streaming replies, safety note, parent-gated open chat) |
| **Progress** | Dashboard with streaks/mastery · Achievements & rewards |
| **Grown-ups** | PIN gate · Parent dashboard · Child report · Subscription paywall · Controls · Settings · Help · Privacy/account |

The learning loop every lesson follows:
**Discover → Hear → See → Understand → Practice → Play → Recall → Speak → Read → Review.**

## Design provenance

The original brief pointed at a Stitch project
(`stitch.withgoogle.com/projects/10296312261291052213`), which is login-gated
and was not reachable from the build environment. The design system therefore
lives in swappable tokens — `lib/theme/app_colors.dart` (a `ThemeExtension`
with light/dark palettes), `app_dimens.dart`, `app_typography.dart`,
`app_theme.dart` (separate *kid* and *parent* themes) — so exact Stitch
tokens/sizes can be dropped in without touching screens. Kid screens are
big-target and picture-led; the parent area is deliberately denser and quieter.

## Quick start

```bash
flutter pub get
flutter gen-l10n          # regenerates lib/l10n/generated from the .arb files
flutter test              # 118 tests: unit + widget + whole-app flow at 4 window sizes
flutter analyze           # must stay at "No issues found!" (strict lints on)

flutter run -d <device>                       # debug
flutter build apk --release --flavor dev      # Android (dev/staging/prod flavors)
flutter build web --release --no-wasm-dry-run # web
flutter build windows --release
```

### Backend mode (compile-time, no secrets in code)

```bash
flutter run --dart-define=BACKEND_MODE=mock          # default: local-only, all mocks
flutter run --dart-define=BACKEND_MODE=offline_first
flutter run --dart-define=BACKEND_MODE=live \
        --dart-define=API_BASE_URL=https://api.example.com
```

`lib/core/env/app_config.dart` reads these. Keys for AI services, Play Billing,
etc. are **never** stored in the client: they belong in the backend, which the
`live` mode talks to via `ApiClient` + `AuthTokenProvider`.

## Architecture

```
lib/
├── app/                    # composition root
│   ├── bootstrap.dart      # storage migrations, error handling, adapter wiring
│   ├── di/infrastructure.dart   # every platform adapter + ApiClient in one file
│   ├── router/             # go_router: adaptive shell (learner tabs) + parent shell
│   └── state/              # cross-feature app settings
├── core/                   # framework-only utilities, no feature logic
│   ├── domain/ models/     # shared entities (LearnerProfile, ReadingLevel, …)
│   ├── result/ error/      # sealed Result<T>, AppFailure
│   ├── storage/            # KeyValueStore, CollectionStore, SecureVault (PIN hashing)
│   ├── network/            # ApiClient (http), AuthTokenProvider (token refresh hook)
│   ├── audio/ speech/      # AudioService, SpeechService + lexical pronunciation scorer
│   ├── billing/ notifications/ analytics/
│   └── responsive/         # Breakpoint, ContentLimits, ResponsiveValue
├── theme/                  # colour/dimension/typography tokens, kid + parent themes
├── l10n/                   # app_en/es/hi .arb → generated AppLocalizations
├── features/<feature>/     # one folder per product area (18 features)
│   ├── domain/             # models + repository/service interfaces
│   ├── data/               # local (SharedPreferences-backed) + mock implementations
│   ├── application/        # Riverpod controllers/notifiers — all state transitions
│   └── presentation/       # screens + widgets — render state, forward intents, no logic
└── shared/                 # cross-feature widgets (AppCard, KidScaffold, status views…)
```

Rules the code follows (enforced by review + `flutter analyze --fatal-infos`
strict lints):

- **No business logic in widgets.** Screens never mutate storage directly; they
  read controllers and send intents.
- **`Result<T>` / `AppFailure` at repository boundaries** — UI renders real
  loading / error / empty states (`status_views.dart`), not spinners into the void.
- **Responsive everywhere:** content is clamped (`ContentLimits`), layout keys off
  `Breakpoint`, never off hard-coded screen sizes. The whole-app widget test runs
  every primary route at 360×640, 412×915, 800×1180 and 1440×900 and fails on any
  RenderFlex overflow.
- **Offline-first persistence:** profiles, progress, SRS review schedule,
  settings, achievements — `shared_preferences` behind `CollectionStore`.
- **Accessibility:** semantics labels on every kid card, ≥56 dp tap targets in
  learner flows (72 dp in games), `MediaQuery.disableAnimations` honoured,
  text everywhere is `TextScaler`-friendly.

## Testing

```
test/core/        storage, pronunciation scoring, utils
test/features/    profile repo, assessment scoring, account repo, learning loop,
                  skills/rewards, tutor rules
test/widget/      onboarding flow, whole-app flow (all shells at 4 sizes)
test/smoke/       app boots, router guards, parent gate lock-on-exit
```

`test/harness/screen_harness.dart` provides `pumpScreen` / `pumpApp` (real
router + DI overrides), `expectNoOverflow`, and a seeded "onboarded" store, so
widget tests run against the same composition the app ships with.

## Integration readiness

The mock layer is *deliberately* the only implementation that ships today.
Swapping in a real backend means implementing an interface and changing one
line of DI:

| Interface (`domain/`) | Today's adapter (`data/`, `app/di/`) | Real drop-in |
|---|---|---|
| `AuthRepository` | `DeviceAccountRepository` (local, device-bound) | OIDC/backend session API |
| `ProgressRepository` | `LocalProgressRepository` | same + sync queue |
| `TutorService` | `PhonicsRuleTutor` (deterministic rules) | LLM SSE endpoint via `ApiSseStream` |
| `SpeechService` | `MockSpeechService` + `LexicalPronunciationScorer` | on-device STT/ASR plugin |
| `AudioService` | `AssetAudioService` | platform media player |
| `BillingGateway` | `MockBillingGateway` | `in_app_purchase` / Play Billing |
| `SupportService` | `QueuedLocallySupportService` (queues, shows queued state) | Zendesk/own API |
| `ReminderScheduler` | `LocalReminderScheduler` | `flutter_local_notifications` |

Search for `TODO(backend)` — every seam is marked (auth, privacy deletion,
billing verification, tutor context endpoint). No payment secrets or AI keys
exist anywhere in the client; `MockBillingGateway` never contacts a store.

## Known limits

- Spanish (`78/213`) and Hindi (`25/213`) translations are partial; untranslated
  keys fall back to English by design (`fallbackLocale: en`).
- The pronunciation scorer is a word-level lexical mock — real phoneme scoring
  needs the speech adapter.
- Letter tracing uses a geometric path-completion score, not a handwriting engine.
