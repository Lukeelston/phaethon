"""Branching crown shells and opaque terminal sprays for close roadside trees."""
from math import cos,sin,pi
import random
import numpy as np
from geometry import unit,rgb_mul

def spray(m,p,direction,length,tint,rng):
    # Four folded, pointed clusters either side of a twig. The facets are rolled
    # towards the sun without alpha masks. Gaps between sprays survive mipmapping.
    d=unit(direction)
    side=unit(np.cross((0,0,1),d))
    for j in range(3):
        t=j/3
        for sign in (-1,1):
            b=p+d*t*length
            along=unit(d*.66+side*sign*(.64-.3*t)+(0,0,rng.uniform(-.56,.25)))
            width=unit(np.cross((0,0,1),along))
            sz=length*(.48-.16*t)
            tip=b+along*sz+(0,0,-.12*sz)
            middle=b+along*sz*.46
            left=middle-width*sz*.23;right=middle+width*sz*.23
            ridge=middle+np.array((0,0,sz*.14))
            shade=rgb_mul(tint,rng.uniform(.84,1.13))
            # Top wedge and a closed underside keep leaves visible from both VR eyes.
            for face in ([b,left,ridge],[left,tip,ridge],[tip,right,ridge],[right,b,ridge],[b,right,tip,left]):
                signed=list(face)
                # Polygon follows a consistent outward order around its ridge.
                m.face(signed,'leaf',shade)
def tree(m,swamp,crown):
    rng=random.Random(381 if swamp else 178)
    branches=10 if swamp else 13
    def tube(a,b,r1,r2):m.tube(a,b,r1,r2,'bark',(.74,.75,.66),7)
    # Mangroves divide into multiple leaning boles above a continuous prop-root skirt.
    if swamp:
        for b in range(4):
            ang=b*2.399
            d=np.array((cos(ang),sin(ang),0))
            top=d*(4.8+b*.35)+(0,0,12+b%2)
            tube(d*.7+(0,0,3.2),top,1.2,.62)
            for j in range(4):
                ang2=ang+(j-1.5)*.41
                side=np.array((cos(ang2),sin(ang2),0));knee=d*3+side*1.7+(0,0,4)
                tube(d*2.3+(0,0,8),knee,.60,.39)
                tube(knee,side*(6.3+.8*j)+(0,0,-.4),.39,.19)
    else:
        tube((0,0,-.5),(-.6,.2,5.5),2.2,1.62)
        tube((-.6,.2,5.5),(1,-.3,12.3),1.62,1.24)
        tube((1,-.3,12.3),(-.3,.7,19.3),1.24,.72)
        for j in range(6):
            ang=j*2.399
            toe=np.array((cos(ang)*3.3,sin(ang)*3.3,0))
            m.face([toe,(cos(ang+.6)*1.2,sin(ang+.6)*1.2,.15),(0,0,3.8)],'bark',(.63,.67,.58))
    for j in range(branches):
        a=j*2.399+(.9 if swamp else .35)
        d=np.array((cos(a),sin(a),0)); side=np.array((-sin(a),cos(a),0))
        if swamp:
            h=13.8+(j%4)*1.55
            radius=7.3+3.7*sin(j*.98)
            fork=d*3.5+(0,0,9.5+j%3)
        else:
            h=15.3+(j%5)*2.65
            radius=12.8-(j%5)*1.8+rng.uniform(-1,1)
            fork=np.array((.4,.15,8+(j%5)*1.9))
        elbow=d*(radius*.57)+side*.84+(0,0,h-4.6)
        tip=d*radius+(0,0,h)
        tube(fork,elbow,.94 if j%4==0 else .70,.50)
        tube(elbow,tip,.50,.28)
        for k in (-1,0,1):
            twig=tip+side*(k*2.8)+d*(.7+1.4*(k==0))+(0,0,1.1+1.3*(k!=0))
            tube(tip,twig,.29,.135)
            hue=(.83+rng.uniform(-.06,.06),.90+rng.uniform(-.07,.05),.77) if swamp else (.88+rng.uniform(-.07,.07),.93+rng.uniform(-.05,.05),.71)
            rad=rng.uniform(2.3,3.4)
            center=twig+(0,0,.75)
            crown(m,center,(rad*1.25,rad,rad*(.53 if swamp else .82)),j*.9+k,hue,7)
            for t in range(5):
                theta=t*2.399+j*.8+k
                forward=unit((cos(theta),sin(theta),rng.uniform(-.55,.47)))
                p=center+forward*rad*rng.uniform(.60,.86)
                spray(m,p,forward,rad*rng.uniform(.78,1.18),hue,rng)
