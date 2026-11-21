"""Realism spike: the seat's tub (Luke, after flying it: "please close up the sides by the pilot's
butt so that its more of a monocoque design").

    blender --background --python tools/art_tub_hd.py [-- --res 2048] [-- --samples 64]

The seat stood in the middle of the hull with a trench a quarter of a metre wide either side of
it, open down to the hull's floor, and behind each console the cabin was open to the hull's wall.
This closes them with one moulded panel a side, in the rig's frame like the other fittings (forward
-Z, y up from the rig's floor):
  hip panel   from under the cushion's bolster up in a hollow to the console's inner face, from the
              lever quadrant's rear back to the console's end; its front rolls down to the deck
  quarter     behind the console the same surface turns up into a wall, from the seat's flank to
              the underside of the cockpit's rim, and runs aft until the seat's back fills the
              opening; the rim light lies in a crease at the wall's waist
  side liner  a strip from the console's outer edge up to the rim: the slot over the console; and a
              small cap behind the console's end, where the liner's foot swings in onto the wall
  the bottom  (Luke, after flying the above: "i'd like to see the bottom of the tub fixed please".
              The panels stopped in the air: the hip's front lip hung 0.07 m over the hull's floor,
              with the hoses on the wall showing under it, and between the deck plate and the
              cushion a slot looked straight down to the hull.) A sill each side, from the hip
              panel's lip forward between the deck plate and the console to a lip of its own ahead
              of the console, slotted for the lever between its quadrant's rails; and an apron
              across the front of the seat, from under the deck plate's rear edge up under the
              cushion, turned up at its ends into the hip panels
Carbon twill under lacquer, with a padded leather insert at the hip, fluted fore and aft and
stitched in the cockpit's orange thread. Forms are geometry; weave, grain, flutes and stitching are
synthesised in surface metres; the occlusion is path traced with the seat, the consoles and the
deck standing in. Writes godot/art/cockpit/tub_hd.glb (one mesh, "Tub", both sides).
"""
import math
import sys
import tempfile
from pathlib import Path

import bpy
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import art_bezel_hd as kit  # noqa: E402  the atlas and its helpers
from art_cockpit import hull_floor, hull_top  # noqa: E402  the game's own hull stations (rig frame)
from art_coaming_hd import ARGS, box, f32, fbm, png, smooth, vnoise  # noqa: E402
from art_gauges_hd import LEATHER, THREAD, Part, bake, grain  # noqa: E402
from art_grip_hd import pbr  # noqa: E402
from art_roof_hd import arc_length, paint_carbon, stitches  # noqa: E402

OUTPUT = Path(__file__).resolve().parents[1] / "godot/art/cockpit/tub_hd.glb"
SAMPLES = int(ARGS[ARGS.index("--samples") + 1]) if "--samples" in ARGS else 64
BAKE = kit.RES // 2
EYE = np.array((0.0, .72, .6))
SEAT_X, SEAT_Y = .325, .205          # where the panel leaves the cushion's bolster (its flank ends at .32)
DECK = np.array((.43, .148))         # ... and where its front meets the deck plate's edge
CONSOLE_X, CONSOLE_Y = .552, .374    # the console's inner face, just under its top edge (.386)
CONSOLE_OUT = np.array((.672, .362)) # just inside the console's outer top edge (its corner is rounded: a liner standing on the edge itself left a slit under its foot)
Z0, Z1, ZC, ZE = .47, .60, .865, 1.135  # the front lip, the cushion's front, the console's aft end, the panel's aft end
LINER_Z = (.0, .915)                 # the side liner runs the console's length and closes onto the quarter wall behind it
SILL_Y = .112                        # the sill's height: under the deck plate's edge (.1175 to .1425) and a third of the way up the quadrant's plates (.09 to .14)
SILL_X = (.418, .556)                # from under the deck plate's edge to just inside the console's inner face
SILL_Z = (-.075, Z0 - .02)           # from its own lip ahead of the console's front (-.055) back to the hip panel's front lip
SLOT_X, SLOT_Z = (.441, .479), (.045, .355)   # the lever's slot, between the quadrant's rails and its end blocks
APRON_Z = (.540, .640)               # the apron: from under the deck plate's rear edge (.55) into the cushion's front (.60: it is .10 to .19 high there, and rounded)
APRON_Y = (.128, .186)               # ... rising from inside the plate's thickness to inside the cushion's, never over its top
APRON_AFT = .705                     # ... and on at that height under the bolsters' noses: they begin at .64 and are rounded, the cushion's flank falls away under them, and each left a pocket open to the hull


