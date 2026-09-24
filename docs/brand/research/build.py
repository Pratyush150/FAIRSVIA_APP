import numpy as np, os
from PIL import Image, ImageDraw, ImageFont, ImageFilter
from cars import automobile, suv, taxi, police
from recolor import load

REPO='/home/nova-robotics/ubernav/packages/design_system/assets'
VEH=REPO+'/vehicles/daylight'; HER=REPO+'/heroes/daylight'
M=1024          # working canvas (4x of 256)
FILL=0.80

def pil(a): return Image.fromarray(np.clip(a,0,255).round().astype(np.uint8),'RGBA')
def src(n): return Image.open('fe2/'+n+'.png').convert('RGBA')
def bbox(im): return im.getchannel('A').point(lambda v:255 if v>6 else 0).getbbox()
def up(im,f): return im.resize((round(im.width*f),round(im.height*f)),Image.LANCZOS)

def shadowed(layer, off=(0,6), blur=10, op=0.22):
    """drop shadow for a badge layer (same size canvas)"""
    a=layer.getchannel('A').point(lambda v:int(v*op))
    sh=Image.new('RGBA',layer.size,(17,19,21,0)); sh.putalpha(a)
    sh=sh.filter(ImageFilter.GaussianBlur(blur))
    out=Image.new('RGBA',layer.size,(0,0,0,0)); out.alpha_composite(sh,off); out.alpha_composite(layer)
    return out

