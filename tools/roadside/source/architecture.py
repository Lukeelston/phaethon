"""Trackside architecture. Compound assets share one surface per instance batch."""
from math import sin,cos,pi
import numpy as np
from geometry import WHITE

TEAL=(.27,.48,.48)
CREAM=(1,.94,.76)
EMBER=(.89,.40,.21)
IRON=(.34,.39,.40)
RED=(.79,.39,.30)
GLASS=(.86,.99,1)
def slab(m,x,y,z,w,d,h,finish,tint,ch=3):
    pts=[(-w/2+ch,-d/2),(w/2-ch,-d/2),(w/2,-d/2+ch),(w/2,d/2-ch),
         (w/2-ch,d/2),(-w/2+ch,d/2),(-w/2,d/2-ch),(-w/2,-d/2+ch)]
    m.rings([[(x+a,y+b,k) for a,b in pts] for k in (z,z+h)],finish,tint)
def house(m,x,y,w,d,wall,profile,finish,tint,roof_tint):
    m.box((x,y,wall/2),(w,d,wall),finish,tint)
    coords=[(-w/2-.7,wall)]+[(a,b+wall) for a,b in profile]+[(w/2+.7,wall)]
    # The roof volume has deep eaves and a readable end gable.
    front=[(x+a,y-d/2-1,b) for a,b in coords]
    back=[(x+a,y+d/2+1,b) for a,b in coords]
    for j in range(1,len(front)-1):
        m.face([front[0],front[j+1],front[j]],finish,tint)
        m.face([back[0],back[j],back[j+1]],finish,tint)
    for j in range(len(front)-1):
        m.face([front[j],front[j+1],back[j+1],back[j]],'roof',roof_tint)
def hvac(m,x,y,z,w=5):
    m.box((x,y,z+1.2),(w,w*.75,2.4),'shutter',(.72,.75,.75))
    if m.near:m.tube((x,y,z+2.4),(x,y,z+2.72),w*.24,w*.23,'metal',IRON,10)
def gas_station(m):
    B=m.box; N=m.near
    slab(m,0,0,-5,232,163,5,'asphalt',(.85,.86,.84),8)
    # Service hall at the back, with a public glazed concourse and a separate bay.
    B((-15,43,8),(103,32,16),'concrete',CREAM)
    B((-15,43,16.9),(108,36,1.8),'metal',TEAL)
    m.panel(-23,26.88,2,70,10,'glazing',GLASS)
    m.panel(26,26.86,.4,12,12,'shutter',(.74,.78,.76))
    # The two floating wedge canopies rise towards the outer tips.
    for side in (-1,1):
        span=79; x=side*40
        for edge_y in (-40,-5):
            front=[(0,edge_y,20),(side*span,edge_y,25),(side*span,edge_y,28),(0,edge_y,23)]
            if (side==1)==(edge_y==-40):m.face(front,'enamel',EMBER)
            else:m.face(front[::-1],'enamel',EMBER)
        q=[(0,-40,23),(side*span,-40,28),(side*span,-5,28),(0,-5,23)]
        m.face(q if side==1 else q[::-1],'roof',CREAM)
        q=[(0,-40,20),(side*span,-40,25),(side*span,-5,25),(0,-5,20)]
        m.face(q[::-1] if side==1 else q,'metal',(.82,.85,.80))
        B((side*span,-22.5,26.5),(.5,35,3),'enamel',CREAM)
        for j in range(2):
            cx=side*(18+43*j); h=21+3*j
            if N:
                slab(m,cx,-23,.03,20,11,1,'concrete',(.83,.83,.76),2)
                m.tube((cx,-23,1),(cx,-23,13),1.3,.92,'metal',IRON,8)
                for yy in (-1,1):
                    m.tube((cx,-23,12),(cx+side*1.8,-23+yy*10,h+.9),.78,.52,'metal',(.58,.62,.60),6)
                for k in (-1,1):
                    px=cx+k*5
                    B((px,-23,4.3),(3.9,3,6.6),'enamel',CREAM)
                    m.panel(px,-24.52,1.45,3.7,6.1,'pump')
                    for dx in (-1,1):
                        m.tube((px+dx*2.8,-26,1),(px+dx*2.8,-26,2.6),.23,.23,'enamel',EMBER,6)
            else:
                B((cx,-23,h/2),(2.5,2.5,h),'metal',IRON)
                B((cx-5,-23,3),(4,3,6),'enamel',CREAM)
    B((90,-48,18),(2.8,4,36),'metal',TEAL)
    B((90,-48,35),(15,5,10),'enamel',EMBER)
    m.panel(90,-50.54,30.8,14.3,8.4,'fascia',WHITE if N else CREAM)
    if N:
        # Low pump islands, directional paint and a parked utility wagon establish scale.
        for dx in (-48,12,59):
            B((dx,-59,.065),(9,.55,.08),'enamel',CREAM)
            for side in (-1,1):
                B((dx+3.7,-59+side*.9,.07),(3,.48,.085),'enamel',CREAM,side*-.50)
        B((47,20,2.1),(12,5,2.6),'enamel',(.61,.63,.56))
        B((48.2,20,4.1),(6.9,4.4,1.8),'glazing',(.70,.84,.82))
        B((48.2,20,5.2),(7,4.6,.5),'enamel',(.77,.79,.67))
        for px in (43.4,50.8):
            for yy in (17.5,22.5):
                m.tube((px,yy-.29,1.4),(px,yy+.29,1.4),1.23,1.23,'enamel',(.16,.18,.18),10)
        m.panel(-58,26.82,11.4,15,4.4,'fascia')
        for xx in (-48,-22,6):hvac(m,xx,43,17.8,7)
        B((-22,23,13),(83,9,1.5),'enamel',TEAL)
        for xx in range(-66,64,15):
            B((xx,12,.065),(.45,14,.09),'enamel',CREAM,angle=-.28)
        for xx in (-59,-36,-6,17):
            B((xx,26.7,7),(1,.45,11),'metal',TEAL)
        for yy in (-34,-13):
            B((0,yy,19.8),(141,.33,.28),'enamel',CREAM)
        for px in (-99,102):
            m.tube((px,13,0),(px,13,20),.55,.35,'metal',IRON,8)
            B((px,11,20),(1.8,6,.8),'enamel',CREAM)
