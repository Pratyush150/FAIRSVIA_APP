import sys
from PIL import Image
src, out = sys.argv[1], sys.argv[2]
kinds = ['economy','comfort','xl','premium','driver']
cw, ch = 512, 320
sheet = Image.new('RGBA', (cw*2 + 2*140, ch*5), (0,0,0,255))
for bi, bg in enumerate([(0x17,0x18,0x1B,255), (255,255,255,255)]):
    x0 = bi*(cw+140)
    panel = Image.new('RGBA', (cw+140, ch*5), bg)
    for i, k in enumerate(kinds):
        im = Image.open(f'{src}/{k}.png').convert('RGBA')
        panel.alpha_composite(im, (0, i*ch))
        th = im.resize((64, 40), Image.LANCZOS)
        panel.alpha_composite(th, (cw+30, i*ch + 140))
    sheet.paste(panel, (x0, 0))
sheet.convert('RGB').save(out)
