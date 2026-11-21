"""Rebuild the flight-deck GLB with Blender --background --python tools/art_cockpit.py."""
import math
import struct
import tempfile
import zlib
from pathlib import Path

import bpy
import numpy as np


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "godot/art/cockpit/flight_deck.glb"
TAU = math.tau
# One shared atlas. Each horizontal strip has UV padding for mip reconstruction.
PAINT, SEAL, METAL, GRAPHITE, CERAMIC, GRIP, FASTENER, BADGE = range(8)
COLORS = [(187, 77, 23), (52, 44, 41), (140, 146, 148), (62, 69, 72),
          (206, 195, 165), (48, 49, 49), (110, 110, 101), (39, 53, 58)]
ROUGH = [.34, .66, .33, .61, .45, .79, .46, .49]
METALLIC = [.43, .02, .91, .39, .13, .02, .82, .65]
GLYPHS = {
    'P': ["1110","1001","1001","1110","1000","1000","1000"],
    'H': ["1001","1001","1001","1111","1001","1001","1001"],
    'A': ["0110","1001","1001","1111","1001","1001","1001"],
    'E': ["1111","1000","1000","1110","1000","1000","1111"],
    'T': ["11111","00100","00100","00100","00100","00100","00100"],
    'O': ["0110","1001","1001","1001","1001","1001","0110"],
    'N': ["10001","11001","11001","10101","10011","10011","10001"],
}


def png(path, pixels):
    height, width, _ = pixels.shape
    def chunk(kind, data):
        return struct.pack(">I", len(data))+kind+data+struct.pack(">I", zlib.crc32(kind+data))
    header = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    data = b"".join(b"\0"+row.tobytes() for row in pixels)
    path.write_bytes(b"\x89PNG\r\n\x1a\n"+chunk(b"IHDR", header)+chunk(b"IDAT", zlib.compress(data))+chunk(b"IEND", b""))


def atlas(folder):
    width, strip = 1024, 128
    rng = np.random.default_rng(2107)
    albedo = np.empty((8 * strip, width, 3), dtype=np.uint8)
    normal = np.empty_like(albedo)
    orm = np.empty_like(albedo)
    y, x = np.mgrid[0:strip, 0:width]
    u, v = (x+.5)/width, (y+.5)/strip
    for band, base in enumerate(COLORS):
        noise = rng.normal(0, 1, (strip, width))
        brush = rng.normal(0, 1, (strip, 1))*.55+np.sin(y*1.6)*.15
        grain = .48*noise + brush if band in [METAL, FASTENER] else noise
        color = np.zeros((strip, width, 3)) + base
        color += grain[..., None] * (2.7 if band != PAINT else 1.45)
        height = grain * (.32 if band in [SEAL, GRIP] else .12)
        rough = ROUGH[band] + np.clip(grain, -2, 2)*.017
        if band == SEAL:
            # Two offset lines of waxed thread punched through the leather welt.
            for line in [.20, .78]:
                thread = ((abs(v-line) < .033) & (abs(((u*24 + v*.42) % 1)-.5) < .34))
                color[thread] = (130, 104, 75)
                height[thread] += 2.2
        if band == PAINT:
            edge = np.exp(-((v-.09)/.065)**2) + .45*np.exp(-((v-.94)/.055)**2)
            color += edge[..., None]*np.array([15, 12, 11])
            rough += edge*.09
        if band == GRIP:
            palm = np.exp(-((u-.5)/.31)**2 - ((v-.42)/.31)**2)
            color += palm[..., None]*np.array([22, 20, 17])
            rough -= palm*.28
            groove = (np.cos(TAU*(u*17+v*1.7)) * np.cos(TAU*(u*17-v*1.7)))**3
            height += groove*(1-palm)*1.7
        if band == FASTENER:
            slot = (abs(v-.5)<.075) & (abs(u-.5)<.32)
            color[slot] *= .19
            height[slot] -= 3
        if band == BADGE:
            pen = 111
            for ch in "PHAETHON":
                glyph = GLYPHS[ch]
                for row, cells in enumerate(glyph):
                    for col, filled in enumerate(cells):
                        if filled == '1':
                            area = np.s_[31+9*row:31+9*(row+1), pen+19*col:pen+19*(col+1)]
                            color[area] = (221, 211, 180)
                            height[area] += .4
                pen += (len(glyph[0])+1)*19
        dy, dx = np.gradient(height)
        n = np.dstack([-dx*.37, dy*.37, np.ones_like(dx)])
        n /= np.linalg.norm(n, axis=2, keepdims=True)
        rows = slice(band*strip, (band+1)*strip)
        albedo[rows] = np.clip(color, 0, 255)
        normal[rows] = np.rint((n*.5+.5)*255)
        orm[rows] = np.dstack([np.full_like(u, 255), np.clip(rough, 0, 1)*255,
                               np.full_like(u, METALLIC[band]*255)])
    for name, image in [("FlightDeck_Base",albedo),("FlightDeck_Normal",normal),("FlightDeck_ORM",orm)]:
        png(folder / (name+".png"), image)


