#!/usr/bin/env python3
"""Build RideVela's Phosphor-style glyphs into the vendored Phosphor fonts.

Phosphor Icons is MIT (fonts/Phosphor-LICENSE.txt). The glyphs defined in
glyphs.py are RideVela's own paths drawn on Phosphor's 256-unit grid.

Each glyph is a list of drawing ops in 256-grid SVG coordinates (y down):
  ("stroke", d)      add the outline of `d` stroked 16 wide, round cap/join
  ("stroke", d, w)   same, with width w
  ("fill", d)        add the filled area of `d` (nonzero)
  ("cut", d)         subtract the filled area of `d`
  ("cutstroke", d, w) subtract `d` stroked w wide
Ops apply in order, so a cut only removes what was added before it.

The result is outlined with skia-pathops, mapped to the font's 1024 em the
same way Phosphor's own glyphs are (x*4, 960 - y*4; checked against `car`,
whose SVG spans y 32..216 and whose glyph spans 832..96), converted to
quadratics and written into both fonts at private-use code points.

  pip install --user fonttools skia-pathops
  python3 tool/ridevela_glyphs/build.py            # from packages/design_system
"""
import os
import sys

import pathops
from fontTools.pens.cu2quPen import Cu2QuPen
from fontTools.pens.recordingPen import RecordingPen
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.pens.areaPen import AreaPen
from fontTools.svgLib.path import parse_path
from fontTools.ttLib import TTFont

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from glyphs import GLYPHS  # noqa: E402

PKG = os.path.dirname(os.path.dirname(HERE))
FONTS = {
    "regular": os.path.join(PKG, "fonts", "Phosphor-Regular.ttf"),
    "fill": os.path.join(PKG, "fonts", "Phosphor-Fill.ttf"),
}


def _path(d):
    p = pathops.Path()
    parse_path(d, p.getPen())
    return p


def _stroked(d, w):
    p = _path(d)
    p.stroke(w, pathops.LineCap.ROUND_CAP, pathops.LineJoin.ROUND_JOIN, 4)
    p.convertConicsToQuads()
    return p


def build_path(ops):
    acc = pathops.Path()
    for op in ops:
        kind, d = op[0], op[1]
        if kind == "stroke":
            acc = pathops.op(acc, _stroked(d, op[2] if len(op) > 2 else 16), pathops.PathOp.UNION)
        elif kind == "fill":
            acc = pathops.op(acc, _path(d), pathops.PathOp.UNION)
        elif kind == "cut":
            acc = pathops.op(acc, _path(d), pathops.PathOp.DIFFERENCE)
        elif kind == "cutstroke":
            acc = pathops.op(acc, _stroked(d, op[2]), pathops.PathOp.DIFFERENCE)
        else:
            raise ValueError(kind)
    acc.simplify()
    return acc


def svg_of(path):
    pen = SVGPathPen(None)
    path.draw(pen)
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" '
        f'fill="currentColor"><path d="{pen.getCommands()}"/></svg>\n'
    )


def tt_glyph(path):
    rec = RecordingPen()
    path.draw(TransformPen(rec, (4, 0, 0, -4, 0, 960)))
    # TrueType wants clockwise outer contours: the y flip reversed skia's
    # winding, so check the total signed area and reverse if needed.
    area = AreaPen()
    rec.replay(area)
    tt = TTGlyphPen(None)
    target = Cu2QuPen(tt, max_err=1.0, reverse_direction=area.value > 0)
    rec.replay(target)
    return tt.glyph()


def main():
    out_svg = os.path.join(HERE, "svg")
    os.makedirs(out_svg, exist_ok=True)
    for weight, font_path in FONTS.items():
        # Phosphor stores padded glyph bboxes (xMin 0 = lsb 0). Recalculating
        # them would move xMin off the hmtx lsb and shift every existing icon
        # sideways in FreeType/Skia, so leave the existing bboxes alone.
        font = TTFont(font_path, recalcBBoxes=False)
        order = font.getGlyphOrder()
        glyf, hmtx = font["glyf"], font["hmtx"]
        for g in GLYPHS:
            name = f"uni{g['codepoint']:04X}"
            path = build_path(g[weight])
            with open(os.path.join(out_svg, f"{g['name']}-{weight}.svg"), "w") as fh:
                fh.write(svg_of(path))
            if name not in glyf:
                order.append(name)
            glyf[name] = tt_glyph(path)
            glyf[name].recalcBounds(glyf)
            hmtx[name] = (1024, glyf[name].xMin)
            for table in font["cmap"].tables:
                if table.isUnicode():
                    table.cmap[g["codepoint"]] = name
        font.setGlyphOrder(order)
        font["maxp"].numGlyphs = len(order)
        font.save(font_path)
        print("wrote", font_path)


if __name__ == "__main__":
    main()
