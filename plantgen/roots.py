"""Root systems: a tree of Root nodes, grown between levels by scale.

The species decides the shape of the tree (build it from Root nodes) and what
each level shows (a levels table). Everything else -- the node structure, the
scale rule, the SVG poses -- is the same for every plant.
"""
import math, random
from .geometry import Group, Path, tapered, cumlen, at_frac
from .ground import ROOT, ROOT_OUTLINE

ROOT_ORIGIN = (512, 0)       # the ground line; roots hang down from here

class Root:
    """One root, its shape defined at unit length so it scales cleanly.

    The shape is a random walk: `wander` is the per-step turn, `gravity` the pull
    back toward straight down. A fern's fibrous roots wander; an oak's taproot
    barely does.
    """
    def __init__(self, rid, frac, ang, length, width, gen, seed, children=(),
                 wander=0.10, gravity=0.035, steps=24):
        self.rid, self.frac, self.ang, self.length, self.width, self.gen = rid, frac, ang, length, width, gen
        rnd = random.Random(seed)
        self.unit = [(0.0, 0.0)]; a = ang; x = y = 0.0
        for i in range(steps):
            a += rnd.uniform(-wander, wander)
            a += (math.pi/2 - a) * gravity
            x += math.cos(a) / steps; y += math.sin(a) / steps
            self.unit.append((x, y))
        self.children = list(children)

    def pts(self, origin, s):
        return [(origin[0] + u*self.length*s, origin[1] + v*self.length*s) for u, v in self.unit]

def root_forest(tree, tip_width=1.4):
    """The whole root system as nested Groups, authored at full size.

    Every root and every branch is its own node, placed at its attachment point
    in its *parent's* local space, holding geometry that starts at its own
    origin. Nothing here knows about levels: growing the system is a scale on
    these nodes, which is what lets one tree serve every level.

    Scale composes down the hierarchy, so scaling a primary carries its branches
    and their attachment points with it -- which is what a root growing longer
    actually does.
    """
    def node(r, prim_index):
        local = [(u * r.length, v * r.length) for u, v in r.unit]
        shape = Path(f"{r.rid}-shape", [tapered(local, r.width, tip_width)], fill=ROOT,
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

def root_scale(part, level, levels):
    """The scale one root node takes at one root level. 0 means "not yet there".

    `levels` maps level -> (length factor, max generation, number of primaries).
    A primary carries the level's length factor; a branch is either present at
    full size or absent, because a branch that is shown is shown whole. `level`
    of None is the empty pose, before any roots exist at all.
    """
    if level is None:
        return 0.0
    length_factor, max_generation, primary_count = levels[level]
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

def roots(level, tree, levels):
    """The root system posed at one level, for the SVG reference.

    Reads the same forest and the same scale rule the RML poses use, so the two
    cannot describe different plants.
    """
    forest = root_forest(tree)
    for part in root_parts(forest):
        part.scale = root_scale(part, level, levels)
    return [forest]
