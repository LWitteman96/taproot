"""Taproot oak generator — layered, animation-ready SVGs and RML for the oak.

The oak is the second plant built on ../plantgen, after the fern. Same canvas,
same ground, same wiring; what is here is the oak's own art and the tables that
tune its motion. See ../fern/NOTES.md for the conventions and traps, and
NOTES.md next to this file for what the oak adds.

The oak differs from the fern in one structural way: a fern grows every part
out of the ground, so everything pivots at the base. A tree does not. Its limbs
leave the trunk higher up, so each limb pivots where it leaves, and the limbs
are nested inside the trunk so that when the trunk sways they ride along.
"""
import math, random, os, sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from plantgen.geometry import (GROUND, BASE, Contour, Dot, Path, Dots, Group,
                               quad_to_cubic, sample_cubic, cumlen, at_frac, tapered)
from plantgen.ground import ROOT_OUTLINE, base_mound, seed_bed
from plantgen.roots import Root
from plantgen.species import Species, main

# ---------- palette ----------
# The leaf greens sit next to the fern's rather than on them: an oak leaf is a
# touch deeper and warmer, so two species side by side read as two plants in
# one garden, not one plant twice.
OUTLINE = "#2F4A2C"
LEAF = "#669C4F"; LEAF_BACK = "#467A3B"
VEIN = "#4A7A3F"; VEIN_BACK = "#3A6433"
SHOOT = "#557F42"                     # a green stem, before it turns to wood
BARK = "#7A5A3E"; BARK_DARK = "#5E4430"; BARK_OUTLINE = ROOT_OUTLINE
# the thirsty end, mapped the same way the fern's is: toward grey-green
LEAF_DRY = "#9BA684"; LEAF_BACK_DRY = "#737F66"; SHOOT_DRY = "#869079"

# acorns: the seed, the husk the sprout leaves behind, and the bloom's fruit
NUT = "#B8895A"; NUT_SHADE = "#9A6E45"; NUT_LIGHT = "#D9B386"   # the fern seed's browns
CAP = "#7F5B3B"; CAP_DARK = "#5E4430"
FRUIT = "#C9A043"; FRUIT_SHADE = "#A98232"                       # ochre, like the fern's spores

DRY_FILL = {LEAF: LEAF_DRY, LEAF_BACK: LEAF_BACK_DRY, SHOOT: SHOOT_DRY}

LEAF_STROKE = 2.4
# Wood is drawn in two passes: an outline pass (outline colour, thick stroke)
# under a fill pass. Overlapping branches then merge into one silhouette
# instead of each one drawing its outline across the other.
WOOD_STROKE = 4.8


