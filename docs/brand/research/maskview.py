import numpy as np, sys
from PIL import Image
def hsvf(a):
    import colorsys
    rgb=a[...,:3].astype(float)/255
    mx=rgb.max(-1); mn=rgb.min(-1); d=mx-mn
    h=np.zeros_like(mx)
    r,g,b=rgb[...,0],rgb[...,1],rgb[...,2]
    with np.errstate(all='ignore'):
        h=np.where(mx==r,((g-b)/d)%6,np.where(mx==g,(b-r)/d+2,(r-g)/d+4))*60
    h=np.nan_to_num(h)
    s=np.where(mx>0,d/np.maximum(mx,1e-6),0)
    return h,s,mx
def show(f,masks,out):
    a=np.array(Image.open(f).convert('RGBA'))
    tiles=[]
    for m in masks:
        t=a.copy().astype(float)
        t[m,:3]=t[m,:3]*0.2+np.array([255,0,255])*0.8
        bg=np.ones_like(t)*255
        al=t[...,3:]/255
        comp=(t[...,:3]*al+bg[...,:3]*(1-al)).astype(np.uint8)
        tiles.append(Image.fromarray(comp).resize((512,512),Image.NEAREST))
    W=Image.new('RGB',(512*len(tiles),512))
    for i,t in enumerate(tiles): W.paste(t,(512*i,0))
    W.save(out)
