"""Taproot lavender generator — layered, animation-ready SVGs and RML.

The fourth plant on ../plantgen, after the fern, the oak and the sunflower. See
../fern/NOTES.md for the conventions and traps, ../oak/NOTES.md and
../sunflower/NOTES.md for what those two added, and NOTES.md here for the
lavender.

What the lavender is for, visually: a low, silvery mound with a spray of thin
flower wands above it. It is the garden's short plant, and the first whose
bloom is a colour other than the ochre and yellow of the others. Structurally
it goes back to the fern's shape -- every part grows out of the ground and
pivots at the base -- so it needs nothing new from plantgen.
"""
import math, random, os, sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from plantgen.geometry import (BASE, GROUND, Contour, Dot, Path, Dots, Group,
                               sample_cubic, cumlen, at_frac, tapered)
from plantgen.ground import ROOT_OUTLINE, base_mound, seed_bed
from plantgen.roots import Root
from plantgen.species import Species, main

# ---------- palette ----------
# Lavender foliage is silvery sage, well away from the other plants' greens, so
# even a lavender with no flowers reads as a different plant. The flowers are
# the accent: grey-lilac while in bud, purple once open.
OUTLINE = "#2F4A2C"
FOLIAGE = "#8FAA86"; FOLIAGE_BACK = "#6F8C6A"
COTYLEDON = "#9DBB83"
WAND = "#7B9470"                       # the bare flower stems
BUD = "#948BAE"; BUD_DARK = "#736A8F"
FLORET = "#8B67BA"; FLORET_DARK = "#644396"; FLORET_LIGHT = "#B79FDC"
FLORET_OUTLINE = "#3D2E57"

# the thirsty end: the silver goes toward straw, the purple toward a faded
# grey-lilac. Lavender is a dry-climate plant, so its thirst is pallor more
# than wilt -- but the wands still flop, which is what reads at garden scale.
FOLIAGE_DRY = "#B5B596"; FOLIAGE_BACK_DRY = "#92967A"; COTYLEDON_DRY = "#BABEA0"
WAND_DRY = "#9EA38A"
BUD_DRY = "#AAA4B5"; BUD_DARK_DRY = "#8C879B"
FLORET_DRY = "#A597BD"; FLORET_DARK_DRY = "#827399"; FLORET_LIGHT_DRY = "#C9BFD8"

DRY_FILL = {FOLIAGE: FOLIAGE_DRY, FOLIAGE_BACK: FOLIAGE_BACK_DRY, COTYLEDON: COTYLEDON_DRY,
            WAND: WAND_DRY, BUD: BUD_DRY, BUD_DARK: BUD_DARK_DRY,
            FLORET: FLORET_DRY, FLORET_DARK: FLORET_DARK_DRY, FLORET_LIGHT: FLORET_LIGHT_DRY}

# the seed: small, dark and glossy
SEED = "#4A3526"; SEED_SHADE = "#35251A"; SEED_LIGHT = "#8A6A52"

LEAF_STROKE = 2.4
K = 0.5523   # cubic handle length for a circular quarter

def frame(x, y, ang):
    ca, sa = math.cos(ang), math.sin(ang)
    return lambda u, v: (x + u*ca - v*sa, y + u*sa + v*ca)

def curve(p0, c1, c2, p3, n=16):
    return sample_cubic(p0, c1, c2, p3, n)

# ---------- the leaf ----------
def narrow_leaf(x, y, ang, L, W):
    """A lavender leaf: long, narrow, blunt-pointed. Four cubic nodes."""
    P = frame(x, y, ang)
    return Contour([
        (P(0, 0), P(0, 0.4*W), P(0, -0.4*W)),
        (P(0.42*L, -W), P(0.15*L, -W), P(0.72*L, -W)),
        (P(L, 0), P(0.97*L, -0.45*W), P(0.97*L, 0.45*W)),
        (P(0.42*L, W), P(0.72*L, W), P(0.15*L, W)),
    ], closed=True)

