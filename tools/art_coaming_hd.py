"""Realism spike: the cockpit coaming rebuilt at headset texel density.

    blender --background --python tools/art_coaming_hd.py [-- --res 4096]

Same envelope and band layout as art_cockpit.py's Coaming. Forms of 2 mm and up are real
geometry (panel gaps, hems, bead, padded welts); finer detail (stitching, grain, paint,
fasteners, the nameplate) is synthesised in surface metres and written to one unique
colour / normal / occlusion-roughness-metal set. Nothing here tiles.
"""
import math
import struct
import sys
import tempfile
import zlib
from pathlib import Path

import bmesh
import bpy
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from art_cockpit import GLYPHS, OPEN_AX, OPEN_AZ, OPEN_AZ_FRONT, OPEN_ZC, hull_top  # noqa: E402  the game's own hull stations and opening

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "godot/art/cockpit/coaming_hd.glb"
ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
RES = int(ARGS[ARGS.index("--res") + 1]) if "--res" in ARGS else 4096
MM = 1e-3
f32 = np.float32

# ---- the path round the opening, and the section, both by arc length in metres ----
A = np.linspace(-138, 138, 2761)
_ar = np.radians(A)
_az = np.where(np.cos(_ar) > 0, OPEN_AZ_FRONT, OPEN_AZ)     # the opening is an egg: shorter ahead of its widest point
PX, PZ = OPEN_AX * np.sin(_ar), OPEN_ZC - _az * np.cos(_ar)
PY = np.array([hull_top(x, z) for x, z in zip(PX, PZ)])
S = np.concatenate([[0], np.cumsum(np.sqrt(np.diff(PX)**2 + np.diff(PY)**2 + np.diff(PZ)**2))])
LEN = float(S[-1])
_n = np.stack([-np.sin(_ar) / OPEN_AX, np.cos(_ar) / _az])
NX, NZ = _n / np.linalg.norm(_n, axis=0)               # horizontal, toward the pilot
ENVELOPE = [(-68, .054), (-62, .058), (-49, .065), (-29, .071), (24, .068), (31, .067),
            (77, .063), (92, .067), (112, .061), (130, .056), (136, .052)]