# ---------- the leaf ----------
def oak_leaf(x, y, ang, L, Wd, lobes=4, bend=0.0, petiole=0.10, seed=0):
    """A lobed oak leaf from (x, y) along `ang`.

    Built in a leaf frame (u along the leaf, v across it) as alternating lobe
    tips and sinuses, all cubic. The envelope is obovate -- widest past the
    middle -- and the lobes grow toward the tip, which is what makes the shape
    read as oak at a few points across. Returns (blade, vein, petiole end).
    """
    rnd = random.Random(seed)
    ca, sa = math.cos(ang), math.sin(ang)
    def P(u, v):
        v = v + bend * L * (u / L) ** 2
        return (x + u*ca - v*sa, y + u*sa + v*ca)
    u0 = petiole * L                 # the blade starts after the stalk
    span = L - u0
    def env(t):                      # half-width at blade fraction t: narrow base, widest past the middle
        t = min(max(t, 0.0), 1.0)
        return Wd * math.sin(math.pi * t ** 1.55) ** 0.62 * min(1.0, t / 0.42) ** 0.55
    def side(sign, offset):
        """Lobe apexes and sinuses for one side, in increasing u.

        Each lobe is a rounded bulge whose apex sits toward its front edge, so
        the lobes point up the leaf the way an oak's do: a long shallow rise
        from the sinus behind, a short steep drop into the sinus ahead.
        """
        nodes = []
        s = 0.80 / lobes             # lobe spacing, as a blade fraction
        for k in range(lobes):
            t0 = 0.10 + s * k + offset * s          # the sinus behind this lobe
            t1 = t0 + s                             # the sinus ahead of it
            ta = t0 + 0.56 * s                      # the apex
            w = env(ta) * rnd.uniform(0.94, 1.04)
            su = span * s
            apex = (u0 + span * ta, sign * w)
            nodes.append((apex, (apex[0] - 0.36 * su, sign * w * 0.97),
                                (apex[0] + 0.28 * su, sign * w * 0.99)))
            if t1 < 0.93:
                d = env(t1) * 0.50
                sn = (u0 + span * t1, sign * d)
                lift = sign * (d + 0.60 * (env(t1) - d))
                nodes.append((sn, (sn[0] - 0.05 * su, lift), (sn[0] + 0.07 * su, lift)))
        return nodes
    upper = side(-1, 0.0)
    lower = side(+1, 0.18)
    tip_w = Wd * 0.42
    base = (u0, 0.0)
    nodes = [(base, (u0 + 0.05 * span, env(0.06)), (u0 + 0.05 * span, -env(0.06)))]
    nodes += upper
    nodes.append(((L, 0.0), (L, -tip_w), (L, tip_w)))
    # the lower side runs back toward the base, so its handles swap
    nodes += [(p, o, i) for p, i, o in reversed(lower)]
    blade = Contour([(P(*p), P(*i), P(*o)) for p, i, o in nodes], closed=True)
    m0, m1, m2 = P(u0, 0), P(u0 + 0.45 * span, 0), P(u0 + 0.86 * span, 0)
    c1, c2 = quad_to_cubic(m0, m1, m2)
    vein = Contour([(m0, None, c1), (m2, c2, None)], closed=False)
    return blade, vein, P(u0, 0)

def rosette(cx, cy, direction, n, L, spread=150, seed=0, lobes=4, size_jitter=0.12):
    """Oak leaves cluster at the ends of twigs. `n` leaves fanned across `spread`
    degrees around `direction`, the middle ones longest and drawn last."""
    rnd = random.Random(seed)
    out = []
    for i in range(n):
        f = (i / (n - 1) - 0.5) if n > 1 else 0.0
        a = math.radians(direction + f * spread + rnd.uniform(-8, 8))
        length = L * (1 - 0.35 * abs(f) * 2 ** 0.5) * rnd.uniform(1 - size_jitter, 1 + size_jitter)
        bend = (0.10 if f < 0 else -0.10) * (1 if math.cos(a) >= 0 else -1)
        out.append((abs(f), oak_leaf(cx, cy, a, length, length * 0.30, lobes, bend,
                                     seed=seed * 31 + i)))
    out.sort(key=lambda item: -item[0])          # outer first, so the middle is on top
    return [leaf for _, leaf in out]

def leaves_paths(pid, leaves, back=False, veins=True):
    blades = [b for b, _, _ in leaves]
    # a vein is 1.6 art px -- a quarter of a point in the garden. Worth it on
    # the big seedling leaves, invisible (and 2 vertices each) in a crown.
    veins = [v for _, v, _ in leaves] if veins else []
    paths = [Path(f"{pid}-leaves", blades, fill=LEAF_BACK if back else LEAF,
                  stroke=OUTLINE, stroke_width=LEAF_STROKE)]
    if veins:
        paths.append(Path(f"{pid}-veins", veins, stroke=VEIN_BACK if back else VEIN,
                          stroke_width=1.6, cap="round"))
    return paths

# ---------- wood ----------
def curve(p0, c1, c2, p3, n=14):
    return sample_cubic(p0, c1, c2, p3, n)

def wood_line(pid, pieces):
    """The outline pass: outline colour, filled and thickly stroked."""
    return Path(f"{pid}-wood-line", pieces, fill=BARK_OUTLINE, stroke=BARK_OUTLINE,
                stroke_width=WOOD_STROKE)

def wood_fill(pid, pieces):
    """The fill pass, drawn over every outline pass it should merge with."""
    return Path(f"{pid}-wood", pieces, fill=BARK)

