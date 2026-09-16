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
W = 1024; GROUND = 900; BASE = (512, GROUND - 18)

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
    def __init__(self, gid, children=()):
        self.gid, self.children = gid, list(children)

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
    return Group(fid, parts)

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
    parts.append(Path(f"{fid}-coil", [stem], fill=(fill if back else "#5E9150"),
                      stroke=OUTLINE, stroke_width=2.4))
    return Group(fid, parts)

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

def stage(n):
    """The drawables for one stage, in SVG order (first drawn = furthest back)."""
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
    mound = {1: 70, 2: 90, 3: 105}.get(n, 125)
    return [Group("plant", parts), base_mound(mound)]

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

def roots(level, tree):
    """one group per primary root (with its branches) so each can get its own bone chain"""
    s, gmax, nprim = ROOT_LEVELS[level]
    groups = []
    for r0 in tree[:nprim]:
        contours = {1: [], 2: [], 3: []}
        def walk(r, origin):
            if r.gen > gmax: return
            pts = r.pts(origin, s)
            contours[r.gen].append(tapered(pts, r.width * (0.75 + 0.25*s), 1.4))
            lens = cumlen(pts)
            for c in r.children:
                o, _ = at_frac(pts, lens, c.frac)
                walk(c, o)
        walk(r0, (512, 2))
        body = []
        for gen, name in ((3, "fine"), (2, "branches"), (1, "main")):
            if contours[gen]:
                body.append(Path(f"{r0.rid}-{name}", contours[gen], fill=ROOT, stroke=ROOT_OUTLINE,
                                 stroke_width=(2.2 if gen == 1 else 1.8)))
        groups.append(Group(r0.rid, body))
    return [Group("roots", groups)]

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

def svg_item(item):
    if isinstance(item, Group):
        return f'<g id="{item.gid}">' + "".join(svg_item(c) for c in item.children) + "</g>"
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

def rml_paint(item, ids, indent):
    """Fill first, then Stroke: within a Shape the later paint draws on top,
    which is the order SVG paints them in."""
    out = []
    if item.fill:
        out.append(f'{indent}<Fill name="Fill" id="{ids()}">')
        out.append(f'{indent}    <SolidColor colorValue="{argb(item.fill)}" name="Color" id="{ids()}"/>')
        out.append(f'{indent}</Fill>')
    stroke = getattr(item, "stroke", None)
    if stroke:
        cap = f' cap="{item.cap}"' if item.cap else ""
        out.append(f'{indent}<Stroke thickness="{item.stroke_width}" join="{item.join}"{cap} '
                   f'name="Stroke" id="{ids()}">')
        out.append(f'{indent}    <SolidColor colorValue="{argb(stroke)}" name="Color" id="{ids()}"/>')
        out.append(f'{indent}</Stroke>')
    return out

def rml_item(item, origin, ids, depth):
    ind = "    " * depth
    if isinstance(item, Group):
        out = [f'{ind}<Node name="{item.gid}" id="{ids()}">']
        # draw order is reversed from SVG: the first Shape declared paints on top
        for child in reversed(item.children):
            out += rml_item(child, origin, ids, depth + 1)
        out.append(f'{ind}</Node>')
        return out
    if isinstance(item, Dots):
        out = [f'{ind}<Shape name="{item.pid}" id="{ids()}">']
        for d in item.dots:
            out.append(f'{ind}    <Ellipse x="{d.cx - origin[0]:.2f}" y="{d.cy - origin[1]:.2f}" '
                       f'width="{2*d.rx:.2f}" height="{2*d.ry:.2f}" name="Dot" id="{ids()}"/>')
        out += rml_paint(item, ids, ind + "    ")
        out.append(f'{ind}</Shape>')
        return out
    out = [f'{ind}<Shape name="{item.pid}" id="{ids()}">']
    for c in item.contours:
        closed = ' isClosed="true"' if c.closed else ""
        out.append(f'{ind}    <PointsPath{closed} name="Path" id="{ids()}">')
        out += rml_vertices(c, origin, ids, ind + "        ")
        out.append(f'{ind}    </PointsPath>')
    out += rml_paint(item, ids, ind + "    ")
    out.append(f'{ind}</Shape>')
    return out

def frond_node(group, ids, depth, nodes):
    """A frond gets two nested transforms, both pivoted on the shared base point.

    The outer one carries the vitality droop, the inner the sway loop. Keeping
    them separate means each rotation has exactly one owner, so the two
    timelines compose instead of overwriting one another. `nodes` collects the
    two ids so the animations can key them.
    """
    ind = "    " * depth
    droop_id, sway_id = ids(), ids()
    nodes[group.gid] = {"droop": droop_id, "sway": sway_id}
    out = [f'{ind}<Node x="{BASE[0]}" y="{BASE[1]}" name="{group.gid}-droop" id="{droop_id}">',
           f'{ind}    <Node name="{group.gid}-sway" id="{sway_id}">']
    for child in reversed(group.children):
        out += rml_item(child, BASE, ids, depth + 2)
    out += [f'{ind}    </Node>', f'{ind}</Node>']
    return out

