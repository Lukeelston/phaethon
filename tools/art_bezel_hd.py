"""Realism spike: the two tread plates and the rails round the instruments and throttle slots.

    blender --background --python tools/art_bezel_hd.py [-- --res 2048]

Same placements as art_cockpit.py's Bezel. The plates' frames, bevels and pressed chevrons are
geometry; coating, wear, grime, fasteners and the rails' machining are synthesised in surface
metres into one atlas, each plate and rail with its own unrepeated area.
"""
import math
import sys
import tempfile
from pathlib import Path

import bmesh
import bpy
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from art_cockpit import dash_point  # noqa: E402
from art_coaming_hd import ARGS, box, f32, fbm, mix, png, smooth, vnoise  # noqa: E402
from art_grip_hd import pbr  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "godot/art/cockpit/bezel_hd.glb"
RES = int(ARGS[ARGS.index("--res") + 1]) if "--res" in ARGS else 2048
Q = RES / 2048
PLATE_W, PLATE_L, TREAD_Y, RIB = .385, 1.042, .1462, .005
BASE = np.full((RES, RES, 3), (60, 70, 82), np.uint8)
NORMAL = np.full((RES, RES, 3), (128, 128, 255), np.uint8)
ORM = np.full((RES, RES, 3), (255, 110, 200), np.uint8)
XYZ, UV, FACES, SMOOTH = [], [], [], []


def rect(x, y, w, h):
    return tuple(int(round(v * Q)) for v in (x, y, w, h))


def window(area, length, width, pad=3):
    """Metres along (rows) and across (columns) for an atlas rectangle, with a little bleed."""
    x0, y0, w, h = area
    a = (np.clip((np.arange(-pad, h + pad) + .5) / h, 0, 1) * length)[:, None].astype(f32)
    b = (np.clip((np.arange(-pad, w + pad) + .5) / w, 0, 1) * width)[None, :].astype(f32)
    return a, b, np.s_[y0 - pad:y0 + h + pad, x0 - pad:x0 + w + pad]


def commit(area, length, width, where, col, h, rough, metal, ao):
    kx, ky = area[2] / width, area[3] / length
    ao = ao * np.clip(1 - .8 * (box(h, max(1, .0007 * ky)) - h) / .0002, .5, 1)
    col = col * (.72 + .28 * ao)[..., None]
    dy, dx = np.gradient(h)
    n = np.dstack([-dx * kx, dy * ky, np.ones_like(h)])
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    BASE[where] = np.clip(col, 0, 255)
    NORMAL[where] = np.rint((n * .5 + .5) * 255)
    ORM[where] = np.clip(np.dstack([ao, np.clip(rough + .14 * (1 - ao), .04, 1), metal]), 0, 1) * 255


def uv_of(area, length, width, a, b):
    x0, y0, w, h = area
    return (x0 + b / width * w) / RES, 1 - (y0 + a / length * h) / RES


def octagon(x, z, w, l, c):
    ax, az = np.abs(x), np.abs(z)
    return np.maximum(np.maximum(ax - w / 2, az - l / 2), (ax + az - (w / 2 + l / 2 - c)) / math.sqrt(2))


def rib_lift(offset, z):
    """0-1 height of the pressed chevrons: nine rows, a rib each side of the plate's centreline."""
    row = np.clip(np.round((z - .36 * offset + .38) / .095), 0, 8)
    uu = (offset - .014) / .128
    vv = .5 - (z - .36 * offset - (-.38 + row * .095)) / .027
    return smooth(np.minimum(np.minimum(uu * 8, (1 - uu) * 8), np.minimum(vv * 6, (1 - vv) * 6)))


def screw(x, z, at, radius, col, h, rough, metal):
    r = np.hypot(x - at[0], z - at[1])
    dish, head = r < radius * 1.7, r < radius
    hexa = head & (np.maximum(np.abs(x - at[0]), np.abs(x - at[0]) * .5 + np.abs(z - at[1]) * .866) < radius * .5)
    h = np.where(dish, -.0006 * smooth((radius * 1.7 - r) / (radius * .7)), h)
    h = np.where(head, -.0002 + .0003 * np.sqrt(np.clip(1 - (r / radius)**2, 0, 1)) - .0012 * hexa, h)
    col = np.where(dish[..., None], np.where(hexa[..., None], 18.0, np.where(head[..., None], 142.0, 96.0)), col)
    return col, h, np.where(dish, np.where(head, .34, .5), rough), np.where(dish, 1, metal)


