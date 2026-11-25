"""Bake the fleet inspection bench, engraved front panel and annunciator legends."""
from pathlib import Path
import re

import numpy as np
import trimesh
from PIL import Image, ImageDraw, ImageFont
from trimesh.visual.material import PBRMaterial

from art_shrike_airframe import vec
from art_workshop_equipment import Fixture, drawers, finish_atlas

GODOT = Path(__file__).resolve().parents[1] / "godot"
DEST = GODOT / "garage"
FONT_DIR = GODOT / "art/signs"
BOARD = vec(-.47, 1.77, .138)
FACE_W, FACE_H = 2.40, 1.16
PRINT_SCALE = 800
ROW_TOP, ROW_STEP = .378, .138
COL_LEFT, COL_RIGHT = 1.615, 2.095
WINDOW_W, WINDOW_H = .366, .082
SPINDLE = vec(.996, 1.338, .418)
HANDWHEEL = SPINDLE + vec(0, 0, .408)
PROBE_AXIS = vec(.68, np.sqrt(1 - .68**2), 0)
GAUGE = SPINDLE + .286 * PROBE_AXIS + vec(0, 0, .352)
POINTER = GAUGE + vec(0, 0, .027)
RUNOUT = .00008  # Metres of radial eccentricity on the reference land.


def panel_type(size, heavy=False):
    return ImageFont.truetype(str(FONT_DIR / ("RG2014EM.ttf" if heavy else "RG2014D.ttf")), size)


def craft_names():
    """Build the printed bay list from the same roster used to park the craft."""
    roster = (GODOT / "sim/pilot_craft.gd").read_text(encoding="utf8")
    order = re.search(r"^const ORDER := \[(.+?)\]", roster, re.M)[1].split(",")
    mapping = re.search(r"^const NAMES := \{(.+?)\}", roster, re.M)[1]
    names = dict(re.findall(r'(\w+):\s*"([^"]+)"', mapping))
    return [names[key.strip()] for key in order]


def printed_faces():
    atlas = Image.new("RGB", (2048, 1024), "#233b40")
    d = ImageDraw.Draw(atlas)
    def pos(x, y):
        return (round(x * PRINT_SCALE), round(y * PRINT_SCALE))
    def lettering(x, y, text, size, color, heavy=False, anchor="lm"):
        d.text(pos(x, y), text, font=panel_type(round(size*PRINT_SCALE), heavy),
               fill=color, anchor=anchor)
    def section(x0, y0, x1, y1, color):
        d.rectangle([pos(x0,y0), pos(x1,y1)], fill=color)
    section(0,0,FACE_W,.196,"#e6e0c9")
    section(.031,.040,.047,.155,"#a66c2b")
    lettering(.073,.102,"ENGINE STATUS",.120,"#263b3e",True)
    section(0,.196,FACE_W,.299,"#374b4b")
    lettering(.081,.247,"BAY",.056,"#f1e9d2",True)
    lettering(.32,.247,"AIRFRAME",.056,"#f1e9d2",True)
    for x, title in [(COL_LEFT,"PORT"), (COL_RIGHT,"STARBOARD")]:
        lettering(x,.247,title,.055,"#f1e9d2",True,"mm")
    for i, name in enumerate(craft_names()):
        y = ROW_TOP+i*ROW_STEP
        section(0, y-ROW_STEP*.5, FACE_W, y+ROW_STEP*.5,
                "#2c4649" if i%2==0 else "#263e42")
        section(.228,y-.041,.231,y+.041,"#b69355")
        lettering(.081,y+.001,f"{i+1:02}",.080,"#e7c687",True)
        lettering(.313,y+.001,name.upper(),.088,"#f4f2e4")
        section(.062,y+.066,FACE_W-.062,y+.0675,"#587071")
    # Analog indicator face in the unused right-hand strip of the same texture.
    cx, cy, radius = 1984, 85, 59
    d.ellipse((cx-radius,cy-radius,cx+radius,cy+radius),fill="#efe8ce")
    for i in range(50):
        angle = np.deg2rad(-90+360*i/50)
        r0 = 44 if i % 5 == 0 else 49
        delta = np.array([np.cos(angle), np.sin(angle)])
        p, q = (cx,cy)+delta*r0, (cx,cy)+delta*55
        d.line((tuple(p),tuple(q)),fill="#273637",width=2 if i%5==0 else 1)
        if i % 5 == 0:
            d.text(tuple((cx,cy)+delta*36),str(i),font=panel_type(13,True),fill="#283837",anchor="mm")
    d.text((cx,cy+17),"0.01 mm",font=panel_type(10),fill="#334545",anchor="mm")
    d.rectangle((1955,172,2013,201),fill="#a13a22")  # Enamel needle.
    return atlas


