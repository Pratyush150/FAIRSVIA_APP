#!/usr/bin/env bash
# Render the realistic Home icon set.
#   ./run.sh <out_dir> [samples] [keys...]      then: python3 export.py <out_dir> --install
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
BL=${BLENDER:-/home/nova-robotics/tools/blender/blender}
OUT=${1:?out dir}; SAMPLES=${2:-384}; shift 2 || true
KEYS=${*:-ride prebook someone_else saved add_stop coins star tag}
mkdir -p "$OUT"
export RV_TEX=${RV_TEX:-$HOME/.cache/ridevela-3d/tex}
python3 "$HERE/textures.py" "$RV_TEX"
for k in $KEYS; do
  echo "== $k"
  "$BL" -b --factory-startup -P "$HERE/render_all.py" -- "$k" "$OUT" "$SAMPLES" 2>&1 \
    | grep -E "Error|Traceback|File \"|^Time:" || true
done
