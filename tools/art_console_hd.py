"""Realism spike: the two side consoles and their switchgear.

    blender --background --python tools/art_console_hd.py [-- --res 2048]

Same envelope and positions as cockpit_interior.gd's code-built consoles: a housing beside each
lever, a faceplate, three guarded toggles and two knobs. Housing edges, the plate's chamfer,
hex nuts, bat levers, tube guards and knob skirts are geometry; coating, engraving, knurl,
wear and fasteners are synthesised in surface metres. The port console is the mirror of the
starboard one. Legends, placards and the indicator lenses stay with the game's own code.
"""
import math
import sys
import tempfile
from pathlib import Path

import bmesh
import bpy
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import art_bezel_hd as kit  # noqa: E402  atlas, patches and the shared maps
from art_coaming_hd import f32, fbm, mix, png, smooth, vnoise  # noqa: E402
from art_grip_hd import pbr  # noqa: E402

OUTPUT = Path(__file__).resolve().parents[1] / "godot/art/cockpit/console_hd.glb"
CX, FACE_Y, MID_Z = .615, .386, .435                              # starboard console, rig metres
TOGGLES, KNOBS = (.28, .42, .56), (.70, .835)
PLATE_W, PLATE_L = .112, .86
sp = lambda t, e: np.sign(t) * np.abs(t)**e


def patch(area, length, width, points, along, across, smooth_faces=True):
    """points[row][col] in rig metres; rows run `along` metres, columns `across` metres."""
    rows, cols = points.shape[:2]
    uvs = [kit.uv_of(area, length, width, float(along[j]), float(across[i])) for j in range(rows) for i in range(cols)]
    faces = [(j * cols + i, j * cols + i + 1, (j + 1) * cols + i + 1, (j + 1) * cols + i) for j in range(rows - 1) for i in range(cols - 1)]
    kit.add([tuple(p) for p in points.reshape(-1, 3)], uvs, faces, smooth_faces)


def lathe(area, profile, around, base, flat=False, tilt=0.0):
    """Turn (radius, height) pairs round the vertical at `base`, optionally leaning toward -z."""
    prof = np.array(profile, float)
    arc = np.concatenate([[0], np.cumsum(np.hypot(np.diff(prof[:, 0]), np.diff(prof[:, 1])))])
    girth = 2 * math.pi * prof[:, 0].max()
    phi = np.linspace(0, 2 * math.pi, around + 1)
    x, y, z = prof[:, :1] * np.cos(phi), prof[:, 1:] + 0 * phi, -prof[:, :1] * np.sin(phi)
    y, z = y * math.cos(tilt) - z * math.sin(tilt), y * math.sin(tilt) + z * math.cos(tilt)
    patch(area, arc[-1], girth, np.stack([x + base[0], y + base[1], z + base[2]], -1), arc, phi / (2 * math.pi) * girth, not flat)
    return arc[-1], girth


def tube(area, path, radius, x):
    """Sweep a round tube along (z, y) points in the plane x = const."""
    path = np.array(path, float)
    tangent = np.gradient(path, axis=0)
    tangent /= np.linalg.norm(tangent, axis=1, keepdims=True)
    arc = np.concatenate([[0], np.cumsum(np.hypot(*np.diff(path, axis=0).T))])
    psi = np.linspace(0, 2 * math.pi, 11)
    # n1 = +x; n2 = t x n1 lies in the path's plane. (n1, n2, t) is right-handed.
    n2z, n2y = -tangent[:, 1:], tangent[:, :1]
    px = x + radius * np.cos(psi) + 0 * n2z
    py = path[:, 1:] + radius * np.sin(psi) * n2y
    pz = path[:, :1] + radius * np.sin(psi) * n2z
    patch(area, arc[-1], 2 * math.pi * radius, np.stack([px, py, pz], -1), arc, psi * radius)
    return arc[-1], 2 * math.pi * radius


