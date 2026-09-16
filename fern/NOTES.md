# RML capability notes — animated fern

Research pass before building. Everything below was checked against
`rive docs` / `rive schema` in this toolchain, not from memory. Doc topic and
type names are cited so each claim can be re-checked.

Source art: `fern_generator.py` (parametric Python) + the nine SVGs it writes.
The mature stage is `fern-stage-4-mature.svg` — five `<g id="frond-*">` groups
plus `<g id="base">`, all fronds already emanating from `BASE = (512, 882)`.

---

## (a) Custom vector paths with cubic bezier vertices — **yes**

`docs drawing` → "Custom paths". A `Shape` holds one or more `PointsPath`
children; each holds an ordered vertex list in the shape's local space.

Four vertex types:

| Type | Handles |
|---|---|
| `StraightVertex` | corner; optional `radius` (auto-clamped) |
| `CubicMirroredVertex` | `rotation`, `distance` — symmetric |
| `CubicAsymmetricVertex` | shared direction, independent lengths |
| `CubicDetachedVertex` | `inRotation`/`inDistance`, `outRotation`/`outDistance` |

`rive schema CubicDetachedVertex` confirms: typeKey 6, own props
`inRotation` (key 84), `inDistance` (85), `outRotation` (86), `outDistance` (87),
plus `x` (24) / `y` (25) from `Vertex`. All animatable **and** bindable.

### The one real impedance mismatch

**Rive stores bezier handles as polar (angle + length) offsets from the vertex,
not as absolute control points like SVG.** SVG `C c1 c2 p` must be converted:

```
outRotation(P0) = atan2(c1 - P0),  outDistance(P0) = |c1 - P0|
inRotation(P1)  = atan2(c2 - P1),  inDistance(P1)  = |c2 - P1|
```

`rotation` is **radians** everywhere in the format (`docs gotchas` —
"Rotation is radians"). This conversion is exactly why hand-transcribing the
SVG `d` strings is a bad idea and why the generator should emit RML directly:
`fern_generator.py` already holds the control points as tuples *before* they are
flattened into a `d` string, so the polar form is a few lines of math on data we
already have.

Notes that will bite:

- `isClosed="true"` closes the contour. An open `PointsPath` with a `Fill`
  still fills across an implied closing line — the leaflet outlines must all be
  closed.
- A `Shape` may hold **several** `PointsPath` children which combine into one
  filled path. This maps 1:1 onto how the generator already batches e.g. every
  leaflet of a frond into a single `<path d="...">` with one fill + one stroke.
- `isClockwise` / `Fill.fillRule` (`nonZero` | `evenOdd`) decide holes.
- `tapered()` in the generator emits a pure polyline (plus one `A` arc cap) —
  that becomes `StraightVertex` runs, no conversion needed. Only `leaflet()`
  and `base_mound()` emit true cubics.
- Paint: `Fill` and `Stroke` are both children of the `Shape`;
  `Stroke` takes `thickness`, `cap`, `join`. Colour is `colorValue="AARRGGBB"`
  — bare hex, no `#`, **alpha first**. So `#6FA35A` → `FF6FA35A`.

## (b) Bones and skinning — **yes, but not needed for the sway**

`docs rigging`. `RootBone` (`x`/`y`/`length`/`rotation`) starts a chain,
`Bone` children inherit from the parent's tip; `rotation` is radians relative
to the parent.

Skinning: a `Skin` nests **inside** the `PointsPath` it deforms, holding one
`Tendon` per bone (recording the bind pose as a `Mat2D`), and every vertex
carries a `Weight` — `indices`/`values` packed one byte per slot, max four
bones per vertex. Sharp edges:

- `indices` is **1-based**; a `0` slot means "identity", which looks exactly
  like bones not working.
- `values` must total **255** (split an even blend 128/127) — the runtime
  divides by 255 and does not renormalize.
- `Tendon`'s matrix is read `Mat2D(xx, xy, yx, yy, tx, ty)`; x-unit is
  `(xx, xy)`, y-unit is `(yx, yy)`. Swapping them renders mirrored/collapsed
  with an empty `problems` list.
- Cubic vertices need `CubicWeight` (adds `inIndices`/`inValues` and
  `outIndices`/`outValues`) so the handles deform with the point.