def rim(z):
    """The cockpit opening's edge at station z: (x, the hull's top there)."""
    x = .72 * math.sqrt(max(0.0, 1 - ((z - .15) / 1.15)**2))
    return x, hull_top(x, z)


def under_rim(z):
    """Where a panel meets the cockpit's rim: just inside the opening's edge, tucked under the lip
    that rolls round it (0.055 m in radius; test_cables holds every fitting clear of it)."""
    x_rim, top = rim(z)
    return np.array((max(x_rim - .01, SEAT_X + .022), top - .075))


def lerp(a, b, t):
    return a + (b - a) * t


def ease(t):
    t = min(max(t, 0.0), 1.0)
    return t * t * (3 - 2 * t)


def rim_light(z):
    """The rim light's line at station z (cockpit_interior.gd: 0.05 m inside the opening, 0.16 m
    under the hull's top)."""
    x = .67 * math.sqrt(max(0.0, 1 - ((z - .15) / 1.10)**2))
    return np.array((x, hull_top(x, z) - .16))


WAIST = .68                          # how far up the quarter wall its crease is: the rim light lies in it


def hip_edges(z):
    """The hip panel's inner and outer edges at station z, and how far aft of the console it is (0..1)."""
    f = ease((z - Z0) / (Z1 - Z0))                    # 0 at the front lip .. 1 from the cushion's front on
    g = ease((z - ZC) / .04)                          # 0 beside the console .. 1 aft of it
    inner = lerp(DECK, np.array((SEAT_X, SEAT_Y)), f)
    outer = lerp(np.array((CONSOLE_X, lerp(.21, CONSOLE_Y, f))), under_rim(z), g)
    if z < Z0:                                        # the lip rolls down onto the sill
        inner = inner - np.array((0, (DECK[1] - SILL_Y) * ease((Z0 - z) / .02)))
        outer = outer - np.array((0, (.21 - SILL_Y) * ease((Z0 - z) / .02)))
    return inner, outer, g


def hip(side, z, t):
    """The hip panel and the quarter behind it: t 0 at the seat .. 1 at the console (or, aft of it,
    under the rim). Beside the console it is one hollow. Behind it, a wall in two faces: a hollow
    up to the rim light's line, which lies in the crease, and a flatter face from there to the rim."""
    inner, outer, g = hip_edges(z)
    hollow = np.array((lerp(inner[0], outer[0], t), inner[1] + (outer[1] - inner[1]) * t**1.75))
    if g <= 0:
        return np.array((side * hollow[0], hollow[1], z))
    waist = rim_light(z) + np.array((.009, -.004))    # just behind the light and under it
    waist[0] = min(max(waist[0], SEAT_X + .012), outer[0] - .004)      # (aft, the light runs in behind the seat's back: the wall does not follow it)
    if t <= WAIST:
        s = t / WAIST
        wall = np.array((lerp(inner[0], waist[0], s), inner[1] + (waist[1] - inner[1]) * s**1.5))
    else:
        s = (t - WAIST) / (1 - WAIST)
        wall = np.array((lerp(waist[0], outer[0], s), waist[1] + (outer[1] - waist[1]) * s**.9))
    p = lerp(hollow, wall, g)
    return np.array((side * p[0], p[1], z))


