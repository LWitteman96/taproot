"""The RML emitter: the other reader over the geometry model.

Rive-specific conversions live here and nowhere else -- polar handles, reversed
draw order, AARRGGBB colours, one id per element.
"""
import math
from .geometry import Group, Dots

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

def keyed(object_id, property_key, keyframe, ids, ind):
    """One property keyed on one object, holding a single keyframe."""
    return [f'{ind}<KeyedObject objectId="{object_id}" id="{ids()}">',
            f'{ind}    <KeyedProperty propertyKey="{property_key}" id="{ids()}">',
            f'{ind}        {keyframe}',
            f'{ind}    </KeyedProperty>',
            f'{ind}</KeyedObject>']
