"""The shared geometry model: primitives, drawables, and the helpers that build them.

Every plant generator builds its art out of these, and both writers (svg.py and
rml.py) read them, so the two outputs can never describe different plants.

Plant canvases are 1024x1024 with the ground line at y=GROUND and the plant's
base at BASE. Root canvases put their ground line at y=0, so a plant canvas
stacks directly on top of a root canvas and the ground lines meet.
"""
import math

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
    """A named group of drawables.

    `tip` and `kind` are set on the parts that animate — a frond, a fiddlehead,
    a branch — and are what the droop and the sway read instead of a lookup
    table, so both work for any stage without knowing which one it is.

    `pivot` is the point a part rotates about, in canvas coordinates. None means
    the plant's base, which is right for anything that grows out of the ground
    (every fern part). A branch pivots where it leaves the trunk instead.
    """
    def __init__(self, gid, children=(), tip=None, kind=None, origin=None, scale=None,
                 meta=None, pivot=None):
        self.gid, self.children = gid, list(children)
        self.tip, self.kind = tip, kind
        self.pivot = pivot
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

