# Fern — RML notes

This project is the **building block for every Taproot animation**, not a
one-off. The fern is the first subject; the generator, the conventions and the
trap list below are meant to carry to the other plants.

`AGENTS.md` is the contract for driving the CLI. This file is what was learned
using it: what RML can do, what it does *silently wrong*, and the decisions this
project has settled on.

Read [Traps](#traps-silent-failures) before writing RML. Every entry there
builds clean, inspects clean, and does the wrong thing at runtime.

**Contents**

- [The shape of the project](#the-shape-of-the-project)
- [The generator](#the-generator)
- [RML capabilities](#rml-capabilities) — paths, bones, view models
- [Traps: silent failures](#traps-silent-failures)
- [Conventions](#conventions)
- [Adding a stage](#adding-a-stage)
- [Progress](#progress)

---

## The shape of the project

```
fern_generator.py     the source of truth: geometry, SVG writer, RML emitter
fern-mature.rml       generated — do not hand-edit
fern-stage-*.svg      generated — the five growth stages
fern-roots-*.svg      generated — the four root levels
rive.yaml             project config (name, log paths)
build/                gitignored: fern.riv, fern.png, logs
```

Nothing in `build/` is committed, and no `.riv` has been added to the Flutter
app's assets yet.

The art comes from `docs/design-spec.md`'s garden metaphor: five growth stages
(sprout → seedling → young → mature → bloom) and four root levels, stacking so
the ground lines meet. Only the **mature** stage has been taken to RML so far.

## The generator

The one rule: **`fern_generator.py` is the source of truth, and both outputs are
readers over one geometry model.** Nothing is hand-transcribed between SVG and
RML, because the two formats describe curves differently (see
[paths](#a-custom-paths-with-cubic-beziers)) and a hand conversion would drift
on the first edit.

```
Contour / Dot          geometry primitives
      ↓
Path / Dots / Group    drawables — what becomes one <path> or one <Shape>
      ↓
svg_item()             SVG writer          rml_item()   RML emitter
```

`Contour` holds on-curve nodes as `(point, in_handle, out_handle)` with handles
as **absolute control points**, the way SVG writes them. Only the RML emitter
converts to Rive's polar form. A handle of `None` means that side is straight,
which is what lets the emitter choose `StraightVertex` over
`CubicDetachedVertex`.

`Dot(cx, cy, rx, ry)` is stored as data rather than as a path string, so SVG can
render it as its two-arc idiom and RML as a real `<Ellipse>`.

Two consequences worth keeping:

- **No format-specific geometry.** When `tapered()` needed a round tip, the SVG
  elliptical arc was replaced by sampled points (`CAP_SAMPLES = 8`) rather than
  teaching the emitter about arcs. Both writers now see identical geometry, and
  the emitter only ever meets straight and cubic vertices. This covers
  fiddlehead coils and root tips for free, since they all run through
  `tapered()`.
- **Verify numerically, not by eye.** A render looking right does not prove the
  emitter agrees with the model. Reconstruct emitted vertices back to absolute
  coordinates and diff them against the model — see
  [Progress](#step-2--the-mature-artboard) for the check that has been run.

---

## RML capabilities

Everything here was checked with `rive docs` / `rive schema` in this toolchain.
Type and doc names are cited so each claim can be re-checked rather than
trusted.

### (a) Custom paths with cubic beziers

`docs drawing` → "Custom paths". A `Shape` holds one or more `PointsPath`
children; each holds an ordered vertex list in the shape's local space.

| Vertex type | Handles |
|---|---|
| `StraightVertex` | corner; optional `radius` (auto-clamped) |
| `CubicMirroredVertex` | `rotation`, `distance` — symmetric |
| `CubicAsymmetricVertex` | shared direction, independent lengths |
| `CubicDetachedVertex` | `inRotation`/`inDistance`, `outRotation`/`outDistance` |

`rive schema CubicDetachedVertex`: typeKey 6, own props `inRotation` (key 84),
`inDistance` (85), `outRotation` (86), `outDistance` (87), plus `x` (24) /
`y` (25) from `Vertex`. All animatable **and** bindable.

**Rive stores handles as polar offsets from the vertex, not as absolute control
points.** Converting from SVG:

```
outRotation(P0) = atan2(c1 - P0)    outDistance(P0) = |c1 - P0|
inRotation(P1)  = atan2(c2 - P1)    inDistance(P1)  = |c2 - P1|
```

`rotation` is radians. This conversion is the whole reason RML is generated
rather than typed.

Also:

- A `Shape` may hold **several** `PointsPath` children; they combine into one
  filled path. This maps 1:1 onto batching many contours into one SVG `<path>`.
- `isClosed="true"` closes a contour. An open `PointsPath` with a `Fill` still
  fills across an implied closing line.
- `isClockwise` and `Fill.fillRule` (`nonZero` | `evenOdd`) decide holes.
  `isClockwise` is editor-only (`rive schema PointsPath --all`) and defaults
  true; this project leaves it alone and relies on `nonZero`.
- Quadratics have no native form — elevate to cubic:
  `c1 = P0 + ⅔(Q − P0)`, `c2 = P2 + ⅔(Q − P2)`.
- Elliptical arcs have no native form either. Sample them, or use `Ellipse`
  geometry when that is what they really are.

Paint: `Fill` and `Stroke` are both children of the `Shape`. `Stroke` takes
`thickness`, `cap` (`butt`/`round`/`square`), `join` (`miter`/`round`/`bevel`).
Colour is `colorValue="AARRGGBB"` — bare hex, no `#`, **alpha first**, so
`#6FA35A` → `FF6FA35A`.

### (b) Bones and skinning

`docs rigging`. `RootBone` (`x`/`y`/`length`/`rotation`) starts a chain; `Bone`
children inherit from the parent's tip. `rotation` is radians, relative to the
parent.

Skinning: a `Skin` nests **inside** the `PointsPath` it deforms, holding one
`Tendon` per bone (recording the bind pose as a `Mat2D`), and every vertex
carries a `Weight` — `indices`/`values` packed one byte per slot, four bones
per vertex maximum. Cubic vertices need `CubicWeight`, which adds
`inIndices`/`inValues` and `outIndices`/`outValues` so the handles deform with
the point.

**Not used so far, and deliberately.** A frond sway is a rigid rotation about a
shared pivot, and `docs transforms` is explicit that a `Node` is the group for
that: wrap the art in a node placed at the pivot and key the node. One keyed
property per frond instead of a tendon per vertex.

Bones remain the right answer for two things this project will want:

- **Tip lag.** A 2–3 bone chain per frond would let the tip trail the base
  instead of the frond rotating rigidly.
- **Roots.** `roots()` already emits one group per primary root "so each can get
  its own bone chain".

If you take that on, the skinning traps are in [Traps](#traps-silent-failures).

### (c) A view model number driving a state machine

`docs data` + `docs state-machines`. `StateMachineNumber`/`Bool`/`Trigger`
inputs are **deprecated**; view model properties replace them and are bindable
into colours, sizes and text as well.

```xml
<ViewModel defaultInstanceId="0:41" name="Fern" id="0:40">
    <ViewModelPropertyNumber name="vitality" id="0:45"/>
    <ViewModelInstance exports="true" name="Default" id="0:41">
        <ViewModelInstanceNumber propertyValue="1" viewModelPropertyId="0:45"/>
    </ViewModelInstance>
</ViewModel>
```

Three links, all required: the artboard names the view model with `viewModelId`,
the view model names its default with `defaultInstanceId`, each instance value
names its property with `viewModelPropertyId`. `defaultInstanceId` and `exports`
are editor-only (`rive schema ViewModel --all`) but belong in the RML. Set
`Artboard.viewModelInstanceId` too, or the artboard opens unpopulated in the
editor.

Two ways to consume a number:

1. **Threshold** — `TransitionViewModelCondition`, `opValue` one of `equal`,
   `notEqual`, `lessThan`, `lessThanOrEqual`, `greaterThan`,
   `greaterThanOrEqual`. Left side a `TransitionPropertyViewModelComparator`
   wrapping a `BindablePropertyNumber` holding a `DataBindContext`; right side a
   `TransitionValueNumberComparator`. Discrete states with a blend time.
2. **`BlendState1DViewModel`** (`docs easing`) — the current form of a 1D blend
   state, for a continuous axis. It has **no `inputId`**: nesting a
   `BindablePropertyNumber` with a `DataBindContext` *is* the wiring.

```xml
<BlendState1DViewModel id="0:70">
    <BindablePropertyNumber>
        <DataBindContext sourcePathIds="0:40-0:45" propertyKey="636"/>
    </BindablePropertyNumber>
    <BlendAnimation1D animationId="0:71" value="0"/>
    <BlendAnimation1D animationId="0:72" value="100"/>
</BlendState1DViewModel>
```

`propertyKey="636"` is `BindablePropertyNumber.propertyValue`
(`rive schema BindablePropertyNumber`, typeKey 473). `sourcePathIds` is
`viewModelId-propertyId`, absolute.

Names are the public surface — the host reads and writes properties by name,
`--data=fern/vitality=0.3` addresses them by name, and renaming one is a
breaking change in a way renumbering an id is not. PascalCase view models,
camelCase properties; no leading digit, no Luau keyword (`type` is the one that
catches people).

---

## Traps: silent failures

Every one of these builds clean, reports `problems: []`, and misbehaves at
runtime. Ordered by how easy they are to hit.

| Trap | What happens | Guard |
|---|---|---|
| **`KeyFrameDouble.interpolationType` defaults to `hold`** | keyed values step instead of interpolating | write `linear` (or `cubic` + an interpolator) on **every** keyframe |
| **Blend weights run 0–100, not 0–1** | every pose collapses onto the first | range-map the axis; put easing on the converter |
| **A property keyed in one blend pose and not another** | jumps instead of blending | key every blended property in every pose |
| **`BlendAnimation1D` children out of ascending `value` order** | the runtime binary-searches; blends the wrong pair | emit sorted |
| **Artboard without `defaultStateMachineId`** | no bind ever pushes, no pointer input arrives; animations still play | always set it |
| **Keyframe element not matching the property type** | the value is never written | `KeyFrameDouble` for `double`, `KeyFrameColor` for `Color`, `KeyFrameUint` for uint/enum, `KeyFrameId` for `Id` |
| **`interpolationType="cubic"` with no `CubicEaseInterpolator` child** | eases nothing | give every cubic keyframe its curve |
| **`nameBased="true"` on a `DataBindContext`** | this toolchain cannot emit the manifest it indexes; the bind is inert | never author it; `problems` is meaningless in both directions here |
| **`Feather` inside a `Fill`** | the paint vanishes entirely | feather strokes; for a soft fill use a `RadialGradient` with an alpha-`00` outer stop |
| **`GradientStop` with no `position`** | all stops sit at 0, gradient renders flat | always set `position` |
| **A `ViewModelInstanceValue` whose `viewModelPropertyId` points at nothing** | silently inert; these ids are never resolved, so `inspect` says nothing | check by hand |
| **Skinning: `indices` is 1-based** | a `0` slot is the identity transform — looks exactly like bones not working | `tendonIndex + 1` |
| **Skinning: `values` must total 255** | the runtime divides by 255 and does not renormalize | split an even blend 128/127 |
| **Skinning: `Tendon` matrix order** | `Mat2D(xx, xy, yx, yy, tx, ty)`; x-unit is `(xx, xy)` | swapping renders mirrored or collapsed, `problems` empty |

Unit traps, which at least fail loudly once you look:

- `rotation` is **radians**. A full turn is `6.2831855`.
- `LinearAnimation.duration` is **frames** (`fps` defaults to 60).
- `StateTransition.duration` is **milliseconds**.
- `exitTimeIsPercetange` is misspelled in the format. Write the typo.

And the meta-trap: **a clean `--verify` proves names, not wiring.** Misspelled
elements and unknown attributes *are* caught. What survives is everything where
the names are right and the wiring is wrong. After every change:

```bash
rive . --verify
rive inspect . --summary          # problems, and what got built by type
rive . --screenshot --advance=1   # appearance, one frame after the machine starts
```

Then read the output for what was actually asked for. The type counts in
`--summary` are the cheapest real check: they catch a whole category of
"emitted nothing" bugs.

---

## Conventions

Settled while building the mature stage; hold these for the other stages and
other plants.

**Ids.** One flat namespace across the whole document — `client:object`, no
leading zeros, `0:0` reserved. The generator mints one for **every** element,
vertices included, via a monotonic `Ids` allocator. `rive` does not rewrite ids
on `--verify` or `inspect` (checked by checksum), but it does on export and
push, so minting them up front keeps a generated file byte-stable and leaves the
write-back nothing to do. A hand-written starter `scene.rml` was deleted for
exactly this reason: its artboard was `0:2`, which the allocator also mints.

**Draw order is reversed from SVG.** The *first* `Shape` declared paints on
**top**. Within one `Shape` it inverts again: the later paint child draws on
top, so `Fill` then `Stroke` reproduces SVG's order.

**One `<g id="...">` becomes one named `Node`; one `<path id="...">` becomes one
named `Shape`.** Names carry across verbatim, so the RML tree reads like the SVG.

**Every animatable part gets nested transform nodes, one per concern.** A frond
is `<Node name="X-droop">` wrapping `<Node name="X-sway">`. Both sit at the
shared base point (512, 882); the art inside is emitted relative to it. Each
rotation then has exactly one owner, so independent timelines compose instead of
overwriting one another. Two state machine layers writing the same property
would not — the later layer wins.

**Colours are carried verbatim** from the palette constants through `argb()`.
No re-picking, no approximation.

**Canvas.** 1024×1024, ground line at y=900, plant base at (512, 882). Root
canvases put their ground line at y=0 so a plant canvas stacks directly on top.

---

## Adding a stage

The mature stage is the only one emitted to RML so far. The path for the rest:

1. `stage(n)` already returns the drawables for every stage — the geometry
   exists. Stages 1–3 add `fiddlehead()` parts, stage 5 adds spore `Dots`.
2. `mature_rml()` is currently hard-wired to `MATURE_ORDER` and `base_mound(125)`.
   Generalise it to take a stage number, reading the same `{1: 70, 2: 90, …}`
   mound widths `stage()` uses.
3. Fiddleheads have no `FRONDS` entry, so they need their own sway/droop
   parameters. A coil probably wants to *uncurl* rather than sway.
4. Decide one artboard per stage versus one artboard with a `Solo`. Separate
   artboards are simpler and what `docs rigging` suggests `Solo` is *not* for;
   a growth transition between stages would argue the other way.
5. Roots are a second canvas with its own artboard, and the one place bones are
   clearly worth it.

---

## Progress

### Step 1 — research

Established (a), (b) and (c) above. The finding that changed the plan: Rive's
polar handle storage, which is why the generator emits RML rather than anyone
transcribing path data.

### Step 2 — the mature artboard

`fern-mature.rml`, generated. 172 KB of markup, 30 KB built `.riv`.

```
FernMature  1024x1024   1524 objects
  Node 12          plant, base, and 5 × (droop + sway)
  Shape 17         one per <g> child path, plus the two base shapes
  PointsPath 250   5 stems + 133 leaflets + 111 midribs + 1 mound
  StraightVertex 685 / CubicDetachedVertex 491
  Ellipse 3        base-clumps
  Fill 12 / Stroke 16 / SolidColor 28
```

The refactor that made this possible is described under
[The generator](#the-generator). Decisions taken: cap sampling moved into
`tapered()` rather than the emitter; dots stored as data; draw order reversed;
nested droop/sway nodes.

Checked numerically rather than by eye — every emitted vertex and handle
reconstructed from the RML back to absolute coordinates and compared against the
model the SVG writer reads. 1176 vertices and 3 ellipses, **max vertex error
0.005 px, max handle error 0.009 px**, entirely the emitter's 2-decimal
rounding.

`inspect` warned `artboard-without-style`; the artboard now declares a
`LayoutComponentStyle` and points `styleId` at it.

### Step 3 — the sway

One `LinearAnimation` (`Sway`, 300 frames at 60fps, looping) keying `rotation`
(propertyKey 15) on each frond's inner `*-sway` node. Outer `*-droop` nodes
untouched.

```
sway_angle(t) = A·sin(2π(t + φ₁)) + 0.28·A·sin(4π(t + φ₂))
```

| Frond | Amplitude | Tip radius | Tip sweep |
|---|---|---|---|
| `frond-back-left` | 1.86° | 704 px | 45.6 px |
| `frond-back-right` | 1.52° | 704 px | 37.3 px |
| `frond-left` | 2.92° | 558 px | 56.9 px |
| `frond-right` | 2.43° | 558 px | 47.3 px |
| `frond-center` | 1.92° | 743 px | 49.8 px |

Both components are whole cycles per loop, so frame 0 and frame 300 agree
exactly — verified off the built file, `f0 == fN` to six decimals on all five.
The second harmonic is what stops five fronds sharing one period from reading as
a metronome; with only a fundamental everything re-synchronises visibly once a
cycle.

The curve is **sampled** at 24 keyframes per frond rather than keyed at its
extremes: with two components at different phases there is no small set of
frames where the turning points line up. Measured linear-interpolation error is
1.43% of amplitude, about 0.04°.

Verified: 5 `KeyedObject` / 5 `KeyedProperty` / 125 `KeyFrameDouble`, every
`objectId` resolving to a `*-sway` node rather than a droop one, every keyframe
reading back as `linear`. Both of those would build clean if wrong.
