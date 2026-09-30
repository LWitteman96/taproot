#!/usr/bin/env bash
# Render every stage at every vitality into build/preview/.
#
#   ./preview.sh                          all 5 stages x 5 vitalities
#   STAGES="Mature Bloom" ./preview.sh    just those two
#   VITALITIES="1 0" ./preview.sh         just the ends
#   FRAME=150 ./preview.sh                sample a different point in the sway
#   VIEWPORT=384x384 ./preview.sh         smaller, faster stills
#
# Names are validated against the built file first, because `rive --artboard`
# falls back to the default artboard on an unknown name without saying so.
set -euo pipefail
cd "$(dirname "$0")"

STAGES=${STAGES:-"Sprout Seedling Young Mature Bloom"}
VITALITIES=${VITALITIES:-"1 0.75 0.5 0.25 0"}
FRAME=${FRAME:-60}
OUT=${OUT:-build/preview}

known=$(rive inspect . --summary | python3 -c \
  'import json,sys; print(" ".join(a["name"] for a in json.load(sys.stdin)["artboards"]))')
for s in $STAGES; do
  case " $known " in
    *" Fern$s "*) ;;
    *) echo "no artboard Fern$s; have: $known" >&2; exit 1 ;;
  esac
done

mkdir -p "$OUT"   # rive writes nothing, and says nothing, if the directory is missing
for s in $STAGES; do
  for v in $VITALITIES; do
    # rive logs to stderr; keep it quiet but show everything if a render fails
    if ! log=$(rive . --screenshot="$OUT/$s-v$v.png" --artboard="Fern$s" \
                      --data=vitality="$v" --advance="$FRAME" \
                      ${VIEWPORT:+--viewport=$VIEWPORT} 2>&1); then
      echo "$log" >&2; exit 1
    fi
    echo "  $OUT/$s-v$v.png"
  done
done
echo "$OUT/"
