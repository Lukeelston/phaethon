"""Deterministic silhouettes for the Network's nine organic and two geological props."""
from math import cos,sin,pi,tau
import random
import numpy as np
from geometry import unit, rgb_mul
from canopy import tree

GOLD=pi*(3-5**.5)
def palm_frame(theta):
    return np.array((cos(theta),sin(theta),0)),np.array((-sin(theta),cos(theta),0))
def stem(m,points,radii,finish='bark',tint=(.76,.77,.68),n=7):
    for a,b,r,s in zip(points,points[1:],radii,radii[1:]):
        m.tube(a,b,r,s,finish,tint,n)
def crown(m,center,size,phase,tint,n=11,finish='leaf'):
    center=np.asarray(center);rx,ry,rz=size
    rings=[]
    for j,(z,k) in enumerate(((-.83,.27),(-.54,.77),(.02,1),(.56,.80),(.86,.34))):
        row=[]
        for i in range(n):
            a=tau*i/n+.11*sin(j*1.7+phase)
            variation=1+.14*sin(3*a+phase)+.10*cos(5*a-phase+j*.62)+.055*cos(a*7+j)
            row.append(center+(rx*k*variation*cos(a),ry*k*variation*sin(a),
                               rz*(z+.095*sin(4*a+phase+j)+.045*cos(7*a-j))))
        rings.append(row)
    m.rings(rings,finish,tint,smooth=1,shading=lambda j,i:.71+j*.071+.045*sin(i*3.2+phase))
def broadleaf(m,swamp=False):
    if m.near:
        tree(m,swamp,crown)
        return
    center=np.array((.7,-.45,13.5 if swamp else 12.3))
    stem(m,[(0,0,-.8),(-.8,.3,6),center,(.3,.6,21)],[2.15,1.55,1.18,.48],n=5)
    if swamp:
        for j in range(5):
            d,_=palm_frame(j*GOLD)
            stem(m,[center*.65,d*2.6+(0,0,6),d*(5.2+j%3)+(0,0,-1)],[.67,.55,.28],n=4)
    for j in range(6):
        a=j*GOLD+.5
        d,_=palm_frame(a)
        reach=(8.6+2.6*sin(j*2.3))*(1.12 if swamp else 1)
        end=d*reach+(0,0,(18.0 if swamp else 20.2)+3.2*(j%3))
        if j%2==0:
            m.tube(center,end,.73,.3,'bark',(.71,.71,.60),4)
        hue=(.68,.85,.73) if swamp else (.81+.075*sin(a),.93+.045*cos(a),.71+.05*sin(a))
        crown(m,end,(6.5+(j%2),5.8+.6*cos(a),5.2+.6*sin(a)),j*.81,hue,5)
    crown(m,(.5,0,25 if swamp else 27),(6.3,6,5.4),.9,(.88,.99,.76),5)
