"""Build the Fleet Workshop's compressed-air installation and pilot lockers.

All measurements are metres. The mounting wall is Z=0, the floor is Y=0, and
the fronts of both fixtures face +Z. The two indexed meshes share one finish.
"""
from pathlib import Path

import numpy as np
import trimesh
from PIL import Image, ImageDraw, ImageFont
from trimesh.visual.material import PBRMaterial

from art_workshop_equipment import Fixture, finish_atlas


DEST = Path(__file__).resolve().parents[1] / "godot/garage/workshop_room_fittings.glb"
AXLE_Y = 1.68


def support(m):
    m.block((0, AXLE_Y, .016), (.42, .46, .032), "dark", .012)
    for x in (-.173, .173):
        for offset in (-.187, .187):
            m.rod((x, AXLE_Y+offset, .030), (x, AXLE_Y+offset, .039), .019, "steel")
            m.rod((x, AXLE_Y+offset, .039), (x, AXLE_Y+offset, .050), .014, "bright", 6)
    # A cast arm and gussets carry the reel off the brick and liner.
    m.block((0, AXLE_Y, .079), (.202, .152, .104), "case", .014)
    for x in (-.073, .073):
        m.rod((x, AXLE_Y-.13, .036), (x, AXLE_Y-.03, .123), .025, "case")
    m.rod((0, AXLE_Y, .065), (0, AXLE_Y, .378), .072, "steel", 24)


def reel(m):
    front = (0, 0, 1)
    # The enclosed back is pressed sheet. The front has a rolled rim and four
    # open spokes, so the layers of hose can actually be seen through it.
    m.turned((0, AXLE_Y, .110), front, [(0,0),(0,.285),(.008,.301),(.018,.302),
             (.025,.296),(.026,.267),(.022,.251),(.022,.113),(.033,.103),(.033,0)], "case", 48)
    m.turned((0, AXLE_Y, .329), front, [(0,.253),(0,.291),(.008,.301),(.020,.301),
             (.027,.294),(.027,.257),(.022,.249),(.008,.248),(0,.253)], "case", 48)
    for theta in np.linspace(0, 2*np.pi, 4, endpoint=False) + .42:
        radial = np.array((np.cos(theta), np.sin(theta)))
        across = np.array((-radial[1], radial[0]))
        outline = [radial*r + across*w + (0, AXLE_Y) for r, w in
                   ((.066,-.043),(.119,-.038),(.256,-.030),(.275,-.020),
                    (.273,.034),(.249,.041),(.113,.052),(.072,.052))]
        m.cutout(outline, .350, .014, "case")
    m.turned((0, AXLE_Y, .328), front, [(0,0),(0,.109),(.009,.121),(.022,.120),
             (.036,.106),(.041,.081),(.044,.079),(.044,0)], "case", 40)
    m.turned((0, AXLE_Y, .369), front, [(0,0),(0,.061),(.006,.067),(.013,.066),
             (.019,.055),(.019,0)], "bright", 32)
    m.rod((0, AXLE_Y, .387), (0, AXLE_Y, .399), .029, "dark", 6)

    # The transverse courses around the drum show from the sides. An actual
    # continuous spiral on its front face feeds the visible free end.
    flank = [(0,0),(0,.231)]
    for i in range(10):
        offset = i*.017
        flank.extend([(offset+.005,.245),(offset+.012,.245),(offset+.017,.231)])
    flank.append((.17,0))
    m.turned((0, AXLE_Y, .141), front, flank, "ochre", 36)
    turns = 6.0
    points = []
    for t in np.linspace(0, 1, 229):
        angle = (1-t)*2*np.pi*turns
        radius = .136+.110*t
        points.append((np.cos(angle)*radius, AXLE_Y+np.sin(angle)*radius, .315))
    points += [(.246,1.57,.315),(.234,1.41,.312),(.228,1.25,.311),
               (.238,1.06,.308),(.258,.92,.304),(.260,.82,.302)]
    m.sweep(points, .0095, "ochre", 10)
    # Rubber bumper parks the line against the roller guide when it retracts.
    for x in (.182,.287):
        m.block((x,1.421,.304),(.020,.059,.145),"dark",.009)
    m.block((.234,1.422,.235),(.119,.056,.019),"case",.006)
    m.rod((.182,1.421,.253),(.287,1.421,.253),.019,"bright")
    m.rod((.182,1.421,.362),(.287,1.421,.362),.019,"bright")
    m.turned((.238,1.30,.311),(0,1,0),[(0,0),(0,.015),(.009,.032),(.021,.041),
             (.039,.040),(.050,.029),(.055,.017),(.055,0)],"rubber",24)
    m.turned((.260,.822,.302),(0,-1,0),[(0,0),(0,.012),(.005,.015),(.023,.015),
             (.026,.0128),(.029,.016),(.040,.016),(.042,.012),(.051,.012),(.055,.015),
             (.073,.015),(.076,.009),(.076,.005),(.061,.005),(.061,0)],"bright",20)


