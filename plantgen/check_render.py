#!/usr/bin/env python3
"""Step 5: prove the data actually drives the render.

`check_rml.py` reads the markup and `check_built.py` reads the resolved tree.
Neither can tell you that a bind which resolves *drives* anything — for that the
only evidence is changing the data and seeing the picture change. This renders
the pairs that matter and diffs them.

Generic over the species: run it for a plant project directory, after
`rive . --once` has built it.

    python3 plantgen/check_render.py oak        # from the worktree root
    python3 check_render.py                     # from oak/, via its wrapper

Everything species-specific is read from the species itself — the artboard
prefix from `SPECIES.name`, the leaning stages and their thresholds from
`SPECIES.lean_threshold`, the never-leaning bloom from stage 5, and the stages
that ignore vitality from `SPECIES.still_stages`. Nothing here is retyped, so a
species whose lean threshold differs is checked against *its* threshold rather
than silently against the oak's.

21 checks for a plant that leans at two stages. Three kinds of assertion, and
the negative ones carry as much weight as the positive: `differ` (a bind drives
something), `identical` (it drives *exactly nothing* where it should not — a
healthy plant adds no droop, roots cap at 0.75, the bloom never leans), and
`zero` (a still stage ignores vitality outright).

Both sides of every comparison use the same `--advance`, because the sway is a
300-frame loop and a frame difference reads as a data difference. See the trap
about `--pointer` in ../fern/NOTES.md before adding a check that clicks.
"""

import hashlib, importlib, subprocess, sys, os

HERE = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 else os.getcwd()
NAME = os.path.basename(HERE)
ROOT = os.path.join(HERE, '..')
sys.path.insert(0, HERE)
sys.path.insert(0, ROOT)
# `pngdiff` still lives in fern/, which is where it was written; it is not
# species-specific and every project's checks reach for it.
sys.path.insert(0, os.path.join(ROOT, 'fern'))
import pngdiff

SPECIES = getattr(importlib.import_module(f'{NAME}_generator'), NAME.upper())
from plantgen.species import STAGES

# Rendering is relative to the project directory: `rive .` and the screenshot
# paths below both assume it.
os.chdir(HERE)

PREFIX = SPECIES.name
OUT = 'build/ab'
os.makedirs(OUT, exist_ok=True)
results = []


def artboard(stage):
    """`OakMature` for stage 4 — the same rule plantgen emits, not a list."""
    return f'{PREFIX}{STAGES[stage].capitalize()}'


def number(value):
    """`0.5` not `0.5000000000000001`, so screenshot names stay readable."""
    text = f'{value:g}'
    return text

def shot(name, artboard, frame, **data):
    path = f'{OUT}/{name}.png'
    cmd = ['rive', '.', f'--screenshot={path}', f'--artboard={artboard}',
           f'--advance={frame}']
    for k, v in data.items():
        cmd.append(f'--data={k}={v}')
    log = subprocess.run(cmd, capture_output=True, text=True)
    assert f'showing {artboard}' in log.stderr + log.stdout, \
        f'{artboard} not shown for {name}: {log.stderr[-300:]}'
    return path

def md5(p):
    return hashlib.md5(open(p, 'rb').read()).hexdigest()

def check(label, a, b, expect):
    """expect: 'differ' | 'identical' | 'zero'"""
    same = md5(a) == md5(b)
    if same:
        px, total = 0, None
    else:
        px, total = pngdiff.changed_pixels(a, b)
    if expect == 'differ':
        ok = not same and px > 0
        detail = f'{px} px'
    elif expect == 'identical':
        ok = same
        detail = 'byte-identical' if same else f'DIFFERS by {px} px'
    else:  # zero changed pixels, allowing byte differences
        ok = px == 0
        detail = f'{px} px changed'
    results.append((ok, label, detail))
    print(('  ok  ' if ok else ' FAIL '), f'{label:46s} {detail}')

# Every stage that responds to vitality: all of them but the still ones.
ANIMATED = [n for n in sorted(STAGES) if n not in SPECIES.still_stages]
STILL = sorted(SPECIES.still_stages)
BLOOM = max(STAGES)
MATURE = BLOOM - 1

