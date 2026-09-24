from PIL import Image, ImageDraw, ImageFont
from palettes_def import P, MAP
F="/tmp/claude-1000/-home-nova-robotics-ubernav/32b0b03b-f246-44cd-933a-739a28167dfc/scratchpad/inter/InterVariable.ttf"
def font(sz, w=400):
    f=ImageFont.truetype(F, sz)
    try: f.set_variation_by_axes([14,w] if len(f.get_variation_axes())==2 else [w])
    except Exception:
        try: f.set_variation_by_axes([w])
        except Exception: pass
    return f
S=2  # supersample
def phone(t, mode):
    W,H=360*S,720*S
    im=Image.new("RGB",(W,H),t["bg"]); d=ImageDraw.Draw(im)
    # map block
    mapc=MAP[mode]; street="#F4F5F7" if mode=="light" else "#34363C"
    d.rectangle([0,0,W,400*S],fill=mapc)
    for x in (60,170,290): d.rectangle([x*S,0,(x+10)*S,400*S],fill=street)
    for y in (70,190,310): d.rectangle([0,y*S,W,(y+10)*S],fill=street)
    route=[(65*S,360*S),(65*S,195*S),(175*S,195*S),(175*S,75*S),(295*S,75*S),(295*S,40*S)]
    d.line(route,fill=t["hi"],width=7*S,joint="curve")
    r=11*S; x,y=route[0]; d.ellipse([x-r,y-r,x+r,y+r],fill=t["brand"],outline=t["s1"],width=3*S)
    x,y=route[-1]; d.rectangle([x-r,y-r,x+r,y+r],fill=t["text"],outline=t["s1"],width=3*S)
    # sheet
    top=380*S
    d.rounded_rectangle([0,top,W,H+40*S],radius=20*S,fill=t["s1"])
    d.rounded_rectangle([W//2-20*S,top+8*S,W//2+20*S,top+12*S],radius=2*S,fill=t["border"])
    d.text((20*S,top+24*S),"Choose a ride",font=font(22*S,700),fill=t["text"])
    d.text((20*S,top+54*S),"Pickup in 4 min · Koregaon Park",font=font(13*S,400),fill=t["text2"])
    rows=[("Economy","3 min · 4 seats","₹142",True),("Comfort","5 min · 4 seats","₹188",False)]
    y=top+84*S
    for name,sub,price,sel in rows:
        box=[16*S,y,W-16*S,y+60*S]
        if sel: d.rounded_rectangle(box,radius=12*S,fill=t["tint"],outline=t["hi"],width=2*S)
        else: d.rounded_rectangle(box,radius=12*S,fill=t["s1"],outline=t["border"],width=1*S)
        d.rounded_rectangle([28*S,y+14*S,60*S,y+46*S],radius=8*S,fill=t["s2"])
        d.text((72*S,y+12*S),name,font=font(15*S,600),fill=t["text"])
        d.text((72*S,y+33*S),sub,font=font(12*S),fill=t["text2"])
        d.text((W-80*S,y+20*S),price,font=font(15*S,700),fill=t["text"])
        y+=70*S
    # chips semantic
    cx=16*S; cy=y+2*S
    for k,lab in (("success","Paid"),("warning","Surge"),("danger","SOS")):
        f=font(11*S,600); w=d.textlength(lab,font=f)+34*S
        d.rounded_rectangle([cx,cy,cx+w,cy+24*S],radius=12*S,fill=t["s2"])
        d.ellipse([cx+9*S,cy+8*S,cx+17*S,cy+16*S],fill=t[k])
        d.text((cx+23*S,cy+5*S),lab,font=f,fill=t[k]); cx+=w+8*S
    # button
    by=H-74*S
    d.rounded_rectangle([16*S,by,W-16*S,by+54*S],radius=27*S,fill=t["brand"])
    f=font(16*S,600); lab="Confirm Economy"; tw=d.textlength(lab,font=f)
    d.text(((W-tw)/2,by+16*S),lab,font=f,fill=t["on"])
    im=im.resize((360,720),Image.LANCZOS)
    m=Image.new("L",(360,720),0); ImageDraw.Draw(m).rounded_rectangle([0,0,359,719],radius=36,fill=255)
    return im,m
def card(name,p):
    W,H=820,860; c=Image.new("RGB",(W,H),"#D9DCE1"); d=ImageDraw.Draw(c)
    d.text((30,22),name,font=font(28,700),fill="#111315")
    d.text((30,60),p["story"],font=font(13),fill="#4A4F57")
    for i,mode in enumerate(("light","dark")):
        im,m=phone(p[mode],mode); x=30+i*400; 
        c.paste("#9CA0A8",(x-3,97,x+363,823),Image.new("L",(366,726),0).__class__.new("L",(366,726),0)) if False else None
        c.paste(im,(x,100),m)
        d.text((x,830),mode,font=font(14,600),fill="#4A4F57")
    return c
import os
out="palettes"; cards=[]
for n,p in P.items():
    cimg=card(n,p); cimg.save(f"{out}/{n}.png"); cards.append(cimg)
cols=3; w,h=cards[0].size; rows=(len(cards)+cols-1)//cols
sheet=Image.new("RGB",(cols*w,rows*h),"#D9DCE1")
for i,cimg in enumerate(cards): sheet.paste(cimg,((i%cols)*w,(i//cols)*h))
sheet.save(f"{out}/all.png"); print("ok",sheet.size)
