#!/usr/bin/env python3
"""Step 5: prove the data actually drives the render.

`check_rml.py` reads the markup and `check_built.py` reads the resolved tree.
Neither can tell you that a bind which resolves *drives* anything — for that the
only evidence is changing the data and seeing the picture change. This renders
the pairs that matter and diffs them.

Run it from `oak/`, after `rive . --once`:

    python3 check_render.py

21 checks. Three kinds of assertion, and the negative ones carry as much weight
as the positive: `differ` (a bind drives something), `identical` (it drives
*exactly nothing* where it should not — a healthy plant adds no droop, roots cap
at 0.75, the bloom never leans), and `zero` (the seed ignores vitality outright).

Both sides of every comparison use the same `--advance`, because the sway is a
300-frame loop and a frame difference reads as a data difference. See the trap
about `--pointer` in ../fern/NOTES.md before adding a check that clicks.
"""

import hashlib, subprocess, sys, os
sys.path.insert(0, '../fern')
import pngdiff

OUT = 'build/ab'
os.makedirs(OUT, exist_ok=True)
results = []

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

STAGES = ['Sprout', 'Seedling', 'Young', 'Mature', 'Bloom']

print('\n-- droop is bound --')
for s in STAGES:
    a = shot(f'{s}-v1', f'Oak{s}', 60, vitality=1)
    b = shot(f'{s}-v0', f'Oak{s}', 60, vitality=0)
    check(f'Oak{s} vitality 1 vs 0', a, b, 'differ')

print('\n-- healthy adds nothing --')
a = shot('mature-h1', 'OakMature', 60, vitality=1)
b = shot('mature-h2', 'OakMature', 60, vitality=1)
check('OakMature vitality 1, two captures', a, b, 'identical')

print('\n-- sway runs --')
for s in ['Seed'] + STAGES:
    a = shot(f'{s}-f1', f'Oak{s}', 1, vitality=1)
    b = shot(f'{s}-f40', f'Oak{s}', 40, vitality=1)
    check(f'Oak{s} frame 1 vs 40', a, b, 'differ')

print('\n-- sway survives thirst --')
a = shot('mature-v0-f1', 'OakMature', 1, vitality=0)
b = shot('mature-v0-f40', 'OakMature', 40, vitality=0)
check('OakMature vitality 0, frame 1 vs 40', a, b, 'differ')

print('\n-- seed ignores vitality --')
a = shot('seed-v1', 'OakSeed', 60, vitality=1)
b = shot('seed-v0', 'OakSeed', 60, vitality=0)
check('OakSeed vitality 1 vs 0', a, b, 'zero')

print('\n-- roots bound --')
paths = {r: shot(f'roots-{r}', 'OakRoots', 120, roots=r)
         for r in ['0', '0.15', '0.3', '0.5', '0.75', '1']}
seen = {}
distinct = True
for r in ['0', '0.15', '0.3', '0.5', '0.75']:
    h = md5(paths[r])
    if h in seen:
        distinct = False
        print(f' FAIL  roots {r} identical to {seen[h]}')
    seen[h] = r
results.append((distinct, 'OakRoots 0/.15/.3/.5/.75 all distinct',
                f'{len(seen)}/5 distinct'))
print(('  ok  ' if distinct else ' FAIL '),
      f'{"OakRoots 0/.15/.3/.5/.75 all distinct":46s} {len(seen)}/5 distinct')
check('OakRoots roots 0.75 vs 1 (cap)', paths['0.75'], paths['1'], 'identical')

print('\n-- the stability lean --')
for artboard, threshold in [('OakMature', '0.5'), ('OakYoung', '0.3')]:
    a = shot(f'{artboard}-r0', artboard, 60, vitality=1, roots=0)
    b = shot(f'{artboard}-rT', artboard, 60, vitality=1, roots=threshold)
    c = shot(f'{artboard}-r1', artboard, 60, vitality=1, roots=1)
    check(f'{artboard} roots 0 vs {threshold} (leans)', a, b, 'differ')
    check(f'{artboard} roots {threshold} vs 1 (stops)', b, c, 'identical')
a = shot('OakBloom-r0', 'OakBloom', 60, vitality=1, roots=0)
b = shot('OakBloom-r1', 'OakBloom', 60, vitality=1, roots=1)
check('OakBloom roots 0 vs 1 (never leans)', a, b, 'identical')

failed = [r for r in results if not r[0]]
print(f'\n{len(results)} checks, {len(failed)} failures')
sys.exit(1 if failed else 0)