**Recommendation: skip bones for steps 3 and 4.** A frond sway is a rigid
rotation about the shared base point, and `docs transforms` says a `Node` is the
group: wrap each frond in a `Node` placed at (512, 882), draw the frond's
geometry in that node's local space, and key the node's `rotation`. One keyed
property per frond instead of a tendon per vertex, and it is what the doc
explicitly recommends for "an object that rotates about the wrong point".

Bones stay on the table for a later, nicer version — a 2–3 bone chain per
frond would let the tip lag behind the base (whip) instead of the whole frond
rotating rigidly, and the same rig would serve the roots, which the generator
already groups one-per-primary "so each can get its own bone chain".

## (c) A view model number driving a state machine — **yes, and it is the current mechanism**

`docs data` + `docs state-machines`. `StateMachineNumber`/`Bool`/`Trigger`
inputs are explicitly **deprecated**; view model properties are the replacement.

```xml
<ViewModel defaultInstanceId="0:41" name="Fern" id="0:40">
    <ViewModelPropertyNumber name="vitality" id="0:45"/>
    <ViewModelInstance exports="true" name="Default" id="0:41">
        <ViewModelInstanceNumber propertyValue="1" viewModelPropertyId="0:45"/>
    </ViewModelInstance>
</ViewModel>
```

The artboard names it with `viewModelId`, the view model names its default with
`defaultInstanceId`, each instance value names its property with
`viewModelPropertyId`. `defaultInstanceId` and `exports` are editor-only —
`rive schema ViewModel --all` to see them, but they still belong in the RML.
Also set `Artboard.viewModelInstanceId` so the artboard opens populated in the
editor.

Two ways to consume the number, and for `vitality` (continuous 0–1) the
second is the right one:

1. **Threshold** — `TransitionViewModelCondition` with
   `opValue="lessThan"` etc., left side a
   `TransitionPropertyViewModelComparator` wrapping a `BindablePropertyNumber`
   holding a `DataBindContext`, right side a `TransitionValueNumberComparator`.
   That gives discrete states with a blend time, not a continuous droop.
2. **`BlendState1DViewModel`** (`docs easing` → "Blending from a view model") —
   the current form of a 1D blend state. It has **no `inputId`**: nesting a
   `BindablePropertyNumber` with a `DataBindContext` *is* the wiring.

```xml
<BlendState1DViewModel id="0:70">
    <BindablePropertyNumber>
        <DataBindContext sourcePathIds="0:40-0:45" propertyKey="636"/>
    </BindablePropertyNumber>
    <BlendAnimation1D animationId="0:71" value="0"/>   <!-- fully drooped -->
    <BlendAnimation1D animationId="0:72" value="100"/> <!-- upright -->
</BlendState1DViewModel>
```

`propertyKey="636"` is `BindablePropertyNumber.propertyValue`
(`rive schema BindablePropertyNumber`, typeKey 473).

**Blend axis traps** (`docs easing`, all three silent):

- **Weights run 0–100, not 0–1.** Authoring the axis over 0–1 collapses every
  pose onto the first one. So `vitality` 0–1 needs a
  `DataConverterRangeMapper` (`minInput=0 maxInput=1 minOutput=0 maxOutput=100`,
  `clampLower`/`clampUpper` true) on the bind — the same converter can carry an
  interpolator, which is where the easing should live, not on the poses.
- `BlendAnimation1D` children must be in **ascending `value` order**; the
  runtime binary-searches and does not check.
- **Every blended property must be keyed in every pose**, or it jumps instead
  of blending. With five fronds × rotation, that means all five keyed in both
  the upright and the drooped timeline.

### Combining sway (step 3) with droop (step 4)

The sway is a looping timeline; the droop is a blend axis. They both want to
own `rotation` on the same five nodes, so they must not be keyed in the same
layer. Two options:

- **Two `StateMachineLayer`s** — a machine can have several. One layer plays
  the looping sway, the other holds the blend state. Both write `rotation`, and
  the later layer wins, which would kill the sway. So instead:
- **Nest the transforms** — an outer `Node` per frond keyed only by the droop
  blend, an inner `Node` keyed only by the sway loop. Transforms compose, each
  property is owned by exactly one timeline, and no layer fights another.
  This is the plan.

---

## Other things worth pinning down before writing the emitter

