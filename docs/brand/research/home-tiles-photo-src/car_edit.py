from PIL import Image,ImageDraw,ImageFilter
import numpy as np
im=Image.open('src/car_crop.png').convert('RGB')
a=np.array(im).astype(float)
# plate: interior 1438-1670 x, 568-622 y -> plain plate with the plate's own light grey
px0,px1,py0,py1=1440,1668,569,621
plate=a[py0:py1,px0:px1]
bright=plate[plate.mean(2)>120]
col=np.median(bright,0)
h=py1-py0
grad=np.linspace(1.04,0.96,h)[:,None,None]
print(col); a[py0:py1,px0:px1]=np.clip(np.array([200,201,203])*grad,0,255)
# badge: copy grille patch from the right, feathered
bx0,bx1,by0,by1=1490,1612,466,548
src=a[by0:by1,bx0+105:bx1+105].copy()
mask=np.zeros((by1-by0,bx1-bx0));
m=Image.new('L',(bx1-bx0,by1-by0),0);ImageDraw.Draw(m).ellipse([4,4,bx1-bx0-4,by1-by0-4],fill=255)
m=np.array(m.filter(ImageFilter.GaussianBlur(4)))/255.0
a[by0:by1,bx0:bx1]=a[by0:by1,bx0:bx1]*(1-m[...,None])+src*m[...,None]
Image.fromarray(a.astype(np.uint8)).save('src/car_clean.png')
Image.fromarray(a.astype(np.uint8)).crop((1350,420,1750,680)).save('car_clean_zoom.png')
