# Machado et al. 2009 severity 1.0 matrices, applied in linear RGB
from deltae import de2000
from palettes_def import P
M={"protan":[[0.152286,1.052583,-0.204868],[0.114503,0.786281,0.099216],[-0.003882,-0.048116,1.051998]],
   "deutan":[[0.367322,0.860646,-0.227968],[0.280085,0.672501,0.047413],[-0.011820,0.042940,0.968881]]}
def sim(h,k):
    h=h.lstrip('#'); c=[int(h[i:i+2],16)/255 for i in (0,2,4)]
    c=[x/12.92 if x<=0.04045 else ((x+0.055)/1.055)**2.4 for x in c]
    o=[max(0,min(1,sum(M[k][r][j]*c[j] for j in range(3)))) for r in range(3)]
    o=[12.92*x if x<=0.0031308 else 1.055*x**(1/2.4)-0.055 for x in o]
    return "#%02X%02X%02X"%tuple(round(x*255) for x in o)
print("| palette | mode | brand↔danger protan | deutan | hi↔danger protan | deutan | hi↔warning protan | deutan |\n|---|---|---|---|---|---|---|---|")
for n,p in P.items():
  for m in ("light","dark"):
    t=p[m]; r=[]
    for a,b in (("brand","danger"),("hi","danger"),("hi","warning")):
      for k in ("protan","deutan"): r.append("%.1f"%de2000(sim(t[a],k),sim(t[b],k)))
    print(f"| {n} | {m} | "+" | ".join(r)+" |")
