from PIL import Image,ImageDraw,ImageFilter,ImageEnhance
import numpy as np, colorsys
OUT='out'; import os; os.makedirs(OUT,exist_ok=True)
def trim(im,th=12):
    bb=im.getchannel('A').point(lambda v:255 if v>th else 0).getbbox(); return im.crop(bb)
def clean_alpha(im):
    # kill faint halo: alpha<10 ->0, and de-fringe light halos by un-premultiplying against white bg
    a=np.array(im).astype(float); al=a[...,3:4]/255.0
    a[...,3]=np.where(a[...,3]<10,0,a[...,3])
    # decontaminate edge pixels (0<alpha<1) that were mixed with white: c = (obs - (1-al)*255)/al
    edge=(al>0.05)&(al<0.95)
    dec=np.clip((a[...,:3]-(1-al)*255)/np.maximum(al,0.05),0,255)
    a[...,:3]=np.where(edge,0.5*dec+0.5*a[...,:3],a[...,:3])
    return Image.fromarray(a.astype(np.uint8))
def grade(im,bright=1.04,contrast=1.05,sat=0.95,warm=0):
    rgb=im.convert('RGB'); a=im.getchannel('A')
    rgb=ImageEnhance.Brightness(rgb).enhance(bright); rgb=ImageEnhance.Contrast(rgb).enhance(contrast); rgb=ImageEnhance.Color(rgb).enhance(sat)
    o=rgb.convert('RGBA'); o.putalpha(a); return o
def place(im,S=1024,maxw=0.88,maxh=0.80,ground=0.86,shadow_w=0.78,shadow_a=0.30):
    im=trim(im); w,h=im.size; k=min(maxw*S/w,maxh*S/h); im=im.resize((max(1,round(w*k)),max(1,round(h*k))),Image.LANCZOS)
    w,h=im.size; x=(S-w)//2; y=int(ground*S)-h
    can=Image.new('RGBA',(S,S),(0,0,0,0))
    sh=Image.new('L',(S,S),0); d=ImageDraw.Draw(sh); sw=w*shadow_w; sh_h=S*0.045
    cy=int(ground*S)-sh_h*0.15
    d.ellipse([S/2-sw/2,cy-sh_h/2,S/2+sw/2,cy+sh_h/2],fill=int(255*shadow_a))
    sh=sh.filter(ImageFilter.GaussianBlur(S*0.018))
    # tight contact core
    core=Image.new('L',(S,S),0); ImageDraw.Draw(core).ellipse([S/2-sw*0.42,cy-sh_h*0.22,S/2+sw*0.42,cy+sh_h*0.22],fill=int(255*shadow_a*0.9))
    core=core.filter(ImageFilter.GaussianBlur(S*0.006))
    shl=Image.fromarray(np.maximum(np.array(sh),np.array(core)))
    shimg=Image.new('RGBA',(S,S),(20,24,28,0)); shimg.putalpha(shl)
    can.alpha_composite(shimg); can.alpha_composite(im,(x,y)); return can
def export(can,name):
    can.resize((512,512),Image.LANCZOS).save(f'{OUT}/{name}@2x.png',optimize=True)
    can.resize((256,256),Image.LANCZOS).save(f'{OUT}/{name}.png',optimize=True)

# RIDE
car=clean_alpha(Image.open('src/car_cut.png').convert('RGBA'))
export(place(grade(car,1.03,1.06,0.9),maxw=0.97,maxh=0.72,shadow_w=0.86),'ride')

# PREBOOK: calendar, remove year, slight lean-back perspective
cal=Image.open('src/z5pClnWen9M_cut.png').convert('RGBA'); ca=np.array(cal).astype(float)
h0,w0=ca.shape[:2]
# fit a smooth paper model (quadratic in x,y) to bright paper pixels of the sheet body, then reprint
y0=150; body=ca[y0:,:,:3]; L=body.mean(2)
yy,xx=np.mgrid[y0:h0,0:w0]
sel=(L>200)&(ca[y0:,:,3]>250)
X=np.stack([np.ones(sel.sum()),xx[sel],yy[sel],xx[sel]**2,yy[sel]**2,xx[sel]*yy[sel]],1)
Xall=np.stack([np.ones(xx.size),xx.ravel(),yy.ravel(),xx.ravel()**2,yy.ravel()**2,(xx*yy).ravel()],1)
paper=np.zeros_like(body)
rng=np.random.default_rng(1)
for c in range(3):
    coef,*_=np.linalg.lstsq(X,body[...,c][sel],rcond=None); paper[...,c]=(Xall@coef).reshape(L.shape)
