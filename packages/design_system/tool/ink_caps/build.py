#!/usr/bin/env python3
"""Build fonts/RideVelaCaps-SemiBold.ttf: Inter SemiBold with every lowercase
letter mapped to its capital, for the small-caps section labels of Plan E
("Ink & Paper", THEME=ink).

Why a font and not `text.toUpperCase()`: Inter has no `smcp` feature, and
upper-casing the string would change what a screen reader says and what
widget tests find. With this font the label's text stays "Add a tip"; only
the drawing is in capitals.

Inter is SIL OFL 1.1 with no Reserved Font Name (fonts/Inter-LICENSE.txt), so
a modified copy may be redistributed under the same licence. It is renamed
anyway so it can never be mistaken for Inter itself.

  pip install --user fonttools
  python3 tool/ink_caps/build.py        # from packages/design_system
"""
import os

from fontTools import subset
from fontTools.ttLib import TTFont

PKG = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = os.path.join(PKG, "fonts", "Inter-SemiBold.ttf")
DST = os.path.join(PKG, "fonts", "RideVelaCaps-SemiBold.ttf")
FAMILY = "FAIRSVIA Caps"

# Latin, Latin-1, Latin Extended-A/B, spacing modifiers (Uzbek oʻ gʻ need
# U+02BB), Cyrillic, general punctuation and the currency signs.
RANGES = [(0x20, 0x7E), (0xA0, 0x24F), (0x2B0, 0x2FF), (0x400, 0x4FF),
          (0x2000, 0x206F), (0x20A0, 0x20CF)]


def main():
    font = TTFont(SRC)
    unicodes = [u for a, b in RANGES for u in range(a, b + 1)]
    opts = subset.Options()
    opts.layout_features = ["kern", "cpsp", "case", "tnum", "ccmp", "locl",
                            "mark", "mkmk"]
    opts.name_IDs = ["*"]
    opts.notdef_outline = True
    sub = subset.Subsetter(opts)
    sub.populate(unicodes=unicodes)
    sub.subset(font)

    cmap = font.getBestCmap()
    remap = {}
    for cp in list(cmap):
        up = chr(cp).upper()
        if len(up) == 1 and ord(up) != cp and ord(up) in cmap:
            remap[cp] = cmap[ord(up)]
    for table in font["cmap"].tables:
        if table.isUnicode():
            for cp, g in remap.items():
                if cp in table.cmap:
                    table.cmap[cp] = g

    for rec in font["name"].names:
        if rec.nameID in (1, 16):
            rec.string = FAMILY
        elif rec.nameID == 4:
            rec.string = FAMILY + " SemiBold"
        elif rec.nameID == 6:
            rec.string = "RideVelaCaps-SemiBold"
        elif rec.nameID == 3:
            rec.string = "RideVelaCaps-SemiBold; derived from Inter 4.001"
    font.save(DST)
    print("wrote", DST, "remapped", len(remap))


if __name__ == "__main__":
    main()