def round_leaf(x, y, ang, L, W):
    """A seed leaf: short and round-ended."""
    P = frame(x, y, ang)
    return Contour([
        (P(0, 0), P(0.02*L, 0.40*W), P(0.02*L, -0.40*W)),
        (P(0.50*L, -W), P(0.20*L, -W), P(0.82*L, -W)),
        (P(L, 0), P(L, -0.60*W), P(L, 0.60*W)),
        (P(0.50*L, W), P(0.82*L, W), P(0.20*L, W)),
    ], closed=True)

# ---------- a leafy shoot ----------
def shoot(gid, c1, c2, tip, pairs, leaf_len, back=False, width=7, seed=0):
    """One leafy stem of the mound: opposite pairs of narrow leaves climbing a
    thin stem, getting smaller toward the tip, with a small tuft on the end.

    Stem and leaves are one path in one colour. They are the same silver-green
    on the plant, and one shape per shoot keeps a mound of a dozen shoots cheap.
    """
    rnd = random.Random(seed)
    pts = curve(BASE, c1, c2, tip, 20)
    lens = cumlen(pts)
    contours = [tapered(pts, width, 2.5)]
    for k in range(pairs):
        s = 0.22 + 0.72 * k / max(pairs - 1, 1)
        (x, y), a = at_frac(pts, lens, s)
        L = leaf_len * (1 - 0.45 * k / max(pairs, 1)) * rnd.uniform(0.9, 1.08)
        for side in (-1, 1):
            spread = math.radians(rnd.uniform(34, 48))
            contours.append(narrow_leaf(x, y, a + side * spread, L, L * 0.12))
    (x, y), a = at_frac(pts, lens, 1.0)
    for d in (-0.35, 0.0, 0.35):
        contours.append(narrow_leaf(x, y, a + d, leaf_len * 0.40, leaf_len * 0.06))
    fill = FOLIAGE_BACK if back else FOLIAGE
    return Group(gid, [Path(f"{gid}-leaves", contours, fill=fill, stroke=OUTLINE,
                            stroke_width=LEAF_STROKE)],
                 tip=tip, kind="shoot",
                 meta={"droop_direction": 1 if tip[0] >= BASE[0] else -1})

# ---------- a flower wand ----------
def wand(gid, c1, c2, tip, spike_len, open_=True, whorls=11, seed=0):
    """A bare stem with a spike of flowers at the top.

    The spike is whorls of small florets, spaced wider toward the bottom -- the
    gaps between the lower whorls are what make a spike read as lavender and not
    as a purple bottle brush. Florets are ellipses, so a whole spike is a few
    shapes: an outline layer (the florets a little larger, in a dark purple),
    the side florets (darker) and the front ones over them, and a few light
    highlights once open.
    `open_` False is the mature stage: the same spike, still in grey-lilac bud.
    """
    rnd = random.Random(seed)
    pts = curve(BASE, c1, c2, tip, 20)
    lens = cumlen(pts)
    total = lens[-1]
    stem = Path(f"{gid}-stem", [tapered(pts, 6.5, 3.2)], fill=WAND, stroke=OUTLINE,
                stroke_width=LEAF_STROKE)
    start = 1 - spike_len / total
    rings, sides, fronts, lights = [], [], [], []
    for k in range(whorls):
        f = k / (whorls - 1)                     # 0 at the bottom whorl, 1 at the tip
        s = start + (1 - start) * (1 - (1 - f) ** 1.8)
        (x, y), a = at_frac(pts, lens, min(s, 0.995))
        nx, ny = -math.sin(a), math.cos(a)
        size = 1.0 - 0.50 * f
        rx, ry = 5.6 * size, 7.6 * size
        spread = 6.0 * size + 1.0
        whorl = [Dot(x + nx * spread * side + rnd.uniform(-1, 1), y + ny * spread * side, rx, ry)
                 for side in (-1, 1)]
        front = Dot(x + rnd.uniform(-1.2, 1.2), y, rx * 1.05, ry * 1.05)
        sides += whorl
        fronts.append(front)
        # the outline: the same florets a little larger, in the outline colour,
        # behind everything -- overlapping florets then share one outline
        rings += [Dot(d.cx, d.cy, d.rx + 2.0, d.ry + 2.0) for d in whorl + [front]]
        if open_ and k % 2 == 0 and k < whorls - 2:
            lights.append(Dot(x - 1.5, y - ry * 0.35, rx * 0.45, ry * 0.35))
    dark, mid = (FLORET_DARK, FLORET) if open_ else (BUD_DARK, BUD)
    parts = [stem, Dots(f"{gid}-florets-line", rings, FLORET_OUTLINE),
             Dots(f"{gid}-florets-side", sides, dark), Dots(f"{gid}-florets", fronts, mid)]
    if lights:
        parts.append(Dots(f"{gid}-florets-light", lights, FLORET_LIGHT))
    return Group(gid, parts, tip=tip, kind="wand",
                 meta={"droop_direction": 1 if tip[0] >= BASE[0] else -1})

