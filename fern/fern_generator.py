"""Taproot fern generator — produces layered, animation-ready SVGs and RML.

Plant canvases: 1024x1024, ground line at y=GROUND, stems emerge from (512, GROUND-18).
Root canvases:  1024x1024, ground line at y=0, roots hang from (512, 0).
Stack a plant canvas directly on top of a root canvas and the ground lines meet.

The script is the source of truth for the geometry. Parts are built as a small
drawable model (groups of paths and dot clusters); the SVG writer and the RML
emitter are two readers over that one model, so the two outputs can never drift.

See NOTES.md for the RML capabilities this relies on and the traps it avoids.
"""
import math, random, os

# ---------- palette ----------
OUTLINE = "#2F4A2C"; LEAF = "#6FA35A"; LEAF_BACK = "#4E7F43"; STEM = "#3E6B3A"
MIDRIB = "#4E7F43"; MIDRIB_BACK = "#3E6B3A"
SOIL = "#7A5537"; SOIL_DARK = "#5E3F28"; ROOT = "#8A6443"; ROOT_OUTLINE = "#4A3322"
OCHRE = "#D9A441"
# the thirsty end of the droop blend -- desaturated toward grey-green, not brown.
# the plant should read as needing water, not as dead.
LEAF_DRY = "#98A585"; LEAF_BACK_DRY = "#71806A"
COIL = "#5E9150"; COIL_DRY = "#8B9A7E"
W = 1024; GROUND = 900; BASE = (512, GROUND - 18)

# Every fill that fades as vitality drops, healthy -> thirsty. A fill not in
# here is keyed by nobody and stays put: stems, midribs, soil, spores.
DRY_FILL = {LEAF: LEAF_DRY, LEAF_BACK: LEAF_BACK_DRY, COIL: COIL_DRY}

CAP_SAMPLES = 8  # straight vertices used to round a tapered tip

def f(p): return f"{p[0]:.1f},{p[1]:.1f}"

# ---------- geometry model ----------
class Contour:
    """On-curve nodes with *absolute* bezier handles, the way SVG writes them.

    A node is (point, in_handle, out_handle). A handle of None means the segment
    on that side is straight. The RML emitter converts handles to Rive's polar
    (rotation, distance) form; keeping them absolute here means the SVG writer
    needs no conversion at all.
    """
    __slots__ = ("nodes", "closed")

    def __init__(self, nodes=None, closed=True):
        self.nodes = list(nodes or [])
        self.closed = closed

class Dot:
    """An ellipse. Stored as data so SVG writes an arc and RML writes <Ellipse>."""
    __slots__ = ("cx", "cy", "rx", "ry")

    def __init__(self, cx, cy, rx, ry=None):
        self.cx, self.cy, self.rx, self.ry = cx, cy, rx, (rx if ry is None else ry)

def polyline(pts, closed=True):
    return Contour([(p, None, None) for p in pts], closed)

def quad_to_cubic(p0, q, p1):
    """Elevate a quadratic to a cubic: control points relative to each endpoint."""
    return ((p0[0] + 2 / 3 * (q[0] - p0[0]), p0[1] + 2 / 3 * (q[1] - p0[1])),
            (p1[0] + 2 / 3 * (q[0] - p1[0]), p1[1] + 2 / 3 * (q[1] - p1[1])))

def arc_pts(centre, radius, a0, a1, n=CAP_SAMPLES):
    """Sample an arc, endpoints included. Replaces what used to be an SVG `A`."""
    return [(centre[0] + radius * math.cos(a0 + (a1 - a0) * i / n),
             centre[1] + radius * math.sin(a0 + (a1 - a0) * i / n)) for i in range(n + 1)]

# ---------- drawables ----------
class Path:
    """One <path> in SVG, one <Shape> in RML. Holds any number of contours."""
    def __init__(self, pid, contours, fill=None, stroke=None, stroke_width=0,
                 join="round", cap=None):
        self.pid, self.contours = pid, list(contours)
        self.fill, self.stroke, self.stroke_width = fill, stroke, stroke_width
        self.join, self.cap = join, cap

class Dots:
    """A cluster of ellipses sharing one fill."""
    def __init__(self, pid, dots, fill):
        self.pid, self.dots, self.fill = pid, list(dots), fill

class Group:
    """A named group of drawables.

    `tip` and `kind` are set on the parts that animate — a frond or a
    fiddlehead — and are what the droop and the sway read instead of a lookup
    table, so both work for any stage without knowing which one it is.
    """
    def __init__(self, gid, children=(), tip=None, kind=None, origin=None, scale=None,
                 meta=None):
        self.gid, self.children = gid, list(children)
        self.tip, self.kind = tip, kind
        # A group may carry its own transform. The roots need it: every root and
        # branch is placed at its attachment point with its geometry local to
        # that point, so growing one is a scale on its node rather than a
        # different set of vertices. SVG writes it as a `transform`, RML as the
        # Node's own x/y/scaleX/scaleY.
        self.origin, self.scale = origin, scale
        self.meta = meta or {}

# ---------- geometry helpers ----------
def cubic(p0, p1, p2, p3, t):
    u = 1 - t
    return tuple(u**3*a + 3*u*u*t*b + 3*u*t*t*c + t**3*d for a, b, c, d in zip(p0, p1, p2, p3))

def sample_cubic(p0, p1, p2, p3, n=48):
    return [cubic(p0, p1, p2, p3, i / n) for i in range(n + 1)]

def cumlen(pts):
    out = [0.0]
    for a, b in zip(pts, pts[1:]):
        out.append(out[-1] + math.dist(a, b))
    return out

def at_frac(pts, lens, s):
    """point + tangent angle at arc-length fraction s"""
    target = s * lens[-1]
    for i in range(1, len(pts)):
        if lens[i] >= target:
            seg = lens[i] - lens[i-1] or 1e-9
            k = (target - lens[i-1]) / seg
            a, b = pts[i-1], pts[i]
            return (a[0] + (b[0]-a[0])*k, a[1] + (b[1]-a[1])*k), math.atan2(b[1]-a[1], b[0]-a[0])
    a, b = pts[-2], pts[-1]
    return b, math.atan2(b[1]-a[1], b[0]-a[0])

