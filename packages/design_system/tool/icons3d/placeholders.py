#!/usr/bin/env python3
"""Stand-in 'clay' PNGs (Phosphor Fill glyph, gradient + soft shadow) so the
font pipeline can be built and tested before the Blender renders land.
Writes docs/brand/icons3d/png_placeholder/{light,dark}/<name>.png."""
import os
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import icons  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(icons.PKG))
OUT = os.path.join(ROOT, 'docs', 'brand', 'icons3d', 'png_placeholder')
FILL = os.path.join(icons.PKG, 'fonts', 'Phosphor-Fill.ttf')
S = 256


def render(cp, top, bottom):
    font = ImageFont.truetype(FILL, int(S * 0.8))
    mask = Image.new('L', (S, S), 0)
    ImageDraw.Draw(mask).text((S / 2, S / 2), chr(cp), font=font, fill=255, anchor='mm')
    grad = Image.new('RGBA', (S, S))
    px = grad.load()
    for y in range(S):
        t = y / (S - 1)
        c = tuple(round(top[i] * (1 - t) + bottom[i] * t) for i in range(3)) + (255,)
        for x in range(S):
            px[x, y] = c
    shadow = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    sm = mask.filter(ImageFilter.GaussianBlur(8)).point(lambda v: v * 0.35)
    shadow.paste((20, 30, 40, 255), (6, 10), sm)
    out = Image.alpha_composite(Image.new('RGBA', (S, S), (0, 0, 0, 0)), shadow)
    body = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    body.paste(grad, (0, 0), mask)
    return Image.alpha_composite(out, body)


def main():
    for mode, (top, bottom) in {
        'light': ((0x3F, 0xD0, 0xC8), (0xE8, 0x7A, 0x3C)),
        'dark': ((0x7F, 0xE8, 0xE0), (0xFF, 0xA8, 0x60)),
    }.items():
        d = os.path.join(OUT, mode)
        os.makedirs(d, exist_ok=True)
        for _cls, name, cp in icons.load():
            render(cp, top, bottom).save(os.path.join(d, name + '.png'))
    print('placeholders ->', OUT)


if __name__ == '__main__':
    main()
