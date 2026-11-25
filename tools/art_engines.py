"""Rebuild the Phaethon engine dress kit: blender -b -P tools/art_engines.py."""
import math
from pathlib import Path
import struct
import tempfile
import zlib

import bpy
import numpy as np
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[1]
ASSET = ROOT / "godot/art/engine/nacelle.glb"
TILE = 256
# Each finish occupies a padded patch in a single shared PBR atlas.
ORANGE, CERAMIC, GRAPHITE, STEEL, CAUTION, TITANIUM, IVORY, SERVICE = range(8)
FINISHES = [
    ((199, 80, 31), 0.42, 0.0), ((138, 128, 110), 0.66, 0.0),
    ((50, 55, 58), 0.62, 0.0), ((153, 159, 160), 0.33, 1.0),
    ((214, 168, 66), 0.52, 0.0), ((86, 91, 100), 0.44, 1.0),
    ((201, 196, 175), 0.47, 0.0), ((47, 67, 69), 0.58, 0.0),
]


def write_png(path, bitmap):
    def chunk(kind, data):
        return (struct.pack(">I", len(data)) + kind + data
                + struct.pack(">I", zlib.crc32(kind + data) & 0xffffffff))
    height, width, _ = bitmap.shape
    rows = b"".join(b"\x00" + row.tobytes() for row in bitmap)
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(
        ">IIBBBBB", width, height, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(rows, 9))
        + chunk(b"IEND", b""))