def tapered(pts, w0, w1, round_end=True):
    """closed outline around a polyline, width w0 -> w1, with a sampled round tip.

    The tip used to be an SVG elliptical arc. It is sampled into straight points
    instead so SVG and RML carry identical geometry and the RML emitter only
    ever meets straight and cubic vertices.
    """
    lens = cumlen(pts); L = lens[-1] or 1
    left, right = [], []
    normal_end = (0.0, 0.0)
    for i, p in enumerate(pts):
        a = pts[max(i-1, 0)]; b = pts[min(i+1, len(pts)-1)]
        ang = math.atan2(b[1]-a[1], b[0]-a[0])
        w = (w0 + (w1 - w0) * lens[i] / L) / 2
        nx, ny = -math.sin(ang), math.cos(ang)
        left.append((p[0] + nx*w, p[1] + ny*w)); right.append((p[0] - nx*w, p[1] - ny*w))
        normal_end = (nx, ny)
    ring = list(left)
    if round_end:
        r = max(w1 / 2, 0.8)
        a0 = math.atan2(normal_end[1], normal_end[0])
        # the cap sweeps from the left edge round the tip to the right edge
        ring += arc_pts(pts[-1], r, a0, a0 + math.pi)[1:-1]
    ring += list(reversed(right))
    return polyline(ring, closed=True)

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

def base_mound(width=120):
    x0, x1 = 512 - width/2, 512 + width/2
    h = width * 0.30
    a = (x0, GROUND)
    b = (512, GROUND - h)
    c = (x1, GROUND)
    a_out = (x0 + width*0.08, GROUND - h*0.9); b_in = (512 - width*0.22, GROUND - h*1.15)
    b_out = (512 + width*0.25, GROUND - h*1.2); c_in = (x1 - width*0.06, GROUND - h*0.8)
    c_out, a_in = quad_to_cubic(c, (512, GROUND + 5), a)   # the underside, a quad in SVG
    mound = Contour([(a, a_in, a_out), (b, b_in, b_out), (c, c_in, c_out)], closed=True)
    clumps = [Dot(cx, cy, r, r * 0.75) for cx, cy, r in (
        (512 - width*0.22, GROUND - h*0.35, width*0.035),
        (512 + width*0.18, GROUND - h*0.45, width*0.028),
        (512 + width*0.02, GROUND - h*0.18, width*0.022))]
    return Group("base", [
        Path("base-mound", [mound], fill=SOIL, stroke=ROOT_OUTLINE, stroke_width=2.6),
        Dots("base-clumps", clumps, SOIL_DARK),
    ])

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

def seed_bed(width=112):
    """The mound behind the seed, and a low lip of soil in front of it."""
    x0, x1, h = 512 - width/2, 512 + width/2, width * 0.22
    a, b, c = (x0, GROUND), (512, GROUND - h), (x1, GROUND)
    c_out, a_in = quad_to_cubic(c, (512, GROUND + 5), a)
    mound = Contour([(a, a_in, (x0 + width*0.10, GROUND - h*0.9)),
                     (b, (512 - width*0.25, GROUND - h*1.1), (512 + width*0.25, GROUND - h*1.1)),
                     (c, (x1 - width*0.10, GROUND - h*0.9), c_out)], closed=True)
    lw, lh = width * 0.80, h * 0.62          # the lip: lower and narrower, in front
    la, lb, lc = (512 - lw/2, GROUND), (512 + 4, GROUND - lh), (512 + lw/2, GROUND)
    lc_out, la_in = quad_to_cubic(lc, (512, GROUND + 4), la)
    lip = Contour([(la, la_in, (512 - lw*0.30, GROUND - lh*0.35)),
                   (lb, (512 - lw*0.22, GROUND - lh*1.05), (512 + lw*0.22, GROUND - lh*0.95)),
                   (lc, (512 + lw*0.30, GROUND - lh*0.30), lc_out)], closed=True)
    clumps = [Dot(512 - width*0.24, GROUND - h*0.30, 3.4, 2.6),
              Dot(512 + width*0.20, GROUND - h*0.22, 2.8, 2.1),
              Dot(512 + width*0.02, GROUND - h*0.12, 2.2, 1.7)]
    back = Group("base", [Path("base-mound", [mound], fill=SOIL_DARK, stroke=ROOT_OUTLINE, stroke_width=2.6)])
    front = Group("soil-front", [
        Path("soil-front-lip", [lip], fill=SOIL, stroke=ROOT_OUTLINE, stroke_width=2.6),
        Dots("soil-front-clumps", clumps, SOIL_DARK),
    ])
    return back, front

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

def stage(n):
    """The drawables for one stage, as the SVG writer wants them: back to front."""
    parts, back, front = stage_parts(n)
    out = [back] if back else []
    out.append(Group("plant", parts))
    if front:
        out.append(front)
    return out

# ---------- roots ----------
class Root:
    def __init__(self, rid, frac, ang, length, width, gen, seed, children=()):
        self.rid, self.frac, self.ang, self.length, self.width, self.gen = rid, frac, ang, length, width, gen
        rnd = random.Random(seed)
        # shape defined in unit length so it scales cleanly between levels
        self.unit = [(0.0, 0.0)]; a = ang; x = y = 0.0
        steps = 24
        for i in range(steps):
            a += rnd.uniform(-0.10, 0.10)
            a += (math.pi/2 - a) * 0.035          # gentle gravity
            x += math.cos(a) / steps; y += math.sin(a) / steps
            self.unit.append((x, y))
        self.children = list(children)

    def pts(self, origin, s):
        return [(origin[0] + u*self.length*s, origin[1] + v*self.length*s) for u, v in self.unit]

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

ROOT_ORIGIN = (512, 0)       # the ground line; roots hang down from here

def root_forest(tree):
    """The whole root system as nested Groups, authored at full size.

    Every root and every branch is its own node, placed at its attachment point
    in its *parent's* local space, holding geometry that starts at its own
    origin. Nothing here knows about levels: growing the system is a scale on
    these nodes, which is what lets one tree serve every level.

    Scale composes down the hierarchy, so scaling a primary carries its branches
    and their attachment points with it — which is what a root growing longer
    actually does.
    """
    def node(r, prim_index):
        local = [(u * r.length, v * r.length) for u, v in r.unit]
        shape = Path(f"{r.rid}-shape", [tapered(local, r.width, 1.4)], fill=ROOT,
                     stroke=ROOT_OUTLINE, stroke_width=(2.2 if r.gen == 1 else 1.8))
        lens = cumlen(local)
        body = []
        for c in r.children:
            attach, _ = at_frac(local, lens, c.frac)
            child = node(c, prim_index)
            child.origin = attach
            body.append(child)
        # The root's own shape goes last, which paints it *over* its branches in
        # both writers. A branch has to emerge from behind the root it grows
        # off; drawn on top, its stroked end cuts a visible notch across it.
        body.append(shape)
        return Group(r.rid, body, kind="root", origin=(0.0, 0.0),
                     meta={"gen": r.gen, "prim": prim_index})

    return Group("roots", [node(r, i) for i, r in enumerate(tree)], origin=ROOT_ORIGIN)

