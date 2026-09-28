"""One plant species as a Rive project: stage artboards, a roots artboard, and
the shared view model -- the animation half of every plant generator.

A species supplies its art (a `stage_parts` function and a root tree) and a
handful of tables (what fades, how parts sway, which way they fall). Everything
here reads those and nothing else, which is what lets a new plant reuse the
fern's wiring without touching it. See fern/NOTES.md for why each piece is the
way it is; the comments here keep the short version.
"""
import math, os
from .geometry import W, BASE, Group
from .svg import svg
from .rml import argb, Ids, rml_item, keyed
from .roots import root_forest, root_parts, root_scale, roots

STAGES = {0: "seed", 1: "sprout", 2: "seedling", 3: "young", 4: "mature", 5: "bloom"}

# ---------- timing and shaping shared by every species ----------
SWAY_FRAMES = 300      # 5s at 60fps
SWAY_SAMPLES = 24      # keyframes per part per loop
SWAY_HARMONIC = 0.28   # weight of the 2x component, relative to the fundamental
SWAY_WIND_LAG = 0.22      # phase lag in turns, across the full width of the plant
SWAY_WIND_HARMONIC = 0.17 # fixed offset of the harmonic, in wind mode
# Irrational-ish steps, so parts with no hand-tuned phase still spread out
# rather than landing on top of each other.
SWAY_PHASE_STEP = 0.37
SWAY_HARMONIC_STEP = 0.61

DROOP_MAX_DEGREES = 25     # what a fully upright part gives up at vitality 0
NEAR_VERTICAL_DEGREES = 80 # above this, which way a part leans is an accident

SMOOTHING_SECONDS = 0.6   # how long a changed vitality takes to arrive
SWAY_FLOOR = 40           # blend weight at vitality 0: the sway never fully stops
# A stage with no vitality (the seed) gets a floor equal to the ceiling, which
# makes the range mapper a constant -- vitality-independence without a
# differently-shaped state machine.
FROZEN_SWAY_FLOOR = 100

# Asymmetric on purpose: steep at the top of the range so a small drop from full
# vitality is visible immediately, flattening toward 0 so the plant settles into
# its wilt instead of slamming into it.
DROOP_EASE = (0.4, 0, 1, 1)
SWAY_EASE = (0.4, 0, 1, 1)

LEAN_DEGREES = 5.0
ROOTS_HEIGHT = 520              # the roots canvas; level 4 must fit
ROOTS_SMOOTHING_SECONDS = 1.2   # roots grow after a reflection; they do not snap
# Blend axis positions for the five root poses. Uneven on purpose: bare soil to
# a first root should read as a bigger event than one level to the next.
ROOTS_POSES = [(0, None), (15, 1), (30, 2), (50, 3), (75, 4)]

# Id clients. Each file gets its own, so ids cannot collide across files that
# share one document. Stages use their number; 6 is the roots, 9 the data.
ROOTS_CLIENT = 6
DATA_CLIENT = 9
VIEWMODEL_ID, VITALITY_ID, INSTANCE_ID = "9:2", "9:3", "9:4"
ROOTS_ID = "9:5"

STAGE_GUTTER = 120   # artboards sit in a row on the editor stage

