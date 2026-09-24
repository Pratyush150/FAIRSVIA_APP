def h(x):
    x=x.lstrip('#');return tuple(int(x[i:i+2],16) for i in (0,2,4))
def L(c):
    r=[]
    for v in h(c) if isinstance(c,str) else c:
        v/=255; r.append(v/12.92 if v<=0.03928 else ((v+0.055)/1.055)**2.4)
    return 0.2126*r[0]+0.7152*r[1]+0.0722*r[2]
def cr(a,b):
    la,lb=L(a),L(b); 
    if la<lb: la,lb=lb,la
    return (la+0.05)/(lb+0.05)
def comp(fg,a,bg):
    f,b=h(fg),h(bg); return tuple(round(a*f[i]+(1-a)*b[i]) for i in range(3))
pairs={
'D light':[('#1C1A17','#FBF7F0'),('#5E574D','#FBF7F0'),('#5E574D','#FFFFFF'),('#FFFFFF','#0A6E6E'),('#0A6E6E','#FBF7F0'),('#0A6E6E','#FFFFFF'),('#F2A93B','#FFFFFF'),('#1C1A17','#F2A93B'),('#0A6E6E','#F3EDE2'),('#1C1A17','#E3F1EE')],
'D dark':[('#F6F1E8','#14110D'),('#B5AC9E','#1E1A15'),('#0E0F11','#3CCFCF'),('#3CCFCF','#1E1A15'),('#F2A93B','#1E1A15'),('#F6F1E8','#29241D')],
'E light':[('#0B0B0C','#FAFAF7'),('#55554F','#FAFAF7'),('#55554F','#FFFFFF'),('#FFFFFF','#0B0B0C'),('#0A7C7C','#FFFFFF'),('#0A7C7C','#FAFAF7'),('#DAD9D3','#FFFFFF'),('#8A8A83','#FFFFFF')],
'E dark':[('#F4F3EE','#0A0A0A'),('#A3A29B','#141413'),('#0A0A0A','#F4F3EE'),('#3FC9C9','#141413'),('#3FC9C9','#0A0A0A')],
'F light':[('#0F1417','#F7F8F9'),('#4A545C','#F7F8F9'),('#FFFFFF','#007A7A'),('#007A7A','#F7F8F9')],
'F dark':[('#F2F5F7','#15191D'),('#A7B0B8','#15191D'),('#0E1114','#35D0D0'),('#35D0D0','#15191D')],
}
for k,v in pairs.items():
    print(k)
    for a,b in v: print('  %s on %s: %.2f'%(a,b,cr(a,b)))
# glass composites
for mapc in ['#E9ECEF','#AAD3DF','#9FB7C4','#6B7780']:
    g=comp('#FFFFFF',0.72,mapc)
    print('light glass over',mapc,g,'text',round(cr('#0F1417',g),2),'sec',round(cr('#4A545C',g),2),'brand',round(cr('#007A7A',g),2))
for mapc in ['#1B2126','#2C3640','#46525C','#8A96A0']:
    g=comp('#12161A',0.70,mapc)
    print('dark glass over',mapc,g,'text',round(cr('#F2F5F7',g),2),'sec',round(cr('#A7B0B8',g),2),'brand',round(cr('#35D0D0',g),2))
for mapc in ['#9FB7C4','#6B7780','#FFFFFF']:
    g=comp('#FFFFFF',0.84,mapc); print('light 0.84 over',mapc,round(cr('#4A545C',g),2))