def plate_texture(area, index):
    a, b, where = window(area, PLATE_L, PLATE_W)
    z, x = np.broadcast_arrays(a - PLATE_L / 2, b - PLATE_W / 2)
    seed = 5.3 * index
    frame, tread = octagon(x, z, PLATE_W, PLATE_L, .055), octagon(x, z, .361, 1.018, .05)
    on_tread = tread < 0
    lift = rib_lift(np.abs(x), z) * on_tread
    grit = fbm((x + seed) * 2600, z * 2600, 2)
    streak = vnoise((x + seed) * 3800, z * 45)                      # boots slide fore and aft
    heel = np.exp(-((np.abs(x) - .075) / .07)**2 - ((z - .12) / .2)**2)
    worn = .62 * lift + .35 * heel + .3 * fbm((x + seed) * 38, z * 22) + .12 * streak
    wear, thin = smooth((worn - .8) * 6), smooth((worn - .62) * 5)
    col = mix(mix(np.array((44, 50, 58), f32) + (grit[..., None] - .5) * 12, (96, 101, 108), .6 * thin),
              np.array((150, 154, 160), f32) + (streak[..., None] - .5) * 11, wear)
    h = (grit - .5) * 7e-5 * (1 - wear) + (streak - .5) * 6e-6 * wear - 3e-5 * wear
    rough, metal = .72 - .08 * thin - .2 * wear + (streak - .5) * .08 * wear, wear
    for sign in (-1, 0, 1):                                        # three painted index marks, outboard and forward
        mark = (np.abs(x - (1 if index else -1) * (.143 + .015 * sign)) < .0035) & (np.abs(z + .448) < .0145) & (fbm(x * 900, z * 900) < .7)
        col, rough, metal = np.where(mark[..., None], (214, 92, 22), col), np.where(mark, .42, rough), np.where(mark, 0, metal)
    # anodised frame, bright on its chamfers, with a rubber gasket where the tread sits in it
    edge = np.minimum(-frame, tread)
    bright = smooth((fbm((x + seed) * 300, z * 300) + .6 * np.exp(-np.clip(edge, 0, None) / .0009) - 1.05) * 9)
    rim = mix(np.array((58, 70, 84), f32) + (grit[..., None] - .5) * 10, (188, 191, 196), bright)
    k = ~on_tread
    col[k], h[k], rough[k], metal[k] = rim[k], ((grit - .5) * 9e-6)[k], (.42 - .12 * bright)[k], .9
    k = (tread >= 0) & (tread < .0016)
    col[k], h[k], rough[k], metal[k] = (14, 15, 16), -.0004, .86, 0
    for sx in (-.143, .143):
        for sz in (-.476, .476):
            col, h, rough, metal = screw(x, z, (sx, sz), .0034, col, h, rough, metal)
    macro = RIB * lift + .0017 * on_tread
    ao = np.clip(1 - .9 * (box(macro, .005 * area[3] / PLATE_L) - macro) / .0025, .3, 1)
    dust = smooth((fbm((x + seed) * 14, z * 9) + .45 * (-z / .52) + .9 * (1 - ao) - .95) * 4) * (1 - wear)
    col = mix(col, (88, 84, 78), .35 * dust)
    commit(area, PLATE_L, PLATE_W, where, col, h, rough + .12 * dust, metal * (1 - .7 * dust), ao)