def pbr(folder):
    material = bpy.data.materials.new("FlightDeck_PBR")
    material.use_nodes = True
    tree = material.node_tree
    bsdf = tree.nodes.get("Principled BSDF")
    def image(name, data):
        tex = tree.nodes.new("ShaderNodeTexImage")
        tex.image = bpy.data.images.load(str(folder / (name+".png")))
        if data:
            tex.image.colorspace_settings.name = "Non-Color"
        return tex.outputs["Color"]
    tree.links.new(image("FlightDeck_Base", False), bsdf.inputs["Base Color"])
    n = tree.nodes.new("ShaderNodeNormalMap")
    tree.links.new(image("FlightDeck_Normal", True), n.inputs["Color"])
    tree.links.new(n.outputs["Normal"], bsdf.inputs["Normal"])
    split = tree.nodes.new("ShaderNodeSeparateColor")
    tree.links.new(image("FlightDeck_ORM", True), split.inputs["Color"])
    tree.links.new(split.outputs["Green"], bsdf.inputs["Roughness"])
    tree.links.new(split.outputs["Blue"], bsdf.inputs["Metallic"])
    return material


class Part:
    def __init__(self, name):
        self.name, self.xyz, self.faces, self.uv = name, [], [], []

    def grid(self, columns, rows, sample, band, smooth=True):
        start = len(self.xyz)
        for j in range(rows+1):
            for i in range(columns+1):
                u,v = i/columns, j/rows
                gx,gy,gz = sample(u,v)
                self.xyz.append((gx,-gz,gy))  # Godot XYZ -> Blender, GLB exports +Y up
                self.uv.append((.008+u*.984, 1-(band+.96-.92*v)/8))
        for j in range(rows):
            for i in range(columns):
                a = start+j*(columns+1)+i
                self.faces.append(((a, a+1, a+columns+2, a+columns+1), smooth))

    def finish(self, material):
        mesh = bpy.data.meshes.new(self.name)
        mesh.from_pydata(self.xyz, [], [face for face,_ in self.faces])
        texcoords = mesh.uv_layers.new(name="FlightDeckUV")
        for face, (_, smooth) in zip(mesh.polygons, self.faces):
            face.use_smooth = smooth
            for loop in face.loop_indices:
                texcoords.data[loop].uv = self.uv[mesh.loops[loop].vertex_index]
        mesh.materials.append(material)
        mesh.update()
        obj = bpy.data.objects.new(self.name, mesh)
        bpy.context.collection.objects.link(obj)
        return obj


def hull_section(z):
    # Same Catmull-Rom hull stations as craft_model.gd: the section's half-width, bottom and top (pod space).
    hull = [(-2.22,.06,-.19,-.11),(-2.12,.30,-.28,-.05),(-1.9,.62,-.4,-.01),
            (-1.5,.90,-.50,0),(-1,1.06,-.56,-.02),(-.4,1.13,-.58,-.05),
            (.4,1.15,-.58,-.06),(1.05,1.11,-.56,.04),(1.45,.98,-.51,.17),
            (1.8,.68,-.42,.12),(2.02,.42,-.31,.03),(2.15,.18,-.18,-.04)]
    k = next(i for i in range(len(hull)-1) if hull[i+1][0]>=z)
    t = (z-hull[k][0])/(hull[k+1][0]-hull[k][0])
    def cat(col):
        a,b,c,d = [hull[min(len(hull)-1,max(0,k+off))][col] for off in [-1,0,1,2]]
        return .5*(2*b+(c-a)*t+(2*a-5*b+4*c-d)*t*t+(3*b-a-3*c+d)*t**3)
    return [cat(i) for i in [1,2,3]]


