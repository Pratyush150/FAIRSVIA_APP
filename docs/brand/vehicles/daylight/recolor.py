import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from maskview import hsvf

SRC='fe2/'
def load(n): return np.array(Image.open(SRC+n+'.png').convert('RGBA')).astype(float)
def hexrgb(h): h=h.lstrip('#'); return np.array([int(h[i:i+2],16) for i in (0,2,4)],float)/255
def lum(rgb): return rgb[...,0]*0.2126+rgb[...,1]*0.7152+rgb[...,2]*0.0722

def band(h, lo, hi, soft=10):
    # soft membership of hue h in circular band [lo,hi]
    def d(x,a): return np.minimum(np.abs(x-a)%360, 360-np.abs(x-a)%360)
    if lo<=hi: inside=(h>=lo)&(h<=hi)
    else: inside=(h>=lo)|(h<=hi)
    dist=np.minimum(d(h,lo),d(h,hi))
    return np.where(inside,1.0,np.clip(1-dist/soft,0,1))

def shape_mask(size, shapes, ss=4):
    """shapes: list of ('rect',x0,y0,x1,y1,r) or ('poly',[(x,y)..]) or ('ellipse',x0,y0,x1,y1) in source px; returns soft 0..1"""
    W,H=size
    im=Image.new('L',(W*ss,H*ss),0); d=ImageDraw.Draw(im)
    for s in shapes:
        if s[0]=='rect': d.rounded_rectangle([s[1]*ss,s[2]*ss,s[3]*ss,s[4]*ss],radius=s[5]*ss,fill=255)
        elif s[0]=='poly': d.polygon([(x*ss,y*ss) for x,y in s[1]],fill=255)
        elif s[0]=='ellipse': d.ellipse([s[1]*ss,s[2]*ss,s[3]*ss,s[4]*ss],fill=255)
    return np.array(im.resize((W,H),Image.BOX)).astype(float)/255

def tone(rgb, w, target, ref=None, k=1.0, seg=None, kl=None):
    kl=k if kl is None else kl
    """map lightness of masked pixels onto target colour. seg: list of (weightmap) for separate references"""
    Y=lum(rgb)
    T=hexrgb(target); YT=lum(T)
    if seg is None: seg=[w]
    out=np.zeros_like(rgb); acc=np.zeros(Y.shape)
    for sw in seg:
        m=(sw*w)>0.9
        Y0=np.median(Y[m]) if ref is None else ref
        r=Y/Y0
        dark=T[None,None,:]*np.clip(r,0,1)[...,None]**k
        up=np.clip((Y-Y0)/max(1-Y0,1e-3),0,1)[...,None]
        light=T+(1-T)*np.clip(up*kl,0,1)
        new=np.where((r<=1)[...,None],dark,light)
        out+=new*sw[...,None]; acc+=sw
    out=out/np.maximum(acc,1e-6)[...,None]
    return rgb*(1-w[...,None])+out*w[...,None]

def save(a,path):
    Image.fromarray(np.clip(a,0,255).round().astype(np.uint8),'RGBA').save(path)