def liner(side, z, t):
    """The side liner: t 0 on the console's outer top edge .. 1 under the rim. Behind the console's
    end its foot swings in onto the quarter wall's own edge, closing the corner between them."""
    foot = liner_foot(z)
    p = lerp(foot, under_rim(z), t)
    return np.array((side * (p[0] + .008 * math.sin(math.pi * t) * (1 - ease((z - ZC) / .045))), p[1], z))     # bowed a little outward


def liner_foot(z):
    return lerp(CONSOLE_OUT, hip_edges(z)[1], ease((z - ZC) / .045))


def cap(side, z, t):
    """Behind the console's end: from the quarter wall's edge (t 0) across to the liner's foot (1),
    over the corner the two leave between them while the liner's foot swings in."""
    p = lerp(hip_edges(z)[1], liner_foot(z), t)
    return np.array((side * p[0], p[1], z))


def sill_y(x, z):
    """The sill's height at (x, z): level, and rolled down ahead of the console to just clear of the
    hull's floor. (The floor rises outboard: a lip rolled down by one drop all the way across went
    through the trim at its outer end.)"""
    low = max(SILL_Y - .045, hull_floor(x, z, .035 + .013))
    return lerp(SILL_Y, low, ease((-.055 - z) / .02))


def sills(part, area):
    """Both sills: four pieces round the lever's slot, all on one painted rectangle of the atlas."""
    zs = np.unique(np.concatenate([np.linspace(SILL_Z[0], -.055, 6), np.linspace(-.055, SLOT_Z[0], 4), np.linspace(SLOT_Z[0], SLOT_Z[1], 9), np.linspace(SLOT_Z[1], SILL_Z[1], 5)]))
    xs = np.unique(np.concatenate([np.linspace(SILL_X[0], SLOT_X[0], 3), np.linspace(SLOT_X[0], SLOT_X[1], 3), np.linspace(SLOT_X[1], SILL_X[1], 5)]))
    ys = np.array([sill_y(SILL_X[0], z) for z in zs])       # (the paint is measured along the inner edge)
    along = np.concatenate([[0], np.cumsum(np.hypot(np.diff(zs), np.diff(ys)))])
    across = xs - xs[0]
    length, width = float(along[-1]), float(across[-1])
    pieces = (((SILL_Z[0], SLOT_Z[0]), SILL_X), ((SLOT_Z[0], SLOT_Z[1]), (SILL_X[0], SLOT_X[0])),
              ((SLOT_Z[0], SLOT_Z[1]), (SLOT_X[1], SILL_X[1])), ((SLOT_Z[1], SILL_Z[1]), SILL_X))
    for (z0, z1), (x0, x1) in pieces:
        rows = np.where((zs >= z0 - 1e-9) & (zs <= z1 + 1e-9))[0]
        cols = np.where((xs >= x0 - 1e-9) & (xs <= x1 + 1e-9))[0]
        for side in (1.0, -1.0):
            points = np.array([[(side * xs[i], sill_y(xs[i], zs[j]), zs[j]) for i in cols] for j in rows])
            part.patch(area, length, width, points, along[rows], across[cols], lambda p: EYE - p)
    paint_carbon(area, length, width)
    return length, width


