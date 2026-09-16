"""Taproot fern generator — produces layered, animation-ready SVGs and RML.

Plant canvases: 1024x1024, ground line at y=GROUND, stems emerge from (512, GROUND-18).
Root canvases:  1024x1024, ground line at y=0, roots hang from (512, 0).
Stack a plant canvas directly on top of a root canvas and the ground lines meet.

This file is the fern: its palette, its parts, its six stages, its root tree
and the tables that tune its motion. Everything generic -- the geometry model,
the SVG writer, the RML emitter and the animation wiring -- lives in
../plantgen, shared with every other plant.

See NOTES.md for the RML capabilities this relies on and the traps it avoids.
"""
import math, random, os, sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from plantgen.geometry import (GROUND, BASE, Contour, Dot, Path, Dots, Group,
                               quad_to_cubic, sample_cubic, cumlen, at_frac, tapered)
from plantgen.ground import ROOT_OUTLINE, base_mound, seed_bed
from plantgen.roots import Root
from plantgen.species import Species, main

# ---------- palette ----------
OUTLINE = "#2F4A2C"; LEAF = "#6FA35A"; LEAF_BACK = "#4E7F43"; STEM = "#3E6B3A"
MIDRIB = "#4E7F43"; MIDRIB_BACK = "#3E6B3A"
OCHRE = "#D9A441"
# the thirsty end of the droop blend -- desaturated toward grey-green, not brown.
# the plant should read as needing water, not as dead.
LEAF_DRY = "#98A585"; LEAF_BACK_DRY = "#71806A"
COIL = "#5E9150"; COIL_DRY = "#8B9A7E"

# Every fill that fades as vitality drops, healthy -> thirsty. A fill not in
# here is keyed by nobody and stays put: stems, midribs, soil, spores.
DRY_FILL = {LEAF: LEAF_DRY, LEAF_BACK: LEAF_BACK_DRY, COIL: COIL_DRY}

def leaflet(x, y, ang, L, Wd, bend):
    """curved, pointed leaflet from (x,y); bend>0 curves it toward +normal"""
    ca, sa = math.cos(ang), math.sin(ang)
    P = lambda u, v: (x + u*ca - v*sa, y + u*sa + v*ca)
    b = bend * L
    tip = P(L, b)
    up1, up2 = P(0.22*L, Wd*1.05 + 0.05*b), P(0.72*L, Wd*0.80 + 0.55*b)
    lo2, lo1 = P(0.72*L, -Wd*0.55 + 0.55*b), P(0.22*L, -Wd*0.95 + 0.05*b)
    root = (x, y)
    # two cubic segments: root -> tip along the upper edge, tip -> root along the lower
    shape = Contour([(root, lo1, up1), (tip, up2, lo2)], closed=True)
    m0, m1, m2 = P(0.12*L, 0.01*b), P(0.45*L, 0.25*b), P(0.70*L, 0.50*b)
    c1, c2 = quad_to_cubic(m0, m1, m2)
    midrib = Contour([(m0, None, c1), (m2, c2, None)], closed=False)
    return shape, midrib, P, b

def spiral_pts(start, ta, r0, turns, side, n=60, decay=0.5):
    """crozier coil continuing from `start` with tangent angle ta"""
    k = -math.log(decay) / (2 * math.pi)
    cang = ta + side * math.pi / 2
    c = (start[0] + r0*math.cos(cang), start[1] + r0*math.sin(cang))
    phi0 = cang + math.pi
    pts = []
    for i in range(1, n + 1):
        th = turns * 2 * math.pi * i / n
        r = r0 * math.exp(-k * th)
        a = phi0 + side * th
        pts.append((c[0] + r*math.cos(a), c[1] + r*math.sin(a)))
    return pts

