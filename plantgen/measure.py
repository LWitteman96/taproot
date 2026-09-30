#!/usr/bin/env python3
"""Where did the plant actually move? Centroids, for the direction checks.

`check_render.py` answers *did the picture change* and by how many pixels. It
cannot answer **which way**, and every plant has a direction the art intends:
the stability lean tips left or right by species, a drooping head swings to one
side, a spray splays outward rather than collapsing inward. A pixel count is the
same either way, so those claims need a coordinate.

Two measurements, both over a colour selection so they follow one part rather
than the whole plant:

    python3 plantgen/measure.py centroid <project> <artboard> <colour> [--data k=v ...]
    python3 plantgen/measure.py shift <project> <artboard> <colour> <k=a> <k=b> [--data ...]

`centroid` prints one (x, y) and the pixel count. `shift` renders twice, with
the named datum at `a` then `b`, and prints the movement between them — which is
the form the direction checks want.

The colour is a hex `RRGGBB` plus an optional `/tolerance` (default 40, as a
sum-of-channels distance). Anti-aliased edge pixels fall outside it, which is
what keeps a centroid from drifting toward whatever the part is drawn against.

Prefix it with `!` to invert the selection: `!1D1D1D` is everything that is not
the background, which is *the plant* — the right selection for a whole-plant
claim like "it tips right". Tracking a named part instead answers a narrower
question, and one that a part near the lean's pivot cannot answer at all, since
nothing at the pivot moves however far the plant tips.
"""

import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "fern"))
import pngdiff  # noqa: E402


def parse_colour(text: str) -> tuple:
    """(rgb, tolerance, invert)."""
    invert = text.startswith("!")
    body, _, tolerance = text.lstrip("!").partition("/")
    body = body.lstrip("#")
    rgb = tuple(int(body[i : i + 2], 16) for i in (0, 2, 4))
    return rgb, int(tolerance) if tolerance else 40, invert


def render(project: Path, artboard: str, target: Path, advance: int, data: dict):
    command = [
        "rive",
        ".",
        f"--screenshot={target}",
        f"--artboard={artboard}",
        f"--advance={advance}",
    ]
    for key, value in data.items():
        command.append(f"--data={key}={value}")
    log = subprocess.run(command, capture_output=True, text=True, cwd=project)
    assert f"showing {artboard}" in log.stdout + log.stderr, (
        f"{artboard} not shown: {(log.stderr or log.stdout)[-300:]}"
    )


def centroid(path: Path, colour: tuple, tolerance: int, invert: bool) -> tuple:
    """(x, y, count) over the pixels matching [colour], or not matching it."""
    width, height, channels, data = pngdiff.read(str(path))
    total_x = total_y = count = 0
    for index in range(width * height):
        source = index * channels
        distance = (
            abs(data[source] - colour[0])
            + abs(data[source + 1] - colour[1])
            + abs(data[source + 2] - colour[2])
        )
        if (distance > tolerance) if invert else (distance <= tolerance):
            total_x += index % width
            total_y += index // width
            count += 1
    if not count:
        return None, None, 0
    return total_x / count, total_y / count, count


def extra_data(argv: list) -> tuple:
    """Split trailing `--data k=v` pairs off the positional arguments."""
    data = {}
    rest = []
    index = 0
    while index < len(argv):
        if argv[index] == "--data":
            key, _, value = argv[index + 1].partition("=")
            data[key] = value
            index += 2
        elif argv[index].startswith("--advance="):
            data["__advance"] = argv[index].split("=", 1)[1]
            index += 1
        else:
            rest.append(argv[index])
            index += 1
    return rest, data


def main() -> int:
    mode = sys.argv[1]
    rest, data = extra_data(sys.argv[2:])
    # 60 frames in: past nothing in particular, but the same frame the A/B
    # checks use, so a centroid is comparable with a pixel count from those.
    advance = int(data.pop("__advance", 60))

    project = Path(rest[0]).resolve()
    artboard = rest[1]
    colour, tolerance, invert = parse_colour(rest[2])
    out = project / "build" / "measure"
    out.mkdir(parents=True, exist_ok=True)

    if mode == "centroid":
        shot = out / f"{artboard}-centroid.png"
        render(project, artboard, shot, advance, data)
        x, y, count = centroid(shot, colour, tolerance, invert)
        if not count:
            print(f"no pixels within {tolerance} of {rest[2]}")
            return 1
        print(f"{artboard}: centroid ({x:.1f}, {y:.1f}) over {count} px")
        return 0

    if mode == "shift":
        key_a, _, value_a = rest[3].partition("=")
        key_b, _, value_b = rest[4].partition("=")
        assert key_a == key_b, "shift compares one datum at two values"
        results = {}
        for label, value in (("a", value_a), ("b", value_b)):
            shot = out / f"{artboard}-{key_a}-{value}.png"
            render(project, artboard, shot, advance, {**data, key_a: value})
            results[label] = centroid(shot, colour, tolerance, invert)
        (ax, ay, an), (bx, by, bn) = results["a"], results["b"]
        if not an or not bn:
            print(f"no pixels within {tolerance} of {rest[2]} "
                  f"({an} then {bn})")
            return 1
        print(f"{artboard}, {key_a} {value_a} -> {value_b}:")
        print(f"  centroid ({ax:.1f}, {ay:.1f}) -> ({bx:.1f}, {by:.1f})")
        print(f"  moves x {bx - ax:+.1f} px, y {by - ay:+.1f} px "
              f"({an} -> {bn} px matched)")
        return 0

    print(__doc__)
    return 1


if __name__ == "__main__":
    sys.exit(main())
