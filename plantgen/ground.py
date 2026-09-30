"""The ground every plant stands in: the soil palette, the mound, the seed bed.

Shared rather than per species because the garden is one world -- a fern and an
oak must sit in the same soil.
"""
from .geometry import GROUND, Contour, Dot, Path, Dots, Group, quad_to_cubic

SOIL = "#7A5537"; SOIL_DARK = "#5E3F28"; ROOT = "#8A6443"; ROOT_OUTLINE = "#4A3322"

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