def paint_small(area, length, width, kind):
    a, b, where = kit.window(area, length, width)
    a, b = np.broadcast_arrays(a, b)
    grit, streak = fbm(b * 9000, a * 9000, 2), vnoise(b * 300, a * 9000)
    foot = .6 + .4 * smooth(a / .003)                                # shade where the part meets the plate
    h, metal = (grit - .5) * 3e-6, np.ones_like(a)
    if kind == "chrome":
        col, rough = np.full(a.shape + (3,), 214.0) + (streak[..., None] - .5) * 8, .16 + (streak - .5) * .08
    elif kind == "zinc":
        col, rough = np.full(a.shape + (3,), 168.0) + (streak[..., None] - .5) * 22, .36 + (streak - .5) * .14
    elif kind == "boot":
        col, rough, metal = np.full(a.shape + (3,), 20.0) + (grit[..., None] - .5) * 8, np.full(a.shape, .7, f32), 0 * a
    elif kind == "guard":                                             # red enamel, chipped where fingers catch it
        chip = smooth((fbm(b * 2500, a * 900, 3) + .35 * np.exp(-np.abs(a - length / 2) / .012) - .98) * 14)
        col = mix(np.array((152, 24, 16), f32) * (.9 + .2 * fbm(b * 60, a * 60)[..., None]), (176, 178, 181), chip)
        rough, metal = .34 + .2 * chip + (grit - .5) * .06, chip
    else:                                                             # knob: metal skirt, straight-knurled body, capped
        body = (a > .0048) & (a < length - .018)
        cap = a > length - .0165
        ridge = np.cos(2 * math.pi * b / .0019) * .5 + .5
        pointer = (np.abs(b - width / 2) < .0011) & (a > length - .03)
        col = np.where(body[..., None], 22.0 + 10 * ridge[..., None], 150.0 + (streak[..., None] - .5) * 20)
        col = np.where(pointer[..., None], 226.0, col)
        h = np.where(body, .00035 * ridge, h) + 6e-5 * pointer
        rough = np.where(body, .62, .3 + (streak - .5) * .1)
        metal = np.where(body | pointer, 0.0, 1.0) * np.where(cap | ~body, 1, 0)
        foot = foot * np.where(body, .72 + .28 * ridge, 1)
    kit.commit(area, length, width, where, col.astype(f32), h.astype(f32), rough.astype(f32), metal.astype(f32), foot.astype(f32))


def paint_plate(area):
    a, b, where = kit.window(area, PLATE_L, PLATE_W)
    a, b = np.broadcast_arrays(a, b)
    z, x = a + (MID_Z - PLATE_L / 2), b - PLATE_W / 2                  # rig z, and metres off the console's centreline
    grit = fbm(x * 5200, z * 5200, 2)
    edge = np.minimum(np.minimum(a, PLATE_L - a), np.minimum(b, PLATE_W - b))
    # The slab's side walls take their colour from the plate's rim texels, so the wear starts
    # just inside the rim: a noisy rim smears down the side as a barcode.
    bright = smooth((fbm(x * 400, z * 160) + .7 * np.exp(-edge / .0007) - 1.1) * 9) * smooth((edge - .0004) / .0005)
    col = mix(np.array((17, 19, 22), f32) + (grit[..., None] - .5) * 7, (184, 187, 191), bright)
    # Dyed anodising is mostly oxide: it reads as a dark dielectric, with bare metal only where it is worn.
    h, rough, metal = (grit - .5) * 9e-6, .64 - .22 * bright, (.2 + .75 * bright).astype(f32)
    ao = np.ones_like(a)
    fill = np.zeros(a.shape, bool)
    for zc in TOGGLES:                                                # an engraved ring round each toggle, paint-filled
        r = np.hypot(x, z - zc)
        fill |= np.abs(r - .0162) < .0005
        ao *= 1 - .5 * np.exp(-np.clip(r - .0118, 0, None) / .003)
        for gx in (-.024, .024):                                      # ... and the guards' feet
            for gz in (-.02, .02):
                ao *= 1 - .5 * np.exp(-np.clip(np.hypot(x - gx, z - zc - gz) - .0024, 0, None) / .002)
    for zc in KNOBS:                                                  # seven index marks round each knob
        r, bearing = np.hypot(x, z - zc), np.degrees(np.arctan2(x, -(z - zc)))
        tick = np.abs((bearing + 135 + 22.5) % 45 - 22.5) * np.radians(1) * r < .0007
        fill |= tick & (r > .0255) & (r < .0295) & (np.abs(bearing) < 140)
        ao *= 1 - .5 * np.exp(-np.clip(r - .022, 0, None) / .004)
    col = np.where(fill[..., None], np.array((196, 197, 190), f32), col)
    h, rough, metal = h - 5e-5 * fill, np.where(fill, .55, rough), np.where(fill, 0, metal)
    for sx in (-.043, .043):
        for sz in (.026, .844):
            col, h, rough, metal = kit.screw(x, z, (sx, sz), .003, col, h, rough, metal)
    kit.commit(area, PLATE_L, PLATE_W, where, col, h, rough, metal, ao)


