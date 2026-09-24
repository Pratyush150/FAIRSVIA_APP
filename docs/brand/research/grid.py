import sys
from PIL import Image, ImageDraw
f,x0,y0,x1,y1,z=sys.argv[1],*map(int,sys.argv[2:7])
im=Image.open(f).convert('RGBA').crop((x0,y0,x1,y1))
bg=Image.new('RGBA',im.size,(255,255,255,255));bg.alpha_composite(im)
im=bg.resize(((x1-x0)*z,(y1-y0)*z),Image.NEAREST)
d=ImageDraw.Draw(im)
for x in range(x0 - x0%10 + 10, x1, 10):
    d.line([((x-x0)*z,0),((x-x0)*z,im.height)],fill=(0,200,0,255) if x%50 else (255,0,0,255))
    if x%20==0: d.text(((x-x0)*z+2,2),str(x),fill=(0,0,0,255))
for y in range(y0 - y0%10 + 10, y1, 10):
    d.line([(0,(y-y0)*z),(im.width,(y-y0)*z)],fill=(0,200,0,255) if y%50 else (255,0,0,255))
    if y%20==0: d.text((2,(y-y0)*z+2),str(y),fill=(0,0,0,255))
im.save(sys.argv[7])