# ---------- plant parts ----------
def open_frond(fid, ctrl1, ctrl2, tip, back=False, pairs=13, max_len=96, seed=0,
               stem_w=11, sori=False, scale=1.0):
    rnd = random.Random(seed)
    fill = LEAF_BACK if back else LEAF
    rib = MIDRIB_BACK if back else MIDRIB
    p0 = BASE
    sc = lambda p: (BASE[0] + (p[0]-BASE[0])*scale, BASE[1] + (p[1]-BASE[1])*scale)
    c1, c2, tp = sc(ctrl1), sc(ctrl2), sc(tip)
    pts = sample_cubic(p0, c1, c2, tp, 64); lens = cumlen(pts)
    leaves, ribs, dots = [], [], []
    for k in range(pairs):
        s = 0.30 + 0.66 * k / (pairs - 1)
        (x, y), a = at_frac(pts, lens, s)
        taper = 1 - 0.80 * (k / (pairs - 1)) ** 1.15
        for side in (-1, 1):
            L = max_len * scale * taper * rnd.uniform(0.92, 1.06)
            ang = a + side * math.radians(rnd.uniform(46, 56))
            shape, midrib, P, b = leaflet(x, y, ang, L, L * 0.25, -side * 0.22)
            leaves.append(shape)
            if L > 26: ribs.append(midrib)
            if sori and L > 30:
                for u, v in ((0.38, 0.40), (0.60, -0.28)):
                    cx, cy = P(u * L, v * L * 0.24 + (0.2 if u < 0.5 else 0.45) * b)
                    dots.append(Dot(cx, cy, 4))
    # terminal leaflet + slight curl
    (x, y), a = at_frac(pts, lens, 0.985)
    tshape, _, _, _ = leaflet(x, y, a, 20 * scale, 4.5 * scale, 0.25)
    leaves.append(tshape)
    stem = tapered(pts, stem_w * scale, 2.6 * scale)
    parts = [
        Path(f"{fid}-stem", [stem], fill=STEM, stroke=OUTLINE, stroke_width=2.4),
        Path(f"{fid}-leaflets", leaves, fill=fill, stroke=OUTLINE, stroke_width=2.6),
        Path(f"{fid}-midribs", ribs, stroke=rib, stroke_width=1.8, cap="round"),
    ]
    if dots:
        parts.append(Dots(f"{fid}-spores", dots, OCHRE))
    return Group(fid, parts, tip=tp, kind="frond")

def fiddlehead(fid, ctrl1, ctrl2, top, coil=34, turns=1.7, side=1, stem_w=10,
               buds=0, seed=0, back=False):
    """a young frond, still curled. buds = small leaflet pairs below the coil"""
    rnd = random.Random(seed)
    pts = sample_cubic(BASE, ctrl1, ctrl2, top, 40)
    ta = math.atan2(pts[-1][1] - pts[-2][1], pts[-1][0] - pts[-2][0])
    coil_pts = spiral_pts(top, ta, coil, turns, side)
    allp = pts + coil_pts
    stem = tapered(allp, stem_w, 3.2)
    fill = LEAF_BACK if back else LEAF
    leaves = []
    if buds:
        lens = cumlen(pts)
        for k in range(buds):
            s = 0.55 + 0.40 * k / max(buds - 1, 1)
            (x, y), a = at_frac(pts, lens, s)
            L = (30 - 12 * k / max(buds - 1, 1)) * rnd.uniform(0.9, 1.05)
            for sd in (-1, 1):
                shape, _, _, _ = leaflet(x, y, a + sd * math.radians(48), L, L * 0.26, -sd * 0.2)
                leaves.append(shape)
    parts = []
    if leaves:
        parts.append(Path(f"{fid}-leaflets", leaves, fill=fill, stroke=OUTLINE, stroke_width=2.4))
    parts.append(Path(f"{fid}-coil", [stem], fill=(fill if back else COIL),
                      stroke=OUTLINE, stroke_width=2.4))
    return Group(fid, parts, tip=top, kind="fiddlehead")

# ---------- stage 0: the seed ----------
SEED = "#B8895A"; SEED_SHADE = "#9A6E45"; SEED_LIGHT = "#D9B386"
SEED_CENTRE = (512, GROUND - 40)   # rests in the mound; the soil lip hides the bottom edge
SEED_SIZE = (74, 56)               # length, width
SEED_TILT = -28                    # degrees; the pointed end lifts to the right
K = 0.5523                         # cubic handle length for a circular quarter

def _seed_frame():
    (cx, cy), a = SEED_CENTRE, math.radians(SEED_TILT)
    ca, sa = math.cos(a), math.sin(a)
    return lambda u, v: (cx + u*ca - v*sa, cy + u*sa + v*ca)

