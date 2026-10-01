#!/usr/bin/env python3
"""Contact sheet: FAIRSVIA glyphs (*) next to Phosphor's own, from the real fonts.

Small sizes are rendered at their true pixel size, then the sheet is scaled
up with nearest-neighbour so each device pixel stays visible (no smoothing
added by the enlargement).

  python3 tool/ridevela_glyphs/contact_sheet.py OUT.png
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
FONTS = os.path.join(os.path.dirname(os.path.dirname(HERE)), "fonts")
COLUMNS = [
    ("car", 0xE112), ("carProfile", 0xE8CC), ("van", 0xE826),
    ("motorcycle", 0xE80A), ("scooter", 0xE820),
    ("autoRickshaw*", 0xF8F0), ("taxi", 0xE902),
    ("money", 0xE588), ("currencyInr", 0xE558), ("creditCard", 0xE1D2),
    ("cashRupee*", 0xF8F2),
]
SIZES = [16, 20, 24, 48]
BGS = [("#FFFFFF", "#17181B"), ("#17181B", "#F2F2F3")]
SCALE = 3


def main(out):
    label = ImageFont.load_default()
    cell = 56
    left = 70
    rows = [(w, s) for w in ("Regular", "Fill") for s in SIZES]
    panel_h = 18 + len(rows) * cell
    width = left + len(COLUMNS) * cell
    img = Image.new("RGB", (width, panel_h * len(BGS)), "white")
    d = ImageDraw.Draw(img)
    fonts = {(w, s): ImageFont.truetype(os.path.join(FONTS, f"Phosphor-{w}.ttf"), s)
             for w in ("Regular", "Fill") for s in SIZES}
    for p, (bg, fg) in enumerate(BGS):
        y0 = p * panel_h
        d.rectangle([0, y0, width, y0 + panel_h], fill=bg)
        for i, (name, _) in enumerate(COLUMNS):
            d.text((left + i * cell, y0 + 3), name[:10], font=label, fill=fg)
        for r, (w, s) in enumerate(rows):
            y = y0 + 18 + r * cell
            d.text((4, y + 4), f"{w} {s}", font=label, fill=fg)
            for i, (_, cp) in enumerate(COLUMNS):
                x = left + i * cell + (48 - s) // 2
                d.text((x, y + (48 - s) // 2), chr(cp), font=fonts[(w, s)], fill=fg)
    img = img.resize((img.width * SCALE, img.height * SCALE), Image.NEAREST)
    img.save(out)
    print("wrote", out, img.size)


if __name__ == "__main__":
    main(sys.argv[1])