def root_scale(part, level):
    """The scale one root node takes at one root level. 0 means "not yet there".

    A primary carries the level's length factor; a branch is either present at
    full size or absent, because a branch that is shown is shown whole. `level`
    of None is the empty pose, before any roots exist at all.
    """
    if level is None:
        return 0.0
    length_factor, max_generation, primary_count = ROOT_LEVELS[level]
    if part.meta["gen"] == 1:
        return length_factor if part.meta["prim"] < primary_count else 0.0
    return 1.0 if part.meta["gen"] <= max_generation else 0.0

def root_parts(forest):
    """Every root node in the forest, depth-first. One entry per keyed node."""
    out = []
    def walk(group):
        if group.kind == "root":
            out.append(group)
        for child in group.children:
            if isinstance(child, Group):
                walk(child)
    walk(forest)
    return out

def roots(level, tree):
    """The root system posed at one level, for the SVG reference.

    Reads the same forest and the same scale rule the RML poses use, so the two
    cannot describe different plants.
    """
    forest = root_forest(tree)
    for part in root_parts(forest):
        part.scale = root_scale(part, level)
    return [forest]

# ---------- SVG writer ----------
def contour_d(c):
    nodes = c.nodes
    out = [f"M{f(nodes[0][0])}"]
    seq = nodes[1:] + ([nodes[0]] if c.closed else [])
    prev = nodes[0]
    for node in seq:
        c1, c2 = prev[2], node[1]
        if c1 is None and c2 is None:
            out.append(f"L{f(node[0])}")
        else:
            out.append(f"C{f(c1 or prev[0])} {f(c2 or node[0])} {f(node[0])}")
        prev = node
    if c.closed:
        out.append("Z")
    return " ".join(out)

def dot_d(d):
    return (f"M{d.cx - d.rx:.1f},{d.cy:.1f} a{d.rx:.1f},{d.ry:.1f} 0 1,0 {2*d.rx:.1f},0 "
            f"a{d.rx:.1f},{d.ry:.1f} 0 1,0 {-2*d.rx:.1f},0")

def group_transform(item):
    parts = []
    if item.origin and item.origin != (0, 0):
        parts.append(f"translate({item.origin[0]:.1f},{item.origin[1]:.1f})")
    if item.scale is not None and item.scale != 1:
        parts.append(f"scale({item.scale:.4f})")
    return f' transform="{" ".join(parts)}"' if parts else ""

def svg_item(item):
    if isinstance(item, Group):
        return (f'<g id="{item.gid}"{group_transform(item)}>'
                + "".join(svg_item(c) for c in item.children) + "</g>")
    if isinstance(item, Dots):
        return f'<path id="{item.pid}" d="{" ".join(dot_d(d) for d in item.dots)}" fill="{item.fill}"/>'
    d = " ".join(contour_d(c) for c in item.contours)
    attrs = [f'id="{item.pid}"', f'd="{d}"', f'fill="{item.fill or "none"}"']
    if item.stroke:
        attrs.append(f'stroke="{item.stroke}"')
        attrs.append(f'stroke-width="{item.stroke_width}"')
        attrs.append(f'stroke-linecap="{item.cap}"' if item.cap else f'stroke-linejoin="{item.join}"')
    return f'<path {" ".join(attrs)}/>'

def svg(items, h=1024, bg=None):
    rect = f'<rect width="{W}" height="{h}" fill="{bg}"/>' if bg else ""
    body = "".join(svg_item(i) for i in items)
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {h}" width="{W}" height="{h}">{rect}{body}</svg>'

# ---------- RML emitter ----------
def argb(hex_colour):
    """#RRGGBB -> Rive's bare AARRGGBB, alpha first, no hash."""
    return "FF" + hex_colour.lstrip("#").upper()

class Ids:
    """A monotonic id allocator. Every element gets one so a rebuild is
    byte-stable and the CLI's id write-back has nothing to do."""
    def __init__(self, client=0, start=2):
        self.client, self.n = client, start

    def __call__(self):
        self.n += 1
        return f"{self.client}:{self.n - 1}"

def polar(p, ctrl):
    """Rive stores a handle as an angle + length from its vertex, not as an
    absolute control point. This is the whole reason RML is generated, not typed."""
    dx, dy = ctrl[0] - p[0], ctrl[1] - p[1]
    return math.atan2(dy, dx), math.hypot(dx, dy)

def rml_vertices(contour, origin, ids, indent):
    ox, oy = origin
    out = []
    for point, cin, cout in contour.nodes:
        x, y = point[0] - ox, point[1] - oy
        if cin is None and cout is None:
            out.append(f'{indent}<StraightVertex x="{x:.2f}" y="{y:.2f}" id="{ids()}"/>')
        else:
            ir, idist = polar(point, cin) if cin else (0.0, 0.0)
            orr, odist = polar(point, cout) if cout else (0.0, 0.0)
            out.append(f'{indent}<CubicDetachedVertex x="{x:.2f}" y="{y:.2f}" '
                       f'inRotation="{ir:.5f}" inDistance="{idist:.2f}" '
                       f'outRotation="{orr:.5f}" outDistance="{odist:.2f}" id="{ids()}"/>')
    return out

def rml_paint(item, ids, indent, paints=None):
    """Fill first, then Stroke: within a Shape the later paint draws on top,
    which is the order SVG paints them in.

    `paints` collects each fill's SolidColor id under the path's name, so an
    animation can key the colour later without hunting through the tree.
    """
    out = []
    if item.fill:
        colour_id = ids()
        if paints is not None:
            paints[item.pid] = colour_id
        out.append(f'{indent}<Fill name="Fill" id="{ids()}">')
        out.append(f'{indent}    <SolidColor colorValue="{argb(item.fill)}" name="Color" id="{colour_id}"/>')
        out.append(f'{indent}</Fill>')
    stroke = getattr(item, "stroke", None)
    if stroke:
        cap = f' cap="{item.cap}"' if item.cap else ""
        out.append(f'{indent}<Stroke thickness="{item.stroke_width}" join="{item.join}"{cap} '
                   f'name="Stroke" id="{ids()}">')
        out.append(f'{indent}    <SolidColor colorValue="{argb(stroke)}" name="Color" id="{ids()}"/>')
        out.append(f'{indent}</Stroke>')
    return out