def branch(pts, w0, w1, round_end=True):
    return tapered(pts, w0, w1, round_end)

def point_on(pts, s):
    lens = cumlen(pts)
    return at_frac(pts, lens, s)

# ---------- acorns ----------
def acorn(cx, cy, ang, size, stalk=True):
    """An acorn: a nut with a rounded point, a scaly cup over its base, a stalk.

    `ang` points from the cup to the nut's tip. Returns the pieces as contours
    and dots by role; acorn_paths() colours and names them.
    """
    ca, sa = math.cos(ang), math.sin(ang)
    P = lambda u, v: (cx + u*ca - v*sa, cy + u*sa + v*ca)
    L, Wd = size, size * 0.66
    hw = Wd / 2
    # the nut: u from 0 (inside the cup) to L (the tip)
    tip, left, right, back = P(L, 0), P(L * 0.42, -hw), P(L * 0.42, hw), P(0.05 * L, 0)
    body = Contour([
        (back, P(0.05 * L, hw * 0.9), P(0.05 * L, -hw * 0.9)),
        (left, P(L * 0.12, -hw), P(L * 0.78, -hw)),
        (tip, P(L * 0.98, -hw * 0.30), P(L * 0.98, hw * 0.30)),
        (right, P(L * 0.78, hw), P(L * 0.12, hw)),
    ], closed=True)
    sh = Contour([
        (P(L * 0.30, hw * 0.55), P(L * 0.20, hw * 0.70), P(L * 0.55, hw * 0.60)),
        (P(L * 0.92, hw * 0.18), P(L * 0.80, hw * 0.52), P(L * 0.86, hw * 0.62)),
        (P(L * 0.50, hw * 0.98), P(L * 0.70, hw * 0.95), P(L * 0.32, hw * 1.0)),
    ], closed=True)
    shine = Dot(*P(L * 0.62, -hw * 0.45), L * 0.08, L * 0.06)
    nib = Contour([(P(L * 0.98, -1.2), None, None), (P(L * 1.10, 0), None, None),
                   (P(L * 0.98, 1.2), None, None)], closed=True)
    # the cup: a bowl over the nut's base, deeper than it is wide
    cw, cd = hw * 1.18, L * 0.40
    c_l, c_r = P(cd, -cw), P(cd, cw)
    cup = Contour([
        (c_l, P(cd + 0.02 * L, -cw * 0.3), P(cd - 0.02 * L, -cw * 1.02)),   # rim
        (P(-L * 0.10, -cw * 0.55), P(cd * 0.25, -cw * 1.05), P(-L * 0.16, -cw * 0.25)),
        (P(-L * 0.10, cw * 0.55), P(-L * 0.16, cw * 0.25), P(cd * 0.25, cw * 1.05)),
        (c_r, P(cd - 0.02 * L, cw * 1.02), P(cd + 0.02 * L, cw * 0.3)),
    ], closed=True)
    scales = []
    for row, (u, n) in enumerate(((cd * 0.72, 5), (cd * 0.38, 4), (cd * 0.05, 3))):
        half = cw * (0.78 - 0.14 * row)
        for k in range(n):
            v = -half + 2 * half * (k + 0.5) / n
            scales.append(Dot(*P(u, v), L * 0.045, L * 0.032))
    parts = {"nut": [body], "shade": [sh], "shine": [shine], "cup": [cup],
             "scales": scales, "nib": [nib]}
    if stalk:
        s0, s1 = P(-L * 0.12, 0), P(-L * 0.34, -L * 0.05)
        parts["stalk"] = [tapered([s0, P(-L * 0.23, -L * 0.01), s1], L * 0.10, L * 0.06)]
    return parts

