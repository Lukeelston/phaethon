"""Realism spike: the dashboard (Luke: "while you're in the gauge cluster, will you please move it up
to the rail, and create a true dash board?", and of the opening: "remove 12 inches of 'legroom'
between the gauges and seat. The idea is to have good visibility through the smallest opening
possible").

    blender --background --python tools/art_dash_hd.py [-- --res 2048] [-- --samples 64]

The instruments stood alone in the footwell, a metre and a third from the eye, with the open nose
showing round them and under them. Now the opening's front is 0.43 m nearer, the instruments are
0.30 m nearer and up under its rim, and this stands behind them from the rim to the floor, in the
rig's frame like the other fittings (forward -Z, y up from the rig's floor):
  top       a padded shelf from the underside of the rim back to the brow: deepest on the centreline,
            where the instruments' cowl grows out of it, a few centimetres at the corners
  brow      rolled over, the leather carried a little way down the fascia and stitched
  fascia    behind the instruments it follows their arc and leans as they do, so their binnacle
            stands proud of it by its own depth; outboard of them it turns aft, inside the opening's
            own line, and runs back as a wall to the consoles and the tub's side liners
  cheeks    a small face each side closing the wall's end over the console's nose
  seal      the top's outer edge turned up behind the rim light to the lip's underside. (Without it a
            slot a centimetre and a half high ran round under the rim, and from a low head the
            open nose showed through it: bright bars over the instruments.) It is its own mesh,
            "DashSeal", because it lies against the lip, where no other fitting may come
Leather as the instruments' cowl, stitched in the cockpit's orange thread; carbon twill under
lacquer as the tub, with a bright bead let in under the leather's edge. Forms are geometry; grain,
weave, stitching and the bead are synthesised in surface metres; the occlusion is path traced with
the binnacle, the rim, the deck and the consoles standing in. Writes godot/art/cockpit/dash_hd.glb
(two meshes, "Dash" and "DashSeal", both sides).
"""
import math
import sys
import tempfile
from pathlib import Path

import bpy
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import art_bezel_hd as kit  # noqa: E402  the atlas and its helpers
import art_gauges_hd as G  # noqa: E402  the binnacle's own lines, its leather and thread
import gauge_layout as L  # noqa: E402
from art_cockpit import OPEN_AX, OPEN_AZ_FRONT, OPEN_ZC, hull_floor, hull_top  # noqa: E402  the game's own hull stations (rig frame) and opening
from art_coaming_hd import ARGS, box, f32, fbm, png, smooth, vnoise  # noqa: E402
from art_grip_hd import pbr  # noqa: E402
from art_roof_hd import arc_length, stitches  # noqa: E402
from art_tub_hd import slab  # noqa: E402

OUTPUT = Path(__file__).resolve().parents[1] / "godot/art/cockpit/dash_hd.glb"
SAMPLES = int(ARGS[ARGS.index("--samples") + 1]) if "--samples" in ARGS else 64
BAKE = kit.RES // 2
EYE = np.array((0.0, .72, .6))
MOUNT_Y, MOUNT_Z, TILT = .33, -.395, .34   # the instruments' mount (vr/dashboard.gd mount()): its origin, and how far its face lies back
COS, SIN = math.cos(TILT), math.sin(TILT)
R = L.R_ARC
DEPTH = .035                         # the fascia stands this far behind the binnacle's own (which is .060 deep)
RIM_IN, RIM_DROP = .012, .075        # where the top tucks under the rim: in from the opening's edge, and under the hull's top there (as the tub's panels)
INSET = .045                         # outboard of the instruments the brow runs this far inside the opening's edge
TURN = (38.0, 56.0)                  # degrees round from the nose over which the fascia leaves the instruments' arc for the opening's line
END_Z = .0                           # the wall runs back to where the tub's side liner begins, over the console's nose
FOOT_UP = .013                       # its foot stands this far off the hull's trim (test_cables wants a centimetre)
ROLL = .014                          # the brow's roll
PAD = .030                           # the leather comes this far down the fascia from the roll
NS, NR, NF = 4, 6, 16                # columns: across the top, round the brow, down the fascia
A_END = math.acos((OPEN_ZC - END_Z) / (OPEN_AZ_FRONT - INSET))
SEAL_IN, SEAL_DROP = .0105, .057     # the seal's top: against the lip's underside (0.055 in radius), outboard of the rim light's holder
CHEEK_FOOT = np.array((.672, .36))   # the tub's side liner starts here, just inside the console's outer top edge: (x, y)


def lerp(a, b, t):
    return a + (b - a) * t


