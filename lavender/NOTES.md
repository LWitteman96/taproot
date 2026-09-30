# Lavender — notes

The fourth plant on `../plantgen`. Everything in
[`../fern/NOTES.md`](../fern/NOTES.md) holds here, along with what
[`../oak/NOTES.md`](../oak/NOTES.md) and
[`../sunflower/NOTES.md`](../sunflower/NOTES.md) added. This file covers only
what the lavender adds.

```
lavender_generator.py    the lavender: palette, leaves, shoots, wands, stages, roots, motion
check_rml.py             wrapper for ../plantgen/check_rml.py
preview.sh               ../sunflower/preview.sh with the species swapped
rive.yaml                name: lavender, main: LavenderBloom
lavender-*.rml / *.svg   generated
Claude outputs/          reference renders for review
```

**Edit the generator, never the output.**

```bash
python3 lavender_generator.py && python3 check_rml.py
```

Public surface: view model `Lavender` (`vitality`, `roots`), state machine
`Lavender`, artboards `LavenderSeed` … `LavenderBloom` and `LavenderRoots`.

---

## Why a lavender, and what it is for

It is the garden's short plant: a low silvery cushion with a spray of thin
wands above it. It is the only silhouette that is wider than it is tall, and
the only colour in the garden that is not green, ochre or yellow. Its
character line, "unfussy, and better for being cut back", suits wind-down
habits: rest, sleep, switching off.

Structurally it goes back to the fern: every part grows out of the ground and
pivots at the base. No nesting, no twins.

## The stages

- **Seed.** A small, dark, glossy oval in the shared seed bed. Ignores
  vitality.
- **Sprout.** A short stem with two round seed leaves, each its own part, and
  the first pair of narrow true leaves between them.
- **Seedling.** One upright leafy shoot and a smaller one leaning out beside
  it.
- **Young.** A cushion of nine leafy shoots. No flowers.
- **Mature.** A cushion of thirteen shoots and a spray of nine wands, in
  grey-lilac bud.
- **Bloom.** The same, with the spikes open and purple, and light highlights
  on alternate whorls.

Mature and Bloom share their geometry exactly. The bloom is a colour change,
which keeps the step from mature to bloom a reward rather than a redraw.

## How it is built

- **Foliage is laid out on a fan.** `fan()` puts each shoot's tip on a
  half-ellipse around the base. Each shoot leaves the base steeply and bends
  out, so the cushion is dome-shaped whatever the count. Every other inner
  shoot is darker and drawn first, which gives the dome depth.
- **One shape per shoot.** A shoot's stem and all its leaves (opposite pairs,
  plus a small terminal tuft) are one path in one colour. They are the same
  silver-green on the real plant, and it keeps thirteen shoots at thirteen
  shapes.