def annunciator_legends():
    strip = Image.new("L",(384, 96*5))
    d = ImageDraw.Draw(strip)
    for i, word in enumerate(["OFF","QUEUED","CRANK","CATCH","RUN"]):
        cy = 96*i+48
        d.text((72,cy),word,font=panel_type(84,True),anchor="lm",fill=240)
        if i in (0,4):
            d.ellipse((22,cy-17,56,cy+17),outline=235, width=6,fill=240 if i==4 else 0)
        elif i == 1:
            d.line([(39,cy-18),(57,cy),(39,cy+18),(21,cy),(39,cy-18)], fill=235,width=6)
        else:
            for b in range(i):
                d.rectangle((22+13*b,cy+16-11*(b+1),31+13*b,cy+16),fill=240)
    strip.save(DEST / "inspection_readouts.png",optimize=True)


def counter(m):
    m.block((0,.927,.48),(3.60,.076,.86),"worktop",.017)
    m.block((0,.975,.074),(3.57,.085,.046),"steel",.009)
    # Two drawer pedestals frame the knee space below the measurement surface.
    for x,width in [(-1.34,.81),(1.28,.95)]:
        m.block((x,.064,.45),(width-.10,.127,.67),"rubber",.010)
        m.block((x,.492,.45),(width,.795,.765),"case",.015)
        drawers(m,x,width-.067,.143,[.261,.206,.143,.112],.835)
    m.block((-.035,.782,.149),(1.79,.206,.183),"dark",.009)
    m.block((-.035,.182,.36),(1.79,.065,.48),"steel",.009)
    # A lined catch tray holds the removed front ring and circlip.
    m.block((-.73,.975,.51),(1.04,.023,.53),"rubber",.01)
    for x in (-1.249,-.211):
        m.block((x,.991,.51),(.011,.026,.54),"steel",.003)
    for z in (.244,.776):
        m.block((-.73,.991,z),(1.05,.026,.011),"steel",.003)
    m.turned(vec(-.92,.989,.52),vec(0,1,0),[(0,.104),(0,.140),(.005,.143),
             (.016,.143),(.023,.135),(.023,.111),(.017,.103),(0,.104)],"bright",40)
    for j in range(6):
        a=np.pi*j/3
        x,z=-.92+.124*np.cos(a),.52+.124*np.sin(a)
        m.turned(vec(x,1.012,z),vec(0,1,0),[(0,.011),(.001,.010),(.001,.006),(.0002,.006)],
                 "dark",12)
    for row in range(2):
        for i in range(3):
            x,z=-.63+i*.104,.422+.16*row
            m.rod((x-.020,.999,z),(x+.022,.999,z),.009,"steel",10)
            m.rod((x+.021,.999,z),(x+.034,.999,z),.014,"bright",6)


def panel(m):
    x,y,z=BOARD
    m.block((x,y,.063),(FACE_W+.082,FACE_H+.078,.108),"dark",.028)
    m.block((x,y,.112),(FACE_W+.045,FACE_H+.044,.034),"steel",.012)
    m.block((x,y,.129),(FACE_W+.011,FACE_H+.010,.014),"case",.005)
    for i in range(6):
        at_y=y + FACE_H*.5 - (ROW_TOP+i*ROW_STEP)
        for column in (COL_LEFT,COL_RIGHT):
            at_x=x-FACE_W*.5+column
            m.block((at_x,at_y,z+.005),(WINDOW_W+.027,WINDOW_H+.017,.009),"rubber",.004)
            m.block((at_x,at_y,z+.009),(WINDOW_W+.012,WINDOW_H+.008,.008),"dark",.003)
    for sx in [-1,1]:
        for sy in [-1,1]:
            x1,y1=x+sx*(FACE_W/2-.021),y+sy*(FACE_H/2-.025)
            m.turned(vec(x1,y1,z),vec(0,0,1),[(0,0),(0,.010),(.003,.012),(.006,.009),
                     (.006,.004),(.003,.003),(.003,0)],"bright",12)


