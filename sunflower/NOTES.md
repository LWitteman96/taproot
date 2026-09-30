# Sunflower — notes

The third plant on `../plantgen`. Everything in
[`../fern/NOTES.md`](../fern/NOTES.md) (conventions, traps, recipes) and
[`../oak/NOTES.md`](../oak/NOTES.md) (pivots, nested parts, twins, two-pass
drawing) holds here. This file is only what the sunflower adds.

```
sunflower_generator.py    the sunflower: palette, leaf, seed, head, stages, roots, motion
check_rml.py              wrapper for ../plantgen/check_rml.py
preview.sh                ../oak/preview.sh with the species swapped
rive.yaml                 name: sunflower, main: SunflowerBloom
sunflower-*.rml / *.svg   generated
Claude outputs/           reference renders for review
```

**Edit the generator, never the output.**

```bash
python3 sunflower_generator.py && python3 check_rml.py
```

Public surface: view model `Sunflower` (`vitality`, `roots`), state machine
`Sunflower`, artboards `SunflowerSeed` … `SunflowerBloom` and `SunflowerRoots`.
`rive.yaml` opens `SunflowerBloom` rather than Mature, since the open flower
is the one you want to see.

---

## Why a sunflower, and what it is for

It is the plant with the most readable thirst: a healthy sunflower stands and
faces you, a thirsty one bends over and hangs its head. It is also cheap —
one stem, a handful of big leaves, one head — and it is the first plant whose
bloom is literally a flower, so it is where the garden's accent colour first
appears. Until the bloom the sunflower is green like everything else.

## The stages

- **Seed** — a striped sunflower seed in the shared seed bed. Ignores
  vitality, like every seed.
- **Sprout** — a shoot with two plain seed leaves (cotyledons), the right one
  still wearing the empty seed hull. Each seed leaf is a part pivoting at the
  top of the shoot.
- **Seedling** — the seed leaves low on the stem, two pairs of true leaves,
  each its own part pivoting where its stalk leaves the stem.
- **Young** — a tall stem, six heart-shaped leaves, and a closed green bud.
- **Mature** — taller, eight leaves, the bud just opening: yellow petal tips
  between the green bracts.
- **Bloom** — the open flower: green bracts, two rings of petals (a darker
  ring behind), and a brown disc with its seeds laid on a Fermat spiral at the
  golden angle. The spiral is the detail that makes a brown circle read as a
  sunflower.

## The structure

```
plant
└ stem                  kind stem         pivot: base
  ├ leaves on the lower stem              (each kind leaf, pivot: its stalk)
  ├ stem outline pass, stem-upper-line    (twin of stem-upper)
  ├ stem fill
  └ stem-upper          kind upper-stem   pivot: the bend, about halfway up
    ├ head-line                           (twin of head)
    ├ leaves on the upper stem
    ├ upper stem fill + joint disc
    └ head              kind head         pivot: the top of the stem
```

- **The stem is two parts.** A wilting sunflower bends in the middle; it does
  not tip over like a pole. The lower stem barely moves (droop scale 0.15),
  the upper one bends (1.0), and the head hangs (5.6, about 135° from upright
  at vitality 0 — past horizontal).
- **Joints are hidden the oak's way, plus a disc.** The stem, the upper stem
  and the neck are drawn in two passes (outline, then fill), with each part's
  outline pass one level *down* as a `follows` twin. At the bend and at the
  neck a stem-width disc sits in the fill (and a slightly larger one in the
  outline pass), so a bent joint stays solid. **The discs are their own
  shapes.** Inside one path with the stem, a disc wound the other way cut a
  hole where they overlapped — nonzero fill, opposite windings. Found by eye
  on the first render; see the trap entry this adds to `../fern/NOTES.md`.
- **Every leaf is behind its stem.** On the lower stem the stem's outline
  crosses the leaf stalk. On the upper stem the stalk sits between the
  outline pass (a level down) and the fill, so the stem's outline breaks where
  the stalk joins, and the leaf reads as grown out of the stem. A stalk drawn
  in front showed its square end across the stem.
