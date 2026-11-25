"""Bake the workshop's parked double-girder crane, in metres with Y up.

The bridge and hoist have separate local origins for vertex precision and LOD.
Run with Python, NumPy, trimesh and Pillow, as for art_workshop_equipment.py.
"""

from pathlib import Path

import numpy as np
import trimesh
from PIL import Image, ImageDraw, ImageFont
from trimesh.visual.material import PBRMaterial

from art_shrike_airframe import unit, vec
from art_workshop_equipment import Fixture


DEST = Path(__file__).resolve().parents[1] / "godot/garage/workshop_crane.glb"
LETTERING = DEST.parents[1] / "art/signs/RG2014D.ttf"
RUNWAY_X = 30.4
# Park at the entrance clerestory, with 0.51 m between the buffer and end stop.
PARKED_BRIDGE_Z = 20.60
PARKED_TROLLEY_X = -10.5
RUNWAY_TREAD_Y = 5.421
TROLLEY_TREAD_Y = 4.9655
# The painted and machined finishes share a padded atlas with the capacity plate.
FINISHES = {
    "beam": ("c3954a", .52, .34),
    "edge": ("aa763b", .46, .40),
    "steel": ("63787b", .40, .75),
    "track": ("aab2a9", .31, .85),
    "graphite": ("37454b", .50, .49),
    "rubber": ("232b2e", .81, .02),
    "green": ("65877b", .43, .34),
    "warning": ("e4b866", .53, .34),
    "forged": ("9eaca5", .48, .46),
    "wire": ("afb6aa", .39, .58),
}
TILE = 96
ATLAS_SIZE = (4*TILE,3*TILE)
REGIONS = {name: (i%4*TILE,i//4*TILE,TILE,TILE) for i,name in enumerate(FINISHES)}
REGIONS["capacity"] = (2*TILE,2*TILE,2*TILE,53)


class CraneMesh(Fixture):
    def vertex(self, p, n, uv, region):
        x,y,w,h = REGIONS[region]
        u,v = uv
        self.pos.append(p)
        self.norm.append(n)
        self.uv.append(((x + 4.5 + u*(w-9)) / ATLAS_SIZE[0], 1 - (y + 4.5 + v*(h-9)) / ATLAS_SIZE[1]))

    def oriented_block(self, center, rotation, size, finish, radius):
        start = len(self.pos)
        self.block((0,0,0),size,finish,radius)
        for i in range(start, len(self.pos)):
            self.pos[i] = center + rotation @ self.pos[i]
            self.norm[i] = rotation @ self.norm[i]

    def beam_between(self, a, b, width, depth, finish):
        a, b = np.array(a), np.array(b)
        direction = unit(b-a)
        # All local bridge and runway diagonals lie in vertical/transverse planes.
        helper = vec(0,0,1) if abs(direction[2]) < .9 else vec(0,1,0)
        right = unit(np.cross(direction, helper))
        rotation = np.column_stack([right, direction, np.cross(right, direction)])
        self.oriented_block((a+b)/2,rotation,(width,np.linalg.norm(b-a),depth),finish,.008)


def finish_atlas():
    rng = np.random.default_rng(6819)
    color = Image.new("RGB", ATLAS_SIZE)
    orm = Image.new("RGB", color.size)
    yy, xx = np.mgrid[0:TILE,0:TILE]
    for i, (name, (rgb, roughness, metallic)) in enumerate(FINISHES.items()):
        grain = rng.normal(0, 1, (TILE,TILE))
        base = np.frombuffer(bytes.fromhex(rgb), dtype=np.uint8)
        pigment = np.broadcast_to(base, (TILE,TILE,3)).astype(float).copy()
        if name in ("steel", "track"):
            grain += rng.normal(0, .9, (TILE,1))
        if name == "warning":
            pigment[(xx-yy*.55) % 46 < 19] = (45,54,51)
        if name == "forged":
            # A sling polishes the inside radius in the bowl and toward the beak.
            along = np.clip((yy/TILE-.12)*5,0,1)*np.clip((1.06-yy/TILE)*4,0,1)
            bearing = np.clip((np.cos(xx/TILE*2*np.pi)-.1)*1.4,0,1)*along
            pigment += bearing[:,:,None]*np.array([57,49,39])
        tile = np.uint8(np.clip(pigment + grain[:,:,None]*2.0, 0, 255))
        data = np.zeros_like(tile)
        data[:,:,0] = 255
        data[:,:,1] = np.uint8(np.clip(roughness*255 + grain*4.3, 0, 255))
        data[:,:,2] = round(metallic*255)
        if name == "forged":
            data[:,:,1] = np.uint8(np.clip(data[:,:,1] - bearing*48,0,255))
        offset = (TILE*(i%4), TILE*(i//4))
        color.paste(Image.fromarray(tile), offset)
        orm.paste(Image.fromarray(data), offset)
    x,y,w,h = REGIONS["capacity"]
    panel = Image.new("RGB",(w,h),(205,181,116))
    draw = ImageDraw.Draw(panel)
    font = ImageFont.truetype(str(LETTERING),38)
    draw.text((w/2,h/2), "SWL  2 t", font=font, anchor="mm", fill=(39,49,47))
    color.paste(panel,(x,y))
    orm.paste((255,150,60),(x,y,x+w,y+h))
    return PBRMaterial(name="CraneEnamelAndMetal", baseColorTexture=color, metallicRoughnessTexture=orm,
                       metallicFactor=1.0, roughnessFactor=1.0)


def runways():
    m = CraneMesh()
    for side in (-1, 1):
        x = side*RUNWAY_X
        # Each runway bears on four wall corbels between the rolling shutter apertures.
        for z in (-21,-7,7,21):
            column = side*34.48
            m.block((column,4.02,z), (.14,1.78,.38), "graphite", .014)
            m.block(((column+x)/2,4.79,z), (abs(column-x)+.36,.19,.30), "steel", .014)
            m.beam_between((column,3.28,z),(x,4.72,z), .18,.23,"steel")
            m.block((x,4.90,z), (.54,.10,.48), "graphite")
        m.block((x,4.988,0), (.37,.076,46.40), "steel")
        m.block((x,5.165,0), (.13,.28,46.35), "graphite")
        m.block((x,5.335,0), (.37,.068,46.40), "steel")
        m.block((x,RUNWAY_TREAD_Y-.026,0), (.12,.052,46.30), "track", .007)
        for end in (-1,1):
            # The full rubber buffer face bears on the stop. Its two feet land
            # on the girder cap, astride the rail head, with rear kick braces.
            m.block((x,5.625,end*22.89), (.34,.44,.18), "edge")
            for dx in (-.119,.119):
                m.block((x+dx,5.387,end*22.98),(.096,.036,.40),"steel",.005)
                m.beam_between((x+dx,5.407,end*23.14),(x+dx,5.735,end*22.968),.053,.055,"steel")
    return m


def bridge():
    m = CraneMesh()
    for side in (-1, 1):
        z = side*.84
        m.block((0,5.33,z), (60.29,.80,.185), "beam", .021)
        m.block((0,5.785,z), (60.35,.11,.43), "edge", .012)
        m.block((0,4.885,z), (60.35,.095,.47), "edge", .010)
        # Narrow running strip for the four wheels of the underhung trolley.
        m.block((0,TROLLEY_TREAD_Y-.0165,z-side*.161), (59.70,.033,.098), "track", .004)
        for x in np.linspace(-27.5,27.5,12):
            m.block((x,5.33,z+side*.133), (.065,.81,.093), "edge", .008)
        for x in (-20,0,20):
            # Bolted splice cover with its bolt heads facing the inspection aisle.
            m.block((x,5.33,z+side*.104), (.56,.65,.025), "edge")
            for dx in (-.19,.19):
                for y in (5.10,5.56):
                    m.rod((x+dx,y,z+side*.116),(x+dx,y,z+side*.140),.032,"steel",6)
        # Capacity is marked on both aisle-facing webs. Define the UVs in the
        # viewer's coordinates so the reverse face also reads from left to right.
        normal, up = vec(0,0,side), vec(0,1,0)
        center = vec(-5,5.33,z+side*.0925)
        if side > 0:
            # Stand the rating off the festoon and cant it down toward the
            # narrow gable aisle. Each stay ends square against the plate back.
            tilt = np.deg2rad(32)
            normal, up = vec(0,-np.sin(tilt),np.cos(tilt)), vec(0,np.cos(tilt),np.sin(tilt))
            center = vec(-5,5.40,1.42)
            web_z = z+.0925
            web_y = center[1] + (center[2]-web_z)*np.tan(tilt)
            for x in (-5.78,-4.22):
                m.beam_between((x,web_y,web_z),(x,center[1],center[2]),.075,.056,"steel")
        uv = [(0,0),(1,0),(1,1),(0,1)]
        orientation = np.column_stack((vec(side,0,0),up,normal))
        m.oriented_block(center+normal*.007,orientation,(2.18,.52,.014),"edge",.004)
        face = center + normal*.0144
        points = [face+vec(side*(u-.5)*2.15,0,0)+up*(.5-v)*.491 for u,v in uv]
        m.poly(points,normal,"capacity",uv)
    for x in (-28,-17,-6,6,17,28):
        m.block((x,5.58,0), (.16,.21,1.55), "edge", .011)
    for side in (-1,1):
        x = side*RUNWAY_X
        m.block((x,5.736,0), (.75,.198,3.13), "beam", .035)
        m.block((x-side*.34,5.50,0), (.20,.44,2.32), "edge", .020)
        for offset in (-.19,.19):
            m.block((x+offset,5.615,0), (.045,.248,2.92), "graphite")
        for z in (-1.10,1.10):
            # Double flanges straddle the polished runway head.
            axle_y = RUNWAY_TREAD_Y + .166
            m.turned((x-.14,axle_y,z),(1,0,0),
                     [(0,0),(0,.179),(.016,.189),(.038,.189),(.048,.166),
                      (.232,.166),(.242,.189),(.266,.189),(.28,.179),(.28,0)],"track",24)
            m.rod((x-.25,axle_y,z),(x+.25,axle_y,z),.087,"steel",16)
        for end in (-1,1):
            m.rod((x,5.75,end*1.53),(x,5.75,end*1.69),.095,"rubber",14)
    # A ribbon of festoon cable pays out between rolling carriers. Gentle curves
    # hold their silhouette overhead and avoid a long run of loose ring meshes.
    m.block((-1.95,5.12,1.22), (55.90,.080,.077), "steel", .006)
    for x in np.linspace(-29.55,25.65,8):
        m.block((x,5.15,1.06), (.084,.064,.30),"graphite")
    stops = np.linspace(-29.45,PARKED_TROLLEY_X,8)
    for x in stops:
        m.block((x,5.07,1.22),(.131,.105,.102),"graphite")
    for x0,x1 in zip(stops, stops[1:]):
        points = [(x0+(x1-x0)*t, 5.04-.48*(4*t*(1-t)), 1.22) for t in np.linspace(0,1,9)]
        m.sweep(points,.023,"rubber",8,ends=False)
    return m


def forged_hook(m, z):
    # Cross-sections follow the forge from the swivel shank into the thick bowl,
    # then slim to a beak at the latch. Catmull-Rom blends both shape and section.
    guides = np.array([(0,3.58,.049,.048),(0,3.49,.050,.052),(-.05,3.40,.060,.060),
                       (-.105,3.30,.071,.073),(-.102,3.21,.080,.076),(-.055,3.125,.077,.070),
                       (.039,3.087,.064,.060),(.130,3.126,.052,.051),(.177,3.207,.036,.036),
                       (.193,3.279,.018,.024),(.189,3.315,.006,.009)])
    sections = []
    for i in range(len(guides)-1):
        p0,p1,p2,p3 = guides[max(0,i-1)], guides[i], guides[i+1], guides[min(i+2,len(guides)-1)]
        for t in (0,.25,.50,.75):
            sections.append(.5*(2*p1+(-p0+p2)*t+(2*p0-5*p1+4*p2-p3)*t*t+(-p0+3*p1-3*p2+p3)*t**3))
    sections.append(guides[-1])
    rings = []
    count = 16
    for i,(x,y,rad,thickness) in enumerate(sections):
        ta = unit(sections[min(i+1,len(sections)-1)][:2] - sections[max(i-1,0)][:2])
        normal = vec(-ta[1],ta[0],0)
        rings.append([vec(x,y,z) + normal*rad*np.cos(a) + vec(0,0,thickness*np.sin(a))
                      for a in np.linspace(0,2*np.pi,count,endpoint=False)])
    base = len(m.pos)
    vertices = np.array(rings)
    for i,ring in enumerate(vertices):
        between = vertices[min(i+1,len(vertices)-1)]-vertices[max(i-1,0)]
        along = np.roll(ring,-1,axis=0)-np.roll(ring,1,axis=0)
        for j in range(count+1):
            k = j % count
            n = unit(np.cross(along[k],between[k]))
            m.vertex(ring[k],n,(j/count,i/(len(rings)-1)),"forged")
    for i in range(len(rings)-1):
        for j in range(count):
            a = base+i*(count+1)+j
            b = a+1
            m.indices.extend((a,b,b+count+1,a,b+count+1,a+count+1))
    for ring,direction in ((vertices[0],vertices[0].mean(0)-vertices[1].mean(0)),
                           (vertices[-1],vertices[-1].mean(0)-vertices[-2].mean(0))):
        m.poly(ring,direction,"forged")
    # Spring latch spanning the throat, doubled around the shank pin.
    m.beam_between((-.018,3.442,z+.026),(.181,3.287,z+.026),.023,.030,"wire")
    m.rod((-.021,3.436,z-.069),(-.021,3.436,z+.069),.031,"graphite",16)


def hoist():
    m = CraneMesh()
    axle_y = TROLLEY_TREAD_Y + .128
    for side in (-1,1):
        # Flanged wheels on the inner faces of the two bridge girders.
        for x in (-.67,.67):
            z = side*.678
            m.turned((x,axle_y,z-side*.070),(0,0,side),
                     [(0,0),(0,.139),(.019,.144),(.03,.128),(.134,.128),(.14,.122),(.14,0)],"track",22)
            m.rod((x,axle_y,side*.447),(x,axle_y,side*.632),.061,"steel",14)
        m.block((0,4.83,side*.489),(1.66,.65,.08),"graphite",.035)
        for x in (-.67,.67):
            m.rod((x,axle_y,side*.439),(x,axle_y,side*.450),.086,"steel",12)
    for x in (-.728,.728):
        m.block((x,4.551,0),(.15,.11,1.07),"graphite")
    # Axles in the side plates support the grooved drum. Its motor and gearbox
    # are on the right; the service enclosure sits behind the drum.
    drum_y = 4.555
    m.rod((-.76,drum_y,0),(.66,drum_y,0),.069,"track",18)
    m.turned((-.62,drum_y,0),(1,0,0),
             [(0,0),(0,.252),(.022,.272),(.052,.272),(.060,.210),
              (.788,.210),(.796,.272),(.830,.272),(.85,.252),(.85,0)],"wire",32)
    windings = [(0,.208)]
    for j in range(15):
        start = j*.046
        windings.extend([(start+.008,.221),(start+.029,.223),(start+.042,.210)])
    m.turned((-.548,drum_y,0),(1,0,0),windings,"steel",26)
    m.block((.39,drum_y+.055,0),(.33,.48,.47),"green",.055)
    motor = [(0,0),(0,.145),(.035,.164),(.056,.141)]
    for j in range(5):
        start = .065 + j*.05
        motor.extend([(start,.141),(start+.003,.166),(start+.018,.166),(start+.022,.141)])
    motor.extend([(.329,.138),(.350,.117),(.350,0)])
    m.turned((.552,drum_y+.053,0),(1,0,0),motor,"green",24)
    m.block((-.18,4.82,-.43),(.74,.32,.30),"green",.019)
    m.block((-.18,4.82,-.598),(.69,.277,.040),"steel",.012)
    m.sweep([(0,5.06,1.22),(0,4.99,1.15),(.18,4.85,.98),(.25,4.74,.53),(.35,4.67,.27)],
            .029,"rubber",10)
    # Rope leaves the drum tangent, returns around the travelling sheave, and
    # terminates in the trolley's dead-end socket. The groove remains visible.
    sheave_y, r, z = 3.84, .159, .220
    m.turned((0,sheave_y,z-.067),(0,0,1),
             [(0,0),(0,.161),(.008,.174),(.027,.174),(.044,.144),
              (.091,.144),(.107,.174),(.126,.174),(.134,.161),(.134,0)],"track",32)
    arc = [(r*np.cos(t),sheave_y+r*np.sin(t),z) for t in np.linspace(np.pi,2*np.pi,17)]
    m.sweep([(-r,drum_y,z),*arc,(r,4.356,z)],.0165,"wire",10,ends=False)
    # Hang the wedge socket off a return on the trolley frame, clear of the drum.
    m.block((r,4.485,.483),(.115,.25,.084),"graphite")
    m.block((r,4.393,.346),(.115,.058,.335),"graphite")
    m.turned((r,4.334,z),(0,1,0),[(0,0),(0,.026),(.016,.033),(.045,.045),
             (.061,.045),(.061,0)],"steel",16)
    for side in (-1,1):
        face = z+side*.103
        span = [(-.14,3.93),(-.16,3.84),(-.09,3.64),(-.05,3.60),(.05,3.60),
                (.09,3.64),(.16,3.84),(.14,3.93)]
        # Rolled bevel on the two lower-block cheeks.
        points = [vec(x,y,face) for x,y in span]
        m.panel(points,vec(0,0,side),"warning",.022,"edge")
        m.rod((0,sheave_y,face+side*.022),(0,sheave_y,face+side*.048),.067,"graphite",12)
    m.rod((0,3.664,z-.134),(0,3.664,z+.134),.052,"steel",18)
    m.rod((0,3.615,z),(0,3.685,z),.08,"graphite",18)
    m.turned((0,3.53,z),(0,1,0),[(0,0),(0,.065),(.015,.074),(.070,.074),(.092,.051),(.092,0)],
             "track",20)
    forged_hook(m,z)
    return m


def build():
    material = finish_atlas()
    scene = trimesh.Scene()
    for name, part, offset in [("Runways",runways(),(0,0,0)),
                               ("TravellingBridge",bridge(),(0,0,PARKED_BRIDGE_Z)),
                               ("WireRopeHoist",hoist(),(PARKED_TROLLEY_X,0,PARKED_BRIDGE_Z))]:
        indices = np.asarray(part.indices).reshape(-1,3)
        mesh = trimesh.Trimesh(part.pos,indices,vertex_normals=part.norm,process=False)
        assert np.all(np.isfinite(mesh.vertices)) and mesh.area_faces.min() > 1e-12, name
        assert np.all((mesh.face_normals*np.asarray(part.norm)[indices].mean(axis=1)).sum(axis=1)>0), name
        mesh.visual = trimesh.visual.TextureVisuals(uv=part.uv,material=material)
        mesh.merge_vertices(merge_norm=False,merge_tex=False)
        transform = np.eye(4)
        transform[:3,3] = offset
        scene.add_geometry(mesh,node_name=name,geom_name=name,transform=transform)
        print(name,len(indices),"triangles; local bounds",mesh.bounds.round(3).tolist())
    DEST.write_bytes(scene.export(file_type="glb"))


if __name__ == "__main__":
    build()
