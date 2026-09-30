# Handoff: Evening Check-in Sheet

Target repo: **LWitteman96/taproot** (Flutter + Riverpod). Governing specs: `docs/reflection-logic.md` (§1–§4, §6), `docs/starter-chip-library.md` (§5 surfacing rule, §7.1 exercise example A), `docs/growth-engine.md` (§5 roots). Companion to `design_handoff_garden_home/` — same tokens, fonts and garden backdrop; this package only adds what the sheet needs.

## Overview
The check-in is a **bottom sheet over the live garden**, opened from **Reflect** on the garden's detail card (or the evening prompt). Two steps — *look back* (one question, chips) → *commit to tomorrow* (one question) — then a *done* state where the reflected habit's **roots visibly grow behind the sheet**. That payoff is the point: reflection is the only thing that deepens roots, and the user should see it happen. Never more than two taps on the happy path; never more than one insight.

## About the design files
`Check-in Sheet.dc.html` is an **interactive HTML reference**, not code to port. Open it in a browser (needs `support.js` + `ios-frame.jsx` alongside). The **framing** tweak switches between the five spec framings; every visual value is inline in the file.

## Fidelity
Hi-fi for layout, color, type, motion and copy. The garden behind the sheet is the same placeholder-plant treatment as the garden handoff (oak silhouette = placeholder art).

## Anatomy
Canvas 402 × 874; the garden underneath is the dusk Garden Home with the reflected habit (oak at x=201) and its roots centered. Layers, back to front:
1. **Garden backdrop** — Garden Home layers 1–9 (see the garden README). Only the reflected plant and its roots need to render; other plants may stay but aren't required.
2. **Roots of the reflected habit** — origin (201, 470). Taproot 4px wide, height `20 + R × 260` px (deeper scale than the garden view — the sheet gives roots the stage). Laterals: ceil(N/2) ≤ 6, 2.5px, alternating sides, angle 32°+5i / 148°−5i, length `22 + (1−frac) × 34`. Height/top/width animate **900ms cubic-bezier(.2,.8,.2,1)** when N changes on *done*.
3. **Root glow** (done step, credit > 0) — 140px-wide radial ellipse of selectionGlow 40% centered on the taproot, height = taproot + 20; opacity 0→1→0 over 1800ms.
4. **Plant** — oak placeholder; leans −3° while R < ρ(young)=.30, springs to 0° (900ms, cubic-bezier(.34,1.5,.64,1)) if the reflection crosses the threshold.
5. **Scrim** — full-screen vertical gradient black-brown (oklch .10 .02 50) 35% → 55%.
6. **Sheet** — pinned to bottom, radius 28 top corners, padding 10 / 20 / 44, card color at **96%** + 20px blur, 1px top border white 10%, shadow 0 −20px 60px black 40%. Enters with translateY 40px → 0 + fade, **520ms cubic-bezier(.2,.8,.2,1)**. Column gap 18. Contents:
   - Grabber 36×4, white 18%, centered.
   - Meta row (mono 11px, .04em tracking, monoLabel 65%): `EVENING CHECK-IN` left; `{habit} · {1 of 2 | 2 of 2 | done}` right.
   - Step content (below). Each step's blocks fade-up in a 60ms stagger (360ms ease).

## Step 1 — Look back
- **Fact line** 15px Karla, ink 70%. **Question** Newsreader 27px/1.15, −0.01em, `text-wrap: pretty`.
- **Chips** wrap row, gap 8. Pill, min-height 44, padding 11×16, 15px/500. States:
  - default: white 6% bg, 1px white 12% border, ink text
  - **pinned** (the designed cue / guaranteed chip): accent 14% bg, accent 45% border, 6px accent dot before the label
  - **selected**: accent bg, onAccent text — held 420ms, then auto-advance to step 2
  - press: scale .96, 120ms
