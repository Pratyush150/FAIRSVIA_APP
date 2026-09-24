"""Turn render_ink.py passes into the Plan E ("Ink & Paper") app assets.

  python3 export_ink.py RENDERDIR ASSETDIR [SHEET.png]

For each vehicle: region boundaries are traced from the flat ID pass (glass,
lamps, grille, door shut lines, tyres live in the clay *shader*), unioned with
the Freestyle strokes, and drawn over flat fills:

  paper -> paper colour   glass -> pale wash   dark -> solid ink
  shade -> mid-tone wash (large black panels, e.g. the auto's body)

Writes (ASSETDIR = packages/design_system/assets/vehicles):
  ink/<v>.png 256 + ink/2.0x/<v>.png 512            3/4 view, light mode
  ink_dark/<v>.png 256 + ink_dark/2.0x/<v>.png 512  3/4 view, dark mode
  ink_top/<v>.png 128 + ink_top/2.0x/<v>.png 256    top-down map marker
Transparent outside the silhouette; the fill makes each drawing opaque so it
reads over a map or a tinted row. SHEET, if given, is a contact sheet.
"""
import json
import os
import sys

import numpy as np
from PIL import Image, ImageFilter

src, dst = sys.argv[1], sys.argv[2]
sheet_path = sys.argv[3] if len(sys.argv) > 3 else None


def rgb(h):
    h = h.lstrip('#')
    return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)], dtype=np.float32)


PALETTES = {
    # line, paper, glass, dark (solid ink parts)
    'ink': dict(line='#0B0B0C', paper='#FFFFFF', glass='#E4E4DE', dark='#0B0B0C',
                shade='#B4B4AE'),
    'ink_dark': dict(line='#F4F3EE', paper='#1D1D1B', glass='#34342F', dark='#050505',
                     shade='#050505'),
    'ink_top': dict(line='#0B0B0C', paper='#FFFFFF', glass='#DCDCD5', dark='#0B0B0C',
                    shade='#B4B4AE'),
}
# Region-line width in px at the 1024 pass (matches render_ink.THICK).
WIDTH = {'side': 6, 'top': 14}


def disk(r):
    y, x = np.ogrid[-r:r + 1, -r:r + 1]
    return (x * x + y * y) <= r * r + 0.5


def dilate(mask, width):
    im = Image.fromarray((mask * 255).astype(np.uint8))
    # MaxFilter needs an odd size; a square is fine once blurred slightly.
    size = max(3, int(round(width)) | 1)
    return np.asarray(im.filter(ImageFilter.MaxFilter(size))) / 255.0


def labels(idpath, roles):
    im = np.asarray(Image.open(idpath).convert('RGBA')).astype(np.float32)
    alpha = im[..., 3] / 255.0
    keys = list(roles.keys())
    cols = np.stack([rgb(k) for k in keys])  # K x 3
    d = ((im[..., None, :3] - cols[None, None]) ** 2).sum(-1)
    lab = d.argmin(-1) + 1
    lab[alpha < 0.5] = 0
    role = np.array(['none'] + [roles[k] for k in keys])[lab]
    return lab, role, alpha


def trace(lab):
    e = np.zeros(lab.shape, bool)
    e[:, :-1] |= lab[:, :-1] != lab[:, 1:]
    e[:-1, :] |= lab[:-1, :] != lab[1:, :]
    return e.astype(np.float32)


def compose(view, v, pal):
    d = os.path.join(src, view)
    roles = json.load(open(os.path.join(d, v + '_roles.json')))
    lab, role, alpha = labels(os.path.join(d, v + '_id.png'), roles)
    region = dilate(trace(lab), WIDTH[view] - 1)
    li = np.asarray(Image.open(os.path.join(d, v + '_line.png')).convert('RGBA')).astype(np.float32)
    # Freestyle ink = darkness of the line pass (white surfaces, black ink).
    fs = (1 - li[..., :3].mean(-1) / 255.0) * (li[..., 3] / 255.0)
    ink = np.clip(np.maximum(region, fs), 0, 1)
    ink = np.asarray(Image.fromarray((ink * 255).astype(np.uint8))
                     .filter(ImageFilter.GaussianBlur(0.9))) / 255.0
    P = {k: rgb(c) for k, c in pal.items()}
    fill = np.empty(lab.shape + (3,), np.float32)
    fill[:] = P['paper']
    fill[role == 'glass'] = P['glass']
    fill[role == 'dark'] = P['dark']
    fill[role == 'shade'] = P['shade']
    # Silhouette alpha from the (hard) ID pass, softened like the lines.
    sil = np.asarray(Image.fromarray((alpha * 255).astype(np.uint8))
                     .filter(ImageFilter.GaussianBlur(0.9))) / 255.0
    out_a = np.maximum(sil, ink)
    col = fill * (1 - ink[..., None]) + P['line'] * ink[..., None]
    # Where only the line exists (outside the silhouette) colour is pure line.
    col = np.where((sil < 0.01)[..., None], P['line'], col)
    rgba = np.dstack([col, out_a * 255]).clip(0, 255).astype(np.uint8)
    img = Image.fromarray(rgba, 'RGBA')
    if view == 'top':
        img = marker(img)
    return img


