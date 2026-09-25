"""Print textures for the realistic Home icons (system python3 + Pillow).

  python3 textures.py <out_dir>

calendar_page.png, phone_screen.png, map.png, tag_print.png
No text beyond numerals / symbols -> region-neutral.
"""
import math
import os
import random
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

FONT = '/usr/share/fonts/truetype/lato/Lato-Black.ttf'
FONT_B = '/usr/share/fonts/truetype/lato/Lato-Bold.ttf'
TEAL = (11, 122, 123)
TEAL_L = (31, 167, 168)
INK = (36, 40, 46)


def calendar(out):
    W, H = 1000, 800
    im = Image.new('RGB', (W, H), (250, 250, 248))
    d = ImageDraw.Draw(im)
    d.rectangle((0, 0, W, 230), fill=TEAL)
    # subtle darker lower edge of the header (printed band)
    d.rectangle((0, 222, W, 230), fill=(8, 104, 105))
    f = ImageFont.truetype(FONT, 470)
    d.text((W / 2, 520), '25', font=f, fill=INK, anchor='mm')
    # thin rule + 7 small day dots (a week strip) at the bottom
    for i in range(7):
        x = 190 + i * 104
        d.ellipse((x - 9, 720 - 9, x + 9, 720 + 9),
                  fill=TEAL_L if i == 4 else (200, 204, 208))
    im.save(os.path.join(out, 'calendar_page.png'))


def _avatar(im, cx, cy, r, fill, ring=0):
    """Round avatar: coloured disc + white head-and-shoulders, optional white ring."""
    from PIL import ImageChops
    W, H = im.size
    d = ImageDraw.Draw(im)
    if ring:
        d.ellipse((cx - r - ring, cy - r - ring, cx + r + ring, cy + r + ring),
                  fill=(255, 255, 255))
    d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=fill)
    g = Image.new('L', (W, H), 0)
    gd = ImageDraw.Draw(g)
    k = r / 215.0
    gd.ellipse((cx - 80 * k, cy - 150 * k, cx + 80 * k, cy + 10 * k), fill=255)
    gd.ellipse((cx - 170 * k, cy + 45 * k, cx + 170 * k, cy + 340 * k), fill=255)
    m = Image.new('L', (W, H), 0)
    ImageDraw.Draw(m).ellipse((cx - r, cy - r, cx + r, cy + r), fill=255)
    im.paste((255, 255, 255), (0, 0), ImageChops.multiply(g, m))


def phone(out):
    """Contact screen that reads 'for someone else': a large teal person avatar
    with a second, smaller person overlapping it; name bar; action pill."""
    W, H = 720, 1480
    im = Image.new('RGB', (W, H), (246, 247, 248))
    d = ImageDraw.Draw(im)
    d.rectangle((0, 0, W, 120), fill=(238, 241, 242))
    _avatar(im, W // 2 - 40, 540, 235, TEAL)
    _avatar(im, W // 2 + 170, 735, 125, TEAL_L, ring=16)
    d = ImageDraw.Draw(im)
    d.rounded_rectangle((170, 960, 550, 1012), 26, fill=(52, 57, 64))
    d.rounded_rectangle((230, 1050, 490, 1088), 19, fill=(186, 191, 197))
    d.rounded_rectangle((150, 1210, 570, 1330), 60, fill=TEAL)
    d.rounded_rectangle((300, 1258, 420, 1282), 12, fill=(255, 255, 255))
    im.save(os.path.join(out, 'phone_screen.png'))


def city_map(out):
    random.seed(7)
    W, H = 1600, 1200
    im = Image.new('RGB', (W, H), (236, 234, 228))
    d = ImageDraw.Draw(im)
    # blocks
    for x in range(0, W, 120):
        for y in range(0, H, 110):
            c = random.choice([(228, 226, 219), (231, 229, 223), (224, 222, 215)])
            d.rectangle((x + 10, y + 10, x + 112, y + 100), fill=c)
    # park + water
    d.rounded_rectangle((980, 120, 1400, 480), 60, fill=(200, 226, 190))
    d.polygon([(0, 850), (420, 760), (760, 900), (1000, 1200), (0, 1200)],
              fill=(187, 217, 232))
    # roads
    for x in range(0, W, 240):
        d.line((x + 5, 0, x + 5, H), fill=(252, 252, 250), width=16)
    for y in range(0, H, 220):
        d.line((0, y + 5, W, y + 5), fill=(252, 252, 250), width=16)
    d.line((0, 300, W, 620), fill=(250, 222, 150), width=30)   # arterial
    d.line((0, 300, W, 620), fill=(253, 238, 190), width=20)
    # teal route
    pts = [(250, 1000), (250, 580), (730, 580), (730, 380), (1210, 380)]
    d.line(pts, fill=TEAL_L, width=22, joint='curve')
    im = im.filter(ImageFilter.GaussianBlur(0.8))
    im.save(os.path.join(out, 'map.png'))


def tag(out):
    W, H = 600, 1000
    im = Image.new('RGB', (W, H), (240, 230, 212))
    d = ImageDraw.Draw(im)
    f = ImageFont.truetype(FONT, 420)
    d.text((W / 2, 610), '%', font=f, fill=TEAL, anchor='mm')
    im.save(os.path.join(out, 'tag_print.png'))


if __name__ == '__main__':
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    calendar(out)
    phone(out)
    city_map(out)
    tag(out)