# ---------- stage 0: the seed ----------
SEED_CENTRE = (512, GROUND - 34)

def seed_stage():
    """A small, dark, glossy oval in the shared seed bed."""
    back, front = seed_bed()
    P = frame(*SEED_CENTRE, math.radians(-18))
    hl, hw = 30, 19
    body = Contour([
        (P(-hl, 0), P(-hl, hw*K), P(-hl, -hw*K)),
        (P(0, -hw), P(-hl*K, -hw), P(hl*K, -hw)),
        (P(hl, 0), P(hl, -hw*K), P(hl, hw*K)),
        (P(0, hw), P(hl*K, hw), P(-hl*K, hw)),
    ], closed=True)
    shade = Contour([
        (P(-hl*0.85, hw*0.35), P(-hl*0.6, hw*0.9), P(-hl*0.3, hw*0.42)),
        (P(hl*0.85, hw*0.35), P(hl*0.3, hw*0.42), P(hl*0.6, hw*0.9)),
    ], closed=True)
    seed = Group("seed", [
        Path("seed-body", [body], fill=SEED),
        Path("seed-shade", [shade], fill=SEED_SHADE),
        Dots("seed-shine", [Dot(*P(-hl*0.30, -hw*0.42), 7, 4.5)], SEED_LIGHT),
        Path("seed-outline", [body], stroke=ROOT_OUTLINE, stroke_width=2.6),
    ], tip=P(hl, 0), kind="seed")
    return back, seed, front

# ---------- stage 1: the sprout ----------
def sprout():
    """A short stem with two round seed leaves and the first true leaves
    showing between them."""
    pts = curve(BASE, (514, 850), (506, 790), (510, 752))
    top = pts[-1]
    contours = [tapered(pts, 9, 5)]
    stem = Path("sprout-stem", contours, fill=WAND, stroke=OUTLINE, stroke_width=LEAF_STROKE)
    cotys = []
    for side, deg in (("left", -165), ("right", -15)):
        a = math.radians(deg)
        cotys.append(Group(f"cotyledon-{side}", [
            Path(f"cotyledon-{side}-leaf", [round_leaf(*top, a, 44, 17)],
                 fill=COTYLEDON, stroke=OUTLINE, stroke_width=LEAF_STROKE),
        ], tip=(top[0] + 44 * math.cos(a), top[1] + 44 * math.sin(a)), kind="leaf", pivot=top))
    first = Group("first-leaves", [
        Path("first-leaves-leaves", [narrow_leaf(*top, math.radians(-112), 40, 5),
                                     narrow_leaf(*top, math.radians(-68), 40, 5)],
             fill=FOLIAGE, stroke=OUTLINE, stroke_width=LEAF_STROKE),
    ], tip=(top[0], top[1] - 38), kind="leaf", pivot=top, meta={"droop_direction": -1})
    return [Group("sprout", [stem] + cotys + [first], tip=top, kind="shoot",
                  meta={"droop_direction": 1})]

