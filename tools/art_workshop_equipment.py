"""Build the garage's reusable service fixtures in metres (+Y up, +Z drawer side).

Run with Python, NumPy, Pillow and trimesh. Each fixture is a single indexed PBR
surface. UVs select swatches of painted metal, steel and rubber in shared atlases.
"""

from itertools import product
from pathlib import Path

import numpy as np
import trimesh
from PIL import Image, ImageDraw
from trimesh.visual.material import PBRMaterial

from art_shrike_airframe import Mesh, panel_faces, unit, vec

DEST = Path(__file__).resolve().parents[1] / "godot/garage/workshop_equipment.glb"
# sRGB albedo, perceptual roughness, metallic.
FINISH = {
    "case": ("386762", .38, .48), "drawer": ("477b72", .34, .45),
    "dark": ("303f46", .51, .48), "steel": ("849398", .37, .78),
    "bright": ("b5beba", .28, .86), "rubber": ("293134", .84, .02),
    "ochre": ("bb803e", .38, .45), "insert": ("677981", .48, .65),
    "worktop": ("8c999a", .36, .78),
}
ATLAS_SIZE = (1024,512)
BORDER = 5
REGIONS = {key: (256*(i%4),256+128*(i//4),256,128) for i,key in enumerate(list(FINISH)[:-1])}
REGIONS["worktop"] = (0,0,1024,256)


class Fixture(Mesh):
    def vertex(self, p, n, uv, region):
        self.pos.append(p)
        self.norm.append(n)
        x,y,w,h = REGIONS[region]
        u,v = uv
        self.uv.append(((x+BORDER+.5+u*(w-2*BORDER-1)) / ATLAS_SIZE[0],
                        1-(y+BORDER+.5+v*(h-2*BORDER-1)) / ATLAS_SIZE[1]))

    def block(self, center, size, finish, radius=.008):
        """A clipped box with six faces, twelve highlight edges and eight corners."""
        center, half = np.asarray(center), np.asarray(size) / 2
        radius = min(radius, .44 * min(size))
        for axis in range(3):
            a, b = (axis+1) % 3, (axis+2) % 3
            for sign in (-1, 1):
                n = np.eye(3)[axis] * sign
                face = []
                for u, v in ((-1,-1), (1,-1), (1,1), (-1,1)):
                    p = n * half
                    p[a], p[b] = u*(half[a]-radius), v*(half[b]-radius)
                    face.append(center + p)
                self.poly(face, n, finish)
            for u, v in product((-1,1), repeat=2):
                n = u*np.eye(3)[a] + v*np.eye(3)[b]
                line = n * half
                ends = np.eye(3)[axis] * (half[axis]-radius)
                first = center + line - u*np.eye(3)[a]*radius
                second = center + line - v*np.eye(3)[b]*radius
                self.poly([first-ends, first+ends, second+ends, second-ends], n, finish)
        for signs in product((-1,1), repeat=3):
            inner = center + (half-radius)*np.array(signs)
            self.poly([inner+n*sign*radius for n, sign in zip(np.eye(3), signs)], signs, finish)

    def turned(self, origin, axis, profile, finish, sides=16):
        """Revolve an axial profile, including annular faces and open sockets."""
        axis = unit(np.asarray(axis))
        right = unit(np.cross(np.eye(3)[np.argmin(abs(axis))], axis))
        up = np.cross(axis, right)
        angles = np.linspace(0,2*np.pi,sides+1)
        rays = np.outer(np.cos(angles), right) + np.outer(np.sin(angles), up)
        length = max(s for s,r in profile)
        radius = max(r for s,r in profile)
        for (s0, r0), (s1, r1) in zip(profile, profile[1:]):
            base = len(self.pos)
            n = np.asarray([unit((s1-s0)*ray - (r1-r0)*axis) for ray in rays])
            for s, r in ((s0,r0), (s1,r1)):
                for j,(ray,normal) in enumerate(zip(rays, n)):
                    uv = (j/sides,s/length)
                    if s0 == s1:
                        uv = (.5+.5*r/radius*np.cos(angles[j]),.5+.5*r/radius*np.sin(angles[j]))
                    self.vertex(origin + s*axis + r*ray, normal, uv, finish)
            for j in range(sides):
                k = j+1
                if r0:
                    self.indices.extend((base+j, base+k, base+j+sides+1))
                if r1:
                    self.indices.extend((base+k, base+k+sides+1, base+j+sides+1))

    def rod(self, a, b, radius, finish, sides=14):
        delta = np.asarray(b) - np.asarray(a)
        length = np.linalg.norm(delta)
        edge = min(.004, radius*.24, length*.15)
        self.turned(a, delta, [(0,0), (0,radius-edge), (edge,radius),
                               (length-edge,radius), (length,radius-edge), (length,0)], finish, sides)

    def cutout(self, outline, z, gauge, finish):
        """Extrude a punched tool silhouette in the plane of the shadowboard."""
        front = np.array([(x,y,z) for x,y in outline])
        forward = vec(0,0,1)
        if np.sum(np.cross(front, np.roll(front,-1,axis=0)), axis=0)[2] < 0:
            front = front[::-1]
        back = front-forward*gauge
        for face in panel_faces(front, forward):
            self.poly(front[list(face)], forward, finish)
            self.poly(back[list(face)], -forward, finish)
        for i, pt in enumerate(front):
            j = (i+1) % len(front)
            self.poly([pt,back[i],back[j],front[j]], np.cross(front[j]-pt,forward), finish)


def drawers(m, x, width, low, heights, z):
    for height in heights:
        m.block((x, low+height/2, z), (width,height-.012,.030), "drawer", .007)
        # A folded full-width return and its undercut finger space.
        m.block((x, low+height-.030, z+.024), (width-.054,.034,.035), "dark", .004)
        m.block((x, low+height-.020, z+.044), (width-.064,.016,.030), "bright", .005)
        low += height


def vise(m):
    x, top = -.96, .988
    m.turned((x,top,-.012), (0,1,0), [(0,0),(0,.158),(.012,.17),(.040,.17),
             (.052,.156),(.052,0)], "dark", 24)
    for dx,dz in ((-.138,.068),(.138,.068),(0,-.139)):
        m.rod((x+dx,top+.044,dz-.012),(x+dx,top+.062,dz-.012),.014,"bright",6)
    m.block((x,top+.106,.008), (.20,.14,.27), "case", .026)
    m.block((x,top+.173,.109), (.129,.076,.264), "bright", .010)
    for z in (.009,.165):
        m.block((x,top+.205,z), (.18,.130,.099), "case", .020)
        m.block((x,top+.257,z), (.242,.055,.103), "case", .011)
        jaw = z + (.05 if z < .1 else -.05)
        m.block((x,top+.263,jaw), (.245,.043,.017), "steel", .004)
    m.block((x+.048,top+.281,.087), (.075,.121,.040), "insert", .002)
    m.rod((x,top+.161,.211),(x,top+.161,.265),.043,"dark")
    m.rod((x-.085,top+.082,.252),(x+.125,top+.278,.252),.010,"bright")
    for dx,dy in ((-.085,.082),(.125,.278)):
        m.rod((x+dx-.008,top+dy-.008,.252),(x+dx+.008,top+dy+.008,.252),.016,"steel")


def bench():
    m = Fixture()
    m.block((0,.064,0), (2.91,.128,.72), "dark", .014)
    m.block((0,.527,-.016), (3.03,.806,.748), "case", .018)
    m.block((0,.957,0), (3.18,.062,.89), "worktop", .012)
    m.block((0,1.048,-.416), (3.14,.119,.056), "steel", .008)
    for x in (-.98,0):
        drawers(m,x,.938,.164,[.237,.18,.145,.139],.368)
    m.block((.982,.514,.370), (.930,.702,.035), "drawer", .012)
    m.block((.644,.696,.405), (.041,.200,.051), "dark", .009)
    m.block((.644,.696,.433), (.026,.154,.024), "bright", .007)
    vise(m)

    # A steel slat board rises from the back lip on two angle uprights.
    for x in (-.36,1.35):
        m.block((x,1.365,-.386), (.045,.758,.050), "dark", .006)
    m.block((.492,1.470,-.357), (1.82,.535,.039), "dark", .012)
    for y in (1.262,1.385,1.506,1.629):
        m.block((.492,y,-.331), (1.755,.026,.022), "insert", .003)
    for i in range(5):
        x, y, s = -.248+i*.121, 1.616, 1-i*.066
        m.rod((x,y-.018,-.319),(x,y-.018,-.290),.011,"ochre",10)
        # Open crescent and a waisted shaft with a rounded heel.
        outline = [(-.012,-.029),(-.014,-.242),(-.009,-.263),(.007,-.266),
                   (.016,-.250),(.011,-.031),(.032,-.018),(.040,.007),
                   (.034,.031),(.016,.011),(-.004,.006),(-.017,.019),
                   (-.020,.043),(-.038,.032),(-.044,.013),(-.037,-.011)]
        m.cutout([(x+a*s,y+b*s) for a,b in outline], -.284, .008, "bright")
    m.block((.832,1.446,-.270),(.716,.034,.15),"steel")
    for i in range(4):
        x = .595+i*.146
        m.rod((x,1.330,-.246),(x,1.610,-.246),.011,"bright",10)
        m.rod((x,1.491,-.246),(x,1.630,-.246),.026,"rubber",14)
        m.rod((x,1.514,-.246),(x,1.615,-.246),.028,("ochre","dark")[i%2],14)
    m.block((.86,1.002,-.082),(.74,.028,.294),"rubber")
    # A removed service cartridge rests on its end collars. The spare gasket
    # and exposed pleats give the pilot a sense of the scale of the engine parts.
    origin = vec(.628,1.083,-.082)
    m.turned(origin,(1,0,0),[(0,0),(0,.063),(.005,.067),(.024,.067),
             (.029,.053),(.232,.053),(.236,.067),(.252,.067),(.256,.063),
             (.256,.027),(.246,.025),(.246,0)],"steel",24)
    for a in np.linspace(0,2*np.pi,24,endpoint=False):
        radial = vec(0,np.sin(a),np.cos(a))
        outer = np.array([origin+vec(x,0,0)+radial*.061 for x in (.026,.234)])
        for direction in (-1,1):
            turn = a+direction*np.pi/24
            inner = [origin+vec(x,0,0)+vec(0,np.sin(turn),np.cos(turn))*.054 for x in (.026,.234)]
            normal = unit(np.cross(outer[1]-outer[0],inner[1]-outer[0]))
            m.poly([outer[0],outer[1],inner[1],inner[0]],normal*np.sign(normal@radial),"ochre")
    m.turned((1.011,1.016,-.078),(0,1,0),[(0,.044),(0,.055),(.003,.057),
             (.007,.057),(.010,.055),(.010,.044),(.007,.042),(.003,.042),(0,.044)],"rubber",24)
    return m


def socket_rail(m):
    m.block((-.119,.897,-.039),(.62,.032,.098),"dark",.009)
    for i in range(6):
        r = .023+i*.0022
        h = .050+i*.003
        m.turned((-.376+i*.099,.913,-.039),(0,1,0),[(0,r-.003),(.003,r),(h-.006,r),
                 (h,r-.003),(h,r*.56),(h-.020,r*.56),(h-.020,0)],"bright",12)


def cart():
    m = Fixture()
    for x,z in product((-.40,.40),(-.18,.18)):
        m.block((x,.207,z),(.109,.025,.125),"steel",.005)
        m.rod((x,.170,z),(x,.203,z),.038,"dark")
        for dx in (-.037,.037):
            m.block((x+dx,.127,z+.005),(.013,.099,.055),"steel",.006)
        m.turned((x-.031,.080,z+.020),(1,0,0),[(0,0),(0,.059),(.008,.075),(.016,.080),
                 (.046,.080),(.054,.075),(.062,.059),(.062,0)], "rubber",20)
        m.rod((x-.049,.080,z+.020),(x+.049,.080,z+.020),.023,"bright",12)
    m.block((0,.530,-.003),(1.08,.628,.55),"case",.020)
    drawers(m,0,.986,.251,[.190,.151,.128,.104],.277)
    m.block((0,.855,0),(1.14,.046,.602),"steel",.012)
    m.block((0,.879,0),(1.09,.006,.555),"rubber",.002)
    for z in (-.289,.289):
        m.block((0,.890,z),(1.14,.024,.026),"steel",.006)
    for x in (-.556,.556):
        m.block((x,.890,0),(.026,.024,.55),"steel",.005)
    # Push rail is supported by two returns, with a rubber centre grip.
    for z in (-.191,.191):
        m.rod((.510,.777,z),(.635,.777,z),.019,"steel")
    m.rod((.621,.777,-.203),(.621,.777,.203),.019,"steel")
    m.rod((.621,.777,-.150),(.621,.777,.150),.025,"rubber")
    socket_rail(m)
    return m


def finish_atlas():
    """Paint material-scale variation, with a full-width tile on the three-metre bench."""
    colors = Image.new("RGB", ATLAS_SIZE)
    orm = Image.new("RGB", ATLAS_SIZE)
    rng = np.random.default_rng(1327)
    for name,(rgb,rough,metal) in FINISH.items():
        x,y,sw,sh = REGIONS[name]
        w,h = sw-2*BORDER,sh-2*BORDER
        grain = rng.normal(0,1,(h,w))
        if name in ("worktop","steel","bright","insert"):
            # Fine abrasive lines follow the rolling direction. Most variation
            # belongs in roughness, so glancing light reveals it during movement.
            brush = rng.normal(0,1,(h,1))
            variation = grain*1.5+brush*2.4
            roughness = rough+grain*.017+brush*.043
            if name == "worktop":
                scuffs = Image.new("L",(w,h))
                pen = ImageDraw.Draw(scuffs)
                for _ in range(172):
                    start = (int(rng.uniform(0,w)),int(rng.uniform(0,h)))
                    end = (start[0]+int(rng.uniform(3,36)),start[1]+int(rng.uniform(-9,7)))
                    pen.line([start,end],fill=int(rng.uniform(35,170)))
                mark = np.asarray(scuffs)/255
                variation += mark*14
                roughness += mark*.11
        elif name == "rubber":
            variation = grain*2.2
            roughness = rough+grain*.032
        else:
            # Small enamel stipple, kept sparse enough for broad finish highlights.
            variation = grain*1.6
            roughness = rough+grain*.029
        base = np.frombuffer(bytes.fromhex(rgb),dtype=np.uint8)
        albedo = np.clip(np.rint(base+variation[:,:,None]),0,255).astype("uint8")
        surface = np.empty((h,w,3),dtype=np.uint8)
        surface[:,:,0],surface[:,:,1],surface[:,:,2] = 255,np.clip(roughness*255,0,255),round(metal*255)
        for atlas,tile in ((colors,albedo),(orm,surface)):
            padded = np.pad(tile,((BORDER,BORDER),(BORDER,BORDER),(0,0)),mode="edge")
            atlas.paste(Image.fromarray(padded),(x,y))
    return colors,orm


def build():
    colors,orm = finish_atlas()
    material = PBRMaterial(name="WorkshopFinishes", baseColorTexture=colors,
                           metallicRoughnessTexture=orm, metallicFactor=1., roughnessFactor=1.)
    scene = trimesh.Scene()
    for name,fixture in (("MachineBench",bench()),("RollCabinet",cart())):
        faces = np.asarray(fixture.indices).reshape(-1,3)
        geometry = trimesh.Trimesh(fixture.pos,faces,vertex_normals=fixture.norm,process=False)
        assert np.all(geometry.area_faces > 1e-12), f"{name}: degenerate faces"
        assert np.all((geometry.face_normals * np.asarray(fixture.norm)[faces].mean(axis=1)).sum(axis=1) > 0)
        geometry.visual = trimesh.visual.TextureVisuals(uv=fixture.uv,material=material)
        scene.add_geometry(geometry,node_name=name,geom_name=name)
        print(name,len(faces),"triangles",geometry.bounds.tolist())
    DEST.write_bytes(scene.export(file_type="glb"))


if __name__ == "__main__":
    build()