- **Leaves hang harder than fronds** (droop scale 2.6): a thirsty sunflower
  leaf goes limp. Horizontal leaves still drop least, as the shared formula
  says; the upper, more upright ones drop 25–40°.
- **Petals and bracts fade too**, to a dull straw and a grey-green. A wilting
  flower loses its shine; it does not go brown. The disc does not fade.
- **The lean goes right** (`+1`), toward where the head nods.

Droop angles at vitality 0 (+ is clockwise):

| stage | parts |
|---|---|
| Sprout | stem +3.7, cotyledon-left −13.7, cotyledon-right +17.3 |
| Seedling | stem +3.7, cotyledons −7.2 / +8.7, leaves −19.2 / +19.2 / −40.9 / +39.4 |
| Young | stem +3.7, stem-upper +24.8, head +137.5, leaves −6.7 … +24.8 |
| Mature, Bloom | stem +3.7, stem-upper +24.7, head +134.6 / +134.3, leaves −4.5 … +26.2 |

## The roots

A taproot again (a sunflower has one), but shorter and bushier than the
oak's: nine fine laterals crowded along it, each with a branchlet, plus four
fibrous roots just under the surface. Level 1 already shows the taproot's
laterals (max generation 2), so even a sprout's roots look like a sunflower's,
not a small oak's.

| level | length | generations | primaries |
|---|---|---|---|
| 1 | 0.36 | 2 | 1 |
| 2 | 0.58 | 2 | 3 |
| 3 | 0.80 | 3 | 5 |
| 4 | 1.00 | 3 | 5 |

## Weight

The lightest plant with a full stage set, well under the fern's mature stage in
vertices.

| artboard | RML | vertices | shapes |
|---|---|---|---|
| `SunflowerYoung` | 125 KB | 368 | 33 |
| `SunflowerMature` | 154 KB | 453 | 40 |
| `SunflowerBloom` | 180 KB | 511 | 43 |
| `SunflowerRoots` | 370 KB | 2,679 | 47 |
| `FernMature` (for scale) | 199 KB | 1,176 | 17 |
| `OakMature` (for scale) | 1.1 MB | 4,952 | 62 |

The shape count is higher than the fern's (every leaf is a stalk, a blade and
veins), and the oak showed render cost follows shapes and paths, so bench it
rather than assume.

## Shared changes this made

- **`plantgen/check_rml.py`** — the oak's structural checker, made generic
  over the species (`python3 plantgen/check_rml.py <project>`). `oak/` and
  `sunflower/` each keep a `check_rml.py` wrapper, so the old command still
  works. The oak's result is unchanged: 13,291 vertices, max error 0.017 px.
- Nothing in `plantgen/`'s generators changed; the fern and oak outputs are
  untouched.

## Open calibration questions

These were judged on stills, not in motion.

1. **The head's droop is steep early.** With the shared asymmetric ease,
   vitality 0.75 already turns the head about 60°. That is very visible —
   which is the point of the ease — but a head half-hanging after one missed
   day may read as an accusation rather than an invitation. A per-kind ease,
   or a smaller head scale, would soften it. Look at it in motion first.
2. **Head scale 5.6 and leaf scale 2.6** are well outside the fern's 0.6–1.0.
   The shared droop formula was written for fronds; the sunflower bends it
   hard. It works, but it is a sign the formula may want a per-kind maximum
   angle instead of a multiplier.
3. **The bud** (young and mature) is the least natural drawing: a star of
   bracts round a dome. It reads at garden scale; up close it is stylised.

## Progress

### Step 1 — the look (SVG)

Six stages and four root levels, reviewed as flat art, with a simulated thirst
preview and a garden-scale mock beside the fern and the oak. RML generated and
checked with `check_rml.py` (9,560 ids, 1,578 vertices, max error 0.015 px, 0
failures). **Not built with the rive CLI yet** — see `HANDOFF.md`.