def marker(img):
    """Map marker: a paper halo outside the ink line and a faint soft
    shadow down-right, so the drawing reads on any map tile."""
    A = img.getchannel('A')
    halo = Image.new('RGBA', img.size, (255, 255, 255, 0))
    halo.putalpha(A.filter(ImageFilter.MaxFilter(13)).filter(ImageFilter.GaussianBlur(1.2)))
    sh = Image.new('RGBA', img.size, (10, 10, 12, 0))
    sh.putalpha(A.filter(ImageFilter.MaxFilter(9)).filter(ImageFilter.GaussianBlur(16))
                .point(lambda v: int(v * 0.35)))
    out = Image.new('RGBA', img.size, (0, 0, 0, 0))
    out.alpha_composite(sh, (12, 18))
    out.alpha_composite(halo)
    out.alpha_composite(img)
    return out


def vehicles(view):
    d = os.path.join(src, view)
    return sorted(f[:-len('_id.png')] for f in os.listdir(d) if f.endswith('_id.png'))


def save(img, folder, name, size1x):
    base = os.path.join(dst, folder)
    os.makedirs(os.path.join(base, '2.0x'), exist_ok=True)
    img.resize((size1x * 2, size1x * 2), Image.LANCZOS).save(
        os.path.join(base, '2.0x', name + '.png'), optimize=True)
    img.resize((size1x, size1x), Image.LANCZOS).save(
        os.path.join(base, name + '.png'), optimize=True)


made = {}
for view, sets in (('side', ('ink', 'ink_dark')), ('top', ('ink_top',))):
    if not os.path.isdir(os.path.join(src, view)):
        continue
    for v in vehicles(view):
        for s in sets:
            img = compose(view, v, PALETTES[s])
            made[(s, v)] = img
            if dst != '-':
                save(img, s, v, 256 if view == 'side' else 128)

if sheet_path:
    # Rows: light 3/4 at 1x and 2x on paper, dark 3/4 on ink, markers on a
    # grey map tone at the size they are drawn in the app.
    names = sorted({v for (_, v) in made})
    cell = 200
    W = cell * len(names)
    sheet = Image.new('RGBA', (W, cell * 4), (250, 250, 247, 255))
    dark_band = Image.new('RGBA', (W, cell), (10, 10, 10, 255))
    sheet.alpha_composite(dark_band, (0, cell * 2))
    map_band = Image.new('RGBA', (W, cell), (226, 228, 224, 255))
    sheet.alpha_composite(map_band, (0, cell * 3))
    for i, v in enumerate(names):
        x = i * cell
        if ('ink', v) in made:
            sheet.alpha_composite(made[('ink', v)].resize((cell, cell), Image.LANCZOS), (x, 0))
            small = made[('ink', v)].resize((96, 96), Image.LANCZOS)
            sheet.alpha_composite(small, (x + 52, cell + 52))
        if ('ink_dark', v) in made:
            sheet.alpha_composite(made[('ink_dark', v)].resize((cell, cell), Image.LANCZOS), (x, cell * 2))
        if ('ink_top', v) in made:
            m = made[('ink_top', v)].resize((48, 48), Image.LANCZOS)
            sheet.alpha_composite(m, (x + 40, cell * 3 + 76))
            m2 = made[('ink_top', v)].resize((96, 96), Image.LANCZOS)
            sheet.alpha_composite(m2, (x + 96, cell * 3 + 52))
    os.makedirs(os.path.dirname(sheet_path), exist_ok=True)
    sheet.save(sheet_path, optimize=True)
