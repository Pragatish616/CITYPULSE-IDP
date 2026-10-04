import re,sys,glob
def toks(s): return re.findall(r"[a-z0-9]+", s.lower())
draft=toks(open(sys.argv[1]).read())
src={}
for f in sys.argv[2:]:
    t=toks(open(f,errors='ignore').read()); src[f]=set(tuple(t[i:i+6]) for i in range(len(t)-5))
hits={}
for i in range(len(draft)-5):
    g=tuple(draft[i:i+6])
    for f,S in src.items():
        if g in S: hits.setdefault(f,[]).append(i)
for f,idx in hits.items():
    # merge runs
    runs=[];s=idx[0];p=idx[0]
    for j in idx[1:]:
        if j>p+1: runs.append((s,p)); s=j
        p=j
    runs.append((s,p))
    for a,b in runs:
        if b-a+6>=6: print(f.split('/')[-1], b-a+6, ' '.join(draft[a:b+6]))
