# CLAUDE.md

Guidance for Claude Code (claude.ai/code) when working in this repository.

Taproot is a Flutter + Supabase habit app built around making the **cue → routine → reward** loop an
explicit object the user designs and refines. See [README.md](README.md) for the product idea.

---

## Current state — read this first

**The app is early. Read [docs/progress-log.md](docs/progress-log.md) for what actually exists.**

At the time of writing: flavors, CI and the pre-commit hook are wired up, the **growth engine is
built and reviewed** (`lib/core/engine/`, `lib/core/models/`, `lib/core/utils/`), and so is the
**local SQLite store** — `lib/app/database/` plus `HabitRepository`, `CompletionRepository`,
`ReflectionRepository` and `NudgeRepository` under `lib/features/`, with a `HabitInputsLoader`
feeding the engine. 358 tests under `test/unit/`. There is no Supabase project, and no feature
has a page yet: `lib/features/*` holds `domain/`, `services/` and `providers/` only.

Do not assume a directory exists because it appears below — the structure is the **target**, taken
from [docs/infrastructure-guide.md](docs/infrastructure-guide.md) §15. Check the progress log, then
check the disk.

The three gates — `flutter analyze`, `dart format --output=none --set-exit-if-changed .`, and
`flutter test` — are currently green. **Keep them green from commit one.** The infrastructure guide
(§17) notes that inkBlox let `flutter analyze` lapse in CI and it was far harder to restore than to
maintain.

---

## The specs are the source of truth

This project is spec-first: the product thinking is finished and pressure-tested, the code is not.
Before implementing anything, read the governing document.

| Document | Governs |
|---|---|
| [docs/design-spec.md](docs/design-spec.md) | Concept, the garden metaphor, visual and UX direction |
| [docs/growth-engine.md](docs/growth-engine.md) | Stage / vitality / roots / autonomy — every formula |
| [docs/reflection-logic.md](docs/reflection-logic.md) | Prompt scheduling, framings, cue and friction taxonomies, insight rules |
| [docs/starter-chip-library.md](docs/starter-chip-library.md) | Chip content and the first-reflection surfacing rule |
| [docs/infrastructure-guide.md](docs/infrastructure-guide.md) | Every stack and architecture decision, with rationale |
| [docs/progress-log.md](docs/progress-log.md) | What is built, what it decided, what comes next |

Two rules about the specs:

- **Their numbers are calibrated defaults, not laws.** Every one belongs in `constants.dart` (see
  below), never inlined at a call site.
- **Their open calibration questions are real open questions.** Where a spec says something is
  untested or unresolved, don't quietly pick an answer and present it as settled — implement the
  default, and say which question you're leaving open.

---

## Target structure

```
lib/
  app/        # App-wide wiring: theme, router, logging, startup, supabase, connectivity
  core/       # Pure domain — THE GROWTH ENGINE, models, utils. No Flutter imports.
  features/   # habits, garden, reflection, insights, notifications, auth, profile, settings
  shared/     # Reusable UI (buttons, inputs, nav shell)
  widgets/    # Garden rendering widgets
test/
  unit/       # ProviderContainer only, no widget tree
  features/   # Widget tests mirroring lib/features
  widgets/
  utils/      # FakeXxx services, Supabase mocks, HTTP overrides
supabase/
  migrations/ # Timestamped SQL
  functions/  # Deno edge functions
docs/         # The five specs
scripts/      # coverage.sh, supabase-push.sh
```

Each feature under `lib/features/<name>/` contains `pages/`, `providers/` or `controllers/`,
`services/`, `domain/`, `widgets/`.

---

## Taproot-specific rules

These are the decisions most likely to be got wrong by defaulting to habit. They matter more than the
style rules further down.

### The engine is pure Dart

`lib/core/engine/` must have **no Flutter dependency and no I/O**. Inputs are completions,
reflections, and nudge records; outputs are stage, vitality, roots, autonomy. This is what makes it
exhaustively testable, and it is the highest-value test target in the app.

**Write the specs' worked examples as tests before the engine exists.** They are a specification and
a test suite at the same time — f=3 reaching Young at 5 completions in a 19-day window; a seedling
drooping at 2.8 days and fully wilting at 5.8; `N/(N+4)` giving 0.50 at 4 and 0.83 at 20. They will
catch every off-by-one in the window arithmetic.

