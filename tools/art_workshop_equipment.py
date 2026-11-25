"""Build the garage's reusable service fixtures in metres (+Y up, +Z drawer side).

Run with Python, NumPy, Pillow and trimesh. Each fixture is a single indexed PBR
surface. UVs select swatches of painted metal, steel and rubber in shared atlases.
"""

from itertools import product
from pathlib import Path

import numpy as np
import trimesh
from PIL import Image, ImageDraw, ImageFont
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


def sign_tray(m, width, height, radius, back, front, face, edge):
    """Roll the perimeter of a sheet-metal tray, including its plan-view corners."""
    rings = []
    for inset, z in ((.005, back), (.0015, back+.002), (0, back+.005),
                     (0, front-.005), (.0015, front-.002), (.005, front)):
        points = []
        for corner, (sx, sy) in enumerate(((1,1),(-1,1),(-1,-1),(1,-1))):
            for angle in np.linspace(corner*np.pi/2, (corner+1)*np.pi/2, 5):
                x = sx*(width/2-radius) + (radius-inset)*np.cos(angle)
                y = sy*(height/2-radius) + (radius-inset)*np.sin(angle)
                points.append(vec(x,y,z))
        rings.append(np.asarray(points))
    m.poly(rings[0],vec(0,0,-1),edge)
    m.poly(rings[-1],vec(0,0,1),face)
    for lower, upper in zip(rings,rings[1:]):
        for i in range(len(lower)):
            j = (i+1) % len(lower)
            side = np.cross(lower[j]-lower[i],upper[i]-lower[i])
            m.poly([lower[i],lower[j],upper[j],upper[i]],side,edge)


def marker_wing():
    m = Fixture()
    # Formed body with a replaceable enamel face, seated on its dark return.
    sign_tray(m, 1.65,.333,.043, -.032,.011, "steel","dark")
    sign_tray(m, 1.628,.313,.033, .011,.025, "case","case")
    m.block((-.713,0,.0265),(.016,.199,.003),"ochre",.001)
    for x, y in product((-.774,.774),(-.110,.110)):
        m.turned((x,y,.0248),(0,0,1),[(0,0),(0,.009),(.002,.010),(.005,.008),
                  (.005,.0035),(.003,.0035),(.003,0)],"steel",8)
    # The continuous return meets the cross-rail at either mounting angle.
    m.block((0,-.107,-.045),(1.42,.069,.028),"steel",.004)
    m.block((0,-.133,-.064),(1.44,.017,.017),"dark",.004)
    return m


def marker_post():
    m = Fixture()
    m.block((0,.017,0),(.345,.034,.267),"dark",.013)
    m.block((0,.042,0),(.305,.018,.228),"steel",.006)
    m.block((0,.552,0),(.103,1.010,.089),"dark",.009)
    m.block((0,.112,0),(.143,.121,.127),"steel",.011)
    for x,z in product((-.119,.119),(-.081,.081)):
        m.turned((x,.0505,z),(0,1,0),[(0,0),(0,.016),(.003,.016),(.004,.013),
                 (.004,0)],"dark",12)
        m.turned((x,.054,z),(0,1,0),[(0,0),(0,.012),(.008,.012),(.010,.010),
                 (.010,0)],"bright",6)
    m.block((0,.932,0),(.134,.105,.132),"steel",.009)
    return m


def shutter_curtain():
    """Continuous interlocking roll-formed slats, with the front towards +Z."""
    m = Fixture()
    pitch = .165
    profile = [(0, .075), (.014, .073), (.028, .084), (.039, .103),
               (.052, .108), (.132, .108), (.146, .100), (pitch, .075)]
    for slat in range(29):
        for (ay,az),(by,bz) in zip(profile, profile[1:]):
            y = .102 + pitch * slat
            points = [(-5.515,y+ay,az),(5.515,y+ay,az),
                      (5.515,y+by,bz),(-5.515,y+by,bz)]
            m.poly(points,(0,az-bz,by-ay),"steel")
    return m


def shutter_frame():
    m = Fixture()
    # The bottom rail and its compressible seal meet the slab beneath the curtain.
    m.block((0,.030,.096),(11.035,.060,.102),"rubber",.022)
    m.block((0,.080,.097),(11.06,.059,.115),"steel",.010)
    for side in (-1,1):
        x = side * 5.545
        m.block((x,2.495,.045),(.20,4.99,.18),"dark",.018)
        m.block((x+side*.066,2.454,.158),(.060,4.89,.136),"steel",.012)
        m.block((x-side*.032,2.454,.142),(.125,4.89,.065),"insert",.007)
        # Replaceable ochre guide guards end below the headbox. Their bolts
        # sit on the guard face, with a separate folded, scuff-prone toe.
        m.block((x+side*.02,1.015,.191),(.148,2.03,.080),"ochre",.016)
        m.block((x+side*.02,.078,.230),(.193,.15,.087),"dark",.013)
        for y in (.29, .97, 1.86, 2.73, 4.16):
            z = .231 if y < 2.03 else .175
            dx = .02 if y < 2.03 else -.032
            m.turned((x+side*dx,y,z),(0,0,1),[(0,0),(0,.021),(.004,.021),
                     (.004,.015),(.013,.015),(.014,.012),(.014,0)],"bright",6)
    # The rolled front of the barrel hood shares tangent strips across the span.
    section = [(4.81,-.02),(4.81,.235),(4.824,.280),(4.859,.308),
               (5.083,.308),(5.128,.297),(5.193,.230),(5.213,.193),(5.213,-.02)]
    for (ay,az),(by,bz) in zip(section,section[1:]):
        m.poly([(-5.72,ay,az),(5.72,ay,az),(5.72,by,bz),(-5.72,by,bz)],
               (0,az-bz,by-ay),"steel")
    for x in (-5.72, 5.72):
        cap = [(x,y,z) for y,z in section]
        m.poly(cap,(np.sign(x),0,0),"dark")
    for x in (-3.77,0,3.77):
        m.block((x,4.975,.31),(.030,.222,.014),"insert",.005)
    return m


