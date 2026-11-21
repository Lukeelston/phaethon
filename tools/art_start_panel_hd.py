"""Realism spike: the start panel under the roof's header (Luke, after flying the code-built one:
"polishing the startup switches so that they are on quality par with the rest of the cockpit").

    blender --background --python tools/art_start_panel_hd.py [-- --res 2048] [-- --samples 64]

Two pods hung from the header rail, in the frame vr/overhead_panel.gd gives each of them: x across
(the pilot's right), y up the face as the pilot sees it, z out of the face. Same envelope, control
positions and pivots as the code-built panel it replaces.
  PodL, PodR      a housing with a recessed, black-anodised faceplate; on it the toggles' lock rings,
                  hex nuts and bushings, the guard's hinge, the lamps' bezels and lenses, the start
                  button's knurled bezel; the legends engraved and paint-filled, hazard striping
                  round the guarded switch
  ClampsL/R       two standoffs and their collars round the rail, and the pod's pigtail up to one
  Bat             the bat handle of 1 BATT and 2 ENGINE, about its pivot
  Paddle          4 PARK's lever and its yellow paddle, about its pivot
  Guard           the red cover over 2 ENGINE, about its hinge pin
  Cap             the start button's cap, at rest
Forms of half a millimetre and up are geometry; grit, wear, knurl, engraving, threads and screws are
synthesised in surface metres; the occlusion is path traced over the finished shapes. A fourth map
(the material's emission) tells the game's finish what lights up: red, the paint that is lit from
behind; green, how bright a lamp's lens is there; blue, which lamp it is. Lettering is set in Inter
(SIL Open Font License) from Blender's own fonts folder; only the drawn legends are kept.
Writes godot/art/cockpit/start_panel_hd.glb.
"""
import math
import sys
import tempfile
from pathlib import Path

import bpy
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import art_bezel_hd as kit  # noqa: E402  the atlas and its helpers
from art_coaming_hd import ARGS, box, f32, fbm, mix, png, smooth, vnoise  # noqa: E402
from art_console_hd import paint_small  # noqa: E402
from art_gauges_hd import Part, bake, paint_frame, rounded_rect, sweep  # noqa: E402
from art_grip_hd import pbr  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "godot/art/cockpit/start_panel_hd.glb"
SAMPLES = int(ARGS[ARGS.index("--samples") + 1]) if "--samples" in ARGS else 64
BAKE = kit.RES // 2
GLOW = np.zeros((kit.RES, kit.RES, 3), np.uint8)       # R lit paint, G a lamp's lens, B which lamp

# ---- the panel's own measures (vr/overhead_panel.gd has the same) ----
EYE = np.array((0.0, .12, .6))                         # the seated eye, canopy space
CABIN = np.array((0.0, .16, .45))                      # what "inward" means for the rail's section (art_roof_hd.py, less the rig's 0.6)
POD_W, DROP, AFT, TOE = .6, .064, .012, .5
BODY_W, BODY_T, BODY_H, BODY_Y = .185, .026, .104, -.012
CONTROLS = {"batt": (-1, -.046), "engine": (-1, .044), "start": (1, -.043), "park": (1, .05)}
LEGENDS = {"batt": "BATT", "engine": "ENGINE", "start": "START", "park": "PARK"}
NUMBERS = {"batt": "1", "engine": "2", "start": "3", "park": "4"}
MARKS = {"batt": ("ON", "OFF"), "engine": ("ON", "OFF"), "park": ("SET", "OFF")}
LAMPS = {"standby": .25, "batt": .5, "engine": .75, "park": 1.0}     # the lens map's blue: which lamp
FACE_Z, RIM_Z = .0005, .0020                           # the faceplate, and the housing's rim round it
PLATE_W, PLATE_H = .177, .096                          # the faceplate inside the rim
HINGE = (.026, .005)                                   # the guard's hinge pin: y, z
LEGEND_Y, LAMP_Y, STANDBY_X = -.0445, -.0535, -.028    # a legend's middle, a lamp's, and the standby lamp beside 1 BATT
RAIL = (.020, .016)                                    # the header rail's section: toward the cabin, and across


def unit(v):
    v = np.asarray(v, float)
    return v / np.linalg.norm(v)


def header_at(w):
    return np.array((.41 * w, .47 - .035 * w * w, .30 + .14 * w * w))


def pod_frame(side):
    """A pod's axes (columns x, y, z) and origin in canopy space: OverheadPanel.pod_frame."""
    w = POD_W * side
    at = header_at(w) + np.array((0.0, -DROP, AFT))
    to_eye = unit(EYE - at)
    along = unit(header_at(w + .01) - header_at(w - .01))
    square = unit(np.cross((0, 1, 0), to_eye))
    angle = math.acos(float(np.clip(along @ square, -1, 1)))
    across = unit((math.sin((1 - TOE) * angle) * along + math.sin(TOE * angle) * square) / math.sin(angle))
    out = unit(to_eye - across * (to_eye @ across))
    return np.stack([across, np.cross(out, across), out], axis=1), at


# ---- the atlas ----
class Shelf:
    """Rows of rectangles in a region of the atlas, in its 2048 units: a new one goes in the first row it fits."""

    def __init__(self, x, y, w, h):
        self.x0, self.y0, self.w, self.h = x, y, w, h
        self.rows, self.y = [], y                                     # [top, height, the next free x]

    def take(self, w, h, gap=12):
        for row in self.rows:
            if h <= row[1] and row[2] + w <= self.x0 + self.w:
                area = kit.rect(row[2], row[0], w, h)
                row[2] += w + gap
                return area
        if self.y + h > self.y0 + self.h or w > self.w:
            return None
        self.rows.append([self.y, h, self.x0 + w + gap])
        self.y += h + gap
        return kit.rect(self.x0, self.y - h - gap, w, h)


SHELVES = [Shelf(1068, 12, 972, 1164), Shelf(12, 1514, 2028, 526), Shelf(1428, 1192, 612, 310)]


def take(length, width, density=5200.0, least=12):
    """A rectangle for a patch `length` metres down its rows and `width` across, at so many texels a metre."""
    w, h = max(least, round(width * density)), max(least, round(length * density))
    for shelf in SHELVES:
        area = shelf.take(w, h)
        if area:
            return area
    raise SystemExit("the atlas is full: %d x %d" % (w, h))


def lit(where, paint=None, lens=None, lamp=0.0):
    if paint is not None:
        GLOW[where][..., 0] = np.clip(paint, 0, 1) * 255
    if lens is not None:
        GLOW[where][..., 1] = np.clip(lens, 0, 1) * 255
        GLOW[where][..., 2] = round(lamp * 255)