Also test explicitly: the pace exemption (`C₇ ≥ ⌈0.8f⌉` ⇒ vitality 1.0 regardless of gap), paused
days excluded from every window, and **stage monotonicity under any input sequence**.

### Every tunable lives in `constants.dart`, with a version stamp

The θ and ρ columns, grace and D per stage, the 0.5 priority threshold, the 48h recency penalty,
weekly budgets, nudge-fade rates, chip priors. One home, one version. Tuning them must never require
a data migration.

### Derived values are computed, never stored

Stage, vitality, roots, and autonomy are **derivations**, not columns. Store them only as a cache
keyed by the engine constants version — otherwise tuning a constant silently invalidates stored data.

### All window math is in local calendar days

"Days since last completion" and "rolling 7 days" are **local-calendar** quantities. Store timestamps
as UTC, but do every window calculation through a local-date helper in `lib/core/utils/local_dates.dart`.
Get this wrong and vitality droops at midnight UTC for half the users.

### SQLite is the primary store, not a cache

This is a stronger position than inkBlox takes, and it's deliberate. **A completion tap must never
fail, never spin, and never be lost.** Every read is local and synchronous-feeling; every write is
local-then-queued. Supabase is durable backup and cross-device sync.

Completions are **append-only events keyed by `(habit_id, local_uuid)`** with the UUID generated
client-side before insert, so multi-device sync is a *union*, not a merge. This one decision removes
essentially all conflict handling — don't undo it.

### The nudge ledger records occasions that were deliberately *not* nudged

Autonomy's denominator is un-nudged expected occasions. That means a `nudges` row must exist for
every expected occasion **including the ones the engine chose to stay silent on**. The skipped nudges
are the measurement instrument; they cannot be inferred from the absence of a notification.

### Split repositories by aggregate from day one

`HabitRepository`, `CompletionRepository`, `ReflectionRepository` — separately. It will feel like
over-structuring. inkBlox's counter-example is a single 873-line service behind a seven-concern
interface (infrastructure guide §6, §17).

### Notification permission denial is an app mode, not an error

The engine measures autonomy by *withholding* nudges, which presupposes nudges were granted. Handle
the denied-permission state as a real, designed mode — not a toast.

### Reduced motion and semantics are not retrofits

The garden's entire feedback language is visual, so stage, vitality, and root depth need semantic
labels. Build ambient animation behind a `GardenTicker` abstraction that can be globally throttled or
disabled — for battery, for accessibility, and so widget tests aren't fighting a running animation.

---

## Commands

```bash
flutter pub get
flutter run                  # flavors not wired up yet

flutter analyze
dart format .
flutter test
flutter test test/unit/engine/vitality_test.dart   # single file
flutter test --name "pace exemption"               # by name
flutter test --coverage
```

Once flavors land, entry points become
`flutter run --flavor dev -t lib/main_dev.dart` (and `stg` / `prod`).

`.env.dev`, `.env.stg`, and `.env.prod` are gitignored **and** declared as assets in `pubspec.yaml`,
which means `flutter analyze` fails in a clean checkout until they exist. CI handles this with
`touch .env.dev .env.stg .env.prod`.

---

## Naming

| Thing | Convention | Example |
|---|---|---|
| Dart files | `lower_snake_case.dart` | `vitality.dart` |
| Classes / enums | `UpperCamelCase` | `HabitInputs`, `Stage` |
| Enum values | `lowerCamelCase` | `Stage.seedling`, `CueType.event` |
| Variables / functions | `lowerCamelCase` | `rootDepth`, `computeVitality()` |
| Providers | `lowerCamelCase` + `Provider` | `habitControllerProvider` |
| Test files | mirror source path + `_test.dart` | `test/unit/engine/roots_test.dart` |

**Never use abbreviations as variable names.** Full, descriptive names, always. The engine is full of
single-letter symbols in the spec (`f`, `G`, `C₇`, `θ`, `ρ`, `c`) — in code these get real names
(`targetFrequency`, `expectedGapDays`, `completionsLastSevenDays`), with the spec symbol in a comment.

---

## Code style

- 2-space indent; run `dart format .` before committing.
- `@immutable` on all state and domain classes.
- **No code generation.** No `freezed`, no `json_serializable`, no `build_runner`. Write `copyWith()`,
  `fromJson()`, and `toJson()` by hand. This is deliberate — it keeps `build_runner` out of the loop
  entirely, which matters most when an agent is editing the code.
