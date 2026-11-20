"""Realism spike: the throttle grip at hand distance.

    blender --background --python tools/art_grip_hd.py [-- --res 1024]

Same envelope as art_cockpit.py's Grip (a lathed, slightly square barrel on the lever, cap at
y = 0.055 under the gate indicator). The turned profile is geometry; the knurl, turning marks,
anodising wear and rubber are synthesised in surface metres and wrap seamlessly round the barrel.
"""
import math
import sys
import tempfile
from pathlib import Path

import bpy
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from art_coaming_hd import ARGS, TAB, box, f32, mix, png, smooth  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "godot/art/cockpit/grip_hd.glb"
RES = int(ARGS[ARGS.index("--res") + 1]) if "--res" in ARGS else 1024
COLLAR, RING, RUBBER, ANODISED, CAP = range(5)
# (y, radius across, radius fore-and-aft, band of the run that ENDS here, curved run?)
PROFILE = [(-.0610, .0165, .0165, COLLAR, 0), (-.0610, .0205, .0245, COLLAR, 0), (-.0595, .0220, .0260, COLLAR, 0),
           (-.0555, .0270, .0300, COLLAR, 0), (-.0540, .0275, .0306, COLLAR, 0), (-.0530, .0262, .0292, COLLAR, 0),
           (-.0515, .0262, .0292, COLLAR, 0), (-.0505, .0292, .0322, RING, 0), (-.0485, .0300, .0332, RING, 0),
           (-.0470, .0296, .0336, RING, 0), (-.0440, .0310, .0360, RUBBER, 1), (-.0320, .0340, .0400, RUBBER, 1),
           (-.0140, .0340, .0390, RUBBER, 1), (.0060, .0320, .0380, RUBBER, 1), (.0230, .0350, .0410, RUBBER, 1),
           (.0360, .0352, .0394, RUBBER, 1), (.0375, .0340, .0380, RUBBER, 0), (.0385, .0356, .0396, ANODISED, 0),
           (.0400, .0362, .0402, ANODISED, 0), (.0445, .0340, .0378, ANODISED, 0), (.0465, .0316, .0354, ANODISED, 0),
           (.0475, .0300, .0340, CAP, 0), (.0515, .0268, .0312, CAP, 0), (.0535, .0235, .0282, CAP, 0),
           (.0548, .0180, .0220, CAP, 0), (.0552, .0090, .0110, CAP, 0), (.0553, .0004, .0004, CAP, 0)]


def resample():
    """Rows along the profile: (y, rx, rz), their arc length, and each row's band."""
    pts = np.array([p[:3] for p in PROFILE])
    rows, bands = [pts[0]], [PROFILE[0][3]]
    for i in range(1, len(pts)):
        a, b = pts[i - 1], pts[i]
        steps = max(1, int(np.linalg.norm((b - a)[:2]) / .0011))
        for k in range(1, steps + 1):
            u = k / steps
            point = a + (b - a) * u
            if PROFILE[i][4] and PROFILE[i - 1][4]:             # Catmull-Rom through the rubber's swell
                p0, p3 = pts[max(i - 2, 0)], pts[min(i + 1, len(pts) - 1)]
                point = .5 * (2 * a + (b - p0) * u + (2 * p0 - 5 * a + 4 * b - p3) * u * u + (3 * a - p0 - 3 * b + p3) * u**3)
            rows.append(point)
            bands.append(PROFILE[i][3])
    rows = np.array(rows)
    arc = np.concatenate([[0], np.cumsum(np.hypot(np.diff(rows[:, 0]), np.diff(rows[:, 1])))])
    return rows, arc, np.array(bands)


ROWS, ARC, BAND = resample()
TLEN = float(ARC[-1])
CIRC = 2 * math.pi * .037                                          # the wrap, at the rubber's mean radius
KU, KT = RES / CIRC, RES * .98 / TLEN                              # texels per metre round and along


def pnoise(x, y, period):
    xi, yi = np.floor(x).astype(np.int32), np.floor(y).astype(np.int32)
    fx, fy = smooth(x - xi), smooth(y - yi)
    x0, x1, y0, y1 = xi % period, (xi + 1) % period, yi & 255, (yi + 1) & 255
    top = TAB[y0, x0] + (TAB[y0, x1] - TAB[y0, x0]) * fx
    bot = TAB[y1, x0] + (TAB[y1, x1] - TAB[y1, x0]) * fx
    return (top + (bot - top) * fy).astype(f32)