def acorn_paths(pid, acorns, nut=FRUIT, shade=FRUIT_SHADE, light=NUT_LIGHT):
    """Many acorns as a handful of shared paths. SVG order: stalk, nut, shade,
    shine, outline, cup, scales."""
    merged = {}
    for a in acorns:
        for key, items in a.items():
            merged.setdefault(key, []).extend(items)
    out = []
    if "stalk" in merged:
        out.append(Path(f"{pid}-stalks", merged["stalk"], fill=BARK_DARK, stroke=BARK_OUTLINE, stroke_width=1.6))
    out += [
        Path(f"{pid}-nuts", merged["nut"], fill=nut),
        Path(f"{pid}-nut-shade", merged["shade"], fill=shade),
        Dots(f"{pid}-nut-shine", merged["shine"], light),
        Path(f"{pid}-nut-line", merged["nut"] + merged["nib"], stroke=BARK_OUTLINE, stroke_width=2.2),
        Path(f"{pid}-cups", merged["cup"], fill=CAP, stroke=BARK_OUTLINE, stroke_width=2.2),
        Dots(f"{pid}-cup-scales", merged["scales"], CAP_DARK),
    ]
    return out

# ---------- stage 0: the acorn ----------
SEED_CENTRE = (508, GROUND - 38)
SEED_TILT = -32          # degrees; the tip lifts to the right, like the fern seed

def seed_stage():
    back, front = seed_bed()
    # the acorn's length runs from its cup to its tip; centre the pair on the bed
    a = acorn(SEED_CENTRE[0] - 26, SEED_CENTRE[1] + 14, math.radians(SEED_TILT), 64, stalk=True)
    nut = acorn_paths("seed", [a], nut=NUT, shade=NUT_SHADE)
    tip = (SEED_CENTRE[0] + 40, SEED_CENTRE[1] - 24)
    return back, Group("acorn", nut, tip=tip, kind="seed"), front

# ---------- stage 1: the sprout ----------
def sprout():
    """A green shoot with its first leaves, the split acorn lying beside it."""
    stem_pts = curve(BASE, (518, 820), (496, 750), (506, 668))
    stem = Path("shoot-stem", [tapered(stem_pts, 11, 5)], fill=SHOOT, stroke=OUTLINE, stroke_width=LEAF_STROKE)
    top = stem_pts[-1]
    leaves = [
        Group("leaf-left", leaves_paths("leaf-left", [oak_leaf(*top, math.radians(-150), 92, 30, 4, 0.10, seed=1)]),
              tip=(top[0] - 80, top[1] - 46), kind="leaf", pivot=top),
        Group("leaf-right", leaves_paths("leaf-right", [oak_leaf(*top, math.radians(-38), 100, 32, 4, -0.10, seed=2)]),
              tip=(top[0] + 78, top[1] - 62), kind="leaf", pivot=top),
        Group("leaf-bud", leaves_paths("leaf-bud", [oak_leaf(*top, math.radians(-96), 46, 15, 3, 0.0, seed=3)]),
              tip=(top[0] - 4, top[1] - 46), kind="leaf", pivot=top),
    ]
    shoot = Group("shoot", [stem] + leaves, tip=top, kind="shoot")
    return [shoot]

def husk():
    """The acorn the sprout came from: an empty cup and a split shell, on the mound."""
    a = acorn(474, GROUND - 14, math.radians(196), 46, stalk=False)
    return Group("husk", acorn_paths("husk", [a], nut=NUT, shade=NUT_SHADE))

# ---------- stage 2: the seedling ----------
SEEDLING_LEAVES = [  # (fraction up the stem, angle, length, side bend, lobes)
    (0.40, -160, 70, 0.10, 3),
    (0.58, -22, 78, -0.10, 4),
    (0.76, -150, 84, 0.10, 4),
]

def seedling():
    stem_pts = curve(BASE, (500, 790), (528, 690), (512, 560))
    stem = Path("shoot-stem", [tapered(stem_pts, 13, 5)], fill=SHOOT, stroke=OUTLINE, stroke_width=LEAF_STROKE)
    parts = [stem]
    for k, (s, deg, L, bend, lobes) in enumerate(SEEDLING_LEAVES):
        (x, y), _ = point_on(stem_pts, s)
        a = math.radians(deg)
        leaf = oak_leaf(x, y, a, L, L * 0.31, lobes, bend, seed=10 + k)
        tip = (x + L * math.cos(a), y + L * math.sin(a))
        parts.append(Group(f"leaf-{k+1}", leaves_paths(f"leaf-{k+1}", [leaf]),
                           tip=tip, kind="leaf", pivot=(x, y)))
    top = stem_pts[-1]
    crown = rosette(*top, -90, 3, 88, spread=110, seed=17)
    parts.append(Group("leaf-top", leaves_paths("leaf-top", crown),
                       tip=(top[0], top[1] - 80), kind="leaf", pivot=top))
    return [Group("shoot", parts, tip=top, kind="shoot")]

