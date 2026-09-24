#!/usr/bin/env python3
"""Build the Plan G ("3D Clay", THEME=clay3d) colour-bitmap icon fonts.

Every Phosphor code point the apps use (PhosphorIconsRegular + Fill, see
icons.py) gets a glyph whose picture is the Blender-rendered 3D icon
docs/brand/icons3d/png/<mode>/<name>.png. Call sites stay `Icon(Phosphor…)`:
under THEME=clay3d the IconData constants name the family 'Phosphor3D'.

One TTF carries the same PNGs twice:
  * CBDT/CBLC (format 17, small metrics + PNG) — what FreeType/Skia render on
    Android, Linux and the flutter_tester (Noto Color Emoji's format);
  * sbix — what CoreText (iOS/macOS) renders.
There is deliberately no glyf table: FreeType only uses bitmap strikes (and
Skia only scales them to the requested size) when the face is not scalable —
exactly how Noto Color Emoji is built.

Metrics copy Phosphor (1024 em, ascent 960, descent 64) so a 3D glyph sits
in exactly the box the line icon did. One strike at 128 ppem, bitmap 128x128
covering the whole em (top at the ascender, bottom at the descender).

  python3 tool/icons3d/build.py                 # from packages/design_system
  python3 tool/icons3d/build.py --src png_placeholder
Writes fonts/Phosphor3D.ttf (light set) and assets/icons3d/Phosphor3DDark.ttf (dark
set; an asset, not a font family: AppClay3D.useIconSetFor registers it
over 'Phosphor3D' at run time when the app is dark — see app_clay3d.dart).
"""
import argparse
import io
import os
import sys

from fontTools import ttLib
from fontTools.fontBuilder import FontBuilder
from fontTools.ttLib.tables.BitmapGlyphMetrics import SmallGlyphMetrics
from fontTools.ttLib.tables.C_B_D_T_ import cbdt_bitmap_format_17
from fontTools.ttLib.tables.E_B_L_C_ import (
    SbitLineMetrics, Strike as CblcStrike, eblc_index_sub_table_1)
from fontTools.ttLib.tables.sbixGlyph import Glyph as SbixGlyph
from fontTools.ttLib.tables.sbixStrike import Strike as SbixStrike
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import icons  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(icons.PKG))
UPM, ASC, DESC = 1024, 960, -64
PPEM = 128