def hull_top(x,z):
    # The hull's top at (x, z), in rig space.
    w,lo,hi = hull_section(z)
    return .6+(hi+lo)*.5+(hi-lo)*.5*(1-(abs(x)/w)**2.6)**(1/2.6)


def hull_floor(x,z,inside=.035):
    # The hull's floor at (x, z), in rig space, `inside` in from the outer skin (0.035: the trim's own
    # face; craft_model.gd's hull_clearance wants every fitting a centimetre clear of that).
    w,lo,hi = hull_section(z)
    return .6+(hi+lo)*.5-((hi-lo)*.5-inside)*(1-min(abs(x)/(w-inside),1.0)**2.6)**(1/2.6)


# The cockpit opening, as craft_model.gd has it: an egg in plan, widest at OPEN_ZC, running OPEN_AZ
# aft of there and OPEN_AZ_FRONT ahead of it.
OPEN_AX, OPEN_ZC, OPEN_AZ, OPEN_AZ_FRONT = .72, .15, 1.15, .72


def open_az(front):
    return OPEN_AZ_FRONT if front else OPEN_AZ


def coaming_point(degrees, angle, radius):
    a, p = map(math.radians,(degrees,angle))
    az = open_az(math.cos(a) > 0)
    x,z = OPEN_AX*math.sin(a), OPEN_ZC-az*math.cos(a)
    rx,rz = -math.sin(a)/OPEN_AX, math.cos(a)/az
    length = math.hypot(rx,rz)
    return x+rx/length*radius*math.cos(p), hull_top(x,z)+radius*math.sin(p), z+rz/length*radius*math.cos(p)


def coaming():
    part = Part("Coaming")
    # Separate removable sheet-metal facing panels, graphite reveal and an upholstered welt.
    ends = [-138,-112,-81,-55,-31,-10,10,31,55,81,112,138]
    for left,right in zip(ends,ends[1:]):
        bands = [(-62,-49,.058,.065,METAL),(-49,-29,.065,.071,GRAPHITE),
                 (-29,24,.071,.068,PAINT),(24,31,.068,.067,METAL),
                 (31,77,.067,.063,SEAL),(77,92,.063,.067,PAINT),
                 (92,112,.067,.061,SEAL),(112,130,.061,.056,GRAPHITE)]
        for bottom,top,r0,r1,finish in bands:
            def sample(u,v):
                a = left+.30+(right-left-.60)*u
                rolled = min(1, u*45, (1-u)*45)
                return coaming_point(a,bottom+(top-bottom)*v,r0+(r1-r0)*v-.003*(1-rolled))
            part.grid(18,3,sample,finish)
        # Recessed brand plate and UV-engraved captive screw heads face the pilot.
        if left == -10:
            part.grid(15, 3, lambda u,v:coaming_point(-8.1+16.2*u, -23+42*v, .0730), BADGE)
        else:
            for end in [left+1.7,right-1.7]:
                # A square patch with bevelled corners represented directly in the UV footprint.
                def fastener(u,v):
                    xx,yy=2*u-1,2*v-1
                    f=min(1, 1.34/(abs(xx)+abs(yy)+.0001))
                    return coaming_point(end+.48*xx*f,-1+6.6*yy*f,.072)
                part.grid(3,3,fastener,FASTENER)
    return part


def dash_point(x,y,d):
    phi=x/1.32
    gx,gz=(1.32-d)*math.sin(phi),1.32-(1.32-d)*math.cos(phi)
    c,s=math.cos(-.29),math.sin(-.29)
    return gx,.27+y*c-gz*s,-.70+y*s+gz*c