PG = np.linspace(-68, 136, 2041)
R0 = np.interp(PG, *zip(*ENVELOPE))
T = np.concatenate([[0], np.cumsum(.5 * (R0[1:] + R0[:-1]) * np.radians(np.diff(PG)))])
WID = float(T[-1])
tp = lambda deg: float(np.interp(deg, PG, T))
sa = lambda deg: float(np.interp(deg, A, S))
E = [tp(p) for p in (-62, -49, -29, 24, 31, 77, 92, 112, 130)]
RAIL, REVEAL, FACING, BEAD, WELT_A, CREST, WELT_B, TRIM = range(8)
EDGE = np.array(E[1:8], f32)
LO = np.array([0] + E[1:8], f32)
HI = np.array(E[1:8] + [WID], f32)
ENDS = [-138, -112, -81, -55, -31, -10, 10, 31, 55, 81, 112, 138]
JOINT = np.array([sa(a) for a in ENDS[1:-1]])
BREAK = [0.0, sa(-81), sa(-31), sa(31), sa(81), LEN]    # UV strips split inside panel gaps
MARGIN, PITCH = 24 * RES // 4096, RES // 5
KS = (RES - 2 * MARGIN) / max(np.diff(BREAK))            # texels per metre along
KT = (PITCH - 28 * RES // 4096) / WID                    # ... and across


def smooth(x):
    x = np.clip(x, 0, 1)
    return x * x * (3 - 2 * x)


def joint_distance(s):
    i = np.clip(np.searchsorted(JOINT, s), 1, len(JOINT) - 1)
    return np.minimum(np.abs(s - JOINT[i - 1]), np.abs(s - JOINT[i]))


def macro(s, t):
    """Geometry offset from the envelope, metres, with the band, position in it and joint terms."""
    s, t = np.broadcast_arrays(np.asarray(s, f32), np.asarray(t, f32))
    b = np.searchsorted(EDGE, t)
    lo, hi = LO[b], HI[b]
    x = np.clip((t - lo) / (hi - lo), 0, 1)
    edge = np.clip(np.minimum(t - lo, hi - t), 0, None)
    dj = joint_distance(s)
    hem = lambda w: np.where(edge < w, 1 - np.sqrt(np.clip(1 - (1 - edge / w)**2, 0, 1)), 0)
    pill = 1 - (2 * x - 1)**4
    pinch = 1 - .45 * np.exp(-(dj / .009)**2)
    seam = np.exp(-(dj / .0012)**2)
    off = np.zeros(s.shape, f32)
    off = np.where(b == REVEAL, -.0025 * smooth(edge / .001), off)
    off = np.where(b == FACING, -.0022 * hem(.0025), off)
    off = np.where(b == BEAD, .0026 * np.sqrt(np.clip(1 - (2 * x - 1)**2, 0, 1)), off)
    off = np.where(b == WELT_A, (.0070 * pill - .0015) * pinch - .0015 * seam, off)
    off = np.where(b == CREST, -.0015 * hem(.002) + .0006 * (1 - (2 * x - 1)**2), off)
    off = np.where(b == WELT_B, (.0045 * pill - .0012) * pinch - .0012 * seam, off)
    trench = np.where((b == FACING) | (b == CREST), 1 - smooth((dj - .0015) / .0015), 0)
    line = np.where((b == RAIL) | (b == BEAD) | (b == TRIM), 1 - smooth((dj - .0004) / .0006), 0)
    off = off - .004 * trench - .001 * line - .006 * (1 - smooth(np.minimum(s, LEN - s) / .012))
    return off.astype(f32), b, x.astype(f32), dj.astype(f32), trench.astype(f32), edge.astype(f32)


# ---- noise in surface metres ----
RNG = np.random.default_rng(2107)
TAB = RNG.random((256, 256), dtype=f32)
JIT = RNG.random((256, 256, 2), dtype=f32)


def vnoise(x, y):
    xi, yi = np.floor(x).astype(np.int32), np.floor(y).astype(np.int32)
    fx, fy = smooth(x - xi), smooth(y - yi)
    x0, x1, y0, y1 = xi & 255, (xi + 1) & 255, yi & 255, (yi + 1) & 255
    top = TAB[y0, x0] + (TAB[y0, x1] - TAB[y0, x0]) * fx
    bot = TAB[y1, x0] + (TAB[y1, x1] - TAB[y1, x0]) * fx
    return (top + (bot - top) * fy).astype(f32)


def fbm(x, y, octaves=3):
    total, amp, norm = 0, 1.0, 0.0
    for k in range(octaves):
        total = total + amp * vnoise(x * 2**k + 17.3 * k, y * 2**k + 9.1 * k)
        norm += amp
        amp *= .5
    return total / norm


def cells(x, y):
    xi, yi = np.floor(x).astype(np.int32), np.floor(y).astype(np.int32)
    f1 = np.full(x.shape, 9, f32)
    f2, ident = f1.copy(), np.zeros(x.shape, f32)
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            cx, cy = xi + dx, yi + dy
            j = JIT[cy & 255, cx & 255]
            d = np.hypot(cx + j[..., 0] - x, cy + j[..., 1] - y).astype(f32)
            near = d < f1
            f2 = np.where(near, f1, np.minimum(f2, d))
            ident = np.where(near, TAB[(cy * 7 + 3) & 255, (cx * 13 + 5) & 255], ident)
            f1 = np.where(near, d, f1)
    return f1, f2, ident


def box(a, radius, passes=2):
    r = max(1, int(radius))
    for _ in range(passes):
        for axis in (0, 1):
            pad = [(r + 1, r) if ax == axis else (0, 0) for ax in (0, 1)]
            c = np.cumsum(np.pad(a, pad, mode="edge"), axis=axis, dtype=np.float64)
            n = a.shape[axis]
            a = ((np.take(c, range(2 * r + 1, 2 * r + 1 + n), axis) - np.take(c, range(0, n), axis)) / (2 * r + 1)).astype(f32)
    return a


def lettering():
    """The nameplate's word as drawn capitals: the strokes' ends (ax, ay, bx, by) in cap heights about the word's
    middle, and its width. (It was art_cockpit.py's 5 x 7 dot font blown up twelve times, whose bowls were squares
    and whose O was an octagon: Luke, of the badge, "looks low-poly". A texel's ink is now its distance to these
    strokes, so the letters are as smooth as the texture is fine.)"""
    def arc(cx, cy, rx, ry, a0, a1, n):
        return [(cx + rx * math.cos(math.radians(a0 + (a1 - a0) * i / n)), cy + ry * math.sin(math.radians(a0 + (a1 - a0) * i / n))) for i in range(n + 1)]
    glyphs = {   # width, then polylines: x from the letter's left, y up from the baseline, the capitals 1 high
        "P": (.56, [[(0, 0), (0, 1), (.30, 1)] + arc(.30, .74, .26, .26, 90, -90, 20) + [(0, .48)]]),
        "H": (.62, [[(0, 0), (0, 1)], [(.62, 0), (.62, 1)], [(0, .5), (.62, .5)]]),
        "A": (.70, [[(0, 0), (.35, 1), (.70, 0)], [(.11, .30), (.59, .30)]]),
        "E": (.52, [[(.52, 1), (0, 1), (0, 0), (.52, 0)], [(0, .5), (.44, .5)]]),
        "T": (.62, [[(0, 1), (.62, 1)], [(.31, 0), (.31, 1)]]),
        "O": (.70, [arc(.35, .5, .35, .5, 0, 360, 48)]),
        "N": (.64, [[(0, 0), (0, 1), (.64, 0), (.64, 1)]]),
    }
    track = .30                                                # between letters: a badge is set wide
    strokes, pen = [], 0.0
    for ch in "PHAETHON":
        wide, lines = glyphs[ch]
        for line in lines:
            strokes += [(pen + a[0], a[1] - .5, pen + b[0], b[1] - .5) for a, b in zip(line, line[1:])]
        pen += wide + track
    wide = pen - track
    return np.array([(ax - wide / 2, ay, bx - wide / 2, by) for ax, ay, bx, by in strokes], f32), wide


WORD, WORD_WIDE = lettering()
WORD_STROKE = .15                                              # the strokes' weight, of the capitals' height
SCREWS = [(sa(a), tp(-1.0), RNG.uniform(0, math.pi)) for left, right in zip(ENDS, ENDS[1:])
          if left != -10 for a in (left + 1.7, right - 1.7)]
RIVETS = [(sa(a), tp(-2.0)) for a in (-7.2, 7.2)]


def mix(col, target, w):
    return col + (np.array(target, f32) - col) * w[..., None]


def surface(s, t):
    """Colour (sRGB 0-255), micro height (m), roughness and metal for a window of the strip."""
    off, b, x, dj, trench, edge = macro(s, t)
    s, t = np.broadcast_arrays(s.astype(f32), t.astype(f32))
    shape = s.shape
    col = np.zeros(shape + (3,), f32)
    h, rough, metal = np.zeros(shape, f32), np.zeros(shape, f32), np.zeros(shape, f32)
    streak = vnoise(s * 55, t * 4200)
    grit = fbm(s * 5200, t * 5200, 2)

    # machined rail, polished bead, graphite trim
    for band, base, r, m in ((RAIL, (178, 181, 185), .33, 1.0), (BEAD, (206, 208, 211), .2, 1.0), (TRIM, (57, 61, 65), .5, .85)):
        k = b == band
        worn = smooth((fbm(s * 240, t * 900) + .45 * np.exp(-edge / .001) - .9) * 9) if band == TRIM else 0
        tone = base + (streak[..., None] - .5) * (16 if band != TRIM else 5)
        if band == TRIM:
            tone = mix(tone, (158, 160, 163), worn)
        col[k] = tone[k]
        h[k] = ((streak - .5) * 5e-6 + (grit - .5) * (8e-6 if band == TRIM else 2e-6))[k]
        rough[k] = (r + (streak - .5) * .1 - .15 * worn)[k]
        metal[k] = m
    k = b == REVEAL                                           # extruded rubber seal
    col[k] = (np.array((23, 24, 26), f32) + fbm(s * 300, t * 300)[..., None] * 14)[k]
    h[k] = (.00011 * np.cos(2 * math.pi * t / .0009))[k]
    rough[k] = .84

    # orange enamel on the facing and the crest
    k = (b == FACING) | (b == CREST)
    fade = fbm(s * 7, t * 30)
    paint = np.array((193, 73, 19), f32) * (.93 + .14 * fade[..., None])
    hp = (fbm(s * 950, t * 950, 2) - .5) * 2.2e-5 + (fbm(s * 9, t * 26, 2) - .5) * 2.5e-4
    rp = .27 + .13 * smooth((fbm(s * 38, t * 55) - .5) * 5)                    # hand smudges
    scratch = smooth((vnoise(s * 30 + 40, t * 2800) - .955) * 40) * smooth((fbm(s * 20, t * 20) - .45) * 6)
    hp, rp = hp - 8e-6 * scratch, rp + .16 * scratch
    reach = np.minimum(edge, np.clip(dj - .003, 0, None))
    # Chips gather on hems and gap edges; the open face only gets the odd knock.
    chip_n = .74 * fbm(s * 1500, t * 1500, 3) + .4 * np.exp(-reach / .0016) + .2 * smooth((fbm(s * 60, t * 60) - .7) * 12)
    chip, bare = smooth((chip_n - .84) * 30), smooth((chip_n - .9) * 30)
    paint = mix(mix(paint, (156, 158, 146), chip), (198, 201, 204), bare)
    hp, rp = hp - 6e-5 * chip - 3e-5 * bare, rp + .2 * chip - .12 * bare
    col[k], h[k], rough[k], metal[k] = paint[k], hp[k], rp[k], bare[k]
    k = trench > .55                                           # rubber backing in the panel gaps
    col[k], rough[k], metal[k] = (15, 16, 17), .86, 0
    h[k] = ((grit - .5) * 1e-5)[k]

    # leather welts: pebbled grain, creases, wear on the crown, two rows of top-stitching
    k = (b == WELT_A) | (b == WELT_B)
    f1, f2, ident = cells(s * 1250, t * 1250)
    crease = smooth((f2 - f1) / .24)
    wear = smooth(1.15 * (1 - (2 * x - 1)**2) + .9 * fbm(s * 24, t * 42) - 1.25)
    leather = np.array((47, 38, 33), f32) * ((.84 + .24 * crease) * (1 + (ident - .5) * .1))[..., None]
    leather = mix(leather, (92, 70, 54), .55 * wear)
    hl = 5.5e-5 * (crease - 1) + 2e-5 * (1 - f1) + (fbm(s * 150, t * 430) - .5) * 9e-5
    rl = .6 - .2 * wear + .12 * (1 - crease)
    cut = dj < .0011                                           # the butt seam between panels
    leather[cut] *= .55
    for at in (.2, .78):
        dt = t - (LO[b] + at * (HI[b] - LO[b]))
        phase = (s + .18 * dt) / .006
        index = np.floor(phase)
        along = (phase - index - .5) * .006
        q = np.hypot(np.clip(np.abs(along) - .0017, 0, None), dt) / .0006      # capsule round the thread
        thread = (q < 1) & k
        hl = hl - .00045 * np.exp(-(dt / .0013)**2) + .00012 * np.cos(2 * math.pi * (phase - index)) * np.exp(-np.abs(dt) / .0035)
        hl = np.where(thread, hl + .0005 * np.sqrt(np.clip(1 - q * q, 0, 1)), hl)
        hole = np.hypot(np.abs(along) - .0027, dt) < .00042
        hl = np.where(hole, hl - .0003, hl)
        ply = .86 + .14 * np.cos(2 * math.pi * (along * .8 + dt) / .00045)
        tone = np.array((152, 123, 88), f32) * (ply * (.9 + .2 * TAB[index.astype(np.int32) & 255, 7]))[..., None]
        leather = np.where(thread[..., None], tone, np.where(hole[..., None], leather * .35, leather))
        rl = np.where(thread, .74, rl)
    col[k], h[k], rough[k], metal[k] = leather[k], hl[k], rl[k], 0

    # captive screws in dished washers, and the nameplate, on the facing
    for cs, ct, angle in SCREWS:
        u, v = s - cs, t - ct
        r = np.hypot(u, v)
        if r.min() > .009:
            continue
        washer, head = r < .0075, r < .0045
        slot = head & (np.abs(-u * math.sin(angle) + v * math.cos(angle)) < .0006)
        h = np.where(washer, -.0007 * smooth((.0075 - r) / .003) + (streak - .5) * 4e-6, h)
        h = np.where(head, .0002 + .0008 * np.sqrt(np.clip(1 - (r / .0045)**2, 0, 1)) - .0009 * slot, h)
        col = np.where(washer[..., None], np.where(slot[..., None], 24.0, np.where(head[..., None], 150.0, 188.0)) + (streak[..., None] - .5) * 14, col)
        rough, metal = np.where(washer, np.where(head, .36, .28), rough), np.where(washer, 1, metal)
    u = (s - sa(-8.1)) / (sa(8.1) - sa(-8.1))
    v = (t - tp(-23)) / (tp(19) - tp(-23))
    plate = (u > 0) & (u < 1) & (v > 0) & (v < 1)
    if plate.any():
        rim = np.minimum(np.minimum(u, 1 - u) * (sa(8.1) - sa(-8.1)), np.minimum(v, 1 - v) * (tp(19) - tp(-23)))
        long, tall = abs(sa(8.1) - sa(-8.1)), abs(tp(19) - tp(-23))
        cap = min(.47 * tall, .74 * long / WORD_WIDE)          # the capitals' height (m): the word fills the plate's middle
        where = np.nonzero(plate)
        px, py = (u[where] - .5) * long / cap, (v[where] - .5) * tall / cap
        near = np.full(px.shape, 9, f32)
        for ax, ay, bx, by in WORD:                            # the nearest stroke
            ex, ey = bx - ax, by - ay
            along = np.clip(((px - ax) * ex + (py - ay) * ey) / max(ex * ex + ey * ey, 1e-12), 0, 1)
            near = np.minimum(near, np.hypot(px - ax - ex * along, py - ay - ey * along))
        ink = np.zeros(shape, f32)
        ink[where] = smooth((.5 * WORD_STROKE - near) * cap / .0003 + .5)   # a 0.3 mm chamfer down each stroke's flank
        for cs, ct in RIVETS:
            ink = np.maximum(ink, smooth((.0022 - np.hypot(s - cs, t - ct)) / .0005))
        hb = -.0005 * smooth(rim / .0012) + (grit - .5) * 9e-6 + .00038 * ink
        tone = mix(np.full(shape + (3,), 1, f32) * np.array((30, 37, 42), f32) + (grit[..., None] - .5) * 10, (214, 216, 219), ink)
        col = np.where(plate[..., None], tone, col)
        h, rough, metal = np.where(plate, hb, h), np.where(plate, .5 - .28 * ink, rough), np.where(plate, .85 + .15 * ink, metal)
    return col, h, rough, metal, off


def png(path, pixels):
    height, width, _ = pixels.shape
    chunk = lambda kind, data: struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
    raw = np.concatenate([np.zeros((height, 1), np.uint8), pixels.reshape(height, -1)], axis=1).tobytes()
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
                     + chunk(b"IDAT", zlib.compress(raw, 4)) + chunk(b"IEND", b""))


