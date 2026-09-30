#!/usr/bin/env python3
"""Does the build draw the art? Diff the `.riv` against the `.svg` it came from.

The strongest appearance check available, and the reason is that both outputs
come from **one geometry model**: the SVG writer and the RML emitter read the
same `Group`/`Path` tree. So this compares the build against *the art the build
came from*, rather than against a reference image someone once approved — a
reference render can only tell you the picture changed, not which of the two
writers is wrong.

Generic over the species: run it for a plant project directory, after
`rive . --once` has built it.

    python3 plantgen/check_svg_render.py sunflower    # from the worktree root
    python3 check_svg_render.py                       # from sunflower/

Every stage and every root level. Two numbers per pair, because they mean
different things:

- **differing at all** (threshold 0) is expected to be non-zero. Two different
  rasterisers never agree on an antialiased edge, and this residue scales with
  edge count rather than with anything structural. The oak's run sat at
  0.008%-0.687%.
- **differing strongly** is the signal, and must be **zero**. Any at all means
  the emitter and the writer disagree about geometry, and the blob report says
  which part.

The strong threshold is calibrated rather than picked, because the first value
tried (96) flagged the sunflower's antialiasing as a failure. Measured on that
run, the two populations do not overlap and are not close to it:

- **antialiasing residue** is isolated single pixels — 35 strong pixels across
  33 separate blobs on `SunflowerBloom`, largest blob 2 px — and tops out at a
  delta of **182 of 765**, because the two rasterisers disagree about partial
  coverage of one edge pixel, not about where the edge is.
- **a geometry disagreement** puts an edge a whole pixel over, so it is one
  connected region at close to full contrast. This palette's worst case is a
  dark outline against a pale petal, about **550**.

So the threshold sits at 240: well above the observed residue ceiling and well
below anything structural. The blob report is printed alongside it, because a
threshold alone cannot tell the two apart and the next plant's palette may sit
differently — 40 scattered 1 px blobs are antialiasing whatever the threshold
says, and one 40 px blob is a bug whatever it says.

Two traps this exists to sidestep, both from `fern/NOTES.md`:

- `rive --screenshot` writes an **opaque** background and headless Chrome
  writes a **transparent** one. Diffing them directly makes ~99% of pixels
  differ and hides the answer, so both are composited over the same colour
  first.
- `--advance=0` is load-bearing **on a stage**. At frame 0 every sway key is 0,
  so the artboard sits in exactly the rest pose the SVG describes. At any other
  frame the sway has moved the plant and the diff measures the animation.

And one this run found, which is the same trap wearing a different hat:

- **`--advance=0` applies no data at all**, so on the roots artboard — where
  every level *is* a data-driven blend pose — it renders the authored level-4
  pose whatever `--data=roots=` says. Compared this way all four root levels
  diff against the same picture, and only level 4 passes. The roots artboard
  carries no sway (its animations are the root poses themselves), so it is
  advanced past the 1.2 s smoothing instead. A stage cannot be, which is why
  the two halves of this check use different advances.
"""

import importlib
import os
import subprocess
import sys
from pathlib import Path

HERE = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path.cwd()
NAME = HERE.name
ROOT = HERE.parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "fern"))
import pngdiff  # noqa: E402

SPECIES = getattr(importlib.import_module(f"{NAME}_generator"), NAME.upper())
from plantgen.species import ROOTS_HEIGHT, ROOTS_POSES, STAGES  # noqa: E402

CHROME = (
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
)

# rive's own screenshot background. Compositing both sides over it is what makes
# the two rasterisers comparable at all.
BACKGROUND = (0x1D, 0x1D, 0x1D)

# Above this per-pixel sum-of-channels difference (max 765), a pixel is a real
# disagreement rather than an antialiased edge. See the calibration above.
STRONG = 240

# A strong blob this size or smaller is still edge residue. Printed rather than
# asserted on: the blob shape is evidence for a human, not a second gate.
RESIDUE_BLOB = 4

# Past the 1.2 s roots smoothing, so the blend has actually arrived at the
# level being checked. Safe only because the roots artboard has no sway.
ROOTS_ADVANCE = 120

OUT = HERE / "build" / "svgdiff"


def composite(path: Path) -> tuple:
    """Flatten onto [BACKGROUND], returning (w, h, rgb-bytes).

    Chrome writes RGBA with transparent ground; rive writes opaque. Without
    this the diff is ~99% and says nothing.
    """
    width, height, channels, data = pngdiff.read(str(path))
    out = bytearray(width * height * 3)
    for index in range(width * height):
        source = index * channels
        alpha = data[source + 3] if channels == 4 else 255
        for channel in range(3):
            value = data[source + channel]
            if alpha != 255:
                value = (value * alpha + BACKGROUND[channel] * (255 - alpha)) // 255
            out[index * 3 + channel] = value
    return width, height, bytes(out)


def crop_top(image: tuple, height: int) -> tuple:
    """The roots SVG is a 1024 canvas; its artboard is only the top of it.

    The roots group is translated to y=0 and grows downward, so the artboard's
    520 px is the top of the SVG and nothing is lost by cropping the rest.
    """
    width, full_height, data = image
    if full_height == height:
        return image
    return width, height, data[: width * height * 3]


