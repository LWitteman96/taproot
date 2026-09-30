# Handoff: build and verify the lavender's Rive assets

**For:** Claude Code, in the `feature/rive_animations` worktree
(`~/Documents/taproot/tree/feature/rive_animations`).
**From:** the session that drew the lavender (2026-09-22).
**Status:** the lavender's art has been drawn and reviewed as flat SVG. Its
RML has been generated and passes `check_rml.py`. **It has never been built
with the rive CLI.** Your job is to build it, prove it behaves, ship
`lavender.riv` into the app's assets, and write up what you found.

This is the fourth run of the same job. The oak's run is written up in
`oak/NOTES.md`, "Step 2 — built". Follow that route and reuse its tools. The
differences are in §2.

**Order matters.** If `sunflower/HANDOFF.md` still exists, do that one first,
completely. It turns the oak's two Rive checkers into shared tools in
`plantgen/`, and this handoff assumes that has happened.

In your last commit, delete this file and set `lavender/CLAUDE.md` back to
just `@AGENTS.md`. Do that once this file's content lives in
`lavender/NOTES.md`, `docs/status.md` and `docs/progress-log.md`.

---

## 0. Read first

1. `CLAUDE.md` (repo root) and `docs/status.md`.
2. `fern/NOTES.md`: the **Traps**, **Previewing** and **Verification
   recipes** sections.
3. `oak/NOTES.md`, "Step 2 — built". This is the recipe you are repeating: the
   SVG-vs-Rive render diff, `check_built`, `check_render`, the bench, and the
   `--advance` trap.
4. `lavender/NOTES.md`: what the lavender is and how it is built.
5. `lavender/AGENTS.md`: the rive CLI contract. **Use `rive docs` and
   `rive schema`, and never guess a type or property name.**

Reference renders are in `lavender/Claude outputs/`:

| File | Shows |
|---|---|
| `lavender-stages-with-roots.png` | the six stages at vitality 1, each over its root level |
| `lavender-thirst-preview.png` | Seedling, Young, Mature and Bloom at vitality 1, 0.75, 0.5 and 0 (a simulation of the droop blend) |
| `garden-with-lavender-art.png` | all four plants at garden scale (0.15) |

---

## 1. What is new or changed on disk (uncommitted)

```
lavender/                  NEW Rive CLI project (same layout as sunflower/)
  lavender_generator.py    the source of truth for the lavender
  check_rml.py             wrapper -> ../plantgen/check_rml.py
  preview.sh, rive.yaml, AGENTS.md, CLAUDE.md, .gitignore, NOTES.md, HANDOFF.md
  lavender-*.rml / *.svg   generated
  Claude outputs/          reference renders
plantgen/species.py        CHANGED: a part may state its droop, meta["droop_degrees"]
docs/status.md             CHANGED: an "In progress: the lavender" note pointing here
```

The `plantgen/species.py` change is inert for the other three plants. Step 1
proves it by checking that their generated files are byte-identical.

---

## 2. What differs from the plants before it

1. **Structurally the simplest since the fern.** Every part pivots at the
   base. There is no nesting and there are no twins.
2. **Ellipse-heavy.** A flower spike is made of ellipses (`Dots` in the model,
   `Ellipse` in RML): 597 in `LavenderMature` and 642 in `LavenderBloom`. The
   oak's bloom had 315, so this is the most `Ellipse` any artboard has had.
   The spike's outline is a layer of slightly larger dark ellipses behind the
   florets. **Check it renders as one outline around each spike, with no
   floret missing its ring.**
3. **The floret colours fade**, as do the foliage, wand stems and seed leaves.
   Fading means a `KeyFrameColor` on each `Dots` shape's `SolidColor`. Dots
   paints go through the same `paints` registry as paths, but no plant has
   faded a `Dots` shape before. The sunflower's disc does not fade, and
   neither do the oak's acorns. **Prove that the florets actually change
   colour between vitality 1 and 0.**
4. **Wands state their droop outright** (`meta["droop_degrees"]`). The spray
   splays: the outer wands fall about 31° and the centre ones about 7°, with
   no gap opening down the middle.
