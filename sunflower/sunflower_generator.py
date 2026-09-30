"""Taproot sunflower generator — layered, animation-ready SVGs and RML.

The third plant on ../plantgen, after the fern and the oak. See
../fern/NOTES.md for the conventions and traps, ../oak/NOTES.md for what the
tree added (pivots, nested parts, twins), and NOTES.md here for the sunflower.

What the sunflower is for, visually: the clearest thirst of any plant. A
healthy sunflower stands straight and faces you; a thirsty one bends at the
middle of its stem and hangs its head. So its stem is two parts -- the upper
one nested in the lower, pivoting where they meet -- and its head is a third,
pivoting at the neck, with a much larger droop than anything else in the
garden.
"""
import math, random, os, sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from plantgen.geometry import (BASE, GROUND, Contour, Dot, Path, Dots, Group,
                               quad_to_cubic, sample_cubic, cumlen, at_frac, tapered)
from plantgen.ground import ROOT_OUTLINE, base_mound, seed_bed
from plantgen.roots import Root
from plantgen.species import Species, main

# ---------- palette ----------
# Greens: a touch yellower than the fern's, so the sunflower reads as a sunny
# plant even before it flowers. Colour arrives with the flower -- the bloom is
# the reward, and until then the garden stays green.
OUTLINE = "#2F4A2C"
LEAF = "#74A553"; LEAF_BACK = "#55853F"
VEIN = "#557F3E"
STEM = "#5E8F45"
COTYLEDON = "#86B060"
BRACT = "#4F8039"
PETAL = "#F2BE3A"; PETAL_BACK = "#DB982B"
DISC = "#5A3A22"; DISC_RING = "#7E5530"; DISC_SEED = "#3A2415"; DISC_LIGHT = "#A0703D"
HEAD_OUTLINE = ROOT_OUTLINE

# the thirsty end: greens toward grey-green like the other plants, petals
# toward a dull straw -- a wilting flower loses its shine, it does not brown
LEAF_DRY = "#A0A985"; LEAF_BACK_DRY = "#7C8768"; STEM_DRY = "#8A957A"
COTYLEDON_DRY = "#AEB595"; BRACT_DRY = "#737F62"
PETAL_DRY = "#D2BD80"; PETAL_BACK_DRY = "#BC9E66"

DRY_FILL = {LEAF: LEAF_DRY, LEAF_BACK: LEAF_BACK_DRY, STEM: STEM_DRY,
            COTYLEDON: COTYLEDON_DRY, BRACT: BRACT_DRY,
            PETAL: PETAL_DRY, PETAL_BACK: PETAL_BACK_DRY}

# the seed: charcoal with pale stripes, the one everybody recognises
HULL = "#443B35"; HULL_STRIPE = "#D9D1C1"; HULL_LIGHT = "#6B6058"

LEAF_STROKE = 2.4
# Stems use the oak's two-pass drawing (outline pass under fill pass) so the
# two stem parts and the neck merge into one stem where they meet.
STEM_STROKE = 4.8
K = 0.5523   # cubic handle length for a circular quarter

def frame(x, y, ang, bend=0.0, L=1.0):
    ca, sa = math.cos(ang), math.sin(ang)
    def P(u, v):
        v = v + bend * L * (u / L) ** 2
        return (x + u*ca - v*sa, y + u*sa + v*ca)
    return P

def circle(cx, cy, r, ry=None):
    ry = r if ry is None else ry
    return Contour([
        ((cx + r, cy), (cx + r, cy - ry*K), (cx + r, cy + ry*K)),
        ((cx, cy + ry), (cx + r*K, cy + ry), (cx - r*K, cy + ry)),
        ((cx - r, cy), (cx - r, cy + ry*K), (cx - r, cy - ry*K)),
        ((cx, cy - ry), (cx - r*K, cy - ry), (cx + r*K, cy - ry)),
    ], closed=True)

def curve(p0, c1, c2, p3, n=14):
    return sample_cubic(p0, c1, c2, p3, n)

def point_on(pts, s):
    return at_frac(pts, cumlen(pts), s)

