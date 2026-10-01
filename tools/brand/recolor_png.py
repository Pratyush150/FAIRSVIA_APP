#!/usr/bin/env python3
"""Recolour the rider Home tile pictures from RideVela teal to FAIRSVIA blue.

Same hue rule as recolor_lottie.py, teal / cyan / mint (hue 140–200°) ->
blue (200–232°), applied per pixel with saturation, lightness and alpha kept,
so shading and anti-aliased edges survive. Gold is left alone here (the coins
and the star are gold objects). Near-grey pixels never change.

Effectively idempotent: blue is outside the source range (a re-run only
nudges a few dozen anti-aliased edge pixels sitting on the 200° boundary).

    python3 tools/brand/recolor_png.py
"""

from __future__ import annotations

from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2] / "packages/design_system/assets"
DIRS = ["home", "home/2.0x", "home_dark", "home_dark/2.0x"]


def recolor(img: Image.Image) -> tuple[Image.Image, int]:
    np.seterr(divide="ignore", invalid="ignore")  # masked out by np.where
    rgba = np.asarray(img.convert("RGBA")).astype(np.float64) / 255.0
    rgb, a = rgba[..., :3], rgba[..., 3:]
    mx, mn = rgb.max(-1), rgb.min(-1)
    l = (mx + mn) / 2
    d = mx - mn
    s = np.where(d == 0, 0, d / np.where(l > 0.5, 2 - mx - mn, mx + mn + 1e-12))
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    dd = np.where(d == 0, 1, d)
    h = np.select(
        [mx == r, mx == g],
        [((g - b) / dd) % 6, (b - r) / dd + 2],
        (r - g) / dd + 4,
    ) * 60
    mask = (d > 0) & (s >= 0.18) & (h >= 140) & (h <= 200) & (a[..., 0] > 0)
    nh = np.where(mask, 200 + (h - 140) * (32 / 60), h)

    # HSL -> RGB for the masked pixels only.
    c = (1 - np.abs(2 * l - 1)) * s
    hp = nh / 60
    x = c * (1 - np.abs(hp % 2 - 1))
    zeros = np.zeros_like(c)
    seg = np.floor(hp).astype(int) % 6
    r1 = np.choose(seg, [c, x, zeros, zeros, x, c])
    g1 = np.choose(seg, [x, c, c, x, zeros, zeros])
    b1 = np.choose(seg, [zeros, zeros, x, c, c, x])
    m = l - c / 2
    out = np.stack([r1 + m, g1 + m, b1 + m], -1)
    new_rgb = np.where(mask[..., None], out, rgb)
    res = np.concatenate([new_rgb, a], -1)
    return Image.fromarray(np.clip(res * 255 + 0.5, 0, 255).astype(np.uint8), "RGBA"), int(mask.sum())


def main() -> None:
    for d in DIRS:
        for p in sorted((ROOT / d).glob("*.png")):
            img = Image.open(p)
            out, n = recolor(img)
            if n:
                out.save(p, optimize=True)
            print(f"{d}/{p.name:18} {n:7} px")


if __name__ == "__main__":
    main()
