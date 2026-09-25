"""Build the realistic ride-list vehicle set (assets/vehicles/photo{,_dark}).

Pipeline, per vehicle (sources and licences: docs/brand/CREDITS-ride-vehicles.md):
  1. download the Unsplash photo (images.unsplash.com CDN, w=3000),
  2. cut the background out with rembg `birefnet-general` (input downscaled to
     1800 px on the long side) -> src/<name>_cut.png,
  3. this script: paint out maker badges, model lettering and plate text
     (OpenCV Telea inpaint; plates are refilled as blank plates), drop the tow
     hitch, mirror so every vehicle faces left, trim to the subject, and lay it
     on a 16:10 transparent canvas on a shared ground line with a soft contact
     shadow. The whole subject is inside the canvas, so the app can show it with
     BoxFit.contain and nothing is ever cropped.

Run: python build.py <work dir holding src/*_cut.png> <repo root>
Needs: pillow, numpy, opencv-python-headless (and rembg for step 2).
"""
import sys
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageEnhance

WORK = Path(sys.argv[1])
REPO = Path(sys.argv[2])
OUT = REPO / 'packages/design_system/assets/vehicles'

# Rectangles (x0, y0, x1, y1) in the *_cut.png pixel grid (before mirroring).
EDITS = {
    'economy': {
        'inpaint': [(1795, 496, 1834, 520), (1850, 396, 1878, 446)],  # model script, maker badge
        'plain': [],
        # Rear plate edge and the tow hitch hang off the bumper: cut them away.
        'erase_poly': [[(1872, 585), (2000, 585), (2000, 780), (1840, 780), (1840, 700),
                        (1868, 668), (1878, 640)]],
        'mirror': False,
    },
    'comfort': {
        'inpaint': [(1502, 1328, 1548, 1363)],  # grille badge
        'plain': [(1472, 1370, 1568, 1396)],    # front plate -> blank
        'erase_poly': [],
        'mirror': True,
    },
    'premium': {
        'inpaint': [(268, 891, 312, 916)],      # bonnet badge
        'plain': [(242, 961, 282, 997)],        # front plate -> blank
        'erase_poly': [],
        'mirror': False,
    },
    'xl': {
        'inpaint': [(344, 446, 372, 499), (384, 501, 434, 538), (356, 505, 380, 548),
                    (1348, 612, 1370, 634)],  # badges, lettering, front wheel cap
        'plain': [],
        'erase_poly': [],
        'mirror': True,
    },
    'auto': {
        'inpaint': [],
        'plain': [(137, 807, 208, 838)],        # rear plate -> blank
        'erase_poly': [],
        'mirror': True,
    },
    'bike': {
        'inpaint': [(1062, 420, 1101, 466), (998, 474, 1087, 514), (618, 630, 692, 672)],
        'plain': [],
        'erase_poly': [],
        'mirror': False,
    },
}

# Width of the subject as a share of the canvas: a class ladder, the
# hatchback a little smaller than the sedans, the XL the biggest car.
SCALE = {'economy': 0.86, 'comfort': 0.92, 'premium': 0.96, 'xl': 0.98,
         'auto': 0.80, 'bike': 0.80}
# Tallest the subject may be, as a share of the canvas height.
MAX_H = 0.83


def clean(name):
    e = EDITS[name]
    im = Image.open(WORK / f'src/{name}_cut.png').convert('RGBA')
    a = np.array(im)
    rgb = np.ascontiguousarray(a[..., :3])
    mask = np.zeros(a.shape[:2], np.uint8)
    for x0, y0, x1, y1 in e['inpaint']:
        mask[y0:y1, x0:x1] = 255
    if mask.any():
        rgb = cv2.inpaint(rgb, mask, 7, cv2.INPAINT_TELEA)
    for x0, y0, x1, y1 in e['plain']:
        patch = rgb[y0:y1, x0:x1].reshape(-1, 3)
        # Plate paint = the brightest half of the plate (the text is dark).
        lum = patch.mean(1)
        col = np.median(patch[lum >= np.median(lum)], 0)
        h = y1 - y0
        grad = np.linspace(1.03, 0.95, h)[:, None, None]
        rgb[y0:y1, x0:x1] = np.clip(col[None, None, :] * grad, 0, 255)
    a[..., :3] = rgb
    alpha = Image.fromarray(a[..., 3])
    d = ImageDraw.Draw(alpha)
    for poly in e['erase_poly']:
        d.polygon(poly, fill=0)
    a[..., 3] = np.array(alpha)
    out = Image.fromarray(a)
    if e['mirror']:
        out = out.transpose(Image.FLIP_LEFT_RIGHT)
    # Trim to the solid subject (ignore faint matte haze).
    bb = out.split()[3].point(lambda v: 255 if v > 24 else 0).getbbox()
    return out.crop(bb)


def compose(name, subj, w, h, dark):
    canvas = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    ground = round(h * 0.90)
    s = min(w * SCALE[name] / subj.width, h * MAX_H / subj.height)
    sw, sh = max(1, round(subj.width * s)), max(1, round(subj.height * s))
    sub = subj.resize((sw, sh), Image.LANCZOS)
    if dark:
        # Lift the dark paint a touch so graphite/navy bodies keep their
        # shape on the dark glass sheet.
        rgb = ImageEnhance.Brightness(sub.convert('RGB')).enhance(1.12)
        rgb.putalpha(sub.split()[3])
        sub = rgb
    x = (w - sw) // 2
    y = ground - sh
    # Contact shadow: a soft ellipse under the wheels.
    sh_layer = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    ew = sw * 0.92
    eh = max(2, h * 0.07)
    col = (255, 255, 255, 34) if dark else (0, 0, 0, 70)
    ImageDraw.Draw(sh_layer).ellipse(
        [w / 2 - ew / 2, ground - eh * 0.55, w / 2 + ew / 2, ground + eh * 0.45], fill=col)
    sh_layer = sh_layer.filter(ImageFilter.GaussianBlur(max(1.0, h * 0.025)))
    canvas.alpha_composite(sh_layer)
    canvas.alpha_composite(sub, (x, y))
    return canvas


def main():
    base = (120, 75)  # 1x logical size; the list shows it at 76 x 47.5
    for name in EDITS:
        subj = clean(name)
        for dark in (False, True):
            folder = OUT / ('photo_dark' if dark else 'photo')
            for scale, sub in ((1, ''), (2, '2.0x'), (3, '3.0x')):
                d = folder / sub if sub else folder
                d.mkdir(parents=True, exist_ok=True)
                img = compose(name, subj, base[0] * scale, base[1] * scale, dark)
                img.save(d / f'{name}.webp', 'WEBP', quality=86, method=6)
                # The driver card's neutral car: the white sedan.
                if name == 'comfort':
                    img.save(d / 'driver.webp', 'WEBP', quality=86, method=6)
        print('built', name)


if __name__ == '__main__':
    main()