# ---------- the leaf ----------
def heart_leaf(x, y, ang, L, W, petiole=0.28, bend=0.0):
    """A sunflower leaf: a long stalk, then a broad heart with a pointed tip.

    Built in a leaf frame (u along, v across; W is the half-width). The two
    rounded lobes at the base sit either side of where the stalk joins, a
    little behind it, which is the shape's whole character. Returns
    (blade, stalk, veins).
    """
    P = frame(x, y, ang, bend, L)
    u0 = petiole * L
    B = L - u0
    s = u0 + 0.07 * B                      # the sinus the stalk runs into
    nodes = [
        ((s, 0), (u0 + 0.02*B, 0.12*W), (u0 + 0.02*B, -0.12*W)),
        ((u0 - 0.03*B, -0.52*W), (u0 - 0.03*B, -0.22*W), (u0 - 0.03*B, -0.88*W)),
        ((u0 + 0.30*B, -W), (u0 + 0.05*B, -W), (u0 + 0.62*B, -0.97*W)),
        ((L, 0), (u0 + 0.86*B, -0.20*W), (u0 + 0.86*B, 0.20*W)),
        ((u0 + 0.30*B, W), (u0 + 0.62*B, 0.97*W), (u0 + 0.05*B, W)),
        ((u0 - 0.03*B, 0.52*W), (u0 - 0.03*B, 0.88*W), (u0 - 0.03*B, 0.22*W)),
    ]
    blade = Contour([(P(*p), P(*i), P(*o)) for p, i, o in nodes], closed=True)
    stalk_pts = [P(u0 * k / 6 + 0.07 * B * k / 6, 0) for k in range(7)]
    stalk = tapered(stalk_pts, max(W * 0.16, 5), max(W * 0.10, 3.5), round_end=False)
    veins = []
    for side in (0, -1, 1):
        end = (u0 + 0.84*B, 0) if side == 0 else (u0 + 0.46*B, side * 0.66*W)
        mid = (u0 + 0.45*B, 0) if side == 0 else (u0 + 0.16*B, side * 0.46*W)
        c1, c2 = quad_to_cubic(P(s, 0), P(*mid), P(*end))
        veins.append(Contour([(P(s, 0), None, c1), (P(*end), c2, None)], closed=False))
    return blade, stalk, veins

def leaf_part(gid, x, y, deg, L, W, back=False, droop=0.10, petiole=0.28):
    """One leaf as its own part, pivoting where its stalk leaves the stem.

    `droop` arches the leaf downward whichever side it points to, as a big
    sunflower leaf does under its own weight.
    """
    a = math.radians(deg)
    bend = droop * (1 if math.cos(a) >= 0 else -1)
    blade, stalk, veins = heart_leaf(x, y, a, L, W, petiole, bend)
    fill = LEAF_BACK if back else LEAF
    tipP = frame(x, y, a, bend, L)(L, 0)
    return Group(gid, [
        Path(f"{gid}-stalk", [stalk], fill=fill, stroke=OUTLINE, stroke_width=LEAF_STROKE),
        Path(f"{gid}-blade", [blade], fill=fill, stroke=OUTLINE, stroke_width=LEAF_STROKE),
        Path(f"{gid}-veins", veins, stroke=VEIN, stroke_width=1.8, cap="round"),
    ], tip=tipP, kind="leaf", pivot=(x, y))

def cotyledon(x, y, ang, L, W):
    """A seed leaf: a plain, smooth oval, paler than the true leaves."""
    P = frame(x, y, ang)
    return Contour([
        (P(0, 0), P(0.05*L, 0.30*W), P(0.05*L, -0.30*W)),
        (P(0.45*L, -W), P(0.18*L, -W), P(0.78*L, -W)),
        (P(L, 0), P(L, -0.55*W), P(L, 0.55*W)),
        (P(0.45*L, W), P(0.78*L, W), P(0.18*L, W)),
    ], closed=True)