def png_bytes(path):
    """128x128 RGBA PNG."""
    im = Image.open(path).convert('RGBA')
    if im.size != (PPEM, PPEM):
        # Fit inside the em, keeping aspect.
        im.thumbnail((PPEM, PPEM), Image.LANCZOS)
        canvas = Image.new('RGBA', (PPEM, PPEM), (0, 0, 0, 0))
        canvas.paste(im, ((PPEM - im.width) // 2, (PPEM - im.height) // 2))
        im = canvas
    # Full RGBA, no palette quantising: a quantised palette gave every
    # transparent pixel alpha 2 and banded the soft ground shadow, which read
    # as a faint box behind the icon on tinted surfaces. Fully transparent
    # pixels are zeroed so they compress to nothing.
    px = im.load()
    for y in range(im.height):
        for x in range(im.width):
            if px[x, y][3] == 0:
                px[x, y] = (0, 0, 0, 0)
    buf = io.BytesIO()
    im.save(buf, 'PNG', optimize=True)
    return buf.getvalue()


def build(src_dir, family, out_path):
    cps = icons.by_codepoint()
    order = sorted(cps)
    glyph_names = ['.notdef'] + ['u%04X' % cp for cp in order]
    images = {}
    missing = []
    for cp in order:
        for name in cps[cp]:
            p = os.path.join(src_dir, name + '.png')
            if os.path.exists(p):
                images['u%04X' % cp] = png_bytes(p)
                break
        else:
            # Not rendered yet: the flat stand-in (placeholders.py), loudly.
            ph = os.path.join(ROOT, 'docs', 'brand', 'icons3d', 'png_placeholder',
                              os.path.basename(src_dir), cps[cp][0] + '.png')
            if os.path.exists(ph):
                print('WARNING: no 3D render for %s, using placeholder' % cps[cp][0])
                images['u%04X' % cp] = png_bytes(ph)
            else:
                missing.append(cps[cp][0])
    if missing:
        raise SystemExit('missing PNGs in %s: %s' % (src_dir, ', '.join(missing)))

    fb = FontBuilder(UPM, isTTF=True)
    fb.setupGlyphOrder(glyph_names)
    fb.setupCharacterMap({cp: 'u%04X' % cp for cp in order})
    fb.setupHorizontalMetrics({g: (UPM, 0) for g in glyph_names})
    fb.setupHorizontalHeader(ascent=ASC, descent=DESC)
    fb.setupOS2(sTypoAscender=ASC, sTypoDescender=DESC, sTypoLineGap=0,
                usWinAscent=ASC, usWinDescent=-DESC, fsType=0)
    fb.setupNameTable({'familyName': family, 'styleName': 'Regular'})
    fb.setupPost()
    font = fb.font
    font['head'].indexToLocFormat = 0
    # No outlines: maxp 0.5 (CFF-style) — the face is bitmap-only.
    maxp = ttLib.newTable('maxp')
    maxp.tableVersion = 0x00005000
    maxp.numGlyphs = len(glyph_names)
    font['maxp'] = maxp
    font['head'].xMin, font['head'].yMin = 0, DESC
    font['head'].xMax, font['head'].yMax = UPM, ASC

    names = glyph_names[1:]
    bearing_y = round(ASC * PPEM / UPM)  # 120: bitmap top on the ascender

    # --- CBDT / CBLC -------------------------------------------------------
    cbdt, cblc = ttLib.newTable('CBDT'), ttLib.newTable('CBLC')
    cbdt.version = cblc.version = 3.0
    data = {}
    for g in names:
        bd = cbdt_bitmap_format_17(b'', None)
        m = SmallGlyphMetrics()
        m.width = m.height = PPEM
        m.BearingX, m.BearingY, m.Advance = 0, bearing_y, PPEM
        bd.metrics, bd.imageData = m, images[g]
        data[g] = bd
    strike = CblcStrike()
    bst = strike.bitmapSizeTable
    bst.startGlyphIndex, bst.endGlyphIndex = 1, len(names)
    bst.ppemX = bst.ppemY = PPEM
    bst.colorRef, bst.bitDepth, bst.flags = 0, 32, 1
    lm = SbitLineMetrics()
    for k in ('caretSlopeNumerator', 'caretSlopeDenominator', 'caretOffset',
              'minOriginSB', 'minAdvanceSB', 'maxBeforeBL', 'minAfterBL',
              'pad1', 'pad2'):
        setattr(lm, k, 0)
    lm.ascender, lm.descender, lm.widthMax = bearing_y, bearing_y - PPEM, PPEM
    bst.hori = bst.vert = lm
    sub = eblc_index_sub_table_1(b'', font)
    sub.indexFormat, sub.imageFormat, sub.imageSize = 1, 17, PPEM
    sub.names = names
    off, locs = 4, []
    for g in names:
        end = off + 9 + len(images[g])
        locs.append((off, end))
        off = end
    sub.locations = locs
    strike.indexSubTables = [sub]
    cblc.strikes, cbdt.strikeData = [strike], [data]
    font['CBDT'], font['CBLC'] = cbdt, cblc

    # --- sbix (iOS / CoreText) -------------------------------------------
    sbix = ttLib.newTable('sbix')
    s = SbixStrike()
    s.ppem, s.resolution = PPEM, 72
    for g in names:
        s.glyphs[g] = SbixGlyph(graphicType='png ', glyphName=g,
                                imageData=images[g], originOffsetX=0,
                                originOffsetY=round(DESC * PPEM / UPM))
    sbix.strikes[PPEM] = s
    font['sbix'] = sbix

    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    font.save(out_path)
    # Round-trip: fontTools must read back both tables.
    chk = ttLib.TTFont(out_path)
    assert len(chk['CBLC'].strikes[0].indexSubTables[0].names) == len(names)
    assert len(chk['sbix'].strikes[PPEM].glyphs) == len(names) + 1 or \
        len(chk['sbix'].strikes[PPEM].glyphs) >= len(names)
    print('%s: %d glyphs, %.1f KB' % (out_path, len(names), os.path.getsize(out_path) / 1024))


# Hero art (rider live-ride / completed sheets): hero name -> icon render.
HEROES = {
    'add_stop': 'mapPinPlus',
    'prebook': 'calendarCheck',
    'done': 'checkCircle',
    'cash': 'money',
}


def copy_heroes(base):
    import shutil
    for mode, folder in (('light', 'clay3d'), ('dark', 'clay3d_dark')):
        out = os.path.join(icons.PKG, 'assets', 'heroes', folder)
        os.makedirs(out, exist_ok=True)
        for hero, icon in HEROES.items():
            im = Image.open(os.path.join(base, mode, icon + '.png')).convert('RGBA')
            im.thumbnail((256, 256), Image.LANCZOS)
            im.save(os.path.join(out, hero + '.png'), optimize=True)
    print('heroes ->', os.path.join(icons.PKG, 'assets', 'heroes', 'clay3d{,_dark}'))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--src', default='png', help='folder under docs/brand/icons3d')
    a = ap.parse_args()
    base = os.path.join(ROOT, 'docs', 'brand', 'icons3d', a.src)
    build(os.path.join(base, 'light'), 'Phosphor3D',
          os.path.join(icons.PKG, 'fonts', 'Phosphor3D.ttf'))
    build(os.path.join(base, 'dark'), 'Phosphor3DDark',
          os.path.join(icons.PKG, 'assets', 'icons3d', 'Phosphor3DDark.ttf'))
    copy_heroes(base)


if __name__ == '__main__':
    main()