def bezel():
    part = Part("Bezel")
    for side in [-1,1]:
        x0,x1 = sorted([side*.440,side*.419])
        part.grid(3,24,lambda u,v:dash_point(x0+(x1-x0)*u,-.127+.254*v,.034), GRAPHITE)
        x0,x1 = sorted([side*.437,side*.433])
        part.grid(1,12,lambda u,v:dash_point(x0+(x1-x0)*u,-.11+.22*v,.035),METAL)
        for yy in [-.147,.148]:
            part.grid(3,3,lambda u,v:dash_point(side*.411+(u-.5)*.012,yy+(v-.5)*.012,.038),FASTENER)
    for base in [-.157,.141]:
        part.grid(42,3,lambda u,v:dash_point(-.417+.834*u,base+.014*v,.033+.003*v),GRAPHITE)
        part.grid(42,1,lambda u,v:dash_point(-.397+.794*u,base+.011+.002*v,.037),METAL)
    # Finished outer rails round the open throttle slots. The moving shaft has >30 mm clearance.
    for side in [-1,1]:
        for edge in [-1,1]:
            x = side*.46+edge*.034
            part.grid(2,12,lambda u,v:(x+(u-.5)*.015,.1435,.337-.267*v), METAL)
            part.grid(1,9,lambda u,v:(x+(u-.5)*.008,.1445,.19-.111*v),GRAPHITE)
    footplates(part)
    return part


def footplates(part):
    # A pair of pressed, clipped-corner inserts on the existing 0.84 m footwell.
    # The driver sees this at the bottom of the windscreen when looking down.
    def plate(cx, cz, width, length, y, band, chamfer):
        def sample(u, v):
            z = [length/2, length/2-chamfer, -length/2+chamfer, -length/2][round(v*3)]
            inset = max(0, abs(z)-(length/2-chamfer))
            return cx+(u-.5)*(width-2*inset), y, cz+z
        part.grid(1, 3, sample, band)

    for side in [-1, 1]:
        cx = side*.199
        plate(cx, 0, .385, 1.042, .144, METAL, .055)
        plate(cx, 0, .373, 1.027, .145, GRAPHITE, .052)
        plate(cx, 0, .303, .899, .146, GRIP, .057)
        # Each chevron has a sloped leading edge and a dark trailing relief.
        for row in range(9):
            start = -.38 + row*.095
            for edge in [-1, 1]:
                lo, hi = sorted((edge*.014, edge*.142))
                def rib(u, v):
                    offset = lo+(hi-lo)*u
                    z = start+abs(offset)*.36+.027*(.5-v)
                    lift = min(1, u*8, (1-u)*8, v*6, (1-v)*6)
                    return cx+offset, .1465+.005*lift, z
                part.grid(7,5,rib,GRAPHITE)
        for end in [-1,1]:
            for edge in [-1,1]:
                plate(cx+edge*.143,end*.476,.018,.018,.1475,FASTENER,.004)
        for marker in range(3):
            x = cx+side*(.158-marker*.015)
            plate(x,-.448,.007,.029,.147,PAINT,.0015)


def grip():
    part = Part("Grip")
    profile=[(-.061,.021,.025,METAL),(-.055,.027,.030,METAL),(-.049,.030,.033,GRAPHITE),
             (-.044,.031,.036,GRIP),(-.032,.034,.040,GRIP),(-.014,.034,.039,GRIP),
             (.006,.032,.038,GRIP),(.023,.035,.041,GRIP),(.038,.035,.039,GRIP),
             (.047,.031,.035,PAINT),(.053,.025,.030,GRAPHITE),(.055,.006,.008,GRAPHITE)]
    for (y0,x0,z0,_),(y1,x1,z1,material) in zip(profile,profile[1:]):
        def sample(u,v):
            phi = -TAU*u
            def signed(p): return math.copysign(abs(p)**.78,p)
            return (signed(math.cos(phi))*(x0+(x1-x0)*v),
                    y0+(y1-y0)*v,
                    signed(math.sin(phi))*(z0+(z1-z0)*v))
        part.grid(32,2,sample,material)
    return part


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    with tempfile.TemporaryDirectory() as tmp:
        atlas(Path(tmp))
        mat=pbr(Path(tmp))
        for item in [coaming(),bezel(),grip()]:
            item.finish(mat)
        OUTPUT.parent.mkdir(exist_ok=True,parents=True)
        bpy.ops.export_scene.gltf(filepath=str(OUTPUT),export_tangents=True,
                                  export_animations=False,export_cameras=False,export_lights=False)
    print("Wrote", OUTPUT, OUTPUT.stat().st_size, "bytes")


if __name__ == "__main__":
    main()