# ---------- the seed ----------
def seed_shapes(cx, cy, ang, L, W):
    """A striped sunflower seed: a teardrop with pale stripes along its length.

    `ang` points from the round end to the pointed end. Returns (body, stripes,
    shine) for the caller to paint.
    """
    P = frame(cx, cy, ang)
    hl, hw = L / 2, W / 2
    body = Contour([
        (P(-hl, 0), P(-hl, hw*K), P(-hl, -hw*K)),
        (P(-hl*0.2, -hw), P(-hl*0.2 - hl*0.8*K, -hw), P(hl*0.35, -hw)),
        (P(hl, 0), P(hl*0.92, -hw*0.22), P(hl*0.92, hw*0.22)),
        (P(-hl*0.2, hw), P(hl*0.35, hw), P(-hl*0.2 - hl*0.8*K, hw)),
    ], closed=True)
    stripes = []
    for v, w in ((-0.52, 0.16), (0.0, 0.20), (0.52, 0.16)):
        a0, a1 = P(-hl*0.70, hw*v*0.85), P(hl*0.78, hw*v*0.35)
        m = P(-hl*0.1, hw*(v*1.05))
        top_c1, top_c2 = quad_to_cubic(a0, (m[0], m[1]), a1)
        # a thin lens: out along one side, back along the other
        mo = P(-hl*0.1, hw*(v*1.05 + w))
        bot_c1, bot_c2 = quad_to_cubic(a1, (mo[0], mo[1]), a0)
        stripes.append(Contour([(a0, bot_c2, top_c1), (a1, top_c2, bot_c1)], closed=True))
    shine = Dot(*P(-hl*0.35, -hw*0.45), L*0.07, W*0.08)
    return body, stripes, shine

def seed_paths(pid, seeds):
    bodies = [b for b, _, _ in seeds]
    return [
        Path(f"{pid}-hull", bodies, fill=HULL),
        Path(f"{pid}-stripes", [s for _, st, _ in seeds for s in st], fill=HULL_STRIPE),
        Dots(f"{pid}-shine", [sh for _, _, sh in seeds], HULL_LIGHT),
        Path(f"{pid}-outline", bodies, stroke=ROOT_OUTLINE, stroke_width=2.6),
    ]

SEED_CENTRE = (512, GROUND - 36)

def seed_stage():
    back, front = seed_bed()
    seed = seed_shapes(*SEED_CENTRE, math.radians(-24), 80, 42)
    tip = (SEED_CENTRE[0] + 36, SEED_CENTRE[1] - 16)
    return back, Group("seed", seed_paths("seed", [seed]), tip=tip, kind="seed"), front

# ---------- stems ----------
def stem_line(pid, contours, joints=()):
    """The outline pass: outline colour, filled and thickly stroked. Joint
    discs are their own shape -- inside one path, a disc wound the other way
    from the stem would cut a hole where they overlap."""
    out = [Path(f"{pid}-line", contours, fill=OUTLINE, stroke=OUTLINE, stroke_width=STEM_STROKE)]
    if joints:
        out.append(Dots(f"{pid}-joint-line", [Dot(x, y, r + STEM_STROKE / 2) for (x, y), r in joints], OUTLINE))
    return out

def stem_fill(pid, contours, joints=()):
    out = [Path(f"{pid}-fill", contours, fill=STEM)]
    if joints:
        out.append(Dots(f"{pid}-joint", [Dot(x, y, r) for (x, y), r in joints], STEM))
    return out

# ---------- stage 1: the sprout ----------
def sprout():
    """A pale shoot with two seed leaves, one still wearing the seed's hull."""
    pts = curve(BASE, (516, 830), (500, 760), (508, 700), 16)
    top = pts[-1]
    stem = Path("stem-shape", [tapered(pts, 12, 7)], fill=STEM, stroke=OUTLINE,
                stroke_width=LEAF_STROKE)
    left = Group("cotyledon-left", [
        Path("cotyledon-left-blade", [cotyledon(*top, math.radians(-160), 74, 22)],
             fill=COTYLEDON, stroke=OUTLINE, stroke_width=LEAF_STROKE),
    ], tip=(top[0] - 70, top[1] - 24), kind="leaf", pivot=top)
    a = math.radians(-24)
    tipR = (top[0] + 70 * math.cos(a), top[1] + 70 * math.sin(a))
    hull = seed_shapes(tipR[0] - 2, tipR[1] + 1, math.radians(150), 46, 26)
    right = Group("cotyledon-right", [
        Path("cotyledon-right-blade", [cotyledon(*top, a, 70, 21)],
             fill=COTYLEDON, stroke=OUTLINE, stroke_width=LEAF_STROKE),
    ] + seed_paths("hull", [hull]), tip=tipR, kind="leaf", pivot=top)
    return [Group("stem", [stem, left, right], tip=top, kind="stem")]

