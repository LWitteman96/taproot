# Habit App — Infrastructure Starter Guide

*Derived from a full read of the inkBlox codebase (`tree/main`, v1.1.0+49). Nothing in inkBlox was modified.*

This is the "how do I stand this project up" document. It takes every infrastructure decision inkBlox already made and settled, says **keep / drop / add** on each, and ends with a day-one checklist. The product decisions live in the three existing specs (design, growth engine, reflection logic) — this document is only about the machinery underneath them.

---

## 0. The one-paragraph summary

inkBlox is a Flutter + Supabase app with three flavors, Riverpod 3 with no code generation, go_router, an offline-first SQLite mirror behind a repository interface, hand-written SQL migrations with explicit RLS, Sentry, and a bare+worktree git layout with symlinked secrets. Roughly **85% of that transfers to the habit app unchanged**. What changes: you drop the social/moderation half, you add local notification scheduling, and — the important one — the *drawing engine* slot in `lib/core/` is where the **growth engine** goes. inkBlox proves the pattern: a pure, dependency-free domain core with ~100 test files around it, wrapped by a thin Riverpod controller. Your engine spec is exactly that shape.

---

## 1. Stack decisions — keep, drop, add

### Keep as-is

| Concern | inkBlox choice | Why it carries over |
|---|---|---|
| Framework | Flutter, Dart SDK `>=3.4.0 <4.0.0` | Same target (iOS + Android), same team |
| State | `riverpod` + `flutter_riverpod` ^3.0.3 | Hand-written providers, no codegen — see §5 |
| Routing | `go_router` ^17.0.1 | Declarative + a redirect guard you'll reuse for onboarding |
| Backend | `supabase_flutter` ^2.5.4 | Auth + Postgres + Storage + Edge Functions in one |
| Local DB | `sqflite` ^2.4.2 | Offline-first completions are non-negotiable (§8) |
| Prefs | `shared_preferences` | Small device-local flags (age gate, onboarding seen) |
| Connectivity | `connectivity_plus` ^7.0.0 | Drives the sync trigger |
| Errors | `sentry_flutter` ^9.7.0 + `sentry_dart_plugin` | Already wired with per-flavor sample rates |
| Logging | `logging` ^1.2.0 + `dart:developer` | Two-tier convention, see §11 |
| Env | `flutter_dotenv` ^6.0.0 | Per-flavor `.env` files declared as assets |
| Flavors | `flutter_flavorizr` ^2.4.1 | Regenerates native flavor config from `pubspec.yaml` |
| Auth SSO | `google_sign_in` ^7.2.0, `sign_in_with_apple` ^7.0.1 | Apple sign-in is mandatory if you ship Google sign-in on iOS |
| Lint | `flutter_lints` ^5.0.0 + `custom_lint` + `riverpod_lint` ^3.0.3 | Catches Riverpod misuse the analyzer can't |
| Test | `flutter_test`, `mocktail`, `mock_supabase_http_client`, `sqflite_common_ffi` | The full local-test triangle already solved |
| Misc | `uuid`, `crypto`, `collection`, `path`, `path_provider`, `url_launcher`, `app_links`, `device_info_plus` | Generic plumbing |

### Drop

| Package | Reason |
|---|---|
| `provider` ^6.1.5 | Legacy in inkBlox, unused. Don't carry the dead weight. |
| `flutter_colorpicker`, `color_parser`, `multi_border`, `atlas_icons` | Drawing-editor specific |
| `image_picker`, `gal`, `file_selector`, `file_saver` | Only needed if you add avatar upload / export later |
| `share_plus`, `hyperlink`, `super_tooltip`, `smooth_page_indicator` | Add back on demand, not up front |
| `open_mail` (git dependency) | A git-sourced dep is a supply-chain and CI liability; only add if support-email UX demands it |
| `path_to_regexp` | go_router handles this now |
| `mocktail` in `dependencies` | inkBlox has it as a **runtime** dependency by mistake — put it in `dev_dependencies` |

### Add