def rml_item(item, origin, ids, depth, paints=None, groups=None):
    ind = "    " * depth
    if isinstance(item, Group):
        attrs = ""
        if item.origin:
            attrs += f' x="{item.origin[0]:.2f}" y="{item.origin[1]:.2f}"'
        if item.scale is not None:
            attrs += f' scaleX="{item.scale:.4f}" scaleY="{item.scale:.4f}"'
        node_id = ids()
        if groups is not None:
            groups[item.gid] = node_id
        out = [f'{ind}<Node{attrs} name="{item.gid}" id="{node_id}">']
        # draw order is reversed from SVG: the first Shape declared paints on top
        for child in reversed(item.children):
            out += rml_item(child, origin, ids, depth + 1, paints, groups)
        out.append(f'{ind}</Node>')
        return out
    if isinstance(item, Dots):
        out = [f'{ind}<Shape name="{item.pid}" id="{ids()}">']
        for d in item.dots:
            out.append(f'{ind}    <Ellipse x="{d.cx - origin[0]:.2f}" y="{d.cy - origin[1]:.2f}" '
                       f'width="{2*d.rx:.2f}" height="{2*d.ry:.2f}" name="Dot" id="{ids()}"/>')
        out += rml_paint(item, ids, ind + "    ", paints)
        out.append(f'{ind}</Shape>')
        return out
    out = [f'{ind}<Shape name="{item.pid}" id="{ids()}">']
    for c in item.contours:
        closed = ' isClosed="true"' if c.closed else ""
        out.append(f'{ind}    <PointsPath{closed} name="Path" id="{ids()}">')
        out += rml_vertices(c, origin, ids, ind + "        ")
        out.append(f'{ind}    </PointsPath>')
    out += rml_paint(item, ids, ind + "    ", paints)
    out.append(f'{ind}</Shape>')
    return out

def part_node(group, ids, depth, nodes, paints=None):
    """A frond or fiddlehead gets two nested transforms, both pivoted on the
    shared base point.

    The outer one carries the vitality droop, the inner the sway loop. Keeping
    them separate means each rotation has exactly one owner, so the two
    timelines compose instead of overwriting one another. `nodes` collects the
    two ids so the animations can key them.
    """
    ind = "    " * depth
    droop_id, sway_id = ids(), ids()
    nodes[group.gid] = {"droop": droop_id, "sway": sway_id}
    # (0,0) because the enclosing `plant` node is already at the base point
    out = [f'{ind}<Node name="{group.gid}-droop" id="{droop_id}">',
           f'{ind}    <Node name="{group.gid}-sway" id="{sway_id}">']
    for child in reversed(group.children):
        out += rml_item(child, BASE, ids, depth + 2, paints)
    out += [f'{ind}    </Node>', f'{ind}</Node>']
    return out

def sway_animation(parts, nodes, ids, anim_id, depth=2):
    """Key rotation (propertyKey 15, radians) on every part's inner sway node.

    The curve is sampled rather than keyed at its extremes: the two components
    have different phases, so there is no small set of frames where all the
    turning points line up. At 24 samples the linear error is under 2% of the
    amplitude, which at a couple of degrees is nothing.
    """
    ind = "    " * depth
    out = [f'{ind}<LinearAnimation loopValue="loop" fps="60" duration="{SWAY_FRAMES}" '
           f'name="Sway" id="{anim_id}">']
    for index, part in enumerate(parts):
        out.append(f'{ind}    <KeyedObject objectId="{nodes[part.gid]["sway"]}" id="{ids()}">')
        out.append(f'{ind}        <KeyedProperty propertyKey="15" id="{ids()}">')
        for i in range(SWAY_SAMPLES + 1):
            frame = round(SWAY_FRAMES * i / SWAY_SAMPLES)
            angle = sway_angle(part, index, parts, i / SWAY_SAMPLES)
            # interpolationType defaults to hold, which would step the sway
            out.append(f'{ind}            <KeyFrameDouble frame="{frame}" value="{angle:.6f}" '
                       f'interpolationType="linear" id="{ids()}"/>')
        out.append(f'{ind}        </KeyedProperty>')
        out.append(f'{ind}    </KeyedObject>')
    out.append(f'{ind}</LinearAnimation>')
    return out

# ---------- the sway ----------
SWAY_FRAMES = 300      # 5s at 60fps
SWAY_SAMPLES = 24      # keyframes per part per loop

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
SWAY_HARMONIC = 0.28      # weight of the 2x component, relative to the fundamental
SWAY_AMPLITUDE = 1.0      # global multiplier on every part's amplitude

# How the parts of one plant relate to each other in time.
#   "independent" -- each part carries its own phase. Reads as several plants in
#                    still air, each doing its own thing.
#   "wind"        -- one shared oscillation crossing the plant left to right,
#                    each part lagging by its tip's x-position. Reads as one
#                    plant in moving air.
# Switchable so the two can be compared in the preview:
#     python3 fern_generator.py --sway=wind
SWAY_MODE = "independent"
SWAY_WIND_LAG = 0.22      # phase lag in turns, across the full width of the plant
SWAY_WIND_HARMONIC = 0.17 # fixed offset of the harmonic, in wind mode

# Irrational-ish steps, so parts with no hand-tuned phase still spread out
# rather than landing on top of each other.
SWAY_PHASE_STEP = 0.37
SWAY_HARMONIC_STEP = 0.61

def sway_degrees(part):
    if part.gid in SWAY:
        return SWAY[part.gid][0]
    return SWAY_DEFAULT[part.kind]

def sway_phases(part, index, parts):
    """(fundamental phase, harmonic phase) in turns, per the current mode."""
    if SWAY_MODE == "wind":
        xs = [p.tip[0] for p in parts]
        span = (max(xs) - min(xs)) or 1
        lag = (part.tip[0] - min(xs)) / span * SWAY_WIND_LAG
        return lag, lag + SWAY_WIND_HARMONIC
    if part.gid in SWAY:
        _, phase, phase2 = SWAY[part.gid]
        return phase, phase2
    return (index * SWAY_PHASE_STEP) % 1.0, (index * SWAY_HARMONIC_STEP) % 1.0

