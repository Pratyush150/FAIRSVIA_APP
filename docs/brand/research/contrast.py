
from palettes_def import P, MAP
def lum(h):
    h=h.lstrip('#'); c=[int(h[i:i+2],16)/255 for i in (0,2,4)]
    c=[x/12.92 if x<=0.04045 else ((x+0.055)/1.055)**2.4 for x in c]
    return 0.2126*c[0]+0.7152*c[1]+0.0722*c[2]
def cr(a,b):
    la,lb=sorted([lum(a),lum(b)],reverse=True); return (la+0.05)/(lb+0.05)
# (label, fg, bg, min, required)
CHECKS=[("text.primary / surface.1","text","s1",4.5,True),("text.secondary / surface.1","text2","s1",4.5,True),
 ("on.brand / brand","on","brand",4.5,True),("highlight / map grey","hi","MAP",3.0,True),
 ("brand / surface.1 (button edge)","brand","s1",3.0,False),("highlight / surface.1 (selected outline)","hi","s1",3.0,False),
 ("highlight / brand.tint","hi","tint",3.0,False),("text.secondary / surface.2","text2","s2",4.5,False),
 ("success / surface.1","success","s1",4.5,False),("warning / surface.1","warning","s1",4.5,False),("danger / surface.1","danger","s1",4.5,False)]
fails=0; out=[]
for name,p in P.items():
    out.append(f"\n## {name}")
    out.append("| check | light | dark |\n|---|---|---|")
    for label,f,b,mn,req in CHECKS:
        row=[label+("" if req else " *(extra)*")]
        for mode in ("light","dark"):
            t=p[mode]; bgc=MAP[mode] if b=="MAP" else t[b]
            r=cr(t[f],bgc); ok=r>=mn
            if not ok and req and not name.startswith("baseline"): fails+=1
            row.append(f"{r:.2f} {'pass' if ok else 'FAIL'}")
        out.append("| "+" | ".join(row)+" |")
print("\n".join(out)); print("\nREQUIRED FAILS (excluding baseline):",fails)