# ---------- stage 2: the seedling ----------
def seedling():
    """One upright leafy shoot and a smaller one leaning out beside it."""
    return [
        shoot("shoot-side", (500, 840), (470, 790), (446, 730), 3, 50, back=True, width=6, seed=2),
        shoot("shoot-main", (514, 820), (508, 720), (516, 640), 5, 64, width=8, seed=1),
    ]

# ---------- stages 3-5: the bush ----------
# A cushion of leafy shoots fanned out from the base, and above it (mature and
# bloom) a spray of wands. Both are laid out on a fan rather than placed one by
# one: a shoot's tip sits on a half-ellipse around the base, so the mound is
# dome-shaped whatever the count.

def fan(n, rx, ry, lo=12, hi=168, jitter=6, seed=0):
    """`n` tip positions on a half-ellipse around the base, from `hi` degrees
    (left) to `lo` (right), and the angle each sits at."""
    rnd = random.Random(seed)
    out = []
    for i in range(n):
        deg = hi - (hi - lo) * i / (n - 1) + rnd.uniform(-jitter, jitter)
        a = math.radians(deg)
        r = rnd.uniform(0.90, 1.06)
        out.append(((BASE[0] + rx * r * math.cos(a), BASE[1] - ry * r * math.sin(a)), deg))
    return out

def mound(n, rx, ry, pairs, leaf_len, seed):
    """A cushion of shoots. Every other shoot is a darker back shoot, drawn
    first, so the dome has depth; the outermost ones are front shoots."""
    backs, fronts = [], []
    for i, (tip, deg) in enumerate(fan(n, rx, ry, seed=seed)):
        # each shoot leaves the base steeply and bends out: a cushion, not a star
        c1 = (BASE[0] + (tip[0] - BASE[0]) * 0.15, BASE[1] - (BASE[1] - tip[1]) * 0.45 - 20)
        c2 = (BASE[0] + (tip[0] - BASE[0]) * 0.65, tip[1] - 10)
        back = i % 2 == 1 and 1 < i < n - 2
        part = shoot(f"shoot-{i+1}", c1, c2, tip, pairs, leaf_len, back=back,
                     width=8, seed=seed * 10 + i)
        (backs if back else fronts).append(part)
    return backs, fronts

def spray(n, rx, ry, spike, open_, seed):
    """A fan of wands. Each states its own droop: the shared rule (the more
    upright, the further it falls) would drop the centre wands most and open a
    gap down the middle of the spray, as it did on the oak's crown. A thirsty
    lavender does the opposite -- the spray splays, outer wands flopping most,
    the centre ones barely leaning -- so the droop grows with how far out a
    wand already leans."""
    wands = []
    for i, (tip, deg) in enumerate(fan(n, rx, ry, lo=38, hi=142, jitter=3, seed=seed)):
        c1 = (BASE[0] + (tip[0] - BASE[0]) * 0.05, BASE[1] - 140)
        c2 = (BASE[0] + (tip[0] - BASE[0]) * 0.55, BASE[1] - (BASE[1] - tip[1]) * 0.60)
        part = wand(f"wand-{i+1}", c1, c2, tip, spike, open_=open_, seed=seed * 10 + i)
        lean = (90 - deg) / 52                    # -1 at the leftmost wand, +1 at the rightmost
        part.meta["droop_degrees"] = WAND_DROOP_MIN * (1 if lean >= 0 else -1) + WAND_DROOP_SPLAY * lean
        wands.append(part)
    return wands

def bush(n):
    """Young (3), mature (4) or bloom (5)."""
    if n == 3:
        backs, fronts = mound(9, 170, 190, 5, 60, seed=3)
        return backs + fronts
    backs, fronts = mound(13, 230, 270, 6, 70, seed=4)
    # the wands rise from inside the mound: behind the front shoots, in front
    # of the back ones, so their bare lower stems disappear into the foliage
    return backs + spray(9, 330, 560, 130, open_=(n == 5), seed=5) + fronts