def sway_angle(part, index, parts, t):
    """Rotation in radians at loop fraction t, for one part.

    A fundamental plus a quarter-weight second harmonic. Both are whole numbers
    of cycles per loop, so frame 0 and the last frame agree exactly and the loop
    is seamless. The harmonic is what stops several parts on one period from
    reading as a metronome, and it survives both phase modes.
    """
    amplitude = math.radians(sway_degrees(part)) * SWAY_AMPLITUDE
    phase, phase2 = sway_phases(part, index, parts)
    return (amplitude * math.sin(2*math.pi * (t + phase))
            + amplitude * SWAY_HARMONIC * math.sin(4*math.pi * (t + phase2)))

# ---------- the vitality droop ----------
DROOP_MAX_DEGREES = 25     # what a fully upright part gives up at vitality 0
NEAR_VERTICAL_DEGREES = 80 # above this, which way a part leans is an accident

# A fiddlehead is a young shoot, not a laden frond -- it gives less.
# A seed is 0: the engine has no vitality before the first completion, so
# stage 0 ignores it. Both droop poses then key the same rotation, which is what
# "key every blended property in every pose" asks for anyway.
DROOP_KIND_SCALE = {"frond": 1.0, "fiddlehead": 0.6, "seed": 0.0}

# Which way a near-vertical part falls. Above NEAR_VERTICAL_DEGREES the tip's
# x-offset is too small to mean anything -- frond-center leans right by 36px out
# of 743, so sign(dx) would flip on a trivial edit to the art. Declaring it
# makes the choice survive the art changing. +1 is right, -1 is left.
# Keyed by (stage, part) because the same part name recurs across stages with
# different geometry.
DROOP_DIRECTION = {
    (1, "fiddlehead-1"): -1,   # the sprout's single shoot, leaning left as drawn
    (3, "frond-center"): +1,   # the same art as stage 4, scaled
    (4, "frond-center"): +1,   # falls to the right; matches the art as drawn
    (5, "frond-center"): +1,
}

def droop_angle(part, n):
    """Rotation in radians at vitality 0, for one part of stage `n`.

    Derived from the art rather than hand-tuned, so it carries across stages: a
    part gives up `DROOP_MAX_DEGREES` scaled by how upright it already is and by
    what kind of thing it is, in the direction it already leans. A
    near-horizontal frond has little height to lose and droops least; the
    near-vertical centre one falls furthest. The sign is the side the tip is on,
    which turns the rotation into "outward and down" rather than "toward the
    middle" -- except for near-vertical parts, where it is declared in
    DROOP_DIRECTION instead.
    """
    dx, dy = part.tip[0] - BASE[0], part.tip[1] - BASE[1]
    elevation = math.degrees(math.atan2(-dy, abs(dx)))          # 0 = flat, 90 = straight up
    magnitude = math.radians(DROOP_MAX_DEGREES * elevation / 90) * DROOP_KIND_SCALE[part.kind]
    # A part that cannot droop has no direction to get wrong, so it is not made
    # to declare one.
    if magnitude == 0:
        return 0.0
    if elevation >= NEAR_VERTICAL_DEGREES:
        if (n, part.gid) not in DROOP_DIRECTION:
            raise ValueError(
                f"stage {n}: {part.gid} is near-vertical ({elevation:.1f} deg), so which way "
                f"it droops cannot be read off the art. Add ({n}, {part.gid!r}) to "
                f"DROOP_DIRECTION (+1 right, -1 left).")
        return DROOP_DIRECTION[(n, part.gid)] * magnitude
    return math.copysign(magnitude, dx)

def _keyed(object_id, property_key, keyframe, ids, ind):
    return [f'{ind}<KeyedObject objectId="{object_id}" id="{ids()}">',
            f'{ind}    <KeyedProperty propertyKey="{property_key}" id="{ids()}">',
            f'{ind}        {keyframe}',
            f'{ind}    </KeyedProperty>',
            f'{ind}</KeyedObject>']

def dry_fills(part):
    """[(path name, healthy colour)] for every fill in this part that fades.

    Driven by DRY_FILL membership rather than by path name, so stems, midribs
    and spores are left alone without anything having to list them.
    """
    return [(c.pid, c.fill) for c in part.children
            if getattr(c, "fill", None) in DRY_FILL]

def droop_pose(name, anim_id, n, parts, dry, nodes, paints, ids, depth=2):
    """One end of the droop blend: rotation on each part, and its fading fills.

    Both poses key *every* property on *every* part. A property keyed in one
    pose and missing from the other has nothing to mix toward, and blends by
    jumping rather than mixing.
    """
    ind = "    " * depth
    out = [f'{ind}<LinearAnimation fps="60" duration="60" name="{name}" id="{anim_id}">']
    for part in parts:
        angle = droop_angle(part, n) if dry else 0.0
        rotation = (f'<KeyFrameDouble frame="0" value="{angle:.6f}" '
                    f'interpolationType="linear" id="{ids()}"/>')
        out += _keyed(nodes[part.gid]["droop"], 15, rotation, ids, ind + "    ")
        for path_name, healthy in dry_fills(part):
            # propertyKey 37 on the SolidColor, and a KeyFrameColor to match it
            value = argb(DRY_FILL[healthy] if dry else healthy)
            colour = (f'<KeyFrameColor frame="0" value="{value}" '
                      f'interpolationType="linear" id="{ids()}"/>')
            out += _keyed(paints[path_name], 37, colour, ids, ind + "    ")
    out.append(f'{ind}</LinearAnimation>')
    return out

def still_pose(anim_id, parts, nodes, ids, depth=2):
    """The zero end of the sway blend: every sway node held at rest.

    Blending this against Sway scales the sway's amplitude. It has to key the
    same rotations Sway does, for the same reason the droop poses do.
    """
    ind = "    " * depth
    out = [f'{ind}<LinearAnimation fps="60" duration="60" name="Still" id="{anim_id}">']
    for part in parts:
        rotation = f'<KeyFrameDouble frame="0" value="0" interpolationType="linear" id="{ids()}"/>'
        out += _keyed(nodes[part.gid]["sway"], 15, rotation, ids, ind + "    ")
    out.append(f'{ind}</LinearAnimation>')
    return out