- **Spikes are ellipses.** Each wand's spike is whorls of three florets,
  spaced wider toward the bottom. The gaps between the lower whorls are what
  make it read as lavender rather than a bottle brush. A spike is drawn in
  up to four shapes:
  - an **outline layer**: the same florets 2 px larger, in dark purple, behind
    the rest, so overlapping florets share one outline (the two-pass idea
    from the oak's wood, done with ellipses);
  - the side florets, darker;
  - the front florets;
  - the highlights (bloom only).
- **The wands rise from inside the cushion.** They are drawn after the back
  shoots and before the front ones, so their bare lower stems disappear into
  the foliage.

## Droop: stated per wand

The shared rule (the more upright a part, the further it falls) would drop
the centre wands most and open a gap down the middle of the spray. That is the
oak's crown-splitting problem again. A thirsty lavender does the opposite: the
spray **splays**. The outer wands flop furthest and the centre ones barely
lean. So each wand states its droop outright through a new part field,
`meta["droop_degrees"]`: `WAND_DROOP_MIN` (6°) plus `WAND_DROOP_SPLAY` (24°)
scaled by how far out the wand already leans. That gives about ±7° at the
centre and ±31° at the edges.

Shoots use the shared rule with a small scale (0.45), so the cushion slumps
slightly. Thirst mostly shows as pallor: the silver goes toward straw and the
purple toward a faded grey-lilac. That fits a dry-climate plant, but the
floppy wands are what reads at garden scale.

Droop at vitality 0 (+ is clockwise):

| stage | parts |
|---|---|
| Sprout | stem +11.1, cotyledons −5.0 / +5.0, first leaves −30.0 |
| Seedling | side shoot −8.3, main shoot +11.1 |
| Young | shoots −9.7 … +10.9 |
| Mature, Bloom | wands −30.3, −24.8, −18.7, −10.7, −7.2, +10.9, +18.1, +23.9, +31.3; shoots −9.8 … +10.8 |

The lean goes **left** (`-1`), as the oak's does.

## Shared change this made

**`plantgen/species.py`: `meta["droop_degrees"]`.** A part can state its droop
at vitality 0 in degrees, overriding the formula. This is inert for every
other plant: the fern, oak and sunflower outputs are byte-identical before and
after the change. It is the second way a generator can override the shared
droop (the first was `meta["droop_direction"]`, from the oak). It also answers
open question 2 in `../sunflower/NOTES.md`: a per-part angle is available now,
if the sunflower's head scale of 5.6 ever wants replacing.

## The roots

There is no taproot. Seven woody main roots fan downward and spread wider than
they go deep, each with branches and branchlets. The primaries are ordered
centre-out, so the low levels show the deep middle roots first.

| level | length | generations | primaries |
|---|---|---|---|
| 1 | 0.32 | 1 | 3 |
| 2 | 0.55 | 2 | 5 |
| 3 | 0.78 | 2 | 7 |
| 4 | 1.00 | 3 | 7 |

## Weight

| artboard | RML | vertices | shapes | ellipses |
|---|---|---|---|---|
| `LavenderYoung` | 174 KB | 912 | 11 | 3 |
| `LavenderMature` | 427 KB | 1,861 | 51 | 597 |
| `LavenderBloom` | 437 KB | 1,861 | 60 | 642 |
| `LavenderRoots` | 386 KB | 2,793 | 49 | 0 |
| `OakMature` (for scale) | 1.1 MB | 4,952 | 62 | 3 |

**Watch the bloom's render cost.** It has 60 shapes, close to `OakMature`'s
62, and the oak was 14% over the render budget. The oak's bench showed that
render time follows shape and path count, not pixels. Levers, cheapest first,
all of which change the look:

- drop the highlights (−9 shapes);
- merge the side and front florets into one colour (−9);
- use fewer wands (−4 or −5 shapes per wand removed).

## Open calibration questions

1. **The spray's splay (6° + 24°)** was judged on stills.
2. **The bloom's highlights** are the cheapest thing to cut if the bench says
   so. Whether they are worth a tenth of the shapes is a look call.
3. **The seed is stylised.** A real lavender seed is tiny. It is drawn at
   roughly the other seeds' size so it can be seen at garden scale.

## Progress

### Step 1: the look (SVG)

Six stages and four root levels, reviewed as flat art, with a simulated thirst
preview and a garden-scale mock beside the other three plants. The RML is
generated and checked with `check_rml.py` (15,010 ids, 4,899 vertices, max
error 0.007 px, 0 failures). **Not built with the rive CLI yet.** See
`HANDOFF.md`.

### Step 2 — built

Built with the rive CLI on 2026-09-30, in one pass, with nothing fixed along
the way. `rive . --verify` gives 0 errors and 0 warnings; `rive inspect .
--summary` reports `problems: []` and seven artboards. `build/lavender.riv` is
**256,612 bytes**, built in **548 ms**.

**Type counts matched the handoff's table exactly** — all 91, across seven
artboards, including the 597 and 642 ellipses on `LavenderMature` and
`LavenderBloom`.

**The built file.** `plantgen/check_built.py`: 2,382 keyframes all `linear`
with none fallen back to `hold`; 942 keyed objects, every `Sway`/`Still` one at
a `*-sway` node and every `Upright`/`Drooped` one at a `*-droop` node or a
`SolidColor`; 60 loop seams exact; **0 twin keys**, which is right — this plant
has no nesting and no twins. 0 failures.

**Does the build draw the art?** `plantgen/check_svg_render.py` on all six
stages and all four root levels: **zero strongly-differing pixels** everywhere.
Pixels differing *at all* run 0.097 %–4.533 %, the highest of any plant, and
that is the ellipses — `LavenderMature` and `LavenderBloom` sit at 4.48 % and
4.53 % against 1.63 % for `LavenderYoung`, which has 3 ellipses rather than
597. The residue scales with edge count and a spike is nothing but edges. The
worst single pixel differs by 183 of 765. **The spikes are in the right place**:
a floret whose outline ring had gone missing or landed off-centre would put a
connected run of strongly-differing pixels there, and there are none.

**The florets fade — the thing no plant had done before.** A `Dots` shape's
`SolidColor` keyed by `KeyFrameColor`, which the sunflower's disc and the oak's
acorns never needed. Counting exact palette colours on `LavenderBloom` at
vitality 1 and 0 settles it:

| colour | vitality 1 | vitality 0 |
|---|---|---|
| `FLORET` `#8B67BA` | 6,191 px | **0 px** |
| `FLORET_DRY` `#A597BD` | 1 px | **6,173 px** |
| `FLORET_DARK` `#644396` | 8,714 px | **0 px** |
| `FLORET_DARK_DRY` `#827399` | 3 px | **8,252 px** |
| `FLORET_LIGHT` `#B79FDC` | 396 px | 44 px |
| `FLORET_LIGHT_DRY` `#C9BFD8` | 0 px | 412 px |

The healthy colours go to **exactly zero** and the dry ones arrive at almost
exactly the same counts. That is the colour changing, not the spikes moving —
a pose change would redistribute the counts, not replace one palette with
another.

**A/B — 21 checks, 0 failures.**

| check | result |
|---|---|
| droop is bound (Sprout…Bloom, v1 vs v0) | 6,218 / 18,516 / 45,786 / 152,763 / 152,782 px |
| healthy adds nothing (Mature v1, twice) | byte-identical |
| sway runs (Seed…Bloom, frame 1 vs 40) | 49 → 91,017 px |
| sway survives thirst (Mature v0, 1 vs 40) | 66,196 px |
| seed ignores vitality | **0 px** |
| seed still rocks | 49 px — the quietest seed of the four |
| roots bound (0/.15/.3/.5/.75) | 5 of 5 distinct |
| roots cap (0.75 vs 1) | byte-identical |
| lean bound (Mature 0 vs 0.5; Young 0 vs 0.3) | 139,691 / 43,483 px |
| lean stops at threshold (0.5 vs 1; 0.3 vs 1) | byte-identical, both |
| bloom never leans (0 vs 1) | byte-identical |

**The splay, measured.** The wands state their own droop, and the emitted
keyframes carry it through unchanged:

| wand | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 |
|---|---|---|---|---|---|---|---|---|---|
| droop | −30.34° | −24.82° | −18.66° | −10.70° | −7.23° | +10.89° | +18.09° | +23.88° | +31.35° |

The handoff's "outer wands about 31°, centre ones about 7°", monotonic from the
centre outward and near-symmetric across it. In the render, the spray's span
goes from **533 px at vitality 1 to 769 px at vitality 0** — left edge out by
111 px, right edge out by 125 px. It splays outward rather than collapsing.

**No gap down the middle**, confirmed by looking rather than by counting. A
column-occupancy measure said 89 of the 121 centre columns held no floret pixel
at vitality 0, which sounds exactly like the failure the handoff warns about
and is not: the spikes are discrete beads strung on thin wands, so empty
columns *between* them are the drawing. The render shows nine wands fanning
evenly out of the cushion with the two centre ones near-vertical. Against
`Claude outputs/lavender-thirst-preview.png`: the spray splays evenly, the
cushion slumps only slightly, the silver-green goes to straw and the purple to
a faded grey-lilac. Matches.

**Bench — 600 frames per artboard. The handoff expected this to fail; it does
not.**

| artboard | advance (mean) | render (mean) | render p95 | memory |
|---|---|---|---|---|
| `LavenderSeed` | 0.001 ms | 0.113 ms | 0.183 ms | +0 pages |
| `LavenderSprout` | 0.002 ms | 0.089 ms | 0.173 ms | +0 pages |
| `LavenderSeedling` | 0.002 ms | 0.084 ms | 0.181 ms | +0 pages |
| `LavenderYoung` | 0.009 ms | 0.095 ms | 0.159 ms | +0 pages |
| `LavenderMature` | 0.063 ms | 0.181 ms | 0.267 ms | +0 pages |
| `LavenderBloom` | 0.066 ms | 0.141 ms | 0.172 ms | +0 pages |
| `LavenderRoots` | 0.001 ms | 0.089 ms | 0.144 ms | +0 pages |

Everything passes: worst render 0.181 ms against a 0.30 ms budget, worst
advance 0.066 ms against 0.10 ms, +0 pages everywhere.

The handoff predicted `LavenderBloom` would be the artboard that failed,
reasoning from its 60 shapes against `OakMature`'s 62. **Shape count was the
wrong predictor.** In the same session `OakMature` renders in 0.309 ms and
`LavenderMature` in 0.181 ms, with near-identical shape counts — because the
oak's shapes are many-vertex paths and the lavender's are ellipses, which are
cheap to rasterise. What the ellipses do cost is **advance**: 0.063–0.066 ms
here against the sunflower's 0.010–0.022 ms, two-thirds of budget and the
highest of the four plants. They are cheap to draw and numerous to step.

So the oak's "render cost follows shapes and paths" wants narrowing: it follows
*path complexity*, and an `Ellipse` is not a path in that sense. Nothing has
been slimmed, and nothing needed to be.

**Smoothing — not re-tested.** Same reasoning as the sunflower's: the emitted
converter chain is byte-identical across all four plants (102 nodes, same types
and attributes), `check_built` confirms every reference resolves, and the fern
and oak each proved convergence in motion. See `../sunflower/NOTES.md`.

**Shipped.** `assets/rive/lavender.riv`, declared in `pubspec.yaml`, and in
`plantArts` — so the garden draws lavender.
