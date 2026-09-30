# ---------- stage 0: the seed ----------
# Drop-in for fern_generator.py: uses only Contour / Dot / Path / Dots / Group,
# GROUND, ROOT_OUTLINE, SOIL, SOIL_DARK and quad_to_cubic from the generator.
import math

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
