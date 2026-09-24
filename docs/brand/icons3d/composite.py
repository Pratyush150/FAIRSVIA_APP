"""Step 3: raw 512 masters -> png/{light,dark}/<name>.png (256, RGBA).

  python3 composite.py RAWDIR [shadow_opacity]

Light: contact-shadow pass composited under the body (same method as
docs/brand/vehicles/clay/export.py: the catcher's residual border alpha is
treated as the floor so no grey box shows). Dark: body only, no floor shadow.
"""
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
raw = sys.argv[1]
op = float(sys.argv[2]) if len(sys.argv) > 2 else 0.5
OUT = os.path.join(HERE, 'png')


def shadow_under(body, sp):
    sh = Image.open(sp).convert('RGBA')
    A = sh.getchannel('A')
    w, h = A.size
    border = [A.getpixel((x, y)) for x in range(0, w, 8) for y in (2, h - 3)] + \
             [A.getpixel((x, y)) for y in range(0, h, 8) for x in (2, w - 3)]
    fl = max(border) + 3
    a = A.point(lambda v: int(max(0, v - fl) * 255 / (255 - fl) * op))
    base = Image.new('RGBA', body.size, (0, 0, 0, 0))
    base.alpha_composite(Image.merge('RGBA', (*sh.convert('RGB').split(), a)))
    base.alpha_composite(body)
    return base


TARGET = float(os.environ.get('TARGET', '0.92'))
MASTER = float(os.environ.get('MASTER', '0.84'))
MARGIN = 0.02   # min clear border, fraction of canvas


def fit(ims):
    """One scale + offset for an icon (shared by its light+shadow and dark
    images): live area MASTER -> TARGET of the canvas, clamped so the
    content bbox keeps MARGIN clear; content centred horizontally, and
    vertically nudged only as far as needed to stay inside the frame."""
    W = ims[0].size[0]
    boxes = [im.getchannel('A').point(lambda v: 255 if v > 6 else 0).getbbox() for im in ims]
    x0 = min(b[0] for b in boxes); y0 = min(b[1] for b in boxes)
    x1 = max(b[2] for b in boxes); y1 = max(b[3] for b in boxes)
    k = TARGET / MASTER
    lim = (1 - 2 * MARGIN) * W
    k = min(k, lim / (x1 - x0), lim / (y1 - y0))
    c = W / 2
    # horizontal: centre the content; vertical: keep common optical centre
    dx = c - (x0 + x1) / 2
    ny0, ny1 = c + (y0 - c) * k, c + (y1 - c) * k
    dy = 0.0
    if ny0 < MARGIN * W:
        dy = MARGIN * W - ny0
    elif ny1 > (1 - MARGIN) * W:
        dy = (1 - MARGIN) * W - ny1
    return k, dx, dy


def apply(im, k, dx, dy):
    W = im.size[0]
    c = W / 2
    # output pixel p <- input (p - c - dy_out)/k + c - dx ; affine inverse map
    a = 1 / k
    return im.transform(im.size, Image.AFFINE,
                        (a, 0, c - dx - c * a, 0, a, c - (dy / 1.0) * a - c * a),
                        resample=Image.BICUBIC)


def edge_fade(im, px):
    """Feather alpha to 0 over the outer px pixels. The body always keeps
    MARGIN clear, so this only trims the soft contact shadow where a tall
    icon pushes it past the frame (no hard shadow edge at the border)."""
    W, H = im.size
    ramp = Image.new('L', (W, H), 255)
    from PIL import ImageDraw
    d = ImageDraw.Draw(ramp)
    for i in range(px):
        v = int(255 * i / px)
        d.rectangle((i, i, W - 1 - i, H - 1 - i), outline=v)
    from PIL import ImageChops
    im.putalpha(ImageChops.multiply(im.getchannel('A'), ramp))
    return im


n = 0
fits = {}
d0 = os.path.join(raw, 'light')
for f in sorted(os.listdir(d0)) if os.path.isdir(d0) else []:
    ims = [Image.open(os.path.join(raw, m, f)).convert('RGBA')
           for m in ('light', 'dark', 'shadow') if os.path.exists(os.path.join(raw, m, f))]
    fits[f] = fit(ims[:2])
for mode in ('light', 'dark'):
    d = os.path.join(raw, mode)
    if not os.path.isdir(d):
        continue
    os.makedirs(os.path.join(OUT, mode), exist_ok=True)
    for f in sorted(os.listdir(d)):
        if not f.endswith('.png'):
            continue
        im = Image.open(os.path.join(d, f)).convert('RGBA')
        sp = os.path.join(raw, 'shadow', f)
        if mode == 'light' and os.path.exists(sp):
            im = shadow_under(im, sp)
        if f in fits:
            im = apply(im, *fits[f])
        if mode == 'light':
            im = edge_fade(im, int(MARGIN * im.size[0]))
        im.resize((256, 256), Image.LANCZOS).save(os.path.join(OUT, mode, f), optimize=True)
        n += 1
print('wrote', n)
