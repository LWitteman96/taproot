"""The SVG writer: one reader over the geometry model."""
from .geometry import W, Group, Dots, f

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