def farm(m):
    N=m.near; B=m.box
    slab(m,1,2,-2.1,99,89,2.1,'asphalt',(.99,.88,.68),5)
    house(m,-18,-4,36,44,13,[(-13,9),(0,15),(13,9)],'timber',RED,(.43,.48,.48))
    m.panel(-18,-26.1,.2,14,12,'timber',(.48,.43,.34))
    if N:
        B((-18,-26.4,12.5),(16,.7,.65),'enamel',CREAM)
        for xx in (-25.5,-18,-10.5):B((xx,-26.4,6),(.52,.5,12),'enamel',CREAM)
        for sign in (-1,1):
            m.tube((-18,-26.6,1),(-18+sign*7,-26.6,11.9),.33,.33,'enamel',CREAM,4)
        m.panel(-18,-27.04,17.6,6.5,4.6,'shutter',(.44,.41,.36))
        for xx in (-29,-7):
            m.panel(xx,-26.1,6.5,4.4,4.5,'glazing')
        B((-18,-4,28.35),(1.7,46,.6),'metal',(.65,.66,.60))
    for j,(x,y,r,h) in enumerate([(17,-14,7.2,29),(32,3,7,25),(17,15,7.2,26)]):
        n=16 if N else 8
        m.tube((x,y,0),(x,y,h),r,r,'metal',(.88,.92,.90),n)
        m.tube((x,y,h),(x,y,h+5.3),r*1.06,.55,'roof',(.62,.69,.68),n)
        if N:
            for z in (3,h*.48,h-1):
                m.tube((x,y,z),(x,y,z+.42),r+.1,r+.1,'metal',(.60,.65,.63),n)
            for dx in (-.48,.48):
                m.tube((x+dx,y-r-.3,.8),(x+dx,y-r-.3,h),.13,.13,'metal',IRON,4)
            for z in range(2,int(h),2):
                B((x,y-r-.3,z),(1.05,.25,.16),'metal',IRON)
    if N:
        for j in range(3):
            x=-34+j*18
            m.tube((x,30,3),(x+8,30,3),3,3,'timber',(.92,.82,.48),10)