def conifer(m,snow=False):
    N=m.near
    m.tube((0,0,-.4),(.5,0,34),1.25,.18,'bark',(.76,.75,.65),8 if N else 5)
    tiers=12 if N else 5
    for j in range(tiers):
        t=j/(tiers-1);z=7+t*24;reach=8.75*(1-t)**.74+1.45
        count=(12-j//2) if N else (7-j//2)
        for k in range(count):
            a=k*tau/count+j*GOLD;direction,side=palm_frame(a)
            rad=reach*(.86+.16*cos(k*2.7+j))
            base=np.array((.48*t,0,z))
            if N:
                # Keel and swept side fans form separate, drooping branch tips.
                for angle,dist,offset in ((0,rad,0),(.34,rad*.70,rad*.22),(-.32,rad*.74,rad*.20)):
                    dr,sd=palm_frame(a+angle);c=base+direction*offset
                    tip=c+dr*dist+(0,0,-dist*.26)
                    ridge=c+dr*dist*.38+(0,0,1.3)
                    w=dist*.165
                    left=c+dr*dist*.54+sd*w+(0,0,-.48)
                    right=c+dr*dist*.54-sd*w+(0,0,-.52)
                    verts=[(c,ridge,left),(c,right,ridge),(ridge,tip,left),(ridge,right,tip)]
                    tint=(.80+.09*t,.89+.09*t,.82+.06*t)
                    for face in verts:
                        top=face if np.cross(face[1]-face[0],face[2]-face[0])[2]>0 else face[::-1]
                        m.face(top,'snow' if snow and (angle==0 or (k+j)%4==0) else 'needle',(.87,.93,.98) if snow and angle==0 else tint)
                    m.face([c,left,tip,right],'needle',(.64,.73,.72))
                    if angle==0:
                        for slot in range(1,5):
                            t2=slot/5
                            anchor=c+dr*dist*t2+(0,0,1.1-dist*.22*t2)
                            for handed in (-1,1):
                                outer=anchor+sd*handed*dist*.22*(1-.66*t2)+dr*dist*.20+(0,0,-dist*.19)
                                mid=(anchor+outer)*.5+np.array((0,0,.39))
                                vertices=[anchor,mid-dr*dist*.053,outer,mid+dr*dist*.053]
                                if np.cross(vertices[1]-anchor,outer-anchor)[2]<0:vertices.reverse()
                                m.face(vertices,'snow' if snow and slot<3 and k%3 else 'needle',(.81,.89,.91))
                                m.face(vertices[::-1],'needle',(.67,.79,.74))
            else:
                # One joined tier, scalloped eaves and a much narrower top ring.
                break
        if not N:
            rim=[]
            for i in range(2*count):
                a=i*tau/(2*count)+j
                r=reach*(1-.26*(i%2))
                rim.append((.45*t+cos(a)*r,sin(a)*r,z-1.25*(i%2==0)))
            for i in range(len(rim)):
                k=(i+1)%len(rim)
                m.face([rim[i],rim[k],(.45*t,0,z+5.6)],'snow' if snow else 'needle',
                       (.97,.99,.98) if snow else (.83,.92,.85))
                m.face([rim[k],rim[i],(.45*t,0,z-.8)],'needle',(.56,.65,.63))
    m.tube((.48,0,31),(.5,-.1,35),1.16,0,'snow' if snow else 'needle',(.95,.99,.92),6)
def palm(m):
    N=m.near
    pts=[(0,0,-.7),(-1.8,.5,12),(-1.7,.4,25),(.3,-.1,36),(2,-.3,42)]
    stem(m,pts,[1.85,1.22,.98,.85,.78],'bark',(.89,.87,.69),10 if N else 6)
    for j in range(15 if N else 10):
        a=j*GOLD;d,s=palm_frame(a);start=np.array(pts[-1]);r=10.2+3*sin(j*1.77)
        h=5.5 if j%3 else 8.5
        spine=[start+d*r*t+(0,0,h*sin(pi*t)-3.4*t) for t in np.linspace(0,1,7)]
        for k in range(6):
            t=(k+.5)/6;w=(.16+.85*sin(pi*t))*(1.45 if N else 2.2)
            left=spine[k]+s*w;right=spine[k]-s*w
            for sign,edge in ((1,left),(-1,right)):
                p=[spine[k],spine[k+1]+(0,0,.12),edge]
                top=p if sign==1 else p[::-1]
                m.face(top,'needle',(.91,.94,.65));m.face(top[::-1],'needle',(.67,.78,.53))
                if N:
                    for offset in (0,.55):
                        base=spine[k]*(1-offset)+spine[k+1]*offset
                        tip=base+s*sign*(1.1+w)+d*1.85+(0,0,-.85-.7*t)
                        fan=[base,base+d*1.2,tip]
                        m.face(fan if sign==1 else fan[::-1],'leaf',(.72,.90,.57))
                        m.face(fan[::-1] if sign==1 else fan,'leaf',(.67,.79,.52))
def reeds(m):
    rng=random.Random(97); N=m.near
    for j in range(26 if N else 6):
        a=j*GOLD;d,s=palm_frame(a)
        p=d*(.8+5.5*(j%7)/7); h=rng.uniform(3.8,9.3)
        peak=p+d*rng.uniform(-.5,1)+(0,0,h)
        m.tube(p,peak,.11 if N else .22,.07,'timber',(.83,.77,.48),4)
        if j%3:
            m.tube(peak-(0,0,1.25),peak,.22,.17,'bark',(.73,.53,.35),5)
        for k in range(3 if N else 2):
            dr,side=palm_frame(a+k*2.3)
            b=p+(0,0,h*(.14+.13*k));mid=b+dr*1.4+(0,0,h*.42)
            tip=mid+dr*1.35+(0,0,h*.12)
            pts=[b,mid-side*.25,tip,mid+side*.25]
            m.face(pts,'leaf',(.84,.82,.49));m.face(pts[::-1],'leaf',(.74,.76,.44))
def shrub(m):
    for j in range(8 if m.near else 4):
        d,_=palm_frame(j*GOLD);at=d*(2.3+j%3)+(0,0,2.3+j%3*.55)
        m.tube((0,0,.1),at,.39,.16,'bark',(.73,.71,.57),5)
        crown(m,at,(2.8,2.3,2.0),j*.87,(.92,.85,.61),7 if m.near else 4)
def cactus(m):
    N=m.near
    def fluted(x,y,z,h,r):
        sections=[(0,.78),(.17,1),(.76,.93),(.94,.73),(1,.20)]
        n=24 if N else 5
        if not N:sections=[sections[i] for i in (0,2,3,4)]
        rings=[[(x+r*k*(1-.16*(j%2))*cos(j*tau/n),y+r*k*(1-.16*(j%2))*sin(j*tau/n),z+h*t)
                for j in range(n)] for t,k in sections]
        m.rings(rings,'needle',(.90,.89,.70),smooth=1)
    fluted(0,0,-.25,18,1.75)
    for sign,z,h in [(-1,7.5,5.8),(1,10.3,3.7)]:
        stem(m,[(sign,0,z),(sign*2.7,.1,z+.1),(sign*4,.25,z+1.5)],
             [1.16,1.05,.94],'needle',(.86,.86,.66),8) if N else m.tube((sign,0,z),(sign*4,.25,z+1.5),1.12,.93,'needle',(.86,.86,.66),5)
        fluted(sign*4,.25,z+1.2,h,1.0)
def geology(m,basalt=False):
    rng=random.Random(171 if basalt else 36)
    specs=[]
    if basalt:
        for j in range(14 if m.near else 6):
            a=j*GOLD;d=4.3*j**.67
            specs.append((d*cos(a),d*sin(a),rng.uniform(5,8),rng.uniform(6,9),rng.uniform(27,76)*(1-j*.025),rng.uniform(.1,2)))
    else:
        specs=[(-3,0,11,9,11,.36),(8,4,7,5.7,7.7,1.7),(-10,-6,4.1,3.4,3.1,.9),(4,-7,5,3.8,4.2,.6)]
        if m.near:specs += [(12,-3,2.6,2.4,1.9,2),(-15,4,3,2.4,2.6,1)]
    if not m.near and not basalt:specs=specs[:3]
    for x,y,rx,ry,h,p in specs:
        n=6 if basalt else (9 if m.near else 6)
        sections=[(-.09,.79),(0,1),(.18,.96),(.78,.78),(.96,.66)] if basalt else [(-.07,.72),(.12,1),(.52,.85),(.89,.55),(1,.22)]
        if not m.near:sections=[sections[i] for i in ((0,1,3,4) if basalt else (0,2,4))]
        rings=[]
        for l,(z,k) in enumerate(sections):
            ring=[]
            for j in range(n):
                a=j*tau/n+p
                dr=1+.13*cos(3*a+p)+.07*sin(l*.9+j*1.9)
                ring.append((x+rx*(k*dr*cos(a)+z*.13),y+ry*(k*dr*sin(a)-z*.09),
                             h*(z+.06*sin(j*2.3+l*.6)*min(1,l))))
            rings.append(ring)
        tint=(.46,.48,.50) if basalt else (.96,.90,.75)
        m.rings(rings,'stone',rgb_mul(tint,.91+.14*rng.random()),
                shading=lambda l,j:.82+.045*l+.035*sin(j*3))
