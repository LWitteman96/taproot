# Handoff: build and verify the sunflower's Rive assets

**For:** Claude Code, in the `feature/rive_animations` worktree
(`~/Documents/taproot/tree/feature/rive_animations`).
**From:** the session that drew the sunflower (2026-09-16).
**Status:** the sunflower's art has been drawn and reviewed as flat SVG. Its
RML has been generated and passes `check_rml.py`. **It has never been built
with the rive CLI.** Your job is to build it, prove that it behaves, ship
`sunflower.riv` into the app's assets, and document what you found.

This is the oak's handoff again, for a third plant. The oak went through every
step cleanly on the first attempt (`oak/NOTES.md`, "Step 2 — built"), so follow
the same route and reuse the same tools. The differences are listed in §2.

In your last commit, delete this file and restore `sunflower/CLAUDE.md` to
just `@AGENTS.md`, once this file's content lives in `sunflower/NOTES.md`,
`docs/status.md` and `docs/progress-log.md`.

---

## 0. Read first

1. `CLAUDE.md` (repo root) and `docs/status.md`.
2. `fern/NOTES.md`: **Traps**, **Previewing**, **Verification recipes**.
3. `oak/NOTES.md`: the whole file, especially "Step 2 — built". It is the
   recipe you are repeating: the SVG-vs-Rive render diff, `check_built.py`,
   `check_render.py`, the bench, and the `--advance` trap.
4. `sunflower/NOTES.md`: what the sunflower is and how it is built.
5. `sunflower/AGENTS.md`: the rive CLI contract. **Use `rive docs` and
   `rive schema`; never guess a type or property name.**

Reference renders are in `sunflower/Claude outputs/`:

| File | Shows |
|---|---|
| `sunflower-stages-with-roots.png` | the six stages at vitality 1, each over its root level |
| `sunflower-thirst-preview.png` | Seedling, Young, Mature and Bloom at vitality 1, 0.75, 0.5 and 0 (a simulation of the droop blend) |
| `garden-with-sunflower-art.png` | sunflowers beside ferns and oaks at garden scale (0.15) |

---

## 1. What is new on disk (uncommitted)

```
sunflower/                 NEW Rive CLI project (same layout as oak/)
  sunflower_generator.py   the source of truth for the sunflower
  check_rml.py             wrapper -> ../plantgen/check_rml.py
  preview.sh, rive.yaml, AGENTS.md, CLAUDE.md, .gitignore, NOTES.md, HANDOFF.md
  sunflower-*.rml / *.svg  generated
  Claude outputs/          reference renders
plantgen/check_rml.py      NEW: oak/check_rml.py made generic over the species
oak/check_rml.py           CHANGED: now a wrapper for the above (same output as before)
fern/NOTES.md              CHANGED: one new trap row (joint discs and winding)
docs/status.md             CHANGED: an "In progress: the sunflower" note pointing here
```

Nothing else in `plantgen/` changed, so the fern and oak outputs must be
byte-identical. Step 1 checks this.

---

## 2. What differs from the oak

1. **A lighter plant.** `SunflowerBloom` has 511 vertices and 43 shapes,
   against `OakMature`'s 4,952 vertices and 62 shapes. The render budget
   should be easy to meet, but bench it anyway: the oak showed that render
   cost follows shapes and paths.
2. **Nesting three deep on one stem:** `stem` → `stem-upper` → `head`, with
   two twins: `stem-upper-line` inside `stem`, and `head-line` inside
   `stem-upper`. The oak's twins were one level deep. The oak did prove nested
   pivots across three levels (trunk → limb → rosette).
3. **A droop far larger than anything before it.** At vitality 0 the head
   turns about 135° and the upper stem about 25°. Rive has not rotated
   anything past 32° in this project yet. Check that the head swings the
   right way (clockwise, to the right, ending *below* its neck) and passes
   smoothly through the blend.
4. **Joint discs are `Ellipse` shapes** (`*-joint`, `*-joint-line`) inside
   the stem parts, at the bend and at the neck. A bent joint must look solid,
   with no notch and no light gap.
5. **More colours fade:** petals, back petals, bracts and the stem fill, as
   well as the leaves. The disc does not fade.
6. **Names:** `Sunflower…` artboards, state machine `Sunflower`, view model
   `Sunflower`. `rive.yaml`'s `main` is `SunflowerBloom`.