def bearing_saddle(m, x, z):
    """A cored casting with a lower sight opening and a bored bearing cradle."""
    # Follow each casting from the lower front edge around the saddle. Matching
    # inner/outer loops let the actual viewing aperture pass through both faces.
    arc = np.linspace(0,np.pi,17)
    outer = [(-.208,0),(.208,0),(.220,.011),(.220,.025),(.105,.281)]
    outer += [(.0885*np.cos(a),.317-.0885*np.sin(a)) for a in arc]
    outer += [(-.105,.281),(-.220,.025),(-.220,.011)]
    hole = [(-.109,.042),(.109,.042),(.120,.050),(.121,.064),(.105,.116)]
    hole += [(.096*np.cos(a),.132+.053*np.sin(a)) for a in arc]
    hole += [(-.105,.116),(-.121,.064),(-.120,.050)]
    outer, hole = (np.asarray(loop)+[x,1.021] for loop in (outer,hole))

    def offset(loop, distance):
        edges=np.roll(loop,-1,axis=0)-loop
        normals=np.column_stack((-edges[:,1],edges[:,0]))/np.linalg.norm(edges,axis=1)[:,None]
        previous=np.roll(normals,1,axis=0)
        return loop+distance*(previous+normals)/(1+(previous*normals).sum(axis=1)[:,None])

    rim, aperture=offset(outer,.003),offset(hole,-.003)
    def at(loop, index, depth):
        return vec(*loop[index],z+depth)
    for i in range(len(outer)):
        j=(i+1)%len(outer)
        for side in (-1,1):
            d=side*.036
            m.poly([at(rim,i,d),at(rim,j,d),at(aperture,j,d),at(aperture,i,d)],(0,0,side),"ochre")
        for loop,face,direction in [(outer,rim,1),(hole,aperture,-1)]:
            dx,dy=loop[j]-loop[i]
            wall=vec(dy,-dx,0)*direction/np.hypot(dx,dy)
            m.poly([at(loop,i,-.033),at(loop,j,-.033),at(loop,j,.033),at(loop,i,.033)],wall,"ochre")
            for side in (-1,1):
                d=side*.036
                m.poly([at(loop,i,side*.033),at(loop,j,side*.033),at(face,j,d),at(face,i,d)],
                       wall+vec(0,0,side),"ochre")


def inspection_stand(m):
    x,y,_=SPINDLE
    m.block((x,.980,.475),(.90,.030,.62),"rubber",.009)
    for z in (.253,.687):
        m.block((x,1.009,z),(.53,.03,.135),"steel",.009)
        bearing_saddle(m,x,z)
        m.turned(vec(x,y,z-.037),vec(0,0,1),[(0,.050),(0,.083),(.01,.088),
                 (.074,.088),(.08,.083),(.08,.05),(0,.05)],"dark",28)
        # Outboard retaining plates unbolt from the two accessible shaft ends.
        side = -1 if z < SPINDLE[2] else 1
        face_z=z+(.043 if side==1 else -.037)
        for a in np.deg2rad([45,135,225,315]):
            screw=vec(x+.067*np.cos(a),y+.067*np.sin(a),face_z)
            m.turned(screw,vec(0,0,side),[(0,0),(0,.006),(.002,.007),(.004,.006),
                     (.004,.003),(.002,.0025),(.002,0)],"steel",10)
        for dx in (-.239,.239):
            bolt=vec(x+dx,1.024,z+.013)
            m.turned(bolt,vec(0,1,0),[(0,.009),(0,.019),(.0025,.019),(.0035,.017),
                     (.0035,.009),(0,.009)],"steel",18)
            m.rod(bolt+vec(0,.0035,0),bolt+vec(0,.015,0),.013,"bright",6)

    # The instrument body and plunger share a radial measuring line. The
    # sliding stem meets the reference land just in front of the near bearing.
    contact_axis = SPINDLE + vec(0,0,GAUGE[2]-SPINDLE[2])
    mount=vec(x+.372,1.034,.672)
    m.block(mount,(.117,.077,.118),"dark",.008)
    m.rod(mount+vec(0,.035,0),mount+vec(0,.517,0),.013,"bright")
    joint=mount+vec(0,.474,0)
    m.rod(joint,GAUGE+vec(.020,0,-.035),.013,"steel")
    m.rod(joint-vec(0,0,.017),joint+vec(0,0,.018),.024,"dark")
    m.rod(contact_axis+.139*PROBE_AXIS,contact_axis+.237*PROBE_AXIS,.012,"dark")
    m.rod(contact_axis+.088*PROBE_AXIS,contact_axis+.15*PROBE_AXIS,.004,"bright",10)
    m.turned(GAUGE,vec(0,0,1),[(-.024,0),(-.024,.051),(-.017,.060),(.017,.060),
             (.017,.066),(.024,.066),(.028,.062),(.028,.057),(.024,.057),(.024,0)],"steel",48)
    # The central bearing pin stays still above the sweeping red needle.
    m.rod(POINTER-vec(0,0,.002),POINTER+vec(0,0,.004),.004,"dark",16)


