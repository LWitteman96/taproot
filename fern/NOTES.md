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
- [Getting it into the app](#getting-it-into-the-app) — the copy step, and the stacking contract
- [The generator](#the-generator)
- [RML capabilities](#rml-capabilities) — paths, bones, view models
- [Traps: silent failures](#traps-silent-failures)
- [Conventions](#conventions)
- [Previewing: a cheatsheet](#previewing-a-cheatsheet) — the commands
- [Verification recipes](#verification-recipes) — proving a change works
- [Adding a stage, or another plant](#adding-a-stage-or-another-plant)
- [Progress](#progress) — what landed, step by step

---

## The shape of the project

```
fern_generator.py     the source of truth for the fern: palette, parts, stages, tables
../plantgen/          the shared half: geometry, SVG writer, RML emitter, wiring
pngdiff.py            dependency-free PNG reader, for measuring render changes
preview.sh            renders every stage at every vitality into build/preview/
fern-data.rml         generated — the shared Fern view model
fern-roots.rml        generated — the root system, its own artboard
fern-stage-*.rml      generated — one artboard per growth stage
fern-stage-*.svg      generated — the same five, as flat art
fern-roots-*.svg      generated — the four root levels
rive.yaml             project config: name, default artboard, log paths
build/                gitignored: fern.riv, fern.png, logs
```

**The `.rml` and `.svg` files are generated. Edit `fern_generator.py`, never
them.** Nothing in `build/` is committed, and no `.riv` has been added to the
Flutter app's assets yet.

The art comes from `docs/design-spec.md`'s garden metaphor: six growth stages
(seed → sprout → seedling → young → mature → bloom) and four root levels,
stacking so the ground lines meet. **All six stages and the roots are built.**

A project compiles every `.rml` in it as one document, so the six files above
produce one `.riv` with **seven** artboards sharing one view model: six stages
plus `FernRoots`. `rive fern` opens `FernMature` (named in `rive.yaml`); the
others are `rive fern --artboard=FernSeed` and so on.

The view model exposes two numbers, both 0–1: **`vitality`** (droop, colour,
sway amplitude) and **`roots`** (root growth, and the stability lean on the two
tall stages).

---

## Getting it into the app

The Flutter app ships `assets/rive/fern.riv`, a **committed copy** of the build
output. It does not rebuild from this project, so regenerating here does not
update the app:

```bash
python3 fern_generator.py      # rml from the generator
rive . --once                  # riv from the rml
cp build/fern.riv ../assets/rive/fern.riv
```

Skip the last step and the app keeps rendering the previous plant, with nothing
reporting it. The asset is binary, so every refresh is a blob in the diff —
regenerate deliberately rather than incidentally.

### The stacking contract

The roots are a separate artboard because a view-model bind inside a
`NestedArtboard` is inert ([Traps](#traps-silent-failures)). The host therefore
stacks `FernRoots` under a stage artboard — ground lines meet, since the stage
canvases put theirs at y=900 and the roots artboard at y=0.

**Both artboards must be bound to one shared `ViewModelInstance`**, not left to
auto-bind. Verified from the Flutter runtime, both directions:

- one instance handed to both controllers (`DataBind.byInstance`) — a single
  write of `roots` is visible through both, and both advance against it;
- two auto-binds — each gets its **own** instance and they do not share a value.

The second is right for a lone plant and silently wrong for the stacked pair:
the roots would grow while the plant above them leaned as though there were
none. Nothing reports it, which is why the app-side tests pin both.

---

## The generator

> Since the oak: the generic half of this generator — the geometry model, both
> writers, the sway/droop/lean/roots wiring — lives in `../plantgen`, and
> `fern_generator.py` hands the fern's art and tables to a `Species`. The fern's
> output was byte-identical across the move. What follows still describes how
> it works; `../oak/NOTES.md` has what the move added.

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

**Vertex properties are bindable as well as animatable** — `x`, `y` and all four
cubic handle properties carry `AB` in the schema. So data can drive individual
vertices and their handles directly, which is a route to shape morphing with no
bones and no `Skin`: a fiddlehead uncurling is a candidate. Untested here; the
cost is one bind per vertex, so it suits a handful of control points rather than
a 130-vertex stem.

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

### Nested artboards

`NestedArtboard artboardId=` embeds another artboard. The source must be marked
`isComponent="true"` and listed by a `<ComponentAsset artboardId=...>` root
element, or the file is malformed.

**It does not carry data binding.** This was measured rather than assumed:
`FernSprout` nested inside an otherwise empty artboard, `vitality` set to 0 and
1, and the nested plant changed by **0 pixels** where the same artboard
standalone changed by 8770. Clean verify, `problems: []`, and the data dump
reports `"inherits": true` — it claims the parent's context and then ignores it.

Two ways through, and only one is usable from data:

| | |
|---|---|
| `NestedNumber.nestedValue` | animatable, **not bindable** — a view model number cannot reach a nested state machine input |
| `NestedRemapAnimation.time` | animatable **and** bindable (key 202) — a parent can scrub a whole child timeline from one number, "with no state machine on either side". `time` is a fraction of the duration, not seconds |

So a component driven by data has to be either a root artboard the host binds
itself, or a single timeline scrubbed through `NestedRemapAnimation`. A blend
state inside a nested child is inert.

`NestedArtboard.artboardId` *is* bindable (key 197), and `ViewModelPropertyArtboard`
exists, so **which** artboard is nested can be data-driven even though what is
inside it cannot.

**`cubic` and `cubicValue` are not variants of one thing.** They take the same
four numbers and read them completely differently: `cubic` with a
`CubicEaseInterpolator` shapes **time**, normalized 0–1, so the result stays
between the two keyframed values. `cubicValue` with a `CubicValueInterpolator`
shapes the **value** — the bezier's control points are `[from, y1, y2, to]` and
`y1`/`y2` are in the property's own units, so the motion can leave the
keyframed range. That is the one to reach for if a frond should overshoot on
the way back up.

`propertyKey="636"` is `BindablePropertyNumber.propertyValue`
(`rive schema BindablePropertyNumber`, typeKey 473). `sourcePathIds` is
`viewModelId-propertyId`, absolute.

### Converters, and the one the app will need

`DataConverterRangeMapper` is one of about eleven converters (`docs data` →
"Converters"), all root elements named from a bind by `converterId`. The others
cover arithmetic (`DataConverterOperationValue`, `DataConverterFormula`),
rounding, and number↔string conversion.

One is worth knowing about before the Flutter integration:
**`DataConverterInterpolator` eases a bound value over `duration` seconds**
rather than remapping it, so a value that *changes* animates to its new setting
instead of jumping. That is a different job from the range mapper's static
remap, and it is what a live `vitality` will want — the app recomputing vitality
after a completion would otherwise snap the fern to its new pose in one frame.
Converters chain through a `DataConverterGroup`, so the two compose.

Not wired yet: nothing sets `vitality` at runtime, so nothing has been seen to
jump.

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
| **`interpolationType` is only tested for `hold` at runtime** | the *nested interpolator* decides the behaviour, so flipping the enum to `linear` does **not** disable an easing curve | to disable easing, remove the interpolator child; keep the enum consistent with the child anyway, since the editor reads it |
| **`nameBased="true"` on a `DataBindContext`** | this toolchain cannot emit the manifest it indexes; the bind is inert | never author it; `problems` is meaningless in both directions here |
| **`Feather` inside a `Fill`** | the paint vanishes entirely | feather strokes; for a soft fill use a `RadialGradient` with an alpha-`00` outer stop |
| **`GradientStop` with no `position`** | all stops sit at 0, gradient renders flat | always set `position` |
| **A `ViewModelInstanceValue` whose `viewModelPropertyId` points at nothing** | silently inert; these ids are never resolved, so `inspect` says nothing | check by hand |
| **A view-model bind inside a `NestedArtboard` does not resolve** | the child renders but never responds to data. Verify is clean, `problems: []`, and the data dump even reports `"inherits": true` | measured: nested 0px vs standalone 8770px for the same data change. Drive a nested child through `NestedRemapAnimation.time` (bindable) or keep it a root artboard and let the host bind both |
| **`--data` cannot change a value mid-run** | it sets the property *before the scene runs*, so a converter that eases changes has nothing to ease | drive the change from a listener (see [Verification recipes](#verification-recipes)) |
| **`sourcePathIds` is not emitted by `inspect --json`** | the bind's path is absent from the tree, like `interpolatorId` — you cannot eyeball it | read `problems` for `unresolved-bind-path`, and A/B with `--data` |
| **`DataConverterRangeMapper.interpolationType` defaults to `linear`** | same attribute name as a keyframe's, opposite default (`hold`) | a converter eases by default once given an interpolator; a keyframe does not |
| **Skinning: `indices` is 1-based** | a `0` slot is the identity transform — looks exactly like bones not working | `tendonIndex + 1` |
| **Skinning: `values` must total 255** | the runtime divides by 255 and does not renormalize | split an even blend 128/127 |
| **Two `--advance` steps around a `--pointer` are not one `--advance` of the sum** | the scene lands on a different animation time, so a pointer-driven capture compared against a plain capture at the "same" frame shows a difference that is entirely the measurement (found on the oak: a spurious ~15,000 px "residual droop" that was still there when the click changed nothing at all) | give both sides of the comparison the **same advance structure**, not the same total; a click that changes nothing is the control that proves it |
| **A disc and a stroke-shape in one path, wound opposite ways** | nonZero fill cancels where they overlap: the joint disc meant to hide a bend cut a hole in the stem instead (found on the sunflower, in the SVG before any build -- both writers fill the same way) | give joint discs their own shape (`Dots`/`Ellipse`), or wind them the same way as the contour they overlap |
| **`rive --screenshot` writes an opaque background; a headless-Chrome SVG screenshot writes a transparent one** | diffing the two makes ~99% of pixels differ and hides the real answer | composite both over the *same* colour before diffing — rive's is `#1D1D1D` |
| **Skinning: `Tendon` matrix order** | `Mat2D(xx, xy, yx, yy, tx, ty)`; x-unit is `(xx, xy)` | swapping renders mirrored or collapsed, `problems` empty |
| **`--advance=0` applies no data at all** | it is the right frame for a *stage*, where every sway key is 0 and the artboard sits in the rest pose the SVG describes — but on an artboard whose poses *are* data-driven blends it renders the authored pose whatever `--data` says. On `SunflowerRoots` all four levels then diff against the same level-4 picture and only level 4 passes; the roots-0.15 render at `--advance=0` is byte-identical to the level-4 one | advance past the smoothing (120 frames) on an artboard with no sway; a stage cannot be advanced, so the two halves of a render diff need different advances |
| **A joint probe at fixed coordinates** | a joint sits at a pivot and pivots move — the sunflower's neck travels 150 px between vitality 1 and 0 — so the probe lands off the stem and reports a hole that is really a mis-aimed sample | compose the transform per pose, or crop and look (`plantgen/crop_joints.py`) |
| **Counting background enclosed by the plant** | looks like a coordinate-free hole detector and is not: `OakMature`, already reviewed and passed, encloses 35,748-62,596 px of sky between its foliage by design, and a real joint hole is a few hundred px inside that | not usable as a gate on foliage-heavy art |

Unit traps, which at least fail loudly once you look:

- `rotation` is **radians**. A full turn is `6.2831855`.
- `LinearAnimation.duration` is **frames** (`fps` defaults to 60).
- `StateTransition.duration` is **milliseconds**.
- `exitTimeIsPercetange` is misspelled in the format. Write the typo.

**`--verify` does not catch a broken bind. `inspect` does.** Demonstrated on
this project by pointing `sourcePathIds` at a view model that does not exist:

```
rive . --verify          → verified (0 errors, 0 warnings)
rive inspect . --summary → {"kind": "unresolved-bind-path",
                            "message": "sourcePathIds root view model 0:9998
                                        is not declared in this file"}
```

This is the concrete reason `AGENTS.md` asks for both commands rather than
either. A green `--verify` on a data-bound file means almost nothing.

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

For anything data-driven, the direct check is to **change the data and see the
picture change**:

```bash
rive . --screenshot=a.png --data=vitality=1 --advance=1
rive . --screenshot=b.png --data=vitality=0 --advance=1
```

Identical files mean nothing is bound, whatever `problems` says. The `--data`
path is relative to **the view model instance bound to the artboard** — neither
the view model's name nor the instance's name appears in it, so it is
`--data=vitality=0`, not `--data=Fern/vitality=0`. A wrong path prints
`no property at "..."` rather than failing silently.

---

## Conventions

Settled while building the mature stage; hold these for the other stages and
other plants.

**Ids.** One flat namespace across the whole document — `client:object`, no
leading zeros, `0:0` reserved. The generator mints one for **every** element,
vertices included, via a monotonic `Ids` allocator. **Each file gets its own id
client** — `0` for the shared data, `1`–`5` for the stages — so ids cannot
collide across files that share one namespace, without any file needing to know
how many ids its neighbours used. `rive` does not rewrite ids
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
No re-picking, no approximation. The one exception is the droop's dry palette,
which is a second set of constants (`LEAF_DRY`, `LEAF_BACK_DRY`) mapped from the
healthy ones by `DRY_FILL` — so a palette change updates both ends together.

**Names are the public surface.** The state machine is `Fern`, the view model is
`Fern`, its property is `vitality`. The host addresses all of these by name, so
renaming one is a breaking change in a way renumbering an id is not.

**Canvas.** 1024×1024, ground line at y=900, plant base at (512, 882). Root
canvases put their ground line at y=0 so a plant canvas stacks directly on top.

---

## Previewing: a cheatsheet

The artboards are `FernSeed`, `FernSprout`, `FernSeedling`, `FernYoung`,
`FernMature`, `FernBloom` and `FernRoots`. `vitality` is `0`–`1` and
**defaults to `1`**, which is the upright,
full-colour pose — so a preview with no `--data` looks static on purpose.

### Live preview

```bash
rive fern                                       # FernMature (rive.yaml names it)
rive fern --artboard=FernSprout                 # any other stage
rive fern --artboard=FernYoung --data=vitality=0.3
```

`--data` is a launch value, not a scrubber: it is applied **before the scene
runs**, so changing it means relaunching. The watcher rebuilds on file change,
so re-running the generator in another terminal updates the open preview — which
is how to compare sway modes:

```bash
python3 fern_generator.py --sway=wind          # then look at the open preview
python3 fern_generator.py --sway=independent   # back to the default
python3 fern_generator.py --amplitude=1.6      # exaggerate, to see it clearly
```

### Stills

One frame, any stage, any vitality:

```bash
mkdir -p build/shots
rive fern --screenshot=build/shots/young-30.png \
          --artboard=FernYoung --data=vitality=0.3 --advance=60
```

`--advance=60` steps 60 frames at 60fps before capturing. Without it you get the
pose before anything has advanced; and since the sway is a 300-frame loop, the
frame number is *which* moment of the sway you are looking at. Use the same
number across a comparison set or the sway will look like a difference.

The whole grid — every stage at every vitality — is one script:

```bash
./preview.sh                                  # 5 stages x 5 vitalities
STAGES="Mature Bloom" ./preview.sh            # just those
VITALITIES="1 0" ./preview.sh                 # just the ends
FRAME=150 ./preview.sh                        # a different point in the sway
VIEWPORT=384x384 ./preview.sh                 # smaller, faster
```

Output lands in `build/preview/` (gitignored).

### Seeing the sway

A screenshot is a still, so the sway is invisible in one. Capture the same
artboard and vitality at several frames:

```bash
for f in 1 75 150 225; do
  rive fern --screenshot=build/shots/sway-$f.png --artboard=FernMature \
            --data=vitality=1 --advance=$f
done
```

Frames 0 and 300 are the same pose — the loop is seamless by construction.

### Checking a value landed

```bash
rive fern --data-dump=- --data=vitality=0.25 --advance=1
```

```json
{ "name": "vitality", "path": "vitality", "type": "number",
  "value": 0.25, "changed": true }
```

### Three ways to preview nothing

Each of these produces a clean run and a misleading result:

- **A wrong `--artboard` name is not an error.** `--artboard=Nope` renders the
  *default* artboard and writes the png as though nothing happened. The only
  signal is the `showing FernMature [1/5]` line in the log — check it, or let
  `preview.sh` validate the name for you.
- **A screenshot path whose directory does not exist writes nothing**, prints no
  error, and exits 0. `mkdir -p` first.
- **The `--data` path takes no view model name.** It is `--data=vitality=0.3`,
  not `--data=Fern/vitality=0.3` — the path is relative to the instance bound to
  the artboard. A wrong path does say so: `no property at "..."`.
- **`--data-dump=` takes a path, `--data=` takes a value**, and they are one
  character apart. `--data-dump=vitality=0` writes the dump to a **file called
  `vitality=0`** in the working directory, sets no data, and reports success.
  Two of these were found in the repo root. Use `--data-dump=-` for stdout.

### Comparing two renders

Hashes answer *did it change*; `pngdiff.py` answers *by how much*.

```bash
md5 -q build/preview/Mature-v1.png build/preview/Mature-v0.png
python3 -c "import pngdiff; print(pngdiff.changed_pixels(
    'build/preview/Mature-v1.png', 'build/preview/Mature-v0.png'))"
```

Only compare renders that differ in one thing. Pixel counts across two different
droop poses are not comparable with each other.

### After any change to the generator

```bash
python3 fern_generator.py && rive fern --verify && rive inspect fern --summary
```

`--verify` catches names; `inspect` catches wiring. Neither catches a bind that
resolves and drives nothing — for that, change the data and look.

---

## Verification recipes

What has actually been used on this project, in increasing order of what it
proves. The first two are cheap enough to run on every change.

```bash
rive . --verify                   # names: misspelled elements, unknown attributes
rive inspect . --summary          # wiring: problems, plus type counts
```

Type counts are the cheapest real check — they catch "emitted nothing" bugs that
a clean build hides. Know roughly what you expect: 250 `PointsPath` for the
mature fern is 5 stems + 133 leaflets + 111 midribs + 1 mound.

**Geometry** — reconstruct emitted vertices back to absolute coordinates and
diff against the model both writers read. Catches the polar-handle conversion,
the origin offset and the straight/cubic choice in one pass. Used in step 2;
1176 vertices at a max error of 0.005 px.

**Animation** — read the built file rather than trusting the markup:

```bash
rive inspect . --json    # then assert on KeyedObject.objectId, propertyKey,
                         # and enums.interpolationType per keyframe
```

Used in step 3 to confirm all five `objectId`s pointed at `*-sway` nodes rather
than `*-droop` ones, and that no keyframe had silently kept the `hold` default.
Both would have built clean.

**Loop seams** — compare the first and last keyframe values. Exact equality is
the only thing that makes a loop invisible.

**Data binding** — A/B the render, since nothing else proves a bind drives
anything:

```bash
rive . --screenshot=a.png --data=vitality=1 --advance=1
rive . --screenshot=b.png --data=vitality=0 --advance=1
```

Two useful variants of the same trick:

- **Identical is sometimes the assertion.** At vitality 1 the render is
  byte-identical to the pre-droop capture at the same frame, which proves the
  droop contributes exactly zero when healthy.
- **Two frames at one data value** must differ if something else is still
  animating — that is how the sway was shown to survive under the droop.

**An effect you cannot A/B by flipping its enum.** Removing the interpolator
child changes the render; changing `interpolationType` does not. Disable the
thing itself, not the label on it.

**A change that only happens mid-run** — `--data` sets a value *before* the
scene runs, so it cannot exercise anything that eases a *change*. To test one,
inject a listener that writes the property, drive it with `--pointer`, and
capture on either side:

```xml
<!-- temporary scaffold: click the mound to water the fern -->
<StateMachineListenerSingle targetId="<mound>" listenerTypeValue="click" name="Water">
    <ListenerViewModelChange>
        <BindablePropertyNumber propertyValue="1">
            <DataBindContext sourcePathIds="<vm>-<vitality>" propertyKey="636" direction="true"/>
        </BindablePropertyNumber>
    </ListenerViewModelChange>
</StateMachineListenerSingle>
```

`direction="true"` is the whole trick — without it the bind reads instead of
writes and the click does nothing, silently.

```bash
rive . --screenshot=a.png --data=vitality=0.2 --advance=30 \
       --pointer=click@512,890 --advance=0
```

`--data-dump` on the same command confirms the click landed (`vitality = 1`).
Then compare against the same capture with the interpolator dropped from the
chain: smoothed, the fern is still fully drooped the instant after the click;
unsmoothed, it is already upright. Remove the scaffold afterwards — it is a test
fixture, not part of the scene.

**Does the build draw the art?** The strongest appearance check available, and
new on the oak. Both outputs already come from one geometry model, so render the
generated `.svg` with headless Chrome, render the `.riv` with
`rive --screenshot`, and diff. This compares the build against *the art the
build came from*, which is a much stronger statement than comparing either
against a reference image someone approved.

```bash
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless \
    --screenshot=build/svgpng/stage.png --window-size=1024,1024 \
    --default-background-color=00000000 --hide-scrollbars "file://$PWD/stage.svg"
rive . --screenshot=build/rest/stage.png --artboard=OakMature \
    --data=vitality=1 --data=roots=1 --advance=0
```

`--advance=0` is the point: at frame 0 every sway key is 0, so the artboard sits
in exactly the rest pose the SVG describes. Composite both over the same
background first (see the trap table). On the oak this gave 0.008%–0.687% of
pixels differing at all and **zero** differing strongly, across six stages and
four root levels — the residue is edge antialiasing, and it scales with edge
count rather than with anything structural.

Treat a *strongly*-differing pixel as the signal. Any at all means the emitter
and the writer disagree about something, and the count will point at which part.

**Measuring "less", not just "different".** Screenshot hashes answer *did it
change*; they cannot answer *by how much*. A ~40-line pure-Python PNG reader
(zlib + un-filtering scanlines, no dependencies) counts differing pixels, which
is enough to show that the sway at vitality 0 moves less than at 1, or that a
`SWAY_FLOOR` of 0 freezes the plant outright. Compare poses that are otherwise
identical — pixel counts across two different droop poses are not comparable.

Screenshots are `md5 -q` comparable, which is enough for all of the above
without an image library.

---

## Adding a stage, or another plant

All five fern stages are built, and the machinery that got there is generic. A
new stage — or a whole new plant — needs:

1. **Geometry**, as a list of `Group` parts plus a mound, the way `stage_parts`
   returns them.
2. **`tip` and `kind` on every animatable part.** These are what the droop and
   the sway read; nothing consults a per-stage table. `open_frond` and
   `fiddlehead` set them, so anything built from those gets them free.
3. **A `DROOP_DIRECTION` entry for each near-vertical part**, keyed
   `(stage, part name)`. The generator **raises** without one rather than
   guessing — see [Conventions](#conventions).
4. **A `DRY_FILL` entry for any new fill that should fade.** Colour keying is
   driven by membership of that dict, not by path name, so stems, midribs and
   spores are left alone without anything listing them.
5. Optionally a `SWAY` entry to hand-tune amplitude and phase. Without one a
   part falls back to `SWAY_DEFAULT[kind]` and a deterministic phase spread.

What is deliberately *not* needed: touching the emitter, the converters, the
state machine, or the blend wiring. `stage_rml` takes a stage number and builds
the rest.

### Still open

- **The roots.** A second canvas (ground line at y=0, so it stacks under a
  plant canvas), four levels, and the one place bones are clearly worth it —
  `roots()` already emits one group per primary root for exactly that.
- **Growth transitions.** Five separate artboards cannot animate *between*
  stages. If a plant should be seen growing, that is a different structure —
  one artboard with a `Solo`, or a nested-artboard swap — and worth deciding
  before anything depends on the current shape.
- **The Flutter side.** Nothing sets `vitality` at runtime yet. The note about
  `DataConverterInterpolator` under [Converters](#converters-and-the-one-the-app-will-need)
  is already handled — the chains smooth by default — but the host still has to
  pick an artboard per stage and write the property by name.

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


### Step 4 — the vitality droop

A `vitality` number (0–1) on a `Fern` view model drives a
`BlendState1DViewModel` between two poses, on a **second state machine layer**.

```
Sway layer      AnimationState → Sway            keys rotation on *-sway nodes
Vitality layer  BlendState1DViewModel            keys rotation on *-droop nodes
                  ├ BlendAnimation1D value=0   → Drooped
                  └ BlendAnimation1D value=100 → Upright
```

The two layers write `rotation` on **different objects**, which is what makes
two layers safe here. Had both targeted the same node the later layer would
simply win — the reason for the nested droop/sway pair from step 2.

**Droop angles are derived from the art, not hand-tuned**, so they carry to the
other stages unchanged: a frond gives up `DROOP_MAX_DEGREES` (25°) scaled by how
upright it already is, in the direction it already leans. A near-horizontal
frond has little height to lose; the near-vertical centre one falls furthest.
The sign is `sign(dx)` of the tip, which is what turns the rotation into
"outward and down" rather than "toward the middle".

| Frond | Droop at vitality 0 | Tip falls |
|---|---|---|
| `frond-back-left` | −20.6° | 253 px |
| `frond-back-right` | +20.6° | 253 px |
| `frond-left` | −11.8° | 115 px |
| `frond-right` | +11.8° | 115 px |
| `frond-center` | +24.2° | 314 px |

The axis is remapped 0–1 → 0–100 by a `DataConverterRangeMapper`
(`clampLower`/`clampUpper` set), carrying a `CubicEaseInterpolator` at the
standard ease-in-out (0.42, 0, 0.58, 1). The easing lives on the value feeding
the blend rather than on the poses, which makes both ends sticky: the fern holds
upright through the top of the range and fully slumped through the bottom, with
the visible change in the middle.

Both poses key **all five** fronds — `Upright` at 0, `Drooped` at its angle — so
nothing jumps for want of something to mix toward.

Verified:

- `problems: []`. 3 `LinearAnimation`, 2 `StateMachineLayer`, 1
  `BlendState1DViewModel` with 2 `BlendAnimation1D` in ascending value order,
  `DataConverterRangeMapper` + `CubicEaseInterpolator` and the `ViewModel` as
  root elements.
- `--data=vitality=` at 1.0 / 0.5 / 0.0 renders three distinct images, so the
  bind genuinely drives the blend.
- At vitality 1.0 the render is **byte-identical** to the step-3 capture at the
  same frame, which is the check that the droop contributes exactly zero when
  the plant is healthy.
- Two frames at a fixed vitality of 0.2 differ, so the sway still runs
  underneath the droop — the layers compose rather than one clobbering the
  other.
- Removing the `CubicEaseInterpolator` child changes the render, so the easing
  is live. **Flipping `interpolationType` does not** — see the trap table; the
  first attempt at this check was measuring nothing.

#### Open calibration questions — since resolved

All four were settled in step 5. Kept here because the reasoning is the record:

- **`DROOP_MAX_DEGREES = 25`** — reviewed and **kept**. The way the fronds fall
  away from the centre reads as drooping at this magnitude.
- **The ease curve** — **replaced**. See step 5; it is now asymmetric, and the
  product question it encodes has been answered in favour of early feedback.
- **The centre frond's lean** — **kept, and made explicit**. See step 5.
- **Sway amplitude not falling with vitality** — **implemented**. See step 5.

---

### Step 5 — colour, curve, smoothing, and a sway that listens

Six changes from review. Every one verified rather than assumed; the mechanisms
that turned out to need a new kind of test are written up under
[Verification recipes](#verification-recipes).

**Leaflet fill fades with vitality.** `KeyFrameColor` on the leaflets'
`SolidColor` (propertyKey 37), keyed in **both** poses like every other blended
property. `#6FA35A → #98A585` front, `#4E7F43 → #71806A` back — desaturated
toward grey-green rather than brown, so the fern reads as thirsty, not dead. The
emitter now records each fill's `SolidColor` id into a `paints` registry as it
walks, so the animation can key a colour without hunting the tree.

**The droop direction is now declared, not inferred.** Above
`NEAR_VERTICAL_DEGREES = 80` the tip's x-offset is too small to mean anything —
`frond-center` leans right by 36 px out of 743, so `sign(dx)` would have flipped
on a trivial edit to the art. `DROOP_DIRECTION` declares it (`+1`, right, as
drawn) and the generator **raises** for any near-vertical frond that is not in
the table. Falling back to `sign(dx)` would have been exactly the silent flip
the declaration exists to prevent. Angles are unchanged: ±20.6°, ±11.8°, +24.2°.

**The ease curve is asymmetric.** `(0.4, 0, 1, 1)` instead of the symmetric
ease-in-out: steep at the top of the range, flattening toward 0.

| vitality | blend | droop |
|---|---|---|
| 1.0 | 100.0 | 0% |
| 0.95 | 92.0 | 8% |
| 0.9 | 84.4 | 15.6% |
| 0.5 | 32.5 | 67.5% |
| 0.25 | 9.9 | 90.1% |

Vitality 0.9 now differs from 1.0 across **9.13% of the canvas** — clearly
visible, where the old symmetric curve gave about 4% droop and read as nothing.

**A changed vitality animates instead of snapping.** Each bind's `converterId`
now points at a `DataConverterGroup`: a `DataConverterInterpolator`
(`duration="0.6"`, ease-out) first, then the range mapper. Smoothing the raw
0–1 value means the shaping curve applies all the way through a transition, and
keeps the range mapper as the one place the 0–1 → 0–100 shaping lives.

Worth knowing: **the interpolator does not ramp at startup.** It begins at its
target, so a scene opened at vitality 0 is already drooped on frame 1 rather
than falling over as you watch.

**The sway scales with vitality, with a floor.** The Sway layer is now a
`BlendState1DViewModel` between a static `Still` pose (value 0) and `Sway`
(value 100), on its own converter chain mapping vitality 0 → **40**, 1 → 100. A
wilted fern moves less but never freezes. `Still` keys the same five rotations
`Sway` does, for the same reason the droop poses key each other's properties.

The floor is load-bearing: rebuilt with `SWAY_FLOOR = 0`, vitality 0 froze the
plant **completely** — 0 pixels changed across 80 frames. At 40 it is 109,252.

**Sway amplitude and phase are parameters.** `SWAY_AMPLITUDE` scales every
frond. `SWAY_MODE` picks how the fronds relate in time:

- `independent` (default) — each frond carries its own phase. Five plants in
  still air.
- `wind` — one oscillation crossing the plant left to right, each frond lagging
  by its tip's x-position. One plant in moving air. Phases come out ordered by
  tip x (0.000, 0.058, 0.120, 0.162, 0.220 turns), and the second harmonic is
  carried at a fixed offset so the correlation does not flatten it.

Switchable without editing the file:

```bash
python3 fern_generator.py --sway=wind
python3 fern_generator.py --amplitude=1.4
```

Loop seams stay exact in both modes — measured at 1e-17 or better.

**Housekeeping.** The state machine is named `Fern` rather than
`State Machine 1`. `.gitignore` covers `build/`, `__pycache__/` and `.DS_Store`.

#### Built state

```
FernMature   1024x1024
  LinearAnimation 4      Sway, Still, Upright, Drooped
  StateMachineLayer 2    Sway (blend), Vitality (blend)
  BlendState1DViewModel 2 / BlendAnimation1D 4 / DataBindContext 2
  KeyedObject 30         5 sway + 5 still + 2 x (5 rotation + 5 colour)
  KeyFrameDouble 140 / KeyFrameColor 10
roots
  DataConverterGroup 2 + DataConverterGroupItem 4
  DataConverterInterpolator 2 + DataConverterRangeMapper 2 + CubicEaseInterpolator 4
  ViewModel 1 (Fern.vitality)
```

Two chains rather than one shared: the droop and the sway need different output
ranges, and the interpolator is stateful, so each gets its own instance rather
than being shared between two binds.

#### Performance baseline

`rive fern --bench=600`, 1024×1024, this machine:

```
advance  mean 0.020ms   p50 0.019ms   p95 0.024ms   max 0.030ms
render   mean 0.100ms   p50 0.103ms   p95 0.128ms   max 2.862ms
memory   0 -> 0 wasm pages (+0) over 600 frames
```

Built `.riv` is 32 KB. At a 16.7 ms frame budget the whole scene costs well
under 1%, and the `max 2.862ms` render is the first frame warming up, not a
recurring spike. No memory growth over 600 frames. Recorded so the next change
has something to regress against — the number to watch is `advance`, since that
is what the 1,500-object tree and two blend states cost.


### Step 6 — the other four stages

`mature_rml()` became `stage_rml(n, name)`, and the fern is now five artboards
in one `.riv`.

**What made it generic.** The droop and the sway used to read `FRONDS`, a table
that only described the mature layout. They now read two attributes the parts
carry themselves — `tip` and `kind` — set by `open_frond` and `fiddlehead` at
construction. Nothing downstream knows which stage it is looking at, which is
why stages 1–3 needed no new emitter code at all despite containing fiddleheads,
scaled fronds and a frond that is in no table.

Three things generalised along with it:

- **`droop_angle`** takes a part and a stage number. `DROOP_KIND_SCALE` gives a
  fiddlehead 0.6 of a frond's droop — a young shoot is springier than a laden
  frond. `DROOP_DIRECTION` is keyed `(stage, part)` because the same part name
  recurs across stages with different geometry; `fiddlehead-1` is near-vertical
  in stage 1 and not in stages 2 or 3.
- **Colour keying** is driven by `DRY_FILL` membership rather than by path name.
  That picked up the fiddlehead coils (`#5E9150 → #8B9A7E`) without naming them,
  and correctly left the bloom's ochre spores alone.
- **Sway phases** fall back to a deterministic spread for parts with no
  hand-tuned entry, so the five tuned mature values survive untouched while
  stages 1–3 still get parts that do not move in lockstep.

**Layout.** One file per stage plus `fern-data.rml` for the shared `Fern` view
model — one `vitality`, whichever stage is on screen. Each file gets its own id
client (0 for data, 1–5 for stages), which is what lets six files share one id
namespace without coordinating. Artboards are spaced along the editor stage by
their width plus a gutter; `rive.yaml` names `FernMature` as the default rather
than letting file order decide.

| Artboard | Objects | Parts | Paths | Fades |
|---|---|---|---|---|
| `FernSprout` | 303 | 1 fiddlehead | 2 | 1 |
| `FernSeedling` | 864 | 2 fiddleheads + 1 frond | 36 | 4 |
| `FernYoung` | 1188 | 3 fronds + 1 fiddlehead | 105 | 4 |
| `FernMature` | 1751 | 5 fronds | 250 | 5 |
| `FernBloom` | 1978 | 5 fronds + spores | 250 | 5 |

Verified:

- `problems: []` across all six files. Every artboard has 4 animations, 2 layers
  and 2 binds — the same wiring, built by the same code.
- **`FernMature` renders byte-identical to before the refactor**, which is the
  check that generalising changed nothing about the stage that was already
  right. Droop angles are unchanged too: ±20.6°, ±11.8°, +24.2°.
- Every stage sways (frame 1 vs 40 at vitality 1) and droops (vitality 1 vs 0),
  measured with `pngdiff.py`: 0.42%–12.14% of canvas for sway, 0.84%–21.54% for
  droop, scaling with how much of the canvas the plant occupies.
- Loop seams stay exact for the derived phases — worst case 2.08e-17 across all
  stages and both modes.

#### Performance baseline

One `.riv` holding all five artboards is **109 KB**. `rive fern --bench=600`:

| Artboard | advance mean | render mean | memory |
|---|---|---|---|
| `FernSprout` | 0.001 ms | 0.092 ms | +0 pages |
| `FernMature` | 0.022 ms | 0.088 ms | +0 pages |
| `FernBloom` | 0.041 ms | 0.079 ms | +0 pages |

`advance` scales with the object count, as expected — it is what the tree and
the two blend states cost. `render` is flat and dominated by canvas size rather
than complexity. The worst case is 0.12 ms of a 16.7 ms frame. Earlier
single-artboard numbers are superseded by these.


### Step 7 — the seed, the roots, and the lean

**Stage 0, the seed.** `stage_parts` returns `(parts, back, front)`: the seed is
the only stage with a layer *behind* the plant as well as in front, and the
front lip of soil is what hides its bottom edge. RML declares them in reverse of
SVG — front first, back last.

Three things the new stage forced:

- the data file moved to id client **9**; `stage_rml` uses `Ids(client=n)` and
  stage 0 had taken client 0;
- the artboard row offset was `(n - 1)`, which put the seed a column left of the
  sprout and off the stage;
- `droop_angle` raised for any near-vertical part with no declared direction,
  *including parts that cannot droop at all*. A zero-magnitude droop has no
  direction to get wrong, so it returns early now.

**The seed ignores vitality**, because the engine has no vitality before the
first completion. `DROOP_KIND_SCALE["seed"] = 0` and no `DRY_FILL` entry were
not enough — sway *amplitude* is vitality-bound too, and the seed still moved
125 px between vitality 1 and 0. Stage 0 gets a sway range mapper whose floor
equals its ceiling, which is a constant rather than a differently-shaped state
machine. Measured 0 px across vitality, 301 px across frames.

**The roots are a node tree, not a set of drawings.** Every root and branch is
its own `Group` placed at its attachment point in its *parent's* local space,
holding geometry that starts at its own origin. Nothing in the tree knows about
levels: growing the system is a **scale** on these nodes, which is what lets one
tree serve all four levels and animate between them. Scale composes down the
hierarchy, so scaling a primary carries its branches and their attachment points
— at level 2 the branches of primaries 4 and 5 carry scale 1 and still vanish,
because their parent is 0.

`Group` gained an optional `origin` and `scale`, honoured by both writers: SVG
emits a `transform`, RML the Node's own `x`/`y`/`scaleX`/`scaleY`. Keeping it in
the shared model rather than in the emitter is what stops the two outputs
describing different plants. Verified: accumulating the nested transforms
reproduces the old flat polylines to **0.000000 px over 3021 vertices**.

`FernRoots` blends five poses at axis positions 0, 15, 30, 50 and 75 — bare
soil, then `ROOT_LEVELS` 1–4. Uneven on purpose: bare soil to a first root
should read as a bigger event than one established level to the next. Every one
of the 53 root nodes is keyed in every pose, on both `scaleX` and `scaleY` —
530 keyed objects — because a node keyed in one pose and absent from another
pops instead of growing. A `DataConverterInterpolator` at 1.2s means roots
visibly grow after a reflection rather than appearing.

One thing the render caught that the numbers did not: **a root must be painted
over its own branches.** Emitted the other way round, each branch's stroked end
cut a visible notch across the root it grows from. The shape is appended after
its children so both writers paint it last.

**The stability lean.** A plant taller than its roots tips over. `FernYoung` and
`FernMature` get a third layer, `Stability`, blending `Leaning` (5°) against
`Steady` through a per-stage range mapper — `roots` at the stage's threshold
(0.30 / 0.50) reads as steady, `roots` at 0 as a full lean. The mapper is
linear, because the threshold is already the shaping. Direction is **declared**
in `LEAN_DIRECTION`, since there is nothing in the art to read it off. Seed,
sprout, seedling and bloom do not lean — the first three have nothing to tip,
and the bloom is the reward pose and should not look precarious.

This forced a structural change: the `plant` node moved from (0,0) to the base
point (512, 882) so it rotates about the plant's base rather than the artboard's
corner, **and the soil moved out of it**. The mound and the front lip are now
siblings of `plant` rather than children. Rotating them with it tilted the
ground line, which reads as the whole world leaning rather than the plant.

Verified: `problems: []` across eight files. `FernYoung` and `FernMature` carry
3 layers / 6 animations / 3 binds; the other four stages 2 / 4 / 2; `FernRoots`
1 / 5 / 1. Roots at 0, 0.15, 0.3, 0.5 and 0.75 are five distinct renders.
`FernMature` at roots 0 vs 0.5 differs across 168,645 px. And `FernMature` at
vitality 1 renders **byte-identical** to before both the plant-node move and the
seed stage — the check that all this restructuring changed nothing that was
already right.

#### Performance baseline

One `.riv`, seven artboards, **171 KB**. `rive fern --bench=600`:

| Artboard | advance mean | render mean | memory |
|---|---|---|---|
| `FernSeed` | 0.001 ms | 0.092 ms | +0 pages |
| `FernMature` | 0.021 ms | 0.076 ms | +0 pages |
| `FernRoots` | 0.002 ms | 0.090 ms | +0 pages |

`FernRoots` holds 5004 objects and still advances in 0.002 ms, because a blend
state resting on a static pose has nothing to recompute per frame. The cost of
the root system is in the file, not in the frame.