| Package | For |
|---|---|
| `flutter_local_notifications` | The evening check-in — the single most load-bearing new dependency |
| `timezone` | Notification scheduling must be timezone- and DST-correct or the whole nudge model breaks |
| `permission_handler` | iOS notification permission, Android 13+ `POST_NOTIFICATIONS`, exact-alarm on Android 12+ |
| `flutter_animate` *or* hand-rolled `AnimationController`s | The watering moment and ambient garden need real craft; inkBlox has no animation library |
| `rive` or `lottie` (decide later) | Only once the external plant illustrator is briefed — their output format decides this. Keep it a placeholder slot. |
| `flutter_svg` | Already in inkBlox; likely how plant art arrives |

> **Notification permission is a first-class product risk, not a plumbing detail.** The entire growth engine measures autonomy by *withholding* nudges — which presupposes nudges were granted in the first place. Handle the denied-permission state as a real app mode, not an error toast.

---

## 2. Repository layout

inkBlox uses a **bare + worktree** layout: `.bare/` holds the git dir, every branch is checked out under `tree/<prefix>/<name>`, and `.secrets/` is the single source of truth for env files, symlinked into each worktree.

**Recommendation: adopt it, but only once you have a second branch in flight.** The payoff is real (parallel branches, no stashing, shared secrets) but each Flutter worktree costs 2–10 GB, and the two scripts that make it usable are ~35 KB of bash you'd want to port carefully.

Two scripts do all the work and port cleanly with a find-and-replace on the project name:

- **`setup-worktree.sh`** — creates `tree/<prefix>/<name>`, symlinks everything in `.secrets/`, runs `flutter pub get`, optionally restarts the shared local Supabase. Flags worth keeping: `--pr` (pick an open PR interactively via `gh`), `--update`, `--no-supabase`, `--create-branch` (non-interactive, required for agents/CI), `--base <ref>`.
- **`cleanup-worktrees.sh`** — dry-run by default; only removes a worktree when HEAD is upstream (or every commit matches by patch-id via `git cherry`), the tree is clean including untracked files, there are no local-only commits, and there's no open PR.

The one detail that's easy to get wrong: `.env` itself is a **copy** of `.env.dev`, not a symlink, because the running app overwrites it when switching flavors. Everything else in `.secrets/` is symlinked.

**Simpler start:** a single normal checkout, with `.secrets/` and the two scripts added the day you branch a lot. The rest of this guide doesn't depend on the choice.

```
lib/
  app/        # app-wide wiring: theme, router, logging, startup, supabase, connectivity
  core/       # pure domain: THE GROWTH ENGINE, models, utils
  features/   # habits, reflection, garden, auth, profile, settings
  shared/     # reusable UI (buttons, inputs, nav shell)
  widgets/    # garden rendering widgets (the drawing-editor slot)
test/
  unit/       # ProviderContainer only, no widget tree
  features/   # widget tests mirroring lib/features
  widgets/
  utils/      # FakeXxx services, Supabase mocks, HTTP overrides
supabase/
  migrations/ # timestamped SQL
  functions/  # Deno edge functions
assets/
scripts/
```

---

## 3. Flavors and environments

Three flavors, three entry points, three env files — copy this wholesale.

| Flavor | Bundle id pattern | Backend |
|---|---|---|
| `dev` | `com.<app>.app.dev` | Local Supabase in Docker |
| `stg` | `com.<app>.app.stg` | Staging project (a persistent branch of prod) |
| `prod` | `com.<app>.app` | Production project |

`flavorizr:` in `pubspec.yaml` generates the native config; each flavor gets its own icon set. Entry points are one-liners:

```dart
// lib/main_dev.dart
void main() async {
  await dotenv.load(fileName: ".env.dev");
  await runMainApp();
}
```

At runtime, `getFlavor()` in `lib/core/utils/flavor.dart` resolves the flavor from `appFlavor` (set by `--flavor`) on mobile, or a `WEB_FLAVOR` dart-define on web, defaulting to `dev`. It's a clean ~30-line switch expression — copy it verbatim.

```bash
flutter run --flavor dev  -t lib/main_dev.dart
flutter run --flavor stg  -t lib/main_stg.dart
flutter run --flavor prod -t lib/main_prod.dart
```

The `.env.*` files are gitignored **and** declared as assets in `pubspec.yaml`. That combination bites in CI: `flutter analyze` verifies declared assets exist. inkBlox's fix is a one-line CI step, `touch .env.dev .env.stg .env.prod` — keep it.

---

## 4. App bootstrap chain

