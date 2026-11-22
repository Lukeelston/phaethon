"""Realism spike: the analogue gauge cluster's binnacle, and the map display's pod.

    blender --background --python tools/art_gauges_hd.py [-- --res 2048] [-- --samples 96]

Five instrument tubes under a stitched leather cowl (tools/gauge_layout.py has the layout): each
a barrel with a brushed trim ring at its mouth, a matte funnel down to the dial and a hub cap
over the needle's pivot, with two flat LCD strips framed into the fascia below. The map's pod is
a hooded housing round the game's 220 mm screen. Rings, chamfers, the cowl's lip, frames and
caps are geometry; grain, stitching, brushing and baffle grooves are synthesised in surface
metres, and the occlusion is path traced over the finished shapes. The dials, needles, glass and
everything that lights up are the game's own (vr/gauge_cluster.gd).
"""
import math
import sys
import tempfile
from pathlib import Path

import bmesh
import bpy
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import art_bezel_hd as kit  # noqa: E402  the atlas and its helpers
import gauge_layout as L  # noqa: E402
from art_coaming_hd import ARGS, box, cells, f32, fbm, mix, png, smooth, vnoise  # noqa: E402
from art_grip_hd import pbr  # noqa: E402

OUTPUT = Path(__file__).resolve().parents[1] / "godot/art/cockpit/gauges_hd.glb"
SAMPLES = int(ARGS[ARGS.index("--samples") + 1]) if "--samples" in ARGS else 96
BAKE = kit.RES // 2
LEATHER, THREAD = np.array((27, 27, 30), f32), np.array((206, 96, 30), f32)
NF, NU = 12, 8                                                        # fascia and underside rows