def pfbm(u, y, cells, octaves=3):
    total = sum(.5**k * pnoise(u * cells * 2**k, y * 2**k + 9.1 * k, cells * 2**k) for k in range(octaves))
    return total / (2 - .5**(octaves - 1))


def textures(folder):
    u = ((np.arange(RES) + .5) / RES)[None, :].astype(f32)        # round the barrel; 0.5 faces the pilot
    t = np.clip(TLEN * (1 - (np.arange(RES) + .5 - .01 * RES) / (.98 * RES)), 0, TLEN)[:, None].astype(f32)
    u, t = np.broadcast_arrays(u, t)
    band = BAND[np.clip(np.searchsorted(ARC, t), 0, len(ARC) - 1)]
    radius = np.interp(t, ARC, ROWS[:, 1]).astype(f32)
    edges = ARC[np.flatnonzero(np.diff(BAND)) + 1]                  # where one material meets the next
    edge = np.min(np.abs(t[..., None] - edges), axis=-1)
    grit = pnoise(u * 256, t * 5200, 256)
    turned = np.cos(2 * math.pi * t / .00024) * .5 + .5              # lathe marks run round the part
    col = np.zeros(u.shape + (3,), f32)
    h, rough, metal = np.zeros(u.shape, f32), np.zeros(u.shape, f32), np.zeros(u.shape, f32)

    for which, base, r, m in ((COLLAR, (186, 189, 193), .3, 1.0), (RING, (50, 53, 57), .46, .85), (CAP, (46, 49, 53), .5, .85)):
        k = band == which
        worn = smooth((pfbm(u, t * 700, 64) + .55 * np.exp(-edge / .0005) - 1.2) * 10) if which != COLLAR else 0 * u
        tone = mix(np.array(base, f32) + (turned[..., None] - .5) * (9 if which == COLLAR else 3) + (grit[..., None] - .5) * 8, (196, 198, 201), worn)
        col[k], rough[k], metal[k] = tone[k], (r + (turned - .5) * .08 - .16 * worn)[k], m
        h[k] = ((turned - .5) * (4e-6 if which == COLLAR else 1e-6) + (grit - .5) * (2e-6 if which == COLLAR else 9e-6))[k]
    k = band == ANODISED                                            # orange anodising, bright on its chamfers
    worn = smooth((pfbm(u, t * 900, 64) + .6 * np.exp(-edge / .0006) - 1.12) * 10)
    tone = mix(np.array((214, 92, 22), f32) * (.94 + .12 * pfbm(u, t * 40, 8)[..., None]) + (turned[..., None] - .5) * 10, (201, 203, 206), worn)
    col[k], rough[k], metal[k] = tone[k], (.3 + (turned - .5) * .1 + .05 * worn)[k], 1
    h[k] = ((turned - .5) * 3e-6 - 5e-6 * worn)[k]

    # moulded rubber: diamond knurl worn smooth where the palm sits, a parting line, dust in the cuts
    k = band == RUBBER
    turns, pitch = 72, .0031
    g1 = np.abs((turns * u + t / pitch) % 1 - .5)
    g2 = np.abs((turns * u - t / pitch) % 1 - .5)
    pyramid = smooth(np.minimum(g1, g2) * 2 / .8)
    body = smooth(edge / .004)                                      # the knurl fades out toward both shoulders
    palm = smooth(1.5 * np.cos(2 * math.pi * (u - .5)) + .9 * pfbm(u, t * 60, 4) - .7)
    relief = body * (1 - .78 * palm)
    parting = np.exp(-(((u % .5) - .25) * CIRC / .00022)**2)
    hr = .00024 * pyramid * relief + (grit - .5) * 1.4e-5 + 3e-5 * parting
    dust = (1 - pyramid) * relief * smooth((pfbm(u, t * 90, 8) - .35) * 3)
    rubber = mix(np.array((25, 25, 26), f32) * (.9 + .25 * palm[..., None]), (84, 80, 74), .5 * dust)
    col[k], h[k], rough[k], metal[k] = rubber[k], hr[k], (.88 - .34 * palm + .08 * dust)[k], 0

    # the grub screw that pins the collar to the lever, on the outboard side
    ty = float(np.interp(-.0575, ROWS[:, 0], ARC))
    r = np.hypot((u - .25) * CIRC, t - ty)
    hole = r < .0019
    h = np.where(hole, -.0009 * smooth((.0019 - r) / .0005), h)
    col = np.where(hole[..., None], 30.0 + 60 * smooth((r - .0012) / .0007)[..., None], col)
    rough = np.where(hole, .5, rough)

    macro = np.broadcast_to(radius, u.shape).astype(f32)
    ao = np.clip(1 - .9 * (box(macro, .003 * KT) - macro) / .0016, .3, 1) * np.clip(1 - .8 * (box(h, .0007 * KT) - h) / .00016, .5, 1)
    col *= (.74 + .26 * ao)[..., None]
    rough = np.clip(rough + .12 * (1 - ao), .04, 1)
    dx = (np.roll(h, -1, axis=1) - np.roll(h, 1, axis=1)) * .5      # wraps round the barrel
    dy = np.gradient(h, axis=0)
    n = np.dstack([-dx * KU, dy * KT, np.ones_like(h)])
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    png(folder / "GripHD_Base.png", np.clip(col, 0, 255).astype(np.uint8))
    png(folder / "GripHD_Normal.png", np.rint((n * .5 + .5) * 255).astype(np.uint8))
    png(folder / "GripHD_ORM.png", (np.dstack([ao, rough, metal]) * 255).astype(np.uint8))


