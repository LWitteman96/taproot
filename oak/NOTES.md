# Oak — notes

The second plant, and the first one built on `../plantgen`. Everything in
[`../fern/NOTES.md`](../fern/NOTES.md) holds here — the conventions, the trap
table, the verification recipes. This file is only what the oak adds.

```
oak_generator.py      the oak: palette, leaf, acorn, stages, root tree, motion tables
check_rml.py          structural checks rive --verify cannot make (see below)
check_built.py        assertions on the built tree, from `rive inspect --json`
check_render.py       the 21 A/B renders that prove the data drives the picture
preview.sh            fern/preview.sh with the species swapped
oak-data.rml          generated — the shared Oak view model
oak-roots.rml         generated — OakRoots
oak-stage-*.rml/.svg  generated — one artboard per stage, and the flat art
oak-roots-*.svg       generated — the four root levels
```

As with the fern: **edit the generator, never the generated files.**

```bash
python3 oak_generator.py && python3 check_rml.py
rive . --verify && rive inspect . --summary
rive . --once && python3 check_built.py && python3 check_render.py
```

The last line is what catches a bind that resolves and drives nothing; the two
above it cannot.

The public surface is the fern's with the species renamed: view model `Oak`
with `vitality` and `roots`, state machine `Oak` on every artboard, artboards
`OakSeed` … `OakBloom` and `OakRoots`. The stacking contract is the same — one
shared `ViewModelInstance` for the stage and `OakRoots`.

---

## The shared module

`fern_generator.py` used to be the whole machine. The generic half moved to
`../plantgen`, and **the fern's output is byte-identical to before the move**
(every `.rml` and `.svg`, in both sway modes). The fern is now a palette, its
parts, and a `Species(...)` holding its tables; the oak is the same shape.

Four things were added to the shared half, all inert for the fern:

- **`Group.pivot`.** A fern grows every part from the ground, so everything
  rotated about the base. A limb leaves the trunk higher up. A part now rotates
  about its own pivot; `None` still means the base, and a node at the base
  writes no `x`/`y`, which is why the fern's bytes did not move.
- **Nested parts.** A part may contain parts. Each gets its own droop/sway
  pair, emitted inside its parent's sway node at its pivot relative to the
  parent's, so a limb rides along when the trunk sways and the two rotations
  compose. `animated()` lists them depth-first; that order is the sway index.
- **`meta["follows"]`.** A part that copies another's motion exactly — same
  sway keys, same droop keys. The reason is below.
- **`meta["droop_direction"]`.** A near-vertical part can declare its side on
  itself, for parts placed by the dozen. Hand-placed parts still use the table,
  and a part with neither still raises.

## The tree

Stages 3–5 are one animated **trunk** with its **limbs** nested inside it, and
each limb holds its **rosettes** — the clusters of five or six leaves oaks grow
at the ends of twigs — as parts of their own.

```
plant
└ trunk            kind trunk (sapling at stage 3)      pivot: base
  ├ limb-back-*    kind limb, whole                    pivot: where it leaves
  │ └ *-r1 …       kind rosette                        pivot: the twig end
  ├ limb-*-line    kind limb, follows limb-*           outline pass only
  ├ trunk wood     outline, fill, bark
  └ limb-*         kind limb                           fill pass + rosettes
    └ *-r1 …
```

**The crown is laid out before the limbs.** A crown is a half-dome scattered
with rosette sites (dart-throwing at a minimum spacing), and each site gets a
twig from the nearest limb. Drawn the other way round — leaves on the ends of
sticks — it read as a bare tree with tufts. Back and front crowns are scattered
separately: the back one, darker and behind the trunk, fills the gaps the
front one leaves.

**Wood is drawn in two passes.** An outline pass (outline colour, filled and
thickly stroked) under a fill pass. Where branches overlap, the fills cover
each other's outlines and the wood reads as one silhouette. A front limb is
split in two parts so its outline pass sits *under* the trunk and its fill pass
*over* it: at the joint neither outline shows, and the limb grows out of the
trunk rather than lying across it. The outline half `follows` the fill half,
so they cannot come apart. A disc "collar" at the joint was tried first; any
limb whose outline ran along the trunk for more than its own width still drew
a line across it.

**Droop is in the leaves, not the wood.** With limbs dropping as far as the
fern's fronds do, the centre limb fell right, the left limbs fell left, and the
crown opened down the middle — a tree splitting, not a tree thirsty. So:

