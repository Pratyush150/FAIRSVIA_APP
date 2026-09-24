"""Step 1: icon manifest + glyph outlines.

  python3 extract.py

Parses packages/design_system/lib/src/theme/phosphor_icons.dart (every
IconData constant in every class), resolves each name to a code point, and
writes the FILL outline (falls back to Regular if the code point is not in
the Fill font) as:
  svg/<name>.svg          - for eyeballing
  glyphs.json             - name -> {cp, source, contours:[[[x,y],...]]}
                            contours are flattened polylines in em units
                            (y up, 0..1 of the 256-grid em), consumed by
                            build.py in Blender.
"""
import json
import os
import re

from fontTools.pens.basePen import BasePen
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.ttLib import TTFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..', '..'))
DART = os.path.join(ROOT, 'packages/design_system/lib/src/theme/phosphor_icons.dart')
FONTS = os.path.join(ROOT, 'packages/design_system/fonts')


class FlatPen(BasePen):
    """Flatten quadratic/cubic segments into polylines."""

    def __init__(self, gs, steps=10):
        super().__init__(gs)
        self.contours, self.cur, self.steps = [], [], steps

    def _moveTo(self, p):
        self.cur = [p]

    def _lineTo(self, p):
        self.cur.append(p)

    def _curveToOne(self, p1, p2, p3):
        p0 = self.cur[-1]
        for i in range(1, self.steps + 1):
            t = i / self.steps
            u = 1 - t
            self.cur.append((u**3 * p0[0] + 3 * u * u * t * p1[0] + 3 * u * t * t * p2[0] + t**3 * p3[0],
                             u**3 * p0[1] + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1] + t**3 * p3[1]))

    def _qCurveToOne(self, p1, p2):
        p0 = self.cur[-1]
        for i in range(1, self.steps + 1):
            t = i / self.steps
            u = 1 - t
            self.cur.append((u * u * p0[0] + 2 * u * t * p1[0] + t * t * p2[0],
                             u * u * p0[1] + 2 * u * t * p1[1] + t * t * p2[1]))

    def _closePath(self):
        c = self.cur
        if len(c) > 1 and abs(c[0][0] - c[-1][0]) < 1e-6 and abs(c[0][1] - c[-1][1]) < 1e-6:
            c = c[:-1]
        # drop zero-length segments (Phosphor has degenerate on-curve runs,
        # e.g. chatCircle starts with 5 identical points) - Blender's curve
        # fill silently produces nothing for such a spline
        d = []
        for p in c:
            if not d or abs(p[0] - d[-1][0]) + abs(p[1] - d[-1][1]) > 0.05:
                d.append(p)
        if len(d) > 1 and abs(d[0][0] - d[-1][0]) + abs(d[0][1] - d[-1][1]) <= 0.05:
            d.pop()
        d = despike(d)
        if len(d) >= 3:
            self.contours.append(d)
        self.cur = []

    _endPath = _closePath


def despike(c, max_len=12.0):
    """Remove short back-tracking spurs (e.g. chatCircle's 'Q.. 314 82 L316 81'
    tail notch). They make the outline self-intersect and Blender's 2D curve
    fill then renders nothing (chatCircle) or only a fragment."""
    import math
    changed = True
    while changed and len(c) > 3:
        changed = False
        for i in range(len(c)):
            a, b, n = c[i - 1], c[i], c[(i + 1) % len(c)]
            v1 = (b[0] - a[0], b[1] - a[1])
            v2 = (n[0] - b[0], n[1] - b[1])
            l1, l2 = math.hypot(*v1), math.hypot(*v2)
            if l1 == 0 or l2 == 0:
                c.pop(i); changed = True; break
            cos = (v1[0] * v2[0] + v1[1] * v2[1]) / (l1 * l2)
            if cos < -0.5 and min(l1, l2) < max_len:
                c.pop(i); changed = True; break
    return c


def self_intersections(c):
    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])
    n, hits = len(c), 0
    for i in range(n):
        p1, p2 = c[i], c[(i + 1) % n]
        for j in range(i + 2, n):
            if i == 0 and j == n - 1:
                continue
            q1, q2 = c[j], c[(j + 1) % n]
            if (cross(p1, p2, q1) * cross(p1, p2, q2) < 0 and
                    cross(q1, q2, p1) * cross(q1, q2, p2) < 0):
                hits += 1
    return hits


# Icons the app needs that are not (yet) constants in phosphor_icons.dart;
# code points verified by drawing them from both fonts.
EXTRA = {'arrowLeft': 0xe058, 'arrowRight': 0xe06c, 'caretLeft': 0xe138}


def manifest():
    src = open(DART).read()
    names = dict(EXTRA)
    for m in re.finditer(r"static const IconData (\w+) = IconData\((0x[0-9a-fA-F]+)", src):
        n, cp = m.group(1), int(m.group(2), 16)
        if n in names and names[n] != cp:
            raise SystemExit('name %s has two code points' % n)
        names[n] = cp
    return names


def main():
    fill = TTFont(os.path.join(FONTS, 'Phosphor-Fill.ttf'))
    reg = TTFont(os.path.join(FONTS, 'Phosphor-Regular.ttf'))
    upm = fill['head'].unitsPerEm
    out = {}
    for name, cp in sorted(manifest().items()):
        font, srcname = fill, 'fill'
        if cp not in font.getBestCmap():
            font, srcname = reg, 'regular'
        gs = font.getGlyphSet()
        g = font.getBestCmap()[cp]
        fp = FlatPen(gs)
        gs[g].draw(fp)
        # Regular outline too: the quiet 'chrome' role (carets, arrows, x,
        # list, dots) is modelled from the stroke weight, not the solid Fill
        rp = FlatPen(reg.getGlyphSet())
        reg.getGlyphSet()[reg.getBestCmap()[cp]].draw(rp)
        sp = SVGPathPen(gs)
        gs[g].draw(sp)
        with open(os.path.join(HERE, 'svg', name + '.svg'), 'w') as f:
            f.write('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 -%d %d %d">'
                    '<path transform="scale(1,-1)" d="%s"/></svg>\n' % (upm - 64, upm, upm, sp.getCommands()))
        # em box: Phosphor draws on y in [-64, 960] (1024 upm) -> normalise to 0..1
        bad = sum(self_intersections(c) for c in fp.contours)
        if bad:
            print('WARN self-intersecting outline', name, bad)
        out[name] = {'cp': cp, 'source': srcname,
                     'contours': [[[round(x / upm, 5), round((y + 64) / upm, 5)] for x, y in c]
                                  for c in fp.contours],
                     'contours_regular': [[[round(x / upm, 5), round((y + 64) / upm, 5)] for x, y in c]
                                          for c in rp.contours]}
    json.dump(out, open(os.path.join(HERE, 'glyphs.json'), 'w'))
    print(len(out), 'glyphs;', sum(v['source'] == 'regular' for v in out.values()), 'from Regular')


if __name__ == '__main__':
    main()