def build(material):
    around = 96
    u = np.arange(around + 1)[None, :] / around
    phi = -math.pi / 2 - 2 * math.pi * u                             # the UV seam faces away from the pilot
    square = lambda p: np.sign(p) * np.abs(p)**.78
    y, rx, rz = (ROWS[:, i][:, None] for i in range(3))
    gx, gy, gz = square(np.cos(phi)) * rx, y + 0 * u, square(np.sin(phi)) * rz
    xyz = np.stack([gx, -gz, gy], axis=-1).reshape(-1, 3)            # Godot XYZ -> Blender; GLB exports +Y up
    v = .01 + .98 * ARC[:, None] / TLEN
    uv = np.stack([u + 0 * v, v + 0 * u], axis=-1).reshape(-1, 2)
    nr, nc = len(ROWS), around + 1
    a = (np.arange(nr - 1)[:, None] * nc + np.arange(nc - 1)[None, :]).ravel()
    faces = np.stack([a, a + 1, a + nc + 1, a + nc], axis=-1)
    mesh = bpy.data.meshes.new("Grip")
    mesh.from_pydata(xyz.tolist(), [], faces.tolist())
    mesh.uv_layers.new(name="GripUV").data.foreach_set("uv", uv[faces.ravel()].astype(f32).ravel())
    mesh.polygons.foreach_set("use_smooth", np.ones(len(faces), bool))
    mesh.materials.append(material)
    mesh.update()
    bpy.context.collection.objects.link(bpy.data.objects.new("Grip", mesh))
    print("MESH", len(mesh.vertices), "vertices", len(faces) * 2, "triangles", flush=True)


def pbr(folder, prefix):
    material = bpy.data.materials.new(prefix + "_PBR")
    material.use_nodes = True
    tree = material.node_tree
    bsdf = next(n for n in tree.nodes if n.type == "BSDF_PRINCIPLED")

    def image(kind, data):
        tex = tree.nodes.new("ShaderNodeTexImage")
        tex.image = bpy.data.images.load(str(folder / f"{prefix}_{kind}.png"))
        if data:
            tex.image.colorspace_settings.name = "Non-Color"
        return tex.outputs["Color"]
    tree.links.new(image("Base", False), bsdf.inputs["Base Color"])
    bump = tree.nodes.new("ShaderNodeNormalMap")
    tree.links.new(image("Normal", True), bump.inputs["Color"])
    tree.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    split = tree.nodes.new("ShaderNodeSeparateColor")
    tree.links.new(image("ORM", True), split.inputs["Color"])
    tree.links.new(split.outputs["Green"], bsdf.inputs["Roughness"])
    tree.links.new(split.outputs["Blue"], bsdf.inputs["Metallic"])
    return material


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    print("GRIP", f"{TLEN * 1000:.0f} mm profile, {KU / 1000:.2f} x {KT / 1000:.2f} texels/mm at {RES}", flush=True)
    with tempfile.TemporaryDirectory() as tmp:
        textures(Path(tmp))
        build(pbr(Path(tmp), "GripHD"))
        bpy.ops.export_scene.gltf(filepath=str(OUTPUT), export_tangents=True, export_animations=False,
                                  export_cameras=False, export_lights=False)
    print("Wrote", OUTPUT, OUTPUT.stat().st_size, "bytes")


if __name__ == "__main__":
    main()