# ---------- the sway ----------
SWAY_FRAMES = 300      # 5s at 60fps
SWAY_SAMPLES = 24      # keyframes per frond per loop

SWAY = {  # frond: (degrees, phase in turns, second-harmonic phase in turns)
    "frond-back-left":  (1.7, 0.00, 0.31),
    "frond-back-right": (1.5, 0.37, 0.74),
    "frond-left":       (2.6, 0.62, 0.12),
    "frond-right":      (2.4, 0.18, 0.55),
    "frond-center":     (1.9, 0.81, 0.93),
}
SWAY_HARMONIC = 0.28   # weight of the 2x component, relative to the fundamental

def sway_angle(fid, t):
    """Rotation in radians at loop fraction t, for one frond.

    A fundamental plus a quarter-weight second harmonic, each with its own phase
    per frond. Both are whole numbers of cycles per loop, so frame 0 and the
    last frame agree exactly and the loop is seamless. The harmonic is what
    stops five fronds on one period from reading as a metronome.
    """
    degrees, phase, phase2 = SWAY[fid]
    amplitude = math.radians(degrees)
    return (amplitude * math.sin(2*math.pi * (t + phase))
            + amplitude * SWAY_HARMONIC * math.sin(4*math.pi * (t + phase2)))

def sway_animation(nodes, ids, anim_id, depth=2):
    """Key rotation (propertyKey 15, radians) on every frond's inner sway node.

    The curve is sampled rather than keyed at its extremes: the two components
    have different phases, so there is no small set of frames where all the
    turning points line up. At 24 samples the linear error is under 1% of the
    amplitude, which at a couple of degrees is nothing.
    """
    ind = "    " * depth
    out = [f'{ind}<LinearAnimation loopValue="loop" fps="60" duration="{SWAY_FRAMES}" '
           f'name="Sway" id="{anim_id}">']
    for fid in MATURE_ORDER:
        out.append(f'{ind}    <KeyedObject objectId="{nodes[fid]["sway"]}" id="{ids()}">')
        out.append(f'{ind}        <KeyedProperty propertyKey="15" id="{ids()}">')
        for i in range(SWAY_SAMPLES + 1):
            frame = round(SWAY_FRAMES * i / SWAY_SAMPLES)
            angle = sway_angle(fid, i / SWAY_SAMPLES)
            # interpolationType defaults to hold, which would step the sway
            out.append(f'{ind}            <KeyFrameDouble frame="{frame}" value="{angle:.6f}" '
                       f'interpolationType="linear" id="{ids()}"/>')
        out.append(f'{ind}        </KeyedProperty>')
        out.append(f'{ind}    </KeyedObject>')
    out.append(f'{ind}</LinearAnimation>')
    return out

# ---------- the vitality droop ----------
DROOP_MAX_DEGREES = 25   # what a fully upright frond gives up at vitality 0

def droop_angle(fid):
    """Rotation in radians at vitality 0, for one frond.

    Derived from the art rather than hand-tuned per frond, so it carries to the
    other stages: a frond gives up `DROOP_MAX_DEGREES` scaled by how upright it
    already is, in the direction it already leans. A near-horizontal frond has
    little height to lose and droops least; the near-vertical centre one falls
    furthest. The sign is the side the tip is on, which turns the rotation into
    "outward and down" rather than "toward the middle".
    """
    tip = FRONDS[fid][2]
    dx, dy = tip[0] - BASE[0], tip[1] - BASE[1]
    elevation = math.degrees(math.atan2(-dy, abs(dx)))          # 0 = flat, 90 = straight up
    return math.copysign(math.radians(DROOP_MAX_DEGREES * elevation / 90), dx)

def pose_animation(name, anim_id, angle_of, nodes, ids, depth=2):
    """One end of the droop blend: a single rotation keyframe per frond.

    Both poses key *every* frond. A property keyed in one pose and missing from
    the other has nothing to mix toward, and blends by jumping.
    """
    ind = "    " * depth
    out = [f'{ind}<LinearAnimation fps="60" duration="60" name="{name}" id="{anim_id}">']
    for fid in MATURE_ORDER:
        out.append(f'{ind}    <KeyedObject objectId="{nodes[fid]["droop"]}" id="{ids()}">')
        out.append(f'{ind}        <KeyedProperty propertyKey="15" id="{ids()}">')
        out.append(f'{ind}            <KeyFrameDouble frame="0" value="{angle_of(fid):.6f}" '
                   f'interpolationType="linear" id="{ids()}"/>')
        out.append(f'{ind}        </KeyedProperty>')
        out.append(f'{ind}    </KeyedObject>')
    out.append(f'{ind}</LinearAnimation>')
    return out