5. **Render cost is the risk.** `LavenderBloom` has 60 shapes, close to
   `OakMature`'s 62, and the oak was over the render budget. Expect this
   artboard to be the one that fails the bench.
6. **The lean goes left** (`-1`), as the oak's does.
7. **Names:** `Lavender…` artboards, the state machine `Lavender`, the view
   model `Lavender`. `rive.yaml`'s `main` is `LavenderBloom`.

---

## 3. Steps

Work from the worktree root unless told otherwise. Fix problems in
`lavender/lavender_generator.py` (or in `plantgen/`), **never in generated
files.**

### Step 1: regenerate and guard the other plants

```bash
git status
for p in fern oak sunflower; do (cd $p && python3 ${p}_generator.py >/dev/null); done
git diff --stat -- fern/ oak/ sunflower/     # no generated .rml/.svg may appear
python3 oak/check_rml.py        # 8 files, 26796 ids, 13291 vertices, max error 0.017 px, 0 failures
python3 sunflower/check_rml.py  # 8 files, 9560 ids, 1578 vertices, max error 0.015 px, 0 failures
python3 lavender/lavender_generator.py
python3 lavender/check_rml.py   # 8 files, 15010 ids, 4899 vertices, max error 0.007 px, 0 failures
```

If `sunflower/` has been committed, the diff must be empty for all three
plants. If not, it may show only the files the sunflower handoff lists as
changed. In both cases, no generated `.rml` or `.svg` file may differ.

### Step 2: verify, inspect, build

```bash
cd lavender
rive . --verify                 # 0 errors, 0 warnings
rive inspect . --summary        # problems: [], seven artboards
rive . --once                   # build/lavender.riv
python3 ../plantgen/check_built.py .   # or the path the sunflower run gave it
```

Expected type counts, from the generated RML. The oak matched its table
exactly.

| artboard | Node | Shape | PointsPath | StraightVertex | CubicDetachedVertex | Ellipse | LinearAnimation | StateMachineLayer | BlendState1DViewModel | BlendAnimation1D | KeyedObject | KeyFrameDouble | KeyFrameColor |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| LavenderSeed | 5 | 7 | 5 | 0 | 16 | 4 | 4 | 2 | 2 | 4 | 4 | 28 | 0 |
| LavenderSprout | 10 | 6 | 6 | 41 | 19 | 3 | 4 | 2 | 2 | 4 | 24 | 112 | 8 |
| LavenderSeedling | 6 | 4 | 25 | 98 | 91 | 3 | 4 | 2 | 2 | 4 | 12 | 56 | 4 |
| LavenderYoung | 20 | 11 | 127 | 441 | 471 | 3 | 6 | 3 | 3 | 6 | 56 | 254 | 18 |
| LavenderMature | 46 | 51 | 218 | 1078 | 783 | 597 | 6 | 3 | 3 | 6 | 170 | 618 | 80 |
| LavenderBloom | 46 | 60 | 218 | 1078 | 783 | 642 | 4 | 2 | 2 | 4 | 186 | 616 | 98 |
| LavenderRoots | 50 | 49 | 49 | 2793 | 0 | 0 | 5 | 1 | 1 | 5 | 490 | 490 | 0 |

Record the `.riv` size and the build time.

### Step 3: look at it

- Run `./preview.sh`. Capture the seed at vitality 1 and 0, and
  `LavenderRoots` at roots 0, 0.15, 0.3, 0.5 and 0.75. Open every image.
- Run the **SVG-vs-Rive render diff** (the recipe is in `fern/NOTES.md`) on
  all six stages and all four root levels. Pass: zero strongly-differing
  pixels. The ellipses are the new thing here, so pay attention to the spikes.
- At vitality 0, compare against `lavender-thirst-preview.png`:
  - the spray splays evenly outward, with no gap down the middle;
  - the cushion slumps only slightly;
  - the silver-green goes to straw;
  - the purple goes to a faded grey-lilac.
- Crop a spike from `LavenderBloom` at vitality 1 and 0, and at sway frames 1,
  75, 150 and 225. Each spike should have one dark outline around it, and the
  florets must stay on their wand as it sways and droops.

