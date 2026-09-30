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