| kind | droop scale | sway (deg) |
|---|---|---|
| rosette | 1.3 | 2.6 |
| limb | 0.3 | 1.1 |
| trunk | 0 | 0.25 |
| sapling | 0.3 | 0.8 |
| shoot / leaf (stages 1–2) | 0.6 / 1.4 | 1.4 / 3.0 |

A rosette hangs outward, away from the crown's middle
(`meta["droop_direction"]` from its x against the crown centre). The trunk
still sways a quarter of a degree, which moves the crown top about 4 px: enough
to feel alive, not enough to look unrooted.

**The lean goes left** (`LEAN_DIRECTION = -1`), the fern's goes right, so a
garden of under-rooted plants does not all tip one way.

## The other stages

- **Seed** — an acorn in the fern's seed bed, in the fern's seed browns, cup
  and stalk to the left. It ignores vitality, as the fern seed does.
- **Sprout** — a green shoot with two lobed leaves and a bud, each a nested
  part pivoting at the top of the shoot. The empty acorn lies beside it, in
  the front soil layer, so it does not lean with the plant.
- **Seedling** — a taller shoot, three alternate leaves (each pivoting where it
  joins) and a top cluster.
- **Bloom** — the mature tree with pairs of ochre acorns hanging under every
  other front rosette. They are inside the rosette, so they swing with it; like
  the fern's spores they do not fade.

## The roots

A **taproot** — primary 0, nearly straight (`wander` 0.04, `gravity` 0.12),
six alternating laterals with their own branches — plus four surface laterals.
Level 1 is the taproot alone: the first thing an acorn grows is the root the
app is named after.

| level | length | generations | primaries |
|---|---|---|---|
| 1 | 0.34 | 1 | 1 |
| 2 | 0.55 | 2 | 3 |
| 3 | 0.78 | 2 | 5 |
| 4 | 1.00 | 3 | 5 |

`Root` gained `wander`, `gravity` and `steps` (the fern's values are the
defaults), and `root_scale` takes the levels table instead of a global.

## The leaf

`oak_leaf()` is built in a leaf frame as alternating lobe apexes and sinuses,
all cubic. The envelope is obovate — narrow base, widest past the middle — and
each lobe's apex sits toward its front edge, so the lobes point up the leaf.
Crown leaves have four lobes a side and no vein (a 1.6 px vein is a quarter of
a point in the garden). The seedling's big leaves keep theirs.

## Checks

`check_rml.py` does what `rive --verify` and `inspect` do not:

- ids unique across all eight files (they share a namespace);
- every `objectId`, `animationId`, `converterId`, `stateToId` resolves;
- every keyframe states its `interpolationType`;
- **every emitted vertex, with the node offsets above it accumulated, lands on
  the model's point** — 13,291 vertices, max error 0.017 px (the emitter's
  2-decimal rounding, summed down three levels of nesting). Moving one limb
  node by 5 px shows up as 5.009 px, so the check is measuring something;
- a `follows` part carries exactly its leader's sway and droop keys.

It does not replace the rive checks, and it does not render anything.

`check_built.py` picks up where it stops, on the *built* tree rather than the
markup: no keyframe fallen back to `hold`, `Sway`/`Still` keying `*-sway` nodes
and `Upright`/`Drooped` keying `*-droop` nodes or `SolidColor`s, exact loop
seams, and twins matching their leaders. It is species-agnostic — point it at
another project directory and it works.

`check_render.py` is the only one of the three that renders. See step 2.

**Each of `check_built.py`'s four assertions has been negative-controlled** —
corrupt the tree in the specific way it is meant to catch, confirm it fails.
Do that again after changing it. A checker that silently passes is worse than
no checker, because it is quoted as evidence.

## Weight

The oak is the heaviest plant so far. A crown is a lot of lobed leaves.

| artboard | RML | vertices | shapes | nodes |
|---|---|---|---|---|
| `OakYoung` | 528 KB | 2,345 | 32 | 58 |
| `OakMature` | 1.1 MB | 4,952 | 62 | 114 |
| `OakBloom` | 1.3 MB | 5,696 | 146 | 114 |
| `FernMature` (for scale) | 199 KB | 1,176 | 17 | 12 |

Built, the whole thing is one **544 KB** `.riv` (seven artboards) against the
fern's 171 KB, and it compiles in 1.1 s.

