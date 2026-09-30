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
