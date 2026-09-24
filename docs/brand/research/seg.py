import numpy as np
from collections import deque
from maskview import hsvf
def grow(a, seed, allow, T=10):
    """flood from seed mask into allow mask where neighbour colour step < T"""
    H,W=seed.shape
    rgb=a[...,:3].astype(int)
    out=seed.copy()
    q=deque(zip(*np.nonzero(seed)))
    while q:
        y,x=q.popleft()
        for dy,dx in ((1,0),(-1,0),(0,1),(0,-1)):
            ny,nx=y+dy,x+dx
            if 0<=ny<H and 0<=nx<W and not out[ny,nx] and allow[ny,nx]:
                if np.abs(rgb[ny,nx]-rgb[y,x]).max()<T:
                    out[ny,nx]=True; q.append((ny,nx))
    return out
