from PIL import Image,ImageDraw,ImageFilter
import numpy as np
ph=Image.open('src/sXVzE285xo0_cut.png').convert('RGBA')
D,A,B,C=np.array([16,166.]),np.array([192,6.]),np.array([752,333.]),np.array([588,540.])
cen=(A+B+C+D)/4
def ins(p,k): return p+(cen-p)*k
# bezel inset: small along short edges
q=[ins(D,0.02),ins(A,0.02),ins(B,0.02),ins(C,0.02)]
W,H=440,900
S=3
cv=Image.new('RGBA',(W*S,H*S),(233,239,241,255));d=ImageDraw.Draw(cv)
teal=(18,140,138,255); teal2=(120,196,192,255)
cx,cy=W*S//2,int(H*S*0.40)
r=int(W*S*0.17)
# second (behind) person, lighter, offset right/up
bx,by=cx+int(r*1.25),cy-int(r*0.55)
d.ellipse([bx-int(r*0.75),by-int(r*1.5),bx+int(r*0.75),by],fill=teal2)
d.chord([bx-int(r*1.45),by+int(r*0.25),bx+int(r*1.45),by+int(r*3.0)],180,360,fill=teal2)
# ring gap then main person
g=int(r*0.18)
d.ellipse([cx-r-g,cy-int(r*2.0)-g,cx+r+g,cy+g],fill=(233,239,241,255))
d.chord([cx-int(r*1.9)-g,cy+int(r*0.3)-g,cx+int(r*1.9)+g,cy+int(r*3.9)+g],180,360,fill=(233,239,241,255))
d.ellipse([cx-r,cy-int(r*2.0),cx+r,cy],fill=teal)
d.chord([cx-int(r*1.9),cy+int(r*0.3),cx+int(r*1.9),cy+int(r*3.9)],180,360,fill=teal)
d.rounded_rectangle([cx-int(r*1.5),int(H*S*0.68),cx+int(r*1.5),int(H*S*0.68)+int(r*0.32)],radius=int(r*0.16),fill=(190,200,204,255))
d.rounded_rectangle([cx-int(r*1.5),int(H*S*0.77),cx+int(r*1.5),int(H*S*0.77)+int(r*0.6)],radius=int(r*0.3),fill=teal)
cv=cv.resize((W,H),Image.LANCZOS)
# homography: output(phone coords) -> input(canvas coords)
src=[(0,0),(W,0),(W,H),(0,H)]  # TL=D, TR=A, BR=B, BL=C
dst=q
M=[];bv=[]
for (x,y),(u,v) in zip(dst,src):
    M.append([x,y,1,0,0,0,-u*x,-u*y]);bv.append(u)
    M.append([0,0,0,x,y,1,-v*x,-v*y]);bv.append(v)
co=np.linalg.solve(np.array(M),np.array(bv))
warp=cv.transform(ph.size,Image.PERSPECTIVE,tuple(co),Image.BICUBIC)
# rounded screen mask: polygon of quad, slightly blurred
mk=Image.new('L',ph.size,0);ImageDraw.Draw(mk).polygon([tuple(p) for p in q],fill=255)
mk=mk.filter(ImageFilter.GaussianBlur(1.2))
wa=np.array(warp).astype(float); pa=np.array(ph).astype(float); m=np.array(mk)[...,None]/255.0
# keep glass sheen: add original screen luminance above its dark floor
L=pa[...,:3].mean(2,keepdims=True); sheen=np.clip((L-18)*1.2,0,60)
out=pa.copy(); out[...,:3]=pa[...,:3]*(1-m)+np.clip(wa[...,:3]*0.97+sheen,0,255)*m
Image.fromarray(out.astype(np.uint8)).save('src/phone_comp.png')