def seed_body():
    """A plump egg with a soft point, a flat shadow along its underside, and a shine."""
    P = _seed_frame(); L, Wd = SEED_SIZE; hl, hw = L / 2, Wd / 2
    tail, top, tip, bot = P(-hl, 0), P(-hl*0.1, -hw), P(hl, 0), P(-hl*0.1, hw)
    body = Contour([
        (tail, P(-hl, hw*K),          P(-hl, -hw*K)),
        (top,  P(-hl*0.1 - hl*0.9*K, -hw), P(hl*0.62, -hw)),
        (tip,  P(hl*1.0, -hw*0.36),  P(hl*1.0, hw*0.36)),
        (bot,  P(hl*0.62, hw),        P(-hl*0.1 - hl*0.9*K, hw)),
    ], closed=True)
    # shadow: the lower edge of the body, closed by a shallower inner curve
    s_tail, s_tip, s_mid = P(-hl*0.93, hw*0.32), P(hl*0.90, hw*0.18), P(-hl*0.05, hw*0.40)
    shade = Contour([
        (s_tail, P(-hl*0.62, hw*0.44), P(-hl*0.72, hw*0.86)),
        (P(-hl*0.1, hw*0.99), P(-hl*0.45, hw*1.0), P(hl*0.42, hw*0.99)),
        (s_tip, P(hl*0.78, hw*0.52), P(hl*0.55, hw*0.30)),
        (s_mid, P(hl*0.40, hw*0.44), P(-hl*0.45, hw*0.38)),
    ], closed=True)
    shine = Dot(*P(-hl*0.38, -hw*0.42), L*0.11, Wd*0.085)
    return Group("seed", [
        Path("seed-body", [body], fill=SEED),
        Path("seed-shade", [shade], fill=SEED_SHADE),
        Path("seed-outline", [body], stroke=ROOT_OUTLINE, stroke_width=2.6),
        Dots("seed-shine", [shine], SEED_LIGHT),
    ], tip=P(hl, 0), kind="seed")

def seed_stage():
    """SVG order: mound (back), seed, soil lip (front)."""
    back, front = seed_bed()
    return [back, Group("plant", [seed_body()]), front]

# ---------- the mature layout (shared by Young / Mature / Bloom) ----------
FRONDS = {  # id: (ctrl1, ctrl2, tip, back, pairs, max_len, seed)
    "frond-back-left":  ((500, 700), (380, 470), (318, 205), True, 13, 88, 11),
    "frond-back-right": ((524, 700), (644, 470), (706, 205), True, 13, 88, 12),
    "frond-left":       ((470, 760), (250, 560), (100, 505), False, 12, 92, 13),
    "frond-right":      ((554, 760), (774, 560), (924, 505), False, 12, 92, 14),
    "frond-center":     ((505, 640), (520, 380), (548, 140), False, 14, 98, 15),
}
MATURE_ORDER = ("frond-back-left", "frond-back-right", "frond-left", "frond-right", "frond-center")

def frond_by_id(fid, scale=1.0, sori=False, pairs_override=None):
    c1, c2, tp, back, pairs, ml, seed = FRONDS[fid]
    pairs = pairs_override or pairs
    return open_frond(fid, c1, c2, tp, back, pairs, ml, seed, sori=sori, scale=scale)

STAGE_MOUND = {1: 70, 2: 90, 3: 105, 4: 125, 5: 125}

def stage_parts(n):
    """(animatable parts, back, front) for one stage.

    The parts are the things that sway and droop. `back` and `front` are the
    static soil layers either side of them: stages 1-5 have only a mound in
    front of the stems, and the seed has a mound behind it *and* a lip of soil
    in front, which is what hides the bottom edge of the seed.
    """
    if n == 0:    # Seed: three layers, and the only stage with a back element
        back, plant, front = seed_stage()
        return plant.children, back, front
    parts = []
    if n == 1:    # Sprout: one tight fiddlehead
        parts.append(fiddlehead("fiddlehead-1", (515, 800), (490, 730), (498, 680), coil=38, turns=1.75, side=1, stem_w=13))
    elif n == 2:  # Seedling: small open frond + two fiddleheads
        parts.append(fiddlehead("fiddlehead-1", (500, 820), (470, 720), (448, 640), coil=32, turns=1.7, side=-1, stem_w=10, buds=2, seed=3))
        parts.append(open_frond("frond-1", (515, 790), (560, 700), (600, 590), False, 8, 58, 21, stem_w=8))
        parts.append(fiddlehead("fiddlehead-2", (505, 845), (490, 815), (478, 792), coil=20, turns=1.8, side=-1, stem_w=8))
    elif n == 3:  # Young: three medium fronds + one fiddlehead
        parts.append(frond_by_id("frond-left", scale=0.66, pairs_override=9))
        parts.append(frond_by_id("frond-right", scale=0.66, pairs_override=9))
        parts.append(frond_by_id("frond-center", scale=0.70, pairs_override=10))
        parts.append(fiddlehead("fiddlehead-1", (505, 830), (478, 760), (462, 715), coil=24, turns=1.7, side=-1, stem_w=9))
    else:         # Mature (4) / Bloom (5)
        for fid in MATURE_ORDER:
            parts.append(frond_by_id(fid, sori=(n == 5)))
    return parts, None, base_mound(STAGE_MOUND[n])

