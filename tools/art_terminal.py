"""Build the Eridanus shelter kit in metres, with one PBR atlas and draw surface per module.

Run with Python, Pillow and NumPy. The glTF uses +Y up. The road goes along local Z.
"""

import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw


DEST = Path(__file__).resolve().parents[1] / "godot" / "art" / "terminal"
# Realism spike: 256-pixel cells, four weathered variants of every finish, and faces laid as
# separate panels about PANEL metres across instead of one swatch stretched over a whole wall.
CELL = 256
GRID = 8
ATLAS = GRID * CELL
VARIANTS = 4
PANEL = 10.0
K = CELL // 128
TILED = {"plate", "recess", "enamel", "ivory", "intake", "hazard", "steel", "cladding", "lampwell",
         "shutter", "tile", "window", "gasket"}
# Name, base colour (sRGB), roughness, metallic, emission (sRGB).
SWATCHES = [
    ("plate", (95, 110, 116), 167, 65, (0, 0, 0)),
    ("recess", (47, 58, 65), 198, 60, (0, 0, 0)),
    ("enamel", (208, 107, 50), 146, 58, (0, 0, 0)),
    ("ivory", (174, 178, 163), 174, 20, (0, 0, 0)),
    ("intake", (71, 78, 82), 205, 70, (0, 0, 0)),
    ("hazard", (204, 140, 63), 161, 54, (0, 0, 0)),
    ("tube", (189, 232, 239), 148, 10, (122, 188, 194)),
    ("beacon", (243, 165, 82), 142, 10, (215, 117, 42)),
    ("steel", (104, 115, 119), 137, 121, (0, 0, 0)),
    ("cladding", (111, 127, 131), 193, 40, (28, 36, 39)),
    ("lampwell", (99, 122, 130), 193, 35, (47, 62, 66)),
    ("shutter", (83, 90, 90), 193, 37, (11, 14, 14)),
    ("tile", (79, 94, 100), 201, 25, (29, 38, 42)),
    ("service", (52, 77, 81), 179, 32, (15, 29, 33)),
    ("window", (78, 115, 119), 87, 80, (64, 98, 94)),
    ("gasket", (35, 42, 45), 221, 16, (0, 0, 0)),
]
CELL_INDEX = {entry[0]: i for i, entry in enumerate(SWATCHES)}


