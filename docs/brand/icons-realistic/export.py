"""Composite the two passes and write app assets + contact sheet (system python3 + Pillow).

  python3 export.py <render_dir> [--install] [keys...]
  <key>_obj.png : subject pass,  <key>_shd.png : shadow-catcher pass
"""
import os
import sys
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..', '..', '..'))
KEYS = ['ride', 'prebook', 'someone_else', 'saved', 'add_stop', 'coins', 'star', 'tag']
SHADOW = {'ride': 0.62}
DEFAULT_SHADOW = 0.55


def master(rd, key):
    a = Image.open(os.path.join(rd, key + '_obj.png')).convert('RGBA')
    sp = os.path.join(rd, key + '_shd.png')
    if not os.path.exists(sp):
        return a
    b = Image.open(sp).convert('RGBA')
    k = SHADOW.get(key, DEFAULT_SHADOW)
    sh = Image.new('RGBA', a.size, (14, 18, 22, 0))
    sh.putalpha(b.getchannel('A').point(lambda v: int(v * k)))
    sh.alpha_composite(a)
    return sh


def sheet(ims, out):
    bgs = ['#FFFFFF', '#F5F6F7', '#14171A']
    sizes = [56, 96]
    pad = 14
    W = pad + len(ims) * (sum(sizes) + (len(sizes) + 1) * pad)
    H = pad + len(bgs) * (max(sizes) + 2 * pad)
    img = Image.new('RGB', (W, H), '#888')
    for r, bg in enumerate(bgs):
        y0 = pad + r * (max(sizes) + 2 * pad)
        img.paste(Image.new('RGB', (W, max(sizes) + 2 * pad), bg), (0, y0 - pad // 2))
        x = pad
        for k, im in ims:
            for s in sizes:
                t = im.resize((s, s), Image.LANCZOS)
                img.paste(t, (x, y0 + (max(sizes) - s) // 2), t)
                x += s + pad
            x += pad
    img.save(out)


def main():
    rd = sys.argv[1]
    install = '--install' in sys.argv
    keys = [k for k in sys.argv[2:] if k in KEYS] or KEYS
    ims = []
    for k in keys:
        if not os.path.exists(os.path.join(rd, k + '_obj.png')):
            continue
        m = master(rd, k).resize((512, 512), Image.LANCZOS)
        m.save(os.path.join(rd, k + '_512.png'))
        ims.append((k, m))
        if install:
            for d in ('home', 'home_dark'):
                base = os.path.join(REPO, 'packages', 'design_system', 'assets', d)
                os.makedirs(os.path.join(base, '2.0x'), exist_ok=True)
                m.save(os.path.join(base, '2.0x', k + '.png'), optimize=True)
                m.resize((256, 256), Image.LANCZOS).save(os.path.join(base, k + '.png'),
                                                         optimize=True)
    sheet(ims, os.path.join(rd, 'contact.png'))
    if install:
        sheet(ims, os.path.join(REPO, 'docs', 'brand', 'research',
                                'home-realistic-contact.png'))


if __name__ == '__main__':
    main()
