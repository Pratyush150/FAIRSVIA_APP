import cv2, numpy as np
from PIL import Image, ImageFilter
im=Image.open('cut.png').convert('RGBA');a=np.array(im);rgb=np.ascontiguousarray(a[...,:3])
m=np.zeros(a.shape[:2],np.uint8)
for x0,y0,x1,y1 in [(144,287,183,333),(80,297,99,312)]: m[y0:y1,x0:x1]=255
rgb=cv2.inpaint(rgb,m,7,cv2.INPAINT_TELEA)
x0,y0,x1,y1=95,349,215,387  # plate interior -> blank white plate
patch=rgb[y0:y1,x0:x1].reshape(-1,3);lum=patch.mean(1);col=np.median(patch[lum>=np.percentile(lum,75)],0)
rgb[y0:y1,x0:x1]=np.clip(col[None,None,:]*np.linspace(1.03,0.96,y1-y0)[:,None,None],0,255)
a[...,:3]=rgb;out=Image.fromarray(a)
out=out.crop(out.split()[3].point(lambda v:255 if v>24 else 0).getbbox())
for size,path in [(512,'2.0x/ride.png'),(256,'ride.png')]:
  c=Image.new('RGBA',(size,size),(0,0,0,0));k=size/512
  w=round(496*k);s=w/out.width;h=round(out.height*s);sub=out.resize((w,h),Image.LANCZOS)
  ground=round(445*k);x=(size-w)//2
  sh=Image.new('RGBA',(size,size),(0,0,0,0));from PIL import ImageDraw
  ImageDraw.Draw(sh).ellipse((x+w*0.06,ground-h*0.06,x+w*0.94,ground+h*0.05),fill=(0,0,0,70))
  c.alpha_composite(sh.filter(ImageFilter.GaussianBlur(10*k)));c.alpha_composite(sub,(x,ground-h))
  for d in ['home','home_dark']: c.save(f'/home/nova-robotics/ubernav/packages/design_system/assets/{d}/{path}',optimize=True)