def ease(t):
    t = min(max(t, 0.0), 1.0)
    return t * t * (3 - 2 * t)


def to_rig(x, y, d):
    """The instruments' flat layout (x along their arc, y up their face, d toward the pilot) -> the rig."""
    px, py, pz = L.to_panel(x, y, d)
    return np.array((px, MOUNT_Y + py * COS + pz * SIN, MOUNT_Z - py * SIN + pz * COS))


def behind_instruments(x, y):
    """The fascia behind the instruments at rig (x, y): on their arc, DEPTH behind their face, leaning as it does."""
    phi = math.asin(x / (R + DEPTH))
    pz = R - (R + DEPTH) * math.cos(phi)
    py = (y - MOUNT_Y - pz * SIN) / COS
    return np.array((x, y, MOUNT_Z - py * SIN + pz * COS))


def edge(a):
    """The opening's edge `a` radians round from the nose: x, z, and the way in from it (x, z)."""
    x, z = OPEN_AX * math.sin(a), OPEN_ZC - OPEN_AZ_FRONT * math.cos(a)
    n = np.array((-math.sin(a) / OPEN_AX, math.cos(a) / OPEN_AZ_FRONT))
    return x, z, n / np.linalg.norm(n)


def station(a):
    """The dashboard at `a`: where its top tucks under the rim, its brow, and the fascia's foot."""
    x, z, n = edge(a)
    rim = np.array((x + n[0] * RIM_IN, hull_top(x, z) - RIM_DROP, z + n[1] * RIM_IN))
    xs, zs = x + n[0] * INSET, z + n[1] * INSET
    w = ease((math.degrees(a) - TURN[0]) / (TURN[1] - TURN[0]))      # 0 behind the instruments .. 1 a wall along the side

    def at(y):
        return lerp(behind_instruments(xs, y), np.array((xs, y, zs)), w)
    foot = hull_floor(xs, at(.1)[2], .035 + FOOT_UP)
    return rim, at(rim[1]), at(foot)


def section(rim, brow, foot):
    """One station's points: across the top from under the rim, rolled over the brow, down the fascia."""
    out, down = rim - brow, foot - brow
    top = brow + out / np.linalg.norm(out) * min(ROLL, .45 * np.linalg.norm(out))
    face = brow + down / np.linalg.norm(down) * ROLL
    pts = [lerp(rim, top, t) for t in np.linspace(0, 1, NS)]
    pts += [(1 - t)**2 * top + 2 * (1 - t) * t * brow + t * t * face for t in np.linspace(0, 1, NR + 1)[1:]]
    pts += [lerp(face, foot, t) for t in np.linspace(0, 1, NF + 1)[1:]]
    return np.array(pts)


# ---- paint ----
def paint_dash(area, length, width, roll_end):
    """Carbon twill, and over the top, the brow and a little of the fascia the leather: padded, a double
    row of stitching under the brow, one along its edge, and a bright bead let into the carbon below it."""
    a, b, where = kit.window(area, length, width)
    a, b = np.broadcast_arrays(a, b)
    tow = .0024                                                      # (as the tub: two-by-two twill under lacquer)
    u, v = a / tow, b / tow
    iu, iv = np.floor(u).astype(np.int32), np.floor(v).astype(np.int32)
    warp = ((iu + iv) % 4) < 2
    fu, fv = u - iu, v - iv
    sheen = np.where(warp, .5 + .5 * np.cos(math.pi * (fv - .5) * 1.6), .5 + .5 * np.cos(math.pi * (fu - .5) * 1.6))
    fibre = vnoise(np.where(warp, u * 9, v * 9), np.where(warp, v * 60, u * 60))
    col = (17 + 30 * sheen * np.where(warp, .7, 1.0) + (fibre - .5) * 7)[..., None] * np.array((1, 1, 1.04), f32)
    h = (sheen - .5) * 4e-6
    rough = .16 + .08 * smooth((fbm(b * 40, a * 40) - .55) * 6)
    metal, ao = np.zeros_like(sheen), np.ones_like(sheen)
    # the bead: a half-round of brushed aluminium, a finger under the leather's edge
    hem = roll_end + PAD
    q = np.abs(b - (hem + .007)) / .0016
    bead = q < 1
    brushed = vnoise(a * 70, b * 2400) * .6 + vnoise(a * 9, b * 900 + 40) * .4
    col = np.where(bead[..., None], 186.0 + (brushed[..., None] - .5) * 26, col * (1 - .35 * np.exp(-((q - 1) / .5)**2) * (q > 1))[..., None])
    h = np.where(bead, .0011 * np.sqrt(np.clip(1 - q * q, 0, 1)) + (brushed - .5) * 5e-6, h)
    rough = np.where(bead, .28 + (brushed - .5) * .14, rough)
    metal = np.where(bead, 1.0, metal)
    # the leather
    inside = hem - b                                                 # metres inside its edge
    pad = smooth(inside / .003)
    peb = G.grain(b, a)
    crease = fbm(b * 55, a * 55, 3)
    lcol = G.LEATHER * (.84 + .2 * peb[..., None]) * (.94 + .12 * crease[..., None])
    lh = .0030 * smooth(inside / .010) + (peb - 1) * 5e-5 + (crease - .5) * 5e-5
    lrough = .6 + .14 * (1 - peb) + (crease - .5) * .08
    for row in (b - (roll_end + .006), b - (roll_end + .0125), inside - .007):
        thread, lift = stitches(a, row)
        lh = lh + lift
        lcol = np.where(thread[..., None], G.THREAD * (.85 + .15 * np.cos(2 * math.pi * a / .00045))[..., None], lcol)
        lrough = np.where(thread, .72, lrough)
    joint = np.exp(-(inside / .0025)**2)                             # a shadowed joint where it is turned under on the carbon
    col = col * (1 - pad[..., None]) + lcol * pad[..., None]
    col = col * (1 - .45 * joint[..., None])
    h = h * (1 - pad) + lh * pad - .0006 * joint
    rough = rough * (1 - pad) + lrough * pad
    metal = metal * (1 - pad)
    ao = ao * (1 - .4 * joint)
    kit.commit(area, length, width, where, col, h, rough, metal.astype(f32), ao)