def blobs(pixels: set) -> list:
    """Connected components, 8-connected, largest first.

    What separates antialiasing from a real disagreement: residue is isolated
    pixels, a moved edge is one connected run.
    """
    remaining = set(pixels)
    found = []
    while remaining:
        blob = [remaining.pop()]
        frontier = list(blob)
        while frontier:
            x, y = frontier.pop()
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    neighbour = (x + dx, y + dy)
                    if neighbour in remaining:
                        remaining.discard(neighbour)
                        blob.append(neighbour)
                        frontier.append(neighbour)
        found.append(blob)
    found.sort(key=len, reverse=True)
    return found


def diff(a: tuple, b: tuple) -> dict:
    """How the two renders differ, and in what shape."""
    width, height, left = a
    width_b, height_b, right = b
    assert (width, height) == (width_b, height_b), (
        f"size mismatch: {width}x{height} vs {width_b}x{height_b}"
    )
    at_all = 0
    worst = 0
    strong = set()
    for index in range(0, len(left), 3):
        delta = (
            abs(left[index] - right[index])
            + abs(left[index + 1] - right[index + 1])
            + abs(left[index + 2] - right[index + 2])
        )
        if delta > 0:
            at_all += 1
            worst = max(worst, delta)
            if delta > STRONG:
                pixel = index // 3
                strong.add((pixel % width, pixel // width))
    clusters = blobs(strong)
    return {
        "at_all": at_all,
        "strong": len(strong),
        "total": width * height,
        "worst": worst,
        "blobs": len(clusters),
        "largest": len(clusters[0]) if clusters else 0,
    }


def render_svg(svg: Path, target: Path) -> None:
    subprocess.run(
        [
            CHROME,
            "--headless",
            f"--screenshot={target}",
            "--window-size=1024,1024",
            "--default-background-color=00000000",
            "--hide-scrollbars",
            f"file://{svg}",
        ],
        capture_output=True,
        check=False,
    )
    if not target.exists():
        sys.exit(f"Chrome wrote no screenshot for {svg}")


def render_riv(artboard: str, target: Path, advance: int, **data) -> None:
    command = [
        "rive",
        ".",
        f"--screenshot={target}",
        f"--artboard={artboard}",
        f"--advance={advance}",
    ]
    for key, value in data.items():
        command.append(f"--data={key}={value}")
    log = subprocess.run(command, capture_output=True, text=True, cwd=HERE)
    assert f"showing {artboard}" in log.stdout + log.stderr, (
        f"{artboard} not shown: {(log.stderr or log.stdout)[-300:]}"
    )


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    prefix = SPECIES.name
    failures = []

    print(f"-- {prefix}: the build against the art it came from --")
    print(
        f"{'pair':40s} {'differ at all':>17s} {'worst':>6s} "
        f"{'strong':>7s} {'blobs':>6s} {'largest':>8s}"
    )

    pairs = []
    for stage in sorted(STAGES):
        label = STAGES[stage]
        pairs.append(
            (
                f"{prefix}{label.capitalize()}",
                HERE / f"{NAME}-stage-{stage}-{label}.svg",
                # A healthy plant at full roots is the pose the SVG is drawn
                # in, and it is also the authored pose — which is what lets
                # this side use advance 0 and so carry no sway.
                {"vitality": 1, "roots": 1},
                1024,
                0,
            )
        )
    # `ROOTS_POSES` is the blend's own table — (percent, level) — so the roots
    # value that poses level N comes from the generator rather than from a
    # second list here that could disagree with it. Level None is the empty
    # pose and has no SVG.
    for percent, level in ROOTS_POSES:
        if level is None:
            continue
        svg = HERE / f"{NAME}-roots-{level}.svg"
        if not svg.exists():
            continue
        pairs.append(
            (
                f"{prefix}Roots",
                svg,
                {"roots": percent / 100},
                ROOTS_HEIGHT,
                ROOTS_ADVANCE,
            )
        )

    for artboard, svg, data, height, advance in pairs:
        stem = svg.stem
        svg_png = OUT / f"{stem}-svg.png"
        riv_png = OUT / f"{stem}-riv.png"
        render_svg(svg, svg_png)
        render_riv(artboard, riv_png, advance, **data)

        measured = diff(
            crop_top(composite(svg_png), height), composite(riv_png)
        )
        ok = measured["strong"] == 0
        if not ok:
            failures.append((stem, measured))
        share = measured["at_all"] / measured["total"]
        print(
            ("  ok  " if ok else " FAIL "),
            f"{stem:38s} {measured['at_all']:7d} ({share:6.3%}) "
            f"{measured['worst']:6d} {measured['strong']:7d} "
            f"{measured['blobs']:6d} {measured['largest']:8d}",
        )

    print(f"\n{len(pairs)} pairs, {len(failures)} with strongly-differing pixels")
    for stem, measured in failures:
        shape = (
            "scattered — looks like edge residue, not geometry"
            if measured["largest"] <= RESIDUE_BLOB
            else "clustered — a part is in the wrong place"
        )
        print(f"  {stem}: {measured['blobs']} blobs, largest "
              f"{measured['largest']} px, worst delta {measured['worst']}/765 "
              f"— {shape}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