def apron(part, area):
    """The apron across the seat's front: rows run across the cabin, columns up from the deck to the cushion."""
    def edge(z):
        return hip_edges(max(z, Z0))[0]                # the hip panel's inner edge there: (x, y)
    ss = np.linspace(-1, 1, 49)
    zs = np.concatenate([np.linspace(APRON_Z[0], APRON_Z[1], 9), np.linspace(APRON_Z[1], APRON_AFT, 4)[1:]])
    points = np.zeros((len(ss), len(zs), 3))
    for i, z in enumerate(zs):
        mid = lerp(APRON_Y[0], APRON_Y[1], ease((z - APRON_Z[0]) / (APRON_Z[1] - APRON_Z[0])))
        ex, ey = edge(z)
        for j, s in enumerate(ss):
            points[j, i] = (s * (ex + .006), mid + (ey - .004 - mid) * abs(s)**2.5, z)  # dished across the knees, rising into each hip panel's edge
    along = arc_length(points[:, len(zs) // 2])
    across = arc_length(points[len(ss) // 2])
    part.patch(area, float(along[-1]), float(across[-1]), points, along, across, lambda p: EYE - p)
    paint_carbon(area, float(along[-1]), float(across[-1]))
    return float(along[-1]), float(across[-1])


# ---- paint ----
def paint_hip(area, length, width):
    """Carbon twill, with the hip's pad let into it: leather, fluted fore and aft, each flute and the
    pad's edge stitched."""
    a, b, where = kit.window(area, length, width)
    a, b = np.broadcast_arrays(a, b)
    # the carbon (as the roof's shell: two-by-two twill under lacquer)
    tow = .0024
    u, v = a / tow, b / tow
    iu, iv = np.floor(u).astype(np.int32), np.floor(v).astype(np.int32)
    warp = ((iu + iv) % 4) < 2
    fu, fv = u - iu, v - iv
    sheen = np.where(warp, .5 + .5 * np.cos(math.pi * (fv - .5) * 1.6), .5 + .5 * np.cos(math.pi * (fu - .5) * 1.6))
    fibre = vnoise(np.where(warp, u * 9, v * 9), np.where(warp, v * 60, u * 60))
    col = (17 + 30 * sheen * np.where(warp, .7, 1.0) + (fibre - .5) * 7)[..., None] * np.array((1, 1, 1.04), f32)
    h = (sheen - .5) * 4e-6
    rough = .16 + .08 * smooth((fbm(b * 40, a * 40) - .55) * 6)
    ao = np.ones_like(sheen)
    # the pad: a rounded panel beside the hip, clear of the panel's edges
    lo, hi = np.array((.17, .035)), np.array((length - .19, min(width - .05, .215)))
    mid, half = (lo + hi) / 2, (hi - lo) / 2
    corner = .03
    qa, qb = np.abs(a - mid[0]) - (half[0] - corner), np.abs(b - mid[1]) - (half[1] - corner)
    inside = corner - (np.hypot(np.clip(qa, 0, None), np.clip(qb, 0, None)) + np.minimum(np.maximum(qa, qb), 0))   # metres inside the pad's edge
    pad = smooth(inside / .003)
    peb = grain(b, a)
    leather = LEATHER * (.84 + .22 * peb[..., None]) * 1.25
    flute = .043
    row = (b - lo[1] + flute / 2) % flute - flute / 2                 # to the nearest flute seam
    plump = np.abs(np.sin(math.pi * (b - lo[1]) / flute))**.6
    lh = .0038 * smooth(inside / .012) + .0022 * plump * smooth((inside - .012) / .006) + (peb - 1) * 5e-5
    lrough = .56 + .14 * (1 - peb)
    lcol = leather * (1 - .2 * (1 - plump[..., None]) * smooth((inside - .012) / .006)[..., None])
    lao = 1 - .3 * (1 - plump) * smooth((inside - .012) / .006)
    field = inside > .016                                            # the flutes stop short of the edge seam
    seam = np.exp(-(row / .0014)**2) * field
    lh = lh - .0007 * seam
    for off in (-.0038, .0038):
        thread, lift = stitches(a, row - off)
        thread = thread & field
        lh = lh + np.where(field, lift, 0)
        lcol = np.where(thread[..., None], THREAD * (.85 + .15 * np.cos(2 * math.pi * a / .00045))[..., None], lcol)
        lrough = np.where(thread, .72, lrough)
    # the pad's edge: a seam a centimetre in, stitched all the way round
    along = np.where(qb > qa, a, b)                                  # along whichever edge is nearer
    d = inside - .011
    lh = lh - .0008 * np.exp(-(d / .0014)**2)
    thread, lift = stitches(along, d)
    thread = thread & (inside > .004)
    lh = lh + np.where(inside > .004, lift, 0)
    lcol = np.where(thread[..., None], THREAD * (.85 + .15 * np.cos(2 * math.pi * along / .00045))[..., None], lcol)
    lrough = np.where(thread, .72, lrough)
    # let in: a shadowed joint where the leather meets the carbon
    joint = np.exp(-(inside / .0025)**2)
    col = col * (1 - pad[..., None]) + lcol * pad[..., None]
    col = col * (1 - .45 * joint[..., None])
    h = h * (1 - pad) + lh * pad - .0006 * joint
    rough = rough * (1 - pad) + lrough * pad
    ao = (ao * (1 - pad) + lao * pad) * (1 - .4 * joint)
    kit.commit(area, length, width, where, col, h, rough, np.zeros_like(sheen), ao)


# ---- forms ----
def sheet(part, area, surface, zs, nt, paint):
    """One side's surface(side, z, t) and its mirror, both on the same part of the atlas."""
    ts = np.linspace(0, 1, nt)
    right = np.array([[surface(1.0, z, t) for t in ts] for z in zs])
    along = arc_length(right[:, nt // 2])
    across = arc_length(right[len(zs) // 2])
    for side in (1.0, -1.0):
        points = right * np.array((side, 1, 1))
        part.patch(area, float(along[-1]), float(across[-1]), points, along, across, lambda p: EYE - p)
    paint(area, float(along[-1]), float(across[-1]))
    return float(along[-1]), float(across[-1])


def slab(part, lo, hi):
    """A box that stands in for a fitting while the occlusion is traced."""
    lo, hi = np.array(lo, float), np.array(hi, float)
    whole = (0, 0, 8, 8)
    for axis in range(3):
        for end in (lo, hi):
            u, v = (axis + 1) % 3, (axis + 2) % 3
            corners = np.zeros((2, 2, 3))
            for j, cu in enumerate((lo[u], hi[u])):
                for i, cv in enumerate((lo[v], hi[v])):
                    corners[j, i, axis], corners[j, i, u], corners[j, i, v] = end[axis], cu, cv
            out = np.zeros(3)
            out[axis] = 1 if end is hi else -1
            part.patch(whole, 1, 1, corners, (0, 1), (0, 1), out)


def tub():
    part, stand_ins = Part("Tub"), Part("StandIns")
    zs = np.concatenate([np.linspace(Z0 - .02, Z0, 4)[:-1], np.linspace(Z0, ZC, 30)[:-1], np.linspace(ZC, ZC + .06, 10)[:-1], np.linspace(ZC + .06, ZE, 16)])
    hip_size = sheet(part, kit.rect(16, 16, 900, 1560), hip, zs, 26, paint_hip)             # (an atlas rectangle is across by along; 26 across puts a row on the waist's crease)
    liner_size = sheet(part, kit.rect(940, 16, 260, 1800), liner, np.concatenate([np.linspace(LINER_Z[0], ZC, 33)[:-1], np.linspace(ZC, LINER_Z[1], 9)]), 7, paint_carbon)
    sheet(part, kit.rect(1220, 16, 160, 200), cap, np.linspace(ZC - .012, ZC + .046, 9), 5, paint_carbon)
    sill_size = sills(part, kit.rect(1580, 16, 300, 1180))
    apron_size = apron(part, kit.rect(1400, 16, 150, 1300))
    print("TUB", "sill %.2f x %.2f m at %.3f, slotted %.3f x %.3f m; apron %.2f m across, %.2f m up" % (sill_size + (SILL_Y, SLOT_Z[1] - SLOT_Z[0], SLOT_X[1] - SLOT_X[0]) + apron_size), flush=True)
    for side in (1.0, -1.0):
        x = sorted((side * .415, side * .505))
        slab(stand_ins, (x[0], .09, .02), (x[1], .14, .05))                           # the quadrant's end blocks and rails, round the lever's slot
        slab(stand_ins, (x[0], .09, .35), (x[1], .14, .38))
    for side in (1.0, -1.0):
        x = sorted((side * .55, side * .68))
        slab(stand_ins, (x[0], .126, .005), (x[1], .386, .865))                       # the console
        x = sorted((side * .22, side * .31))
        slab(stand_ins, (x[0], .14, .68), (x[1], .265, 1.10))                         # the cushion's bolster, from behind its rounded nose
    # the cushion: its front is narrower and lower, and its flanks are rounded off. (As one square box it
    # stood over the apron's ends and they baked black: two pockets at the cushion's corners.)
    slab(stand_ins, (-.24, .085, .60), (.24, .185, .70))
    slab(stand_ins, (-.30, .085, .70), (.30, .21, 1.12))
    slab(stand_ins, (-.31, .15, 1.04), (.31, .93, 1.20))                              # the seat's back
    slab(stand_ins, (-.42, .117, -.55), (.42, .143, .55))                             # the deck plate
    x_rim, top = rim(1.0)
    print("TUB", "hip panel %.2f x %.2f m, side liner %.2f x %.2f m;" % (hip_size + liner_size),
          "behind the console the wall stands %.2f m, from the seat's flank to %.3f m under the hull's top at the rim" % (top - .075 - SEAT_Y, .075), flush=True)
    return part, stand_ins


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
    scene.world.light_settings.distance = .3

    image = bpy.data.images.new("Occlusion", BAKE, BAKE, alpha=True, is_data=True)
    image.pixels.foreach_set(np.tile(np.array((1, 1, 1, 0), f32), BAKE * BAKE))
    target = bpy.data.materials.new("BakeTarget")
    target.use_nodes = True
    node = target.node_tree.nodes.new("ShaderNodeTexImage")
    node.image = image
    target.node_tree.nodes.active = node

    part, stand_ins = tub()
    body = part.mesh(target)
    others = stand_ins.mesh(bpy.data.materials.new("StandIn"))
    bake([body], [], image, False)                                    # (the stand-ins shade it)
    pixels = np.empty(BAKE * BAKE * 4, f32)
    image.pixels.foreach_get(pixels)
    pixels = pixels.reshape(BAKE, BAKE, 4)[::-1]                     # Blender's rows run bottom-up
    scale = kit.RES // BAKE
    lit = np.kron(np.where(pixels[..., 3] > .5, pixels[..., 0], 1.0), np.ones((scale, scale), f32))
    lit = np.clip(box(lit.astype(f32), 1, 1), 0, 1)
    print("BAKE", f"{(pixels[..., 3] > .5).mean() * 100:.0f}% of the atlas baked, occlusion {lit.min():.2f}-{lit.max():.2f}, mean {lit.mean():.2f}", flush=True)
    kit.BASE[:] = np.clip(kit.BASE * (.5 + .5 * lit[..., None]), 0, 255)
    kit.ORM[..., 0] = np.clip(kit.ORM[..., 0] * lit, 0, 255)
    bpy.data.objects.remove(others, do_unlink=True)

    with tempfile.TemporaryDirectory() as tmp:
        folder = Path(tmp)
        for name, pixels8 in (("TubHD_Base", kit.BASE), ("TubHD_Normal", kit.NORMAL), ("TubHD_ORM", kit.ORM)):
            png(folder / (name + ".png"), pixels8)
        body.data.materials.clear()
        body.data.materials.append(pbr(folder, "TubHD"))
        bpy.ops.export_scene.gltf(filepath=str(OUTPUT), export_tangents=True, export_animations=False,
                                  export_cameras=False, export_lights=False)
    print("Wrote", OUTPUT, OUTPUT.stat().st_size, "bytes")


if __name__ == "__main__":
    main()