def rail_texture(area, length, width, kind, seed):
    a, b, where = window(area, length, width)
    a, b = np.broadcast_arrays(a, b)
    grit = fbm((b + seed) * 4200, a * 4200, 2)
    brushed = vnoise((b + seed) * 4000, a * 40)
    edge = np.minimum(np.minimum(b, width - b), np.minimum(a, length - a))
    bright = smooth((fbm((b + seed) * 500, a * 160) + .7 * np.exp(-edge / .0007) - 1.08) * 9)
    h = -.0005 * (1 - smooth(edge / .0009))                          # the chamfer round every rail
    if kind == "slot":                                               # machined aluminium with an engraved travel scale
        col = np.array((180, 183, 187), f32) + (brushed[..., None] - .5) * 22
        rough, metal = .32 + (brushed - .5) * .12, np.ones_like(h)
        step = length / 10
        tick = (np.abs((a + step / 2) % step - step / 2) < .00035) & (b > width * np.where(np.round(a / step) % 5 == 0, .12, .45))
        col, h, rough = np.where(tick[..., None], 22.0, col), h - 6e-5 * tick + (brushed - .5) * 5e-6, np.where(tick, .6, rough)
    else:                                                            # graphite anodising with a polished inlay
        col = mix(np.array((52, 56, 61), f32) + (grit[..., None] - .5) * 9, (190, 193, 198), bright)
        rough, metal = .48 - .16 * bright, np.full(h.shape, .85, f32)
        inlay = np.abs(b - width * (.5 if kind == "frame" else .72)) < .0011
        col = np.where(inlay[..., None], 205.0 + (brushed[..., None] - .5) * 16, col)
        h, rough, metal = h + (grit - .5) * 8e-6 + 5e-5 * inlay, np.where(inlay, .22, rough), np.where(inlay, 1, metal)
        if kind == "frame":
            for at in (.006, length - .006):
                col, h, rough, metal = screw(b, a, (width / 2, at), .0032, col, h, rough, metal)
    ao = .6 + .4 * smooth(edge / .0015)
    commit(area, length, width, where, col, h, rough, metal, ao)


def add(points, uvs, faces, smooth_faces):
    start = len(XYZ)
    XYZ.extend((gx, -gz, gy) for gx, gy, gz in points)              # Godot XYZ -> Blender; GLB exports +Y up
    UV.extend(uvs)
    FACES.extend(tuple(start + i for i in face) for face in faces)
    SMOOTH.extend([smooth_faces] * len(faces))


def grid(area, length, width, sample, across, along, smooth_faces=True):
    """A patch whose columns run across the rail and rows along it, mapped to its atlas rectangle."""
    points, uvs = [], []
    for j in range(along + 1):
        for i in range(across + 1):
            ua, ub = j / along, i / across
            points.append(sample(ua, ub))
            uvs.append(uv_of(area, length, width, ua * length, ub * width))
    faces = [(j * (across + 1) + i, j * (across + 1) + i + 1, (j + 1) * (across + 1) + i + 1, (j + 1) * (across + 1) + i)
             for j in range(along) for i in range(across)]
    add(points, uvs, faces, smooth_faces)