def mature_rml():
    ids = Ids()
    artboard_id, machine_id, layer_id, anim_id, state_id = ids(), ids(), ids(), ids(), ids()
    style_id = ids()
    vitality_layer_id, blend_id, bindable_id = ids(), ids(), ids()
    upright_id, drooped_id = ids(), ids()
    converter_id, interpolator_id = ids(), ids()
    viewmodel_id, vitality_id, instance_id = ids(), ids(), ids()
    nodes = {}
    body = []
    # reversed: base is painted last in SVG, so it is declared first here
    body += rml_item(base_mound(125), (0, 0), ids, 2)
    for fid in reversed(MATURE_ORDER):
        body += frond_node(frond_by_id(fid), ids, 2, nodes)

    head = [
        '<Rive version="1" kind="fragment">',
        f'    <Artboard defaultStateMachineId="{machine_id}" viewModelId="{viewmodel_id}" '
        f'viewModelInstanceId="{instance_id}" width="{W}" height="{W}" '
        f'styleId="{style_id}" name="FernMature" id="{artboard_id}">',
        f'        <LayoutComponentStyle name="Artboard Style" id="{style_id}"/>',
        '',
        f'        <Node name="plant" id="{ids()}">',
    ]
    tail = [
        '        </Node>',
        '',
    ] + sway_animation(nodes, ids, anim_id) + [
        '',
    ] + pose_animation("Upright", upright_id, lambda fid: 0.0, nodes, ids) + [
        '',
    ] + pose_animation("Drooped", drooped_id, droop_angle, nodes, ids) + [
        '',
        f'        <StateMachine name="State Machine 1" id="{machine_id}">',
        '',
        '            <!-- the sway owns rotation on the inner *-sway nodes -->',
        f'            <StateMachineLayer name="Sway" id="{layer_id}">',
        '                <AnyState x="420" y="-120"/>',
        '                <ExitState x="620" y="-120"/>',
        '                <EntryState x="0" y="0">',
        f'                    <StateTransition stateToId="{state_id}"/>',
        '                </EntryState>',
        f'                <AnimationState x="160" y="0" animationId="{anim_id}" id="{state_id}"/>',
        '            </StateMachineLayer>',
        '',
        '            <!-- vitality owns rotation on the outer *-droop nodes -->',
        f'            <StateMachineLayer name="Vitality" id="{vitality_layer_id}">',
        '                <AnyState x="420" y="-120"/>',
        '                <ExitState x="620" y="-120"/>',
        '                <EntryState x="0" y="0">',
        f'                    <StateTransition stateToId="{blend_id}"/>',
        '                </EntryState>',
        f'                <BlendState1DViewModel x="160" y="0" id="{blend_id}">',
        f'                    <BindablePropertyNumber id="{bindable_id}">',
        f'                        <DataBindContext sourcePathIds="{viewmodel_id}-{vitality_id}" '
        f'propertyKey="636" converterId="{converter_id}"/>',
        '                    </BindablePropertyNumber>',
        '                    <!-- ascending value order: the runtime binary-searches these -->',
        f'                    <BlendAnimation1D animationId="{drooped_id}" value="0"/>',
        f'                    <BlendAnimation1D animationId="{upright_id}" value="100"/>',
        '                </BlendState1DViewModel>',
        '            </StateMachineLayer>',
        '        </StateMachine>',
        '    </Artboard>',
        '',
        '    <!-- vitality is 0-1; a blend axis is 0-100. the easing lives here, on the',
        '         value feeding the blend, rather than on the two poses. -->',
        '    <DataConverterRangeMapper minInput="0" maxInput="1" minOutput="0" maxOutput="100"',
        '                              clampLower="true" clampUpper="true"',
        f'                              interpolationType="cubic" name="VitalityToBlend" id="{converter_id}">',
        f'        <CubicEaseInterpolator x1="0.42" y1="0" x2="0.58" y2="1" id="{interpolator_id}"/>',
        '    </DataConverterRangeMapper>',
        '',
        f'    <ViewModel defaultInstanceId="{instance_id}" name="Fern" id="{viewmodel_id}">',
        f'        <ViewModelPropertyNumber name="vitality" id="{vitality_id}"/>',
        f'        <ViewModelInstance exports="true" name="Default" id="{instance_id}">',
        f'            <ViewModelInstanceNumber propertyValue="1" viewModelPropertyId="{vitality_id}"/>',
        '        </ViewModelInstance>',
        '    </ViewModel>',
        '</Rive>',
        '',
    ]
    # the shapes were emitted at depth 2; the wrapping plant Node sits at depth 2 too
    return "\n".join(head + ["    " + line if line else line for line in body] + tail)

STAGES = {1: "sprout", 2: "seedling", 3: "young", 4: "mature", 5: "bloom"}

if __name__ == "__main__":
    out = os.path.dirname(os.path.abspath(__file__))
    for n, name in STAGES.items():
        open(f"{out}/fern-stage-{n}-{name}.svg", "w").write(svg(stage(n)))
    tree = build_root_tree()
    for lv in ROOT_LEVELS:
        open(f"{out}/fern-roots-{lv}.svg", "w").write(svg(roots(lv, tree)))
    open(f"{out}/fern-mature.rml", "w").write(mature_rml())
    print("written to", out)