paper+=rng.normal(0,1.2,paper.shape[:2])[...,None]
m=np.ones(L.shape); m[:, :8]=0; m[:, -8:]=0; m[-8:,:]=0
ca[y0:,:,:3]=body*(1-m[...,None])+paper*m[...,None]
# also wipe the band between clip slot and body (y 130-150)
cal=Image.fromarray(np.clip(ca,0,255).astype(np.uint8))
from PIL import ImageFont
d=ImageDraw.Draw(cal)
F1=ImageFont.truetype('/home/nova-robotics/ubernav/packages/design_system/fonts/Inter-ExtraBold.ttf',380)
ink=(31,36,40,255); teal=(18,140,138,255)
# teal header band like a printed calendar strip
d.rectangle([34,170,w0-34,300],fill=teal)
for i in range(7):
    cx=90+i*(w0-180)/6; d.ellipse([cx-9,228,cx+9,246],fill=(233,243,242,255))
tb=d.textbbox((0,0),'25',font=F1); tw=tb[2]-tb[0]
d.text(((w0-tw)/2-tb[0],560-tb[1]-(tb[3]-tb[1])/2),'25',font=F1,fill=ink)
cal=cal.filter(ImageFilter.GaussianBlur(0.6))
w,h=cal.size
pad=int(w*0.07)
# perspective: top edge narrower (desk calendar leaning back)
cal2=Image.new('RGBA',(w,h),(0,0,0,0))
src_q=(0,0, 0,h, w,h, w,0)  # QUAD maps these source corners to the output rectangle; we want the inverse, so build via PERSPECTIVE
def homog(dst,src):
    M=[];b=[]
    for (x,y),(u,v) in zip(dst,src):
        M.append([x,y,1,0,0,0,-u*x,-u*y]);b.append(u);M.append([0,0,0,x,y,1,-v*x,-v*y]);b.append(v)
    return tuple(np.linalg.solve(np.array(M,float),np.array(b,float)))
dst=[(pad,int(h*0.03)),(w-pad,int(h*0.03)),(w,h),(0,h)]
cal2=cal.transform((w,h),Image.PERSPECTIVE,homog(dst,[(0,0),(w,0),(w,h),(0,h)]),Image.BICUBIC)
export(place(clean_alpha(grade(cal2,1.02,1.08,0.95)),maxw=0.80,maxh=0.80,shadow_w=0.95),'prebook')

# SOMEONE_ELSE: phone composite
ph=Image.open('src/phone_comp.png').convert('RGBA')
export(place(clean_alpha(grade(ph,1.03,1.05,0.95)),maxw=0.90,maxh=0.80,shadow_w=0.80),'someone_else')

# SAVED: Pixabay 3D pin, red -> brand teal
pin=Image.open('cand/location-icon-9546695_1280.png').convert('RGBA')
orig=np.array(pin.convert('RGB')).astype(float)
hsv=np.array(pin.convert('RGB').convert('HSV')).astype(float); al=np.array(pin.getchannel('A'))
hue=hsv[...,0]; hd=np.minimum(np.abs(hue-0),np.abs(hue-255)); 
wgt=np.clip((hsv[...,1]-8)/40,0,1)*np.clip((45-hd)/20,0,1)
sh=hsv.copy(); sh[...,0]=125; sh[...,1]=hsv[...,1]*0.92; sh[...,2]=hsv[...,2]*0.62
shr=np.array(Image.fromarray(sh.astype(np.uint8),'HSV').convert('RGB')).astype(float)
# low-sat pixels (speculars/base) keep their own value; only tint
outp=orig*(1-wgt[...,None])+shr*wgt[...,None]
rgb=Image.fromarray(np.clip(outp,0,255).astype(np.uint8)).convert('RGBA'); rgb.putalpha(Image.fromarray(al))
export(place(grade(rgb,1.02,1.04,0.95),maxw=0.80,maxh=0.80,shadow_w=0.85,shadow_a=0.22),'saved')
Image.fromarray(np.array(pin)).save('out/saved_red_src.png')