The startup path is worth copying exactly, because the ordering matters:

```
main_<flavor>.dart
  └─ dotenv.load(".env.<flavor>")
      └─ runMainApp()                       // lib/main.dart
          ├─ SentryWidgetsFlutterBinding.ensureInitialized()   // enables frame tracking
          ├─ setupLogging()
          ├─ await Supabase.initialize(url, anonKey)
          ├─ getFlavor()
          └─ SentryFlutter.init(              // sample rates: 0.2 prod, 1.0 dev/stg
               appRunner: () => runApp(ProviderScope(child: MyApp())))
                └─ MyApp (ConsumerWidget)
                    └─ MaterialApp.router(routerConfig: ref.watch(goRouterProvider))
```

Two pieces to carry over that are easy to overlook:

- **`restorationScopeId`** on `MaterialApp.router` — Flutter state restoration so Android can restore the nav stack after backgrounded process death. inkBlox pairs it with local autosave. Your equivalent: an in-progress reflection check-in should survive the same way.
- **`AppStartupWidget` + `appStartupProvider`** — a `FutureProvider<void>` that owns all async init after Supabase/Sentry, with loading and error-with-retry screens. In inkBlox it's nearly empty (it just keeps the auth↔guest-mode listener alive), which is exactly the point: it's a slot that costs nothing now and saves a refactor later. **Your habit app fills it immediately** — notification permission check, timezone database init, rehydrating the garden from SQLite, and scheduling the evening check-in.

---

## 5. State management conventions

**Riverpod 3, hand-written, zero code generation.** No `.g.dart`, no freezed, no `json_serializable`. Every `copyWith()` and `fromJson()`/`toJson()` is written by hand. This is a deliberate constraint in inkBlox's `AGENTS.md` and it's worth keeping — it removes build_runner from the loop entirely, which matters most when an agent is editing the code.

The conventions that make it work:

**Nullable fields in `copyWith` use thunks**, so you can distinguish "not provided" from "set to null":

```dart
DrawingState copyWith({Drafting? Function()? draft}) =>
    DrawingState(draft: draft != null ? draft() : this.draft);
```

**Selector providers sit next to any large state object** to keep rebuilds narrow:

```dart
final currentToolProvider = Provider<Tool>((ref) =>
    ref.watch(drawingControllerProvider.select((s) => s.settings.currentTool)));
```

For the habit app this pattern is if anything more important — the garden screen watches many derived values (per-habit vitality, stage, root depth) off one habit-state object, and you do not want a completion tap on one plant rebuilding the whole garden.

**Other rules from `AGENTS.md` worth adopting verbatim:**

- `@immutable` on all state/domain classes
- `NotifierProvider<Controller, State>(Controller.new)` for controllers; `Provider<T>` for DI; `FutureProvider<void>` for async startup
- `ref.watch` in widgets, `ref.read` in methods; inject deps in `Notifier.build()` via `ref.read`
- Prefer `switch` expressions over if/else chains when exhausting an enum
- Absolute package imports (`package:<app>/...`), relative only within the same directory
- No abbreviations as variable names — ever
- 2-space indent, `dart format .` before commit

---

## 6. The repository/service pattern

Every backend-touching feature follows one shape:

```dart
abstract class HabitRepository { /* interface */ }
class HabitService implements HabitRepository { /* Supabase impl */ }

final habitServiceProvider = Provider<HabitRepository>(
  (ref) => HabitService(supabase: ref.watch(supabaseClientProvider)),
);
```

…with a `FakeHabitService` in `test/utils/` for unit tests. `supabaseClientProvider` is a three-line `Provider<SupabaseClient>` wrapping `Supabase.instance.client` — its only job is to be overridable in tests, and it's worth having on day one.

This interface is also what makes §8 possible: inkBlox has **four** implementations of one repository interface (remote, local SQLite, caching decorator, guest) and swaps them at the provider level.

One inkBlox caution to avoid repeating: `pixel_art_service.dart` is **873 lines** and its repository interface covers pixel art, feed, likes, comments, reports, blocks, and moderation. Split by aggregate from the start — `HabitRepository`, `CompletionRepository`, `ReflectionRepository` — even though it feels like over-structuring on day one.

---

## 7. Routing and the gate pattern