def supply(m):
    x, z = -.52, .068
    # The pipe runs to the ceiling. Offset saddles attach it to the liner.
    m.rod((x,1.178,z),(x,3.25,z),.018,"steel")
    for y in (1.24,2.22,3.07):
        m.block((x,y,.025),(.086,.042,.048),"dark",.006)
        m.turned((x,y-.018,z),(0,1,0),[(0,0),(0,.022),(.006,.027),(.029,.027),
                 (.035,.022),(.035,0)],"bright")
        for dx in (-.035,.035):
            m.rod((x+dx,y,.046),(x+dx,y,.053),.007,"steel",6)
    m.turned((x,1.48,z),(0,1,0),[(0,0),(0,.025),(.015,.033),(.029,.033),
             (.045,.023),(.138,.024),(.154,.033),(.171,.033),(.183,.025),(.183,0)],"insert",16)
    m.rod((x,1.58,z),(x,1.58,z+.063),.017,"bright")
    m.block((x,1.644,z+.072),(.027,.154,.019),"ochre",.008)
    m.block((x,1.145,z),(.072,.067,.066),"insert",.010)
    # A formed hard line returns to the axle's rear swivel fitting.
    m.sweep([(x,1.146,z),(-.393,1.146,z),(-.351,1.166,z),(-.326,1.211,.074),
             (-.318,1.50,.08),(-.282,1.622,.084),(-.214,AXLE_Y,.087),
             (-.076,AXLE_Y,.087)],.012,"steel",12)
    for nut_x in (-.477,-.117):
        nut_y = 1.146 if nut_x < -.4 else AXLE_Y
        nut_z = z if nut_x < -.4 else .087
        m.rod((nut_x-.010,nut_y,nut_z),(nut_x+.013,nut_y,nut_z),.020,"bright",6)


def label(m, x, y, z, width, height, slot):
    """Folded card holder with a legible ID or the designation of the open bay."""
    m.block((x,y,z), (width+.014,height+.014,.013), "dark", .004)
    for dy in (-1,1):
        m.block((x,y+dy*(height+.006)/2,z+.008),(width+.012,.006,.008),"bright",.002)
    m.poly([(x-width/2,y+height/2,z+.007),(x-width/2,y-height/2,z+.007),
            (x+width/2,y-height/2,z+.007),(x+width/2,y+height/2,z+.007)],
           (0,0,1),"worktop",[(slot/3,0),(slot/3,1),((slot+1)/3,1),((slot+1)/3,0)])


def locker_door(m, x, slot):
    """A folded door blank with real punched openings for its vents and latch."""
    left, right = x-.244, x+.244
    bottom, top = .170, 1.854
    front, rear = .643, .628
    vents = [1.485+.058*i for i in range(4)] + [.282,.340]
    latch_x, latch_y = x+.160, .984
    holes = [(x-.132,y-.009,x+.132,y+.010) for y in vents]
    holes.append((latch_x-.043,latch_y-.098,latch_x+.043,latch_y+.098))
    xs = sorted({left,right,*[a for hole in holes for a in (hole[0],hole[2])]})
    ys = sorted({bottom,top,*[a for hole in holes for a in (hole[1],hole[3])]})
    for x0,x1 in zip(xs,xs[1:]):
        for y0,y1 in zip(ys,ys[1:]):
            if any(a<(x0+x1)/2<c and b<(y0+y1)/2<d for a,b,c,d in holes):
                continue
            for z,normal in ((front,(0,0,1)),(rear,(0,0,-1))):
                m.poly([(x0,y0,z),(x1,y0,z),(x1,y1,z),(x0,y1,z)],normal,"case")
    # The folded outer edge and the returns behind each actual aperture.
    for rect in [(left,bottom,right,top),*holes]:
        a,b,c,d = rect
        for (x0,y0),(x1,y1),normal in [((a,b),(c,b),(0,-1,0)),((c,b),(c,d),(1,0,0)),
                                      ((c,d),(a,d),(0,1,0)),((a,d),(a,b),(-1,0,0))]:
            outward = np.asarray(normal) if rect == (left,bottom,right,top) else -np.asarray(normal)
            m.poly([(x0,y0,rear),(x1,y1,rear),(x1,y1,front),(x0,y0,front)],outward,"dark")
    for y in vents:
        profile = [(y+.024,front),(y+.020,front+.006),(y+.002,front+.021),
                   (y-.004,front+.023),(y-.006,front+.020)]
        for (ay,az),(by,bz) in zip(profile,profile[1:]):
            m.poly([(x-.135,ay,az),(x+.135,ay,az),(x+.135,by,bz),(x-.135,by,bz)],
                   (0,bz-az,ay-by),"case")
        for side in (-1,1):
            points = [(x+side*.135,py,pz) for py,pz in profile]
            points.append((x+side*.135,profile[-1][0],front))
            m.poly(points,(side,0,0),"case")
    # Recessed pull well, rolled handle lip, and a separate keyed barrel.
    m.block((latch_x,latch_y,rear-.017),(.106,.223,.018),"dark",.009)
    for side in (-1,1):
        m.block((latch_x+side*.041,latch_y,front-.009),(.009,.201,.033),"steel",.003)
    for y in (latch_y-.096,latch_y+.096):
        m.block((latch_x,y,front-.009),(.082,.009,.033),"steel",.003)
    m.rod((latch_x-.019,latch_y-.058,.623),(latch_x-.019,latch_y-.058,.646),.009,"bright")
    m.rod((latch_x-.019,latch_y+.054,.623),(latch_x-.019,latch_y+.054,.646),.009,"bright")
    m.rod((latch_x-.019,latch_y-.060,.646),(latch_x-.019,latch_y+.056,.646),.009,"bright")
    m.turned((latch_x,1.132,.641),(0,0,1),[(0,0),(0,.021),(.005,.023),(.010,.021),
             (.012,.016),(.012,0)],"bright",20)
    m.block((latch_x,1.132,.654),(.0037,.014,.002),"rubber",.0008)
    for y in (.488,1.412):
        m.rod((left+.009,y-.054,.646),(left+.009,y+.054,.646),.012,"steel",12)
        m.rod((left+.009,y-.042,.646),(left+.009,y+.038,.646),.015,"case",16)
    label(m,x,1.77,.649,.122,.040,slot)