# ---------- roots ----------
def build_root_tree(seed=7):
    rnd = random.Random(seed)
    prim = []
    for i, deg in enumerate((100, 62, 124, 38, 146)):
        ln = rnd.uniform(430, 520) if i == 0 else rnd.uniform(300, 400) * (0.85 if i > 2 else 1)
        r = Root(f"root-{i+1}", 0, math.radians(deg + rnd.uniform(-5, 5)), ln, 13 if i < 3 else 10, 1, seed*10+i)
        for j in range(rnd.randint(3, 4)):
            fr = 0.22 + 0.2*j + rnd.uniform(-0.04, 0.04)
            sd = 1 if j % 2 == 0 else -1
            c = Root(f"{r.rid}-{j+1}", fr, r.ang + sd*math.radians(rnd.uniform(35, 55)),
                     ln * rnd.uniform(0.32, 0.45) * (1 - fr*0.4), 6.5, 2, seed*100+i*10+j)
            for m in range(2):
                fr2 = 0.35 + 0.3*m
                sd2 = -sd if m == 0 else sd
                c.children.append(Root(f"{c.rid}-{m+1}", fr2, c.ang + sd2*math.radians(rnd.uniform(30, 50)),
                                       c.length * rnd.uniform(0.35, 0.5), 3.4, 3, seed*1000+i*100+j*10+m))
            r.children.append(c)
        prim.append(r)
    return prim

ROOT_LEVELS = {  # level: (length scale, max generation, number of primaries)
    1: (0.30, 1, 3),
    2: (0.52, 2, 3),
    3: (0.76, 2, 5),
    4: (1.00, 3, 5),
}

# ---------- motion ----------
# Hand-tuned amplitudes and phases for the mature layout. Any part not listed
# -- a fiddlehead, a stage-2 frond -- falls back to SWAY_DEFAULT and a spread of
# phases derived from its position in the stage.
SWAY = {  # part: (degrees, phase in turns, second-harmonic phase in turns)
    "frond-back-left":  (1.7, 0.00, 0.31),
    "frond-back-right": (1.5, 0.37, 0.74),
    "frond-left":       (2.6, 0.62, 0.12),
    "frond-right":      (2.4, 0.18, 0.55),
    "frond-center":     (1.9, 0.81, 0.93),
}
# A seed does not sway like a frond -- it rocks, gently, in its bed.
SWAY_DEFAULT = {"frond": 2.2, "fiddlehead": 1.3, "seed": 1.2}   # degrees, by kind

# A fiddlehead is a young shoot, not a laden frond -- it gives less.
# A seed is 0: the engine has no vitality before the first completion.
DROOP_KIND_SCALE = {"frond": 1.0, "fiddlehead": 0.6, "seed": 0.0}

# Which way a near-vertical part falls. Above 80 degrees the tip's x-offset is
# too small to mean anything -- frond-center leans right by 36px out of 743, so
# sign(dx) would flip on a trivial edit to the art. +1 is right, -1 is left.
# Keyed by (stage, part) because the same part name recurs across stages with
# different geometry.
DROOP_DIRECTION = {
    (1, "fiddlehead-1"): -1,   # the sprout's single shoot, leaning left as drawn
    (3, "frond-center"): +1,   # the same art as stage 4, scaled
    (4, "frond-center"): +1,   # falls to the right; matches the art as drawn
    (5, "frond-center"): +1,
}

# A plant taller than its roots leans. Only the two stages tall enough for the
# lean to read carry it -- the seed and sprout have nothing to tip, and the
# bloom is the reward pose and should not look precarious.
LEAN_THRESHOLD = {3: 0.30, 4: 0.50}   # roots at or above this = steady
LEAN_DIRECTION = {3: +1, 4: +1}       # declared: nothing in the art says which way

FERN = Species(
    "Fern", stage_parts, build_root_tree, ROOT_LEVELS, DRY_FILL,
    sway=SWAY, sway_default=SWAY_DEFAULT, droop_kind_scale=DROOP_KIND_SCALE,
    droop_direction=DROOP_DIRECTION, lean_threshold=LEAN_THRESHOLD,
    lean_direction=LEAN_DIRECTION, still_stages=(0,))

if __name__ == "__main__":
    # python3 fern_generator.py [--sway=wind|independent] [--amplitude=1.4]
    main(FERN, "fern", sys.argv[1:], __file__)