# ---------- converters ----------
# vitality is 0-1; a blend axis is 0-100. Two chains read the same property:
# the droop needs the full range, the sway only fades down to a floor.
#
# Each chain smooths first, then maps. Smoothing the raw 0-1 value means the
# shaping curve applies all the way through a transition, and keeps the range
# mapper as the one place the 0-1 -> 0-100 shaping lives.
SMOOTHING_SECONDS = 0.6   # how long a changed vitality takes to arrive
SWAY_FLOOR = 40           # blend weight at vitality 0: the sway never fully stops

# Stage 0 is the exception. There is no vitality before the first completion, so
# the seed must not react to it at all -- and a floor equal to the ceiling makes
# the range mapper a constant, which is vitality-independence without giving
# stage 0 a differently-shaped state machine from every other stage.
SEED_SWAY_FLOOR = 100

def converter_chain(name, ids, min_output, max_output, ease, group_id,
                    seconds=None, max_input=1):
    """A DataConverterGroup: smooth the incoming value, then remap its range.

    `ease` of None leaves the range mapper linear -- the roots axis is already
    shaped by where its poses sit on the blend, so easing it there as well would
    shape the same curve twice.
    """
    smoother_id, mapper_id, interpolator_id, ease_id = ids(), ids(), ids(), ids()
    seconds = SMOOTHING_SECONDS if seconds is None else seconds
    out = [
        f'    <DataConverterGroup name="{name}" id="{group_id}">',
        f'        <DataConverterGroupItem converterId="{smoother_id}"/>',
        f'        <DataConverterGroupItem converterId="{mapper_id}"/>',
        '    </DataConverterGroup>',
        '',
        f'    <DataConverterInterpolator duration="{seconds}" interpolationType="cubic"',
        f'                               name="{name} Smoothing" id="{smoother_id}">',
        f'        <CubicEaseInterpolator x1="0" y1="0" x2="0.58" y2="1" id="{interpolator_id}"/>',
        '    </DataConverterInterpolator>',
        '',
        f'    <DataConverterRangeMapper minInput="0" maxInput="{max_input}" '
        f'minOutput="{min_output}" maxOutput="{max_output}"',
        '                              clampLower="true" clampUpper="true"',
    ]
    if ease is None:
        out.append(f'                              name="{name} Range" id="{mapper_id}"/>')
        return out
    x1, y1, x2, y2 = ease
    out += [
        f'                              interpolationType="cubic" name="{name} Range" id="{mapper_id}">',
        f'        <CubicEaseInterpolator x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" id="{ease_id}"/>',
        '    </DataConverterRangeMapper>',
    ]
    return out

# Asymmetric on purpose: steep at the top of the range so a small drop from full
# vitality is visible immediately, flattening toward 0 so the fern settles into
# its wilt instead of slamming into it.
DROOP_EASE = (0.4, 0, 1, 1)
SWAY_EASE = (0.4, 0, 1, 1)

# The view model is shared by every stage artboard, declared once in its own
# file. Names are the host's surface: one `Fern` with one `vitality`, whichever
# stage is on screen.
# Client 9, not 0: stage_rml uses Ids(client=n) and stage 0 is the seed, so the
# data file would collide with it.
DATA_CLIENT = 9
VIEWMODEL_ID, VITALITY_ID, INSTANCE_ID = "9:2", "9:3", "9:4"
ROOTS_ID = "9:5"

def data_rml():
    return "\n".join([
        '<Rive version="1" kind="fragment">',
        f'    <ViewModel defaultInstanceId="{INSTANCE_ID}" name="Fern" id="{VIEWMODEL_ID}">',
        f'        <ViewModelPropertyNumber name="vitality" id="{VITALITY_ID}"/>',
        f'        <ViewModelPropertyNumber name="roots" id="{ROOTS_ID}"/>',
        f'        <ViewModelInstance exports="true" name="Default" id="{INSTANCE_ID}">',
        f'            <ViewModelInstanceNumber propertyValue="1" viewModelPropertyId="{VITALITY_ID}"/>',
        f'            <ViewModelInstanceNumber propertyValue="0" viewModelPropertyId="{ROOTS_ID}"/>',
        '        </ViewModelInstance>',
        '    </ViewModel>',
        '</Rive>',
        '',
    ])

# Artboards are laid out in a row on the editor's stage so they do not stack on
# the origin. The CLI ignores these; the editor does not.
STAGE_GUTTER = 120