# ---------- stage 2: the seedling ----------
def seedling():
    """Seed leaves low down, two pairs of true leaves, and a tip still folded."""
    pts = curve(BASE, (500, 800), (524, 690), (512, 560), 18)
    top = pts[-1]
    stem = Path("stem-shape", [tapered(pts, 15, 7)], fill=STEM, stroke=OUTLINE,
                stroke_width=LEAF_STROKE)
    parts = []
    (cx, cy), _ = point_on(pts, 0.30)
    for side, deg, L, W in (("left", -170, 58, 17), ("right", -12, 56, 16)):
        a = math.radians(deg)
        parts.append(Group(f"cotyledon-{side}", [
            Path(f"cotyledon-{side}-blade", [cotyledon(cx, cy, a, L, W)],
                 fill=COTYLEDON, stroke=OUTLINE, stroke_width=LEAF_STROKE),
        ], tip=(cx + L * math.cos(a), cy + L * math.sin(a)), kind="leaf", pivot=(cx, cy)))
    for k, (s, deg, L, W) in enumerate(((0.62, -150, 118, 40), (0.64, -30, 124, 42),
                                        (0.90, -120, 84, 28), (0.91, -58, 86, 29))):
        (x, y), _ = point_on(pts, s)
        parts.append(leaf_part(f"leaf-{k+1}", x, y, deg, L, W, droop=0.06))
    back, front = parts[:2], parts[2:]
    return [Group("stem", back + [stem] + front, tip=top, kind="stem")]

# ---------- the flower head ----------
def petal(C, r0, a, Lp, w, bend=0.0):
    ca, sa = math.cos(a), math.sin(a)
    def P(u, v):
        v = v + bend * Lp * (u / Lp) ** 2
        r = r0 + u
        return (C[0] + r*ca - v*sa, C[1] + r*sa + v*ca)
    return Contour([
        (P(0, -0.45*w), None, P(0.30*Lp, -1.25*w)),
        (P(Lp, 0), P(0.74*Lp, -0.62*w), P(0.74*Lp, 0.62*w)),
        (P(0, 0.45*w), P(0.30*Lp, 1.25*w), None),
    ], closed=True)

def ring(C, r0, n, Lp, w, offset, seed, jitter=0.10):
    rnd = random.Random(seed)
    out = []
    for i in range(n):
        a = 2 * math.pi * (i + offset) / n + rnd.uniform(-0.04, 0.04)
        out.append(petal(C, r0, a, Lp * rnd.uniform(1 - jitter, 1 + jitter), w,
                         bend=rnd.uniform(-0.08, 0.08)))
    return out

def flower(C, R, Lp):
    """The open face: green bracts, two rings of petals, the disc and its seeds.

    The seeds are laid on the sunflower's own pattern -- a Fermat spiral at the
    golden angle -- because that is the detail that makes a disc read as a
    sunflower rather than a brown circle.
    """
    bracts = ring(C, R * 0.70, 14, Lp * 0.62, R * 0.20, 0.25, 5, 0.12)
    back = ring(C, R * 0.80, 17, Lp * 0.96, R * 0.21, 0.5, 6)
    front = ring(C, R * 0.82, 17, Lp, R * 0.20, 0.0, 7)
    n = 120
    c = R * 0.80 / math.sqrt(n)
    golden = math.radians(137.508)
    seeds, light = [], []
    for i in range(1, n + 1):
        r, t = c * math.sqrt(i), i * golden
        d = Dot(C[0] + r * math.cos(t), C[1] + r * math.sin(t), c * 0.40)
        (light if i % 3 == 0 else seeds).append(d)
    return [
        Path("head-bracts", bracts, fill=BRACT, stroke=OUTLINE, stroke_width=LEAF_STROKE),
        Path("head-petals-back", back, fill=PETAL_BACK, stroke=HEAD_OUTLINE, stroke_width=LEAF_STROKE),
        Path("head-petals", front, fill=PETAL, stroke=HEAD_OUTLINE, stroke_width=LEAF_STROKE),
        Path("head-disc", [circle(*C, R)], fill=DISC_RING, stroke=HEAD_OUTLINE, stroke_width=2.8),
        Path("head-disc-centre", [circle(*C, R * 0.84)], fill=DISC),
        Dots("head-seeds", seeds, DISC_SEED),
        Dots("head-seeds-light", light, DISC_LIGHT),
    ]

