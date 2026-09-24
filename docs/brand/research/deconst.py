import re,subprocess,sys,os
os.environ['PATH']='/home/nova-robotics/flutter/bin:'+os.environ['PATH']
root='/home/nova-robotics/ubernav/'
pkgs=['packages/design_system','packages/core','apps/rider_app','apps/driver_app','apps/admin_app']
for it in range(8):
    total=0
    for d in pkgs:
        out=subprocess.run(['flutter','analyze'],cwd=root+d,capture_output=True,text=True).stdout
        errs=[]
        for line in out.splitlines():
            if ' error ' not in line: continue
            m=re.search(r'(lib/\S+\.dart|test/\S+\.dart):(\d+):(\d+)',line)
            if m and ('onstant' in line or 'const' in line): errs.append((m.group(1),int(m.group(2)),int(m.group(3))))
            elif m: print('OTHER',d,line.strip())
        total+=len(errs)
        # process each file, errors bottom-up
        byf={}
        for f,l,c in errs: byf.setdefault(f,[]).append((l,c))
        for f,locs in byf.items():
            path=root+d+'/'+f
            src=open(path).read()
            lines=src.split('\n')
            offs=[0]
            for ln in lines: offs.append(offs[-1]+len(ln)+1)
            done=set()
            for l,c in sorted(set(locs),reverse=True):
                pos=offs[l-1]+c-1
                # nearest preceding 'const' keyword (word-boundary) before pos
                seg=src[:pos]
                ms=[m for m in re.finditer(r'\bconst\s+', seg)]
                if not ms: continue
                m=ms[-1]
                if m.start() in done: continue
                done.add(m.start())
                src=src[:m.start()]+src[m.end():]
            open(path,'w').write(src)
    print('iteration',it,'const errors',total)
    if total==0: break