Measured (step 2), the weight lands almost entirely on **render**, not on
advance, and **render does not fall with viewport** — `OakMature` costs 0.37 ms
at 256×256 and 0.34 ms at 1024×1024. The cost is path count, so drawing the oak
small in the garden does not buy any of it back. `advance` is comfortable
everywhere.

Levers if this has to come down, cheapest first: three lobes a side
(about −25% vertices), five leaves a rosette instead of six is already taken,
fewer crown sites (raise `Crown` spacing), acorns as one shared path per limb
instead of per rosette (bloom shapes 146 → ~70). **Every one of them changes the
look**, which is why none has been taken — see step 2.

## Progress

### Step 1 — the look (SVG)

All six stages and the four root levels drawn, reviewed as flat art and at
garden scale (0.15) beside the fern. RML generated and structurally checked,
not yet built with the rive CLI.

### Step 2 — built

Built with the rive CLI for the first time. **Nothing in the art or the wiring
had to change**: every count, every A/B and every render matched what step 1
predicted, first time. The two risks the handoff named — new pivot/nesting code
that Rive had never rendered, and old code now emitted from `plantgen` — both
came through clean.

**Verify and inspect.** `rive . --verify` → 0 errors, 0 warnings, 1.1 s.
`rive inspect . --summary` → `problems: []`, seven artboards. **Every type count
matched the handoff's table exactly** — all 13 columns on all 7 artboards, no
discrepancy to explain. Layers are 3 on `OakYoung`/`OakMature` (Sway, Vitality,
Stability), 2 elsewhere, 1 on `OakRoots`.

**The built file.** `check_built.py` (new, and written to be reused by the next
plant) asserts on the resolved tree from `rive inspect . --json`: 4,904
keyframes all `linear` with none fallen back to `hold`; 1,304 keyed objects,
every `Sway`/`Still` one pointing at a `*-sway` node and every
`Upright`/`Drooped` one at a `*-droop` node or a `SolidColor`; 150 loop seams
exact; 52 twin keys identical to their leaders. 0 failures.

Each of those four checks was then **negative-controlled** — a keyframe flipped
to `hold`, a twin's value perturbed, a seam broken, a `Sway` key repointed at a
droop node — and each was caught. Worth the five minutes: a checker that
silently passes is exactly the class of thing this project keeps finding.

**Appearance, measured rather than eyeballed.** Headless Chrome renders the
generated `.svg`, `rive --screenshot` renders the `.riv`, and the two are
diffed. This is a much stronger check than comparing against the reference
pngs, because it compares the build against *the art the build came from*:

| artboard | pixels differing at all | differing strongly |
|---|---|---|
| `OakSeed` … `OakBloom` | 0.008 % – 0.687 % | **0** |
| `OakRoots` levels 1–4 | 0.001 % – 0.120 % | **0** |

Zero strongly-differing pixels anywhere: Rive draws exactly the reviewed art,
on all six stages and all four root levels. What does differ is edge
antialiasing, and it scales with edge count (the bloom differs most). The
recipe is written up in `../fern/NOTES.md`.

By eye, against the reference renders: crown stays one mass at vitality 0, the
rosettes tilt outward, the leaves go pale grey-green, the limbs sag slightly and
the mature trunk does not move — matching `oak-thirst-preview.png`. Joints were
cropped at sway frames 1/75/150/225 and at both vitality ends: **no dark outline
anywhere across the trunk, and no outline offset from its fill** — the two-pass
wood and the `follows` twins do what they were designed to do. Drooped limbs
stay attached and drooped rosettes stay on their twig ends, so the pivots
compose correctly through three levels of nesting. `OakRoots` shows five
distinct poses, the taproot alone and straight down at 0.15.

One thing checked and dismissed: at contact-sheet scale the mature crown looks
clipped at the left edge. It is not — no pixel is painted in columns 0–3 of any
render. It was the downscaling.

**A/B — 21 checks, 0 failures.** Same `--advance` on both sides of every one.

| check | result |
|---|---|
| droop is bound (Sprout…Bloom, v1 vs v0) | 17,016 / 29,838 / 129,355 / 327,426 / 325,776 px |
| healthy adds nothing (Mature v1, twice) | byte-identical |
| sway runs (Seed…Bloom, frame 1 vs 40) | 418 → 128,533 px |
| sway survives thirst (Mature v0, 1 vs 40) | 96,292 px |
| seed ignores vitality | **0 px** |
| seed still rocks | 418 px |
| roots bound (0/.15/.3/.5/.75) | 5 of 5 distinct |
| roots cap (0.75 vs 1) | byte-identical |
| lean bound (Mature 0 vs 0.5; Young 0 vs 0.3) | 301,641 / 107,987 px |
| lean stops at threshold (0.5 vs 1; 0.3 vs 1) | byte-identical, both |
| bloom never leans (0 vs 1) | byte-identical |