def rotor(m):
    # Front-facing blisk on a bench spindle. Each swept blade has two finite-
    # thickness airfoil skins and a tip cap. The root sits inside the hub.
    x,y,_=SPINDLE
    m.rod((x,y,.177),(x,y,.843),.048,"bright",38)
    hub=SPINDLE
    m.turned(hub,vec(0,0,1),[(0,.046),(0,.101),(.016,.114),(.028,.133),(.087,.136),
             (.110,.121),(.123,.093),(.123,.062),(.113,.052),(.113,.046),(0,.046)],"steel",48)
    m.turned(hub+vec(0,0,.102),vec(0,0,1),[(0,.047),(0,.074),(.018,.079),(.034,.067),
             (.034,.052),(.030,.047),(0,.047)],"bright",32)
    for j in range(17):
        theta=2*np.pi*j/17
        def blade(u, v, side):
            r=.126+(.303-.126)*u
            a=theta+.30*u+(.34-.105*u)*(v-.5)
            # Offset tangentially from the camber surface to produce a blunt root
            # and a thinner tip, with a small leading/trailing radius.
            thick=(.0012+.0031*np.sin(np.pi*v))*(1-.55*u)
            return hub+vec(r*np.cos(a),r*np.sin(a),.051+.025*u+
                           (.085-.05*u)*(v-.5)+side*thick)
        for side in (-1,1):
            m.grid(3,5,lambda u,v: blade(u,v,side),"bright",side<0)
        for v in (0.,1.):
            m.grid(3,1,lambda u,t: blade(u,v,2*t-1),"steel",v==1)
        m.grid(1,5,lambda t,v: blade(1.,v,2*t-1),"steel",True)
    # Offset the polished measurement land 0.08 mm. At rest the offset is
    # perpendicular to the stylus, so a positive turn starts the dial at zero.
    eccentric=RUNOUT*vec(PROBE_AXIS[1],-PROBE_AXIS[0],0)
    land=vec(x,y,GAUGE[2]-.018)+eccentric
    m.turned(land,vec(0,0,1),[(0,.047),(0,.080),(.004,.088),(.030,.088),(.035,.082),
             (.035,.049),(.032,.047),(0,.047)],"bright",48)
    # The operator grips this rounded three-spoke wheel or its travelling knob.
    center=HANDWHEEL
    m.turned(center,vec(0,0,1),[(-.009,.091),(-.012,.097),(-.010,.104),(-.004,.109),
             (.004,.109),(.010,.104),(.012,.098),(.009,.091),(-.009,.091)],"case",48)
    m.turned(center,vec(0,0,1),[(-.014,.046),(-.014,.054),(-.007,.058),(.010,.058),
             (.016,.052),(.016,.046),(-.014,.046)],"steel",32)
    for i in range(3):
        ray=vec(np.cos(i*2*np.pi/3),np.sin(i*2*np.pi/3),0)
        m.rod(center+ray*.051,center+ray*.100,.009,"steel")
    grip=center+vec(-.050,.086,.007)
    m.rod(grip,grip+vec(0,0,.046),.008,"bright")
    m.turned(grip+vec(0,0,.021),vec(0,0,1),[(0,0),(0,.010),(.004,.015),(.009,.016),
             (.025,.016),(.030,.014),(.034,.010),(.034,0)],"ochre",20)