def locker_bank(m):
    # The open centre compartment exposes the actual shelf depths and returns.
    m.block((0,.065,.32),(1.52,.130,.55),"rubber",.010)
    m.block((0,.145,.325),(1.56,.032,.610),"dark",.008)
    m.block((0,1.009,.038),(1.56,1.695,.038),"insert",.008)
    for x in (-.788,-.258,.258,.788):
        m.block((x,1.016,.326),(.022,1.775,.614),"case",.007)
        m.block((x,1.017,.632),(.034,1.746,.018),"dark",.004)
    m.block((0,1.900,.329),(1.610,.042,.646),"case",.011)
    for y in (.183,.794,1.289):
        m.block((0,y,.324),(.503,.028,.600),"steel",.005)
        m.block((0,y-.010,.617),(.495,.038,.019),"bright",.004)
        if y > .2:
            for x in (-.238,.238):
                m.block((x,y-.025,.36),(.023,.027,.45),"dark",.004)
    m.block((0,1.848,.611),(.503,.079,.030),"case",.005)
    label(m,0,1.852,.634,.180,.037,1)
    locker_door(m,-.519,0)
    locker_door(m,.519,2)


def draw_cards(atlas, orm):
    card = Image.new("RGB",(180,42),"#d2c8a4")
    font = ImageFont.truetype(str(DEST.parents[1]/"art/signs/RG2014D.ttf"),30)
    for i,words in enumerate(("01","PILOT KIT","02")):
        face = card.copy()
        ImageDraw.Draw(face).text((90,21),words,font=font,anchor="mm",fill="#293b3d")
        x0, x1 = round((1024-11)*i/3+5), round((1024-11)*(i+1)/3+5)
        atlas.paste(face.resize((x1-x0,246),Image.Resampling.LANCZOS),(x0,5))
        ImageDraw.Draw(orm).rectangle((x0,5,x1-1,250),fill=(255,184,0))


def build():
    air, lockers = Fixture(), Fixture()
    support(air)
    reel(air)
    supply(air)
    locker_bank(lockers)
    colors, orm = finish_atlas()
    draw_cards(colors,orm)
    material = PBRMaterial(name="RoomFittings", baseColorTexture=colors.resize((512,256)),
                           metallicRoughnessTexture=orm.resize((512,256)),
                           metallicFactor=1., roughnessFactor=1.)
    scene = trimesh.Scene()
    for name,fixture in [("WindingDrum",air),("LockerBank",lockers)]:
        mesh = trimesh.Trimesh(fixture.pos, np.asarray(fixture.indices).reshape(-1,3),
                               vertex_normals=fixture.norm, process=False)
        assert np.all(mesh.area_faces > 1e-12), f"Degenerate {name} faces"
        normals = np.asarray(fixture.norm)[mesh.faces].mean(axis=1)
        assert np.all((mesh.face_normals*normals).sum(axis=1) > 0), f"Inverted {name} faces"
        mesh.visual = trimesh.visual.TextureVisuals(uv=fixture.uv,material=material)
        scene.add_geometry(mesh,node_name=name,geom_name=name)
        print(f"{name}: {len(mesh.faces):,} triangles, one surface")
    DEST.write_bytes(scene.export(file_type="glb"))


if __name__ == "__main__":
    build()