`goRouterProvider` is a `Provider<GoRouter>` with a flat list of `GoRoute`s and a `redirect` that gates entry. inkBlox's version resolves an `AccountGate` record:

```dart
typedef AccountGate = ({bool hasUsername, bool hasBirthDate, bool ageRestricted});
```

…via an `autoDispose` `FutureProvider` that reads the profile row, and — importantly — **fails safe**: on any error it returns "needs onboarding, not restricted", so a transient network failure never bypasses onboarding *nor* wrongly locks someone out. It also only evaluates on the root and initial paths (`state.matchedLocation == '/' || '/feed'`) so the guard doesn't rerun on every navigation.

Copy the structure, change the gate contents. Yours is something like `(bool hasProfile, bool hasFirstHabit, bool notificationsDecided)` — routing a new user into habit creation rather than into an empty garden.

Custom transitions live in `lib/app/routing/` (inkBlox has `no_swipe_back_page_route.dart` for screens where iOS back-swipe would lose work — your reflection flow wants the same).

---

## 8. Offline-first — the most valuable thing to copy

This is the part of inkBlox worth studying closely, because a habit app needs it *more* than a drawing app does. **A completion tap must never fail, never spin, and never be lost.** It is the emotional core interaction and it happens in gyms, on trails, and on airplanes.

inkBlox's architecture, all behind one `PixelArtRepository` interface:

| Implementation | Role |
|---|---|
| `PixelArtService` | Remote — Supabase |
| `LocalPixelArtService` | SQLite via `sqflite`, with versioned `onCreate`/`onUpgrade` migrations (currently at v6) |
| `CachingPixelArtService` | **Decorator** — delegates to remote, mirrors results into local fire-and-forget so the cache stays warm |
| `GuestPixelArtService` | Purely local, for users who chose "continue without an account" |
| `SyncService` | A `Notifier<SyncState>` that listens for a **false → true connectivity edge** and pushes rows where `pending_sync = 1` |

The details that make it correct:

- The caching decorator writes to the local cache **without awaiting** and `.catchError`s into a log line — a failed cache write must never fail the user's operation.
- `SyncService` treats a `null` previous connectivity value as "was offline," so the very first `true` emission also triggers a sync rather than being swallowed.
- The local schema carries a `pending_sync INTEGER NOT NULL DEFAULT 0` column and the SQLite `onUpgrade` path adds columns idempotently (it even `PRAGMA table_info`s before adding, for re-run safety).
- Signed URLs are cached with an expiry **one hour shorter** than the real 24h TTL, so the cache goes stale before Supabase starts rejecting.
- Guest mode (`guestModeProvider`) is a plain `Notifier<bool>` plus `authGuestModeSyncProvider`, which listens to `onAuthStateChange` and clears the guest flag on `signedIn`/`tokenRefreshed` regardless of which login path was used. A synthetic `guestUserId = 'guest'` keeps the model's `userId` non-nullable.

**For the habit app**, the local database is not a cache — it is the **primary store**, and Supabase is the durable backup and cross-device sync. That's a stronger position than inkBlox takes and it simplifies the UI: every read is local and synchronous-feeling; every write is local-then-queued.

Tables to keep local-first: `habits`, `completions`, `reflections`, `nudges`. Derived engine values (stage, vitality, roots, autonomy) should be **computed, never stored** — or stored only as a cache keyed by a version of the engine constants, so tuning the θ/ρ tables in the growth spec doesn't require a data migration.

> **Conflict policy, decide now:** completions are append-only events keyed by `(habit_id, local_uuid)`, so multi-device sync is a union rather than a merge. Generate the UUID client-side with `uuid` before insert. This one decision removes essentially all sync conflict handling.

---

## 9. Supabase backend

### Migrations

32 timestamped SQL files in `supabase/migrations/`, hand-written, applied by `supabase start` / `supabase db reset` locally and `supabase db push` remotely. No ORM, no schema-diffing.

The house style is worth keeping: migrations are **idempotent and re-runnable**. Policies are dropped inside a `DO $$ ... IF EXISTS ... EXECUTE 'DROP POLICY' ... END $$;` block before being recreated, and indexes use `CREATE INDEX IF NOT EXISTS`. That's what lets the same file apply cleanly to local, staging, and prod at different points in their history.

### RLS