def textures(folder):
    base = np.full((RES, RES, 3), 40, np.uint8)
    normal = np.full((RES, RES, 3), (128, 128, 255), np.uint8)
    orm = np.full((RES, RES, 3), (255, 128, 0), np.uint8)
    pad = max(2, 10 * RES // 4096)
    for k in range(5):
        x0, y0 = MARGIN - pad, k * PITCH + 14 * RES // 4096 - pad
        w, hgt = int((BREAK[k + 1] - BREAK[k]) * KS) + 2 * pad, int(WID * KT) + 2 * pad
        s = np.clip(BREAK[k] + (np.arange(w) - pad + .5) / KS, BREAK[k], BREAK[k + 1])[None, :]
        t = np.clip(WID - (np.arange(hgt) - pad + .5) / KT, 0, WID)[:, None]
        col, h, rough, metal, off = surface(s, t)
        # Occlusion: the formed geometry at 6 mm, the micro relief at 0.8 mm, and the tuck under each edge.
        ao = np.clip(1 - .9 * (box(off, .006 * KS) - off) / .003, .22, 1) * np.clip(1 - .8 * (box(h, .0008 * KS) - h) / .00025, .45, 1)
        ao *= .55 + .45 * smooth(np.minimum(t, WID - t) / .008)
        col *= (.72 + .28 * ao)[..., None]                    # grime settles where the light doesn't
        rough = np.clip(rough + .18 * (1 - ao), .04, 1)
        dy, dx = np.gradient(h)
        n = np.dstack([-dx * KS, dy * KT, np.ones_like(h)])
        n /= np.linalg.norm(n, axis=2, keepdims=True)
        window = np.s_[y0:y0 + hgt, x0:x0 + w]
        base[window] = np.clip(col, 0, 255)
        normal[window] = np.rint((n * .5 + .5) * 255)
        orm[window] = np.dstack([ao, rough, np.clip(metal, 0, 1)]) * 255
        print("STRIP", k, w, hgt, flush=True)
    for name, image in (("CoamingHD_Base", base), ("CoamingHD_Normal", normal), ("CoamingHD_ORM", orm)):
        png(folder / (name + ".png"), image)


def samples(length, step, anchors, offsets, forced):
    extra = (np.asarray(anchors)[:, None] + np.asarray(offsets)[None, :]).ravel()
    v = np.sort(np.concatenate([np.linspace(0, length, int(length / step) + 1), extra, forced]))
    v = v[(v >= 0) & (v <= length)]
    v = v[np.concatenate([[True], np.diff(v) > 1.2e-4])]
    for value in forced:                                       # strip breaks and the ends must be exact
        v[np.argmin(np.abs(v - value))] = value
    return np.unique(v)


def build(material):
    near = np.array([-8, -5.5, -4, -3.2, -2.6, -2.1, -1.7, -1.3, -.9, -.5, 0, .5, .9, 1.3, 1.7, 2.1, 2.6, 3.2, 4, 5.5, 8]) * MM
    cols = samples(LEN, .016, list(JOINT) + [0, LEN], near, BREAK)
    rows = samples(WID, .0045, E, np.array([-2.5, -1.5, -.8, -.3, .3, .8, 1.5, 2.5]) * MM, [0, WID])
    xyz, uv, faces, start = [], [], [], 0
    for k in range(5):
        s = cols[(cols >= BREAK[k]) & (cols <= BREAK[k + 1])][None, :]
        t = rows[:, None]
        off = macro(s, t)[0]
        p = np.radians(np.interp(t, T, PG))
        r = np.interp(t, T, R0) + off
        x0, y0, z0 = (np.interp(s, S, table) for table in (PX, PY, PZ))
        nx, nz = np.interp(s, S, NX), np.interp(s, S, NZ)
        gx, gy, gz = x0 + nx * r * np.cos(p), y0 + r * np.sin(p), z0 + nz * r * np.cos(p)
        xyz.append(np.stack([gx, -gz, gy], axis=-1).reshape(-1, 3))     # Godot XYZ -> Blender; GLB exports +Y up
        px = MARGIN + (s - BREAK[k]) * KS + 0 * t
        py = k * PITCH + 14 * RES // 4096 + (WID - t) * KT + 0 * s
        uv.append(np.stack([px / RES, 1 - py / RES], axis=-1).reshape(-1, 2))
        nr, nc = len(rows), s.shape[1]
        a = (start + np.arange(nr - 1)[:, None] * nc + np.arange(nc - 1)[None, :]).ravel()
        faces.append(np.stack([a, a + 1, a + nc + 1, a + nc], axis=-1))
        start += nr * nc
    xyz, uv, faces = np.concatenate(xyz), np.concatenate(uv), np.concatenate(faces)
    mesh = bpy.data.meshes.new("Coaming")
    mesh.from_pydata(xyz.tolist(), [], faces.tolist())
    mesh.uv_layers.new(name="CoamingUV").data.foreach_set("uv", uv[faces.ravel()].astype(f32).ravel())
    mesh.polygons.foreach_set("use_smooth", np.ones(len(faces), bool))
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)   # weld the strips; their UVs stay split
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.append(material)
    mesh.update()
    bpy.context.collection.objects.link(bpy.data.objects.new("Coaming", mesh))
    print("MESH", len(mesh.vertices), "vertices", len(mesh.polygons) * 2, "triangles", len(cols), "x", len(rows), flush=True)


