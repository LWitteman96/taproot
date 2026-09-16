# Handoff: Garden Home (soil + plants)

Target repo: **LWitteman96/taproot** (Flutter + Riverpod, spec-first). Governing specs: `docs/design-spec.md`, `docs/growth-engine.md`, `docs/reflection-logic.md`. This package designs the **garden home screen** — the one surface the design spec says the app opens to.

## Overview
The garden is a single vertical cross-section: sky above, a grass line, and **soil below with roots visible**. Each habit is one plant. Above ground shows stage + vitality (how big, how healthy); below ground shows roots (how well the cue→routine loop is understood). The user taps a plant to select it, and a floating detail card exposes the two actions: **Water** (completion) and **Reflect** (check-in). The soil is permanently visible in this MVP — the "tall plant on shallow roots" message the growth engine relies on (§3, advisory ρ gates) only lands if roots are always in view.

## About the design files
`Garden Home.dc.html` (+ `support.js`, `ios-frame.jsx`) is a **design reference built in HTML** — an interactive prototype of intended look and behavior, not code to port. Recreate it in Flutter using the repo's target structure (`lib/features/garden/`, `lib/widgets/` for garden rendering, engine values from `lib/core/engine/`). Open the HTML in a browser to see the live behavior; every visual value is inline in the file.

## Fidelity
**Hi-fi for layout, color, type, motion and copy. Lo-fi for plant art.** Plants are deliberately drawn as dashed placeholder silhouettes labelled with species + stage — real plant art arrives as SVG (`flutter_svg` is already a dependency). Everything else (sky, soil, roots, card, watering moment, typography) is final direction and should be matched.

## Screen: Garden Home
Canvas 402 × 874 (iPhone 16 Pro logical px); all coordinates below are in that frame. Layout must scale with the viewport — treat the **ground line at y=466 (53% of height)** as the anchor and lay sky above / soil below.