def bud(C, r, opening=0.0):
    """A closed head: a green star of bracts around a green dome. `opening`
    between 0 and 1 lets that much petal show between the bracts."""
    parts = [Path("head-bracts", ring(C, r * 0.25, 11, r * 0.95, r * 0.34, 0.0, 9, 0.08),
                  fill=BRACT, stroke=OUTLINE, stroke_width=LEAF_STROKE)]
    if opening:
        parts.append(Path("head-petals", ring(C, r * 0.55, 11, r * (0.55 + 0.35 * opening),
                                              r * 0.22, 0.5, 10, 0.15),
                          fill=PETAL, stroke=HEAD_OUTLINE, stroke_width=LEAF_STROKE))
    parts.append(Path("head-dome", [circle(*C, r * 0.62)], fill=STEM,
                      stroke=OUTLINE, stroke_width=LEAF_STROKE))
    # the inner bracts fold toward the centre: a negative start radius runs the
    # petal shape inward, from the dome's edge to near its middle
    parts.append(Path("head-scales", ring(C, -r * 0.60, 8, r * 0.44, r * 0.15, 0.3, 11, 0.1),
                      fill=LEAF, stroke=OUTLINE, stroke_width=1.8))
    return parts

def head_part(neck_base, C, face, stem_w, gid="head"):
    """The head as a part pivoting at the top of the stem, with its neck.

    Returns (head, twin): the twin is the neck's outline pass, which the caller
    puts *behind* the upper stem's fill so the neck grows out of the stem.
    """
    neck_pts = curve(neck_base, (neck_base[0] + 4, neck_base[1] - 30),
                     (C[0] - 6, C[1] + 60), C, 10)
    neck = [tapered(neck_pts, stem_w, stem_w * 0.8, round_end=False)]
    joints = [(neck_base, stem_w / 2)]
    head = Group(gid, stem_fill(f"{gid}-neck", neck, joints) + face,
                 tip=C, kind="head", pivot=neck_base)
    twin = Group(f"{gid}-line", stem_line(f"{gid}-neck", neck, joints),
                 tip=C, kind="head", pivot=neck_base, meta={"follows": gid})
    return head, twin

# ---------- stages 3 to 5: the tall plant ----------
# A tall sunflower bends in the middle of its stem when it wilts, so the stem is
# two parts: `stem` from the ground to the bend, and `stem-upper` nested in it
# from the bend to the neck. The head is a third, nested in the upper stem.
#
#   plant
#   └ stem                  pivot: base
#     ├ back leaves
#     ├ stem outline pass, stem-upper-line (twin)
#     ├ stem fill, front leaves
#     └ stem-upper          pivot: the bend
#       ├ head-line (twin)
#       ├ upper fill + joint disc, its leaves
#       └ head              pivot: the neck

class TallPlan:
    def __init__(self, top, bend_at, w0, w_bend, w_top, leaves, head, head_r, petal_len=0,
                 opening=0.0):
        self.top, self.bend_at = top, bend_at
        self.w0, self.w_bend, self.w_top = w0, w_bend, w_top
        self.leaves, self.head, self.head_r = leaves, head, head_r
        self.petal_len, self.opening = petal_len, opening