def pbr(folder):
    material = bpy.data.materials.new("CoamingHD_PBR")
    material.use_nodes = True
    tree = material.node_tree
    bsdf = next(n for n in tree.nodes if n.type == "BSDF_PRINCIPLED")

    def image(name, data):
        tex = tree.nodes.new("ShaderNodeTexImage")
        tex.image = bpy.data.images.load(str(folder / (name + ".png")))
        if data:
            tex.image.colorspace_settings.name = "Non-Color"
        return tex.outputs["Color"]
    tree.links.new(image("CoamingHD_Base", False), bsdf.inputs["Base Color"])
    bump = tree.nodes.new("ShaderNodeNormalMap")
    tree.links.new(image("CoamingHD_Normal", True), bump.inputs["Color"])
    tree.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    split = tree.nodes.new("ShaderNodeSeparateColor")
    tree.links.new(image("CoamingHD_ORM", True), split.inputs["Color"])
    tree.links.new(split.outputs["Green"], bsdf.inputs["Roughness"])
    tree.links.new(split.outputs["Blue"], bsdf.inputs["Metallic"])
    return material


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    print("COAMING", f"{LEN:.3f} m long, {WID * 1000:.0f} mm across, {KS / 1000:.2f} x {KT / 1000:.2f} texels/mm at {RES}", flush=True)
    with tempfile.TemporaryDirectory() as tmp:
        textures(Path(tmp))
        build(pbr(Path(tmp)))
        bpy.ops.export_scene.gltf(filepath=str(OUTPUT), export_tangents=True, export_animations=False,
                                  export_cameras=False, export_lights=False)
    print("Wrote", OUTPUT, OUTPUT.stat().st_size, "bytes")


if __name__ == "__main__":
    main()