def surface_maps(directory):
    rng = np.random.default_rng(28)
    y, x = np.mgrid[0:TILE, 0:TILE] / (TILE - 1)
    maps = {key: np.zeros((TILE * 2, TILE * 4, 3), dtype=np.uint8)
            for key in ["NacelleColour", "NacelleMetalRough", "NacelleNormal"]}
    for index, (base, rough, metal) in enumerate(FINISHES):
        rows = slice(TILE * (index // 4), TILE * (index // 4 + 1))
        cols = slice(TILE * (index % 4), TILE * (index % 4 + 1))
        grain = rng.normal(0, 1, x.shape)
        brushing = np.sin((y + 0.001 * np.sin(x * 7)) * 490)
        variation = grain * 0.9 + brushing * (2 if metal > 0.7 else 0.3)
        colour = np.array(base, dtype=float)[None, None, :] + variation[:, :, None]
        if index == ORANGE:
            # A parallel pair of asymmetrically spaced warm-ivory racing flashes.
            ramp = x - y * 0.20
            flash = ((ramp > 0.19) & (ramp < 0.29)) | ((ramp > 0.315) & (ramp < 0.333))
            colour[flash] = (226, 208, 161)
        elif index == TITANIUM:
            # Oxide colours belong to the hot metal. Refractory ceramic stays
            # matte and dielectric rather than inheriting a metal rainbow.
            tint = np.array([(70,70,74), (88,91,106), (109,84,91), (151,119,83), (174,164,140)])
            for channel in range(3):
                colour[:, :, channel] = np.interp(y + 0.022*np.sin(9*x), np.linspace(0,1,5), tint[:,channel]) + variation
        elif index == CAUTION:
            bars = (np.mod(x + 0.26 * y, 0.33) < 0.115)
            colour[bars] *= 0.24
        elif index == SERVICE:
            # Three printed index lines on each access latch.
            index_lines = (x > 0.17) & (x < 0.65 - 0.18 * y) & (y > 0.26) & (y < 0.74)
            colour[index_lines & (np.mod(y - 0.26, 0.17) < 0.045)] = (188, 193, 175)
        # Pressed perimeter groove, exposed edges and grime at the fasteners.
        border = np.minimum.reduce([x, 1-x, y, 1-y])
        groove = np.exp(-((border-0.085)/0.006)**2)
        scuff = np.exp(-((border-0.062)/0.009)**2) * (0.4 + 0.6*rng.random(x.shape))
        sockets = np.zeros_like(x)
        for px,py in [(0.13,0.14),(0.87,0.14),(0.13,0.86),(0.87,0.86)]:
            d = np.hypot(x-px, y-py)
            sockets += np.exp(-(d/0.018)**2) - 0.50*np.exp(-((d-0.022)/0.006)**2)
        panel = index in (ORANGE,SERVICE,IVORY)
        # Hardware shares these islands with rolled lips and tubes. A pressed
        # panel border there repeated once per sector, drawing false mesh seams.
        relief = 0.75*groove + sockets if panel else np.zeros_like(x)
        painted = index in (ORANGE, GRAPHITE, CAUTION, IVORY, SERVICE)
        wear = np.clip(scuff*0.32,0,1) if panel else np.zeros_like(x)
        colour = colour*(1.0-0.46*relief[:, :, None])*(1-wear[:,:,None]) + np.array([174,174,164])*wear[:,:,None]
        dy, dx = np.gradient(relief)
        maps["NacelleColour"][rows, cols] = colour.clip(0, 255).astype(np.uint8)
        maps["NacelleMetalRough"][rows, cols] = np.stack((
            (1-0.26*relief)*255,
            (rough*255 + grain*2.2 + brushing*(4 if metal > 0.7 else 0.6) + 25*relief - 24*wear),
            (metal+(1-metal)*wear if painted else np.full_like(x,metal))*255
        ), axis=-1).clip(0, 255).astype(np.uint8)
        normal = np.stack((grain*1.2 + 115*dx, brushing*(2 if metal>.7 else .4) - 115*dy, np.full_like(x,127.5)),axis=-1)
        normal /= np.linalg.norm(normal,axis=-1,keepdims=True)
        maps["NacelleNormal"][rows, cols] = ((normal*.5+.5)*255).clip(0,255).astype(np.uint8)
    for name, bitmap in maps.items():
        write_png(directory / (name + ".png"), bitmap)


def material(directory):
    mat = bpy.data.materials.new("Nacelle heat-treated alloy and enamel")
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    pbr = next(n for n in nodes if n.type == "BSDF_PRINCIPLED")
    def texture(name, data=False):
        node = nodes.new("ShaderNodeTexImage")
        node.image = bpy.data.images.load(str(directory / (name + ".png")))
        if data:
            node.image.colorspace_settings.name = "Non-Color"
        node.image.pack()
        return node.outputs["Color"]
    links.new(texture("NacelleColour"), pbr.inputs["Base Color"])
    channels = nodes.new("ShaderNodeSeparateColor")
    links.new(texture("NacelleMetalRough", True), channels.inputs["Color"])
    links.new(channels.outputs["Green"], pbr.inputs["Roughness"])
    links.new(channels.outputs["Blue"], pbr.inputs["Metallic"])
    normal = nodes.new("ShaderNodeNormalMap")
    links.new(texture("NacelleNormal", True), normal.inputs["Color"])
    links.new(normal.outputs["Normal"], pbr.inputs["Normal"])
    return mat


class Nacelle:
    """Coordinates use the Godot rig convention, with +Z aft and +Y up."""
    def __init__(self):
        self.points = []
        self.faces = []
        self.uvs = []
        self.normals = []
        self.smooth = []

    def face(self, points, outward, finish, uv=None, normals=None):
        if uv is None:
            uv = [(0, 0), (1, 0), (1, 1), (0, 1)][:len(points)]
        assert len(points) == len(uv)
        points = [Vector(p) for p in points]
        if (points[1] - points[0]).cross(points[2] - points[0]).dot(Vector(outward)) < 0:
            points.reverse()
            uv = list(reversed(uv))
            if normals is not None:
                normals = list(reversed(normals))
        self.smooth.append(normals is not None)
        if normals is None:
            # Zero requests Blender's geometric corner normal. In particular,
            # triangulated non-planar plates need each triangle's own normal.
            normals = [(0,0,0)] * len(points)
        for normal in normals:
            n = Vector(normal).normalized()
            self.normals.append((n.x,-n.z,n.y))
        start = len(self.points)
        self.points.extend((p.x, -p.z, p.y) for p in points)
        self.faces.append(tuple(range(start, start + len(points))))
        for u, v in uv:
            self.uvs.append(((finish % 4 + 0.05 + u * 0.90) / 4,
                             1 - (finish // 4 + 0.05 + v * 0.90) / 2))

    def plate(self, rim, normal, depth, bevel, finish, edge):
        normal = Vector(normal).normalized()
        rim = [Vector(p) for p in rim]
        center = sum(rim, Vector((0, 0, 0))) / len(rim)
        top = [p.lerp(center, bevel) + normal * depth for p in rim]
        axes = sorted(range(3), key=lambda axis: abs(normal[axis]))[:2]
        bounds = [(min(p[a] for p in top), max(p[a] for p in top)) for a in axes]
        uv = [tuple((p[a] - lo) / max(0.0001, hi - lo) for a, (lo, hi) in zip(axes, bounds)) for p in top]
        for i in range(len(rim)):
            j = (i + 1) % len(rim)
            self.face([rim[i], rim[j], top[j], top[i]], (rim[i] + rim[j]) / 2 - center, edge)
        self.face(top, normal, finish, uv)

    def sleeve(self, z_values, radii, sectors, finish, segmented=False):
        """Open, superelliptical exhaust sleeve; never puts a face across the exhaust slot."""
        def pos(t, w, h, z):
            x, y = math.cos(t), math.sin(t)
            return (math.copysign(abs(x)**0.55, x) * w, math.copysign(abs(y)**0.55, y) * h, z)
        for i in range(sectors):
            gap = 0.018 if segmented else 0
            a = math.tau * (i + gap) / sectors
            b = math.tau * (i + 1 - gap) / sectors
            radial = (math.cos((a + b) / 2), math.sin((a + b) / 2), 0)
            rings = [[pos(t, w, h, z) for t in (a, b)] for z, (w, h) in zip(z_values, radii)]
            for j in range(len(rings) - 1):
                s = j / (len(rings) - 1)
                e = (j + 1) / (len(rings) - 1)
                smooth = None
                if not segmented:
                    # Smooth around the rolled circumference, retaining the
                    # authored axial breaks between the rolled profile stations.
                    smooth = []
                    for angle in (a,b,b,a):
                        w,h = radii[j]
                        tangent = Vector(pos(angle+.0001,w,h,z_values[j]))-Vector(pos(angle-.0001,w,h,z_values[j]))
                        along = Vector(pos(angle,*radii[j+1],z_values[j+1]))-Vector(pos(angle,w,h,z_values[j]))
                        normal = tangent.cross(along).normalized()
                        smooth.append(normal if normal.dot(Vector(radial))>=0 else -normal)
                self.face([*rings[j], rings[j + 1][1], rings[j + 1][0]], radial, finish,
                          [(0,s),(1,s),(1,e),(0,e)], normals=smooth)
            lip = [pos(t, radii[-1][0] - 0.033, radii[-1][1] - 0.025, z_values[-1] - 0.008) for t in (a,b)]
            self.face([*rings[-1], lip[1], lip[0]], (0, 0, 1), STEEL)

    def object(self, name, mat):
        mesh = bpy.data.meshes.new(name)
        mesh.from_pydata(self.points, [], self.faces)
        mesh.uv_layers.new(name="Deck and exhaust atlas")
        for loop, point in zip(mesh.uv_layers.active.data, self.uvs):
            loop.uv = point
        mesh.materials.append(mat)
        mesh.update()
        for polygon,smooth in zip(mesh.polygons,self.smooth):
            polygon.use_smooth = smooth
        mesh.normals_split_custom_set(self.normals)
        obj = bpy.data.objects.new(name, mesh)
        bpy.context.collection.objects.link(obj)
        bpy.context.view_layer.objects.active = obj
        obj.select_set(True)
        # Triangulate the actual polygons so tangents are exported for the normal map.
        modifier = obj.modifiers.new("Game triangles", "TRIANGULATE")
        bpy.ops.object.modifier_apply(modifier=modifier.name)

    def tube(self, start, end, radius, finish, sides=12):
        a,b = Vector(start),Vector(end)
        axis = (b-a).normalized()
        u = axis.orthogonal().normalized()
        v = axis.cross(u)
        circle = [u*math.cos(math.tau*j/sides)+v*math.sin(math.tau*j/sides) for j in range(sides)]
        for j,n in enumerate(circle):
            m = circle[(j+1)%sides]
            self.face([a+n*radius,b+n*radius,b+m*radius,a+m*radius], n+m, finish, normals=[n,n,m,m])
        self.face([a+n*radius for n in circle], -axis, STEEL, [(0.5+n.dot(u)*0.48,0.5+n.dot(v)*0.48) for n in circle])
        self.face([b+n*radius for n in circle], axis, STEEL, [(0.5+n.dot(u)*0.48,0.5+n.dot(v)*0.48) for n in circle])


def brake_leaf(front):
    leaf = Nacelle()
    # Local hinge at z=0, outward skin above, boxed spars on the pressure face.
    outline = [(-0.41,0), (0.41,0), (0.49,0.15), (0.46,1.02),
               (0.34,1.28), (0.22,1.30), (-0.39,1.21), (-0.48,1.02), (-0.49,0.17)]
    for side,finish in [(1, TITANIUM),(-1, CAUTION if front else ORANGE)]:
        leaf.plate([(x,0.014,z) for x,z in outline], (0,side,0), 0.027, 0.035, finish, STEEL)
    for x in [-0.31, 0.0, 0.31]:
        rib = [(x-0.028,0.12),(x+0.028,0.12),(x+0.023,1.09),(x-0.018,1.13)]
        leaf.plate([(a,-0.014,b) for a,b in rib],(0,-1,0),0.034,0.12,GRAPHITE,TITANIUM)
    for x in [-0.34,0.34]:
        leaf.tube((x-0.095,0.025,0.045),(x+0.095,0.025,0.045),0.049,STEEL)
    leaf.tube((-0.49,0.025,0.045),(0.49,0.025,0.045),0.028,GRAPHITE)
    return leaf


def detail_hardware(kit):
    kit.sleeve([-4.015,-3.96,-3.81,-3.48],[(1.155,0.477),(1.238,0.511),(1.26,0.527),(1.226,0.489)],80,TITANIUM)
    kit.sleeve([2.07,2.19,2.58,2.84],[(1.075,0.402),(1.119,0.434),(1.125,0.438),(1.118,0.428)],28,TITANIUM,True)
    for z in (2.33,2.69):
        kit.sleeve([z-0.038,z-0.024,z+0.024,z+0.038],[(1.12,0.437),(1.145,0.453),(1.145,0.453),(1.12,0.437)],32,GRAPHITE)
    # Rolled intake bellmouths, with a dark inner wall and an exposed machined lip.
    for cx in (-0.55,0.55):
        section = [(0.368,-3.842),(0.36,-3.965),(0.371,-4.015),(0.414,-4.008),(0.449,-3.847)]
        for j in range(64):
            a,b = (math.tau*n/64 for n in (j,j+1))
            for k,((r,z),(rr,zz)) in enumerate(zip(section,section[1:])):
                ring = [(cx+s*math.cos(t),s*math.sin(t),d) for s,d,t in [(r,z,a),(r,z,b),(rr,zz,b),(rr,zz,a)]]
                mid = (a+b)/2
                normals=[((zz-z)*math.cos(t),(zz-z)*math.sin(t),r-rr) for t in (a,b,b,a)]
                kit.face(ring, ((zz-z)*math.cos(mid),(zz-z)*math.sin(mid),r-rr), [GRAPHITE,TITANIUM,STEEL,TITANIUM][k],
                         uv=[(a/math.tau,k/4),(b/math.tau,k/4),(b/math.tau,(k+1)/4),(a/math.tau,(k+1)/4)],normals=normals)
    # Scalloped overlapping exit petals with a real return into the dark nozzle well.
    for j in range(24):
        a = math.tau*(j+0.032)/24
        b = math.tau*(j+0.968)/24
        def point(t,w,h,z):
            return (w*math.copysign(abs(math.cos(t))**0.65,math.cos(t)),
                    h*math.copysign(abs(math.sin(t))**0.65,math.sin(t)),z)
        mid=(a+b)/2
        radial=(math.cos(mid),math.sin(mid),0)
        root=[point(t,1.125,0.425,3.80) for t in (a,b)]
        lip=[point(t,1.05,0.369,z) for t,z in [(a,4.31),(mid,4.41),(b,4.31)]]
        inside=[point(t,0.997,0.317,z-0.008) for t,z in [(a,4.31),(mid,4.41),(b,4.31)]]
        for lo,hi in [(0,1),(1,2)]:
            kit.face([root[lo],lip[lo],lip[hi]],radial,CERAMIC)
            kit.face([lip[lo],lip[hi],inside[hi],inside[lo]],(0,0,1),STEEL)
        kit.face([*root,lip[1]],radial,CERAMIC)
        kit.face([*inside,point(b,0.93,0.265,4.025),point(a,0.93,0.265,4.025)],tuple(-x for x in radial),GRAPHITE,
                 [(0,1),(0.5,1),(1,1),(1,0),(0,0)])
    for s in (-1,1):
        # A formed bypass fairing sweeps up from the intake and tucks back in at
        # the brake hinge. The change of section is large enough to read at speed.
        stations=[(-3.24,0.38,0.87,0.52),(-2.78,0.31,1.04,0.64),(-1.55,0.34,1.12,0.735),
                  (-0.32,0.44,1.09,0.70),(0.84,0.60,1.01,0.61),(1.26,0.76,0.90,0.51)]
        rings=[]
        for z,inner,outer,peak in stations:
            rings.append([(s*inner,0.485,z),(s*(inner+0.12),peak-0.016,z),
                          (s*(outer-0.14),peak,z),(s*outer,0.505,z)])
        for j,(a,b) in enumerate(zip(rings,rings[1:])):
            for k,finish in enumerate([GRAPHITE,ORANGE,TITANIUM]):
                normal=[(-s*0.7,0.6,0),(0,1,0),(s*0.7,0.6,0)][k]
                kit.face([a[k],b[k],b[k+1],a[k+1]],normal,finish,[(0,j/5),(0,(j+1)/5),(1,(j+1)/5),(1,j/5)])
        # Shrouded black vent with sloped thermal louvers on the raised shoulder.
        for i in range(5):
            z=-1.49+i*0.17
            x=0.60+i*0.014
            h=0.743-i*0.005
            rim=[(s*x,h,z),(s*(x+0.255),h,z+0.055),(s*(x+0.25),h,z+0.12),(s*x,h,z+0.105)]
            kit.plate(rim,(0,1,-0.44),0.031,0.12,GRAPHITE,STEEL)
        # Paired bypass pipes turn into fittings at each end; side-brake sweep stops before these.
        for y in (-0.18,-0.065):
            path=[(s*1.24,y,-1.25),(s*1.325,y+0.035,-1.05),(s*1.325,y+0.035,0.52),(s*1.19,y+0.10,0.83)]
            for a,b in zip(path,path[1:]):
                kit.tube(a,b,0.040,TITANIUM)
            for z in [-0.94,0.40]:
                kit.tube((s*1.325,y+0.035,z),(s*1.325,y+0.035,z+0.083),0.062,STEEL,8)


def build():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    kit = Nacelle()
    # A dark joint underneath the separated tapered heat-shield leaves gives the exhaust
    # a layered profile when viewed from behind. The moving petals end at z=2.7 m.
    kit.sleeve([2.77, 2.83, 2.93], [(1.01,0.37), (1.14,0.451), (1.125,0.449)], 32, GRAPHITE)
    kit.sleeve([2.87, 2.95, 3.75, 4.12],
               [(1.10,0.423), (1.145,0.474), (1.143,0.456), (1.108,0.407)], 28, CERAMIC, True)
    kit.sleeve([2.85, 2.90, 2.965], [(1.113,0.432), (1.16,0.478), (1.148,0.46)], 32, TITANIUM)
    for side in (-1, 1):
        # Armour follows the cool shoulder; the central deck stays clear of the fin
        # and painted legend. The chamfer is substantial enough to read from the pod.
        shoulder = [(0.39,-2.05), (0.74,-2.13), (1.04,-1.90), (1.075,-0.76),
                    (0.98,1.05), (0.81,1.32), (0.69,1.15), (0.65,0.12)]
        rim = [(side*x, 0.541 - (x-0.39)*0.09, z) for x,z in shoulder]
        kit.plate(rim, (side*0.09,1,0), 0.061, 0.095, ORANGE, GRAPHITE)
        # Cast side service panel visible from the pilot's oblique view and on a bank.
        service = [(-0.24,-1.18), (0.21,-1.49), (0.31,-1.27), (0.28,0.26),
                   (0.11,0.55), (-0.19,0.54), (-0.27,0.22)]
        rim = [(side*1.223,y,z) for y,z in service]
        kit.plate(rim,(side,0,0),0.035,0.095,SERVICE,TITANIUM)
        # Porcelain hot-zone cheeks sit outboard of the nozzle opening. The spun edge
        # and ochre witness mark identify the hot side even with the burner off.
        for sign in (-1, 1):
            shield = [(0.72,3.00),(0.97,3.01),(1.085,3.18),(1.07,3.85),
                      (0.96,4.03),(0.83,3.88)]
            rim = [(side*x,sign*(0.461-(x-0.72)*0.25),z) for x,z in shield]
            kit.plate(rim,(side*0.25,sign,0),0.032,0.09,IVORY,CERAMIC)
        witness = [(3.13,-0.10),(3.26,-0.16),(3.76,-0.13),(3.83,0.08),(3.64,0.11),(3.22,0.09)]
        kit.plate([(side*1.145,y,z) for z,y in witness],(side,0,0),0.018,0.08,CAUTION,TITANIUM)
    ASSET.parent.mkdir(parents=True, exist_ok=True)
    gas_textures(ASSET.parent)
    with tempfile.TemporaryDirectory() as tmp:
        directory = Path(tmp)
        surface_maps(directory)
        mat = material(directory)
        detail_hardware(kit)
        kit.object("NacelleHardware",mat)
        brake_leaf(False).object("AftBrakeLeaf",mat)
        brake_leaf(True).object("FrontBrakeLeaf",mat)
        bpy.ops.export_scene.gltf(filepath=str(ASSET), export_format="GLB", export_texcoords=True,
                                  export_tangents=True, export_yup=True)


def gas_textures(directory):
    """Continuous periodic eddies for both gas layers and the recessed flame holder."""
    size = 256
    rng = np.random.default_rng(236)
    fy,fx = np.meshgrid(np.fft.fftfreq(size),np.fft.fftfreq(size),indexing="ij")
    channels=[]
    for frequency in [0.048,0.10,0.17]:
        filt = np.exp(-((fx/frequency)**2 + (fy/(frequency*0.50))**2))
        cloud = np.fft.ifft2(np.fft.fft2(rng.normal(size=(size,size)))*filt).real
        channels.append(np.clip(128 + 44*cloud/cloud.std(),0,255))
    write_png(directory/"jet_flow.png",np.stack(channels,axis=-1).astype(np.uint8))
    y,x = np.mgrid[0:160,0:512]
    u,v = (x+0.5)/512,(y+0.5)/160
    cell_x = (u*23 + 0.5*(np.floor(v*6)%2))%1-0.5
    cell_y = (v*6)%1-0.5
    holes = np.clip((0.43-np.hypot(cell_x,cell_y))*15,0,1)
    heat = np.clip(1.0-((2*v-1)**4 + (2*u-1)**8),0,1)
    colour = (18 + 220*heat*holes)*(0.87+0.13*np.cos(u*math.tau*3))
    write_png(directory/"flame_holder.png",np.stack((colour,colour*0.82,colour*0.67),axis=-1).astype(np.uint8))


if __name__ == "__main__":
    build()