### Layers, back to front
1. **Sky** — 0→470px. Vertical gradient by time of day (see tokens). 1.2s ease crossfade when the mode changes.
2. **Sun / moon** — 46–60px circle with wide soft glow; position depends on mode (dusk: x296 y386 low right, dawn: x52 y392 low left, day: x318 y88, night moon: x312 y112 34px).
3. **Horizon haze** — 140px gradient from transparent into the mode's haze color, ending at the ground line.
4. **Grass line** — 7px band at y=466, gradient grassTop→grassBottom, 3px top radius.
5. **Soil** — y=472→bottom. Four-stop vertical gradient soil0 → soil1 (35%) → soil2 (75%) → soil3. Overlay at 50% opacity: repeating faint strata (1px light line every ~41px, 1px dark line offset) — subtle, angled 2°. Seven pebbles: small ellipses 5–9px wide, pebble color at 55–90% alpha.
6. **Damp patches** — under each *watered* plant: 96×46 radial ellipse of damp color, anchored at the ground line, fading to transparent at 75%. Opacity 0→1 over 900ms, delayed 480ms after the water tap (so it follows the drop landing).
7. **Roots** — per plant, origin at (plant.x, 470). Taproot: 3px wide, height = 12 + R×150 px, gradient root 90% → rootFade 35%. Laterals: ceil(N/2) capped at 6, 2px thick, alternating sides, angle 32°+5i (right) / 148°−5i (left), length 14 + (1−frac)×22 (+8 when N>8). Height/width animate 800ms cubic-bezier(.2,.8,.2,1) when R changes.
8. **Selection glow** — 120×28 radial ellipse of selectionGlow at 45% alpha under the selected plant at the ground line; slides between plants over 500ms.
9. **Plants** — bottom-anchored at (plant.x, 468). Placeholder silhouette: dashed 1px border, faint diagonal hatch fill; sizes: lotus 88×150, oak 66×200, fern 56×64, sprout 22×26. Healthy: plantHealthy 50% fill / plantHealthyStroke 55% border. Thirsty: plantThirsty 32% / plantThirstyStroke 45%. Selected: 2px ring of selectionGlow at 35%. Label (mono 9.5px, monoLabel 75%): species + stage, two lines, omitted on sprout.
   - **Droop**: rotate about the base by −round((1−V)×14)° (V = vitality). Shallow-rooted plants (R below the stage's advisory ρ) add a permanent −3° lean. Recovery on watering: 900ms cubic-bezier(.34,1.5,.64,1), delayed 450ms — the overshoot is the "perk up".
   - **Ambient sway**: ±1.2° rotate loop, period 5s + height/60 s, phase offset per plant. Runs behind a global ticker; must be disableable (reduced motion, tests).
10. **Watering moment** (only while `watering != null`, 1.5s total): a 12×16 teardrop (water0→water1, 30/30/70/70 radius) falls from 110px above the ground line to the base over 650ms cubic-bezier(.5,0,.8,.4), flattening to 1.6×0.25 as it lands; then a 70×18 ripple ellipse (1.5px stroke, water0 80%) scales 0.15→1 and fades over 700ms starting at 560ms. Soil darkens (layer 6) and the plant springs upright (layer 9). Add haptic on landing (design spec §6: "water, soil darkens, haptic, done").
11. **Header** — top-left at (24, 66): greeting in Newsreader 32px/1.1, −0.01em; status line 15px Karla at 78% ink. Text shadow 0 1px 12px black 25%.
12. **Toast** — centered at y=600, pill 8×14 padding, toast color 90% + 1px white 10% border, 13px. Appears on Reflect: `Roots deepened · N reflections`. 2.4s life, fade in 12%, hold, fade out.
13. **Detail card** — inset 16px, bottom 50px, 18px padding, radius 24, card color 82% with 18px backdrop blur, 1px white 9% border, shadow 0 20px 50px black 35%. Contents:
    - Row: habit name (Newsreader 24px) · mono 11px `{species} · {stage}` right-aligned.
    - Two lines 14px at 80% ink: `Cue worked {hit} of {total} times` · `{N} reflections · {shallow roots | roots taking hold | deep roots}` (R < .30 / < .60 / ≥ .60).
    - Optional hint, Newsreader italic 15px inkHint 90% (rules below).
    - Buttons row, gap 10: **Water** flex 1.3, 46px tall, radius 14, accent bg / onAccent text 600. After watering: label `Watered today`, bg white 7%, text ink 55%, disabled. **Reflect** flex 1, outlined 1px white 18%, 500 weight.

### Copy (exact)
- Greeting by mode: `Good morning.` / `Good afternoon.` / `Good evening.` / `Good night.`
- Status: 0 thirsty → `Everything’s watered. Just visiting?`; 1 → `One plant could use a drink.`; n → `{Two|Three|Four} plants could use a drink.`
- Hints (first match wins): shallow → `Growing fast on shallow roots — a reflection or two would anchor it.`; thirsty sprout/seedling → `Looking a little thirsty. Seedlings perk right up.`; mature → `Locked in. A missed day won’t shake this one.`; else none.
- Stage words: seed, sprout, seedling, young, mature, `in bloom`.

## Interactions
- Tap plant → select (card + glow move). Tap the selected plant again → water (same as the button).
- Water: no-op if V already 1.0 or a watering animation is running. Sets V=1.0 immediately (§4: snaps, always), runs the 1.5s moment. Per CLAUDE.md the tap must never fail or spin — write locally, queue sync.
- Reflect: in the MVP it increments weighted N by 1 and toasts. In the app it opens the evening check-in sheet (reflection-logic §1) — **not designed yet**; leave a route stub.
- The card never blocks the garden; garden taps outside plants do nothing (no deselect) so there is always a selected habit.

## State & data (Flutter mapping)
Per plant the screen reads only derived values — take them from the engine via selector providers (CLAUDE.md: one plant's completion must not rebuild the garden):
- `stage` (Stage enum), `vitality` V ∈ [0,1], `roots` R ∈ [0,1], `weightedReflectionCount` N, `designedCueHits/Total`, `species`, `name`.
- Shallow flag = `R < advisoryRootThreshold[stage]` (young .30, mature .50, bloom .75 — from `constants.dart`, never inlined).
- Screen-local state: `selectedHabitId`, `wateringHabitId?` (1.5s), `toast?`.
- Plant x positions in the prototype are fixed (64, 160, 252, 336); real layout should distribute plants across the width with min 84px spacing and horizontal scroll past 4.
- Time-of-day: derive from local hour (dawn <9, day <17, dusk <20, night) — the prototype exposes it as a tweak.

## Accessibility
Every plant has a semantic label: `{name}, {stage}, vitality {V%}, roots {R%}[, shallow for its size]`. Ambient sway and the watering overshoot go behind `GardenTicker` / reduced-motion; the state change itself (droop angle, damp patch) must still apply instantly without motion.

## Design tokens
Fonts: **Newsreader** (display, 400; italic for hints) and **Karla** (UI, 400/500/600); mono labels use the platform mono. Both are Google Fonts — add via `google_fonts` or bundle.
Radii: card 24, buttons 14, toast pill. Spacing: 16 inset, 18 card padding, 10 button gap, 12 card row gap.
Colors — oklch is canonical, hex is an sRGB conversion (also in `tokens.json`):

| Token | Hex | oklch | Use |
|---|---|---|---|
| bgApp | #1B110C | oklch(0.19 0.02 50) | app background / soil base |
| soil0 | #463021 | oklch(0.33 0.04 55) | soil gradient top |
| soil1 | #322219 | oklch(0.27 0.03 52) | soil 35% |
| soil2 | #201610 | oklch(0.21 0.02 50) | soil 75% |
| soil3 | #17100C | oklch(0.18 0.015 50) | soil bottom |
| damp | #120905 | oklch(0.15 0.02 50) | damp patch (95%→50% alpha) |
| pebble | #4E3F32 | oklch(0.38 0.03 62) | pebbles |
| grassTop | #4B6035 | oklch(0.46 0.07 130) | grass line top |
| grassBottom | #3F3F1F | oklch(0.36 0.05 110) | grass line bottom |
| ink | #F0EAE0 | oklch(0.94 0.015 80) | primary text |
| inkHint | #E6CDA5 | oklch(0.86 0.06 80) | italic hint text |
| accent | #87BA88 | oklch(0.74 0.09 145) | Water button, links |
| onAccent | #091509 | oklch(0.18 0.03 145) | text on accent |
| selectionGlow | #8FC990 | oklch(0.78 0.10 145) | selection glow, plant ring |
| root | #9F8056 | oklch(0.62 0.07 75) | taproot / lateral start |
| rootFade | #917552 | oklch(0.58 0.06 72) | root tip |
| plantHealthy | #3F6A41 | oklch(0.48 0.08 145) | placeholder fill, V=1 |
| plantHealthyStroke | #A2CAA2 | oklch(0.80 0.07 145) | placeholder border, V=1 |
| plantThirsty | #5B5A3F | oklch(0.46 0.04 105) | placeholder fill, V<1 |
| plantThirstyStroke | #ACA682 | oklch(0.72 0.05 100) | placeholder border, V<1 |
| monoLabel | #D2E4D2 | oklch(0.90 0.03 145) | species/stage mono labels |
| water0 | #B7DEF3 | oklch(0.88 0.05 230) | drop highlight, ripple |
| water1 | #69AED5 | oklch(0.72 0.09 235) | drop body |
| card | #291C14 | oklch(0.24 0.025 55) | detail card (82%) |
| toast | #35251B | oklch(0.28 0.03 55) | toast (90%) |
| dusk0 | #241F3A | oklch(0.26 0.05 290) | dusk sky 0% |
| dusk1 | #683964 | oklch(0.42 0.09 330) | dusk sky 45% |
| dusk2 | #BE6438 | oklch(0.60 0.13 45) | dusk sky 82% |
| dusk3 | #CD8F50 | oklch(0.70 0.11 65) | dusk sky 100% |
| duskSun | #FFC27C | oklch(0.88 0.13 60) | dusk sun |
| duskHaze | #D08D54 | oklch(0.70 0.11 60) | dusk horizon haze (55%) |
| dawn0 | #322E4B | oklch(0.32 0.05 290) | dawn sky 0% |
| dawn1 | #7D5279 | oklch(0.50 0.08 330) | dawn sky 45% |
| dawn2 | #CF8D60 | oklch(0.70 0.10 55) | dawn sky 100% |
| dawnSun | #FFDC98 | oklch(0.92 0.10 75) | dawn sun |
| dawnHaze | #CE976A | oklch(0.72 0.09 60) | dawn haze (55%) |
| day0 | #3D6F8C | oklch(0.52 0.07 235) | day sky 0% |
| day1 | #689BAC | oklch(0.66 0.06 220) | day sky 55% |
| day2 | #BEB994 | oklch(0.78 0.05 100) | day sky 100% |
| daySun | #FFF6D0 | oklch(0.97 0.05 95) | day sun |
| dayHaze | #C5BF9A | oklch(0.80 0.05 100) | day haze (50%) |
| night0 | #090917 | oklch(0.15 0.03 280) | night sky 0% |
| night1 | #191527 | oklch(0.21 0.035 295) | night sky 60% |
| night2 | #2D2230 | oklch(0.27 0.03 320) | night sky 100% |
| nightMoon | #ECE8D9 | oklch(0.93 0.02 95) | moon |
| nightHaze | #352937 | oklch(0.30 0.03 320) | night haze (60%) |

## Assets
None yet. Plant silhouettes are placeholders; species (lotus, oak, fern, sprout) × stage art is the open workstream noted in `pubspec.yaml`.

## Out of scope / open
- Reflection check-in sheet (chips, four framings) — next design.
- "Peek underground" alternative (soil hidden until pull-down) — rejected for MVP; shallow-roots visual must be always-on.
- Renegotiation / pause states, bloom art, graduated habits.

## Files
- `Garden Home.dc.html` — the prototype (open in a browser; requires `support.js` and `ios-frame.jsx` alongside).
- `tokens.json` — the color table above as data.