def stage_rml(n, name):
    """One stage as its own artboard, in its own file.

    Each file gets its own id client, so ids cannot collide across the five even
    though they share one document and one namespace.
    """
    parts, back, front = stage_parts(n)
    ids = Ids(client=n)
    artboard_id, machine_id, style_id = ids(), ids(), ids()
    sway_layer_id, sway_blend_id, sway_bindable_id = ids(), ids(), ids()
    vitality_layer_id, droop_blend_id, droop_bindable_id = ids(), ids(), ids()
    sway_id, still_id, upright_id, drooped_id = ids(), ids(), ids(), ids()
    droop_group_id, sway_group_id = ids(), ids()
    leans = n in LEAN_THRESHOLD
    lean_layer_id, lean_blend_id, lean_bindable_id = ids(), ids(), ids()
    steady_id, leaning_id, lean_group_id = ids(), ids(), ids()
    nodes, paints = {}, {}
    plant_id = ids()
    body = []
    # RML draw order is the reverse of SVG's: the first Shape declared paints on
    # top. So the front soil goes first, the plant next, and whatever sits
    # behind the plant goes last.
    #
    # The soil sits *outside* the plant node rather than inside it, which is a
    # change from earlier. The stability lean rotates the plant node, and the
    # ground must not tilt with it -- a 5 degree tilt on the mound reads as the
    # whole world leaning, not the plant.
    if front:
        body += rml_item(front, (0, 0), ids, 2, paints)
    body.append(f'        <Node x="{BASE[0]}" y="{BASE[1]}" name="plant" id="{plant_id}">')
    for part in reversed(parts):
        body += part_node(part, ids, 3, nodes, paints)
    body.append('        </Node>')
    if back:
        body += rml_item(back, (0, 0), ids, 2, paints)

    artboard = f"Fern{name.capitalize()}"
    head = [
        '<Rive version="1" kind="fragment">',
        f'    <Artboard defaultStateMachineId="{machine_id}" viewModelId="{VIEWMODEL_ID}" '
        f'viewModelInstanceId="{INSTANCE_ID}" x="{n * (W + STAGE_GUTTER)}" y="0" '
        f'width="{W}" height="{W}" styleId="{style_id}" name="{artboard}" id="{artboard_id}">',
        f'        <LayoutComponentStyle name="Artboard Style" id="{style_id}"/>',
        '',
    ]
    tail = [
        '',
    ] + sway_animation(parts, nodes, ids, sway_id) + [
        '',
    ] + still_pose(still_id, parts, nodes, ids) + [
        '',
    ] + droop_pose("Upright", upright_id, n, parts, False, nodes, paints, ids) + [
        '',
    ] + droop_pose("Drooped", drooped_id, n, parts, True, nodes, paints, ids)
    if leans:
        tail += [''] + lean_pose('Steady', steady_id, 0.0, plant_id, ids)
        tail += [''] + lean_pose(
            'Leaning', leaning_id,
            LEAN_DIRECTION[n] * math.radians(LEAN_DEGREES), plant_id, ids)
    tail += [
        '',
        f'        <StateMachine name="Fern" id="{machine_id}">',
        '',
        '            <!-- the sway owns rotation on the inner *-sway nodes.',
        '                 vitality scales its amplitude between Still and Sway. -->',
        f'            <StateMachineLayer name="Sway" id="{sway_layer_id}">',
        '                <AnyState x="420" y="-120"/>',
        '                <ExitState x="620" y="-120"/>',
        '                <EntryState x="0" y="0">',
        f'                    <StateTransition stateToId="{sway_blend_id}"/>',
        '                </EntryState>',
        f'                <BlendState1DViewModel x="160" y="0" id="{sway_blend_id}">',
        f'                    <BindablePropertyNumber id="{sway_bindable_id}">',
        f'                        <DataBindContext sourcePathIds="{VIEWMODEL_ID}-{VITALITY_ID}" '
        f'propertyKey="636" converterId="{sway_group_id}"/>',
        '                    </BindablePropertyNumber>',
        f'                    <BlendAnimation1D animationId="{still_id}" value="0"/>',
        f'                    <BlendAnimation1D animationId="{sway_id}" value="100"/>',
        '                </BlendState1DViewModel>',
        '            </StateMachineLayer>',
        '',
        '            <!-- vitality owns rotation on the outer *-droop nodes,',
        '                 and the fills that fade -->',
        f'            <StateMachineLayer name="Vitality" id="{vitality_layer_id}">',
        '                <AnyState x="420" y="-120"/>',
        '                <ExitState x="620" y="-120"/>',
        '                <EntryState x="0" y="0">',
        f'                    <StateTransition stateToId="{droop_blend_id}"/>',
        '                </EntryState>',
        f'                <BlendState1DViewModel x="160" y="0" id="{droop_blend_id}">',
        f'                    <BindablePropertyNumber id="{droop_bindable_id}">',
        f'                        <DataBindContext sourcePathIds="{VIEWMODEL_ID}-{VITALITY_ID}" '
        f'propertyKey="636" converterId="{droop_group_id}"/>',
        '                    </BindablePropertyNumber>',
        '                    <!-- ascending value order: the runtime binary-searches these -->',
        f'                    <BlendAnimation1D animationId="{drooped_id}" value="0"/>',
        f'                    <BlendAnimation1D animationId="{upright_id}" value="100"/>',
        '                </BlendState1DViewModel>',
        '            </StateMachineLayer>',
    ]
    if leans:
        tail += [
            '',
            '            <!-- a plant taller than its roots leans. this layer owns',
            '                 rotation on the plant node; nothing else touches it. -->',
            f'            <StateMachineLayer name="Stability" id="{lean_layer_id}">',
            '                <AnyState x="420" y="-120"/>',
            '                <ExitState x="620" y="-120"/>',
            '                <EntryState x="0" y="0">',
            f'                    <StateTransition stateToId="{lean_blend_id}"/>',
            '                </EntryState>',
            f'                <BlendState1DViewModel x="160" y="0" id="{lean_blend_id}">',
            f'                    <BindablePropertyNumber id="{lean_bindable_id}">',
            f'                        <DataBindContext sourcePathIds="{VIEWMODEL_ID}-{ROOTS_ID}" '
            f'propertyKey="636" converterId="{lean_group_id}"/>',
            '                    </BindablePropertyNumber>',
            f'                    <BlendAnimation1D animationId="{leaning_id}" value="0"/>',
            f'                    <BlendAnimation1D animationId="{steady_id}" value="100"/>',
            '                </BlendState1DViewModel>',
            '            </StateMachineLayer>',
        ]
    tail += [
        '        </StateMachine>',
        '    </Artboard>',
        '',
    ] + converter_chain("Droop", ids, 0, 100, DROOP_EASE, droop_group_id) + [
        '',
    ] + converter_chain("Sway", ids, SEED_SWAY_FLOOR if n == 0 else SWAY_FLOOR,
                        100, SWAY_EASE, sway_group_id)
    if leans:
        # roots at the stage's threshold read as steady, roots at 0 as a full
        # lean. The mapper is linear: the threshold is the shaping.
        tail += [''] + converter_chain('Stability', ids, 0, 100, None, lean_group_id,
                                       seconds=ROOTS_SMOOTHING_SECONDS,
                                       max_input=LEAN_THRESHOLD[n])
    tail += [
        '</Rive>',
        '',
    ]
    # the shapes were emitted at depth 2; the wrapping plant Node sits at depth 2 too
    return "\n".join(head + body + tail)

# ---------- the stability lean ----------
# A plant taller than its roots leans. Below the stage's root threshold it tips
# over; at or above it, it stands up. Only the two stages tall enough for the
# lean to read carry it -- the seed and sprout have nothing to tip, and the
# bloom is the reward pose and should not look precarious.
LEAN_DEGREES = 5.0
LEAN_THRESHOLD = {3: 0.30, 4: 0.50}   # roots at or above this = steady

# Which way an under-rooted plant tips. There is nothing in the art to read this
# off -- the lean is about the roots, not the silhouette -- so it is declared
# rather than derived. +1 is to the right.
LEAN_DIRECTION = {3: +1, 4: +1}