def wind(m):
    N=m.near;n=20 if N else 6; B=m.box
    m.tube((0,0,-1),(0,0,2.5),9.5,8.7,'concrete',(.85,.85,.77),n)
    m.tube((0,0,2.5),(0,0,133),4.6,2,'enamel',(.96,.96,.91),n)
    if N:slab(m,0,4,130,9,22,8,'metal',(.93,.94,.89),2)
    else:B((0,4,134),(9,22,8),'metal',(.93,.94,.89))
    m.tube((0,-1,134),(0,-9.5,134),4.2,1.1,'enamel',CREAM,n)
    # Tapered, swept, twisted airfoils, with real thickness at the root.
    for j in range(3):
        angle=j*2*pi/3+.24
        radial=np.array([sin(angle),0,cos(angle)])
        cross=np.array([cos(angle),0,-sin(angle)])
        hub=np.array([0,-6.5,134])
        sections=[(2,1.8,0,0),(9,3.1,.4,.2),(19,4.5,1.4,.9),(44,2.8,2.7,1.6),(60,1.25,3.9,2.4),(67,.17,4.5,2.9)]
        if not N:sections=[sections[i] for i in (0,2,4,5)]
        rings=[]
        for dist,w,sweep,lean in sections:
            center=hub+radial*dist+cross*sweep+np.array((0,lean,0))
            rings.append([center+cross*(f*w)+np.array((0,dy*w,0)) for f,dy in ((-.57,0),(-.3,-.32),(.64,-.09),(.64,.1),(-.3,.32))])
        if not N:rings=[[row[i] for i in (0,2,4)] for row in rings]
        m.rings(rings,'enamel',(.99,.98,.92),smooth=1)
    if N:
        for z in (28,62,96):
            r=4.6-(z-2.5)/130.5*2.6
            m.tube((0,0,z),(0,0,z+.35),r+.08,r+.08,'metal',(.74,.76,.73),18)
        m.panel(0,-4.56,1,2.7,5.4,'shutter',(.57,.66,.63))
        B((0,6,138.4),(6,9,.8),'shutter',IRON)
def solar(m):
    B=m.box; N=m.near
    slab(m,0,0,-2,199,174,2,'asphalt',(.95,.89,.72),6)
    for row in range(4):
        for col in range(3 if N else 1):
            x=(col-1)*52 if N else 0; y=(row-1.5)*37
            w=47 if N else 151
            for side in (-1,1) if N else (0,):
                B((x+side*w*.29,y,3),(1.25,2.2,6),'metal',IRON)
            pts=[(x-w/2,y-10,4),(x+w/2,y-10,4),(x+w/2,y+10,10),(x-w/2,y+10,10)]
            m.face(pts,'pv',(.95,.98,1));m.face(pts[::-1],'metal',(.48,.53,.54))
            if N:
                for t in (-1,1):
                    B((x,y+t*10,7+t*3),(w+.7,.46,.52),'metal',(.84,.87,.86))
    B((79,71,4),(17,12,8),'shutter',CREAM)
def urban(m):
    B=m.box;N=m.near
    slab(m,0,0,-2,219,162,2,'asphalt',(.83,.86,.87),7)
    for j,(x,y,w,d,h,t) in enumerate([(-62,-27,44,36,36,CREAM),(5,-34,39,31,58,(.83,.89,.88)),
                                     (62,19,36,43,43,(.86,.78,.64)),(-34,43,48,30,25,(.78,.84,.78))]):
        B((x,y,h*.5),(w,d,h),'concrete',t)
        B((x,y,h-2),(w+.8,d+.8,3),'metal',TEAL)
        B((x,y,h+3),(w*.73,d*.64,6),'shutter',(.66,.74,.73))
        if N:
            for sign in (-1,1):
                B((x+sign*w*.5,y,h*.51),(.22,d-5,h-11),'glazing',GLASS)
                B((x,y+sign*d*.5,h*.51),(w-5,.22,h-11),'glazing',GLASS)
            for side in (-1,1):
                B((x+side*w*.24,y-d/2-.22,h*.52),(.85,.5,h*.8),'metal',(.68,.66,.59))
            B((x,y-d/2-2.2,5.1),(w*.46,5,1),'enamel',EMBER)
            m.panel(x,y-d/2-.2,.1,w*.37,4.5,'glazing',(.61,.75,.74))
            hvac(m,x,y,h+6,5)
            for side in (-1,1):
                B((x+side*(w/2-2.1),y,h/2),(3.7,d+.8,h+1),'concrete',(.67,.70,.66))
            for k in range(1,1+int(h/6)):
                B((x,y-d/2-.45,k*5.7),(w-4,.75,.52),'metal',(.69,.71,.65))
            if j in (1,2):
                extension_x=x-w*.45
                B((extension_x,y+d*.36,5.4),(w*.51,d*.82,10.8),'concrete',t)
                B((extension_x,y+d*.36,11.1),(w*.56,d*.86,.65),'timber',(.73,.78,.56))
                B((extension_x,y+d*.36,11.8),(w*.29,d*.35,1.3),'leaf',(.70,.83,.60))
        else:
            B((x,y,h*.53),(w+.1,d+.1,h*.57),'glazing',GLASS)
    if N:
        for xx in (-60,0,60):
            slab(m,xx,-68,.02,24,5,1,'concrete',CREAM,1)