print('\n-- droop is bound --')
for n in ANIMATED:
    name = artboard(n)
    a = shot(f'{STAGES[n]}-v1', name, 60, vitality=1)
    b = shot(f'{STAGES[n]}-v0', name, 60, vitality=0)
    check(f'{name} vitality 1 vs 0', a, b, 'differ')

print('\n-- healthy adds nothing --')
mature = artboard(MATURE)
a = shot('mature-h1', mature, 60, vitality=1)
b = shot('mature-h2', mature, 60, vitality=1)
check(f'{mature} vitality 1, two captures', a, b, 'identical')

print('\n-- sway runs --')
# Including the still stages: they ignore *vitality*, not the sway. The seed
# still rocks, which is the whole reason this loops over every stage.
for n in sorted(STAGES):
    name = artboard(n)
    a = shot(f'{STAGES[n]}-f1', name, 1, vitality=1)
    b = shot(f'{STAGES[n]}-f40', name, 40, vitality=1)
    check(f'{name} frame 1 vs 40', a, b, 'differ')

print('\n-- sway survives thirst --')
a = shot('mature-v0-f1', mature, 1, vitality=0)
b = shot('mature-v0-f40', mature, 40, vitality=0)
check(f'{mature} vitality 0, frame 1 vs 40', a, b, 'differ')

print('\n-- a still stage ignores vitality --')
for n in STILL:
    name = artboard(n)
    a = shot(f'{STAGES[n]}-v1', name, 60, vitality=1)
    b = shot(f'{STAGES[n]}-v0', name, 60, vitality=0)
    check(f'{name} vitality 1 vs 0', a, b, 'zero')

print('\n-- roots bound --')
roots_artboard = f'{PREFIX}Roots'
paths = {r: shot(f'roots-{r}', roots_artboard, 120, roots=r)
         for r in ['0', '0.15', '0.3', '0.5', '0.75', '1']}
seen = {}
distinct = True
for r in ['0', '0.15', '0.3', '0.5', '0.75']:
    h = md5(paths[r])
    if h in seen:
        distinct = False
        print(f' FAIL  roots {r} identical to {seen[h]}')
    seen[h] = r
label = f'{roots_artboard} 0/.15/.3/.5/.75 all distinct'
results.append((distinct, label, f'{len(seen)}/5 distinct'))
print(('  ok  ' if distinct else ' FAIL '), f'{label:46s} {len(seen)}/5 distinct')
check(f'{roots_artboard} roots 0.75 vs 1 (cap)',
      paths['0.75'], paths['1'], 'identical')

print('\n-- the stability lean --')
# Highest stage first, as the oak's run recorded them.
for n in sorted(SPECIES.lean_threshold, reverse=True):
    name = artboard(n)
    threshold = number(SPECIES.lean_threshold[n])
    a = shot(f'{name}-r0', name, 60, vitality=1, roots=0)
    b = shot(f'{name}-rT', name, 60, vitality=1, roots=threshold)
    c = shot(f'{name}-r1', name, 60, vitality=1, roots=1)
    check(f'{name} roots 0 vs {threshold} (leans)', a, b, 'differ')
    check(f'{name} roots {threshold} vs 1 (stops)', b, c, 'identical')

# The bloom is the payoff stage and deliberately stands straight whatever the
# roots say. It is only a meaningful check while it has no threshold of its own.
bloom = artboard(BLOOM)
assert BLOOM not in SPECIES.lean_threshold, \
    f'{bloom} has a lean threshold; this check assumes it never leans'
a = shot(f'{bloom}-r0', bloom, 60, vitality=1, roots=0)
b = shot(f'{bloom}-r1', bloom, 60, vitality=1, roots=1)
check(f'{bloom} roots 0 vs 1 (never leans)', a, b, 'identical')

failed = [r for r in results if not r[0]]
print(f'\n{len(results)} checks, {len(failed)} failures')
sys.exit(1 if failed else 0)
