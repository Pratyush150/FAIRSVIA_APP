from cars import *
from PIL import Image
res=[automobile('#2BC4C4'),automobile('#D9DDE2'),taxi('#5B6B80'),suv('#E8D5B5'),police('#3A3D42')]
import numpy as np
W=Image.new('RGBA',(512*3,512*2),(255,255,255,255))
for i,(b,w) in enumerate(res):
    im=Image.fromarray(b.clip(0,255).astype('uint8')).resize((512,512),Image.LANCZOS)
    W.alpha_composite(im,(512*(i%3),512*(i//3)))
W.save('carsv2.png')