def paint_cheek(area, length, width):
    a, b, where = kit.window(area, length, width)
    a, b = np.broadcast_arrays(a, b)
    peb = G.grain(b, a)
    col = G.LEATHER * (.84 + .2 * peb[..., None])
    kit.commit(area, length, width, where, col, (peb - 1) * 5e-5, .62 + .12 * (1 - peb), np.zeros_like(peb), np.ones_like(peb))


# ---- forms ----
def dash():
    part, seal, stand_ins = G.Part("Dash"), G.Part("DashSeal"), G.Part("StandIns")
    aa = np.unique(np.concatenate([np.linspace(0, math.radians(TURN[0]), 22), np.linspace(math.radians(TURN[0]), math.radians(TURN[1]), 14),
                                   np.linspace(math.radians(TURN[1]), A_END, 12)]))
    stations = [station(a) for a in aa]
    right = np.array([section(*s) for s in stations])                # [station][column]
    brow_col = NS + NR // 2 - 1
    along = arc_length(right[:, brow_col])
    across = arc_length(right[int(np.searchsorted(aa, math.radians(24.0)))])
    length, width = float(along[-1]), float(across[-1])
    area = kit.rect(16, 16, 1000, 2010)                              # (an atlas rectangle is across by along)
    for side in (1.0, -1.0):
        part.patch(area, length, width, right * np.array((side, 1, 1)), along, across, lambda p: EYE - p)
    paint_dash(area, length, width, float(across[NS + NR - 1]))
    # the cheeks: from the wall's end out to the rim, down onto the console's nose
    rim, brow, _ = stations[-1]
    cheek = np.array([[brow, rim], [(brow[0], CHEEK_FOOT[1], brow[2]), (CHEEK_FOOT[0], CHEEK_FOOT[1], rim[2])]])
    tall, wide = float(brow[1] - CHEEK_FOOT[1]), float(np.linalg.norm(rim - brow))
    cheek_area = kit.rect(1040, 16, 120, 220)
    for side in (1.0, -1.0):
        part.patch(cheek_area, tall, wide, cheek * np.array((side, 1, 1)), (0, tall), (0, wide), (0, 0, 1))
    paint_cheek(cheek_area, tall, wide)
    # the seal: from the top's outer edge up to the lip's underside, all the way round
    strip = []
    for a, (rim, _, _) in zip(aa, stations):
        x, z, n = edge(a)
        strip.append([rim, (x + n[0] * SEAL_IN, hull_top(x, z) - SEAL_DROP, z + n[1] * SEAL_IN)])
    strip = np.array(strip)
    run, rise = arc_length(strip[:, 0]), float(np.linalg.norm(strip[0, 1] - strip[0, 0]))
    seal_area = kit.rect(1180, 16, 40, 2010)
    for side in (1.0, -1.0):
        seal.patch(seal_area, float(run[-1]), rise, strip * np.array((side, 1, 1)), run, (0, rise), lambda p: EYE - p)
    paint_cheek(seal_area, float(run[-1]), rise)

    # ---- what shades it ----
    whole = (0, 0, 8, 8)
    xs = np.linspace(-L.HALF_W, L.HALF_W, 33)
    ramp = np.linspace(0, 1, 7)
    face = np.array([[to_rig(x, lerp(L.Y_BOTTOM, float(G.top(x)), t), 0.0) for t in ramp] for x in xs])
    stand_ins.patch(whole, 1, 1, face, np.linspace(0, 1, len(xs)), ramp, lambda p: EYE - p)          # the binnacle: its face ...
    for y_of, out in ((lambda x: float(G.top(x)), (0, 1, 0)), (lambda x: L.Y_BOTTOM, (0, -1, 0))):   # ... its cowl and its underside ...
        sheet = np.array([[to_rig(x, y_of(x), lerp(L.D_BACK, float(G.lip(x)) if out[1] > 0 else 0.0, t)) for t in ramp[::2]] for x in xs])
        stand_ins.patch(whole, 1, 1, sheet, np.linspace(0, 1, len(xs)), ramp[::2], out)
    for x in (-L.HALF_W, L.HALF_W):                                                                    # ... and its ends
        end = np.array([[to_rig(x, lerp(L.Y_BOTTOM, float(G.top(x)), t), lerp(L.D_BACK, float(G.lip(x)), s)) for s in (0, .5, 1)] for t in ramp[::2]])
        stand_ins.patch(whole, 1, 1, end, ramp[::2], (0, .5, 1), (x, 0, 0))
    round_it = np.linspace(0, 2 * math.pi, 9)
    lip = []
    for a in np.linspace(-A_END - .25, A_END + .25, 73):                                               # the rim: the hull's lip and the coaming round it
        x, z, n = edge(a)
        lip.append([(x + n[0] * .058 * math.cos(p), hull_top(x, z) + .058 * math.sin(p), z + n[1] * .058 * math.cos(p)) for p in round_it])
    stand_ins.patch(whole, 1, 1, np.array(lip), np.linspace(0, 1, 73), np.linspace(0, 1, 9), (0, 1, 0))
    slab(stand_ins, (-.42, .117, -.55), (.42, .143, .55))                                              # the deck plate
    slab(stand_ins, (-1.1, .0, -.75), (1.1, .056, .3))                                                 # the hull's floor
    for side in (1.0, -1.0):
        x = sorted((side * .55, side * .68))
        slab(stand_ins, (x[0], .126, -.055), (x[1], .386, .865))                                      # the consoles
    rim, brow, foot = stations[0]
    corner = stations[int(np.searchsorted(aa, math.radians(47.0)))]
    print("DASH", "brow %.2f m a side, section %.2f m; on the centreline the top is %.3f m deep at y %.3f and the fascia runs from z %.3f to %.3f at its foot (y %.3f)" % (
        length, width, float(np.linalg.norm(rim - brow)), brow[1], brow[2], foot[2], foot[1]), flush=True)
    print("DASH", "at the corner (47 degrees) the brow is at x %.3f z %.3f, %.3f m inside the rim's underside; the wall ends at x %.3f z %.3f, y %.3f" % (
        corner[1][0], corner[1][2], float(np.linalg.norm(corner[0] - corner[1])), stations[-1][1][0], stations[-1][1][2], stations[-1][1][1]), flush=True)
    return part, seal, stand_ins


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

    part, seal, stand_ins = dash()
    body, edging = part.mesh(target), seal.mesh(target)
    others = stand_ins.mesh(bpy.data.materials.new("StandIn"))
    for obj in (body, edging):
        print("MESH", obj.name, len(obj.data.vertices), "vertices", sum(len(p.vertices) - 2 for p in obj.data.polygons), "triangles", flush=True)
    G.bake([body, edging], [], image, False)                         # (the stand-ins shade them)
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
        for name, pixels8 in (("DashHD_Base", kit.BASE), ("DashHD_Normal", kit.NORMAL), ("DashHD_ORM", kit.ORM)):
            png(folder / (name + ".png"), pixels8)
        finish = pbr(folder, "DashHD")
        for obj in (body, edging):
            obj.data.materials.clear()
            obj.data.materials.append(finish)
        bpy.ops.export_scene.gltf(filepath=str(OUTPUT), export_tangents=True, export_animations=False,
                                  export_cameras=False, export_lights=False)
    print("Wrote", OUTPUT, OUTPUT.stat().st_size, "bytes")


if __name__ == "__main__":
    main()