Every table has RLS enabled with explicit grants, and the pattern is consistent:

```sql
ALTER TABLE public.habits ENABLE ROW LEVEL SECURITY;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.habits TO authenticated;

CREATE POLICY "Enable select for users based on user_id"
  ON public.habits FOR SELECT TO PUBLIC
  USING ((SELECT auth.uid()) = user_id);
```

Two things to carry over: the `(SELECT auth.uid())` wrapping (it lets Postgres cache the call per-statement instead of per-row — a real performance difference at scale), and `REVOKE`ing grants you don't want even when a policy would already block them. Belt and braces.

The habit app's RLS is *much* simpler than inkBlox's, because there's no social graph. Every table is `user_id = auth.uid()`, full stop. inkBlox needed six migrations to untangle RLS recursion in feed deletes and comments — you get to skip all of it.

### New-user trigger

`handle_new_user()` is a `security definer` trigger on `auth.users` that inserts the `profiles` row, with `on conflict (id) do nothing`. Copy it directly; extend the insert with your defaults.

### Storage

Buckets are created in migrations, objects are stored under a `<user id>/` prefix, and signed URLs have a 24h TTL. The habit app probably needs no storage at launch — plant art ships in the bundle. Add a bucket only if habits get user photos.

### Edge Functions

Deno functions in `supabase/functions/`, with a `_shared/` directory for CORS helpers and the like. inkBlox has exactly one: `delete-account`, which is **required by App Store Review Guideline 5.1.1(v)** — an app with account creation must allow in-app account deletion, and deactivation doesn't count. It has to be server-side because the service-role key can't ship in the app and RLS can't delete from `auth.users`.

Its ordering logic is well-reasoned and worth copying with the comment intact: resolve the caller from their **JWT, never the request body** → revoke the Apple grant best-effort → purge storage → delete the auth user (which cascades). Purge-then-delete is chosen because its failure mode is recoverable (user still signed in, can retry) while delete-then-purge orphans files forever with nobody able to retry.

**Port this on day one, not at submission time.** It's the single most common cause of a Flutter app being rejected on first review.

### Config and secrets

`supabase/config.toml` uses `env(...)` references — SMTP password, Apple/Google OAuth client ids and secrets, OTP expiry — resolved from the active `.env`. Auth config includes rate limits, PKCE deep-link redirect URLs (`io.supabase.<app>://login-callback/`), and Apple + Google external providers.

`scripts/supabase-push.sh <stg|prod>` exists because pushing config to the wrong environment with the wrong secrets silently breaks auth. It copies `.env.<env>` to `.env`, links the CLI to the right project ref, pushes secrets, pushes config, and **always restores `.env` to dev via an EXIT trap**. Prod requires typing `production` to confirm. It's ~150 lines and ports with two constants changed.

One honest caveat baked into its output: `supabase config push` is interactive and exits 0 even when you decline the diff, so the script explicitly refuses to claim success.

---

## 10. Testing

inkBlox has **100 test files against 133 source files** — the strongest signal in the repo about how it's meant to be worked on. The split:

- `test/unit/` — pure logic, `ProviderContainer` only, never a widget tree:
  ```dart
  final container = ProviderContainer(overrides: [
    habitServiceProvider.overrideWithValue(FakeHabitService()),
  ]);
  addTearDown(container.dispose);
  ```
- `test/features/`, `test/widgets/` — widget tests mirroring the source tree
- `test/widget/accessibility/` — a dedicated a11y suite (paired with `lib/app/a11y/a11y_labels.dart` and a 19 KB `accessibility_findings.md`)
- `test/utils/` — the enabling layer: `FakeXxxService` implementations, `supabase_test_utils.dart`, `test_http_overrides.dart`, `test_asset_bundle.dart`, `connectivity_test_utils.dart`

`supabase_test_utils.dart` is the piece to steal outright: it initializes Supabase against `mock_supabase_http_client` and hand-builds a session JSON injected via `SharedPreferences.setMockInitialValues`, so tests can run as an authenticated user with no network and no real project. For SQLite tests, `sqflite_common_ffi` runs the real database in-process.