- Nullable fields in `copyWith` use thunks, to distinguish "not provided" from "set to null":
  ```dart
  HabitState copyWith({DateTime? Function()? pausedAt}) =>
      HabitState(pausedAt: pausedAt != null ? pausedAt() : this.pausedAt);
  ```
- Prefer `switch` expressions over if/else chains when exhausting an enum.
- Keep widgets `const` wherever possible.
- Absolute package imports (`package:taproot/...`); relative only within the same directory.
- Alias `dart:developer` as `dev`.

---

## Riverpod

- `NotifierProvider<Controller, State>(Controller.new)` for controllers; `Provider<T>` for DI;
  `FutureProvider<void>` for async startup.
- `ref.watch` in widgets, `ref.read` in methods; inject dependencies in `Notifier.build()` via
  `ref.read`.
- **Add selector providers next to any large state object.** This matters more here than in inkBlox:
  the garden screen watches many derived values off one habit-state object, and a completion tap on
  one plant must not rebuild the whole garden.
  ```dart
  final habitStageProvider = Provider.family<Stage, String>((ref, habitId) =>
      ref.watch(gardenControllerProvider.select((s) => s.habits[habitId]!.stage)));
  ```

---

## Repository / service pattern

```dart
abstract class HabitRepository { /* interface */ }
class HabitService implements HabitRepository { /* Supabase impl */ }

final habitServiceProvider = Provider<HabitRepository>(
  (ref) => HabitService(supabase: ref.watch(supabaseClientProvider)),
);
```

`supabaseClientProvider` is a three-line `Provider<SupabaseClient>` whose only job is to be
overridable in tests. Provide a `FakeHabitService` in `test/utils/`.

---

## Error handling

- **Services / repositories** — catch specific exceptions first, then a generic
  `catch (error, stackTrace)` that logs and **rethrows**. Never swallow.
- **Notifier controllers** — catch all, `Sentry.captureException`, surface via
  `state = state.copyWith(errorMessage: ...)`.
- Model known data-consistency conditions as **typed exceptions that deliberately don't reach
  Sentry** — e.g. a completion whose habit was deleted on another device. Keeping expected-but-
  abnormal states out of the error budget is what keeps Sentry usable.

## Logging

- **Core domain controllers** → `dart:developer` `dev.log()` via a small `_log(action, msg)` helper.
- **Services and feature providers** → `package:logging` `Logger('ServiceName')`, one per class.

---

## Testing

- **Unit tests** (`test/unit/`) use `ProviderContainer` only — never a widget tree:
  ```dart
  final container = ProviderContainer(overrides: [
    habitServiceProvider.overrideWithValue(FakeHabitService()),
  ]);
  addTearDown(container.dispose);
  ```
- Widget tests mirror the source tree under `test/features/` and `test/widgets/`.
- `mocktail` for mocking, `sqflite_common_ffi` to run the real database in-process,
  `mock_supabase_http_client` for Supabase.
- Cover edge cases, not just happy paths — especially in the engine, where the edge cases *are* the
  spec.

---

## Backend

- Migrations are hand-written, timestamped SQL in `supabase/migrations/`. No ORM, no schema diffing.
- **Migrations must be idempotent and re-runnable** — drop policies inside a
  `DO $$ ... IF EXISTS ... END $$;` block before recreating, and use `CREATE INDEX IF NOT EXISTS`.
- Every table has RLS enabled with explicit grants. Taproot's access matrix is trivial —
  **every table is `user_id = auth.uid()`, full stop** — because there is no social graph.
- Wrap the auth call as `(SELECT auth.uid())`, which lets Postgres cache it per-statement rather than
  per-row.
- Port the `delete-account` edge function early, not at submission time. App Store Review Guideline
  5.1.1(v) requires in-app account deletion, and it's the most common cause of a first-review
  rejection.

---

## Security — this repository is public

- **Never commit secrets.** Real values live in `.secrets/` (gitignored); `.env*` files are gitignored
  and populated from there.
- `.gitignore` guards `.env*`, `.secrets/`, `android/key.properties`, `**/google-services.json`,
  `**/GoogleService-Info.plist`, `sentry.properties`, and `.mcp.json`. If you add a new class of
  credential file, add it to `.gitignore` in the same commit.
- On a public repo a secret committed once is compromised even if later removed, because the object
  stays in history and is indexed within minutes. Check `git status` before staging.

---

## Commits

Short, lowercase, imperative — `add vitality droop curve`, `split habit repository by aggregate`.
Keep the three gates green in every commit.