def tall(plan):
    x0, y0 = BASE[0], BASE[1] + 12
    top = plan.top
    full = curve((x0, y0), (x0 + 14, y0 - (y0 - top[1]) * 0.35),
                 (top[0] - 10, y0 - (y0 - top[1]) * 0.70), top, 24)
    lens = cumlen(full)
    bend, _ = at_frac(full, lens, plan.bend_at)
    k = min(range(len(full)), key=lambda i: math.dist(full[i], bend))
    lower_pts = full[:k + 1]
    upper_pts = full[k:]
    lower = [tapered(lower_pts, plan.w0, plan.w_bend, round_end=False)]
    upper = [tapered(upper_pts, plan.w_bend, plan.w_top, round_end=False)]
    upper_joint = [(full[k], plan.w_bend / 2)]
    # leaves: (fraction up the whole stem, angle, length, half-width, darker?)
    # Every leaf is drawn *behind* its stem, so the stalk disappears into it:
    # on the lower stem the stem's outline crosses the stalk, and on the upper
    # stem the stalk sits between the outline pass and the fill, so the stem's
    # outline breaks where the stalk joins -- it reads as grown, not stuck on.
    low, up = [], []
    for i, (s, deg, L, W, back) in enumerate(plan.leaves):
        (x, y), _ = at_frac(full, lens, s)
        part = leaf_part(f"leaf-{i+1}", x, y, deg, L, W, back=back)
        (low if s < plan.bend_at else up).append(part)
    if plan.petal_len:
        face = flower(plan.head, plan.head_r, plan.petal_len)
    else:
        face = bud(plan.head, plan.head_r, plan.opening)
    head, head_twin = head_part(top, plan.head, face, plan.w_top)
    upper_part = Group("stem-upper",
                       [head_twin] + up + stem_fill("stem-upper", upper, upper_joint) + [head],
                       tip=top, kind="upper-stem", pivot=full[k])
    upper_twin = Group("stem-upper-line", stem_line("stem-upper", upper, upper_joint),
                       tip=top, kind="upper-stem", pivot=full[k], meta={"follows": "stem-upper"})
    stem = Group("stem", low + stem_line("stem", lower) + [upper_twin]
                 + stem_fill("stem", lower) + [upper_part],
                 tip=top, kind="stem")
    return [stem]

LEAVES_YOUNG = [
    (0.20, -165, 150, 56, True), (0.30, -18, 160, 60, False),
    (0.50, -150, 140, 52, False), (0.60, -28, 132, 50, True),
    (0.78, -140, 104, 38, False), (0.84, -40, 100, 36, False),
]
LEAVES_MATURE = [
    (0.14, -168, 210, 78, True), (0.22, -14, 222, 82, False),
    (0.36, -158, 206, 76, False), (0.46, -22, 196, 72, True),
    (0.60, -150, 176, 64, False), (0.68, -30, 168, 62, False),
    (0.80, -140, 136, 50, False), (0.86, -42, 128, 46, False),
]

def young():
    return tall(TallPlan(top=(520, 400), bend_at=0.55, w0=22, w_bend=17, w_top=13,
                         leaves=LEAVES_YOUNG, head=(522, 330), head_r=44))

def mature(bloom=False):
    if bloom:
        return tall(TallPlan(top=(524, 320), bend_at=0.52, w0=32, w_bend=26, w_top=20,
                             leaves=LEAVES_MATURE, head=(532, 196), head_r=74, petal_len=86))
    return tall(TallPlan(top=(524, 320), bend_at=0.52, w0=32, w_bend=26, w_top=20,
                         leaves=LEAVES_MATURE, head=(530, 222), head_r=70, opening=0.55))

STAGE_MOUND = {1: 70, 2: 90, 3: 110, 4: 130, 5: 130}

def stage_parts(n):
    """(animated parts, back, front) for one stage."""
    if n == 0:
        back, seed, front = seed_stage()
        return [seed], back, front
    if n == 1:
        parts = sprout()
    elif n == 2:
        parts = seedling()
    elif n == 3:
        parts = young()
    else:
        parts = mature(bloom=(n == 5))
    return parts, None, base_mound(STAGE_MOUND[n])