7. **The lean goes right** (`+1`), like the fern's. The oak's goes left.
8. **Two of the oak's checkers are still oak-specific.** Make them generic
   first (step 2).

---

## 3. Steps

Work from the worktree root unless a step says otherwise. Fix problems in
`sunflower/sunflower_generator.py` (or `plantgen/`), **never in generated
files.**

### Step 1: regenerate and guard the other plants

```bash
git status
python3 fern/fern_generator.py && python3 oak/oak_generator.py
git diff --stat -- fern/ oak/     # expect only fern/NOTES.md and oak/check_rml.py
python3 oak/check_rml.py          # 8 files, 26796 ids, 13291 vertices, max error 0.017 px, 0 failures
python3 sunflower/sunflower_generator.py
python3 sunflower/check_rml.py    # 8 files, 9560 ids, 1578 vertices, max error 0.015 px, 0 failures
```

### Step 2: make the oak's checkers generic

- `oak/check_built.py` is already generic except for its cache path
  (`build/oak-inspect.json`). Name the cache after the project directory, and
  move the script to `plantgen/check_built.py` with a wrapper in `oak/`, the
  way `check_rml.py` is done.
- `oak/check_render.py` hard-codes `Oak` artboard names and the lean
  thresholds. Take the species from the project directory. Take the lean
  stages and thresholds from the species (`SPECIES.lean_threshold`). Take the
  bloom from stage 5. Move it to `plantgen/` with wrappers too.
- Rerun both on the oak. **They must give the same results as recorded in
  `oak/NOTES.md`**, so the refactor is proven before you rely on it for the
  sunflower.

### Step 3: verify, inspect, build

```bash
cd sunflower
rive . --verify                 # 0 errors, 0 warnings
rive inspect . --summary        # problems: [], seven artboards
rive . --once                   # build/sunflower.riv
python3 check_built.py          # after step 2
```

Expected type counts, taken from the generated RML. The oak matched its table
exactly.

| artboard | Node | Shape | PointsPath | StraightVertex | CubicDetachedVertex | Ellipse | LinearAnimation | StateMachineLayer | BlendState1DViewModel | BlendAnimation1D | KeyedObject | KeyFrameDouble | KeyFrameColor |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| SunflowerSeed | 5 | 7 | 7 | 0 | 20 | 4 | 4 | 2 | 2 | 4 | 4 | 28 | 0 |
| SunflowerSprout | 8 | 9 | 9 | 41 | 25 | 4 | 4 | 2 | 2 | 4 | 18 | 84 | 6 |
| SunflowerSeedling | 16 | 17 | 24 | 101 | 59 | 3 | 4 | 2 | 2 | 4 | 50 | 196 | 22 |
| SunflowerYoung | 24 | 33 | 57 | 232 | 136 | 7 | 6 | 3 | 3 | 6 | 86 | 310 | 40 |
| SunflowerMature | 28 | 40 | 78 | 260 | 193 | 7 | 6 | 3 | 3 | 6 | 104 | 366 | 50 |
| SunflowerBloom | 28 | 43 | 97 | 260 | 251 | 127 | 4 | 2 | 2 | 4 | 100 | 364 | 48 |
| SunflowerRoots | 48 | 47 | 47 | 2679 | 0 | 0 | 5 | 1 | 1 | 5 | 470 | 470 | 0 |

(`SunflowerRoots` has the same vertex count as `OakRoots` by coincidence:
both trees have 47 roots of 57 vertices each. The shapes are different.)

Record the `.riv` size and build time.

### Step 4: look at it

- Run `./preview.sh`, capture the seed at vitality 1 and 0, and capture
  `SunflowerRoots` at 0, 0.15, 0.3, 0.5 and 0.75. Open every image.
- Run the **SVG-vs-Rive render diff** from `oak/NOTES.md` (the recipe is in
  `fern/NOTES.md`) on all six stages and all four root levels. Pass: zero
  strongly-differing pixels.
- Compare vitality 0 with `sunflower-thirst-preview.png`. The stem stays
  upright at the ground and curves over above the bend. The head hangs to the
  right, below its neck. The leaves droop and fade. The petals turn dull straw.
- **Joints.** Crop the bend and the neck of `SunflowerYoung` and
  `SunflowerBloom`: at vitality 1, 0.5 and 0, and at sway frames 1, 75, 150
  and 225. Pass: no notch, no light gap, no outline across the stem, and no
  outline showing offset from its fill.