**Lean direction, measured.** The crown's x-centroid moves −45.4 px on
`OakMature` and −39.2 px on `OakYoung` between roots 1 and roots 0. Both tip
**left**, as `LEAN_DIRECTION = -1` intends and opposite to the fern.

**Smoothing.** With the listener scaffold from `../fern/NOTES.md` temporarily
injected (and removed afterwards by regenerating), a click sets `vitality` 0 → 1
mid-run and the pose eases rather than snapping:

| frames after the click | difference from an always-healthy tree |
|---|---|
| 0 | 327,210 px — still fully drooped |
| 15 (0.25 s) | 303,697 px |
| 30 (0.50 s) | 8,954 px |
| 60 (1.00 s) | **0 px** |

It converges *exactly*, which is a stronger result than the fern recorded. It
only reads that way once both sides use the same `--advance` structure — see
the new trap in `../fern/NOTES.md`; a first attempt showed a permanent ~15,000 px
residual that turned out to be entirely an artefact of the measurement.

**Bench — `advance` and memory pass, `render` is over budget on two artboards.**
600 frames, 1024×1024:

| artboard | advance mean | render mean | render p50 | memory |
|---|---|---|---|---|
| `OakSeed` | 0.002 ms | 0.150 ms | 0.077 ms | +0 pages |
| `OakSprout` | 0.002 ms | 0.135 ms | 0.079 ms | +0 pages |
| `OakSeedling` | 0.003 ms | 0.147 ms | 0.056 ms | +0 pages |
| `OakYoung` | 0.015 ms | 0.227 ms | 0.150 ms | +0 pages |
| `OakMature` | 0.029 ms | **0.343 ms** | 0.270 ms | +0 pages |
| `OakBloom` | 0.066 ms | **0.361 ms** | 0.294 ms | +0 pages |
| `OakRoots` | 0.001 ms | 0.083 ms | 0.078 ms | +0 pages |

Against the handoff's budget (advance ≤ 0.10 ms, render ≤ 0.30 ms, no memory
growth): **advance passes everywhere** with the worst case at two-thirds of
budget, **memory passes** (+0 pages on all seven), and **`OakMature` and
`OakBloom` exceed the render budget** by 14 % and 20 %. Three repeat runs put
Mature at 0.32–0.38 ms and Bloom at 0.36–0.45 ms, so it is the real number, not
a sample.

Two things put that in proportion, and neither makes it go away:

- **Shrinking does not help.** At a garden-sized viewport the number is the same
  or worse (Mature 0.47 ms at 384×384, 0.37 ms at 256×256, 0.34 ms at
  1024×1024). Render here is bound by path count, not pixel count.
- **The budget's baseline moved.** Re-benched in the same session, `FernMature`
  renders in 0.132 ms and `FernBloom` in 0.113 ms — against the 0.076–0.092 ms
  recorded in `../fern/NOTES.md` step 7. This machine is running about 1.5×
  slower today than when the fern set the baseline, so the oak is roughly **3×
  the fern**, not 4×. Three oaks at once costs about 1.1 ms of a 16.7 ms frame.

Per the handoff, **nothing has been slimmed**: every lever changes the look, and
that is Luuk's call. The levers and their costs are under [Weight](#weight).

### Still open

- **The render budget on `OakMature` and `OakBloom`** — over by 14–20 %, with
  the levers listed under [Weight](#weight). Waiting on Luuk, because every one
  of them changes art he has already reviewed.
- Teach `plant_art.dart` about a second species — today it hard-codes the fern
  (`fernPlantType`, `fernStateMachineName`, `hasPlantArt()`). `assets/rive/oak.riv`
  ships and the garden does not draw it yet.
- The garden-design art pass (outline widths × 2, root recolour) applies here
  too, and should be done once in `plantgen` for both plants.
- The calibration questions from step 1 are unreviewed in motion: the rosette
  droop scale of 1.3, the limb 0.3, and the trunk's quarter-degree sway were
  all judged on stills.