def saddle_base():
    """Anchor plate below either leg of an airframe support trestle."""
    m = Fixture()
    m.block((0,.0275,0),(.54,.055,.20),"dark",.009)
    # Each anchor clamps the plate with a broad washer beneath the hex head.
    for x in (-.214,.214):
        m.turned((x,.055,0),(0,1,0),[(0,.026),(.006,.026),(.006,.016)],"steel",10)
        m.turned((x,.061,0),(0,1,0),[(0,.019),(.014,.019),
                 (.017,.015),(.017,0)],"bright",6)
    return m


def saddle_screw():
    """The permanent spindle, hexagonal locknut and swivel bearing."""
    m = Fixture()
    m.turned((0,-.231,0),(0,1,0),[(0,.053),(.080,.053),(.085,.047),(.085,.030)],"dark",12)
    m.turned((0,-.147,0),(0,1,0),[(0,.054),(.021,.054),(.026,.049),(.026,.030)],"steel",6)
    m.turned((0,-.122,0),(0,1,0),[(0,.030),(.064,.030)],"insert",12)
    m.turned((0,-.062,0),(0,1,0),[(0,.027),(.010,.035),(.021,.035),
             (.035,.024)],"steel",12)
    return m


def saddle_thread():
    """Physical Acme flanks for inspection at arm's length; the shaft bears the silhouette."""
    m = Fixture()
    # Each flank shares an edge with its neighbor around the machined spindle.
    pitch, revolutions, per_turn = .016, 4, 12
    profile = [(.030,-.0048),(.036,-.0014),(.036,.0014),(.030,.0048)]
    for i in range(revolutions * per_turn):
        a,b = 2*np.pi*i/per_turn, 2*np.pi*(i+1)/per_turn
        for (r0,h0),(r1,h1) in zip(profile,profile[1:]):
            points = np.array([(r*np.cos(t),-.122 + pitch*t/(2*np.pi) + h,r*np.sin(t))
                               for t,r,h in ((a,r0,h0),(b,r0,h0),(b,r1,h1),(a,r1,h1))])
            normal = np.cross(points[1]-points[0],points[2]-points[0])
            if normal.dot(vec(np.cos((a+b)/2),0,np.sin((a+b)/2))) < 0:
                normal = -normal
            m.poly(points,normal,"bright")
    return m


def saddle_shoe():
    """Swivelling steel shoe below three molded load pads. Local Y=0 is the skin."""
    m = Fixture()
    m.block((0,-.039,0),(.118,.019,.158),"steel",.006)
    for z in (-.053,0,.053):
        m.block((0,-.015,z),(.120,.030,.053 if z == 0 else .051),"rubber",.0045)
    return m


