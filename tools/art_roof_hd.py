"""Realism spike: a roof for the cockpit (Luke, after flying it: "I think the vehicle needs to
have a roof. I know that kills the name phaeton, but I think it's necessary to the immersion").

    blender --background --python tools/art_roof_hd.py [-- --res 2048] [-- --samples 64]

A closed canopy standing on the cockpit's rim, in the rig's frame like the other fittings (forward
-Z, y up from the rig's floor, the hull's centre 0.6 above it; the seated eye is at (0, 0.72, 0.6)).
Swept back (Luke, seeing the first one stand upright: "I think it should be swept back pretty
significantly"): the screen leaves the rim's nose and lies back some 70 degrees from vertical to a
header over the pilot's brow, its pillars with it, and the roof falls away behind the head.
  header     a leather-wrapped rail across the top of the windscreen, 0.3 m ahead of the eye and
             0.35 m over it (about 50 degrees up: the road ahead and the sky over it are all glass)
  pillars    an A-pillar each side, its foot well forward on the rim and its top back at the header's
             corner (65 degrees from vertical); a raked B-pillar behind the shoulders
  rails      a short cant rail each side from the header back over the head to the B-pillars
  roof       a crowned shell between them: Alcantara inside (0.36 m over the eye), quilted in padded
             diamonds and stitched in the cockpit's orange thread; carbon weave under lacquer outside
  cowl       the same shell carried down behind the head to the rear of the rim
  glass      the shade band along the top of the windscreen and of each side window: a separate mesh
             ("RoofGlass", u across and v down the pane in its UVs) that the game gives its own material.
             Only the band: a whole pane of clear glass cost the headset 0.7 ms a frame to draw nothing
             you could see (it is blended at four samples a pixel over the whole view)
Forms are geometry; grain, nap, weave and stitching are synthesised in surface metres, and the
occlusion is path traced over the finished shapes. Writes godot/art/cockpit/roof_hd.glb.
"""
import math
import sys
import tempfile
from pathlib import Path

import bpy
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import art_bezel_hd as kit  # noqa: E402  the atlas and its helpers
from art_cockpit import hull_top  # noqa: E402  the game's own hull stations
from art_coaming_hd import ARGS, box, f32, fbm, png, smooth, vnoise  # noqa: E402
from art_gauges_hd import LEATHER, THREAD, Part, bake, grain  # noqa: E402
from art_grip_hd import pbr  # noqa: E402

OUTPUT = Path(__file__).resolve().parents[1] / "godot/art/cockpit/roof_hd.glb"
SAMPLES = int(ARGS[ARGS.index("--samples") + 1]) if "--samples" in ARGS else 64
BAKE = kit.RES // 2
UP = .6                                       # the pod's centre above the rig's floor (CraftModel.POD_FRAME_UP)
EYE = np.array((0.0, UP + .12, .6))
CABIN = np.array((0.0, UP + .16, .45))        # what "inward" means for a rail's section
SUEDE = np.array((76, 74, 77), f32)            # anthracite, not black: it faces down, away from every light (at 33 it rendered as a void)


# ---- the lines the canopy is hung on (Godot metres, pod frame) ----
def foot(deg):
    """On top of the coaming, round the opening: 0 degrees is the right side, -90 the nose."""
    ph = math.radians(deg)
    x, z = .72 * math.cos(ph), .15 + 1.15 * math.sin(ph)
    return np.array((x, hull_top(x, z) + .052, z))


A_DEG, B_DEG = 50.0, 30.0        # the pillars' feet: degrees round the rim from the nose, and aft of abeam
HEAD_Z, HEAD_BOW = .30, .14      # the header: its middle this far aft of the opening's centre line (the eye is at .6), its corners further
TAIL_Z = 1.08                    # the roof's rear edge at the B-pillars' tops
GLASS_FROM = .74                 # the glass mesh starts this far up each pane (roof_glass.gdshader fades in from there)


def header(w):
    """Across the top of the windscreen, w -1 (left) .. 1 (right): bowed forward and up in the middle."""
    return np.array((.41 * w, UP + .47 - .035 * w * w, HEAD_Z + HEAD_BOW * w * w))


def rail(side, t):
    """A cant rail, t 0 at the header's corner .. 1 at the B-pillar's top: highest by the head, falling aft."""
    return np.array((side * (.41 + .05 * math.sin(math.pi * t)), UP + .435 + .12 * t * (1 - t) - .05 * t,
                     HEAD_Z + HEAD_BOW + (TAIL_Z - HEAD_Z - HEAD_BOW) * t))