**The growth engine is the highest-value test target in your app.** It's pure Dart — inputs are completions, reflections, and nudge records; outputs are stage, vitality, roots, autonomy. It has no Flutter dependency, no I/O, and a spec full of exact worked examples (f=3 → Young at 5 completions in a 19-day window; seedling droops at 2.8 days and fully wilts at 5.8; `N/(N+4)` giving 0.50 at 4 and 0.83 at 20). **Write those worked examples as the first test file, before the engine exists.** They're a specification and a test suite at the same time, and they'll catch every off-by-one in the window arithmetic.

Also test explicitly: the pace exemption (`C₇ ≥ f` ⇒ vitality 1.0 regardless of gap — the Mon/Tue/Wed rester), paused days excluded from every window, and stage monotonicity under any input sequence.

---

## 11. Observability

Two logging tiers, by design:

- **Core domain controllers** → `dart:developer` `dev.log()` through a small `_log(action, msg)` helper
- **Services and feature providers** → `package:logging` `Logger('ServiceName')`, one named logger per class

`setupLogging()` sets root level to `ALL` in debug and `WARNING` in release and pipes everything through `dev.log`.

Error handling, split by layer:

- **Services/repositories** — catch specific exceptions first (`StorageException`, etc.), then a generic `catch (error, stackTrace)` that logs and **rethrows**. Never swallow.
- **Notifier controllers** — catch all, `Sentry.captureException`, surface via `state = state.copyWith(errorMessage: ...)`.

inkBlox also models known data-consistency conditions as **typed exceptions that deliberately don't reach Sentry** — `PixelArtStorageObjectNotFoundException` for a DB row that outlived its storage object. Keeping expected-but-abnormal states out of your error budget is what makes Sentry usable. Your equivalent: a completion whose habit was deleted on another device.

---

## 12. CI, lint, and hooks

`.github/workflows/flutter.yml` runs on PRs and pushes to `develop` and `main`, with `concurrency: cancel-in-progress` so a new push doesn't queue behind a stale run:

1. `flutter pub get`
2. `touch .env.dev .env.stg .env.prod` (see §3)
3. `dart format --output=none --set-exit-if-changed .`
4. `flutter analyze`
5. `flutter test`

Pin the Flutter version explicitly (inkBlox is on `3.44.9` via `subosito/flutter-action@v2` with `cache: true`).

`analysis_options.yaml` is minimal — extends `package:flutter_lints/flutter.yaml` and registers the `custom_lint` analyzer plugin, which is what activates `riverpod_lint`.

`.githooks/pre-commit` is an interactive version bumper (major/minor/patch/none, always increments the build number, `git add`s `pubspec.yaml`). Installed with `git config --local core.hooksPath .githooks/`. Critically, it **detects the absence of a controlling TTY and exits 0** — without that guard, scripted and agent-driven commits abort under `set -e`. Keep that guard if you port the hook.

`scripts/coverage.sh` runs `flutter test --coverage`, filters generated files out of `lcov.info`, and emits an HTML report when `lcov`/`genhtml` are available. Optional branch coverage via `BRANCH_COVERAGE=1`.

---

## 13. Agent-facing documentation

inkBlox carries `CLAUDE.md` (at both the repo root and inside each worktree), `AGENTS.md`, and `.github/instructions/instructions.instructions.md`. The root `CLAUDE.md` exists mainly to stop an agent running `flutter` from a directory that has no `pubspec.yaml` — a nice example of documenting the trap rather than the happy path.

`AGENTS.md` is the substantive one: structure, naming table, code style, imports, Riverpod rules, error handling, logging, the repository pattern, testing, commit conventions, and backend rules. **Write this file in week one, not month three.** It is why the inkBlox codebase looks like one person wrote it.

There's also `.claude/agents/inkblox-ios-simulator-specialist/` with numbered per-screen playbooks (`01-auth-onboarding.md`, `02-app-shell.md`, …) for driving the iOS simulator. Worth replicating for the habit app, where the garden and the watering animation genuinely need visual verification that unit tests can't give you.

---

## 14. What the habit app needs that inkBlox doesn't have