def industrial(m,outpost=False):
    N=m.near; B=m.box
    slab(m,0,0,-2.6,126,103,2.6,'asphalt',(.91,.87,.78),5)
    x,y=-20,4
    if outpost:
        house(m,x,y,46,34,11,[(0,4)],'metal',(.69,.72,.65),(.44,.54,.54))
    else:
        B((x,y,8.5),(59,40,17),'metal',(.72,.79,.75))
        for j in range(3):
            # North-light sawtooth roof modules.
            cx=x-19+j*19
            house(m,cx,y,18,40,17,[(5.5,5)],'glazing',GLASS,(.54,.58,.56)) if N else B((cx,y,18.4),(16,38,3),'roof',(.56,.64,.61))
    m.panel(-20,y-20.12 if not outpost else y-17.12,1,24,9,'shutter',(.58,.64,.63))
    for j in range(2 if outpost else 3):
        xx=24+(j%2)*16; yy=-12+(j//2)*27; h=17+j*2
        m.tube((xx,yy,0),(xx,yy,h),6.3,6.3,'metal',CREAM,14 if N else 7)
        m.tube((xx,yy,h),(xx,yy,h+2.4),6.4,2.6,'roof',IRON,14 if N else 7)
        if N:
            m.tube((xx,yy,h*.45),(xx,yy,h*.45+1.2),6.36,6.36,'enamel',EMBER,14)
    if outpost:
        a=(-42,32,0);b=(-42,32,39)
        m.tube(a,b,1.1,.65,'metal',IRON,8 if N else 5)
        # Parabolic dish, tilted towards the sky, open concave front.
        origin=np.array(b); n=np.array((0,-.78,.625)); u=np.array((1,0,0));v=np.cross(n,u)
        ring=[origin+u*8*cos(i*2*pi/14)+v*8*sin(i*2*pi/14)+n*2 for i in range(14)]
        for j in range(14):
            fan=[origin,ring[j],ring[(j+1)%14]]
            m.face(fan,'enamel',CREAM);m.face(fan[::-1],'metal',(.66,.68,.63))
        if N:
            for j in (1,6,10):m.tube(ring[j],origin+n*6,.18,.12,'metal',IRON,5)
    else:
        for xx,h in ((27,49),(44,39)):
            yy=31
            m.tube((xx,yy,0),(xx,yy,h),3.3,2.4,'concrete',(.76,.72,.65),12 if N else 6)
            if N:
                for level in (.68,.85):
                    r=3.3-.9*level
                    m.tube((xx,yy,h*level),(xx,yy,h*level+2.1),r+.08,r+.04,'enamel',EMBER,12)
            m.tube((xx,yy,h),(xx,yy,h+.5),2.55,2.55,'metal',IRON,8)
    if N:
        B((-19,-21,10.5),(35,9,1),'enamel',TEAL)
        for xx in (-48,-1):m.tube((xx,20,2),(xx,20,13),.6,.6,'metal',EMBER,7)
def stilt(m):
    N=m.near;B=m.box
    for xx in (-12,12):
        for yy in (-10,10):
            m.tube((xx,yy,-2),(xx,yy,11.8),.86,.64,'timber',(.55,.52,.44),7 if N else 4)
    B((0,0,11.6),(33,28,1.3),'timber',(.66,.59,.45))
    # House is built at grade in its own coordinate space then elevated as a unit.
    shell=type(m)(m.name,N)
    house(shell,0,2,24,17,8,[(0,6)],'timber',(.76,.81,.66),(.40,.57,.53))
    if N:
        shell.panel(-4,-6.6,2.4,9,4,'glazing')
        shell.panel(7,-6.6,.1,3,6.8,'timber',(.45,.46,.37))
    for vert in shell.verts:
        v=list(vert);v[2]+=12.3;m.verts.append(tuple(v))
    start=len(m.verts)-len(shell.verts);m.indices.extend(i+start for i in shell.indices)
    if N:
        for xx in (-15,-7,1,9,15):B((xx,-13,13.8),(.45,.45,3),'timber')
        B((0,-13,15.3),(30.5,.55,.5),'timber')
        for xx in (-12,12):
            m.tube((xx,-10,2),(xx,10,9),.37,.37,'timber',IRON,4)
        for j in range(8):B((15,-14-j*1.4,11.6-j*1.45),(4.4,1.6,.55),'timber',(.79,.72,.59))
    else:
        m.face([(12.8,-24.6,1.3),(17.2,-24.6,1.3),(17.2,-13.3,12),(12.8,-13.3,12)],'timber',(.79,.72,.59))
