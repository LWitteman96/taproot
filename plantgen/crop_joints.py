#!/usr/bin/env python3
"""Crop a stem joint across the poses, so a person can look at it.

This is deliberately **not** a pass/fail check, and that is a finding rather
than a shortcut. Two automated formulations were tried on the sunflower and
both are wrong:

1. **Sample a disc at the joint's coordinates.** The joint sits at a pivot, and
   every pivot moves as the parts above it rotate — the sunflower's neck travels
   150 px right and 37 px down between vitality 1 and 0. A fixed probe lands off
   the stem at vitality 0 and reports a hole that is really a mis-aimed sample.
2. **Count background enclosed by the plant.** Elegant, coordinate-free, and
   useless here: `OakMature` — art already reviewed and passed — encloses
   35,748-62,596 background pixels depending on pose, because a tree crown
   encloses sky between its foliage masses by design. The signal a real joint
   hole would add is a few hundred pixels inside that.

A correct automated version would compose each joint's transform per pose,
including the per-frame sway rotations read back out of the `Sway` animation.
That is buildable; it is also several steps of bookkeeping where aiming the
probe wrong produces a confident false answer, which is worse than no answer.
So the joints stay a **human appearance check**, exactly as the handoffs ask
("crop the bend and the neck ... and open every image"), and this makes the
crops.

    python3 plantgen/crop_joints.py <project> <artboard> <x,y> [<x,y> ...] [--size 160]

Coordinates are where to centre the window, and the window must cover the
joint's **whole travel** — a joint is at a pivot, and pivots move. The
sunflower's neck goes 150 px right and 37 px down between vitality 1 and 0, so
cropping 180 px about its authored position shows an empty sky at vitality 0.
Centre on the midpoint of the travel and size the window to span it: for that
neck, `598,338 --size 420` rather than `524,320 --size 180`. The bend barely
moves and is fine at its authored position.

The poses are the ones either failure mode shows at:

    vitality 1, 0.5, 0   x   sway frames 1, 75, 150, 225

Look for: a notch in the stem, a light gap where two segments meet, an outline
running across the stem rather than around it, and an outline offset from the
fill it belongs to.
"""

import subprocess
import sys
import zlib
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "fern"))
import pngdiff  # noqa: E402

VITALITIES = ("1", "0.5", "0")
SWAY_FRAMES = (1, 75, 150, 225)
DEFAULT_SIZE = 160


def render(project: Path, artboard: str, target: Path, advance: int, **data):
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


def write_png(path: Path, width: int, height: int, rgb: bytes):
    """Minimal RGB8 PNG writer — the counterpart to pngdiff's reader."""

    def chunk(kind: bytes, body: bytes) -> bytes:
        return (
            len(body).to_bytes(4, "big")
            + kind
            + body
            + zlib.crc32(kind + body).to_bytes(4, "big")
        )

    raw = bytearray()
    for y in range(height):
        raw.append(0)  # filter: none
        raw += rgb[y * width * 3 : (y + 1) * width * 3]
    header = (
        width.to_bytes(4, "big")
        + height.to_bytes(4, "big")
        + bytes([8, 2, 0, 0, 0])
    )
    path.write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", header)
        + chunk(b"IDAT", zlib.compress(bytes(raw), 6))
        + chunk(b"IEND", b"")
    )


def crop(source: Path, target: Path, centre: tuple, size: int):
    width, height, channels, data = pngdiff.read(str(source))
    half = size // 2
    x0 = max(0, min(width - size, int(centre[0]) - half))
    y0 = max(0, min(height - size, int(centre[1]) - half))
    out = bytearray()
    for y in range(y0, y0 + size):
        for x in range(x0, x0 + size):
            offset = (y * width + x) * channels
            out += data[offset : offset + 3]
    write_png(target, size, size, bytes(out))


def main() -> int:
    argv = sys.argv[1:]
    size = DEFAULT_SIZE
    if "--size" in argv:
        index = argv.index("--size")
        size = int(argv[index + 1])
        argv = argv[:index] + argv[index + 2 :]

    project = Path(argv[0]).resolve()
    artboard = argv[1]
    joints = [tuple(float(v) for v in spec.split(",")) for spec in argv[2:]]

    out = project / "build" / "joints"
    out.mkdir(parents=True, exist_ok=True)

    written = []
    for vitality in VITALITIES:
        for frame in SWAY_FRAMES:
            shot = out / f"{artboard}-v{vitality}-f{frame}.png"
            render(project, artboard, shot, frame, vitality=vitality, roots=1)
            for index, centre in enumerate(joints):
                target = out / f"{artboard}-joint{index}-v{vitality}-f{frame}.png"
                crop(shot, target, centre, size)
                written.append(target)

    print(f"{len(written)} crops of {len(joints)} joint(s) on {artboard}, "
          f"{size}x{size} px")
    print(f"in {out}")
    print("\nThis is not a pass/fail check — open them. See the module "
          "docstring for why, and for what to look for.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