| Need | Notes |
|---|---|
| **Local notification scheduling** | The evening check-in. `flutter_local_notifications` + `timezone`. Schedule locally rather than via push: the decision of *whether* to nudge depends on engine state that already lives on-device, and it works offline. |
| **A nudge ledger** | Autonomy is `completions on un-nudged expected occasions / un-nudged expected occasions`. That requires persisting **every expected occasion and whether it was nudged** — including the ones you deliberately skipped. The skipped nudges are the measurement instrument, so they must be recorded as first-class rows, not inferred from the absence of a notification. |
| **Notification actions** | The evening check-in's `Yes` / `Different day` should be answerable from the notification itself on both platforms. This changes the UX budget materially. |
| **Exact-alarm / permission handling on Android 12+** | Scheduled notifications need `SCHEDULE_EXACT_ALARM` or a graceful inexact fallback. Decide which, early. |
| **Animation infrastructure** | inkBlox has none. Watering, ambient sway, time-of-day light, droop transitions. Build a small `GardenTicker` abstraction so ambient animation can be globally throttled or disabled — for battery, for reduced-motion accessibility, and for widget tests. |
| **Reduced-motion + a11y** | inkBlox already treats a11y seriously (dedicated test suite, `a11y_labels.dart`). A garden whose entire feedback language is visual needs semantic labels for stage, vitality, and root depth. |
| **Time-of-day and DST correctness** | "Days since last completion" and "rolling 7 days" must be computed in the **user's local calendar days**, not UTC instants. Get this wrong and vitality droops at midnight UTC for half your users. Store timestamps as UTC, but do all window math against a local-date helper in `lib/core/`. |

### What you get to skip

The feed, likes, comments, reports, tags, per-viewer blocking, the moderation dashboard, user roles, and the pre-publication review flow — roughly a third of inkBlox's feature code and half its migration history. The age gate and its device-sticky ineligibility store are also probably unnecessary unless you're targeting minors.

---

## 15. Suggested domain layout

Mapping the specs onto inkBlox's proven structure. The key move: **`lib/core/engine/` is the new `lib/core/drawing/`** — same layered shape, same "pure Dart, no Flutter, heavily unit-tested" discipline.

```
lib/core/
  engine/
    domain.dart        # Stage, CueType, FrictionType, Framing, Occasion enums
    inputs.dart        # HabitInputs: target f, completions, reflections, nudges
    adherence.dart     # W_days, expected, A  (growth spec §2)
    ladder.dart        # stage advancement, θ/ρ tables  (§3)
    vitality.dart      # droop curve, grace/D per stage, C₇ ≥ f pace exemption  (§4)
    roots.dart         # weighted N, R_raw, convergence c, cue-type exemption  (§5)
    autonomy.dart      # un-nudged completion ratio, graduation predicate  (§6)
    constants.dart     # every tunable in one file, versioned
  models/
    habit.dart  completion.dart  reflection.dart  nudge.dart
  utils/
    local_dates.dart   # local-calendar day math — used by every window calculation
    flavor.dart

lib/features/
  habits/       # create, edit, pause, renegotiate target
  garden/       # home screen, plant rendering, watering interaction
  reflection/   # evening check-in, chips, insight surfacing
  insights/     # detection rules (reflection spec §6)
  notifications/# scheduling, permission, nudge ledger
  auth/  profile/  settings/
```

Put **every tunable number in `constants.dart`** — the θ and ρ columns, grace and D per stage, the priority threshold of 0.5, the 48h recency penalty, weekly budgets, nudge-fade rates. The growth spec explicitly calls them "calibrated defaults, meant to be tuned, not laws," and §9 lists four still-open. Give them one home and a version stamp so you can tune without hunting and without invalidating stored derivations.

### Schema sketch

```sql
habits         (id, user_id, name, identity_statement, plant_type,
                target_frequency, designed_cue, designed_cue_type,
                routine, reward, created_at, paused_at, graduated_at)
completions    (id uuid, habit_id, user_id, completed_at, was_nudged, source)
reflections    (id uuid, habit_id, user_id, occasion, framing,
                cue_reported, cue_type, matched_designed_cue,
                friction_reported, friction_type, input_mode,
                was_nudged, root_credit, created_at)
nudges         (id uuid, habit_id, user_id, scheduled_for, sent,
                confirmed, declined, expected_occasion_date)
habit_pauses   (id, habit_id, started_at, ended_at)
```

`reflections` maps one-to-one onto the record in reflection-logic §5. `nudges` rows exist for expected occasions **even when deliberately not sent** — that's the autonomy denominator.

---

