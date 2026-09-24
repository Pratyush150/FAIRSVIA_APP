from palettes_def import P
import math
def lab(h):
    h=h.lstrip('#'); c=[int(h[i:i+2],16)/255 for i in (0,2,4)]
    c=[x/12.92 if x<=0.04045 else ((x+0.055)/1.055)**2.4 for x in c]
    X=(0.4124*c[0]+0.3576*c[1]+0.1805*c[2])/0.95047; Y=0.2126*c[0]+0.7152*c[1]+0.0722*c[2]; Z=(0.0193*c[0]+0.1192*c[1]+0.9505*c[2])/1.08883
    f=lambda t: t**(1/3) if t>0.008856 else 7.787*t+16/116
    return 116*f(Y)-16, 500*(f(X)-f(Y)), 200*(f(Y)-f(Z))
def de2000(a,b):
    L1,a1,b1=lab(a);L2,a2,b2=lab(b)
    C1=math.hypot(a1,b1);C2=math.hypot(a2,b2);Cb=(C1+C2)/2
    G=0.5*(1-math.sqrt(Cb**7/(Cb**7+25**7)));a1p=(1+G)*a1;a2p=(1+G)*a2
    C1p=math.hypot(a1p,b1);C2p=math.hypot(a2p,b2)
    h1=math.degrees(math.atan2(b1,a1p))%360;h2=math.degrees(math.atan2(b2,a2p))%360
    dL=L2-L1;dC=C2p-C1p;dh=h2-h1
    if C1p*C2p==0: dh=0
    elif dh>180: dh-=360
    elif dh<-180: dh+=360
    dH=2*math.sqrt(C1p*C2p)*math.sin(math.radians(dh/2))
    Lb=(L1+L2)/2;Cbp=(C1p+C2p)/2
    hb=(h1+h2)/2 if abs(h1-h2)<=180 else (h1+h2+360)/2
    T=1-0.17*math.cos(math.radians(hb-30))+0.24*math.cos(math.radians(2*hb))+0.32*math.cos(math.radians(3*hb+6))-0.2*math.cos(math.radians(4*hb-63))
    SL=1+0.015*(Lb-50)**2/math.sqrt(20+(Lb-50)**2);SC=1+0.045*Cbp;SH=1+0.015*Cbp*T
    dth=30*math.exp(-((hb-275)/25)**2);RC=2*math.sqrt(Cbp**7/(Cbp**7+25**7));RT=-math.sin(math.radians(2*dth))*RC
    return math.sqrt((dL/SL)**2+(dC/SC)**2+(dH/SH)**2+RT*(dC/SC)*(dH/SH))
print("| palette | mode | brand↔danger | hi↔danger | brand↔warning | hi↔warning |\n|---|---|---|---|---|---|")
for n,p in P.items():
    for m in ("light","dark"):
        t=p[m]; print(f"| {n} | {m} | {de2000(t['brand'],t['danger']):.1f} | {de2000(t['hi'],t['danger']):.1f} | {de2000(t['brand'],t['warning']):.1f} | {de2000(t['hi'],t['warning']):.1f} |")