def roof(t, w):
    """The roof's middle surface: t header .. rear, w across."""
    edge = rail(1.0, t)
    front, back = HEAD_Z + HEAD_BOW * w * w, TAIL_Z + .08 * (1 - w * w)
    return np.array((w * edge[0], edge[1] + (.035 + .07 * t * (1 - t)) * (1 - w * w), front + (back - front) * t))


def screen(u, v):
    """The windscreen: u across (left .. right), v from the rim up to the header, blown out a little."""
    base, top = foot(-90 - A_DEG + 2 * A_DEG * u), header(2 * u - 1)
    p = base + (top - base) * v
    out = np.array((p[0], .9, p[2] - .15))
    return p + out / np.linalg.norm(out) * .045 * math.sin(math.pi * v)


def side_window(side, t, v):
    """A side window: t from the A-pillar back to the B-pillar, v from the rim up to the cant rail."""
    deg = (-90 + A_DEG + (90 - A_DEG + B_DEG) * t) if side > 0 else (-90 - A_DEG - (90 - A_DEG + B_DEG) * t)
    base, top = foot(deg), rail(side, t)
    p = base + (top - base) * v
    return p + np.array((side, .25, 0.0)) / math.hypot(1, .25) * .022 * math.sin(math.pi * v) * math.sin(math.pi * min(max(t, .02), .98))


def cowl(q, v):
    """Behind the head: q round the back from the right B-pillar to the left, v from the rim up to the roof's rear edge."""
    base, top = foot(B_DEG + (180 - 2 * B_DEG) * q), roof(1.0, 1 - 2 * q)
    p = base + (top - base) * v
    out = np.array((p[0], .2, p[2] - .3))
    return p + out / np.linalg.norm(out) * .05 * math.sin(math.pi * v)


def arc_length(points):
    return np.concatenate([[0], np.cumsum(np.linalg.norm(np.diff(points, axis=0), axis=1))])


# ---- paint ----
def stitches(a, row, pitch=.006):
    """A row of top-stitching running along `a`, `row` metres off it: -> (thread mask, height, dimple)."""
    phase = a / pitch
    along = (phase - np.floor(phase) - .5) * pitch
    q = np.hypot(np.clip(np.abs(along) - .0017, 0, None), row) / .0006
    thread = q < 1
    h = -.0004 * np.exp(-(row / .0013)**2) + np.where(thread, .0005 * np.sqrt(np.clip(1 - q * q, 0, 1)), 0)
    return thread, h


def paint_suede(area, length, width, seams):
    """Alcantara: a fine nap brushed this way and that, with stitched seams running fore and aft."""
    a, b, where = kit.window(area, length, width)
    a, b = np.broadcast_arrays(a, b)
    nap = fbm(b * 2600, a * 2600, 2)
    brushed = smooth((fbm(b * 9 + 3, a * 6, 3) - .5) * 3 + .5)              # where a hand has stroked it
    col = SUEDE * (.86 + .22 * nap[..., None]) * (.95 + .1 * brushed[..., None])
    h, rough = (nap - .5) * 3.5e-5, .93 + (nap - .5) * .06
    ao = np.ones_like(nap)
    for at in seams:
        d = b - at
        groove = np.exp(-(d / .0016)**2)
        h = h - .0009 * groove
        ao = ao * (1 - .45 * groove)
        for off in (-.0045, .0045):
            thread, lift = stitches(a, d - off)
            h = h + lift
            col = np.where(thread[..., None], THREAD * (.85 + .15 * np.cos(2 * math.pi * a / .00045))[..., None], col)
            rough = np.where(thread, .7, rough)
    kit.commit(area, length, width, where, col, h, rough, np.zeros_like(nap), ao)