- **Ids are one flat namespace across the whole document**, `client:object`
  numeric pairs, no leading zeros, `0:0` reserved. Duplicates fail the build.
  The generator needs a single monotonic id allocator.
- `rive` **writes ids back into the `.rml`** for elements left without one.
  Since the file is generated, the generator should mint every id itself so a
  rebuild is byte-stable and the write-back has nothing to do.
- **Draw order is reversed from SVG**: the *first* `Shape` declared paints on
  **top** (`docs drawing` / `docs transforms`). The generator's frond order is
  back-left, back-right, left, right, center — SVG order, so the RML emitter
  must reverse it.
- Within one `Shape`, paint children are the other way round: later-declared
  paint draws on top, so `Fill` then `Stroke` reproduces the SVG.
- `LinearAnimation.duration` is in **frames** (fps default 60), but
  `StateTransition.duration` is in **milliseconds**.
- `KeyFrameDouble` for `rotation` (propertyKey 15, radians). A mismatched
  keyframe type fails **silently**.
- `interpolationType="cubic"` with no `CubicEaseInterpolator` child eases
  nothing, silently.
- The artboard needs `defaultStateMachineId` or **nothing binds and nothing
  receives input**, however correct the rest is.
- A clean `--verify` proves names, not wiring. After every stage:
  `rive fern --verify`, then `rive inspect fern --summary` for problems and
  type counts, then `rive fern --screenshot --advance=1`.
- Never author `nameBased="true"` on a `DataBindContext` — this toolchain
  cannot produce the manifest it needs, and it fails silently in both
  directions.

## Decisions taken (approved before step 2)

- **0–1 → 0–100 via `DataConverterRangeMapper`**, with the easing interpolator
  on the converter rather than on the blend poses.
- **Nested transforms per frond**: an outer `*-droop` `Node` at the shared base
  point (512, 882) and an inner `*-sway` `Node` inside it. One owner per
  rotation, so the two timelines compose instead of fighting.
- **Draw order reversed** from the SVG when emitting RML.
- **Stem tip caps are sampled into straight vertices inside `tapered()`**, not
  at emit time. The SVG arc is gone: both writers now read the same sampled
  points, so the two outputs cannot drift, and the emitter only ever meets
  straight and cubic vertices. `CAP_SAMPLES = 8`. This covers fiddlehead coils
  and root tips for free, since they all go through `tapered()`.
- **Dots are data** (`Dot(cx, cy, rx, ry)`), not path strings. The SVG writer
  renders them as the two-arc idiom it used before; the RML emitter writes
  `<Ellipse>`. Covers `base-clumps` and the bloom-stage spore dots alike.

The refactor generalised this: geometry is now a small drawable model
(`Contour` / `Dot` → `Path` / `Dots` → `Group`) and **the SVG writer and the
RML emitter are two readers over it**. Neither format is the source of truth;
the model is. `Contour` holds handles as *absolute* control points the way SVG
writes them, and only the RML emitter converts to polar.

## Measured shape of the mature stage

Counted off `fern-stage-4-mature.svg`, per frond:

| Path | Contours | Segment types |
|---|---|---|
| `*-stem` | 1 (closed) | 129 lines + 1 arc cap |
| `*-leaflets` | 25–29 (closed) | 2 cubics each |
| `*-midribs` | 20–26 (open) | 1 **quadratic** each |

So roughly 300 vertices per frond, ~1,500 for the artboard plus the base —
well inside anything that should need optimising. Three consequences for the
emitter:

- The stem is already a polyline: `StraightVertex` throughout. The single `A`
  round cap has no Rive equivalent as a path segment — approximate it with a
  few sampled `StraightVertex`, or give the last vertex a `radius`.
- Leaflets are the only true cubics, two per contour, and they need the polar
  conversion in (a).
- **Midribs are quadratic (`Q`) and open.** Elevate each to a cubic
  (`c1 = P0 + 2/3(Q - P0)`, `c2 = P2 + 2/3(Q - P2)`) before converting to
  handles, and emit them with `isClosed` left false, a `Stroke` and no `Fill`.
- `base-clumps` uses SVG elliptical arcs (`a`) for its dots — sample those to
  a closed vertex loop, or swap them for `Ellipse` geometry, which is what they
  actually are.