- **Pivots.** A drooped leaf stays on its stalk joint, the head stays on its
  neck, and the upper stem stays on the lower one.

Any difference from the reference renders is a bug, not an art choice.
**Do not change the art or the motion tuning without asking Luuk.**

### Step 5: A/B (the generic `check_render.py`)

Use the same checks as the oak, with the sunflower's names:

- droop bound on Sprout…Bloom;
- healthy captured twice is identical;
- sway runs on every stage, and survives at vitality 0;
- the seed shows **0 px** difference across vitality, and still rocks;
- five distinct root poses, and roots 0.75 vs 1 identical;
- lean bound on Young (0 vs 0.3) and Mature (0 vs 0.5), and stops at the
  threshold;
- Bloom never leans.

Also check:

- **Lean direction:** the plant's x-centroid moves **right** between roots 1
  and roots 0.
- **Head swing:** on `SunflowerBloom` at vitality 0, the disc centre is right
  of the neck and below it. Measure it: find the centroid of the disc-brown
  pixels.
- **Smoothing:** the listener scaffold on `SunflowerBloom`. Mind the
  `--advance` trap from the oak. Remove the scaffold afterwards.

### Step 6: bench

Bench every artboard, 600 frames. Budget: advance ≤ 0.10 ms, render ≤
0.30 ms, no memory growth.

Re-bench `FernMature` in the same session. The oak found the machine's speed
drifting between sessions, so compare like with like. If anything is over
budget, stop and report the numbers to Luuk before changing anything.

### Step 7: ship the asset

```bash
cp sunflower/build/sunflower.riv assets/rive/sunflower.riv
```

- Add the file to `pubspec.yaml` beside the fern's and the oak's, with the
  same comment style.
- Add `test/features/garden/sunflower_asset_test.dart`, modelled on
  `oak_asset_test.dart`, pinning the names.
- The three gates must stay green.

**Out of scope:** making the garden *draw* sunflowers. `plant_art.dart` is
still fern-only; that task is already listed for the oak.

### Step 8: document

- **`sunflower/NOTES.md`:** add "Step 2 — built" in the same shape as the
  oak's (verify and inspect, counts, render diff, joints, A/B, lean and
  head-swing measurements, smoothing, bench). Update "Weight" with measured
  numbers. Answer the open calibration questions *only* with what motion
  showed you; the decisions stay Luuk's.
- **`fern/NOTES.md`:** add any new silent failure to Traps, and name the
  plant it was found on.
- **`docs/status.md`:** replace the "In progress: the sunflower" note. Three
  species now have generated art; list which `.riv` files ship, and say the
  garden still draws only the fern.
- **`docs/progress-log.md`:** add one new entry at the top, covering the
  sunflower's art session and this build.
- **`CLAUDE.md`:** add `sunflower/` to "Target structure", next to `oak/`.

### Step 9: commit

Run `git status` first. Never commit `build/` or `__pycache__/`. Suggested
commits:

1. `make rml checker generic across species`: `plantgen/check_rml.py`,
   `oak/check_rml.py`, plus the generic `check_built`/`check_render` from
   step 2
2. `add sunflower generator and art`: `sunflower/` sources, generated files,
   `Claude outputs/`, and the `fern/NOTES.md` trap row
3. `build sunflower.riv into the app assets`: the asset, `pubspec.yaml`, the
   asset test, the docs, the deletion of this file, and `CLAUDE.md` restored

Keep the three gates green at every commit. Do not push unless Luuk asks.

---

## 4. If something goes wrong

- **A build or render problem:** fix it in the generator, rerun
  `check_rml.py`, and rebuild. If the fix is in `plantgen/`, rerun the step 1
  guard.
- **The head swings the wrong way, or not about its neck:** check the
  `head` / `head-line` nodes' `x`/`y` in the RML against the neck point
  `(524, 320)`, relative to `stem-upper`'s pivot. `check_rml.py` already
  confirms that vertices land where the model puts them.
- **A 135° blend looks wrong mid-way** (for example, the head flipping
  through the stem): Rive blends the two keyed values linearly, so this should
  not happen. If it does, write the exact capture down, and ask Luuk before
  changing the angle.
- **You are unsure whether a difference is a bug or the art:** ask Luuk, and
  show both images.