# ---------- trees: stages 3 to 5 ----------
# A tree is a trunk, some limbs, and a crown. The crown is laid out first -- a
# dome scattered with points where rosettes of leaves sit -- and each point is
# then given a twig from whichever limb passes nearest. Drawing it that way
# round is what makes the crown read as one mass rather than as leaves stuck on
# the ends of sticks.

class Crown:
    """A half-dome of rosette sites. `layer` picks back (dark, behind the trunk)
    or front (light, in front of it); the two are scattered separately so the
    back fills the gaps the front leaves."""
    def __init__(self, centre, rx, ry, floor, spacing, seed, tries=4000):
        rnd = random.Random(seed)
        cx, cy = centre
        pts = []
        for _ in range(tries):
            x = rnd.uniform(cx - rx, cx + rx); y = rnd.uniform(cy - ry, floor)
            if ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 > 1:
                continue
            if all(math.dist((x, y), q) >= spacing for q in pts):
                pts.append((x, y))
        self.centre, self.points = centre, pts

    def outward(self, p):
        """The way a rosette at p faces: away from the crown's heart, and up."""
        cx, cy = self.centre
        a = math.degrees(math.atan2(p[1] - (cy + 60), p[0] - cx))
        return a * 0.75 + (-90) * 0.25

def nearest_on(pts, p, s_min=0.3):
    lens = cumlen(pts)
    best = None
    for i in range(41):
        s = s_min + (1 - s_min) * i / 40
        q, _ = at_frac(pts, lens, s)
        d = math.dist(q, p)
        if best is None or d < best[0]:
            best = (d, s, q)
    return best

class LimbSpec:
    def __init__(self, lid, at, c1, c2, tip, w0, back=False, seed=0):
        self.lid, self.at, self.c1, self.c2, self.tip = lid, at, c1, c2, tip
        self.w0, self.back, self.seed = w0, back, seed

