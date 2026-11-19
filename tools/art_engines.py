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
TILE = 192
# Each finish occupies a padded patch in a single shared PBR atlas.
ORANGE, CERAMIC, GRAPHITE, STEEL, CAUTION, TITANIUM, IVORY, SERVICE = range(8)
FINISHES = [
    ((199, 80, 31), 0.34, 0.35), ((138, 128, 110), 0.54, 0.76),
    ((50, 55, 58), 0.62, 0.44), ((153, 159, 160), 0.33, 0.89),
    ((214, 168, 66), 0.49, 0.34), ((86, 91, 100), 0.43, 0.84),
    ((201, 196, 175), 0.44, 0.39), ((47, 67, 69), 0.52, 0.40),
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
        elif index == CERAMIC:
            # Exhaust ceramic picks up a broad bronze-blue heat tint toward the edge.
            heat = np.clip(y * 2 - 0.45, 0, 1)[:, :, None]
            colour += heat * np.array((-27, -17, 0)) + np.sin(y * 8)[:, :, None] * (4, 0, -6)
        elif index == CAUTION:
            bars = (np.mod(x + 0.26 * y, 0.33) < 0.115)
            colour[bars] *= 0.24
        elif index == SERVICE:
            # Three printed index lines on each access latch.
            index_lines = (x > 0.17) & (x < 0.65 - 0.18 * y) & (y > 0.26) & (y < 0.74)
            colour[index_lines & (np.mod(y - 0.26, 0.17) < 0.045)] = (188, 193, 175)
        maps["NacelleColour"][rows, cols] = colour.clip(0, 255).astype(np.uint8)
        maps["NacelleMetalRough"][rows, cols] = np.stack((
            np.ones_like(x) * 255, (rough * 255 + grain * 2.2 + brushing * 3), np.ones_like(x) * metal * 255
        ), axis=-1).clip(0, 255).astype(np.uint8)
        maps["NacelleNormal"][rows, cols] = np.stack((
            128 + grain * 1.7, 128 + brushing * 3, np.full_like(x, 255)), axis=-1).clip(0, 255).astype(np.uint8)
    for name, bitmap in maps.items():
        write_png(directory / (name + ".png"), bitmap)


def material(directory):
    mat = bpy.data.materials.new("Nacelle heat-treated alloy and enamel")
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    pbr = nodes.get("Principled BSDF")
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

    def face(self, points, outward, finish, uv=None):
        uv = uv or [(0, 0), (1, 0), (1, 1), (0, 1)]
        points = [Vector(p) for p in points]
        if (points[1] - points[0]).cross(points[2] - points[0]).dot(Vector(outward)) < 0:
            points.reverse()
            uv = list(reversed(uv))
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
                self.face([*rings[j], rings[j + 1][1], rings[j + 1][0]], radial, finish,
                          [(0,s),(1,s),(1,e),(0,e)])
            lip = [pos(t, radii[-1][0] - 0.033, radii[-1][1] - 0.025, z_values[-1] - 0.008) for t in (a,b)]
            self.face([*rings[-1], lip[1], lip[0]], (0, 0, 1), STEEL)

    def export(self, path, mat):
        mesh = bpy.data.meshes.new("Nacelle fairings")
        mesh.from_pydata(self.points, [], self.faces)
        mesh.uv_layers.new(name="Deck and exhaust atlas")
        for loop, point in zip(mesh.uv_layers.active.data, self.uvs):
            loop.uv = point
        mesh.materials.append(mat)
        mesh.update()
        obj = bpy.data.objects.new("Ceramic exhaust and shoulder kit", mesh)
        bpy.context.collection.objects.link(obj)
        bpy.context.view_layer.objects.active = obj
        obj.select_set(True)
        # Triangulate the actual polygons so tangents are exported for the normal map.
        modifier = obj.modifiers.new("Game triangles", "TRIANGULATE")
        bpy.ops.object.modifier_apply(modifier=modifier.name)
        bpy.ops.export_scene.gltf(filepath=str(path), use_selection=True, export_format="GLB",
                                  export_texcoords=True, export_tangents=True, export_yup=True)


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
    with tempfile.TemporaryDirectory() as tmp:
        directory = Path(tmp)
        surface_maps(directory)
        kit.export(ASSET, material(directory))


if __name__ == "__main__":
    build()