# ---- lettering ----
class Type:
    """Legends as outlines: a text object's filled faces, scanned into a mask."""
    SS = 4

    def __init__(self):
        self.font, self.cache = None, {}
        for path in (Path(bpy.utils.system_resource("DATAFILES", path="fonts")) / "Inter.woff2", ROOT / "godot/art/signs/RG2014D.ttf"):
            try:
                self.font = bpy.data.fonts.load(str(path))
                break
            except RuntimeError:
                continue
        self.cap = float(self.outline("H")[0][:, 1].max())
        print("TYPE", self.font.name if self.font else "Blender's own", "capitals %.3f of the em" % self.cap, flush=True)

    def outline(self, body):
        if body not in self.cache:
            curve = bpy.data.curves.new("legend", "FONT")
            curve.body, curve.size, curve.align_x, curve.space_character = body, 1.0, "CENTER", 1.1
            if self.font:
                curve.font = self.font
            obj = bpy.data.objects.new("legend", curve)
            bpy.context.collection.objects.link(obj)
            shown = obj.evaluated_get(bpy.context.evaluated_depsgraph_get())
            mesh = shown.to_mesh()
            mesh.calc_loop_triangles()
            points = np.array([v.co[:2] for v in mesh.vertices], float)
            tris = np.array([t.vertices[:] for t in mesh.loop_triangles], int)
            shown.to_mesh_clear()
            bpy.data.objects.remove(obj)
            bpy.data.curves.remove(curve)
            self.cache[body] = (points, tris)
        return self.cache[body]

    def width(self, body, cap):
        points = self.outline(body)[0]
        return float(points[:, 0].max() - points[:, 0].min()) * cap / self.cap


class Canvas:
    """The lettering of one flat area: x across and y up in the part's own metres."""

    def __init__(self, area, length, width, left, top):
        self.rows, self.cols = area[3] + 6, area[2] + 6                # kit.window's shape: three texels of bleed all round
        self.kx, self.ky, self.left, self.top = area[2] / width * Type.SS, area[3] / length * Type.SS, left, top
        self.bits = np.zeros((self.rows * Type.SS, self.cols * Type.SS), bool)

    def text(self, face, body, x, y, cap):
        """Set `body` with capitals `cap` metres high, the middle of its baseline at (x, y)."""
        points, tris = face.outline(body)
        k = cap / face.cap
        px = (points[:, 0] * k + x - self.left) * self.kx + 3 * Type.SS
        py = (self.top - points[:, 1] * k - y) * self.ky + 3 * Type.SS
        for tri in tris:
            xs, ys = px[tri], py[tri]
            x0, x1 = max(0, int(xs.min())), min(self.bits.shape[1], int(xs.max()) + 2)
            y0, y1 = max(0, int(ys.min())), min(self.bits.shape[0], int(ys.max()) + 2)
            d = (ys[1] - ys[2]) * (xs[0] - xs[2]) + (xs[2] - xs[1]) * (ys[0] - ys[2])
            if x0 >= x1 or y0 >= y1 or abs(d) < 1e-12:
                continue
            gx, gy = np.meshgrid(np.arange(x0, x1) + .5, np.arange(y0, y1) + .5)
            l1 = ((ys[1] - ys[2]) * (gx - xs[2]) + (xs[2] - xs[1]) * (gy - ys[2])) / d
            l2 = ((ys[2] - ys[0]) * (gx - xs[2]) + (xs[0] - xs[2]) * (gy - ys[2])) / d
            self.bits[y0:y1, x0:x1] |= (l1 >= 0) & (l2 >= 0) & (l1 + l2 <= 1)

    def mask(self):
        return self.bits.reshape(self.rows, Type.SS, self.cols, Type.SS).mean((1, 3)).astype(f32)


# ---- forms ----
def frame_z(x=0.0, y=0.0, z=0.0):
    """A fitting standing on the face at (x, y): its axis out of the face."""
    return (x, y, z), (1, 0, 0), (0, 1, 0), (0, 0, 1)


def loop(points):
    """An anticlockwise outline as sweep() wants it: points (closed), outward normals, arc length."""
    pts = np.array(list(points) + [points[0]], float)
    inner = pts[:-1]
    tangent = np.roll(inner, -1, 0) - np.roll(inner, 1, 0)
    tangent /= np.linalg.norm(tangent, axis=1, keepdims=True)
    normal = np.stack([tangent[:, 1], -tangent[:, 0]], -1)
    return pts, np.concatenate([normal, normal[:1]]), np.concatenate([[0], np.cumsum(np.hypot(*np.diff(pts, axis=0).T))])


def arc(cx, cy, r, a0, a1, n=5):
    return [(cx + r * math.cos(t), cy + r * math.sin(t)) for t in np.radians(np.linspace(a0, a1, n + 1))]