def lean_pose(name, anim_id, angle, plant_id, ids, depth=2):
    """One end of the stability blend: rotation on the whole plant.

    Both poses key it, so the plant blends between leaning and upright rather
    than snapping when the roots cross the threshold.
    """
    ind = "    " * depth
    frame = (f'<KeyFrameDouble frame="0" value="{angle:.6f}" '
             f'interpolationType="linear" id="{ids()}"/>')
    return ([f'{ind}<LinearAnimation fps="60" duration="60" name="{name}" id="{anim_id}">']
            + _keyed(plant_id, 15, frame, ids, ind + "    ")
            + [f'{ind}</LinearAnimation>'])

# ---------- the roots artboard ----------
ROOTS_CLIENT = 6
ROOTS_HEIGHT = 520          # level 4 reaches y=455; the rest is breathing room
ROOTS_SMOOTHING_SECONDS = 1.2   # roots grow after a reflection; they do not snap

# Blend axis positions for the five poses. Uneven on purpose: the gap from bare
# soil to a first root should read as a bigger event than the gap between two
# established levels, and roots past 0.75 stay at level 4.
ROOTS_POSES = [(0, None), (15, 1), (30, 2), (50, 3), (75, 4)]

def roots_pose(name, anim_id, level, parts, groups, ids, depth=2):
    """One pose of the root blend: scaleX and scaleY on every root node.

    Every node is keyed in every pose, including the ones that are 0 there. A
    node keyed in one pose and absent from another has nothing to mix toward,
    so it would pop into place instead of growing.
    """
    ind = "    " * depth
    out = [f'{ind}<LinearAnimation fps="60" duration="60" name="{name}" id="{anim_id}">']
    for part in parts:
        value = root_scale(part, level)
        for property_key in (16, 17):        # scaleX, scaleY
            frame = (f'<KeyFrameDouble frame="0" value="{value:.4f}" '
                     f'interpolationType="linear" id="{ids()}"/>')
            out += _keyed(groups[part.gid], property_key, frame, ids, ind + "    ")
    out.append(f'{ind}</LinearAnimation>')
    return out

def roots_rml():
    """The root system as its own artboard.

    Separate from the stage artboards because a view model bind inside a
    NestedArtboard does not resolve -- measured, see NOTES.md -- so the roots
    cannot be nested into each stage and driven by data. The host stacks this
    artboard under a stage artboard and binds both to the same view model
    instance.
    """
    ids = Ids(client=ROOTS_CLIENT)
    artboard_id, machine_id, style_id = ids(), ids(), ids()
    layer_id, blend_id, bindable_id, group_id = ids(), ids(), ids(), ids()
    pose_ids = [ids() for _ in ROOTS_POSES]

    forest = root_forest(build_root_tree())
    parts = root_parts(forest)
    for part in parts:
        part.scale = root_scale(part, 4)   # what shows if anything renders it unbound

    groups = {}
    body = rml_item(forest, (0, 0), ids, 2, {}, groups)

    head = [
        '<Rive version="1" kind="fragment">',
        f'    <Artboard defaultStateMachineId="{machine_id}" viewModelId="{VIEWMODEL_ID}" '
        f'viewModelInstanceId="{INSTANCE_ID}" x="0" y="{W + 240}" '
        f'width="{W}" height="{ROOTS_HEIGHT}" styleId="{style_id}" name="FernRoots" id="{artboard_id}">',
        f'        <LayoutComponentStyle name="Artboard Style" id="{style_id}"/>',
        '',
    ]
    tail = ['']
    for (_, level), anim_id in zip(ROOTS_POSES, pose_ids):
        name = "RootsNone" if level is None else f"RootsLevel{level}"
        tail += roots_pose(name, anim_id, level, parts, groups, ids) + ['']
    tail += [
        f'        <StateMachine name="Fern" id="{machine_id}">',
        f'            <StateMachineLayer name="Roots" id="{layer_id}">',
        '                <AnyState x="420" y="-120"/>',
        '                <ExitState x="620" y="-120"/>',
        '                <EntryState x="0" y="0">',
        f'                    <StateTransition stateToId="{blend_id}"/>',
        '                </EntryState>',
        f'                <BlendState1DViewModel x="160" y="0" id="{blend_id}">',
        f'                    <BindablePropertyNumber id="{bindable_id}">',
        f'                        <DataBindContext sourcePathIds="{VIEWMODEL_ID}-{ROOTS_ID}" '
        f'propertyKey="636" converterId="{group_id}"/>',
        '                    </BindablePropertyNumber>',
        '                    <!-- ascending value order: the runtime binary-searches these -->',
    ]
    for (value, _), anim_id in zip(ROOTS_POSES, pose_ids):
        tail.append(f'                    <BlendAnimation1D animationId="{anim_id}" value="{value}"/>')
    tail += [
        '                </BlendState1DViewModel>',
        '            </StateMachineLayer>',
        '        </StateMachine>',
        '    </Artboard>',
        '',
    ] + converter_chain("Roots", ids, 0, 100, None, group_id,
                        seconds=ROOTS_SMOOTHING_SECONDS) + [
        '</Rive>',
        '',
    ]
    return "\n".join(head + body + tail)

STAGES = {0: "seed", 1: "sprout", 2: "seedling", 3: "young", 4: "mature", 5: "bloom"}

if __name__ == "__main__":
    import sys
    for arg in sys.argv[1:]:
        if arg.startswith("--sway="):
            SWAY_MODE = arg.split("=", 1)[1]
            if SWAY_MODE not in ("independent", "wind"):
                raise SystemExit(f"--sway must be independent or wind, not {SWAY_MODE!r}")
        elif arg.startswith("--amplitude="):
            SWAY_AMPLITUDE = float(arg.split("=", 1)[1])
        else:
            raise SystemExit(f"unknown argument {arg!r}")

    out = os.path.dirname(os.path.abspath(__file__))
    for n, name in STAGES.items():
        open(f"{out}/fern-stage-{n}-{name}.svg", "w").write(svg(stage(n)))
    tree = build_root_tree()
    for lv in ROOT_LEVELS:
        open(f"{out}/fern-roots-{lv}.svg", "w").write(svg(roots(lv, tree)))
    open(f"{out}/fern-data.rml", "w").write(data_rml())
    open(f"{out}/fern-roots.rml", "w").write(roots_rml())
    for n, name in STAGES.items():
        open(f"{out}/fern-stage-{n}-{name}.rml", "w").write(stage_rml(n, name))
    print(f"written to {out}  (sway={SWAY_MODE}, amplitude={SWAY_AMPLITUDE})")