def tree(trunk_top, trunk_w, specs, crowns, leaf_len, rosette_n, trunk_kind,
         flare=0, bark=0, acorns=False):
    """A whole tree as one animated trunk with its limbs nested inside it.

    `crowns` is [(Crown, back?)]. Every rosette site in a back crown goes to
    the nearest back limb, every front site to the nearest front limb.

    Draw order, back to front, inside the trunk:

        back limbs          whole: they sit behind the trunk
        front limb outlines
        trunk               outline, fill, bark
        front limbs         fill, leaves, acorns

    A front limb is split in two so that its outline is under the trunk's
    fill and its fill is over the trunk's outline. Where they overlap, neither
    outline shows, and the limb grows out of the trunk instead of being laid
    across it. The outline half `follows` the fill half, so they move as one.
    """
    tp = trunk_pts(trunk_top)
    limbs = []
    for sp in specs:
        pv = point_on(tp, sp.at)[0]
        add = lambda d: (pv[0] + d[0], pv[1] + d[1])
        pts = curve(pv, add(sp.c1), add(sp.c2), sp.tip, 12)
        limbs.append((sp, pv, pts))
    sites = {sp.lid: [] for sp in specs}
    for crown, back in crowns:
        for p in crown.points:
            options = [(nearest_on(pts, p), sp) for sp, pv, pts in limbs if sp.back == back]
            (d, s, q), sp = min(options, key=lambda o: o[0][0])
            sites[sp.lid].append((p, s, q, crown.outward(p)))
    groups = {}
    cx = sum(c.centre[0] for c, _ in crowns) / len(crowns)
    for sp, pv, pts in limbs:
        rnd = random.Random(sp.seed)
        # the ends are hidden under rosettes, so they are left square
        pieces = [branch(pts, sp.w0, 3.5, round_end=False)]
        rosettes = []
        # lower sites last, so the rosettes nearer the viewer overlap the ones above
        for k, (p, s, q, facing) in enumerate(sorted(sites[sp.lid], key=lambda t: t[0][1])):
            if math.dist(p, q) > 16:
                mid = ((p[0] + q[0]) / 2 + rnd.uniform(-8, 8), (p[1] + q[1]) / 2 - 8)
                wq = max(sp.w0 * (1 - s) + 3.5 * s, 4) * 0.7
                pieces.append(branch(curve(q, mid, mid, p, 4), wq, 3, round_end=False))
            rid = f"{sp.lid}-r{k + 1}"
            length = leaf_len * rnd.uniform(0.9, 1.1)
            children = leaves_paths(rid, rosette(*p, facing, rosette_n, length, spread=200,
                                                 seed=sp.seed * 13 + k), sp.back, veins=False)
            if acorns and not sp.back and k % 2 == 1:
                hang = math.radians(90 + rnd.uniform(-20, 20))
                fruit = [acorn(p[0] + j * 16, p[1] + 12, hang + j * 0.40, 36) for j in (-1, 1)]
                children += acorn_paths(f"{rid}-acorns", fruit)
            a = math.radians(facing)
            # Each rosette is its own part: it flutters on its own, and when the
            # tree is thirsty it hangs -- outward, away from the crown's middle.
            rosettes.append(Group(rid, children, kind="rosette", pivot=p,
                                  tip=(p[0] + length * math.cos(a), p[1] + length * math.sin(a)),
                                  meta={"droop_direction": 1 if p[0] >= cx else -1}))
        children = [wood_fill(sp.lid, pieces)] + rosettes
        line = wood_line(sp.lid, pieces)
        if sp.back:
            children.insert(0, line)
        else:
            groups[sp.lid + "-line"] = Group(sp.lid + "-line", [line], tip=sp.tip, kind="limb",
                                             pivot=pv, meta={"follows": sp.lid})
        groups[sp.lid] = Group(sp.lid, children, tip=sp.tip, kind="limb", pivot=pv)
    trunk_pieces = [branch(tp, *trunk_w)]
    if flare:
        # two low buttresses where the trunk meets the mound
        bx, by = BASE[0], BASE[1] + 12
        for sd in (-1, 1):
            trunk_pieces.append(Contour([
                ((bx + sd * trunk_w[0] * 0.30, by - flare * 1.6), None, None),
                ((bx + sd * (trunk_w[0] * 0.5 + flare), by), None,
                 (bx + sd * (trunk_w[0] * 0.5 + flare * 0.2), by - flare * 0.2)),
                ((bx + sd * trunk_w[0] * 0.40, by - flare * 1.2),
                 (bx + sd * trunk_w[0] * 0.45, by - flare * 0.5), None),
            ], closed=True))
    trunk = [wood_line("trunk", trunk_pieces), wood_fill("trunk", trunk_pieces)]
    if bark:
        trunk.append(bark_lines(tp, *trunk_w, n=bark, seed=5))
    back = [groups[sp.lid] for sp in specs if sp.back]
    lines = [groups[sp.lid + "-line"] for sp in specs if not sp.back]
    front = [groups[sp.lid] for sp in specs if not sp.back]
    top_tip = max((sp.tip for sp in specs), key=lambda t: -t[1])
    return [Group("trunk", back + lines + trunk + front, tip=top_tip, kind=trunk_kind)]

def trunk_pts(top):
    x0, y0 = BASE[0], BASE[1] + 14
    return curve((x0, y0), (x0 + 6, y0 - (y0 - top[1]) * 0.35),
                 (top[0] - 8, y0 - (y0 - top[1]) * 0.7), top)