def planar(part, area, length, width, points, ab, out):
    """A grid of quads whose place in the area is given point by point (a down its rows, b across)."""
    points, ab = np.asarray(points, float), np.asarray(ab, float)
    rows, cols = points.shape[:2]
    start = len(part.xyz)
    part.xyz += [(p[0], -p[2], p[1]) for p in points.reshape(-1, 3)]
    part.uv += [kit.uv_of(area, length, width, float(a), float(b)) for a, b in ab.reshape(-1, 2)]
    j, i = min(rows // 2, rows - 2), min(cols // 2, cols - 2)
    normal = np.cross(points[j, i + 1] - points[j, i], points[j + 1, i] - points[j, i])
    order = (0, 1, cols + 1, cols) if normal @ np.asarray(out, float) > 0 else (cols, cols + 1, 1, 0)
    part.faces += [tuple(start + r * cols + c + k for k in order) for r in range(rows - 1) for c in range(cols - 1)]


def fan(part, area, length, width, ring, ab, out):
    """One many-sided face over a ring of points, mapped point by point."""
    ring = np.asarray(ring, float)
    start = len(part.xyz)
    part.xyz += [(p[0], -p[2], p[1]) for p in ring]
    part.uv += [kit.uv_of(area, length, width, float(a), float(b)) for a, b in ab]
    normal = np.sum(np.cross(ring, np.roll(ring, -1, axis=0)), axis=0)
    index = list(range(start, start + len(ring)))
    part.faces.append(tuple(index if normal @ np.asarray(out, float) > 0 else index[::-1]))


def cap(part, area, size, base, frame, depth, out, inset=0.0):
    """Close a swept outline with a flat face at `depth`, mapped flat into a square area `size` metres across."""
    pts, nrm, _ = base
    o, ux, uy, n = (np.array(v, float) for v in frame)
    flat = (pts - nrm * inset)[:-1]
    ring = o + flat[:, :1] * ux + flat[:, 1:] * uy + depth * n
    mid = (flat.max(0) + flat.min(0)) / 2
    fan(part, area, size, size, ring, [(size / 2 - (y - mid[1]), size / 2 + (x - mid[0])) for x, y in flat], out)


def plain(area, length, width, colour, rough, metal=0.0, grit=6.0, bump=8e-6):
    """A plain finish with its grit: what an end face or an inside wall is given."""
    a, b, where = kit.window(area, length, width)
    a, b = np.broadcast_arrays(a, b)
    g = fbm(b * 5200, a * 5200, 2)
    col = np.array(colour, f32) + (g[..., None] - .5) * grit
    kit.commit(area, length, width, where, col, (g - .5) * bump, np.full(a.shape, rough, f32), np.full(a.shape, metal, f32), np.ones(a.shape, f32))


# ---- paint ----
def box_distance(x, y, half_w, half_h, corner):
    """Signed distance to a rounded rectangle round the origin (negative inside)."""
    qx, qy = np.abs(x) - (half_w - corner), np.abs(y) - (half_h - corner)
    return np.hypot(np.clip(qx, 0, None), np.clip(qy, 0, None)) + np.minimum(np.maximum(qx, qy), 0) - corner


def line(d, half):
    """An engraved line `half` metres either side of where d is 0, soft over about a texel."""
    return smooth(1 - (np.abs(d) - half) / .00016)


def paint_face(area, side, face):
    """A pod's faceplate: black anodising worn bright at its rim, each control ringed, marked and
    named in engraving filled with white paint, hazard stripes round the guarded switch."""
    a, b, where = kit.window(area, PLATE_H, PLATE_W)
    a, b = np.broadcast_arrays(a, b)
    x, y = b - PLATE_W / 2, BODY_Y + PLATE_H / 2 - a
    canvas = Canvas(area, PLATE_H, PLATE_W, -PLATE_W / 2, BODY_Y + PLATE_H / 2)
    seed = 3.7 * side
    grit = fbm((x + seed) * 5200, y * 5200, 2)
    edge = np.minimum(np.minimum(a, PLATE_H - a), np.minimum(b, PLATE_W - b))
    bright = smooth((fbm((x + seed) * 400, y * 400) + .7 * np.exp(-edge / .0007) - 1.14) * 9) * smooth((edge - .0004) / .0005)
    ao = np.ones_like(grit)
    fill = np.zeros(a.shape, f32)
    rub = np.zeros(a.shape, f32)                                     # where fingers find each control
    for control, (pod, cx) in CONTROLS.items():
        if pod != side:
            continue
        r = np.hypot(x - cx, y)
        rub = np.maximum(rub, np.exp(-(r / .028)**2))
        if control == "start":
            ao *= 1 - .55 * np.exp(-np.clip(r - .0345, 0, None) / .004)
        else:
            fill = np.maximum(fill, line(r - .0150, .00022))
            ao *= 1 - .5 * np.exp(-np.clip(r - .0118, 0, None) / .003)
            canvas.text(face, MARKS[control][0], cx, .0167, .0032)
            canvas.text(face, MARKS[control][1], cx, -.0199, .0032)
            ao *= 1 - .45 * np.exp(-np.clip(box_distance(x - cx, y - LAMP_Y, .0172, .0039, .001), 0, None) / .0025)
        capital, ring_r, gap = .0046, .0041, .0024                   # the legend: its number in a ring, then its name
        name_w = face.width(LEGENDS[control], capital)
        left = cx - (2 * ring_r + gap + name_w) / 2
        fill = np.maximum(fill, line(np.hypot(x - left - ring_r, y - LEGEND_Y) - ring_r, .0002))
        canvas.text(face, NUMBERS[control], left + ring_r, LEGEND_Y - .0031 / 2, .0031)
        canvas.text(face, LEGENDS[control], left + 2 * ring_r + gap + name_w / 2, LEGEND_Y - capital / 2, capital)
    stripe = np.zeros(a.shape, f32)
    if side < 0:
        sx = CONTROLS["batt"][1] + STANDBY_X                          # the standby lamp, and its name under it
        canvas.text(face, "STBY", sx, -.0116, .0028)
        ao *= 1 - .5 * np.exp(-np.clip(np.hypot(x - sx, y) - .0052, 0, None) / .002)
        gx = CONTROLS["engine"][1]                                    # hazard stripes round the guard's footprint
        d = box_distance(x - gx, y - .0012, .0228, .0340, .003)
        band = smooth(-d / .00018) * smooth((d + .0034) / .00018)
        chipped = smooth((fbm(x * 1700, y * 1700, 3) + .3 * np.exp(-np.abs(d + .0017) / .0012) - .93) * 12)
        stripe = band * (((x + y) / .0052) % 1 < .5) * (1 - chipped)
        ao *= 1 - .35 * np.exp(-np.clip(box_distance(x - gx, y - HINGE[0] - .0025, .0215, .0045, .001), 0, None) / .002)
    fill = np.maximum(fill, canvas.mask())
    polish = rub * smooth((fbm((x + seed) * 120, y * 120, 3) - .35) * 2.5)
    col = mix(np.array((17, 19, 22), f32) + (grit[..., None] - .5) * 7 + 5 * polish[..., None], (184, 187, 191), bright)
    h, rough, metal = (grit - .5) * 9e-6 * (1 - .6 * polish), .52 - .16 * bright - .14 * polish, .25 + .7 * bright
    col = mix(col, np.array((226, 172, 22), f32) + (grit[..., None] - .5) * 10, stripe)
    h, rough, metal = h + 8e-6 * stripe, rough + .06 * stripe, metal * (1 - stripe)
    col = mix(col, np.array((230, 230, 222), f32), fill)
    h, rough, metal = h - 7e-5 * fill, rough + (.56 - rough) * fill, metal * (1 - fill)
    for sx in (-.0815, .0815):
        for sy in (BODY_Y + .0415, BODY_Y - .0415):
            col, h, rough, metal = kit.screw(x, y, (sx, sy), .0027, col, h, rough, metal)
    kit.commit(area, PLATE_H, PLATE_W, where, col, h, rough, metal, ao)
    lit(where, paint=fill)


def paint_shell(area, arc, girth, seed):
    """The housing round the faceplate: pebbled graphite coating, worn to metal on its front
    chamfer, a machined bright line where the rim turns in, the shell's split line half way back."""
    a, b, where = kit.window(area, float(arc[-1]), girth)
    a, b = np.broadcast_arrays(a, b)
    pebble = fbm((b + seed) * 2400, a * 2400, 2)
    corner = np.minimum(np.abs(a - arc[2]), np.abs(a - arc[3]))
    worn = smooth((.6 * fbm((b + seed) * 90, a * 500, 3) + .4 * fbm((b + seed) * 700, a * 700, 2) + .5 * np.exp(-corner / .0005) - 1.0) * 7)
    scuff = smooth((fbm((b + seed) * 40, a * 60) - .66) * 7) * (a < arc[2])
    col = mix(np.array((33, 35, 40), f32) * (.9 + .2 * pebble[..., None]), (150, 154, 160), .75 * worn)
    col = mix(col, (60, 62, 66), .5 * scuff)
    h, rough, metal = (pebble - .5) * 2.6e-5 * (1 - worn), .72 - .24 * worn - .12 * scuff, .1 + .8 * worn
    seam = np.exp(-((a - arc[1] - .0115) / .00035)**2)
    h, col = h - 3.5e-4 * seam, col * (1 - .5 * seam[..., None])
    inner = (a > arc[4]) & (a < arc[5])                               # the rim's inner chamfer, machined after coating
    brushed = vnoise(b * 50, a * 9000)
    col = np.where(inner[..., None], 200.0 + (brushed[..., None] - .5) * 16, col)
    h, rough, metal = np.where(inner, 0, h), np.where(inner, .24, rough), np.where(inner, 1.0, metal)
    wall = a >= arc[5]
    col = np.where(wall[..., None], 12.0, col)
    ao = np.where(wall, .5, .6 + .4 * smooth(a / .004))
    kit.commit(area, float(arc[-1]), girth, where, col, h, rough, metal.astype(f32), ao.astype(f32))


def paint_bezel(area, arc, girth):
    """The start button's bezel, machined from bar: a satin flange, a diamond-knurled wall, a turned
    top land between two polished chamfers, and a black throat down to the ring of lights."""
    a, b, where = kit.window(area, float(arc[-1]), girth)
    a, b = np.broadcast_arrays(a, b)
    brushed = vnoise(b * 60, a * 6000) * .6 + vnoise(b * 9, a * 900 + 40) * .4
    turned = np.cos(2 * math.pi * a / .00028) * .5 + .5
    col = np.full(a.shape + (3,), 176.0, f32) + (brushed[..., None] - .5) * 26
    h, rough, metal = (brushed - .5) * 5e-6, .32 + (brushed - .5) * .14, np.ones(a.shape, f32)
    turns, pitch = round(girth / .0015), .0015                         # the knurl closes on itself round the wall
    g1 = np.abs((turns * b / girth + a / pitch) % 1 - .5)
    g2 = np.abs((turns * b / girth - a / pitch) % 1 - .5)
    peak = smooth(np.minimum(g1, g2) * 2 / .8)
    k = (a > arc[3] + .0004) & (a < arc[4] - .0004)
    col = np.where(k[..., None], 128.0 + 78 * peak[..., None] + (brushed[..., None] - .5) * 10, col)
    h, rough = np.where(k, .00024 * peak, h), np.where(k, .44 - .16 * peak, rough)
    ao = np.where(k, .62 + .38 * peak, 1.0)
    for lo, hi in ((1, 2), (4, 5), (6, 7)):                           # chamfers: polished
        k = (a > arc[lo]) & (a < arc[hi])
        col, rough, h = np.where(k[..., None], 214.0 + (brushed[..., None] - .5) * 8, col), np.where(k, .18, rough), np.where(k, 0, h)
    k = (a > arc[5]) & (a < arc[6])                                   # the top land: turned
    col, rough, h = np.where(k[..., None], 186.0 + 14 * turned[..., None], col), np.where(k, .28 + .1 * turned, rough), np.where(k, (turned - .5) * 3e-6, h)
    k = (a > arc[2]) & (a < arc[3])
    col, rough = np.where(k[..., None], 170.0 + 10 * turned[..., None], col), np.where(k, .36, rough)
    k = a >= arc[7]                                                   # the throat: black
    col, rough, metal, ao = np.where(k[..., None], 9.0, col), np.where(k, .7, rough), np.where(k, 0.0, metal), np.where(k, .55, ao)
    ao = ao * (.6 + .4 * smooth(a / .0025))
    kit.commit(area, float(arc[-1]), girth, where, col, h.astype(f32), rough.astype(f32), metal.astype(f32), ao.astype(f32))


RED = np.array((158, 22, 14), f32)


def paint_cap_side(area, arc, girth):
    a, b, where = kit.window(area, float(arc[-1]), girth)
    a, b = np.broadcast_arrays(a, b)
    turned, streak = np.cos(2 * math.pi * a / .0003) * .5 + .5, vnoise(b * 50, a * 7000)
    worn = smooth((fbm(b * 500, a * 500, 3) + .75 * np.exp(-np.abs(a - arc[2]) / .0007) - 1.08) * 9)
    col = mix(RED * (.9 + .12 * turned[..., None]) + (streak[..., None] - .5) * 8, (204, 206, 209), worn)
    kit.commit(area, float(arc[-1]), girth, where, col, (turned - .5) * 3e-6, .3 + (turned - .5) * .08 - .08 * worn, np.full(a.shape, .9, f32),
               (.45 + .55 * smooth((a - .0035) / .005)).astype(f32))


def paint_cap_top(area, size, face):
    """The cap's face: red anodising spun on the lathe, an engraved ring, and START cut through it."""
    a, b, where = kit.window(area, size, size)
    a, b = np.broadcast_arrays(a, b)
    x, y = b - size / 2, size / 2 - a
    r = np.hypot(x, y)
    spun = np.cos(2 * math.pi * r / .00032) * .5 + .5
    sector = vnoise(np.arctan2(y, x) * 40, r * 900)
    worn = smooth((fbm(x * 500, y * 500, 3) + .6 * np.exp(-np.clip(.0166 - r, 0, None) / .0006) - 1.12) * 9)
    canvas = Canvas(area, size, size, -size / 2, size / 2)
    canvas.text(face, "START", 0.0, -.0026, .0052)
    fill = np.maximum(canvas.mask(), line(r - .0146, .00022))
    col = mix(RED * (.9 + .12 * spun[..., None]) + (sector[..., None] - .5) * 10, (204, 206, 209), worn)
    col = mix(col, np.array((238, 236, 228), f32), fill)
    kit.commit(area, size, size, where, col, (spun - .5) * 3e-6 - 7e-5 * fill, .3 + (spun - .5) * .08 + (.5 - .3) * fill, .9 * (1 - fill), np.ones(a.shape, f32))
    lit(where, paint=fill)


def paint_guard(area, length, width, worn=(False, False), spans=None):
    """Red enamel over a pressing: a little orange peel, chipped to metal at an edge fingers catch
    (`worn`: its first row, its last; `spans`: only between these places across it)."""
    a, b, where = kit.window(area, length, width)
    a, b = np.broadcast_arrays(a, b)
    grit, peel = fbm(b * 5200, a * 5200, 2), fbm(b * 700, a * 700, 2)
    rim = np.minimum(a if worn[0] else 1.0, (length - a) if worn[1] else 1.0) + 0 * a
    if spans:
        rim = np.where(np.any([(b > lo) & (b < hi) for lo, hi in spans], axis=0), rim, 1.0)
    chip = smooth((.55 * fbm(b * 260, a * 260, 3) + .45 * fbm(b * 2200, a * 2200, 2) + .62 * np.exp(-rim / .00045) - 1.0) * 10)
    col = mix(np.array((154, 24, 16), f32) * (.92 + .16 * fbm(b * 60, a * 60)[..., None]), (176, 178, 181), chip)
    kit.commit(area, length, width, where, col, (peel - .5) * 1.6e-5 * (1 - chip) - 2e-5 * chip, .32 + .2 * chip + (grit - .5) * .06, chip.astype(f32), np.ones(a.shape, f32))


def paint_paddle(area, arc, girth):
    """Moulded yellow: grip ribs across it, dirt in the cuts, its edges rubbed pale."""
    a, b, where = kit.window(area, float(arc[-1]), girth)
    a, b = np.broadcast_arrays(a, b)
    grit = fbm(b * 5200, a * 5200, 2)
    body = smooth((a - arc[2] - .001) / .001) * smooth((arc[3] - .001 - a) / .001)
    rib = (np.cos(2 * math.pi * (a - arc[2]) / .0026) * .5 + .5) * body
    dirt = (1 - rib) * body * smooth((fbm(b * 90, a * 90) - .3) * 3)
    rubbed = smooth((fbm(b * 400, a * 400, 3) + .5 * np.exp(-np.abs(a - arc[4]) / .001) - 1.0) * 8)
    col = mix(np.array((236, 182, 20), f32) * (.86 + .14 * rib[..., None]) + (grit[..., None] - .5) * 8, (96, 84, 40), .5 * dirt)
    col = mix(col, (246, 226, 150), .5 * rubbed)
    kit.commit(area, float(arc[-1]), girth, where, col, .00028 * rib + (grit - .5) * 8e-6, .5 - .1 * rubbed + .1 * dirt, np.zeros(a.shape, f32),
               (1 - .3 * (1 - rib) * body).astype(f32))


def paint_lens(area, length, width, lamp):
    """A bar lamp's lens: a smoked diffuser moulded in fine prisms; where it glows, and for which lamp."""
    a, b, where = kit.window(area, length, width)
    a, b = np.broadcast_arrays(a, b)
    prism = np.cos(2 * math.pi * b / .0011) * .5 + .5
    edge = np.minimum(np.minimum(a, length - a), np.minimum(b, width - b))
    col = np.full(a.shape + (3,), 78.0, f32) + 16 * prism[..., None]
    kit.commit(area, length, width, where, col, 5e-5 * prism, np.full(a.shape, .26, f32), np.zeros(a.shape, f32), (.7 + .3 * smooth(edge / .0006)).astype(f32))
    glow = (.5 + .5 * np.exp(-((a - length / 2) / (.45 * length))**2)) * (.78 + .22 * prism) * (.35 + .65 * smooth(edge / .0007))
    lit(where, lens=glow, lamp=LAMPS[lamp])


def paint_jewel(area, arc, girth):
    """The standby lamp: a green glass jewel, fluted round its dome."""
    a, b, where = kit.window(area, float(arc[-1]), girth)
    a, b = np.broadcast_arrays(a, b)
    flute = np.cos(2 * math.pi * 14 * b / girth) * .5 + .5
    up = a / float(arc[-1])
    col = np.array((22, 84, 40), f32) * (.8 + .4 * flute[..., None])
    kit.commit(area, float(arc[-1]), girth, where, col, 9e-5 * flute * (1 - up), np.full(a.shape, .1, f32), np.zeros(a.shape, f32), np.ones(a.shape, f32))
    lit(where, lens=(.45 + .55 * up) * (.75 + .25 * flute), lamp=LAMPS["standby"])


def paint_thread(area, length, girth):
    """A toggle's bushing: bright zinc, threaded."""
    a, b, where = kit.window(area, length, girth)
    a, b = np.broadcast_arrays(a, b)
    streak = vnoise(b * 300, a * 9000)
    thread = np.cos(2 * math.pi * (a / .0007 + b / girth)) * .5 + .5
    cut = a < length - .0022                                          # (its lip and bore are plain)
    col = np.full(a.shape + (3,), 172.0, f32) + (streak[..., None] - .5) * 18 - 40 * (1 - thread[..., None]) * cut[..., None]
    col = np.where((a > length - .0009)[..., None], 14.0, col)       # down the bore
    kit.commit(area, length, girth, where, col, 8e-5 * thread * cut, .34 + .1 * (1 - thread) * cut, np.ones(a.shape, f32),
               (.55 + .45 * smooth(a / .002)).astype(f32))


def paint_braid(area, length, girth):
    """A braided sleeve over the pod's wiring."""
    a, b, where = kit.window(area, length, girth)
    a, b = np.broadcast_arrays(a, b)
    turns, pitch = 10, .0016
    g1 = np.abs((turns * b / girth + a / pitch) % 1 - .5)
    g2 = np.abs((turns * b / girth - a / pitch) % 1 - .5)
    over = smooth(np.abs(g1 - g2) * 3)
    col = np.full(a.shape + (3,), 22.0, f32) + 26 * over[..., None]
    kit.commit(area, length, girth, where, col, .00016 * over, .62 + .2 * (1 - over), np.zeros(a.shape, f32), (.6 + .4 * over).astype(f32))


# ---- fittings, each kind painted once into an area of its own ----
AREAS = {}
zinc = lambda area, run, girth: paint_small(area, float(run[-1]), girth, "zinc")
chrome = lambda area, run, girth: paint_small(area, float(run[-1]), girth, "chrome")
enamel = lambda first, last, spans=None: (lambda area, run, girth: paint_guard(area, float(run[-1]), girth, (first, last), spans))


def turned(part, key, profile, around, frame, hint, paint, density=5200.0):
    """Lathe (radius, depth) pairs round a frame's axis; every fitting of one `key` shares its maps."""
    fresh = key not in AREAS
    if fresh:
        prof = np.array(profile, float)
        AREAS[key] = take(float(np.sum(np.hypot(*np.diff(prof, axis=0).T))), 2 * math.pi * float(prof[:, 0].max()), density)
    run, girth = part.lathe(AREAS[key], profile, around, frame, hint)
    if fresh:
        paint(AREAS[key], run, girth)
    return run, girth


def swept(part, key, profile, base, frame, hint, paint, density=5200.0):
    """Run (offset, depth) rows round an outline, likewise."""
    fresh = key not in AREAS
    if fresh:
        prof = np.array(profile, float)
        AREAS[key] = take(float(np.sum(np.hypot(*np.diff(prof, axis=0).T))), float(base[2][-1]), density)
    run, girth = sweep(part, AREAS[key], profile, base, frame, hint)
    if fresh:
        paint(AREAS[key], run, girth)
    return run, girth


def flat(key, size, paint, density=5200.0):
    if key not in AREAS:
        AREAS[key] = take(size, size, density)
        paint(AREAS[key])
    return AREAS[key]


def cable(part, path, radius, around=10):
    """A sleeved cable through `path`, its corners eased."""
    path = np.array(path, float)
    for _ in range(2):
        eased = [path[0]]
        for p0, p1 in zip(path[:-1], path[1:]):
            eased += [.75 * p0 + .25 * p1, .25 * p0 + .75 * p1]
        path = np.array(eased + [path[-1]])
    tangent = np.gradient(path, axis=0)
    tangent /= np.linalg.norm(tangent, axis=1, keepdims=True)
    n1 = np.cross(tangent, (0.0, 0.0, 1.0))
    n1 /= np.linalg.norm(n1, axis=1, keepdims=True)
    n2 = np.cross(tangent, n1)
    psi = np.linspace(0, 2 * math.pi, around + 1)
    points = path[:, None, :] + radius * (np.cos(psi)[None, :, None] * n1[:, None, :] + np.sin(psi)[None, :, None] * n2[:, None, :])
    run = np.concatenate([[0], np.cumsum(np.linalg.norm(np.diff(path, axis=0), axis=1))])
    girth = 2 * math.pi * radius
    area = take(float(run[-1]), girth, 3600)
    j = min(len(path) // 2, len(path) - 2)
    part.patch(area, float(run[-1]), girth, points, run, psi * radius, lambda p: p - path[j])
    paint_braid(area, float(run[-1]), girth)


def pod(side, face):
    """A pod's fixed parts, in its own frame."""
    row = 0 if side < 0 else 1
    part = Part("PodR" if row else "PodL")
    base, here = rounded_rect(BODY_W / 2, BODY_H / 2, .007, 16, 5), frame_z(0, BODY_Y, 0)
    shell = kit.rect(12, 1192 + 160 * row, 1400, 148)
    run, girth = sweep(part, shell, [(-.0030, -BODY_T), (0, -BODY_T + .0025), (0, .0005), (-.0012, RIM_Z), (-.0040, RIM_Z), (-.0045, RIM_Z - .0005),
                                     (-.0045, FACE_Z - .0002)], base, here, "out")
    paint_shell(shell, run, girth, 1.9 * row)
    cap(part, flat("back", .19, lambda area: plain(area, .19, .19, (33, 35, 40), .72), 700), .19, base, here, -BODY_T, (0, 0, -1), .003)
    plate = kit.rect(12, 12 + 584 * row, 1040, 564)                # (overhead_panel.gd's PLATE_AREA and PLATE_STEP)
    hw, top = PLATE_W / 2, BODY_Y + PLATE_H / 2
    planar(part, plate, PLATE_H, PLATE_W, [[(-hw, top, FACE_Z), (hw, top, FACE_Z)], [(-hw, top - PLATE_H, FACE_Z), (hw, top - PLATE_H, FACE_Z)]],
           [[(0, 0), (0, PLATE_W)], [(PLATE_H, 0), (PLATE_H, PLATE_W)]], (0, 0, 1))
    paint_face(plate, side, face)
    for control, (where, cx) in CONTROLS.items():
        if where != side:
            continue
        if control == "start":                                        # the bezel, and the floor of its throat under the ring of lights
            at = frame_z(cx, 0, 0)
            turned(part, "bezel", [(.0345, FACE_Z), (.0345, .0022), (.0336, .0030), (.0318, .0030), (.0318, .0082), (.0308, .0092), (.0262, .0092),
                                   (.0248, .0078), (.0248, .0048)], 96, at, "out", paint_bezel, 5600)
            turned(part, "well", [(.0248, .0050), (.0176, .0050)], 48, at, "front", lambda area, run, girth: plain(area, float(run[-1]), girth, (8, 8, 9), .8), 1500)
            continue
        at = frame_z(cx, 0, FACE_Z)                                   # a toggle: lock ring, hex nut, threaded bushing
        turned(part, "lockring", [(.0118, 0), (.0118, .0007), (.0111, .0012), (.0094, .0012)], 40, at, "out", zinc)
        turned(part, "nut", [(.0096, .0010), (.0096, .0031), (.0086, .0039), (.0062, .0039)], 6, at, "out", zinc)
        turned(part, "bushing", [(.0062, .0036), (.0062, .0061), (.0056, .0067), (.0044, .0067), (.0040, .0052)], 24, at, "out",
               lambda area, run, girth: paint_thread(area, float(run[-1]), girth), 7000)
        swept(part, "lampframe", [(.0022, 0), (.0022, .0013), (.0016, .0019), (.0005, .0019), (0, .0015), (0, .0008)], rounded_rect(.0150, .0017, .0007, 8, 3),
              frame_z(cx, LAMP_Y, FACE_Z), "out", lambda area, run, girth: paint_frame(area, run, girth, ((1, 2), (3, 4))), 6500)
        lens, lz = take(.0038, .0304, 7000), FACE_Z + .0010          # its lamp: a lens of its own in the map
        planar(part, lens, .0038, .0304, [[(cx - .0152, LAMP_Y + .0019, lz), (cx + .0152, LAMP_Y + .0019, lz)],
                                          [(cx - .0152, LAMP_Y - .0019, lz), (cx + .0152, LAMP_Y - .0019, lz)]],
               [[(0, 0), (0, .0304)], [(.0038, 0), (.0038, .0304)]], (0, 0, 1))
        paint_lens(lens, .0038, .0304, control)
    if side < 0:
        at = frame_z(CONTROLS["batt"][1] + STANDBY_X, 0, FACE_Z)       # the standby lamp: a jewel in a chromed bezel
        turned(part, "jewelbezel", [(.0052, 0), (.0052, .0021), (.0046, .0027), (.0036, .0027), (.0033, .0022)], 28, at, "out", chrome, 7000)
        turned(part, "jewel", [(.0033, .0020), (.0031, .0034), (.0024, .0044), (.0012, .0049), (.0002, .0050)], 28, at, "out", paint_jewel, 9000)
        gx = CONTROLS["engine"][1]                                    # the guard's hinge: a leaf on the plate, a lug at each end of the pin
        leaf, at = rounded_rect(.0215, .0045, .001, 8, 3), frame_z(gx, HINGE[0] + .0025, FACE_Z)
        swept(part, "leaf", [(0, 0), (0, .0011), (-.0005, .0016)], leaf, at, "out", zinc)
        bare = flat("leaftop", .044, lambda area: plain(area, .044, .044, (168, 170, 172), .38, 1.0, 16), 3000)
        cap(part, bare, .044, leaf, at, .0016, (0, 0, 1), .0005)
        for end in (-1, 1):
            lug, at = rounded_rect(.0016, .0040, .0010, 4, 3), frame_z(gx + end * .0201, HINGE[0], FACE_Z)
            swept(part, "lug", [(0, 0), (0, .0068), (-.0006, .0076)], lug, at, "out", zinc)
            cap(part, bare, .044, lug, at, .0076, (0, 0, 1), .0006)
    return part


def clamps(side):
    """What hangs a pod from the rail, in the pod's frame: two standoffs and their collars, and its
    pigtail. Also the rail itself there, for the bake."""
    part, rail = Part("ClampsR" if side > 0 else "ClampsL"), Part("RailR" if side > 0 else "RailL")
    axes, origin = pod_frame(side)

    def section(w):
        p, t = header_at(w), unit(header_at(w + .01) - header_at(w - .01))
        inward = CABIN - p
        inward = unit(inward - t * (inward @ t))
        return axes.T @ (p - origin), axes.T @ t, axes.T @ inward, axes.T @ np.cross(t, inward)

    phi = np.linspace(0, 2 * math.pi, 41)
    ws = np.linspace(POD_W * side - .36, POD_W * side + .36, 25)
    spare = flat("spare", .01, lambda area: plain(area, .01, .01, (30, 30, 30), .6), 2000)
    points = []
    for w in ws:
        c, t, inward, across = section(w)
        points.append([c + RAIL[0] * math.cos(f) * inward + RAIL[1] * math.sin(f) * across for f in phi])
    middle = section(ws[12])[0]
    rail.patch(spare, 1, 1, points, np.linspace(0, 1, len(ws)), np.linspace(0, 1, len(phi)), lambda p: p - middle)

    profile = np.array([(-.0006, -.0070), (.0020, -.0070), (.0029, -.0061), (.0029, .0061), (.0020, .0070), (-.0006, .0070)])
    run = np.concatenate([[0], np.cumsum(np.hypot(*np.diff(profile, axis=0).T))])
    girth = 2 * math.pi * (sum(RAIL) / 2 + .0029)
    for sx in (-.058, .058):
        c, t, inward, across = section(POD_W * side + sx / .41)
        fresh = "collar" not in AREAS
        if fresh:
            AREAS["collar"] = take(float(run[-1]), girth, 4200)
        ring = [[c + s * t + (RAIL[0] + off) * math.cos(f) * inward + (RAIL[1] + off) * math.sin(f) * across for f in phi] for off, s in profile]
        part.patch(AREAS["collar"], float(run[-1]), girth, ring, run, phi / (2 * math.pi) * girth, lambda p, c=c: p - c)
        if fresh:
            paint_frame(AREAS["collar"], run, girth, ((1, 2), (3, 4)))
        foot = np.array((sx, .014, -BODY_T + .0005))                  # a standoff from the pod's back to the collar
        length = float(np.linalg.norm(c - foot)) - .0185
        n = unit(c - foot)
        ux = unit(np.cross(n, (1, 0, 0)))
        turned(part, "strut%d" % round(length * 1e4), [(.0085, 0), (.0085, .0012), (.0058, .0026), (.0046, .0042), (.0046, length - .003), (.0060, length)],
               16, (foot, ux, np.cross(n, ux), n), "out", zinc, 4200)
    inboard = -side                                                   # the pigtail: from a gland in the pod's top, along the rail, into the inboard collar
    gx, top = inboard * .034, BODY_Y + BODY_H / 2
    turned(part, "gland", [(.0056, 0), (.0056, .0026), (.0046, .0034), (.0034, .0034)], 6, ((gx, top - .0003, -.012), (1, 0, 0), (0, 0, -1), (0, 1, 0)), "out", zinc)
    path = [np.array((gx, top + .0028, -.012)), np.array((gx, top + .0090, -.0135))]
    for w in np.linspace(POD_W * side + (gx + inboard * .006) / .41, POD_W * side + inboard * .052 / .41, 4):
        c, t, inward, across = section(w)
        path.append(c + (RAIL[0] + .0032) * unit(.75 * inward + .66 * across * side))
    cable(part, path, .0026)
    return part, rail


def movers(face):
    """The parts the game moves, each about its own pivot."""
    bat = Part("Bat")
    turned(bat, "bat", [(.0030, -.0015), (.0030, .0030), (.0033, .0110), (.0040, .0200), (.0049, .0280), (.0055, .0330), (.0056, .0365), (.0052, .0395),
                        (.0040, .0416), (.0022, .0427), (.0003, .0430)], 24, frame_z(), "out", chrome, 6500)

    paddle = Part("Paddle")
    turned(paddle, "stem", [(.0030, -.0015), (.0030, .0040), (.0034, .0160), (.0038, .0268)], 20, frame_z(), "out", chrome, 6000)
    tab = rounded_rect(.0125, .00375, .0028, 8, 4)
    swept(paddle, "tab", [(-.0026, .0252), (-.0006, .0258), (0, .0276), (0, .0408), (-.0008, .0424), (-.0028, .0431)], tab, frame_z(), "back", paint_paddle, 7000)
    yellow = flat("tabend", .026, lambda area: plain(area, .026, .026, (232, 180, 22), .5), 4000)
    cap(paddle, yellow, .026, tab, frame_z(), .0431, (0, 0, 1), .0028)
    cap(paddle, yellow, .026, tab, frame_z(), .0252, (0, 0, -1), .0026)

    guard = Part("Guard")                                             # about its hinge pin: x across, z out of the face, depths down from the pin
    down = ((0, 0, 0), (1, 0, 0), (0, 0, 1), (0, -1, 0))
    w, d, b, r, t, win = .017, .046, -.0035, .005, .0018, .0095
    outer = [(w, b), (w, d - r)] + arc(w - r, d - r, r, 0, 90)[1:] + [(-(w - r), d)] + arc(-(w - r), d - r, r, 90, 180)[1:] + [(-w, b)]
    inner = [(-(w - t), b), (-(w - t), d - r)] + arc(-(w - r), d - r, r - t, 180, 90)[1:] + [(w - r, d - t)] + arc(w - r, d - r, r - t, 90, 0)[1:] + [(w - t, b)]
    cheek = [(w, b), (w, d - r)] + arc(w - r, d - r, r, 0, 90)[1:] + [(win, d), (win, d - t), (w - r, d - t)] + arc(w - r, d - r, r - t, 90, 0)[1:] + [(w - t, b)]
    foot = [(w, b), (w, d - r)] + arc(w - r, d - r, r, 0, 90)[1:] + [(.0085, d), (.0085, d + .0055), (-.0085, d + .0055), (-.0085, d), (-(w - r), d)] \
        + arc(-(w - r), d - r, r, 90, 180)[1:] + [(-w, b)]
    channel, lid, sole = loop(outer + inner), loop(outer), loop(foot)
    swept(guard, "guardlid", [(-.0006, .0030), (0, .0036), (0, .0050)], lid, down, "out", enamel(True, False), 4200)
    edges = []                                                        # the window's own width of the channel, outside and in: its edges are the worn ones
    for x0, z0 in ((w - r, d), (-(w - r), d - t)):
        k = next(i for i, p in enumerate(channel[0]) if abs(p[0] - x0) < 1e-9 and abs(p[1] - z0) < 1e-9)
        edges.append((channel[2][k] + w - r - win, channel[2][k] + w - r + win))
    swept(guard, "guardover", [(0, .0050), (0, .0170)], channel, down, "out", enamel(False, True, edges), 4200)       # over the window
    swept(guard, "guardunder", [(0, .0400), (0, .0520)], channel, down, "out", enamel(True, False, edges), 4200)      # under it
    for key, outline in (("guardcheekR", cheek), ("guardcheekL", [(-x, z) for x, z in reversed(cheek)])):      # (each its own maps: the mirror runs the other way round)
        swept(guard, key, [(0, .0170), (0, .0400)], loop(outline), down, "out", enamel(False, False), 3600)
    swept(guard, "guardsole", [(0, .0520), (0, .0539), (-.0006, .0545)], sole, down, "out", enamel(False, True), 4200)
    red = flat("guardflat", .06, lambda area: paint_guard(area, .06, .06), 3400)
    cap(guard, red, .06, lid, down, .0030, (0, 1, 0), .0006)
    cap(guard, red, .06, lid, down, .0050, (0, -1, 0))
    cap(guard, red, .06, channel, down, .0170, (0, -1, 0))
    cap(guard, red, .06, channel, down, .0400, (0, 1, 0))
    cap(guard, red, .06, sole, down, .0520, (0, 1, 0))
    cap(guard, red, .06, sole, down, .0545, (0, -1, 0), .0006)
    turned(guard, "barrel", [(.0004, 0), (.0028, 0), (.0030, .0004), (.0030, .0360), (.0028, .0364), (.0004, .0364)], 16,
           ((-.0182, 0, 0), (0, 1, 0), (0, 0, 1), (1, 0, 0)), "back", zinc, 3000)

    button = Part("Cap")
    turned(button, "capside", [(.0183, 0), (.0183, .0098), (.0176, .0112), (.0166, .0120)], 64, frame_z(), "out", paint_cap_side, 5200)
    size = .034
    top = take(size, size, 8200)
    radii, spokes = np.array((.0002, .004, .008, .012, .0146, .0166)), np.linspace(0, 2 * math.pi, 65)
    planar(button, top, size, size, [[(q * math.cos(f), q * math.sin(f), .0120 - .0007 * (1 - (q / .0166)**2)) for f in spokes] for q in radii],
           [[(size / 2 - q * math.sin(f), size / 2 + q * math.cos(f)) for f in spokes] for q in radii], (0, 0, 1))
    paint_cap_top(top, size, face)
    return bat, paddle, guard, button


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
    scene.world.light_settings.distance = .05

    image = bpy.data.images.new("Occlusion", BAKE, BAKE, alpha=True, is_data=True)
    image.pixels.foreach_set(np.tile(np.array((1, 1, 1, 0), f32), BAKE * BAKE))
    target = bpy.data.materials.new("BakeTarget")
    target.use_nodes = True
    node = target.node_tree.nodes.new("ShaderNodeTexImage")
    node.image = image
    target.node_tree.nodes.active = node

    face = Type()
    sets = []
    for side in (-1, 1):
        body = pod(side, face)
        hung, rail = clamps(side)
        sets.append([part.mesh(target) for part in (body, hung, rail)])
    loose = [part.mesh(target) for part in movers(face)]
    everything = [obj for group in sets for obj in group] + loose
    for group in sets:                                                # a pod with its clamps, under its own length of rail
        bake(group[:2], [obj for obj in everything if obj not in group], image, False)
    for obj in loose:                                                 # each moving part by itself
        bake([obj], [other for other in everything if other is not obj], image, False)
    pixels = np.empty(BAKE * BAKE * 4, f32)
    image.pixels.foreach_get(pixels)
    pixels = pixels.reshape(BAKE, BAKE, 4)[::-1]                     # Blender's rows run bottom-up
    scale = kit.RES // BAKE
    shade = np.kron(np.where(pixels[..., 3] > .5, pixels[..., 0], 1.0), np.ones((scale, scale), f32))
    shade = np.clip(box(shade.astype(f32), 1, 1), 0, 1)
    print("BAKE", f"{(pixels[..., 3] > .5).mean() * 100:.0f}% of the atlas baked, occlusion {shade.min():.2f}-{shade.max():.2f}, mean {shade.mean():.2f}", flush=True)
    kit.BASE[:] = np.clip(kit.BASE * (.5 + .5 * shade[..., None]), 0, 255)
    kit.ORM[..., 0] = np.clip(kit.ORM[..., 0] * shade, 0, 255)
    kit.ORM[..., 1] = np.clip(kit.ORM[..., 1] + 30 * (1 - shade), 0, 255)

    with tempfile.TemporaryDirectory() as tmp:
        folder = Path(tmp)
        for name, pixels8 in (("StartPanelHD_Base", kit.BASE), ("StartPanelHD_Normal", kit.NORMAL), ("StartPanelHD_ORM", kit.ORM), ("StartPanelHD_Glow", GLOW)):
            png(folder / (name + ".png"), pixels8)
        material = pbr(folder, "StartPanelHD")
        tree = material.node_tree                                     # the fourth map rides as the material's emission
        bsdf = next(n for n in tree.nodes if n.type == "BSDF_PRINCIPLED")
        glow = tree.nodes.new("ShaderNodeTexImage")
        glow.image = bpy.data.images.load(str(folder / "StartPanelHD_Glow.png"))
        tree.links.new(glow.outputs["Color"], bsdf.inputs["Emission Color"])
        bsdf.inputs["Emission Strength"].default_value = 1.0
        for group in sets:
            bpy.data.objects.remove(group[2])
            for obj in group[:2]:
                obj.data.materials.clear()
                obj.data.materials.append(material)
                obj.hide_render = False
        for obj in loose:
            obj.data.materials.clear()
            obj.data.materials.append(material)
            obj.hide_render = False
        bpy.ops.export_scene.gltf(filepath=str(OUTPUT), export_tangents=True, export_animations=False,
                                  export_cameras=False, export_lights=False)
    print("Wrote", OUTPUT, OUTPUT.stat().st_size, "bytes")


if __name__ == "__main__":
    main()
