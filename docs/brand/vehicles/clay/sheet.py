"""Contact sheet: light on #FFFFFF and #F5F6F7, dark on #17181B, 64px thumbs.

  python3 sheet.py RENDERDIR OUT.png
"""
import sys
from PIL import Image, ImageDraw

ORDER = ['economy', 'comfort', 'xl', 'premium', 'auto', 'bike', 'driver']
src, out = sys.argv[1], sys.argv[2]
T = 240
rows = [('light', '#FFFFFF'), ('light', '#F5F6F7'), ('dark', '#17181B')]
names = [n for n in ORDER if __import__('os').path.exists(f'{src}/light/{n}.png')]
W = len(names) * T
thumb_h = 64 + 24
TOPH = 2 * (T // 2) + 2 * 72
H = len(rows) * T + 3 * thumb_h + 30 + TOPH
sheet = Image.new('RGB', (W, H), '#FFFFFF')
d = ImageDraw.Draw(sheet)
for r, (mode, bg) in enumerate(rows):
    sheet.paste(Image.new('RGB', (W, T), bg), (0, 30 + r * T))
    for i, n in enumerate(names):
        try:
            im = Image.open(f'{src}/{mode}/{n}.png').convert('RGBA').resize((T, T), Image.LANCZOS)
        except FileNotFoundError:
            continue
        sheet.paste(im, (i * T, 30 + r * T), im)
for i, n in enumerate(names):
    d.text((i * T + 8, 8), n, fill='#333333')
y = 30 + len(rows) * T
for r, (mode, bg) in enumerate(rows):
    sheet.paste(Image.new('RGB', (W, thumb_h), bg), (0, y + r * thumb_h))
    for i, n in enumerate(names):
        try:
            im = Image.open(f'{src}/{mode}/{n}.png').convert('RGBA').resize((64, 64), Image.LANCZOS)
        except FileNotFoundError:
            continue
        sheet.paste(im, (i * T + (T - 64) // 2, y + r * thumb_h + 12), im)
y2 = y + 3 * thumb_h
for r, bg in enumerate(('#E5E7EB', '#1F2227')):
    sheet.paste(Image.new('RGB', (W, T // 2 + 72), bg), (0, y2 + r * (T // 2 + 72)))
    for i, n in enumerate(names):
        p = f'{src}/top/{n}.png'
        if not __import__('os').path.exists(p):
            continue
        im = Image.open(p).convert('RGBA')
        big = im.resize((T // 2, T // 2), Image.LANCZOS)
        sheet.paste(big, (i * T + 10, y2 + r * (T // 2 + 72) + 10), big)
        sm = im.resize((48, 48), Image.LANCZOS)
        sheet.paste(sm, (i * T + T // 2 + 40, y2 + r * (T // 2 + 72) + 40), sm)
sheet.save(out)