def paint_body(area, length, girth):
    a, b, where = kit.window(area, length, girth)
    a, b = np.broadcast_arrays(a, b)
    phi = b / girth * 2 * math.pi                                     # 0 inboard... wait for the mesh: 0 = +x
    up = np.sin(phi)
    pebble = fbm(b * 2400, a * 2400, 2)
    corner = np.minimum(np.abs(phi - math.pi / 4), np.abs(phi - 3 * math.pi / 4)) * .09   # metres from a top edge, roughly
    worn = smooth((fbm(b * 300, a * 300, 3) + .45 * np.exp(-corner / .0025) - 1.1) * 8)   # only the top edges, and only in places
    scuff = smooth((fbm(b * 30, a * 14) - .62) * 7) * (up < .7)
    col = mix(np.array((31, 33, 38), f32) * (.9 + .2 * pebble[..., None]), (112, 116, 122), .6 * worn)
    col = mix(col, (58, 60, 64), .5 * scuff)
    h = (pebble - .5) * 3e-5 * (1 - worn)
    rough = .74 - .22 * worn - .14 * scuff + (pebble - .5) * .06
    seam = np.abs(up + .55) < .012                                    # the housing's lower shell line
    h, col = h - 4e-4 * seam, col * np.where(seam, .5, 1)[..., None]
    ao = (.5 + .5 * smooth((up + 1.05) / .7)) * (.75 + .25 * smooth(np.minimum(a, length - a) / .02))
    kit.commit(area, length, girth, where, col, h, rough, .15 + .75 * worn, ao)