class Part:
    """One exported mesh: patches of quads, each mapped to its own rectangle of the atlas."""

    def __init__(self, name):
        self.name, self.xyz, self.uv, self.faces = name, [], [], []

    def patch(self, area, length, width, points, along, across, out):
        """points[row][col] in Godot metres; rows run `along` metres, columns `across` (one
        list for every row, or a row of its own for each). The middle of the patch faces `out`
        (a vector, or a function of the point there)."""
        points = np.asarray(points, float)
        rows, cols = points.shape[:2]
        start = len(self.xyz)
        self.xyz += [(p[0], -p[2], p[1]) for p in points.reshape(-1, 3)]      # Godot XYZ -> Blender
        across = np.broadcast_to(np.asarray(across, float), (rows, cols))
        self.uv += [kit.uv_of(area, length, width, float(along[j]), float(across[j, i])) for j in range(rows) for i in range(cols)]
        j, i = min(rows // 2, rows - 2), min(cols // 2, cols - 2)
        normal = np.cross(points[j, i + 1] - points[j, i], points[j + 1, i] - points[j, i])
        facing = np.asarray(out(points[j, i]) if callable(out) else out, float)
        assert np.linalg.norm(normal) > 1e-12, (self.name, "flat middle cell")
        order = (0, 1, cols + 1, cols) if normal @ facing > 0 else (cols, cols + 1, 1, 0)
        self.faces += [tuple(start + r * cols + c + k for k in order) for r in range(rows - 1) for c in range(cols - 1)]

    def lathe(self, area, profile, around, frame, hint, under=None):
        """Turn (radius, depth) pairs round a fitting's axis; `hint` is how its first run faces.
        `under` is a neighbouring tube this one stands partly under, as (a point on its axis, the
        axis, a radius): nothing is built nearer that axis than the radius. Each row stops exactly
        on that cylinder, and there is a row where the profile first touches it, so the cut edge
        lies inside the neighbour's wall all the way."""
        prof = np.array(profile, float)
        arc = np.concatenate([[0], np.cumsum(np.hypot(np.diff(prof[:, 0]), np.diff(prof[:, 1])))])
        girth = 2 * math.pi * prof[:, 0].max()
        o, ux, uy, n = (np.array(v, float) for v in frame)
        across, depth = facing(prof, hint)
        if under is None:
            phi = np.linspace(0, 2 * math.pi, around + 1)
            radial = np.cos(phi)[:, None] * ux + np.sin(phi)[:, None] * uy
            points = o + prof[:, :1, None] * radial[None] + prof[:, 1:, None] * n
            self.patch(area, arc[-1], girth, points, arc, phi / (2 * math.pi) * girth, across * radial[min((around + 1) // 2, around - 1)] + depth * n)
            return arc, girth
        centre, axis, limit = np.array(under[0], float), np.array(under[1], float), float(under[2])

        def reach(row, phi):
            """How far the row's points at these angles are from the neighbour's axis."""
            phi = np.asarray(phi, float)
            p = o + row[0] * (np.cos(phi)[..., None] * ux + np.sin(phi)[..., None] * uy) + row[1] * n - centre
            return np.linalg.norm(p - (p @ axis)[..., None] * axis, axis=-1)

        def nearest(row):
            """The angle at which a row comes nearest the neighbour's axis, and how near."""
            coarse = np.linspace(0, 2 * math.pi, 721)[:-1]
            lo = coarse[np.argmin(reach(row, coarse))] - math.pi / 360
            hi = lo + math.pi / 180
            for _ in range(60):
                m1, m2 = lo + (hi - lo) / 3, hi - (hi - lo) / 3
                lo, hi = (lo, m2) if reach(row, m1) < reach(row, m2) else (m1, hi)
            return (lo + hi) / 2, float(reach(row, (lo + hi) / 2))

        def edge(row, inside, outside):
            """The angle between these two at which the row crosses the cylinder."""
            for _ in range(60):
                mid = (inside + outside) / 2
                inside, outside = (mid, outside) if reach(row, mid) < limit else (inside, mid)
            return outside

        # rows no more than 10 mm apart, and one wherever the profile first touches the cylinder
        fine, fine_arc = [prof[0]], [arc[0]]
        for k in range(len(prof) - 1):
            steps = max(1, int(math.ceil((arc[k + 1] - arc[k]) / .010)))
            for s in range(1, steps + 1):
                row, at = prof[k] + (prof[k + 1] - prof[k]) * s / steps, arc[k] + (arc[k + 1] - arc[k]) * s / steps
                before = fine[-1]
                if (nearest(before)[1] < limit) != (nearest(row)[1] < limit):
                    t0, t1 = 0.0, 1.0
                    cut0 = nearest(before)[1] < limit
                    for _ in range(50):
                        tm = (t0 + t1) / 2
                        t0, t1 = (tm, t1) if (nearest(before + (row - before) * tm)[1] < limit) == cut0 else (t0, tm)
                    clear = t1 if cut0 else t0                                    # (the side that just clears it)
                    fine_arc.append(fine_arc[-1] + (at - fine_arc[-1]) * clear)
                    fine.append(before + (row - before) * clear)
                fine.append(row)
                fine_arc.append(at)
        fine, fine_arc = np.array(fine), np.array(fine_arc)
        toward = centre - o
        toward = math.atan2(toward @ uy, toward @ ux)                             # the neighbour's side of this tube
        points, wide, cut = [], [], 0
        for row in fine:
            at, least = nearest(row)
            at = toward + (at - toward + math.pi) % (2 * math.pi) - math.pi      # (within half a turn of that side)
            if least < limit:
                phi = np.linspace(edge(row, at, at + math.pi), edge(row, at, at - math.pi) + 2 * math.pi, around + 1)
                cut += 1
            else:
                phi = np.linspace(at, at + 2 * math.pi, around + 1)
            points.append(o + row[0] * (np.cos(phi)[:, None] * ux + np.sin(phi)[:, None] * uy) + row[1] * n)
            wide.append(np.clip(phi - toward, 0, 2 * math.pi) / (2 * math.pi) * girth)
        far = math.cos(toward + math.pi) * ux + math.sin(toward + math.pi) * uy   # the middle column's side
        self.patch(area, arc[-1], girth, np.array(points), fine_arc, np.array(wide), across * far + depth * n)
        print("CUT", self.name, "%d of %d rows stop at the neighbour's wall" % (cut, len(fine)), flush=True)
        return arc, girth

    def mesh(self, material):
        mesh = bpy.data.meshes.new(self.name)
        mesh.from_pydata(self.xyz, [], self.faces)
        mesh.uv_layers.new(name="UV").data.foreach_set("uv", np.array([self.uv[i] for face in self.faces for i in face], f32).ravel())
        mesh.polygons.foreach_set("use_smooth", np.ones(len(self.faces), bool))
        mesh.materials.append(material)
        bm = bmesh.new()
        bm.from_mesh(mesh)
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=2e-5)       # close seams so shading runs across them
        bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 4])
        bm.to_mesh(mesh)
        bm.free()
        mesh.set_sharp_from_angle(angle=math.radians(36))             # chamfers stay crisp
        mesh.update()
        obj = bpy.data.objects.new(self.name, mesh)
        bpy.context.collection.objects.link(obj)
        print("MESH", self.name, len(mesh.vertices), "vertices", sum(len(p.vertices) - 2 for p in mesh.polygons), "triangles", flush=True)
        return obj


def facing(profile, hint):
    """Which way the middle run of a continuous (across, depth) profile faces, given how its first
    run does: every run of one profile faces the same side of it."""
    want = {"out": (1, 0), "in": (-1, 0), "front": (0, 1), "back": (0, -1)}[hint]
    first = profile[1] - profile[0]
    sign = 1.0 if first[1] * want[0] - first[0] * want[1] > 0 else -1.0
    j = min(len(profile) // 2, len(profile) - 2)
    run = profile[j + 1] - profile[j]
    return sign * run[1], -sign * run[0]


# ---- the cowl's line over the tubes, and how far its lip stands out ----
_X = np.linspace(-.5, .5, 1001)


def _blur(values, sigma):
    k = np.exp(-.5 * (np.arange(-4 * sigma, 4 * sigma + 1) / sigma)**2)
    return np.convolve(np.pad(values, len(k) // 2, mode="edge"), k / k.sum(), mode="valid")


_env = np.full(_X.shape, .050)
for _, gx, gy, ro, _, _ in L.GAUGES:
    _env = np.maximum(_env, gy + np.sqrt(np.clip((ro + .026)**2 - (_X - gx)**2, 0, None)) * (np.abs(_X - gx) < ro + .026))
_TOP = _blur(np.maximum(_blur(_env, 22), _env), 6) + .012
_LIP = _blur(np.interp(_X, [-L.HALF_W] + [g[1] for g in (L.GAUGES[3], L.GAUGES[1], L.GAUGES[0], L.GAUGES[2], L.GAUGES[4])] + [L.HALF_W],
                       [.060] + [g[4] + .034 for g in (L.GAUGES[3], L.GAUGES[1], L.GAUGES[0], L.GAUGES[2], L.GAUGES[4])] + [.060]), 30)
top = lambda x: np.interp(x, _X, _TOP)
lip = lambda x: np.interp(x, _X, _LIP)


def section(x):
    """The shell's loop at station x as (d, y) points: the front it shows the pilot, then the rest."""
    yt, dl, yb, db = float(top(x)), float(lip(x)), L.Y_BOTTOM, L.D_BACK
    yu = yt - .032
    pts = [(-.008 + .008 * math.sin(t), yb + .008 - .008 * math.cos(t)) for t in np.radians((0, 30, 60, 90))]
    pts += [(0.0, y) for y in np.linspace(yb + .008, yu - .016, NF + 1)[1:]]
    pts += [(.016 - .016 * math.cos(t), yu - .016 + .016 * math.sin(t)) for t in np.radians((22.5, 45, 67.5, 90))]
    pts += [(d, yu + .006 * (d - .016) / (dl - .028)) for d in np.linspace(.016, dl - .012, NU + 1)[1:]]
    pts += [(dl - .012 + .012 * math.cos(t), yt - .014 + .012 * math.sin(t)) for t in np.radians(np.linspace(-90, 90, 11)[1:])]
    front = len(pts)
    span = dl - .024 - db
    pts += [(d, yt - .002 - .012 * ((dl - .012 - d) / span)**2) for d in np.linspace(dl - .012, db + .012, 9)[1:]]
    pts += [(db + .012 + .012 * math.cos(t), yt - .026 + .012 * math.sin(t)) for t in np.radians((120, 150, 180))]
    pts += [(db, y) for y in np.linspace(yt - .026, yb + .010, 5)[1:]]
    pts += [(db + .010 + .010 * math.cos(t), yb + .010 + .010 * math.sin(t)) for t in np.radians((210, 240, 270))]
    return np.array(pts), front


_S0, FRONT = section(0.0)
_ARC0 = np.concatenate([[0], np.cumsum(np.hypot(*np.diff(_S0, axis=0).T))])
FRONT_LEN = float(_ARC0[FRONT - 1])
REAR_LEN = float(_ARC0[-1] - _ARC0[FRONT - 1] + math.hypot(*(_S0[-1] - _S0[0])))
# nominal arc lengths (at the centreline) where the front's zones begin
Z_FASCIA, Z_FILLET, Z_UNDER, Z_LIP = (float(_ARC0[i]) for i in (3, 3 + NF, 7 + NF, 7 + NF + NU))


def grain(x, y, size=.0017):
    f1, f2, _ = cells(x / size, y / size)
    return smooth((f2 - f1) / .24)


def paint_front(area):
    width = 2 * L.HALF_W
    a, b, where = kit.window(area, FRONT_LEN, width)
    a, b = np.broadcast_arrays(a, b)
    x = b - L.HALF_W
    yt, yb = top(x).astype(f32), L.Y_BOTTOM
    peb = grain(b, a)
    crease = fbm(b * 55, a * 55, 3)
    col = LEATHER * (.84 + .2 * peb[..., None]) * (.94 + .12 * crease[..., None])
    h = (peb - 1) * 5e-5 + (crease - .5) * 5e-5
    rough = .6 + .14 * (1 - peb) + (crease - .5) * .08
    metal, ao = np.zeros_like(h), np.ones_like(h)
    # the fascia's flat-layout height, for shading that follows the tubes
    y = yb + .008 + np.clip((a - Z_FASCIA) / (Z_FILLET - Z_FASCIA), 0, 1) * (yt - .032 - .016 - yb - .008)
    fascia = (a > Z_FASCIA) & (a < Z_FILLET)
    for _, gx, gy, ro, _, _ in L.GAUGES:                            # a soft shade where each barrel meets it
        r = np.hypot(x - gx, y - gy)
        ao = np.where(fascia, ao * (1 - .45 * np.exp(-np.clip(r - ro, 0, None) / .006)), ao)
    # the lip: a seam where the cowl's panel is turned under, and a row of saddle stitching above it
    turn = (a - Z_LIP) / .012                                        # radians round the lip's nose from its underside
    seam = np.exp(-((turn - .32) * .012 / .0007)**2)
    h, col = h - 3.5e-4 * seam, col * (1 - .55 * seam)[..., None]
    pitch, row = .0092, (turn - .86) * .012
    along = (b + .0012 * fbm(b * 30, a * 9)) % pitch - pitch / 2
    q = np.hypot(np.clip(np.abs(along) - .0030, 0, None), row) / .00085
    thread = q < 1
    hole = (np.hypot(np.abs(along) - .0038, row) < .0008) & ~thread
    pucker = np.exp(-(row / .0022)**2) * (1 - np.abs(along) / (pitch / 2)) * (a > Z_LIP)
    twist = .5 + .5 * np.cos((along + row * 1.6) / .00042)
    h = np.where(thread, h + 4.5e-4 * np.sqrt(np.clip(1 - q * q, 0, 1)) + 5e-5 * twist, h - 1.6e-4 * pucker)
    col = np.where(thread[..., None], THREAD * (.78 + .3 * twist[..., None]), np.where(hole[..., None], col * .35, col))
    rough = np.where(thread, .78, rough)
    ao = ao * np.where(hole, .6, 1)
    kit.commit(area, FRONT_LEN, width, where, col, h, rough, metal, ao)


def paint_rear(area, length, width):
    a, b, where = kit.window(area, length, width)
    a, b = np.broadcast_arrays(a, b)
    peb = grain(b, a)
    col = LEATHER * (.84 + .2 * peb[..., None])
    kit.commit(area, length, width, where, col, (peb - 1) * 5e-5, .62 + .12 * (1 - peb), np.zeros_like(peb), np.ones_like(peb))


def paint_barrel(area, length, girth):
    a, b, where = kit.window(area, length, girth)
    a, b = np.broadcast_arrays(a, b)
    grit = fbm(b * 2600, a * 2600, 2)
    col = np.array((17, 17, 19), f32) + (grit[..., None] - .5) * 7
    kit.commit(area, length, girth, where, col, (grit - .5) * 2.4e-5, .56 + (grit - .5) * .08, np.zeros_like(grit), .55 + .45 * smooth(a / .02))


def paint_ring(area, arc, girth, seed):
    """Brushed aluminium, the brushing running round the ring; brighter and tighter on its chamfers."""
    a, b, where = kit.window(area, float(arc[-1]), girth)
    a, b = np.broadcast_arrays(a, b)
    brushed = vnoise((b + seed) * 70, a * 2400) * .6 + vnoise((b + seed) * 9, a * 900 + 40) * .4
    chamfer = np.zeros(a.shape, bool)
    for k in (2, 4):                                                 # the two 45-degree runs of the profile
        chamfer |= (a > arc[k]) & (a < arc[k + 1])
    col = np.where(chamfer[..., None], 214.0, 178.0) + (brushed[..., None] - .5) * np.where(chamfer[..., None], 10, 30)
    rough = np.where(chamfer, .2, .31) + (brushed - .5) * .16
    seat = smooth((a - arc[5]) / max(float(arc[-1] - arc[5]), 1e-6))  # shaded down toward the glass
    kit.commit(area, float(arc[-1]), girth, where, col * (1 - .25 * seat[..., None]), (brushed - .5) * 5e-6, rough,
               np.ones_like(rough), 1 - .4 * seat)


def paint_funnel(area, length, girth):
    """Matte black, with shallow anti-glare grooves turned round it."""
    a, b, where = kit.window(area, length, girth)
    a, b = np.broadcast_arrays(a, b)
    grit = fbm(b * 3000, a * 3000, 2)
    step = .0075
    groove = np.exp(-((((a - .006) % step) - step / 2) / .0009)**2) * (a > .006) * (a < length - .005)
    col = np.array((10, 10, 11), f32) + (grit[..., None] - .5) * 4 - 3 * groove[..., None]
    kit.commit(area, length, girth, where, col, (grit - .5) * 1.2e-5 - 3.5e-4 * groove, .86 - .1 * groove + (grit - .5) * .06,
               np.zeros_like(grit), 1 - .35 * groove)


def paint_cap(area, arc, girth):
    """A satin black hub cap, spun on top, with a bright machined chamfer."""
    a, b, where = kit.window(area, float(arc[-1]), girth)
    a, b = np.broadcast_arrays(a, b)
    chamfer = (a > arc[1]) & (a < arc[2])
    spun = np.cos(2 * math.pi * a / .00034) * .5 + .5
    grit = fbm(b * 3000, a * 3000, 2)
    col = np.where(chamfer[..., None], 198.0 + (vnoise(b * 40, a * 7000)[..., None] - .5) * 18, 19.0 + 5 * spun[..., None] * (a > arc[2])[..., None] + (grit[..., None] - .5) * 5)
    rough = np.where(chamfer, .24, np.where(a > arc[2], .36 + .1 * spun, .5))
    kit.commit(area, float(arc[-1]), girth, where, col, (spun - .5) * 2e-6 * (a > arc[2]), rough, chamfer.astype(f32), np.ones_like(rough))


def paint_frame(area, arc, girth, bright):
    """Black anodising with a bright chamfer (the LCD strips), or brushed aluminium (the map's bezel)."""
    a, b, where = kit.window(area, float(arc[-1]), girth)
    a, b = np.broadcast_arrays(a, b)
    grit, brushed = fbm(b * 5000, a * 5000, 2), vnoise(b * 60, a * 7000)
    chamfer = np.zeros(a.shape, bool)
    for lo, hi in bright:
        chamfer |= (a > arc[lo]) & (a < arc[hi])
    col = np.where(chamfer[..., None], 204.0 + (brushed[..., None] - .5) * 16, 19.0 + (grit[..., None] - .5) * 6)
    kit.commit(area, float(arc[-1]), girth, where, col, (grit - .5) * 8e-6, np.where(chamfer, .24, .46), np.where(chamfer, 1.0, .35).astype(f32),
               np.ones_like(grit))


def paint_pod(area, arc, girth, zones):
    """The map pod's loop: aluminium bezel, a dark gap, the stitched leather hood, the moulded shell."""
    bezel, gap, hood_in, lip_end, wrap = zones
    a, b, where = kit.window(area, float(arc[-1]), girth)
    a, b = np.broadcast_arrays(a, b)
    peb, grit, brushed = grain(b, a), fbm(b * 2600, a * 2600, 2), vnoise(b * 55, a * 7000)
    col = LEATHER * (.84 + .2 * peb[..., None])
    h, rough, metal, ao = (peb - 1) * 5e-5, .6 + .14 * (1 - peb), np.zeros_like(peb), np.ones_like(peb)
    pitch, row = .0092, a - (lip_end + .006)                         # stitching just behind the lip, outside
    along = b % pitch - pitch / 2
    q = np.hypot(np.clip(np.abs(along) - .0030, 0, None), row) / .00085
    thread = q < 1
    twist = .5 + .5 * np.cos((along + row * 1.6) / .00042)
    h = np.where(thread, h + 4.5e-4 * np.sqrt(np.clip(1 - q * q, 0, 1)), h - 1.4e-4 * np.exp(-(row / .0022)**2))
    col = np.where(thread[..., None], THREAD * (.78 + .3 * twist[..., None]), col)
    rough = np.where(thread, .78, rough)
    shell = a > wrap                                                  # past the wrap's edge: satin plastic
    edge = np.exp(-((a - wrap) / .0008)**2)
    col = np.where(shell[..., None], 17.0 + (grit[..., None] - .5) * 7, col) * (1 - .5 * edge[..., None])
    h = np.where(shell, (grit - .5) * 2.4e-5, h) - 3e-4 * edge
    rough = np.where(shell, .56, rough)
    k = a < bezel                                                     # the bezel: brushed, bright on its chamfers
    col = np.where(k[..., None], 178.0 + (brushed[..., None] - .5) * 28, col)
    h, rough, metal = np.where(k, (brushed - .5) * 5e-6, h), np.where(k, .3 + (brushed - .5) * .14, rough), np.where(k, 1.0, metal)
    k = (a >= bezel) & (a < gap)
    col, rough, ao = np.where(k[..., None], 8.0, col), np.where(k, .8, rough), np.where(k, .5, ao)
    kit.commit(area, float(arc[-1]), girth, where, col, h, rough, metal.astype(f32), ao)


def rounded_rect(half_w, half_h, corner, per_side, per_corner):
    """Points and outward normals round a rounded rectangle, anticlockwise from the bottom's middle."""
    pts, nrm = [], []
    runs = [((0, -half_h), (half_w - corner, -half_h), (0, -1)), ((half_w, -half_h + corner), (half_w, half_h - corner), (1, 0)),
            ((half_w - corner, half_h), (-half_w + corner, half_h), (0, 1)), ((-half_w, half_h - corner), (-half_w, -half_h + corner), (-1, 0)),
            ((-half_w + corner, -half_h), (0, -half_h), (0, -1))]
    centres = [(half_w - corner, -half_h + corner, -90), (half_w - corner, half_h - corner, 0), (-half_w + corner, half_h - corner, 90),
               (-half_w + corner, -half_h + corner, 180)]
    for k, (p0, p1, n) in enumerate(runs):
        count = per_side if 0 < k < 4 else per_side // 2
        for t in np.linspace(0, 1, count + 1):
            pts.append((p0[0] + (p1[0] - p0[0]) * t, p0[1] + (p1[1] - p0[1]) * t))
            nrm.append(n)
        if k < 4:
            cx, cy, start = centres[k]
            for t in np.radians(start + np.linspace(0, 90, per_corner + 1)[1:-1]):
                pts.append((cx + corner * math.cos(t), cy + corner * math.sin(t)))
                nrm.append((math.cos(t), math.sin(t)))
    pts, nrm = np.array(pts), np.array(nrm, float)
    return pts, nrm, np.concatenate([[0], np.cumsum(np.hypot(*np.diff(pts, axis=0).T))])


def sweep(part, area, profile, base, frame, hint):
    """Run (offset, depth) rows round a rounded rectangle laid in a fitting's own plane; `hint`
    is how the profile's first run faces."""
    pts, nrm, around = base
    o, ux, uy, n = (np.array(v, float) for v in frame)
    prof = [np.broadcast_to(np.asarray(p, float), (len(pts), 2)) if np.ndim(p) == 1 else np.asarray(p, float) for p in profile]
    rows = []
    for row in prof:
        flat = pts + nrm * row[:, :1]
        rows.append(o + flat[:, :1] * ux + flat[:, 1:] * uy + row[:, 1:] * n)
    k = len(pts) * 3 // 4                                             # measure the profile on the fitting's left side
    line = np.array([row[k] for row in prof])
    arc = np.concatenate([[0], np.cumsum(np.hypot(*np.diff(line, axis=0).T))])
    i = min(len(pts) // 2, len(pts) - 2)
    across, depth = facing(np.array([row[i] for row in prof]), hint)
    part.patch(area, float(arc[-1]), float(around[-1]), np.array(rows), arc, around, across * (nrm[i, 0] * ux + nrm[i, 1] * uy) + depth * n)
    return arc, float(around[-1])


def binnacle():
    part = Part("Binnacle")
    # ---- the shell: fascia, the cowl's underside and stitched lip at full density, the rest coarse ----
    front, rear = kit.rect(8, 8, 1800, 1000), kit.rect(1824, 8, 216, 400)
    cheek = np.radians(np.linspace(0, 90, 7)[1:])
    xs = np.concatenate([-(L.HALF_W - .024 + .024 * np.sin(cheek[::-1])), np.linspace(-(L.HALF_W - .024), L.HALF_W - .024, 121),
                         L.HALF_W - .024 + .024 * np.sin(cheek)])
    shrink = np.concatenate([1 - .24 * (1 - np.cos(cheek[::-1])), np.ones(121), 1 - .24 * (1 - np.cos(cheek))])
    xs, shrink = np.concatenate([[xs[0]], xs, [xs[-1]]]), np.concatenate([[0], shrink, [0]])    # ... and a flat end each side
    loops = []
    for x, s in zip(xs, shrink):
        loop, _ = section(x)
        centre = np.array([(lip(x) + L.D_BACK) / 2, (top(x) + L.Y_BOTTOM) / 2])
        loop = centre + (loop - centre) * s
        loops.append([L.to_panel(x, y, d) for d, y in loop])
    loops = np.array(loops)                                           # [station][profile point]
    width = 2 * L.HALF_W
    part.patch(front, FRONT_LEN, width, loops[:, :FRONT].transpose(1, 0, 2), _ARC0[:FRONT], xs + L.HALF_W, (0, 0, 1))
    rear_rows = np.concatenate([loops[:, FRONT - 1:], loops[:, :1]], axis=1).transpose(1, 0, 2)
    rear_arc = np.concatenate([_ARC0[FRONT - 1:] - _ARC0[FRONT - 1], [REAR_LEN]])
    part.patch(rear, REAR_LEN, width, rear_rows, rear_arc, xs + L.HALF_W, (0, .4, -1))
    paint_front(front)
    paint_rear(rear, REAR_LEN, width)

    # ---- the tubes ----
    rings = [kit.rect(*r) for r in ((8, 1020, 760, 96), (780, 1020, 600, 96), (1392, 1020, 600, 96), (8, 1128, 480, 96), (500, 1128, 480, 96))]
    funnels = [kit.rect(*r) for r in ((992, 1128, 640, 150), (8, 1236, 480, 130), (500, 1236, 480, 130), (992, 1290, 420, 110), (1424, 1290, 420, 110))]
    barrels = [kit.rect(*r) for r in ((8, 1412, 560, 80), (580, 1412, 440, 64), (1032, 1412, 440, 64), (1484, 1412, 260, 44), (1756, 1412, 260, 44))]
    caps, stems = kit.rect(1824, 420, 216, 64), kit.rect(1824, 492, 216, 20)
    occluders = Part("Occluders")
    spare = kit.rect(1824, 520, 16, 16)
    for index, gauge in enumerate(L.GAUGES):
        key, gx, gy, ro, mouth, recess = gauge
        frame = L.frame(gx, gy)
        rg, rf, face = L.glass_radius(ro), L.face_radius(ro), mouth - recess
        # a tube that stands under a bigger neighbour stops inside that neighbour's wall (L.OVER)
        under = None
        if index in L.OVER:
            over = L.GAUGES[L.OVER[index]]
            beside = L.frame(over[1], over[2])
            under = (beside[0], beside[3], over[3] - L.CUT)
        arc, girth = part.lathe(barrels[index], [(ro - L.WALL, -.006), (ro - L.WALL, mouth - .016)], 96, frame, "out", under)
        paint_barrel(barrels[index], float(arc[-1]), girth)
        arc, girth = part.lathe(rings[index], [(ro - L.WALL, mouth - .016), (ro, mouth - .014), (ro, mouth - .003), (ro - .003, mouth),
                                               (rg + .0025, mouth), (rg, mouth - .0025), (rg, mouth - L.SEAT)], 128, frame, "out", under)
        paint_ring(rings[index], arc, girth, 3.1 * index)
        arc, girth = part.lathe(funnels[index], [(rg, mouth - L.SEAT), (rg - .0025, mouth - L.SEAT - .001), (rf + .0015, face + .003),
                                                 (rf, face + .0005), (rf, face - .002)], 128, frame, "in", under)
        paint_funnel(funnels[index], float(arc[-1]), girth)
        rc = .19 * rf
        up = face + L.CAP_UP
        cap_arc, cap_girth = part.lathe(caps, [(rc, up), (rc, up + .0055), (rc - .0022, up + .0075), (rc * .5, up + .0087), (.0004, up + .0091)],
                                        40, frame, "out")
        stem_arc, stem_girth = part.lathe(stems, [(.36 * rc, face - .001), (.36 * rc, up + .001)], 16, frame, "out")
        occluders.lathe(spare, [(rf + .002, face), (.0004, face)], 48, frame, "front")
    paint_cap(caps, cap_arc, cap_girth)
    paint_barrel(stems, float(stem_arc[-1]), stem_girth)

    # ---- the LCD strips' frames: flat modules standing just proud of the curved fascia ----
    for index, (key, wx, wy, hw, hh, off) in enumerate(L.WINDOWS):
        area = kit.rect(8, 1500 + 44 * index, 1000, 36)
        o, ux, uy, n = (np.array(v, float) for v in L.frame(wx, wy))
        frame = (o + off * n, ux, uy, n)
        base = rounded_rect(hw, hh, .004, 16, 5)
        arc, girth = sweep(part, area, [(.0075, -.020), (.0075, .0030), (.0060, .0045), (.0030, .0045), (.0012, .0030), (.0012, .0004)], base, frame, "out")
        paint_frame(area, arc, girth, ((1, 2), (3, 4)))
        occluders.patch(spare, 1, 1, [[frame[0] + sx * hw * ux + sy * hh * uy for sx in (-1, 1)] for sy in (-1, 1)], (0, 1), (0, 1), n)
    return part, occluders


def map_pod():
    """The map's enclosure, in the screen's own frame: x across, y up, z toward the pilot."""
    part, occluders = Part("MapPod"), Part("PodOccluders")
    area = kit.rect(8, 1592, 1700, 440)
    base = rounded_rect(.111, .111, .008, 24, 7)
    pts = base[0]
    rise = smooth((pts[:, 1] / .111 + .6) / 1.4)                      # the hood: deepest over the top, short below
    zf = .008 + .044 * rise
    const = lambda e, z: (e, z)
    nose = [np.stack([.0175 - .005 * math.cos(t) + 0 * zf, zf - .006 + .005 * math.sin(t)], -1) for t in np.radians((30, 60, 90, 120, 150, 180))]
    profile = [const(.0005, 0), const(.0005, .0030), const(.0020, .0045), const(.0085, .0045), const(.0100, .0032), const(.0100, .0015),
               const(.0125, .0015), np.stack([.0125 + 0 * zf, zf - .006], -1)] + nose + \
              [const(.0225, -.012), const(.0225, -.030), const(.0190, -.048), const(.0100, -.060), const(-.0060, -.066)]
    frame = ((0, 0, 0), (1, 0, 0), (0, 1, 0), (0, 0, 1))
    arc, girth = sweep(part, area, profile, base, frame, "in")
    paint_pod(area, arc, girth, (float(arc[5]), float(arc[6]), float(arc[7]), float(arc[13]), float(arc[14]) + .004))
    # the back plate, and the screen the game draws on (so the bake knows it is there)
    back = kit.rect(1824, 544, 64, 64)
    rim = np.array([(p[0] - .006 * n_[0], p[1] - .006 * n_[1], -.066) for p, n_ in zip(pts, base[1])])
    part.patch(back, 1, 1, np.array([rim, 0 * rim + (0, 0, -.068)]), (0, 1), np.linspace(0, 1, len(pts)), (0, 0, -1))
    paint_barrel(back, 1, 1)
    occluders.patch(back, 1, 1, [[(-.111, -.111, 0), (.111, -.111, 0)], [(-.111, .111, 0), (.111, .111, 0)]], (0, 1), (0, 1), (0, 0, 1))
    return part, occluders


def bake(objects, hidden, image, clear):
    """Path trace ambient occlusion for these objects into the atlas, with the others out of sight."""
    scene = bpy.context.scene
    for obj in bpy.data.objects:
        obj.hide_render = obj in hidden
        obj.select_set(False)
    scene.render.bake.use_clear = clear
    for obj in objects:
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.bake(type="AO")
        obj.select_set(False)
        scene.render.bake.use_clear = False


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
    scene.world.light_settings.distance = .35

    image = bpy.data.images.new("Occlusion", BAKE, BAKE, alpha=True, is_data=True)
    image.pixels.foreach_set(np.tile(np.array((1, 1, 1, 0), f32), BAKE * BAKE))
    target = bpy.data.materials.new("BakeTarget")
    target.use_nodes = True
    node = target.node_tree.nodes.new("ShaderNodeTexImage")
    node.image = image
    target.node_tree.nodes.active = node

    body, body_occluders = binnacle()
    pod, pod_occluders = map_pod()
    objects = [p.mesh(target) for p in (body, body_occluders, pod, pod_occluders)]
    bake([objects[0]], [objects[2], objects[3]], image, False)
    bake([objects[2]], [objects[0], objects[1]], image, False)
    pixels = np.empty(BAKE * BAKE * 4, f32)
    image.pixels.foreach_get(pixels)
    pixels = pixels.reshape(BAKE, BAKE, 4)[::-1]                     # Blender's rows run bottom-up
    scale = kit.RES // BAKE
    lit = np.kron(np.where(pixels[..., 3] > .5, pixels[..., 0], 1.0), np.ones((scale, scale), f32))
    lit = np.clip(box(lit.astype(f32), 1, 1), 0, 1)
    print("BAKE", f"{(pixels[..., 3] > .5).mean() * 100:.0f}% of the atlas baked, occlusion {lit.min():.2f}-{lit.max():.2f}, mean {lit.mean():.2f}", flush=True)
    kit.BASE[:] = np.clip(kit.BASE * (.5 + .5 * lit[..., None]), 0, 255)
    kit.ORM[..., 0] = np.clip(kit.ORM[..., 0] * lit, 0, 255)
    kit.ORM[..., 1] = np.clip(kit.ORM[..., 1] + 30 * (1 - lit), 0, 255)

    with tempfile.TemporaryDirectory() as tmp:
        folder = Path(tmp)
        for name, pixels8 in (("GaugesHD_Base", kit.BASE), ("GaugesHD_Normal", kit.NORMAL), ("GaugesHD_ORM", kit.ORM)):
            png(folder / (name + ".png"), pixels8)
        material = pbr(folder, "GaugesHD")
        for obj in (objects[0], objects[2]):
            obj.data.materials.clear()
            obj.data.materials.append(material)
            obj.hide_render = False
        for obj in (objects[1], objects[3]):
            bpy.data.objects.remove(obj)
        bpy.ops.export_scene.gltf(filepath=str(OUTPUT), export_tangents=True, export_animations=False,
                                  export_cameras=False, export_lights=False)
    print("Wrote", OUTPUT, OUTPUT.stat().st_size, "bytes")


if __name__ == "__main__":
    main()
