"""Structural checks on the generated RML that `rive --verify` cannot make.

Generic over the species: run it for a plant project directory,

    python3 plantgen/check_rml.py oak          # from the worktree root
    python3 check_rml.py                        # from oak/, via its wrapper

The project directory `<name>/` must hold `<name>_generator.py`, which defines
the species as `<NAME>` (OAK, SUNFLOWER, ...), and the generated `<name>-*.rml`.

- every file is well-formed XML, and ids are unique across the whole project
  (the files share one namespace);
- every KeyedObject, BlendAnimation1D and converter reference resolves;
- every KeyFrameDouble / KeyFrameColor carries an explicit interpolationType
  (the default is `hold`);
- every emitted vertex, with the Node offsets above it accumulated, lands on
  the model's own point -- the check that pivots and nesting are emitted in
  the right space;
- a part that `follows` another is keyed with exactly the same values.
"""
import glob, math, os, sys
import xml.etree.ElementTree as ET

import importlib

def project_dir(argv):
    if len(argv) > 1:
        return os.path.abspath(argv[1])
    return os.getcwd()

HERE = project_dir(sys.argv)
NAME = os.path.basename(HERE)
sys.path.insert(0, HERE); sys.path.insert(0, os.path.join(HERE, ".."))
og = importlib.import_module(f"{NAME}_generator")
SPECIES = getattr(og, NAME.upper())
from plantgen.geometry import Group, Path
from plantgen.species import STAGES, animated

def fail(msg):
    print("FAIL", msg); fail.count += 1
fail.count = 0

files = sorted(glob.glob(os.path.join(HERE, f"{NAME}-*.rml")))
trees, ids = {}, {}
for f in files:
    root = ET.parse(f).getroot()
    trees[os.path.basename(f)] = root
    for el in root.iter():
        i = el.get("id")
        if i is None:
            continue
        if i in ids:
            fail(f"duplicate id {i} in {os.path.basename(f)} and {ids[i]}")
        ids[i] = os.path.basename(f)

for name, root in trees.items():
    for el in root.iter():
        for attr in ("objectId", "animationId", "converterId", "stateToId",
                     "defaultStateMachineId", "styleId"):
            ref = el.get(attr)
            if ref is not None and ref not in ids:
                fail(f"{name}: {el.tag}.{attr}={ref} resolves to nothing")
        if el.tag in ("KeyFrameDouble", "KeyFrameColor") and el.get("interpolationType") is None:
            fail(f"{name}: {el.tag} {el.get('id')} has no interpolationType")

def model_points(item, out):
    if isinstance(item, Group):
        for c in item.children:
            model_points(c, out)
    elif isinstance(item, Path):
        for c in item.contours:
            out.setdefault(item.pid, []).extend(n[0] for n in c.nodes)

def emitted_points(el, ox, oy, out, shape=None):
    if el.tag == "Node":
        ox += float(el.get("x", 0)); oy += float(el.get("y", 0))
    if el.tag == "Shape":
        shape = el.get("name")
    if el.tag in ("StraightVertex", "CubicDetachedVertex"):
        out.setdefault(shape, []).append((ox + float(el.get("x")), oy + float(el.get("y"))))
    for c in el:
        emitted_points(c, ox, oy, out, shape)

worst, count = 0.0, 0
for n, stage in STAGES.items():
    parts, back, front = og.stage_parts(n)
    model = {}
    for item in [back, Group("plant", parts), front]:
        if item is not None:
            model_points(item, model)
    root = trees[f"{NAME}-stage-{n}-{stage}.rml"]
    emitted = {}
    emitted_points(root.find("Artboard"), 0.0, 0.0, emitted)
    for pid, pts in model.items():
        got = emitted.get(pid)
        if got is None or len(got) != len(pts):
            fail(f"stage {n}: {pid} has {len(pts)} model points, {0 if got is None else len(got)} emitted")
            continue
        for a, b in zip(pts, got):
            e = math.dist(a, b); worst = max(worst, e); count += 1
    # twins: a follower's sway and droop keys equal its leader's
    anim = animated(parts)
    nodes = {el.get("name"): el.get("id") for el in root.iter("Node")}
    def keys(node_id):
        vals = []
        for ko in root.iter("KeyedObject"):
            if ko.get("objectId") == node_id:
                vals += [kf.get("value") for kf in ko.iter("KeyFrameDouble")]
        return vals
    for p in anim:
        lead = p.meta.get("follows")
        if lead:
            for layer in ("sway", "droop"):
                a, b = keys(nodes[f"{p.gid}-{layer}"]), keys(nodes[f"{lead}-{layer}"])
                if a != b or not a:
                    fail(f"stage {n}: {p.gid} {layer} keys differ from {lead}")
if worst > 0.05:     # the emitter rounds to 2 decimals; nesting can add a little
    fail(f"emitted vertices are up to {worst:.3f} px from the model")
print(f"{len(files)} files, {len(ids)} ids, {count} vertices, max error {worst:.3f} px, "
      f"{fail.count} failures")
sys.exit(1 if fail.count else 0)