def paint_quilt(area, length, width, pitch=.082, border=.04):
    """The headliner (Luke, after flying under the plain one: "add a bit of texture to the ceiling to
    match the rest of the stitching quality"): Alcantara quilted in diamonds, each one padded and
    drawn down into its seams, every seam a row of the cockpit's orange thread; a plain border round
    the field, closed by a double row of the same stitching. The padding's shade is painted into the
    colour as well as the relief: the headliner faces down and is lit mostly by its own glow, which
    shows colour and hides relief."""
    a, b, where = kit.window(area, length, width)
    a, b = np.broadcast_arrays(a, b)
    nap = fbm(b * 2600, a * 2600, 2)
    brushed = smooth((fbm(b * 9 + 3, a * 6, 3) - .5) * 3 + .5)              # where a hand has stroked it
    col = SUEDE * (.86 + .22 * nap[..., None]) * (.95 + .1 * brushed[..., None])
    h, rough = (nap - .5) * 3.5e-5, .93 + (nap - .5) * .06
    ao = np.ones_like(nap)
    edge = np.minimum(np.minimum(a, length - a), np.minimum(b, width - b))    # to the nearest edge of the panel
    field = smooth((edge - border) / .003)                                   # 1 inside the border
    d1, d2 = (a + b) / math.sqrt(2), (a - b) / math.sqrt(2)
    puff = np.sqrt(np.abs(np.sin(math.pi * d1 / pitch)) * np.abs(np.sin(math.pi * d2 / pitch)))
    h = h + field * .0034 * puff
    col = col * (1 - .3 * field[..., None] * (1 - puff[..., None])**1.5)
    ao = ao * (1 - .4 * field * (1 - puff)**2)
    for along, across in ((d2, d1), (d1, d2)):
        row = (across + pitch / 2) % pitch - pitch / 2
        h = h - .0008 * field * np.exp(-(row / .0015)**2)
        thread, lift = stitches(along, row)
        thread = thread & (field > .5)
        h = h + np.where(field > .5, lift, 0)
        col = np.where(thread[..., None], THREAD * (.85 + .15 * np.cos(2 * math.pi * along / .00045))[..., None], col)
        rough = np.where(thread, .7, rough)
    # the border's seam, and its two rows of stitching, running round the field
    along = np.where(np.minimum(b, width - b) < np.minimum(a, length - a), a, b)
    d = edge - border
    groove = np.exp(-(d / .0016)**2)
    h = h - .0009 * groove
    ao = ao * (1 - .45 * groove)
    col = col * (1 - .25 * groove[..., None])
    for off in (-.0045, .0045):
        thread, lift = stitches(along, d - off)
        h = h + lift
        col = np.where(thread[..., None], THREAD * (.85 + .15 * np.cos(2 * math.pi * along / .00045))[..., None], col)
        rough = np.where(thread, .7, rough)
    kit.commit(area, length, width, where, col, h, rough, np.zeros_like(nap), ao)


def paint_carbon(area, length, width):
    """Two-by-two twill under lacquer."""
    a, b, where = kit.window(area, length, width)
    a, b = np.broadcast_arrays(a, b)
    tow = .0024
    u, v = a / tow, b / tow
    iu, iv = np.floor(u).astype(np.int32), np.floor(v).astype(np.int32)
    warp = ((iu + iv) % 4) < 2
    fu, fv = u - iu, v - iv
    sheen = np.where(warp, .5 + .5 * np.cos(math.pi * (fv - .5) * 1.6), .5 + .5 * np.cos(math.pi * (fu - .5) * 1.6))
    fibre = vnoise(np.where(warp, u * 9, v * 9), np.where(warp, v * 60, u * 60))
    col = (17 + 30 * sheen * np.where(warp, .7, 1.0) + (fibre - .5) * 7)[..., None] * np.array((1, 1, 1.04), f32)
    dust = fbm(b * 40, a * 40)
    kit.commit(area, length, width, where, col, (sheen - .5) * 4e-6, .16 + .08 * smooth((dust - .55) * 6), np.zeros_like(sheen), np.ones_like(sheen))


def paint_leather(area, length, girth, seam_at):
    """A leather-wrapped rail: pebbled grain, its seam stitched along one side."""
    a, b, where = kit.window(area, length, girth)
    a, b = np.broadcast_arrays(a, b)
    peb = grain(b, a)
    col = LEATHER * (.84 + .22 * peb[..., None])
    h, rough = (peb - 1) * 5e-5, .58 + .14 * (1 - peb)
    d = b - seam_at * girth
    h = h - .0006 * np.exp(-(d / .0012)**2)
    for off in (-.004, .004):
        thread, lift = stitches(a, d - off)
        h = h + lift
        col = np.where(thread[..., None], THREAD * (.85 + .15 * np.cos(2 * math.pi * a / .00045))[..., None], col)
        rough = np.where(thread, .72, rough)
    kit.commit(area, length, girth, where, col, h, rough, np.zeros_like(peb), np.ones_like(peb))