def print_mesh():
    x,y,z=BOARD
    points=[(x-FACE_W/2,y+FACE_H/2,z),(x-FACE_W/2,y-FACE_H/2,z),
            (x+FACE_W/2,y-FACE_H/2,z),(x+FACE_W/2,y+FACE_H/2,z)]
    uv=[(.5, .5),(.5,927.5),(1919.5,927.5),(1919.5,.5)]
    faces=[(0,1,2),(0,2,3)]
    start=len(points)
    dial=GAUGE+vec(0,0,.0245)
    points.append(dial); uv.append((1984,85))
    for j in range(49):
        t=np.pi*2*j/48
        points.append(dial+vec(np.cos(t),np.sin(t),0)*.0573)
        uv.append((1984+np.cos(t)*58,85-np.sin(t)*58))
        if j: faces.append((start,start+j,start+j+1))
    return points,faces,[(u/2048,1-v/1024) for u,v in uv]


def add_fixture(scene, fixture, name, material, pivot, texcoord=None):
    mesh=trimesh.Trimesh(np.asarray(fixture.pos)-pivot,np.asarray(fixture.indices).reshape(-1,3),
                         vertex_normals=fixture.norm,process=False)
    assert np.all(mesh.area_faces > 1e-12), f"degenerate triangles on {name}"
    averaged_normals=mesh.vertex_normals[mesh.faces].mean(axis=1)
    assert np.all((averaged_normals*mesh.face_normals).sum(axis=1)>.50), f"inverted normals on {name}"
    uv=fixture.uv if texcoord is None else np.tile(texcoord, (len(mesh.vertices),1))
    mesh.visual=trimesh.visual.TextureVisuals(uv=uv,material=material)
    scene.add_geometry(mesh,node_name=name,geom_name=name,
                       transform=trimesh.transformations.translation_matrix(pivot))


def build():
    colors,orm=finish_atlas()
    finish=PBRMaterial(name="InspectionFixtures",baseColorTexture=colors.resize((512,256)),
                       metallicRoughnessTexture=orm.resize((512,256)),
                       metallicFactor=1.,roughnessFactor=1.)
    scene=trimesh.Scene()
    body=Fixture()
    counter(body); panel(body); inspection_stand(body)
    add_fixture(scene,body,"InspectionBench",finish,vec(0,0,0))
    spinning=Fixture()
    rotor(spinning)
    add_fixture(scene,spinning,"RotatingAssembly",finish,SPINDLE)
    points,faces,uv=print_mesh()
    printed=trimesh.Trimesh(points,faces,process=False)
    assert np.all(printed.face_normals[:,2]>.99)
    print_mat=PBRMaterial(name="EngravedFace",baseColorTexture=printed_faces(),metallicFactor=.08,
                          roughnessFactor=.64)
    printed.visual=trimesh.visual.TextureVisuals(uv=uv,material=print_mat)
    scene.add_geometry(printed,node_name="PanelLegends",geom_name="PanelLegends")
    needle=Fixture()
    outline=[(-.0026,-.014),(-.0018,-.017),(.0018,-.017),(.0026,-.014),
             (.0015,-.005),(.0024,.010),(.0006,.048),(0,.053),(-.0006,.048),
             (-.0024,.010),(-.0015,-.005)]
    needle.cutout([(x+POINTER[0],y+POINTER[1]) for x,y in outline],
                  POINTER[2],.001,"steel")
    add_fixture(scene,needle,"IndicatorNeedle",print_mat,POINTER,(1984/2048,1-188/1024))
    (DEST/"inspection_station.glb").write_bytes(scene.export(file_type="glb"))
    annunciator_legends()
    print(f"Inspection station: {sum(len(m.faces) for m in scene.geometry.values()):,} triangles")


if __name__=="__main__":
    build()