### Step 2 — built

Built with the rive CLI on 2026-09-30, in one pass, with nothing fixed along
the way. `rive . --verify` gives 0 errors and 0 warnings; `rive inspect .
--summary` reports `problems: []` and seven artboards.
`build/sunflower.riv` is **130,610 bytes**, built in **325 ms** — the smallest
plant so far, against the fern's 171 KB and the oak's 557 KB.

**Type counts matched the handoff's table exactly** — all 91 of them, across
seven artboards. The RML is what got built.

**The built file.** `check_built.py` (now `plantgen/check_built.py`, see
below): 1,984 keyframes all `linear` with none fallen back to `hold`; 832
keyed objects, every `Sway`/`Still` one at a `*-sway` node and every
`Upright`/`Drooped` one at a `*-droop` node or a `SolidColor`; 48 loop seams
exact; 24 twin keys identical to their leaders — the `stem-upper-line` and
`head-line` pair the handoff names. 0 failures.

**Does the build draw the art?** `plantgen/check_svg_render.py`, new here, does
the oak's SVG-vs-Rive diff as a script. All six stages and all four root levels
pass with **zero strongly-differing pixels**. Pixels differing *at all* run
0.133 %–2.671 %, higher than the oak's 0.008 %–0.687 % because `SunflowerBloom`
carries 127 ellipses and the residue scales with edge count. The worst single
pixel anywhere in the set differs by 182 of 765, which is partial-coverage
disagreement on one edge, not a moved edge.

**A trap this run found, and it was mine rather than the art's.** `--advance=0`
is right for a stage — every sway key is 0 there, so the artboard sits in the
rest pose the SVG describes — but **it applies no data at all**. On
`SunflowerRoots`, where every level *is* a data-driven blend pose, all four
levels then render the authored level-4 pose whatever `--data=roots=` says, and
only level 4 passes. Confirmed directly: the roots-0.15 render at `--advance=0`
is byte-identical to the level-4 render. The roots artboard carries no sway, so
it is advanced 120 frames instead — past the 1.2 s smoothing. A stage cannot be.
Added to `../fern/NOTES.md`.

**A/B — 21 checks, 0 failures.** Same `--advance` on both sides of every one.

| check | result |
|---|---|
| droop is bound (Sprout…Bloom, v1 vs v0) | 10,627 / 34,725 / 87,021 / 185,944 / 236,401 px |
| healthy adds nothing (Mature v1, twice) | byte-identical |
| sway runs (Seed…Bloom, frame 1 vs 40) | 399 → 54,117 px |
| sway survives thirst (Mature v0, 1 vs 40) | 32,639 px |
| seed ignores vitality | **0 px** |
| seed still rocks | 399 px |
| roots bound (0/.15/.3/.5/.75) | 5 of 5 distinct |
| roots cap (0.75 vs 1) | byte-identical |
| lean bound (Mature 0 vs 0.5; Young 0 vs 0.3) | 111,829 / 54,860 px |
| lean stops at threshold (0.5 vs 1; 0.3 vs 1) | byte-identical, both |
| bloom never leans (0 vs 1) | byte-identical |

**Lean direction, measured.** The whole plant's x-centroid moves **+27.3 px on
`SunflowerMature` and +22.8 px on `SunflowerYoung`** between roots 1 and roots
0. Both tip **right**, as `LEAN_DIRECTION = +1` intends and opposite to the oak.

Measuring a *part* rather than the plant does not work on `SunflowerYoung`: the
disc-brown pixels there sit at y ≈ 886, which is the lean's own pivot, and
nothing at a pivot moves however far the plant tips. That produced a confident
+0.1 px before the selection was widened to the whole plant. `plantgen/
measure.py` takes `!RRGGBB` for exactly this.