def fit(im, fill=FILL, size=M):
    b=bbox(im); im=im.crop(b)
    f=fill*size/max(im.size); im=up(im,f)
    c=Image.new('RGBA',(size,size),(0,0,0,0))
    c.alpha_composite(im,((size-im.width)//2,(size-im.height)//2)); return c

def write(img, folder, name):
    os.makedirs(folder+'/2.0x',exist_ok=True)
    img.resize((512,512),Image.LANCZOS).save(f'{folder}/2.0x/{name}.png',optimize=True)
    img.resize((256,256),Image.LANCZOS).save(f'{folder}/{name}.png',optimize=True)

# ---------- vehicles: common scale + common baseline ----------
veh={
 'economy':pil(automobile('#2BC4C4')[0]),
 'comfort':pil(taxi('#5B6B80')[0]),
 'xl':pil(suv('#E8D5B5')[0]),
 'premium':pil(police('#3A3D42')[0]),
 'driver':pil(automobile('#D9DDE2')[0]),
 'auto':src('rickshaw'),
}
# all Fluent vehicles face left already; no flip needed (verified visually)
boxes={k:bbox(v) for k,v in veh.items()}
cars=[k for k in boxes if k!='auto']
Wmax=max(boxes[k][2]-boxes[k][0] for k in cars); Hmax=max(boxes[k][3]-boxes[k][1] for k in cars)
scale=FILL*M/max(Wmax,Hmax)
base=int(M/2+Hmax*scale/2)
ab=boxes['auto']
auto_scale=min(scale, FILL*M/(ab[3]-ab[1]), FILL*M/(ab[2]-ab[0]))
auto_base=base
def place_vehicle(k):
    b=boxes[k]; sc=auto_scale if k=='auto' else scale; bl=auto_base if k=='auto' else base
    im=up(veh[k].crop(b),sc)
    c=Image.new('RGBA',(M,M),(0,0,0,0))
    c.alpha_composite(im,((M-im.width)//2, bl-im.height)); return c
VEHOUT={k:place_vehicle(k) for k in veh}
for k,v in VEHOUT.items(): write(v,VEH,k)

# ---------- heroes ----------
def rupee_note():
    a=load('dollar')
    for y in range(96,181):
        L=a[y,53].copy(); R=a[y,101].copy()
        for x in range(54,101):
            t=(x-53)/48; a[y,x]=L*(1-t)+R*t
    im=up(pil(a),4)          # 1024
    font=ImageFont.truetype('/usr/share/fonts/truetype/lato/Lato-Black.ttf',330)
    g=Image.new('RGBA',im.size,(0,0,0,0)); d=ImageDraw.Draw(g)
    cx,cy=77*4,138*4
    d.text((cx,cy),'₹',font=font,fill=(236,236,242,255),anchor='mm')
    # soft inner-ish shadow like the original glyph: dark offset copy under it
    sh=Image.new('RGBA',im.size,(0,0,0,0)); ImageDraw.Draw(sh).text((cx+6,cy+8),'₹',font=font,fill=(20,80,50,150),anchor='mm')
    sh=sh.filter(ImageFilter.GaussianBlur(5))
    im.alpha_composite(sh); im.alpha_composite(g)
    return im

def badge(base_im, badge_im, rel=0.42, pos='br', inset=0.0):
    """compose two 1024 layers: base fitted to 80%, badge scaled rel of canvas at a corner of the base bbox"""
    c=fit(base_im); b=bbox(c)
    bd=badge_im.crop(bbox(badge_im)); f=rel*M/max(bd.size); bd=up(bd,f)
    if pos=='br': x=b[2]-bd.width+int(inset*M); y=b[3]-bd.height+int(inset*M)
    elif pos=='tr': x=b[2]-bd.width+int(inset*M); y=b[1]-int(inset*M)
    layer=Image.new('RGBA',(M,M),(0,0,0,0)); layer.alpha_composite(bd,(x,y))
    c.alpha_composite(shadowed(layer))
    return fit(c)   # refit so union is 80%

def search_car():
    car=VEHOUT['economy']; c=Image.new('RGBA',(M,M),(0,0,0,0))
    cb=car.crop(bbox(car)); cb=up(cb,0.72*M/cb.width)
    c.alpha_composite(cb,(40,M-cb.height-150))
    mg=src('magL'); mg=mg.crop(bbox(mg)); mg=up(mg,0.55*M/mg.width)
    layer=Image.new('RGBA',(M,M),(0,0,0,0)); layer.alpha_composite(mg,(M-mg.width-40,150))
    c.alpha_composite(shadowed(layer))
    return fit(c)

def pin_plus():
    c=Image.new('RGBA',(M,M),(0,0,0,0))
    p=src('pin'); p=p.crop(bbox(p)); p=up(p,0.9*M/p.height)
    c.alpha_composite(p,(int(M*0.30)-p.width//2+60,(M-p.height)//2))
    pl=src('plus'); pl=pl.crop(bbox(pl)); pl=up(pl,0.30*M/pl.width)
    layer=Image.new('RGBA',(M,M),(0,0,0,0)); layer.alpha_composite(pl,(int(M*0.62),int(M*0.10)))
    c.alpha_composite(shadowed(layer))
    return fit(c)

def sleeping_car():
    car=VEHOUT['driver']; c=Image.new('RGBA',(M,M),(0,0,0,0))
    cb=car.crop(bbox(car)); cb=up(cb,0.80*M/cb.width)
    c.alpha_composite(cb,(0,M-cb.height))
    z=src('zzz'); z=z.crop(bbox(z)); z=up(z,0.42*M/z.width)
    c.alpha_composite(z,(M-z.width-10, M-cb.height-z.height+90))
    return fit(c)

H={
 'cash':fit(rupee_note()),
 'upi':badge(src('phone'),src('checkbtn'),rel=0.38,pos='br',inset=0.06),
 'card':fit(src('card')),
 'add_stop':pin_plus(),
 'prebook':badge(src('spiral'),src('checkbtn'),rel=0.36,pos='br',inset=0.05),
 'search_car':search_car(),
 'no_cars':sleeping_car(),
 'done':fit(src('checkbtn')),
 'safety':fit(src('shield')),
 'wallet':fit(src('purse')),
 'gift':fit(src('gift')),
 'star':fit(src('star')),
}
for k,v in H.items(): write(v,HER,k)

# ---------- contact sheet ----------
items=[('vehicles/'+k,VEH+'/2.0x/'+k+'.png') for k in VEHOUT]+[('heroes/'+k,HER+'/2.0x/'+k+'.png') for k in H]
T=200; cols=6; rows=(len(items)+cols-1)//cols
sheet=Image.new('RGB',(cols*T*2+40,rows*(T+40)+60),(255,255,255))
d=ImageDraw.Draw(sheet)
d.rectangle([cols*T+40,0,sheet.width,sheet.height],fill=(245,246,247))
d.text((10,10),'on #FFFFFF',fill=(0,0,0)); d.text((cols*T+50,10),'on #F5F6F7',fill=(0,0,0))
for i,(lab,p) in enumerate(items):
    im=Image.open(p).convert('RGBA').resize((T,T),Image.LANCZOS)
    for side in (0,1):
        x=side*(cols*T+40)+(i%cols)*T; y=40+(i//cols)*(T+40)
        sheet.paste(im,(x,y),im); d.text((x+6,y+T+4),lab,fill=(60,60,60))
# 1x strip of vehicles side by side as in the ride list
sheet.save('/tmp/claude-1000/-home-nova-robotics-ubernav/32b0b03b-f246-44cd-933a-739a28167dfc/scratchpad/daylight_contact.png')
print('scale',scale,'base',base,'auto',auto_scale,auto_base, {k:(b[2]-b[0],b[3]-b[1]) for k,b in boxes.items()})
