"""Contact sheet: every icon, light on #FFFFFF and dark on #17181B, each at
256 (shown at 96), plus actual-size 40 px and 24 px rows.

  python3 sheet.py [out.png] [name ...]
"""
import json
import os
import sys

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, '..', 'research', 'icons3d-contact.png')
names = sys.argv[2:] or sorted(json.load(open(os.path.join(HERE, 'roles.json')))['icons'])
roles = json.load(open(os.path.join(HERE, 'roles.json')))['icons']
try:
    font = ImageFont.truetype(os.path.join(HERE, '../../../packages/design_system/fonts/Inter-Medium.ttf'), 11)
except OSError:
    font = ImageFont.load_default()

COLS = 10
CELL_W, CELL_H = 124, 176   # 96 preview + 40 + 24 row + label
cols = min(COLS, len(names))
rows = (len(names) + cols - 1) // cols
W = cols * CELL_W
panel_h = rows * CELL_H
sheet = Image.new('RGB', (W * 2 + 20, panel_h + 30), '#DADCE0')
for pi, (mode, bg, fg) in enumerate((('light', '#FFFFFF', '#555'), ('dark', '#17181B', '#aaa'))):
    panel = Image.new('RGB', (W, panel_h), bg)
    dr = ImageDraw.Draw(panel)
    for i, n in enumerate(names):
        p = os.path.join(HERE, 'png', mode, n + '.png')
        if not os.path.exists(p):
            continue
        im = Image.open(p).convert('RGBA')
        x0, y0 = (i % cols) * CELL_W, (i // cols) * CELL_H
        big = im.resize((96, 96), Image.LANCZOS)
        panel.paste(big, (x0 + 14, y0 + 4), big)
        m40 = im.resize((40, 40), Image.LANCZOS)
        m24 = im.resize((24, 24), Image.LANCZOS)
        panel.paste(m40, (x0 + 20, y0 + 104), m40)
        panel.paste(m24, (x0 + 72, y0 + 112), m24)
        dr.text((x0 + 4, y0 + 150), n, fill=fg, font=font)
        dr.text((x0 + 4, y0 + 162), roles[n]['role'], fill=roles[n]['hex'], font=font)
    sheet.paste(panel, (pi * (W + 20), 30))
ImageDraw.Draw(sheet).text((8, 8), 'RideVela 3D clay icons - light (left) / dark (right); each cell: 96px preview, 40px + 24px actual size',
                           fill='#222', font=font)
os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
sheet.save(out)
print(out, sheet.size)