**The head swing, the largest rotation in the project.** Read out of the
emitted keyframes rather than eyeballed: the head turns **+134.26°** and the
upper stem **+24.74°** — the handoff's "about 135°" and "about 25°", to two
decimal places. Both positive, so both clockwise, so the head goes right.

Composing that transform puts the neck at (673.4, 356.6) at vitality 0, against
its authored (524, 320). The disc centroid measures (698.0, 496.3), so the disc
ends **+24.6 px right of the neck and +139.7 px below it** — it was 94.7 px
*above* the neck at vitality 1. Right of and below, as the handoff asks.

**Joints — looked at, not asserted.** Crops of the bend and the neck across
vitality 1/0.5/0 × sway frames 1/75/150/225: the bend is a clean turn through
its full 24.7° with the outline continuous around the outside of the corner,
no notch, no light gap, and no outline crossing the stem interior. The neck is
solid where the head attaches at every pose. The full-frame render at vitality
0 matches `Claude outputs/sunflower-thirst-preview.png` — stem upright at the
ground and curving above the bend, head hanging right and below its neck,
leaves drooped and faded, petals dull straw, and every pivot holding (leaves on
their stalks, head on its neck, upper stem on the lower).

**Two automated joint checks were tried and both are wrong**, which is worth
more than the crops. A fixed probe at the joint's coordinates misses a joint
that travels — this neck moves 150 px. Counting background enclosed by the
plant is drowned by the 35,748–62,596 px an already-passed `OakMature` encloses
between its foliage by design. Both dead ends are recorded in
`plantgen/crop_joints.py`, which now makes the crops and says plainly that it
is not a pass/fail check.

**Bench — 600 frames per artboard, all seven inside budget.**

| artboard | advance (mean) | render (mean) | render p95 | memory |
|---|---|---|---|---|
| `SunflowerSeed` | 0.002 ms | 0.121 ms | 0.286 ms | +0 pages |
| `SunflowerSprout` | 0.002 ms | 0.089 ms | 0.183 ms | +0 pages |
| `SunflowerSeedling` | 0.003 ms | 0.104 ms | 0.173 ms | +0 pages |
| `SunflowerYoung` | 0.006 ms | 0.099 ms | 0.179 ms | +0 pages |
| `SunflowerMature` | 0.010 ms | 0.104 ms | 0.156 ms | +0 pages |
| `SunflowerBloom` | 0.022 ms | 0.081 ms | 0.119 ms | +0 pages |
| `SunflowerRoots` | 0.001 ms | 0.097 ms | 0.145 ms | +0 pages |

Against the budget (advance ≤ 0.10 ms, render ≤ 0.30 ms, no memory growth):
**everything passes, with room.** Worst advance is a fifth of budget and worst
render is 40 % of it.

Re-benched in the same session for a like-for-like baseline: `FernMature`
0.136 ms and `FernBloom` 0.100 ms — against 0.132 / 0.113 in the oak's session,
so the machine is running at the same speed and the numbers are comparable.
`OakMature` 0.309 ms and `OakBloom` 0.317 ms, both still over the 0.30 ms
budget. **The sunflower renders at about the same cost as the fern and a third
of the oak**, which is what the handoff predicted from its vertex count.

**Smoothing — not re-tested, and here is why.** The listener-scaffold check was
not run for this plant. The smoothing chain is emitted entirely by shared
`plantgen` code with no species-specific configuration, and comparing the
emitted converter nodes across all four plants shows them **byte-identical**:
102 nodes each, same types, same attributes, same distribution across files.
`check_built` separately confirms every converter and interpolator reference
resolves. So running the scaffold here would re-test the same emitted XML the
fern and the oak each already proved converges exactly. If a species ever gains
its own smoothing configuration, that reasoning stops holding and the scaffold
run comes back.

**Shipped.** `assets/rive/sunflower.riv`, declared in `pubspec.yaml`, and in
`plantArts` — so the garden draws sunflowers.
