"""Realism spike: the SPEEDCRAFT / STARFIGHTER mode switch on the starboard console.

    blender --background --python tools/art_mode_switch_hd.py -- --res 1024

Same envelope as mode_switch.gd's code-built panel: a housing with a faceplate, a hex nut and
boot, two tube guards, and the bat handle as its own mesh so the game can still swing it.
Built with the console's helpers in a frame where the face looks up, then turned so the face
looks along the switch's own +z. Lamps and legends stay with the game's code.
"""
import math
import sys
import tempfile
from pathlib import Path

import bmesh
import bpy
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import art_bezel_hd as kit  # noqa: E402
from art_coaming_hd import f32, fbm, mix, png, smooth  # noqa: E402
from art_console_hd import lathe, paint_small, tube  # noqa: E402
from art_grip_hd import pbr  # noqa: E402

OUTPUT = Path(__file__).resolve().parents[1] / "godot/art/cockpit/mode_switch_hd.glb"
PLATE_W, PLATE_L, TOP = .12, .15, .0015


def paint_plate(area):
    a, b, where = kit.window(area, PLATE_L, PLATE_W)
    a, b = np.broadcast_arrays(a, b)
    z, x = a - PLATE_L / 2, b - PLATE_W / 2
    grit = fbm(x * 5200, z * 5200, 2)
    edge = np.minimum(np.minimum(a, PLATE_L - a), np.minimum(b, PLATE_W - b))
    bright = smooth((fbm(x * 400, z * 400) + .7 * np.exp(-edge / .0007) - 1.1) * 9) * smooth((edge - .0004) / .0005)
    col = mix(np.array((17, 19, 22), f32) + (grit[..., None] - .5) * 7, (184, 187, 191), bright)
    h, rough, metal = (grit - .5) * 9e-6, .5 - .16 * bright, .25 + .7 * bright
    r = np.hypot(x, z)
    ring = np.abs(r - .0215) < .0006                               # engraved round the switch, paint-filled
    col = np.where(ring[..., None], np.array((196, 197, 190), f32), col)
    h, rough, metal = h - 5e-5 * ring, np.where(ring, .55, rough), np.where(ring, 0, metal)
    ao = 1 - .5 * np.exp(-np.clip(r - .017, 0, None) / .004)
    for lamp in (-.05, .05):                                        # the two lamp windows' recessed frames
        inside = np.maximum(np.abs(x) - .02, np.abs(z - lamp) - .0045)
        frame = (inside > 0) & (inside < .0012)
        col = np.where(frame[..., None], 150.0, col)
        h, rough, metal = h - 3e-4 * (inside <= 0), np.where(frame, .3, rough), np.where(frame, 1, metal)
        ao *= np.where(inside <= 0, .6, 1)
    for gx in (-.03, .03):                                          # shade round the guards' feet
        for gz in (-.043, .043):
            ao *= 1 - .5 * np.exp(-np.clip(np.hypot(x - gx, z - gz) - .0035, 0, None) / .003)
    for sx in (-.046, .046):
        for sz in (-.057, .057):
            col, h, rough, metal = kit.screw(x, z, (sx, sz), .003, col, h, rough, metal)
    kit.commit(area, PLATE_L, PLATE_W, where, col, h, rough, metal, ao)