# ---------- roots ----------
def build_root_tree(seed=23):
    """A sunflower's roots: a taproot that goes down fast, crowded with fine
    laterals, and a fringe of fibrous roots just under the surface.

    The oak's taproot is a long straight spike with a few long branches; this
    one is shorter and bushier, so the two root systems do not read alike.
    """
    rnd = random.Random(seed)
    tap_len = 400
    tap = Root("taproot", 0, math.radians(90), tap_len, 17, 1, seed * 10,
               wander=0.07, gravity=0.10)
    for j in range(9):
        fr = 0.10 + 0.085 * j + rnd.uniform(-0.02, 0.02)
        sd = 1 if j % 2 == 0 else -1
        c = Root(f"taproot-{j+1}", fr, math.radians(90 - sd * rnd.uniform(50, 72)),
                 tap_len * rnd.uniform(0.20, 0.30) * (1 - fr * 0.6), 5.5, 2, seed * 100 + j,
                 wander=0.16, gravity=0.04)
        c.children.append(Root(f"{c.rid}-1", 0.5, c.ang + sd * math.radians(35),
                               c.length * 0.5, 2.8, 3, seed * 1000 + j))
        tap.children.append(c)
    prim = [tap]
    for i, deg in enumerate((34, 146, 58, 122)):
        ln = rnd.uniform(200, 250) * (0.85 if i > 1 else 1)
        r = Root(f"fibrous-{i+1}", 0, math.radians(deg + rnd.uniform(-5, 5)), ln,
                 9 if i < 2 else 8, 1, seed * 10 + i + 1, wander=0.16, gravity=0.05)
        for j in range(3):
            fr = 0.28 + 0.24 * j + rnd.uniform(-0.04, 0.04)
            sd = 1 if j % 2 == 0 else -1
            c = Root(f"{r.rid}-{j+1}", fr, r.ang + sd * math.radians(rnd.uniform(30, 50)),
                     ln * rnd.uniform(0.25, 0.35), 4.5, 2, seed * 200 + i * 10 + j, wander=0.18)
            c.children.append(Root(f"{c.rid}-1", 0.55, c.ang - sd * math.radians(35),
                                   c.length * 0.5, 2.6, 3, seed * 2000 + i * 100 + j))
            r.children.append(c)
        prim.append(r)
    return prim

ROOT_LEVELS = {  # level: (length scale, max generation, number of primaries)
    1: (0.36, 2, 1),     # the taproot, already bristling
    2: (0.58, 2, 3),
    3: (0.80, 3, 5),
    4: (1.00, 3, 5),
}

# ---------- motion ----------
SWAY = {}
SWAY_DEFAULT = {"seed": 1.2, "stem": 0.8, "upper-stem": 1.0, "leaf": 2.4, "head": 1.6}
# The head is what wilts. The droop is 25 degrees times elevation/90 times this
# scale, so for an upright head 5.6 gives 140 degrees: past horizontal, hanging
# below its neck. The stem stays nearly upright at the ground and bends above
# the joint, so the plant curves over rather than tipping like a pole. Leaves
# hang harder than the fern's fronds: a thirsty sunflower leaf goes limp.
DROOP_KIND_SCALE = {"seed": 0.0, "stem": 0.15, "upper-stem": 1.0, "leaf": 2.6, "head": 5.6}
DROOP_DIRECTION = {
    (1, "stem"): +1,
    (2, "stem"): +1,
    (2, "leaf-3"): -1,
    (3, "stem"): +1, (3, "stem-upper"): +1, (3, "head"): +1,
    (4, "stem"): +1, (4, "stem-upper"): +1, (4, "head"): +1,
    (5, "stem"): +1, (5, "stem-upper"): +1, (5, "head"): +1,
}
LEAN_THRESHOLD = {3: 0.30, 4: 0.50}
LEAN_DIRECTION = {3: +1, 4: +1}   # the way the head nods: a top-heavy flower tips toward it

SUNFLOWER = Species(
    "Sunflower", stage_parts, build_root_tree, ROOT_LEVELS, DRY_FILL,
    sway=SWAY, sway_default=SWAY_DEFAULT, droop_kind_scale=DROOP_KIND_SCALE,
    droop_direction=DROOP_DIRECTION, lean_threshold=LEAN_THRESHOLD,
    lean_direction=LEAN_DIRECTION, still_stages=(0,))

if __name__ == "__main__":
    # python3 sunflower_generator.py [--sway=wind|independent] [--amplitude=1.4]
    main(SUNFLOWER, "sunflower", sys.argv[1:], __file__)
