"""Composite the shadow pass under each light render and write deliverables.

  python3 export.py RENDERDIR ASSETDIR [shadow_opacity]

ASSETDIR/clay/<v>.png (256), ASSETDIR/clay/2.0x/<v>.png (512),
ASSETDIR/clay_dark/... likewise. Also RENDERDIR/final/{light,dark}/<v>.png
(512) for the contact sheet.
"""
import os
import sys
from PIL import Image

src, dst = sys.argv[1], sys.argv[2]
op = float(sys.argv[3]) if len(sys.argv) > 3 else 0.55
from PIL import ImageFilter


def marker(src_png):
    """Top-down map marker: thin light outline + soft drop shadow offset
    down-right, 256 master."""
    im = Image.open(src_png).convert('RGBA').resize((256, 256), Image.LANCZOS)
    A = im.getchannel('A')
    ring = A.filter(ImageFilter.MaxFilter(5))
    outline = Image.new('RGBA', im.size, (255, 255, 255, 0))
    outline.putalpha(ring.point(lambda v: int(v * 0.85)))
    sh_a = A.filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.GaussianBlur(5))
    sh = Image.new('RGBA', im.size, (10, 14, 20, 0))
    sh.putalpha(sh_a.point(lambda v: int(v * 0.45)))
    out = Image.new('RGBA', im.size, (0, 0, 0, 0))
    out.alpha_composite(sh, (4, 6))
    out.alpha_composite(outline)
    out.alpha_composite(im)
    return out


td = os.path.join(src, 'top')
if os.path.isdir(td):
    for f in sorted(os.listdir(td)):
        if not f.endswith('.png'):
            continue
        m = marker(os.path.join(td, f))
        os.makedirs(os.path.join(src, 'final', 'top'), exist_ok=True)
        m.save(os.path.join(src, 'final', 'top', f))
        if dst != '-':
            os.makedirs(os.path.join(dst, 'top', '2.0x'), exist_ok=True)
            m.save(os.path.join(dst, 'top', '2.0x', f), optimize=True)
            m.resize((128, 128), Image.LANCZOS).save(os.path.join(dst, 'top', f), optimize=True)

for mode, folder in (('light', 'clay'), ('dark', 'clay_dark')):
    d = os.path.join(src, mode)
    if not os.path.isdir(d):
        continue
    for f in sorted(os.listdir(d)):
        if not f.endswith('.png'):
            continue
        car = Image.open(os.path.join(d, f)).convert('RGBA')
        sp = os.path.join(src, 'shadow', f)
        if mode == 'light' and os.path.exists(sp):
            sh = Image.open(sp).convert('RGBA')
            A = sh.getchannel('A')
            # residual catcher alpha from world occlusion: take the frame's
            # border level as the floor so no grey box shows on white.
            w, h = A.size
            border = [A.getpixel((x, y)) for x in range(0, w, 8) for y in (2, h - 3)] + \
                     [A.getpixel((x, y)) for y in range(0, h, 8) for x in (2, w - 3)]
            fl = max(border) + 3
            a = A.point(lambda v: int(max(0, v - fl) * 255 / (255 - fl) * op))
            base = Image.new('RGBA', car.size, (0, 0, 0, 0))
            sh = Image.merge('RGBA', (*sh.convert('RGB').split(), a))
            base.alpha_composite(sh)
            base.alpha_composite(car)
            car = base
        os.makedirs(os.path.join(src, 'final', mode), exist_ok=True)
        car.save(os.path.join(src, 'final', mode, f))
        if dst != '-':
            os.makedirs(os.path.join(dst, folder, '2.0x'), exist_ok=True)
            car.save(os.path.join(dst, folder, '2.0x', f), optimize=True)
            car.resize((256, 256), Image.LANCZOS).save(os.path.join(dst, folder, f), optimize=True)
