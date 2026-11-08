"""S5's varied crook, arranged into an analytically closed race circuit.

Run to regenerate both simulator definitions and the layout evidence.
The Network generator is imported only for its unchanged curve primitives.
"""
from pathlib import Path
import json, math, re
import numpy as np
from design_network import varied_arc, walk

ROOT=Path(__file__).resolve().parents[1]
def arc(turn,radius,angle):
    return varied_arc(turn,radius,angle,'sp',max(6000,radius*.70),math.ceil(angle/50))

def segments():
    # A preserves S5's 7km tightening crook and 11km opening counter-sweep.
    # B is a flowing return with a broader apex and short power-on intervals.
    a=[('S',3000,0,'sp')]+arc('R',7000,120)+arc('L',11000,120)+arc('L',10000,90)
    b=[('S',2500,0,'sp')]+arc('L',14000,90)
    # GDScript divides Variant ints as integers; keep sampled lengths floating
    # point just like the existing course definitions and the JS simulator.
    return [tuple(float(v) if isinstance(v,(int,float)) else v for v in s) for s in a+b+a+b]

def main():
    segs=segments()
    pts,end=walk(segs,0,0,0)
    assert math.hypot(end[0],end[1])<1e-5 and abs(end[2]-math.tau)<1e-10
    # Distant portions must not cross or create hidden track shortcuts.
    from scipy.spatial import cKDTree
    p=np.array(pts[:-1])[::4]
    for i,j in cKDTree(p).query_pairs(230):
        assert min(abs(j-i),len(p)-abs(j-i))<=6, f'overlapping track at {i},{j}'
    body=json.dumps(segs,separators=(',',':'))
    for name,decl in [('sim-core.js','  const CARVING_SEGS = '+body+';'),('godot/sim/craft_sim.gd','const CARVING_SEGS := '+body)]:
        file=ROOT/name
        text=file.read_text(encoding='utf-8')
        pattern=r'(?m)^\s*const CARVING_SEGS.*$'
        if re.search(pattern,text): text=re.sub(pattern,lambda _:decl,text)
        else:
            marker='  const COURSES = {' if name.endswith('.js') else 'const COURSES := {'
            assert marker in text
            text=text.replace(marker,decl+'\n'+marker)
        file.write_text(text,encoding='utf-8')
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    fig,ax=plt.subplots(figsize=(10,8),facecolor='#101820')
    ax.set_facecolor('#101820')
    ax.plot(p[:,0]/1000,p[:,1]/1000,color='#efb15d',lw=2)
    ax.scatter([0],[0],color='white',s=40,label='Start / finish')
    ax.set_aspect('equal');ax.set_title('S5 CARVING CIRCUIT',color='white');ax.tick_params(colors='white')
    ax.set_xlabel('km',color='white');ax.set_ylabel('km',color='white');ax.grid(alpha=.15)
    ax.legend();(ROOT/'evidence').mkdir(exist_ok=True)
    fig.savefig(ROOT/'evidence/carving-layout.png',dpi=150,bbox_inches='tight')
    print(f'CARVING closure/nonintersection PASS: {len(segs)} segments, {len(pts)} samples')

if __name__=='__main__':main()