def bark_lines(pts, w0, w1, n=4, seed=0):
    """A few dark strokes along the trunk -- enough to say bark, not a texture."""
    rnd = random.Random(seed)
    lens = cumlen(pts); out = []
    for k in range(n):
        s0 = rnd.uniform(0.06, 0.45); s1 = s0 + rnd.uniform(0.18, 0.30)
        off = ((k + 0.5) / n - 0.5) * 1.1
        line = []
        for i in range(6):
            s = s0 + (s1 - s0) * i / 5
            (x, y), a = at_frac(pts, lens, s)
            w = (w0 + (w1 - w0) * s) / 2
            line.append((x - math.sin(a) * w * off, y + math.cos(a) * w * off))
        out.append(Contour([(p, None, None) for p in line], closed=False))
    return Path("trunk-bark", out, stroke=BARK_DARK, stroke_width=2.6, cap="round")

YOUNG_TOP = (514, 520)
YOUNG_LIMBS = [
    LimbSpec("limb-back", 0.92, (-10, -40), (-30, -90), (470, 360), 10, back=True, seed=51),
    LimbSpec("limb-left", 0.78, (-30, -30), (-70, -70), (410, 440), 11, seed=52),
    LimbSpec("limb-right", 0.86, (30, -30), (70, -60), (625, 430), 11, seed=53),
    LimbSpec("limb-top", 1.00, (2, -40), (10, -90), (535, 335), 10, seed=54),
]

def young():
    crowns = [(Crown((515, 410), 160, 105, 450, 72, seed=3), True),
              (Crown((515, 425), 200, 125, 500, 78, seed=4), False)]
    return tree(YOUNG_TOP, (26, 12), YOUNG_LIMBS, crowns, leaf_len=64, rosette_n=5,
                trunk_kind="sapling", bark=0)

MATURE_TOP = (512, 600)
MATURE_LIMBS = [
    LimbSpec("limb-back-left", 0.93, (-20, -90), (-80, -220), (400, 250), 24, back=True, seed=41),
    LimbSpec("limb-back-right", 0.95, (20, -90), (80, -230), (630, 240), 24, back=True, seed=42),
    LimbSpec("limb-low-left", 0.78, (-70, -30), (-170, -100), (215, 460), 26, seed=43),
    LimbSpec("limb-low-right", 0.83, (70, -30), (170, -95), (815, 450), 26, seed=44),
    LimbSpec("limb-left", 0.92, (-50, -60), (-150, -170), (315, 320), 26, seed=45),
    LimbSpec("limb-right", 0.95, (50, -60), (150, -180), (715, 315), 26, seed=46),
    LimbSpec("limb-center", 1.00, (-8, -100), (14, -230), (520, 230), 26, seed=47),
]

def mature(bloom=False):
    crowns = [(Crown((512, 330), 330, 200, 430, 84, seed=7), True),
              (Crown((512, 360), 380, 225, 520, 88, seed=8), False)]
    return tree(MATURE_TOP, (74, 34), MATURE_LIMBS, crowns, leaf_len=82, rosette_n=5,
                trunk_kind="trunk", flare=16, bark=4, acorns=bloom)

STAGE_MOUND = {1: 70, 2: 90, 3: 110, 4: 170, 5: 170}

def stage_parts(n):
    """(animated parts, back, front) for one stage. See fern_generator.stage_parts."""
    if n == 0:
        back, acorn_part, front = seed_stage()
        return [acorn_part], back, front
    if n == 1:
        parts = sprout()
        mound = base_mound(STAGE_MOUND[n])
        return parts, None, Group("soil-front", [mound, husk()])
    if n == 2:
        parts = seedling()
    elif n == 3:
        parts = young()
    else:
        parts = mature(bloom=(n == 5))
    return parts, None, base_mound(STAGE_MOUND[n])