Nothing here argues for reducing `pairs` or the sample rate. Still worth
checking the built `.riv` size after stage 1 rather than assuming.


---

## Step 2 result — mature artboard

`fern-mature.rml`, generated by `fern_generator.py` (172 KB of markup,
30 KB built `.riv`). `rive fern --verify` clean, `problems: []`.

```
FernMature  1024x1024   1524 objects
  Node 12          plant, base, and 5 x (droop + sway)
  Shape 17         one per <g> child path, plus the two base shapes
  PointsPath 250   5 stems + 133 leaflets + 111 midribs + 1 mound
  StraightVertex 685 / CubicDetachedVertex 491
  Ellipse 3        base-clumps
  Fill 12 / Stroke 16 / SolidColor 28
```

Colours are carried across verbatim — `#6FA35A` → `FF6FA35A` and so on for all
nine palette entries, via `argb()`.

Geometry was checked numerically rather than by eye: every emitted vertex and
handle was reconstructed from the RML back to absolute coordinates and compared
against the model the SVG writer reads. 1176 vertices and 3 ellipses, max
vertex error 0.005 px and max handle error 0.009 px — entirely the emitter's
2-decimal rounding.

The artboard carries a `LinearAnimation` named `Sway` (240 frames, looping) and
a one-state machine playing it. **Both are empty placeholders** so the artboard
is alive and binds will push once step 3 fills the timeline in.

Two things dealt with along the way:

- `scene.rml` — the starter skeleton — was **deleted**. Its artboard was `0:2`,
  which the generator's own allocator also mints, and ids share one namespace
  across the whole document.
- `inspect` warned `artboard-without-style`; the artboard now declares a
  `LayoutComponentStyle` and points `styleId` at it.

`rive` does **not** rewrite ids on `--verify` or `inspect` (checked by
checksum), but the generator mints one for every element anyway, vertices
included, so a future `push` has nothing to write back into a generated file.


---

## Step 3 result — the sway

One `LinearAnimation` (`Sway`, 300 frames at 60fps, `loopValue="loop"`) keying
`rotation` (propertyKey 15, radians) on each frond's **inner `*-sway` node**.
The outer `*-droop` nodes are untouched and stay free for step 4.

Each frond's curve is a fundamental plus a second harmonic at 28% weight, each
with its own phase:

```
sway_angle(t) = A·sin(2π(t + φ₁)) + 0.28·A·sin(4π(t + φ₂))
```

Both components complete a whole number of cycles per loop, so frame 0 and
frame 300 agree **exactly** — confirmed off the built file, `f0 == fN` to six
decimals on all five fronds. The harmonic is what stops five fronds sharing one
period from reading as a metronome; with only a fundamental, everything
re-synchronises visibly every 5 seconds.

| Frond | Amplitude | Tip radius | Tip sweep |
|---|---|---|---|
| `frond-back-left` | 1.86° | 704 px | 45.6 px |
| `frond-back-right` | 1.52° | 704 px | 37.3 px |
| `frond-left` | 2.92° | 558 px | 56.9 px |
| `frond-right` | 2.43° | 558 px | 47.3 px |
| `frond-center` | 1.92° | 743 px | 49.8 px |

Two decisions worth recording:

- **The curve is sampled (24 keyframes per frond), not keyed at its extremes.**
  Two components at different phases means there is no small set of frames where
  the turning points line up, so keying extremes would need per-frond frame
  numbers and would still only approximate the sum. Sampling sidesteps it, and
  makes the shape of the curve a pure function of `sway_angle()`. Measured
  linear-interpolation error is **1.43% of amplitude** — about 0.04°.
- **`interpolationType="linear"` is written on every keyframe.**
  `rive schema KeyFrameDouble` gives the default as **`hold`**, not linear — left
  off, the sway would step between samples 12 times a second and build perfectly
  clean. This is the same class of silent failure as the `cubic`-without-an-
  interpolator trap.

Verified: `problems: []`, 5 `KeyedObject` / 5 `KeyedProperty` / 125
`KeyFrameDouble`, every `objectId` resolving to a `*-sway` node (not a droop
one) and every keyframe reading back as `linear`. Screenshots at frames 1, 75,
150 and 225 are four distinct images, with the stem bases staying planted in the
mound.