def make_atlas():
    albedo = Image.new("RGB", (ATLAS, ATLAS))
    orm = Image.new("RGB", (ATLAS, ATLAS))
    emission = Image.new("RGB", (ATLAS, ATLAS))
    normal = Image.new("RGB", (ATLAS, ATLAS), (128, 128, 255))
    rng = np.random.default_rng(731)
    yy, xx = np.mgrid[:CELL, :CELL]
    for i, (name, base, rough, metallic, glow) in enumerate(SWATCHES):
        for variant in range(VARIANTS):
            # A cool wash in the centre of the panels falls off toward their mounting channels.
            wash = 0.54 + 0.53 * np.exp(-((xx - 64 * K) / (68 * K)) ** 2 - ((yy - 58 * K) / (73 * K)) ** 2)
            wear = rng.normal(0, 0.013, (CELL, CELL)) + rng.normal(0, 0.013, (1, CELL))
            # Rain and dust: streaks that start part-way down a panel and fade toward its foot.
            top = rng.random((1, CELL))
            run = np.clip(yy / CELL - top, 0, 1)
            streak = rng.random((1, CELL)) ** 3 * np.clip(run * 4, 0, 1) * np.exp(-run * 2.4)
            streak = (np.roll(streak, 1, 1) + streak + np.roll(streak, -1, 1)) / 3
            lit = sum(glow) > 0
            batch = 1 + (0 if lit else rng.normal(0, 0.035))       # no two panels came off the line alike
            value = (0.96 + wear) * batch
            if name in ("plate", "cladding", "lampwell", "tile"):
                value = (wash + wear) * batch
            if not lit:
                value = value * (1 - 0.24 * streak)
            tile = Image.fromarray(np.uint8(np.clip(value[:, :, None] * base, 0, 255)))
            light = Image.fromarray(np.uint8(np.clip(wash[:, :, None] * glow, 0, 255)))
            relief = Image.new("L", (CELL, CELL), 128)             # 128 is the panel's face
            d, e, h = ImageDraw.Draw(tile), ImageDraw.Draw(light), ImageDraw.Draw(relief)
            if name in ("cladding", "plate", "lampwell", "tile", "shutter"):
                seam = tuple(int(0.48 * c) for c in base)
                frame = (9 * K, 7 * K, 118 * K, 120 * K)
                d.rounded_rectangle(frame, radius=5 * K, outline=seam, width=2 * K)
                h.rounded_rectangle(frame, radius=5 * K, outline=48, width=2 * K)
                for x in (14 * K, 113 * K):
                    for y in (12 * K, 115 * K):
                        d.ellipse((x - 2 * K, y - 2 * K, x + 2 * K, y + 2 * K), fill=seam)
                        h.ellipse((x - 2 * K, y - 2 * K, x + 2 * K, y + 2 * K), fill=215)
                        d.point((x - K, y - K), fill=(131, 140, 139))
            if name in ("intake", "shutter"):
                for y in range(13 * K, 119 * K, 11 * K):
                    d.rectangle((7 * K, y, 120 * K, y + 3 * K), fill=(43, 49, 52))
                    h.rectangle((7 * K, y, 120 * K, y + 3 * K), fill=30)
                    d.line((8 * K, y + 4 * K, 119 * K, y + 4 * K), fill=(117, 124, 123), width=K)
                    h.line((8 * K, y + 4 * K, 119 * K, y + 4 * K), fill=200, width=K)
            if name == "hazard":
                for x in range(-128 * K, 165 * K, 36 * K):
                    d.polygon([(x, 0), (x + 15 * K, 0), (x + 143 * K, CELL), (x + 128 * K, CELL)], fill=(52, 58, 55))
            if name == "window":
                for x in (4 * K, 43 * K, 84 * K, 122 * K):
                    d.rectangle((x, 0, x + 2 * K, CELL), fill=(44, 56, 60))
                    e.rectangle((x, 0, x + 2 * K, CELL), fill=(5, 8, 9))
                    h.rectangle((x, 0, x + 2 * K, CELL), fill=205)
            if name == "service":
                # Transit maintenance mark, registered to the gallery face's UVs.
                for image, ink in ((d, (215, 216, 191)), (e, (64, 79, 75))):
                    image.line([(17 * K, 93 * K), (33 * K, 37 * K), (49 * K, 93 * K)], fill=ink, width=5 * K)
                    image.line([(27 * K, 72 * K), (39 * K, 72 * K)], fill=ink, width=4 * K)
                    for y in (39 * K, 63 * K, 87 * K):
                        image.rectangle((63 * K, y, 108 * K, y + 4 * K), fill=ink)
            # Relief to a tangent-space normal (green up), softened so edges read as pressed, not cut.
            height = np.asarray(relief, dtype=float) / 255
            for axis in (0, 1):
                height = (np.roll(height, 1, axis) + 2 * height + np.roll(height, -1, axis)) / 4
            gy, gx = np.gradient(height)
            n = np.dstack([-gx * 9.0, gy * 9.0, np.ones_like(height)])
            n /= np.linalg.norm(n, axis=2, keepdims=True)
            shade = np.clip(1 - 1.7 * np.clip(0.5 - height, 0, 1), 0.4, 1)     # grooves and louvres sit in shadow
            rough_map = np.clip(rough / 255 + (0 if lit else 0.12) * streak - 0.05 * (wash - 0.8), 0.05, 1)
            cell = i * VARIANTS + variant
            xy = (cell % GRID * CELL, cell // GRID * CELL)
            albedo.paste(tile, xy)
            orm.paste(Image.fromarray(np.uint8(np.dstack([shade * 255, rough_map * 255, np.full_like(shade, metallic)]))), xy)
            emission.paste(light, xy)
            normal.paste(Image.fromarray(np.uint8(np.rint((n * 0.5 + 0.5) * 255))), xy)
    for name, image in (("base", albedo), ("orm", orm), ("emission", emission), ("normal", normal)):
        image.save(DEST / f"shelter_{name}.png", optimize=True)


class Module:
    def __init__(self, name):
        self.name = name
        self.pos, self.norm, self.uv, self.tan, self.idx = [], [], [], [], []

    def face(self, corners, swatch):
        """Add one outward-facing flat face as separate panels, each on its own atlas cell."""
        p = np.asarray(corners, dtype=float)
        e, f = p[1] - p[0], p[3] - p[0]
        tangent = e / np.linalg.norm(e)
        n = np.cross(e, f)
        n /= np.linalg.norm(n)
        across = up = 1
        if swatch in TILED:
            across = max(1, round(float(np.linalg.norm(e)) / PANEL))
            up = max(1, round(float(np.linalg.norm(f)) / PANEL))
        low, high = 3 / ATLAS, 1 / GRID - 3 / ATLAS

        def at(s, t):
            return (p[0] * (1 - s) + p[1] * s) * (1 - t) + (p[3] * (1 - s) + p[2] * s) * t
        for a in range(across):
            for b in range(up):
                cell = CELL_INDEX[swatch] * VARIANTS + (len(self.pos) // 4 * 7 + a * 3 + b * 5) % VARIANTS
                u, v = cell % GRID / GRID, cell // GRID / GRID
                start = len(self.pos)
                self.pos.extend([at(a / across, b / up), at((a + 1) / across, b / up),
                                 at((a + 1) / across, (b + 1) / up), at(a / across, (b + 1) / up)])
                self.norm.extend([n] * 4)
                self.tan.extend([[*tangent, 1]] * 4)                # bitangent up the face, with the map's green
                self.uv.extend([(u+low, v+high), (u+high, v+high), (u+high, v+low), (u+low, v+low)])
                self.idx.extend([start, start+1, start+2, start, start+2, start+3])

    def prism(self, section, z, depth, face, edge=None):
        """Extrude a counterclockwise convex XY quad. Both travel directions get a finished face."""
        low = [(x, y, z-depth/2) for x, y in section]
        high = [(x, y, z+depth/2) for x, y in section]
        self.face(high, face)
        self.face(low[::-1], face)
        for i in range(4):
            j = (i+1) % 4
            self.face([low[i], low[j], high[j], high[i]], edge or face)

    def block(self, x, y, z, width, height, depth, swatch, edge=None):
        a, b = width/2, height/2
        self.prism([(x-a, y-b), (x+a, y-b), (x+a, y+b), (x-a, y+b)], z, depth, swatch, edge)

    def member(self, a, b, thickness, z, depth, swatch, edge=None):
        a, b = np.array(a), np.array(b)
        axis = b-a
        normal = np.array([-axis[1], axis[0]]) * (thickness/2/np.linalg.norm(axis))
        self.prism([a-normal, b-normal, b+normal, a+normal], z, depth, swatch, edge)


def make_bay(kind):
    m = Module(kind)
    gallery = kind == "ServiceGallery"
    full_frame = kind != "LightWell"
    # Service galleries along the flanks and faceted haunches leave the carriageway untouched.
    for s in (-1, 1):
        m.block(s*100, 30, 0, 4.2, 44, 16, "cladding", "tile")
        if full_frame:
            m.member((s*99, 52), (s*80, 85), 5, 0, 15, "plate", "tile")
            m.member((s*81, 84), (s*51, 101), 6, 0, 15, "plate", "tile")
            m.member((s*95, 51), (s*66, 88), 2.5, -1.8, 5, "steel")
            m.member((s*80, 86), (s*78, 100), 3, 0, 10, "recess")
        m.block(s*96.5, 34, 0, 3.3, 4, 14, "plate", "steel")
        # Service bay shutters, long viewing galleries, gallery floor and a continuous conduit.
        m.block(s*99.4, 29, -25, 2.7, 30, 36, "plate", "shutter")
        m.block(s*97.7, 46, -25, 2.7, 3, 39, "recess", "steel")
        if gallery:
            m.block(s*98, 44.1, -25, 1.5, 0.75, 30, "beacon")
        m.block(s*99.6, 30, 24, 2.5, 30, 34, "plate", "tile")
        m.block(s*97.5, 50.2, 24, 3.1, 9, 33, "gasket", "window" if gallery else "recess")
        m.block(s*96.4, 45.5, 24, 3, 1.4, 36, "steel")
        m.block(s*98.5, 9, 0, 4.3, 2.2, 87, "plate", "tile")
        for z in (-40, -24, -8, 8, 24, 40):
            m.block(s*97.8, 16, z, 2.8, 11.6, 15.1, "recess", "cladding")
        if gallery:
            # The deep, projecting operators' gallery and stencil are visible in either direction.
            m.block(s*94.5, 61, 1, 9.8, 19, 62, "steel", "window")
            m.block(s*93.2, 70.5, 1, 13.5, 2.5, 68, "plate")
            m.block(s*92, 50.5, 1, 15.5, 3, 69, "steel")
            m.block(s*93, 39, 1, 5, 17, 21, "gasket")
            # Face the lettering toward the road; keep Y vertical on both sides.
            x = s * 90.4
            m.face([(x,31,1-s*10),(x,31,1+s*10),(x,47,1+s*10),(x,47,1-s*10)], "service")
        # Paired suspended light wells, with a broad diffusor and visible recess.
        m.block(s*37, 98.4, 0, 33, 8.7, 14.5, "plate", "lampwell")
        m.block(s*37, 93.9, 0, 27, 1.4, 10.6, "gasket")
        m.block(s*37, 93.1, 0, 23, 0.4, 6.8, "tube")
        m.block(s*64, 103.6, 25, 6.8, 5.5, 49, "recess", "steel")
        m.block(s*64, 104, -25, 6.8, 5.5, 49, "recess", "steel")
    if full_frame:
        m.block(0, 104.8, 0, 114, 7.8, 14.8, "plate", "tile")
        m.block(0, 100.1, 0, 102, 2.4, 16.5, "steel", "plate")
    else:
        for x in (-49,-25,25,49):
            m.block(x,104.5,0,2.5,12,6,"recess")
    return m


def make_gate():
    m = Module("StormGate")
    # A blast shutter parked overhead, with deep stacked jaws and protected warning lanterns.
    m.block(0, 117, 0, 210, 30, 29, "plate", "cladding")
    m.block(0, 103.5, 0, 168, 16, 30, "ivory", "tile")
    m.block(0, 95.4, 0, 146, 4.4, 31, "enamel")
    for z in (-17, 17):
        for x in range(-60, 61, 12):
            m.block(x, 106, z, 10.8, 7, 3.1, "intake", "recess")
        m.block(0, 96, z, 62, 1.7, 1.8, "enamel")
    for s in (-1, 1):
        m.block(s*103, 63, 0, 14, 114, 44, "ivory", "plate")
        m.block(s*102, 17, 0, 9, 19, 48, "hazard", "recess")
        m.member((s*101, 44), (s*72, 97), 10.5, 0, 32, "plate", "cladding")
        m.member((s*96, 57), (s*75, 96), 3.2, -17.5, 3, "enamel")
        m.member((s*96, 57), (s*75, 96), 3.2, 17.5, 3, "enamel")
        for z in (-24, 24):
            m.block(s*101.5, 67, z, 7, 32, 4, "recess")
            m.block(s*101.5, 67, z*1.10, 3.6, 22, 1.5, "beacon")
        m.block(s*82, 124, 0, 20, 24, 37, "enamel", "plate")
    return m


def write_gltf(modules):
    blob, views, accessors = bytearray(), [], []
    def array(data, dtype, kind, target):
        while len(blob) % 4:
            blob.append(0)
        v = np.asarray(data, dtype=dtype)
        view = {"buffer": 0, "byteOffset": len(blob), "byteLength": v.nbytes, "target": target}
        views.append(view)
        blob.extend(v.tobytes())
        acc = {"bufferView": len(views)-1, "componentType": 5126 if dtype == "<f4" else 5123,
               "count": len(v), "type": kind}
        if kind == "VEC3":
            acc.update(min=v.min(axis=0).tolist(), max=v.max(axis=0).tolist())
        accessors.append(acc)
        return len(accessors)-1
    meshes = []
    for m in modules:
        assert len(m.pos) < 65536, m.name               # indices are 16-bit
        attributes = {k: array(v, "<f4", t, 34962) for k, v, t in
                      (("POSITION", m.pos, "VEC3"), ("NORMAL", m.norm, "VEC3"),
                       ("TEXCOORD_0", m.uv, "VEC2"), ("TANGENT", m.tan, "VEC4"))}
        meshes.append({"name": m.name, "primitives": [{"attributes": attributes, "material": 0,
                       "indices": array(m.idx, "<u2", "SCALAR", 34963)}]})
    names = ["base", "orm", "emission", "normal"]
    material = {"name": "Shelter enamel and service lighting", "pbrMetallicRoughness": {
        "baseColorTexture": {"index": 0}, "metallicRoughnessTexture": {"index": 1}},
        "emissiveTexture": {"index": 2}, "emissiveFactor": [1.0, 1.0, 1.0],
        "normalTexture": {"index": 3}, "occlusionTexture": {"index": 1}}
    asset = {"asset": {"version": "2.0", "generator": "Phaethon shelter workshop"}, "scene": 0,
             "scenes": [{"nodes": list(range(len(modules)))}],
             "nodes": [{"name": m.name, "mesh": i} for i, m in enumerate(modules)], "meshes": meshes,
             "materials": [material], "textures": [{"source": i, "sampler": 0} for i in range(4)],
             "samplers": [{"magFilter": 9729, "minFilter": 9987}],
             "images": [{"uri": f"shelter_{name}.png"} for name in names],
             "buffers": [{"uri": "shelter.bin", "byteLength": len(blob)}],
             "bufferViews": views, "accessors": accessors}
    (DEST/"shelter.bin").write_bytes(blob)
    (DEST/"shelter.gltf").write_text(json.dumps(asset, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    DEST.mkdir(parents=True, exist_ok=True)
    make_atlas()
    write_gltf([make_bay("BayFrame"), make_gate(), make_bay("LightWell"), make_bay("ServiceGallery")])