def shutter_stencils():
    """Whole identifiers in padded cells so minified digits never sample a neighbor."""
    image = Image.new("L",(768,512))
    pen = ImageDraw.Draw(image)
    font = ImageFont.truetype(str(DEST.parents[1] / "art/signs/RG2014D.ttf"),207)
    for i in range(6):
        number = f"{i+1:02d}"
        x,y = (i % 3)*256+128, (i // 3)*256+128
        pen.text((x,y),number,font=font,anchor="mm",fill=255)
    image.save(DEST.with_name("workshop_shutter_numbers.png"),optimize=True)


def trench_grate():
    """Flush removable cast grates and their recessed channel, along local X."""
    m = Fixture()
    half, width = 5.40, .202
    # Redundant back faces are omitted on surfaces embedded in the slab.
    def strip(x0, x1, ya, za, yb, zb, normal, finish):
        m.poly([(x0,ya,za),(x1,ya,za),(x1,yb,zb),(x0,yb,zb)],normal,finish)

    strip(-half,half,-.069,-width/2,-.069,width/2,(0,1,0),"dark")
    for side in (-1,1):
        edge = side * width / 2
        strip(-half,half,-.069,edge,0,edge,(0,0,-side),"dark")
        strip(-half,half,0,edge,0,side*.085,(0,1,0),"insert")
        strip(-half,half,0,side*.085,-.021,side*.085,(0,0,-side),"steel")
    for idx in range(10):
        start = -half + idx*1.08
        for i in range(12):
            # Cast faces are crowned by 1.5 mm and taper into the channel.
            # A sightline through the 22 mm slot reaches the actual trough.
            x = start + .045 + i*.09
            section = [(x-.028,-.026),(x-.034,-.003),(x-.032,-.0008),
                       (x+.032,-.0008),(x+.034,-.003),(x+.028,-.026)]
            for (xa,ya),(xb,yb) in zip(section,section[1:]):
                m.poly([(xa,ya,-.085),(xb,yb,-.085),(xb,yb,.085),(xa,ya,.085)],
                       (ya-yb,xb-xa,0),"insert")
        # Captive hex fixings secure the leading bar of each removable panel.
        x = start+.045
        for side in (-1,1):
            m.turned((x,-.0008,side*.061),(0,1,0),
                     [(0,.010),(.0012,.010),(.0012,.004),(-.0012,.004)],
                     "dark",6)
    for end in (-half,half):
        m.poly([(end,0,-width/2),(end,-.069,-width/2),(end,-.069,width/2),
                (end,0,width/2)],(-np.sign(end),0,0),"dark")
    return m


def high_bay_lamp():
    """Pressed-aluminium luminaire and bridge clips, relative to the lens face."""
    m = Fixture()
    # A folded extrusion creates a splayed reflector below the dark upper case.
    cross = [(-.205,.189),(-.243,.154),(-.243,.043),(-.227,.017),(-.194,.009),
             (-.166,.047),(.166,.047),(.194,.009),(.227,.017),(.243,.043),
             (.243,.154),(.205,.189)]
    for i,((za,ya),(zb,yb)) in enumerate(zip(cross,cross[1:])):
        m.poly([(-1.756,ya,za),(1.756,ya,za),(1.756,yb,zb),(-1.756,yb,zb)],
               (0,za-zb,yb-ya),"bright" if 4 <= i <= 6 else "dark")
    m.poly([(-1.756,.189,-.205),(1.756,.189,-.205),(1.756,.189,.205),
            (-1.756,.189,.205)],(0,1,0),"steel")
    for x in (-1.753,1.753):
        m.block((x,.102,0),(.040,.184,.475),"insert",.016)
    for x in (-.572,.572):
        m.poly([(x-.005,.009,-.186),(x+.005,.009,-.186),(x+.005,.009,.186),
                (x-.005,.009,.186)],(0,-1,0),"insert")
    for x in (-1.14,1.14):
        # The ceilings' lower chord has its underside at y=6.32. A dark
        # bracket with folded feet joins it directly to the luminaire.
        m.block((x,.256,0),(.055,.134,.055),"steel",.004)
        m.block((x,.317,0),(.132,.013,.125),"dark",.004)
    return m


def aisle_stencil():
    """A single painted direction for the pedestrian aisle, facing the entrance."""
    image = Image.new("L",(1024,256))
    pen = ImageDraw.Draw(image)
    font = ImageFont.truetype(str(DEST.parents[1] / "art/signs/RG2014D.ttf"),176)
    words = "WORKSHOP"
    left,top,right,bottom = pen.textbbox((0,0),words,font=font)
    word = Image.new("L",(right-left,bottom-top))
    ImageDraw.Draw(word).text((-left,-top),words,font=font,fill=255)
    # Stretch along the direction of travel, as on an actual floor stencil.
    image.paste(word.resize((692,176),Image.Resampling.LANCZOS),(58,40))
    pen.polygon([(792,115),(868,38),(944,115),(920,139),(886,104),
                 (886,216),(850,216),(850,104),(815,139)],fill=255)
    image.save(DEST.with_name("workshop_direction.png"),optimize=True)


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
    for name,fixture in (("MachineBench",bench()),("RollCabinet",cart()),
                         ("MarkerWing",marker_wing()),("MarkerPost",marker_post()),
                         ("ShutterCurtain",shutter_curtain()),("ShutterFrame",shutter_frame()),
                         ("SaddleBase",saddle_base()),("SaddleScrew",saddle_screw()),("SaddleThread",saddle_thread()),
                         ("SaddleShoe",saddle_shoe()),("TrenchGrate",trench_grate()),
                         ("HighBayLamp",high_bay_lamp())):
        faces = np.asarray(fixture.indices).reshape(-1,3)
        geometry = trimesh.Trimesh(fixture.pos,faces,vertex_normals=fixture.norm,process=False)
        assert np.all(geometry.area_faces > 1e-12), f"{name}: degenerate faces"
        assert np.all((geometry.face_normals * np.asarray(fixture.norm)[faces].mean(axis=1)).sum(axis=1) > 0)
        geometry.visual = trimesh.visual.TextureVisuals(uv=fixture.uv,material=material)
        scene.add_geometry(geometry,node_name=name,geom_name=name)
        print(name,len(faces),"triangles",geometry.bounds.tolist())
    DEST.write_bytes(scene.export(file_type="glb"))
    aisle_stencil()
    shutter_stencils()


if __name__ == "__main__":
    build()