def build():
    # housing: a rounded section run fore and aft, closed at both ends
    phi = np.linspace(0, 2 * math.pi, 49)
    section = np.stack([CX + .065 * sp(np.cos(phi), 2 / 9), .24 + .13 * sp(np.sin(phi), 2 / 9)], -1)
    girth = np.concatenate([[0], np.cumsum(np.hypot(*np.diff(section, axis=0).T))])
    zs = np.linspace(-.055, .895, 13)
    body = kit.rect(8, 20, 1180, 1960)
    points = np.stack([section[None, :, 0] + 0 * zs[:, None], section[None, :, 1] + 0 * zs[:, None], zs[:, None] + 0 * phi[None, :]], -1)
    patch(body, .95, girth[-1], points, zs + .055, girth)
    for z, order in ((-.055, -1), (.895, 1)):
        ring = [(float(sx), float(sy), z) for sx, sy in section[:-1]][::order]
        kit.add(ring, [kit.uv_of(body, .95, girth[-1], .01, .01)] * len(ring), [tuple(range(len(ring)))], False)
    paint_body(body, .95, girth[-1])

    # faceplate: a chamfered slab on the housing's top
    plate = kit.rect(1204, 20, 268, 1960)
    hw, hl, c, bevel = PLATE_W / 2, PLATE_L / 2, .005, .001
    def ring(inset, y):
        w, l, cc = hw - inset, hl - inset, c - inset * (2 - math.sqrt(2))
        outline = [(w, l - cc), (w - cc, l), (-w + cc, l), (-w, l - cc), (-w, -l + cc), (-w + cc, -l), (w - cc, -l), (w, -l + cc)]
        return [(CX + x, y, MID_Z - z) for x, z in outline]
    rings = ring(bevel, FACE_Y) + ring(0, FACE_Y - bevel) + ring(0, FACE_Y - .012)
    faces = [tuple(range(8))] + [(k * 8 + i, (k + 1) * 8 + i, (k + 1) * 8 + (i + 1) % 8, k * 8 + (i + 1) % 8) for k in (0, 1) for i in range(8)]
    kit.add(rings, [kit.uv_of(plate, PLATE_L, PLATE_W, z - (MID_Z - hl), x - CX + hw) for x, _, z in rings], faces, False)
    paint_plate(plate)

    # switchgear: every toggle shares one set of maps, as does every knob
    nut, boot, lever, guard, knob = (kit.rect(1490, y, w, h) for y, w, h in ((20, 160, 48), (80, 96, 48), (140, 64, 128), (280, 40, 330), (630, 360, 170)))
    sizes = {}
    for zc in TOGGLES:
        at = (CX, FACE_Y, zc)
        sizes[nut] = lathe(nut, [(.0118, 0), (.0118, .0036), (.0102, .0046), (.0062, .0046)], 6, at, flat=True)
        sizes[boot] = lathe(boot, [(.0062, .0046), (.0062, .0085), (.0048, .0095), (.0036, .0095)], 16, at)
        sizes[lever] = lathe(lever, [(.0030, 0), (.0030, .004), (.0036, .014), (.0044, .024), (.0046, .029), (.0038, .0325), (.0018, .0345), (.0002, .035)],
                             16, (CX, FACE_Y + .009, zc), tilt=-.3)
        for side in (-1, 1):
            r, top = .008, FACE_Y + .036
            arc = [(math.sin(t), math.cos(t)) for t in np.linspace(0, math.pi / 2, 7)]
            path = [(zc - .02, FACE_Y + y) for y in np.linspace(0, .036 - r, 5)[:-1]]
            path += [(zc - .02 + r * (1 - c), top - r + r * s) for s, c in arc]
            path += [(zc + .02 - r * (1 - c), top - r + r * s) for s, c in arc[::-1]]
            path += [(zc + .02, FACE_Y + y) for y in np.linspace(.036 - r, 0, 5)[1:]]
            sizes[guard] = tube(guard, path, .0024, CX + side * .024)
    for zc in KNOBS:
        sizes[knob] = lathe(knob, [(.022, 0), (.022, .0016), (.0195, .0026), (.0188, .003), (.0185, .0032), (.0185, .024), (.0172, .0258),
                                   (.0148, .0262), (.0148, .027), (.0002, .0272)], 40, (CX, FACE_Y, zc))
    for area, kind in ((nut, "zinc"), (boot, "boot"), (lever, "chrome"), (guard, "guard"), (knob, "knob")):
        paint_small(area, sizes[area][0], sizes[area][1], kind)


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    build()
    with tempfile.TemporaryDirectory() as tmp:
        folder = Path(tmp)
        for name, image in (("ConsoleHD_Base", kit.BASE), ("ConsoleHD_Normal", kit.NORMAL), ("ConsoleHD_ORM", kit.ORM)):
            png(folder / (name + ".png"), image)
        material = pbr(folder, "ConsoleHD")
        loop_uv = np.array([kit.UV[i] for face in kit.FACES for i in face], f32)
        for name, flip in (("ConsoleR", False), ("ConsoleL", True)):
            xyz = [(-x, y, z) for x, y, z in kit.XYZ] if flip else kit.XYZ      # Blender x is the rig's x
            faces = [tuple(reversed(f)) for f in kit.FACES] if flip else kit.FACES
            mesh = bpy.data.meshes.new(name)
            mesh.from_pydata(xyz, [], faces)
            uv = np.array([kit.UV[i] for face in faces for i in face], f32) if flip else loop_uv
            mesh.uv_layers.new(name="ConsoleUV").data.foreach_set("uv", uv.ravel())
            mesh.polygons.foreach_set("use_smooth", np.array(kit.SMOOTH, bool))
            mesh.materials.append(material)
            bm = bmesh.new()
            bm.from_mesh(mesh)
            bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 4])
            bm.to_mesh(mesh)
            bm.free()
            mesh.update()
            bpy.context.collection.objects.link(bpy.data.objects.new(name, mesh))
        print("MESH", len(kit.XYZ), "vertices each", sum(len(f) - 2 for f in kit.FACES), "triangles each", flush=True)
        bpy.ops.export_scene.gltf(filepath=str(OUTPUT), export_tangents=True, export_animations=False,
                                  export_cameras=False, export_lights=False)
    print("Wrote", OUTPUT, OUTPUT.stat().st_size, "bytes")


if __name__ == "__main__":
    main()