# ---- forms ----
def tube(part, area, curve, ra, rb, around=14):
    """A leather-wrapped rail along `curve`: ra is its half depth toward the cabin, rb its half width."""
    curve = np.asarray(curve, float)
    tangent = np.gradient(curve, axis=0)
    tangent /= np.linalg.norm(tangent, axis=1, keepdims=True)
    inward = CABIN - curve
    inward -= tangent * np.sum(inward * tangent, axis=1, keepdims=True)
    inward /= np.linalg.norm(inward, axis=1, keepdims=True)
    side = np.cross(tangent, inward)
    phi = np.linspace(0, 2 * math.pi, around + 1)
    points = curve[:, None, :] + ra * np.cos(phi)[None, :, None] * inward[:, None, :] + rb * np.sin(phi)[None, :, None] * side[:, None, :]
    length = arc_length(curve)
    girth = 2 * math.pi * math.sqrt((ra * ra + rb * rb) / 2)
    j, i = min(len(curve) // 2, len(curve) - 2), min((around + 1) // 2, around - 1)
    part.patch(area, float(length[-1]), girth, points, length, phi / (2 * math.pi) * girth, points[j, i] - curve[j])
    paint_leather(area, float(length[-1]), girth, 1 / 14)        # the seam just round from the cabin's side
    return float(length[-1])


def shell(part, inner_area, outer_area, surface, nt, nw, paint_inner, thick=(.014, .009)):
    """A skin both sides of a middle surface(t, w): the cabin's side `thick[0]` in from it, the outside `thick[1]` out."""
    ts, ws = np.linspace(0, 1, nt), np.linspace(-1, 1, nw) if surface is roof else np.linspace(0, 1, nw)
    mid = np.array([[surface(t, w) for w in ws] for t in ts])
    dt, dw = np.gradient(mid, axis=0), np.gradient(mid, axis=1)
    normal = np.cross(dw, dt)
    normal /= np.linalg.norm(normal, axis=2, keepdims=True)
    normal *= np.sign(np.sum(normal * (mid - EYE), axis=2, keepdims=True))      # out of the cabin
    along = arc_length(mid[:, nw // 2])
    across = arc_length(mid[nt // 2])
    inner, outer = mid - normal * thick[0], mid + normal * thick[1]
    part.patch(inner_area, float(along[-1]), float(across[-1]), inner, along, across, lambda p: EYE - p)
    part.patch(outer_area, float(along[-1]), float(across[-1]), outer, along, across, lambda p: p - EYE)
    paint_inner(inner_area, float(along[-1]), float(across[-1]))
    paint_carbon(outer_area, float(along[-1]), float(across[-1]))
    return float(along[-1]), float(across[-1])


def canopy():
    part, glass = Part("Roof"), Part("RoofGlass")
    # the roof and the cowl behind the head
    span = shell(part, kit.rect(16, 16, 1100, 860), kit.rect(16, 900, 1100, 500), roof, 33, 25,
                 paint_quilt)
    back = shell(part, kit.rect(1140, 16, 880, 300), kit.rect(1140, 330, 880, 200), lambda v, q: cowl(q, v), 9, 33,
                 lambda area, length, width: paint_quilt(area, length, width, border=.03))
    # the rails
    n = 41
    lengths = {}
    lengths["cant L"] = tube(part, kit.rect(1470, 560, 100, 620), [rail(-1, t) for t in np.linspace(0, 1, n)], .022, .017)
    lengths["cant R"] = tube(part, kit.rect(1580, 560, 100, 620), [rail(1, t) for t in np.linspace(0, 1, n)], .022, .017)
    lengths["header"] = tube(part, kit.rect(1360, 560, 100, 776), [header(w) for w in np.linspace(-1, 1, n)], .020, .016)
    rake = {}
    for k, side in enumerate((-1, 1)):
        base, top = foot(-90 - A_DEG if side < 0 else -90 + A_DEG), header(side)
        lengths["A %d" % side] = tube(part, kit.rect(1140 + 110 * k, 560, 100, 1016), [base + (top - base) * v for v in np.linspace(0, 1, 33)], .023, .017)
        rake["A"] = math.degrees(math.atan2(top[2] - base[2], top[1] - base[1]))
        base, top = foot(180 - B_DEG if side < 0 else B_DEG), rail(side, 1.0)
        lengths["B %d" % side] = tube(part, kit.rect(1690 + 110 * k, 560, 100, 460), [base + (top - base) * v for v in np.linspace(0, 1, 17)], .027, .020)
        rake["B"] = math.degrees(math.atan2(top[2] - base[2], top[1] - base[1]))
    nose, brow = foot(-90), header(0)
    rake["screen"] = math.degrees(math.atan2(brow[2] - nose[2], brow[1] - nose[1]))
    # the glass: its UVs are (u across, 1 - v up the pane), nothing in the atlas
    whole = (0, 0, kit.RES, kit.RES)
    us, vs = np.linspace(0, 1, 41), np.linspace(GLASS_FROM, 1, 5)
    glass.patch(whole, 1, 1, [[screen(u, v) for u in us] for v in vs], vs, us, lambda p: p - EYE)
    for side in (-1, 1):
        ts = np.linspace(0, 1, 25)
        glass.patch(whole, 1, 1, [[side_window(side, t, v) for t in ts] for v in vs], vs, ts, lambda p: p - EYE)
    print("ROOF", "roof %.2f x %.2f m, cowl %.2f x %.2f m, rails" % (span + back), {k: round(v, 2) for k, v in lengths.items()},
          "headroom over the eye %.3f m;" % (roof((EYE[2] - HEAD_Z) / (TAIL_Z + .08 - HEAD_Z), 0)[1] - .014 - EYE[1]),
          "lying back from vertical:", {k: round(v) for k, v in rake.items()},
          "the header %.2f m ahead of the eye, %.2f m over it" % (EYE[2] - brow[2], brow[1] - EYE[1]), flush=True)
    return part, glass


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    try:
        scene.render.engine = "CYCLES"
    except TypeError as error:
        raise SystemExit("Cycles is needed for the occlusion bake: %s" % error)
    scene.cycles.device = "CPU"
    scene.cycles.samples = SAMPLES
    scene.cycles.use_denoising = False
    scene.render.bake.margin = 3
    scene.world = bpy.data.worlds.new("BakeWorld")
    scene.world.light_settings.distance = .45

    image = bpy.data.images.new("Occlusion", BAKE, BAKE, alpha=True, is_data=True)
    image.pixels.foreach_set(np.tile(np.array((1, 1, 1, 0), f32), BAKE * BAKE))
    target = bpy.data.materials.new("BakeTarget")
    target.use_nodes = True
    node = target.node_tree.nodes.new("ShaderNodeTexImage")
    node.image = image
    target.node_tree.nodes.active = node

    part, glass = canopy()
    body = part.mesh(target)
    pane = glass.mesh(bpy.data.materials.new("RoofGlass"))
    bake([body], [pane], image, False)                                # (glass casts no shade)
    pixels = np.empty(BAKE * BAKE * 4, f32)
    image.pixels.foreach_get(pixels)
    pixels = pixels.reshape(BAKE, BAKE, 4)[::-1]                     # Blender's rows run bottom-up
    scale = kit.RES // BAKE
    lit = np.kron(np.where(pixels[..., 3] > .5, pixels[..., 0], 1.0), np.ones((scale, scale), f32))
    lit = np.clip(box(lit.astype(f32), 1, 1), 0, 1)
    print("BAKE", f"{(pixels[..., 3] > .5).mean() * 100:.0f}% of the atlas baked, occlusion {lit.min():.2f}-{lit.max():.2f}, mean {lit.mean():.2f}", flush=True)
    kit.BASE[:] = np.clip(kit.BASE * (.55 + .45 * lit[..., None]), 0, 255)
    kit.ORM[..., 0] = np.clip(kit.ORM[..., 0] * lit, 0, 255)

    with tempfile.TemporaryDirectory() as tmp:
        folder = Path(tmp)
        for name, pixels8 in (("RoofHD_Base", kit.BASE), ("RoofHD_Normal", kit.NORMAL), ("RoofHD_ORM", kit.ORM)):
            png(folder / (name + ".png"), pixels8)
        body.data.materials.clear()
        body.data.materials.append(pbr(folder, "RoofHD"))
        pane.hide_render = False
        bpy.ops.export_scene.gltf(filepath=str(OUTPUT), export_tangents=True, export_animations=False,
                                  export_cameras=False, export_lights=False)
    print("Wrote", OUTPUT, OUTPUT.stat().st_size, "bytes")


if __name__ == "__main__":
    main()