A difference from the reference renders is a bug, not an art choice. **Do not
change the art or the motion tuning without asking Luuk.**

### Step 4: A/B (the shared `check_render`)

Run the same checks as the oak and sunflower, with the lavender's names:

- droop bound on Sprout…Bloom;
- healthy twice gives identical renders;
- sway runs on every stage, and survives at vitality 0;
- the seed shows **0 px** difference across vitality, and still rocks;
- five distinct root poses, with roots 0.75 vs 1 identical;
- the lean is bound on Young (roots 0 vs 0.3) and Mature (0 vs 0.5), and stops
  at the threshold;
- Bloom never leans.

Also:

- **Lean direction:** the plant's x-centroid moves **left** between roots 1
  and roots 0.
- **Florets fade:** on `LavenderBloom`, count purple pixels at vitality 1 and
  at vitality 0. Hue-select the spikes, or diff only the region above the
  cushion. The colour must change, not only the position.
- **Splay:** the leftmost spike's centroid moves left and down, the rightmost
  moves right and down, and the centre spikes move the least.
- **Smoothing:** use the listener scaffold on `LavenderBloom`. Mind the
  `--advance` trap. Remove the scaffold afterwards.

### Step 5: bench

Bench every artboard for 600 frames. The budget is advance ≤ 0.10 ms, render
≤ 0.30 ms, and no memory growth. Re-bench `FernMature` in the same session so
you compare like with like.

**If `LavenderBloom` or `LavenderMature` is over budget, stop and report the
numbers to Luuk.** Do not slim anything. The levers are listed in
`lavender/NOTES.md` under "Weight", and every one of them changes the look.

### Step 6: ship the asset

```bash
cp lavender/build/lavender.riv assets/rive/lavender.riv
```

- Add the asset to `pubspec.yaml` beside the others, in the same comment
  style.
- Add `test/features/garden/lavender_asset_test.dart`, modelled on the oak's
  and the sunflower's.
- The three gates must stay green.

**Out of scope:** making the garden *draw* lavender. `plant_art.dart` is still
fern-only, and that task is already on the list.

### Step 7: document

- **`lavender/NOTES.md`:** add "Step 2 — built" in the oak's shape. Include
  the counts, the render diff, the spike crops, the A/B results (with the
  floret fade and the splay measurements), smoothing and the bench. Update
  "Weight" with the measured numbers. Answer the open questions only with what
  motion showed. The decisions stay Luuk's.
- **`fern/NOTES.md`:** add any new silent failure to Traps, naming the plant
  it was found on.
- **`docs/status.md`:** replace the "In progress: the lavender" note. Four
  species now have generated art. List which `.riv` files ship, and note that
  the garden still draws only the fern.
- **`docs/progress-log.md`:** add one new entry at the top, covering the
  lavender's art session and this build, including the
  `meta["droop_degrees"]` addition to `plantgen/`.
- **`CLAUDE.md`:** add `lavender/` to "Target structure".

### Step 8: commit

Run `git status` first. Never commit `build/` or `__pycache__/`. Suggested
commits:

1. `let a plant part state its droop`: `plantgen/species.py`
2. `add lavender generator and art`: the `lavender/` sources, generated files
   and `Claude outputs/`
3. `build lavender.riv into the app assets`: the asset, `pubspec.yaml`, the
   asset test, the docs, the deletion of this file, and `lavender/CLAUDE.md`
   restored

The three gates must stay green at every commit. Do not push unless Luuk
asks.

---

## 4. If something goes wrong

- **A build or render problem:** fix it in the generator, rerun
  `check_rml.py`, and rebuild. If the fix is in `plantgen/`, rerun the step 1
  guard for all three other plants.
- **Florets do not fade:** check that each `Dots` shape's `SolidColor` id is
  keyed in both the `Upright` and `Drooped` animations (`propertyKey` 37,
  `KeyFrameColor`). `check_built` lists what each animation keys.
- **Spike outlines look broken:** the outline layer is the florets 2 px larger
  in `#3D2E57`, drawn first within the wand. Check the shape order inside the
  wand node. In RML, the first shape declared paints on top.
- **You are unsure whether a difference is a bug or the art:** ask Luuk, and
  show both images.