def plate_mesh(area, cx):
    project = lambda x, z: uv_of(area, PLATE_L, PLATE_W, z + PLATE_L / 2, x + PLATE_W / 2)

    def slab(w, l, c, top, bottom, bevel):
        def ring(inset, y):                                           # counter-clockwise seen from above
            hw, hl = w / 2 - inset, l / 2 - inset
            cc = c - inset * (2 - math.sqrt(2))
            outline = [(hw, hl - cc), (hw - cc, hl), (-hw + cc, hl), (-hw, hl - cc), (-hw, -hl + cc), (-hw + cc, -hl), (hw - cc, -hl), (hw, -hl + cc)]
            return [(x, y, -z) for x, z in outline]
        rings = [ring(bevel, top), ring(0, top - bevel), ring(0, bottom)]
        points = [p for r in rings for p in r]
        faces = [tuple(range(8))]
        for k in (0, 1):
            faces += [(k * 8 + i, (k + 1) * 8 + i, (k + 1) * 8 + (i + 1) % 8, k * 8 + (i + 1) % 8) for i in range(8)]
        add([(cx + x, y, z) for x, y, z in points], [project(x, z) for x, y, z in points], faces, False)

    slab(PLATE_W, PLATE_L, .055, .1445, .139, .001)
    slab(.361, 1.018, .05, TREAD_Y, .1445, .0008)
    for row in range(9):
        for side in (-1, 1):
            lo, hi = sorted((side * .014, side * .142))

            def rib(ua, ub, lo=lo, hi=hi, row=row):
                offset = lo + (hi - lo) * ub
                z = -.38 + row * .095 + abs(offset) * .36 + .027 * (.5 - ua)
                lift = float(smooth(np.float64(min(ub * 8, (1 - ub) * 8, ua * 6, (1 - ua) * 6))))
                return cx + offset, TREAD_Y + RIB * lift, z
            points, uvs, across, along = [], [], 16, 10
            for j in range(along + 1):
                for i in range(across + 1):
                    p = rib(j / along, i / across)
                    points.append(p)
                    uvs.append(project(p[0] - cx, p[2]))
            faces = [(j * (across + 1) + i, j * (across + 1) + i + 1, (j + 1) * (across + 1) + i + 1, (j + 1) * (across + 1) + i)
                     for j in range(along) for i in range(across)]
            add(points, uvs, faces, True)


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    plate_w, plate_h = 732, 1980
    for index, cx in enumerate((-.199, .199)):
        area = rect(8 + index * 744, 30, plate_w, plate_h)
        plate_texture(area, index)
        plate_mesh(area, cx)
    n = 0
    rails_from = len(FACES)
    for base in (-.157, .141):                                      # rails above and below the instruments
        area = rect(1510 + 44 * n, 30, 34, 1960)
        rail_texture(area, .834, .014, "frame", 1.7 * n)
        grid(area, .834, .014, lambda ua, ub, base=base: dash_point(.417 - .834 * ua, base + .014 * ub, .033 + .003 * ub), 3, 56)
        n += 1
    for index, side in enumerate((-1, 1)):                          # ... and at each end of them
        x0, x1 = sorted((side * .440, side * .419))
        area = rect(1604, 30 + 612 * index, 50, 597)
        rail_texture(area, .254, .021, "side", 3.1 + index)
        grid(area, .254, .021, lambda ua, ub, x0=x0, x1=x1: dash_point(x0 + (x1 - x0) * ub, -.127 + .254 * ua, .034), 3, 24)
    n = 0
    rails_to = len(FACES)
    for side in (-1, 1):                                            # the throttle slots' outer rails
        for edge in (-1, 1):
            x = side * .46 + edge * .034
            area = rect(1668 + 48 * (n // 3), 30 + 640 * (n % 3), 36, 628)
            rail_texture(area, .267, .015, "slot", 2.3 * n)
            grid(area, .267, .015, lambda ua, ub, x=x: (x + (ub - .5) * .015, .1435, .337 - .267 * ua), 2, 12)
            n += 1
    with tempfile.TemporaryDirectory() as tmp:
        folder = Path(tmp)
        for name, image in (("BezelHD_Base", BASE), ("BezelHD_Normal", NORMAL), ("BezelHD_ORM", ORM)):
            png(folder / (name + ".png"), image)
        material = pbr(folder, "BezelHD")
        # The frame rails round the flat instrument panel are their own mesh: the gauge cluster
        # (vr/gauge_cluster.gd) stands where they were, and the game leaves them out with it.
        frame = set(range(rails_from, rails_to))
        for name, keep in (("Bezel", [k for k in range(len(FACES)) if k not in frame]), ("InstrumentRails", sorted(frame))):
            used = sorted({i for k in keep for i in FACES[k]})
            index = {old: new for new, old in enumerate(used)}
            faces = [tuple(index[i] for i in FACES[k]) for k in keep]
            mesh = bpy.data.meshes.new(name)
            mesh.from_pydata([XYZ[i] for i in used], [], faces)
            mesh.uv_layers.new(name="BezelUV").data.foreach_set("uv", np.array([UV[i] for k in keep for i in FACES[k]], f32).ravel())
            mesh.polygons.foreach_set("use_smooth", np.array([SMOOTH[k] for k in keep], bool))
            mesh.materials.append(material)
            bm = bmesh.new()                                      # the exporter needs triangles or quads for tangents
            bm.from_mesh(mesh)
            bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 4])
            bm.to_mesh(mesh)
            bm.free()
            mesh.update()
            bpy.context.collection.objects.link(bpy.data.objects.new(name, mesh))
            print("MESH", name, len(used), "vertices", sum(len(f) - 2 for f in faces), "triangles", flush=True)
        bpy.ops.export_scene.gltf(filepath=str(OUTPUT), export_tangents=True, export_animations=False,
                                  export_cameras=False, export_lights=False)
    print("Wrote", OUTPUT, OUTPUT.stat().st_size, "bytes")


if __name__ == "__main__":
    main()