# ---------- roots ----------
def build_root_tree(seed=11):
    """A taproot, and the laterals an oak spreads near the surface.

    The taproot is primary 0, so it is the one root every level shows -- the
    first thing an acorn grows is the root the app is named after.
    """
    rnd = random.Random(seed)
    tap_len = 440
    tap = Root("taproot", 0, math.radians(90), tap_len, 22, 1, seed * 10,
               wander=0.04, gravity=0.12)
    for j in range(6):
        fr = 0.16 + 0.13 * j + rnd.uniform(-0.03, 0.03)
        sd = 1 if j % 2 == 0 else -1
        c = Root(f"taproot-{j+1}", fr, math.radians(90 - sd * rnd.uniform(45, 62)),
                 tap_len * rnd.uniform(0.26, 0.36) * (1 - fr * 0.5), 7, 2, seed * 100 + j,
                 wander=0.12, gravity=0.03)
        for m in range(2):
            c.children.append(Root(f"{c.rid}-{m+1}", 0.35 + 0.3 * m,
                                   c.ang + (-sd if m == 0 else sd) * math.radians(rnd.uniform(30, 50)),
                                   c.length * rnd.uniform(0.35, 0.5), 3.4, 3, seed * 1000 + j * 10 + m))
        tap.children.append(c)
    prim = [tap]
    for i, deg in enumerate((22, 158, 48, 132)):
        ln = rnd.uniform(270, 330) * (0.8 if i > 1 else 1)
        r = Root(f"lateral-{i+1}", 0, math.radians(deg + rnd.uniform(-4, 4)), ln,
                 13 if i < 2 else 10, 1, seed * 10 + i + 1, wander=0.10, gravity=0.03)
        for j in range(3):
            fr = 0.3 + 0.22 * j + rnd.uniform(-0.04, 0.04)
            sd = 1 if j % 2 == 0 else -1
            c = Root(f"{r.rid}-{j+1}", fr, r.ang + sd * math.radians(rnd.uniform(30, 50)),
                     ln * rnd.uniform(0.28, 0.4) * (1 - fr * 0.4), 6, 2, seed * 200 + i * 10 + j)
            c.children.append(Root(f"{c.rid}-1", 0.5, c.ang - sd * math.radians(35),
                                   c.length * 0.45, 3.2, 3, seed * 2000 + i * 100 + j))
            r.children.append(c)
        prim.append(r)
    return prim

ROOT_LEVELS = {  # level: (length scale, max generation, number of primaries)
    1: (0.34, 1, 1),     # the taproot alone
    2: (0.55, 2, 3),
    3: (0.78, 2, 5),
    4: (1.00, 3, 5),
}

# ---------- motion ----------
SWAY = {}
# A tree moves at its ends, not its base: limbs sway most, the trunk barely.
SWAY_DEFAULT = {"rosette": 2.6, "limb": 1.1, "leaf": 3.0, "shoot": 1.4,
                "sapling": 0.8, "trunk": 0.25, "seed": 1.2}
# A thirsty tree shows it in its leaves, not its wood: the rosettes hang, the
# limbs sag a little, the trunk not at all. Limbs that fell as far as fronds do
# would open the crown down the middle, which reads as the tree splitting.
DROOP_KIND_SCALE = {"rosette": 1.3, "limb": 0.3, "leaf": 1.4, "shoot": 0.6,
                    "sapling": 0.3, "trunk": 0.0, "seed": 0.0}
DROOP_DIRECTION = {
    (1, "shoot"): +1,
    (1, "leaf-bud"): -1,
    (2, "shoot"): -1,
    (2, "leaf-top"): +1,
    (3, "trunk"): +1,
    (3, "limb-top"): -1,
    (4, "limb-center"): +1,
    (5, "limb-center"): +1,
}
LEAN_THRESHOLD = {3: 0.30, 4: 0.50}
LEAN_DIRECTION = {3: -1, 4: -1}   # the other way from the fern, so a mixed garden does not all tip one way

OAK = Species(
    "Oak", stage_parts, build_root_tree, ROOT_LEVELS, DRY_FILL,
    sway=SWAY, sway_default=SWAY_DEFAULT, droop_kind_scale=DROOP_KIND_SCALE,
    droop_direction=DROOP_DIRECTION, lean_threshold=LEAN_THRESHOLD,
    lean_direction=LEAN_DIRECTION, still_stages=(0,))

if __name__ == "__main__":
    # python3 oak_generator.py [--sway=wind|independent] [--amplitude=1.4]
    main(OAK, "oak", sys.argv[1:], __file__)