## 16. Day-one checklist

```bash
# 1. Scaffold
flutter create --org com.<yourorg> --platforms ios,android <appname>
cd <appname>

# 2. Port config files from inkBlox (read-only source — copy, don't move)
#    analysis_options.yaml, .gitignore, .github/workflows/flutter.yml,
#    .githooks/pre-commit, scripts/coverage.sh, scripts/supabase-push.sh

# 3. pubspec.yaml — keep §1, drop §1, add §1; set up flavorizr
flutter pub get
flutter pub run flutter_flavorizr

# 4. Secrets
mkdir .secrets
#    .env.dev / .env.stg / .env.prod — SUPABASE_URL, SUPABASE_ANON_KEY, SENTRY_DSN,
#    SMTP_PASS, AUTH_EXTERNAL_APPLE_CLIENT_ID / _SECRET, OTP_EXPIRY
cp .secrets/.env.dev .env          # copy, not symlink — the app rewrites it

# 5. Backend
supabase init
supabase start
#    migrations: 0001_initial (habits/completions/reflections/nudges)
#                0002_rls
#                0003_new_user_trigger
supabase db reset

# 6. App skeleton — port these files near-verbatim
#    lib/main.dart, lib/main_{dev,stg,prod}.dart
#    lib/core/utils/flavor.dart
#    lib/app/logging/logging.dart
#    lib/app/supabase/supabase_client_provider.dart
#    lib/app/connectivity/connectivity_provider.dart
#    lib/app/startup/app_startup_{provider,widget}.dart
#    lib/app/theme/{app_colors,app_spacing,app_radius,app_dimensions,themedata}.dart
#    lib/app/router/app_router.dart  (gate contents rewritten)

# 7. Test harness
#    test/utils/supabase_test_utils.dart, test_http_overrides.dart,
#    connectivity_test_utils.dart  — port verbatim

# 8. Write AGENTS.md + CLAUDE.md before writing feature code

# 9. First real code: lib/core/engine/ + its worked-example tests
git config --local core.hooksPath .githooks/
flutter analyze && dart format --set-exit-if-changed . && flutter test
```

**Suggested build order.** Engine first (pure Dart, fully tested, no UI) → local SQLite store and repository interfaces → completion tap with local write → Supabase sync → notification scheduling and the nudge ledger → reflection check-in → garden rendering → insight surfacing. The garden is the emotional payload but it's also the part that depends on everything else being right, and it's blocked on the external illustrator anyway.

---

## 17. Things inkBlox got wrong that are worth not repeating

Honest notes from the read-through, offered as a list of traps rather than criticism:

1. **`provider` and `mocktail` sit in `dependencies`** — one dead, one belonging in `dev_dependencies`.
2. **`path: any` and `supabase: any`** — unbounded version constraints will eventually break a build with no code change.
3. **One 873-line service with a seven-concern interface.** Split by aggregate early (§6).
4. **A git-sourced dependency** (`open_mail`) with no pinned ref.
5. **Six migrations spent fixing RLS recursion.** Design policies against a written access matrix before the first one ships — trivial in your case, since everything is `user_id = auth.uid()`.
6. **A 27 KB `design_debt.md` and a 19 KB `accessibility_findings.md`.** Both are excellent documents and both exist because those concerns were retrofitted. Design tokens (`AppColors`/`AppSpacing`/`AppRadius`) and semantic labels are near-free at the start.
7. **`flutter analyze` was commented out of CI for a period** (it's back now). Keep the gate green from commit one; it's much harder to restore than to maintain.

---

## Sources

Everything above is from a read of `/Users/luukwitteman/Documents/inkblox/tree/main` and the repo root, plus the three product specs in the Habit app project.

Key files referenced: `CLAUDE.md` (root and worktree), `AGENTS.md`, `README.md`, `pubspec.yaml`, `analysis_options.yaml`, `lib/main.dart`, `lib/core/utils/flavor.dart`, `lib/app/**`, `lib/features/pixel_art/services/*.dart`, `supabase/migrations/*.sql`, `supabase/config.toml`, `supabase/functions/delete-account/index.ts`, `scripts/supabase-push.sh`, `scripts/coverage.sh`, `.github/workflows/flutter.yml`, `.githooks/pre-commit`, `test/utils/*.dart`.