class Species:
    """Everything that differs between two plants.

    name            PascalCase. Names the view model, the state machine and
                    every artboard (`{name}Mature`, `{name}Roots`) -- the host's
                    public surface.
    stage_parts     n -> (animated parts, back, front). Parts are Groups with a
                    `kind` and a `tip`; they may nest (a branch inside a trunk),
                    and a nested part's droop and sway compose with its parent's.
    root_tree       () -> [Root]. root_levels: level -> (length, max gen, primaries).
    dry_fill        healthy fill -> thirsty fill. Membership decides what fades.
    sway            part id -> (degrees, phase, harmonic phase), hand-tuned.
    sway_default    kind -> degrees, for every part without a `sway` entry.
    droop_kind_scale kind -> multiplier on DROOP_MAX_DEGREES. 0 = does not droop.
    droop_direction (stage, part id) -> +1/-1, required for near-vertical parts.
    lean_threshold  stage -> roots value at which the plant stands straight.
    lean_direction  stage -> +1/-1.
    still_stages    stages that ignore vitality entirely (the seed).
    sway_mode       "independent" or "wind"; sway_amplitude a global multiplier.
    """
    def __init__(self, name, stage_parts, root_tree, root_levels, dry_fill,
                 sway=None, sway_default=None, droop_kind_scale=None,
                 droop_direction=None, lean_threshold=None, lean_direction=None,
                 still_stages=(0,), sway_mode="independent", sway_amplitude=1.0):
        self.name = name
        self.stage_parts, self.root_tree, self.root_levels = stage_parts, root_tree, root_levels
        self.dry_fill = dry_fill
        self.sway = sway or {}
        self.sway_default = sway_default or {}
        self.droop_kind_scale = droop_kind_scale or {}
        self.droop_direction = droop_direction or {}
        self.lean_threshold = lean_threshold or {}
        self.lean_direction = lean_direction or {}
        self.still_stages = set(still_stages)
        self.sway_mode, self.sway_amplitude = sway_mode, sway_amplitude

    # ----- art -----
    def stage(self, n):
        """The drawables for one stage, as the SVG writer wants them: back to front."""
        parts, back, front = self.stage_parts(n)
        out = [back] if back else []
        out.append(Group("plant", parts))
        if front:
            out.append(front)
        return out

    # ----- the sway -----
    @staticmethod
    def leader(part, parts):
        """The part whose motion this one copies, and its index.

        A part with meta["follows"] moves exactly like the part it names. It is
        how one limb can be drawn in two layers -- its outline behind the
        trunk, its fill in front -- and still move as one thing.
        """
        name = part.meta.get("follows")
        if name is None:
            return part, None
        for i, p in enumerate(parts):
            if p.gid == name:
                return p, i
        raise ValueError(f"{part.gid} follows {name!r}, which is not an animated part")

    def sway_degrees(self, part):
        if part.gid in self.sway:
            return self.sway[part.gid][0]
        return self.sway_default[part.kind]

    def sway_phases(self, part, index, parts):
        """(fundamental phase, harmonic phase) in turns, per the current mode."""
        if self.sway_mode == "wind":
            xs = [p.tip[0] for p in parts]
            span = (max(xs) - min(xs)) or 1
            lag = (part.tip[0] - min(xs)) / span * SWAY_WIND_LAG
            return lag, lag + SWAY_WIND_HARMONIC
        if part.gid in self.sway:
            _, phase, phase2 = self.sway[part.gid]
            return phase, phase2
        return (index * SWAY_PHASE_STEP) % 1.0, (index * SWAY_HARMONIC_STEP) % 1.0

    def sway_angle(self, part, index, parts, t):
        """Rotation in radians at loop fraction t. A fundamental plus a
        second harmonic, both whole cycles per loop, so the loop is seamless."""
        lead, lead_index = self.leader(part, parts)
        if lead is not part:
            part, index = lead, lead_index
        amplitude = math.radians(self.sway_degrees(part)) * self.sway_amplitude
        phase, phase2 = self.sway_phases(part, index, parts)
        return (amplitude * math.sin(2*math.pi * (t + phase))
                + amplitude * SWAY_HARMONIC * math.sin(4*math.pi * (t + phase2)))

    # ----- the droop -----
    def droop_angle(self, part, n, parts=()):
        """Rotation in radians at vitality 0, derived from the art.

        A part gives up DROOP_MAX_DEGREES scaled by how upright it is (measured
        from its own pivot) and by its kind, toward the side its tip is on.
        Near-vertical parts must declare the side instead.
        """
        if part.meta.get("follows"):
            part, _ = self.leader(part, parts)
        # A generator that lays parts out by rule can state each part's droop
        # outright, when "more upright falls further" is the wrong rule for it.
        if "droop_degrees" in part.meta:
            return math.radians(part.meta["droop_degrees"])
        pivot = part.pivot or BASE
        dx, dy = part.tip[0] - pivot[0], part.tip[1] - pivot[1]
        elevation = math.degrees(math.atan2(-dy, abs(dx)))          # 0 = flat, 90 = straight up
        magnitude = math.radians(DROOP_MAX_DEGREES * elevation / 90) * self.droop_kind_scale[part.kind]
        if magnitude == 0:
            return 0.0
        if elevation >= NEAR_VERTICAL_DEGREES:
            # a generator placing parts by the dozen can declare the side on
            # the part itself; a hand-placed part is declared in the table
            if "droop_direction" in part.meta:
                return part.meta["droop_direction"] * magnitude
            if (n, part.gid) not in self.droop_direction:
                raise ValueError(
                    f"stage {n}: {part.gid} is near-vertical ({elevation:.1f} deg), so which way "
                    f"it droops cannot be read off the art. Add ({n}, {part.gid!r}) to "
                    f"droop_direction (+1 right, -1 left).")
            return self.droop_direction[(n, part.gid)] * magnitude
        return math.copysign(magnitude, dx)

    def dry_fills(self, part):
        """[(path name, healthy colour)] for every fill directly in this part that fades."""
        return [(c.pid, c.fill) for c in part.children
                if getattr(c, "fill", None) in self.dry_fill]

    # ----- RML -----
    def data_rml(self):
        return "\n".join([
            '<Rive version="1" kind="fragment">',
            f'    <ViewModel defaultInstanceId="{INSTANCE_ID}" name="{self.name}" id="{VIEWMODEL_ID}">',
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

    def stage_rml(self, n, name):
        return stage_rml(self, n, name)

    def roots_rml(self):
        return roots_rml(self)

    def write(self, out, prefix):
        """Every generated file, into `out`: stage and root SVGs, then the RML."""
        for n, name in STAGES.items():
            open(f"{out}/{prefix}-stage-{n}-{name}.svg", "w").write(svg(self.stage(n)))
        tree = self.root_tree()
        for lv in self.root_levels:
            open(f"{out}/{prefix}-roots-{lv}.svg", "w").write(svg(roots(lv, tree, self.root_levels)))
        open(f"{out}/{prefix}-data.rml", "w").write(self.data_rml())
        open(f"{out}/{prefix}-roots.rml", "w").write(self.roots_rml())
        for n, name in STAGES.items():
            open(f"{out}/{prefix}-stage-{n}-{name}.rml", "w").write(self.stage_rml(n, name))


def animated(parts):
    """Every animated part, depth-first: top-level parts and any nested in them."""
    out = []
    def walk(group):
        out.append(group)
        for child in group.children:
            if isinstance(child, Group) and child.kind is not None:
                walk(child)
    for part in parts:
        walk(part)
    return out

def part_node(group, ids, depth, nodes, paints=None, parent_pivot=BASE):
    """A part gets two nested transforms, both at its pivot: the outer carries
    the vitality droop, the inner the sway. Each rotation has exactly one owner,
    so the two timelines compose instead of overwriting one another.

    The node sits at the pivot relative to its parent's pivot (the plant node is
    at BASE), and the art inside is emitted relative to the pivot. A part nested
    in another is emitted inside its parent's sway node, so it rides along.
    """
    ind = "    " * depth
    pivot = group.pivot or BASE
    droop_id, sway_id = ids(), ids()
    nodes[group.gid] = {"droop": droop_id, "sway": sway_id}
    dx, dy = pivot[0] - parent_pivot[0], pivot[1] - parent_pivot[1]
    at = f' x="{dx:.2f}" y="{dy:.2f}"' if (dx, dy) != (0, 0) else ""
    out = [f'{ind}<Node{at} name="{group.gid}-droop" id="{droop_id}">',
           f'{ind}    <Node name="{group.gid}-sway" id="{sway_id}">']
    for child in reversed(group.children):
        if isinstance(child, Group) and child.kind is not None:
            out += part_node(child, ids, depth + 2, nodes, paints, pivot)
        else:
            out += rml_item(child, pivot, ids, depth + 2, paints)
    out += [f'{ind}    </Node>', f'{ind}</Node>']
    return out

def sway_animation(sp, parts, nodes, ids, anim_id, depth=2):
    """Key rotation (propertyKey 15, radians) on every part's inner sway node,
    sampled at SWAY_SAMPLES points per loop."""
    ind = "    " * depth
    out = [f'{ind}<LinearAnimation loopValue="loop" fps="60" duration="{SWAY_FRAMES}" '
           f'name="Sway" id="{anim_id}">']
    for index, part in enumerate(parts):
        out.append(f'{ind}    <KeyedObject objectId="{nodes[part.gid]["sway"]}" id="{ids()}">')
        out.append(f'{ind}        <KeyedProperty propertyKey="15" id="{ids()}">')
        for i in range(SWAY_SAMPLES + 1):
            frame = round(SWAY_FRAMES * i / SWAY_SAMPLES)
            angle = sp.sway_angle(part, index, parts, i / SWAY_SAMPLES)
            # interpolationType defaults to hold, which would step the sway
            out.append(f'{ind}            <KeyFrameDouble frame="{frame}" value="{angle:.6f}" '
                       f'interpolationType="linear" id="{ids()}"/>')
        out.append(f'{ind}        </KeyedProperty>')
        out.append(f'{ind}    </KeyedObject>')
    out.append(f'{ind}</LinearAnimation>')
    return out

def droop_pose(sp, name, anim_id, n, parts, dry, nodes, paints, ids, depth=2):
    """One end of the droop blend. Both poses key *every* property on *every*
    part, or the blend jumps instead of mixing."""
    ind = "    " * depth
    out = [f'{ind}<LinearAnimation fps="60" duration="60" name="{name}" id="{anim_id}">']
    for part in parts:
        angle = sp.droop_angle(part, n, parts) if dry else 0.0
        rotation = (f'<KeyFrameDouble frame="0" value="{angle:.6f}" '
                    f'interpolationType="linear" id="{ids()}"/>')
        out += keyed(nodes[part.gid]["droop"], 15, rotation, ids, ind + "    ")
        for path_name, healthy in sp.dry_fills(part):
            # propertyKey 37 on the SolidColor, and a KeyFrameColor to match it
            value = argb(sp.dry_fill[healthy] if dry else healthy)
            colour = (f'<KeyFrameColor frame="0" value="{value}" '
                      f'interpolationType="linear" id="{ids()}"/>')
            out += keyed(paints[path_name], 37, colour, ids, ind + "    ")
    out.append(f'{ind}</LinearAnimation>')
    return out

def still_pose(anim_id, parts, nodes, ids, depth=2):
    """The zero end of the sway blend: every sway node held at rest."""
    ind = "    " * depth
    out = [f'{ind}<LinearAnimation fps="60" duration="60" name="Still" id="{anim_id}">']
    for part in parts:
        rotation = f'<KeyFrameDouble frame="0" value="0" interpolationType="linear" id="{ids()}"/>'
        out += keyed(nodes[part.gid]["sway"], 15, rotation, ids, ind + "    ")
    out.append(f'{ind}</LinearAnimation>')
    return out

def lean_pose(name, anim_id, angle, plant_id, ids, depth=2):
    """One end of the stability blend: rotation on the whole plant."""
    ind = "    " * depth
    frame = (f'<KeyFrameDouble frame="0" value="{angle:.6f}" '
             f'interpolationType="linear" id="{ids()}"/>')
    return ([f'{ind}<LinearAnimation fps="60" duration="60" name="{name}" id="{anim_id}">']
            + keyed(plant_id, 15, frame, ids, ind + "    ")
            + [f'{ind}</LinearAnimation>'])

def converter_chain(name, ids, min_output, max_output, ease, group_id,
                    seconds=None, max_input=1):
    """A DataConverterGroup: smooth the incoming value, then remap its range.

    `ease` of None leaves the range mapper linear -- for an axis already shaped
    elsewhere, so the same curve is not shaped twice.
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

def blend_layer(layer_name, layer_id, blend_id, bindable_id, property_id, group_id, poses):
    """A state machine layer holding one BlendState1DViewModel.

    `poses` is [(animation id, axis value)], emitted in the given order -- the
    caller passes them ascending, since the runtime binary-searches them.
    """
    out = [
        f'            <StateMachineLayer name="{layer_name}" id="{layer_id}">',
        '                <AnyState x="420" y="-120"/>',
        '                <ExitState x="620" y="-120"/>',
        '                <EntryState x="0" y="0">',
        f'                    <StateTransition stateToId="{blend_id}"/>',
        '                </EntryState>',
        f'                <BlendState1DViewModel x="160" y="0" id="{blend_id}">',
        f'                    <BindablePropertyNumber id="{bindable_id}">',
        f'                        <DataBindContext sourcePathIds="{VIEWMODEL_ID}-{property_id}" '
        f'propertyKey="636" converterId="{group_id}"/>',
        '                    </BindablePropertyNumber>',
    ]
    return out, [
        '                </BlendState1DViewModel>',
        '            </StateMachineLayer>',
    ]

def stage_rml(sp, n, name):
    """One stage as its own artboard, in its own file, with id client `n`."""
    top, back, front = sp.stage_parts(n)
    parts = animated(top)
    ids = Ids(client=n)
    artboard_id, machine_id, style_id = ids(), ids(), ids()
    sway_layer_id, sway_blend_id, sway_bindable_id = ids(), ids(), ids()
    vitality_layer_id, droop_blend_id, droop_bindable_id = ids(), ids(), ids()
    sway_id, still_id, upright_id, drooped_id = ids(), ids(), ids(), ids()
    droop_group_id, sway_group_id = ids(), ids()
    leans = n in sp.lean_threshold
    lean_layer_id, lean_blend_id, lean_bindable_id = ids(), ids(), ids()
    steady_id, leaning_id, lean_group_id = ids(), ids(), ids()
    nodes, paints = {}, {}
    plant_id = ids()
    body = []
    # RML draw order is the reverse of SVG's: the first Shape declared paints on
    # top. Front soil first, the plant next, whatever sits behind it last. The
    # soil is outside the plant node so the stability lean does not tilt it.
    if front:
        body += rml_item(front, (0, 0), ids, 2, paints)
    body.append(f'        <Node x="{BASE[0]}" y="{BASE[1]}" name="plant" id="{plant_id}">')
    for part in reversed(top):
        body += part_node(part, ids, 3, nodes, paints)
    body.append('        </Node>')
    if back:
        body += rml_item(back, (0, 0), ids, 2, paints)

    artboard = f"{sp.name}{name.capitalize()}"
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
    ] + sway_animation(sp, parts, nodes, ids, sway_id) + [
        '',
    ] + still_pose(still_id, parts, nodes, ids) + [
        '',
    ] + droop_pose(sp, "Upright", upright_id, n, parts, False, nodes, paints, ids) + [
        '',
    ] + droop_pose(sp, "Drooped", drooped_id, n, parts, True, nodes, paints, ids)
    if leans:
        tail += [''] + lean_pose('Steady', steady_id, 0.0, plant_id, ids)
        tail += [''] + lean_pose(
            'Leaning', leaning_id,
            sp.lean_direction[n] * math.radians(LEAN_DEGREES), plant_id, ids)
    tail += [
        '',
        f'        <StateMachine name="{sp.name}" id="{machine_id}">',
        '',
        '            <!-- the sway owns rotation on the inner *-sway nodes.',
        '                 vitality scales its amplitude between Still and Sway. -->',
    ]
    opened, closed = blend_layer("Sway", sway_layer_id, sway_blend_id, sway_bindable_id,
                                 VITALITY_ID, sway_group_id, None)
    tail += opened + [
        f'                    <BlendAnimation1D animationId="{still_id}" value="0"/>',
        f'                    <BlendAnimation1D animationId="{sway_id}" value="100"/>',
    ] + closed + [
        '',
        '            <!-- vitality owns rotation on the outer *-droop nodes,',
        '                 and the fills that fade -->',
    ]
    opened, closed = blend_layer("Vitality", vitality_layer_id, droop_blend_id, droop_bindable_id,
                                 VITALITY_ID, droop_group_id, None)
    tail += opened + [
        '                    <!-- ascending value order: the runtime binary-searches these -->',
        f'                    <BlendAnimation1D animationId="{drooped_id}" value="0"/>',
        f'                    <BlendAnimation1D animationId="{upright_id}" value="100"/>',
    ] + closed
    if leans:
        tail += [
            '',
            '            <!-- a plant taller than its roots leans. this layer owns',
            '                 rotation on the plant node; nothing else touches it. -->',
        ]
        opened, closed = blend_layer("Stability", lean_layer_id, lean_blend_id, lean_bindable_id,
                                     ROOTS_ID, lean_group_id, None)
        tail += opened + [
            f'                    <BlendAnimation1D animationId="{leaning_id}" value="0"/>',
            f'                    <BlendAnimation1D animationId="{steady_id}" value="100"/>',
        ] + closed
    tail += [
        '        </StateMachine>',
        '    </Artboard>',
        '',
    ] + converter_chain("Droop", ids, 0, 100, DROOP_EASE, droop_group_id) + [
        '',
    ] + converter_chain("Sway", ids, FROZEN_SWAY_FLOOR if n in sp.still_stages else SWAY_FLOOR,
                        100, SWAY_EASE, sway_group_id)
    if leans:
        # roots at the stage's threshold read as steady, roots at 0 as a full
        # lean. The mapper is linear: the threshold is the shaping.
        tail += [''] + converter_chain('Stability', ids, 0, 100, None, lean_group_id,
                                       seconds=ROOTS_SMOOTHING_SECONDS,
                                       max_input=sp.lean_threshold[n])
    tail += [
        '</Rive>',
        '',
    ]
    return "\n".join(head + body + tail)

def roots_pose(sp, name, anim_id, level, parts, groups, ids, depth=2):
    """One pose of the root blend: scaleX and scaleY on every root node, keyed
    in every pose so nothing pops."""
    ind = "    " * depth
    out = [f'{ind}<LinearAnimation fps="60" duration="60" name="{name}" id="{anim_id}">']
    for part in parts:
        value = root_scale(part, level, sp.root_levels)
        for property_key in (16, 17):        # scaleX, scaleY
            frame = (f'<KeyFrameDouble frame="0" value="{value:.4f}" '
                     f'interpolationType="linear" id="{ids()}"/>')
            out += keyed(groups[part.gid], property_key, frame, ids, ind + "    ")
    out.append(f'{ind}</LinearAnimation>')
    return out

def roots_rml(sp):
    """The root system as its own artboard, stacked under a stage by the host
    (a bind inside a NestedArtboard does not resolve)."""
    ids = Ids(client=ROOTS_CLIENT)
    artboard_id, machine_id, style_id = ids(), ids(), ids()
    layer_id, blend_id, bindable_id, group_id = ids(), ids(), ids(), ids()
    pose_ids = [ids() for _ in ROOTS_POSES]

    forest = root_forest(sp.root_tree())
    parts = root_parts(forest)
    for part in parts:
        part.scale = root_scale(part, 4, sp.root_levels)   # what shows if rendered unbound

    groups = {}
    body = rml_item(forest, (0, 0), ids, 2, {}, groups)

    head = [
        '<Rive version="1" kind="fragment">',
        f'    <Artboard defaultStateMachineId="{machine_id}" viewModelId="{VIEWMODEL_ID}" '
        f'viewModelInstanceId="{INSTANCE_ID}" x="0" y="{W + 240}" '
        f'width="{W}" height="{ROOTS_HEIGHT}" styleId="{style_id}" name="{sp.name}Roots" id="{artboard_id}">',
        f'        <LayoutComponentStyle name="Artboard Style" id="{style_id}"/>',
        '',
    ]
    tail = ['']
    for (_, level), anim_id in zip(ROOTS_POSES, pose_ids):
        pose = "RootsNone" if level is None else f"RootsLevel{level}"
        tail += roots_pose(sp, pose, anim_id, level, parts, groups, ids) + ['']
    tail += [f'        <StateMachine name="{sp.name}" id="{machine_id}">']
    opened, closed = blend_layer("Roots", layer_id, blend_id, bindable_id,
                                 ROOTS_ID, group_id, None)
    tail += opened + [
        '                    <!-- ascending value order: the runtime binary-searches these -->',
    ]
    for (value, _), anim_id in zip(ROOTS_POSES, pose_ids):
        tail.append(f'                    <BlendAnimation1D animationId="{anim_id}" value="{value}"/>')
    tail += closed + [
        '        </StateMachine>',
        '    </Artboard>',
        '',
    ] + converter_chain("Roots", ids, 0, 100, None, group_id,
                        seconds=ROOTS_SMOOTHING_SECONDS) + [
        '</Rive>',
        '',
    ]
    return "\n".join(head + body + tail)

def main(sp, prefix, argv, here):
    """The command line every generator shares: --sway=, --amplitude=."""
    for arg in argv:
        if arg.startswith("--sway="):
            sp.sway_mode = arg.split("=", 1)[1]
            if sp.sway_mode not in ("independent", "wind"):
                raise SystemExit(f"--sway must be independent or wind, not {sp.sway_mode!r}")
        elif arg.startswith("--amplitude="):
            sp.sway_amplitude = float(arg.split("=", 1)[1])
        else:
            raise SystemExit(f"unknown argument {arg!r}")
    out = os.path.dirname(os.path.abspath(here))
    sp.write(out, prefix)
    print(f"written to {out}  (sway={sp.sway_mode}, amplitude={sp.sway_amplitude})")
