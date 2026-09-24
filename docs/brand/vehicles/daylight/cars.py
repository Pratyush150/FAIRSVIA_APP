import numpy as np
from recolor import *
from maskview import show

def satw(s,lo=0.2,sp=0.15): return np.clip((s-lo)/sp,0,1)

def automobile(target):
    a=load('automobile'); rgb=a[...,:3]/255
    h,s,v=hsvf(a)
    w=band(h,300,25,12)*satw(s)
    w*=1-shape_mask((256,256),[('ellipse',226,163,248,195)])
    out=tone(rgb,w,target)
    b=a.copy(); b[...,:3]=out*255
    return b,w

def suv(target):
    a=load('suv'); rgb=a[...,:3]/255
    h,s,v=hsvf(a)
    w=band(h,195,240,10)*satw(s)
    win=shape_mask((256,256),[
        ('poly',[(70,79.5),(119,79.5),(119,136),(20,136)]),
        ('rect',60,79.5,119.5,136,5),
        ('rect',135.5,79.5,183.5,136,5),
        ('rect',199.5,79.5,240,136,5)])
    w*=1-win
    out=tone(rgb,w,target)
    b=a.copy(); b[...,:3]=out*255
    return b,w

CHECK=[(93,148,113,168),(125,148,145,168),(157,148,177,168),(109,165,129,186),(141,165,161,186)]
def taxi(target):
    a=load('taxi')
    # remove roof sign: copy column 120 over x 124..150 for y<=96
    for x in range(123,152):
        a[40:97,x]=a[40:97,119]
    # inpaint checkers: interpolate between x=91 and x=182 per row
    for (x0,y0,x1,y1) in CHECK:
        for y in range(y0,y1+1):
            L=a[y,x0-1].copy(); R=a[y,x1+1].copy()
            for x in range(x0,x1+1):
                t=(x-x0+1)/(x1-x0+2); a[y,x]=L*(1-t)+R*t
    for x in range(92,180):
        T_=a[162,x].copy(); B_=a[174,x].copy()
        for y in range(163,174):
            t=(y-162)/12; a[y,x]=T_*(1-t)+B_*t
    rgb=a[...,:3]/255
    h,s,v=hsvf(a)
    w=band(h,330,62,10)*satw(s)
    w*=1-shape_mask((256,256),[('ellipse',219,163,245,195)])*band(h,320,25,10)
    w*=1-shape_mask((256,256),[('rect',0,165,14,196,4)])
    out=tone(rgb,w,target)
    b=a.copy(); b[...,:3]=out*255
    return b,w

def police(target):
    a=load('police')
    for x in range(122,151):
        a[40:97,x]=a[40:97,118]
    rgb=a[...,:3]/255
    h,s,v=hsvf(a)
    neutral=np.clip((0.22-s)/0.08,0,1)
    w=neutral*(a[...,3]>0)
    # exclude hubcaps and tyre discs (tyres are purple-saturated anyway) and lights
    w*=1-shape_mask((256,256),[('ellipse',38,181,98,241),('ellipse',158,181,218,241)])
    # windows are saturated blue so excluded by neutral; but roof dark rim ok
    door=shape_mask((256,256),[('rect',62,152,196,216,0),('ellipse',79,132,98,162)])
    seg=[door*(1-0)+0, 1-door]
    out=tone(rgb,w,target,seg=[door,1-door],k=0.6,kl=1.8)
    b=a.copy(); b[...,:3]=out*255
    return b,w