def build():
    plate, nut, boot, guard, bat = (kit.rect(*r) for r in ((20, 20, 960, 1200), (1000, 20, 320, 96), (1000, 130, 192, 96),
                                                           (1000, 240, 80, 660), (1100, 240, 256, 700)))
    hw, hl, c, bevel = PLATE_W / 2, PLATE_L / 2, .006, .0012

    def ring(inset, y):
        w, l, cc = hw - inset, hl - inset, c - inset * (2 - math.sqrt(2))
        outline = [(w, l - cc), (w - cc, l), (-w + cc, l), (-w, l - cc), (-w, -l + cc), (-w + cc, -l), (w - cc, -l), (w, -l + cc)]
        return [(x, y, -z) for x, z in outline]
    rings = ring(bevel, TOP) + ring(0, TOP - bevel) + ring(0, -.035)
    faces = [tuple(range(8))] + [(k * 8 + i, (k + 1) * 8 + i, (k + 1) * 8 + (i + 1) % 8, k * 8 + (i + 1) % 8) for k in (0, 1) for i in range(8)]
    kit.add(rings, [kit.uv_of(plate, PLATE_L, PLATE_W, z + hl, x + hw) for x, _, z in rings], faces, False)
    paint_plate(plate)
    at = (0.0, TOP, 0.0)
    sizes = {nut: lathe(nut, [(.017, 0), (.017, .004), (.0135, .0058), (.008, .0058)], 6, at, flat=True),
             boot: lathe(boot, [(.008, .0058), (.008, .011), (.0065, .0125), (.0045, .0125)], 16, at)}
    for side in (-1, 1):
        r, top = .009, TOP + .0425
        arc = [(math.sin(t), math.cos(t)) for t in np.linspace(0, math.pi / 2, 7)]
        path = [(-.043, TOP + y) for y in np.linspace(0, .0425 - r, 5)[:-1]]
        path += [(-.043 + r * (1 - c2), top - r + r * s) for s, c2 in arc]
        path += [(.043 - r * (1 - c2), top - r + r * s) for s, c2 in arc[::-1]]
        path += [(.043, TOP + y) for y in np.linspace(.0425 - r, 0, 5)[1:]]
        sizes[guard] = tube(guard, path, .0035, side * .03)
    split = (len(kit.XYZ), len(kit.FACES))
    # The bat handle, about its own pivot: it leaves the face and swells to a rounded tip.
    sizes[bat] = lathe(bat, [(.0055, 0), (.006, .01), (.0075, .045), (.0095, .062), (.0105, .074), (.0095, .081), (.006, .0855), (.0004, .0865)],
                       20, (0.0, 0.0, 0.0))
    for area, kind in ((nut, "zinc"), (boot, "boot"), (guard, "guard"), (bat, "chrome")):
        paint_small(area, sizes[area][0], sizes[area][1], kind)
    return split


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    nv, nf = build()
    with tempfile.TemporaryDirectory() as tmp:
        folder = Path(tmp)
        for name, image in (("ModeSwitchHD_Base", kit.BASE), ("ModeSwitchHD_Normal", kit.NORMAL), ("ModeSwitchHD_ORM", kit.ORM)):
            png(folder / (name + ".png"), image)
        material = pbr(folder, "ModeSwitchHD")
        # Stored as (x, -z, up): turn about x so the face that looked up looks along the switch's +z.
        turned = [(x, -up, y) for x, y, up in kit.XYZ]
        for name, v0, v1, f0, f1 in (("Panel", 0, nv, 0, nf), ("Bat", nv, len(kit.XYZ), nf, len(kit.FACES))):
            faces = [tuple(i - v0 for i in f) for f in kit.FACES[f0:f1]]
            mesh = bpy.data.meshes.new(name)
            mesh.from_pydata(turned[v0:v1], [], faces)
            uv = np.array([kit.UV[i] for face in kit.FACES[f0:f1] for i in face], f32)
            mesh.uv_layers.new(name="SwitchUV").data.foreach_set("uv", uv.ravel())
            mesh.polygons.foreach_set("use_smooth", np.array(kit.SMOOTH[f0:f1], bool))
            mesh.materials.append(material)
            bm = bmesh.new()
            bm.from_mesh(mesh)
            bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 4])
            bm.to_mesh(mesh)
            bm.free()
            mesh.update()
            bpy.context.collection.objects.link(bpy.data.objects.new(name, mesh))
            print("MESH", name, v1 - v0, "vertices", flush=True)
        bpy.ops.export_scene.gltf(filepath=str(OUTPUT), export_tangents=True, export_animations=False,
                                  export_cameras=False, export_lights=False)
    print("Wrote", OUTPUT, OUTPUT.stat().st_size, "bytes")


if __name__ == "__main__":
    main()
