#!/usr/bin/env python3
"""NOT APPLIED to the shipped look (FAIRSVIA ships turquoise since
2026-10-05; the art is the original teal). Kept to re-create the Ocean Blue
alternative.

Recolour the bundled Lottie animations into the FAIRSVIA palette.

The animations came from RideVela in its teal + gold style. FAIRSVIA's look is
"Ocean Blue" with a coral warm accent, so this moves every colour by hue:

  teal / cyan / mint (hue 140–200°)  ->  blue (200–232°)
  gold / amber / yellow (hue 28–62°) ->  coral (2–16°), except in the trophy
                                         and money drawings, where gold is the
                                         object's own colour

Everything else keeps its colour on purpose: green still means done/success,
red still means SOS/danger, and greys/whites/blacks stay neutral. Saturation
and lightness are kept, so highlights and shadows inside each drawing still
read the same. Handles solid fills/strokes (static and keyframed) and gradient
stops.

Idempotent: blue and coral are outside both source ranges, so running it twice
changes nothing.

    python3 tools/brand/recolor_lottie.py            # rewrite in place
    python3 tools/brand/recolor_lottie.py --check    # exit 1 if any teal/gold is left
"""

from __future__ import annotations

import colorsys
import json
import sys
from pathlib import Path

LOTTIE_DIR = Path(__file__).resolve().parents[2] / "packages/design_system/assets/lottie"

# Gold means something in these drawings (a trophy, coins), so only their teal
# moves; everywhere else gold is just the old brand's warm accent.
KEEP_GOLD = {"trophy.json", "money.json"}
_keep_gold = False


def _map_hue(h_deg: float, s: float) -> float | None:
    """New hue in degrees, or None to leave the colour alone."""
    if s < 0.18:  # near-grey: neutral, never brand
        return None
    if 140 <= h_deg <= 200:  # teal/cyan/mint -> blue
        return 200 + (h_deg - 140) * (32 / 60)
    if 28 <= h_deg <= 62 and not _keep_gold:  # gold/amber -> coral
        return 2 + (h_deg - 28) * (14 / 34)
    return None


def _recolor_rgb(r: float, g: float, b: float) -> tuple[float, float, float] | None:
    h, l, s = colorsys.rgb_to_hls(r, g, b)
    nh = _map_hue(h * 360, s)
    if nh is None:
        return None
    return colorsys.hls_to_rgb(nh / 360, l, s)


def _fix_color_list(v: list) -> int:
    """[r,g,b] or [r,g,b,a] in 0..1, in place. Returns 1 if changed."""
    if len(v) < 3 or not all(isinstance(x, (int, float)) for x in v[:3]):
        return 0
    if max(v[:3]) > 1.0:  # 0..255 form (rare in Lottie): normalise round-trip
        r, g, b = (x / 255 for x in v[:3])
        out = _recolor_rgb(r, g, b)
        if out is None:
            return 0
        v[0], v[1], v[2] = (round(x * 255, 4) for x in out)
        return 1
    out = _recolor_rgb(*v[:3])
    if out is None:
        return 0
    v[0], v[1], v[2] = (round(x, 4) for x in out)
    return 1


def _fix_gradient(stops: list, n: int) -> int:
    """Gradient data: n × [offset, r, g, b] then optional opacity stops."""
    changed = 0
    for i in range(n):
        base = i * 4
        if base + 3 >= len(stops):
            break
        rgb = stops[base + 1 : base + 4]
        if _fix_color_list(rgb):
            stops[base + 1 : base + 4] = rgb
            changed += 1
    return changed


def _walk(node, counts: dict) -> None:
    if isinstance(node, dict):
        # Solid colour property: {"c": {"a":0,"k":[r,g,b,a]}} or keyframed.
        c = node.get("c")
        if isinstance(c, dict) and "k" in c:
            k = c["k"]
            if isinstance(k, list) and k and isinstance(k[0], (int, float)):
                counts["solid"] += _fix_color_list(k)
            elif isinstance(k, list):
                for kf in k:
                    if isinstance(kf, dict):
                        for key in ("s", "e"):
                            if isinstance(kf.get(key), list):
                                counts["solid"] += _fix_color_list(kf[key])
        # Gradient: {"g": {"p": n, "k": {"k": [...]}}}
        g = node.get("g")
        if isinstance(g, dict) and isinstance(g.get("p"), int) and isinstance(g.get("k"), dict):
            n = g["p"]
            gk = g["k"].get("k")
            if isinstance(gk, list) and gk and isinstance(gk[0], (int, float)):
                counts["gradient"] += _fix_gradient(gk, n)
            elif isinstance(gk, list):
                for kf in gk:
                    if isinstance(kf, dict):
                        for key in ("s", "e"):
                            if isinstance(kf.get(key), list):
                                counts["gradient"] += _fix_gradient(kf[key], n)
        for v in node.values():
            _walk(v, counts)
    elif isinstance(node, list):
        for v in node:
            _walk(v, counts)


def main() -> int:
    global _keep_gold
    check = "--check" in sys.argv
    total = 0
    for path in sorted(LOTTIE_DIR.glob("*.json")):
        raw = path.read_text()
        data = json.loads(raw)
        _keep_gold = path.name in KEEP_GOLD
        counts = {"solid": 0, "gradient": 0}
        _walk(data, counts)
        n = counts["solid"] + counts["gradient"]
        total += n
        if n and not check:
            path.write_text(json.dumps(data, separators=(",", ":")))
        print(f"{path.name:20} {counts['solid']:4} colours, {counts['gradient']:3} gradient stops"
              + (" (would change)" if check and n else ""))
    if check:
        return 1 if total else 0
    print(f"recoloured {total} colours")
    return 0


if __name__ == "__main__":
    sys.exit(main())