STAGE_MOUND = {1: 64, 2: 80, 3: 110, 4: 130, 5: 130}

def stage_parts(n):
    """(animated parts, back, front) for one stage."""
    if n == 0:
        back, seed, front = seed_stage()
        return [seed], back, front
    if n == 1:
        parts = sprout()
    elif n == 2:
        parts = seedling()
    else:
        parts = bush(n)
    return parts, None, base_mound(STAGE_MOUND[n])

# ---------- roots ----------
def build_root_tree(seed=41):
    """Lavender roots: no single taproot, but a woody fan of main roots that
    spreads wider than it goes deep, each branching into finer ones.

    The fern's roots are a loose tangle, the oak's and the sunflower's are
    taproots. This is the fourth shape: a broad, even fan.
    """
    rnd = random.Random(seed)
    prim = []
    # centre-out, so the first primaries at the low levels are the deep ones
    for i, deg in enumerate((96, 72, 118, 50, 140, 30, 158)):
        ln = rnd.uniform(300, 360) * (1.0 if i < 3 else 0.82 if i < 5 else 0.66)
        r = Root(f"root-{i+1}", 0, math.radians(deg + rnd.uniform(-4, 4)), ln,
                 12 if i < 3 else 10, 1, seed * 10 + i, wander=0.08, gravity=0.04)
        for j in range(3):
            fr = 0.28 + 0.24 * j + rnd.uniform(-0.04, 0.04)
            sd = 1 if j % 2 == 0 else -1
            c = Root(f"{r.rid}-{j+1}", fr, r.ang + sd * math.radians(rnd.uniform(28, 45)),
                     ln * rnd.uniform(0.28, 0.38) * (1 - fr * 0.4), 5.5, 2,
                     seed * 100 + i * 10 + j, wander=0.12)
            c.children.append(Root(f"{c.rid}-1", 0.5, c.ang - sd * math.radians(32),
                                   c.length * 0.5, 3.0, 3, seed * 1000 + i * 10 + j))
            r.children.append(c)
        prim.append(r)
    return prim

ROOT_LEVELS = {  # level: (length scale, max generation, number of primaries)
    1: (0.32, 1, 3),
    2: (0.55, 2, 5),
    3: (0.78, 2, 7),
    4: (1.00, 3, 7),
}

# ---------- motion ----------
SWAY = {}
# The wands are the lavender's motion: long, thin and top-heavy, they bob more
# than anything else in the garden. The mound barely moves.
SWAY_DEFAULT = {"seed": 1.2, "shoot": 0.9, "leaf": 2.0, "wand": 2.8}
# Wands fall outward like the fern's fronds; the mound slumps a little.
DROOP_KIND_SCALE = {"seed": 0.0, "shoot": 0.45, "leaf": 1.2, "wand": 1.1}
DROOP_DIRECTION = {}          # every near-vertical part declares its side on itself
# wands state their droop outright (see spray): a small lean for the centre
# wands, growing to MIN + SPLAY for the outermost
WAND_DROOP_MIN = 6.0
WAND_DROOP_SPLAY = 24.0
LEAN_THRESHOLD = {3: 0.30, 4: 0.50}
LEAN_DIRECTION = {3: -1, 4: -1}

LAVENDER = Species(
    "Lavender", stage_parts, build_root_tree, ROOT_LEVELS, DRY_FILL,
    sway=SWAY, sway_default=SWAY_DEFAULT, droop_kind_scale=DROOP_KIND_SCALE,
    droop_direction=DROOP_DIRECTION, lean_threshold=LEAN_THRESHOLD,
    lean_direction=LEAN_DIRECTION, still_stages=(0,))

if __name__ == "__main__":
    # python3 lavender_generator.py [--sway=wind|independent] [--amplitude=1.4]
    main(LAVENDER, "lavender", sys.argv[1:], __file__)