- **Footer row** 14px, ink 60%: `Something else` (→ typing) · `Can't remember` (¼ credit) · `Skip` right-aligned at ink 40% (0 credit). Hidden while a yes/no framing is un-expanded. `Can't remember` is hidden in diagnosis and behind a flag (spec §9 open question about reflection #1).

### Framings (exact copy)
| Framing | Fact | Question | Chips | Credit |
|---|---|---|---|---|
| validation | You trained this morning. | Did after breakfast kick it off? | **Yes** (pinned) · No, something else → expands to *What got you going, then?* + non-designed cue chips | 1.0 |
| confirmation | You trained this morning. | Same as usual — after breakfast? | **Yes** (pinned) · Actually, no → expands to *What was it this time?* | 0.5 (yes) / 1.0 (expanded pick) |
| discovery | You trained this morning. | What got you going? | full cue set | 1.0 |
| autonomy | You trained this morning — without us asking. | What reminded you? | full cue set | **1.5** |
| diagnosis | No training yesterday. | What got in the way? | friction set | 1.0 |

Cue chip set (exercise, logged 07:10, designed cue `after breakfast`): **after breakfast** (pinned) · after coffee · put my shoes on · first thing up · walked past the gym.
Friction chip set: just forgot · ran out of time · too tired · something came up · didn't feel like it (spec: *forgot* and *motivation* always present).
Typed answers get the framing's chip credit. Can't remember = 0.25. Skip = 0.

### Typing sub-step
Question `What got you going?` / `What got in the way?` (diagnosis). Single-line input 52px, radius 16, white 6% bg, white 18% border, 16px Karla; placeholder `e.g. the dog woke me up` / `e.g. dentist ran over`. Buttons: **Back** (outlined, flex 1) · **Save** (flex 1.3, accent; disabled look white 7% / ink 40% until text). Autofocus; keyboard pushes the sheet up.

## Step 2 — Commit to tomorrow
Fact `Thursday next, then.` (`Tomorrow, then.` in diagnosis). Question `After breakfast?` (`After breakfast — still the plan?` in diagnosis). Chips: **Yes** (pinned) · Different day → `Which day?` with the next four scheduled days. Any pick → done.

## Done
- Title Newsreader 30px: `Roots deepened.` Sub 15px ink 75%: `{+1.5 | +1 | +½ | +¼} credit · {N} reflections · roots {still shallow | taking hold | deep} · {day} is set`. R < .30 / < .60 / ≥ .60.
- Can't remember → title `Noted.`, sub `An honest blank counts a little · +¼ credit · …`. Skip → `Another time.` / `Tomorrow is set. We'll ask again when there's something to learn.` (no glow, no root growth).
- **Insight card** (at most one; radius 18, white 5% bg, white 9% border, Newsreader italic 17px inkHint; fades in 220ms after title):
  - autonomy → `You trained without us asking. That's the whole idea.`
  - non-designed cue picked → `Second time it's been "{chip}". A few more and we'll suggest making it official.`
  - diagnosis, by friction chip → text + action button (accent 18% bg / accent 35% border / 14px 600) + `Not now`:
    - just forgot → *Sounds like the cue didn't fire. Want to try anchoring to something that always happens?* → **Look at the cue**
    - ran out of time → *Might be too big for the slot it's in. Want to shrink the routine?* → **Shrink it**
    - too tired → *Energy runs out before the habit does. Want to try it earlier?* → **Move it earlier**
    - something came up → *Other things keep winning that slot. Want a more protected one?* → **Pick a slot**
    - didn't feel like it → *The routine happened, the reward didn't. Want to revisit what follows it?* → **Revisit the reward**
  - Diagnosis title becomes `Thanks — that helps.`
- Primary button **Back to the garden** — 48px, radius 14, accent, full width. Dismisses sheet; the garden's detail card should now show the new N / roots word.

## State & data (Flutter mapping)
- Inputs (from engine selectors): `habit` (name, species, stage), `designedCue`, `framing` (Framing enum — chosen by `reflection-logic` §2 from history, **not** by the sheet), `chipSet` (from the starter library surfacing rule: time-of-log + cue family), `N`, `R`, `nextScheduledDays`, feature flag `allowCantRemember`.
- Sheet-local state: `step` (reflect | typing | commit | done), `mode` (chip | expanded | typed | cant | skip | days), `picked`, `typed`, `credit`, `day`.
- Outputs on done: `ReflectionEntry { habitId, framing, answer (chip id | freeText | none), credit, committedDay }` → engine recomputes N and R; the sheet animates from old R to new R (don't re-fetch — pass both).
- Root credit table must live in `constants.dart`; the sheet never hard-codes 1.5 / 1.0 / 0.5 / 0.25.
- Writes are local-first; the done step never waits on sync.

## Accessibility
Chips are toggle buttons with labels; pinned chips announce `suggested`. Auto-advance after a chip pick must be cancelable by reduced-motion → show a `Next` button instead. Root growth and glow are decorative; the done sub-line carries the same information as text.

## Tokens
Same palette and fonts as `design_handoff_garden_home/tokens.json` (copied here as `tokens.json`). Additional literals used only here: sheet bg = card @ 96%; scrim oklch(0.10 0.02 50) 35→55%; chip default white 6% / border white 12%; chip pinned accent 14% / border accent 45%; input white 6% / border white 18%; insight card white 5% / border white 9%.

## Out of scope / open
- Where the sheet is triggered from besides Reflect (evening notification deep-link) and the prompt-time rule.
- Whether reflection #1 gets `Can't remember` (§9) — flagged.
- Intervention flows behind the insight action buttons (cue/slot/shrink/reward editors).

## Files
- `Check-in Sheet.dc.html` — the prototype (open in a browser with `support.js` and `ios-frame.jsx` alongside).
- `tokens.json` — shared color table.
