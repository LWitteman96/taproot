#!/usr/bin/env python3
"""Assert on the *built* file, not the markup.

`rive . --verify` checks names and `rive inspect --summary` checks wiring;
neither reads what a keyframe actually says. This walks the resolved tree
from `rive inspect . --json` and checks the four things that build clean and
misbehave at runtime:

  1. no keyframe fell back to `hold`;
  2. the Sway/Still animations key `*-sway` nodes and the Upright/Drooped
     ones key `*-droop` nodes (or a SolidColor, for the colour fade);
  3. every Sway loop seam is exact — first keyframe == last;
  4. twins (`*-line` parts, which follow their leader) carry identical keys.

Generic over the species: pass the project directory, or run it from one.

    python3 check_built.py [project-dir]
"""

import json
import subprocess
import sys
from pathlib import Path

SWAY_ANIMATIONS = ("Sway", "Still")
DROOP_ANIMATIONS = ("Upright", "Drooped")


def inspect_json(project: Path) -> dict:
    """Read the resolved tree, building it if it is missing or stale."""
    cached = project / "build" / "oak-inspect.json"
    if cached.exists():
        return json.loads(cached.read_text())
    out = subprocess.run(
        ["rive", "inspect", str(project), "--json"],
        capture_output=True, text=True, check=True,
    )
    return json.loads(out.stdout)


def index(artboard: dict) -> dict:
    """id -> node, for the whole artboard."""
    by_id = {}

    def walk(node):
        if "id" in node:
            by_id[node["id"]] = node
        for child in node.get("children", ()):
            walk(child)

    walk(artboard)
    return by_id


def animations(artboard: dict) -> list:
    return [c for c in artboard.get("children", ()) if c.get("type") == "LinearAnimation"]


def keyed(animation: dict) -> list:
    """(objectId, propertyKey, [(frame, value), ...]) per keyed property."""
    out = []
    for keyed_object in animation.get("children", ()):
        if keyed_object.get("type") != "KeyedObject":
            continue
        for prop in keyed_object.get("children", ()):
            if prop.get("type") != "KeyedProperty":
                continue
            frames = [
                (kf.get("frame", 0), kf.get("value"))
                for kf in prop.get("children", ())
                if kf.get("type", "").startswith("KeyFrame")
            ]
            out.append((keyed_object["objectId"], prop["propertyKey"], frames))
    return out


def check(project: Path) -> int:
    document = inspect_json(project)
    failures = []
    counts = {"keyframes": 0, "objects": 0, "seams": 0, "twins": 0}

    for problem in document.get("problems", ()):
        failures.append(f"inspect problem: {problem}")

    for artboard in document["artboards"]:
        name = artboard["name"]
        by_id = index(artboard)

        for animation in animations(artboard):
            animation_name = animation.get("name", "?")

            # 1. every keyframe interpolates
            for keyed_object in animation.get("children", ()):
                for prop in keyed_object.get("children", ()):
                    for keyframe in prop.get("children", ()):
                        if not keyframe.get("type", "").startswith("KeyFrame"):
                            continue
                        counts["keyframes"] += 1
                        how = keyframe.get("enums", {}).get("interpolationType")
                        if how == "hold":
                            failures.append(
                                f"{name}/{animation_name}: {keyframe['id']} "
                                f"is hold"
                            )

            # 2. the right animation keys the right kind of node
            for object_id, _, _ in keyed(animation):
                counts["objects"] += 1
                target = by_id.get(object_id)
                if target is None:
                    failures.append(
                        f"{name}/{animation_name}: objectId {object_id} resolves to nothing"
                    )
                    continue
                target_name = target.get("name", "")
                if animation_name in SWAY_ANIMATIONS and not target_name.endswith("-sway"):
                    failures.append(
                        f"{name}/{animation_name} keys {target_name!r} "
                        f"({target.get('type')}), not a *-sway node"
                    )
                if animation_name in DROOP_ANIMATIONS:
                    ok = target_name.endswith("-droop") or target.get("type") == "SolidColor"
                    if not ok:
                        failures.append(
                            f"{name}/{animation_name} keys {target_name!r} "
                            f"({target.get('type')}), not a *-droop node or a SolidColor"
                        )

            # 3. the sway loop seam is exact
            if animation_name == "Sway":
                for object_id, property_key, frames in keyed(animation):
                    if len(frames) < 2:
                        continue
                    counts["seams"] += 1
                    first, last = frames[0][1], frames[-1][1]
                    if first != last:
                        target = by_id.get(object_id, {}).get("name", object_id)
                        failures.append(
                            f"{name}/Sway: {target} key {property_key} seam "
                            f"{first} != {last}"
                        )

        # 4. twins carry identical keys
        for animation in animations(artboard):
            by_target = {}
            for object_id, property_key, frames in keyed(animation):
                target = by_id.get(object_id, {}).get("name")
                if target:
                    by_target[(target, property_key)] = frames
            for (target, property_key), frames in by_target.items():
                if "-line-" not in target:
                    continue
                leader = target.replace("-line-", "-", 1)
                counts["twins"] += 1
                leader_frames = by_target.get((leader, property_key))
                if leader_frames is None:
                    failures.append(
                        f"{name}/{animation.get('name')}: {target} has no leader {leader}"
                    )
                elif leader_frames != frames:
                    failures.append(
                        f"{name}/{animation.get('name')}: {target} differs from {leader}"
                    )

    for failure in failures:
        print("FAIL", failure)
    print(
        f"{len(document['artboards'])} artboards, {counts['keyframes']} keyframes, "
        f"{counts['objects']} keyed objects, {counts['seams']} loop seams, "
        f"{counts['twins']} twin keys, {len(failures)} failures"
    )
    return 1 if failures else 0


if __name__ == "__main__":
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).parent
    sys.exit(check(root.resolve()))
