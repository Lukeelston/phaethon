"""Bake four rigged-by-part airframes, in metres (+Y up, +Z aft).

Usage: python tools/art_pilot_fleet.py [orrery|kiln|vesper|basilisk ...]. Fixed fittings
are welded into their parent mesh. Parts with a flight-system pivot are local
to that pivot. The four drives mate to the game's standard vectoring nozzle.
The Basilisk also carries its gun's moving parts (GunHatch, GunRing, GunCradle,
GunCoils, SightBall, SightLens), each local to its own pivot: view/turret.gd.
"""

import math
import sys
from itertools import pairwise

import numpy as np
from art_pilot_fleet_finish import ART, FLEET, REGIONS, make_maps
from art_shrike_airframe import TAU, Mesh, signed, unit, vec, write_glb


class Surface(Mesh):
    def vertex(self, p, n, uv, region):
        x, y, w, h = REGIONS[region]
        self.pos.append(p)
        self.norm.append(n)
        self.uv.append(((x + 4 + uv[0] * (w - 8)) / 1024, (y + 4 + uv[1] * (h - 8)) / 1024))


def loft(m, rows, mat, exp=0.78, sides=32, closed=True):
    """Rows are z, centre x/y, radii x/y; rolled edges keep their highlights."""
    rows = np.asarray(rows, dtype=float)

    def ring(row, a):
        z, x, y, w, h = row
        return vec(x + w * signed(math.cos(a), exp), y + h * signed(math.sin(a), exp), z)

    def at(u, v):
        f = u * (len(rows) - 1)
        i = min(int(f), len(rows) - 2)
        return ring(rows[i] + (rows[i + 1] - rows[i]) * (f - i), TAU * v - math.pi * 0.5)

    m.grid(len(rows) - 1, sides, at, mat, True)
    if closed:
        for i, n in [(0, (0, 0, -1)), (-1, (0, 0, 1))]:
            m.poly([ring(rows[i], TAU * k / sides) for k in range(sides)], n, mat)


def skin_patch(m, rows, start, end, angles, exp, mat, lift=0.012):
    """Stamp a curved plate onto a specified run of skin. Its edges follow the host loft."""
    table = np.asarray(rows)

    def at(u, v):
        f = start + (end - start) * u
        i = min(int(f), len(rows) - 2)
        z, x, y, w, h = table[i] + (table[i + 1] - table[i]) * (f - i)
        a = math.radians(angles[0] + (angles[1] - angles[0]) * v)
        return vec(
            x + (w + lift) * signed(math.cos(a), exp), y + (h + lift) * signed(math.sin(a), exp), z
        )

    m.grid(max(3, math.ceil((end - start) * 4)), 7, at, mat, True)


def hoop(m, z, x, y, w, h, t, depth, mat, exp=0.94):
    rows = [
        (z + dz, x, y, w * scale, h * scale)
        for dz, scale in [
            (-depth * 0.46, 1 - t),
            (-depth * 0.5, 1 - t * 0.65),
            (-depth * 0.46, 1 - t * 0.18),
            (-depth * 0.34, 1),
            (depth * 0.34, 1),
            (depth * 0.49, 1 - t * 0.18),
            (depth * 0.5, 1 - t * 0.70),
            (depth * 0.44, 1 - t),
            (-depth * 0.46, 1 - t),
        ]
    ]
    loft(m, rows, mat, exp, 40, False)


def tube(m, pts, r, mat, n=10):
    for a, b in pairwise(pts):
        m.pipe(a, b, r, mat, n)


def badge(m, z, x, y, side, width, height):
    # A plaque reads nose-to-tail on port, tail-to-nose on starboard.
    right = vec(0, 0, -side * width / 2)
    up = vec(0, height / 2, 0)
    p = vec(side * x, y, z)
    m.poly(
        [p - right + up, p + right + up, p + right - up, p - right - up],
        (side, 0, 0),
        "badge",
        [(0, 0), (1, 0), (1, 1), (0, 1)],
    )


def blade(m, pts, thickness, mat, normal=(0, 1, 0)):
    m.panel(pts, vec(*normal), mat, thickness, "dark")


def shared_engine(m, side, craft):
    # A forged two-cheek hanger from the nozzle cradle to the simulated yoke.
    for s in (-1, 1):
        x = s * 0.11
        blade(
            m,
            [(x, -0.43, 2.66), (x, -0.49, 3.62), (x, -0.97, 3.59), (x, -1.04, 3.45), (x, -0.92, 3.29)],
            0.032,
            "brushed",
            (s, 0, 0),
        )
    m.pipe((-0.18, -0.95, 3.45), (0.18, -0.95, 3.45), 0.073, "gold", 16)
    # Saddle blending the round core into the rectangular thrust-vector cassette.
    loft(
        m,
        [
            (2.56, 0, 0, 0.78, 0.45),
            (2.73, 0, 0, 1.05, 0.51),
            (2.93, 0, 0, 1.03, 0.49),
            (3.58, 0, 0, 1.02, 0.45),
            (3.82, 0, 0, 0.96, 0.42),
        ],
        "brushed",
        0.50,
        32,
        False,
    )
    for z in (2.85, 3.09, 3.36):
        hoop(m, z, 0, 0, 1.06, 0.49, 0.043, 0.055, "gold" if craft == "orrery" else "dark", 0.49)
    # The pilot sees the exhaust end most of the time. Each outer jacket
    # surrounds the working vector nozzle, leaving its full swept slot free.
    if craft == "orrery":
        hoop(m, 4.12, 0, 0.03, 1.32, 0.86, 0.11, 0.25, "gold")
        for a in (0, math.pi * 0.25, math.pi * 0.75, math.pi):
            x, y = math.cos(a), math.sin(a)
            tube(
                m,
                [(0.92 * x, 0.47 * y, 2.79), (1.13 * x, 0.69 * y, 3.42), (1.26 * x, 0.83 * y, 4.13)],
                0.068,
                "accent",
            )
    elif craft == "kiln":
        for s in (-1, 1):
            loft(
                m,
                [
                    (2.52, s * 1.01, 0.10, 0.14, 0.42),
                    (2.70, s * 1.12, 0.18, 0.19, 0.52),
                    (3.84, s * 1.12, 0.19, 0.19, 0.52),
                    (4.43, s * 1.14, 0.11, 0.14, 0.43),
                    (4.53, s * 1.12, 0.10, 0.11, 0.34),
                ],
                "accent",
                0.34,
                24,
            )
            for j in range(4):
                z = 2.88 + j * 0.27
                tube(m, [(s * 1.30, 0.03, z), (s * 1.30, 0.46, z + 0.09)], 0.047, "dark", 8)
    else:
        for s in (-1, 1):
            loft(
                m,
                [
                    (2.29, s * 0.92, 0.21, 0.13, 0.15),
                    (2.83, s * 1.08, 0.30, 0.19, 0.20),
                    (3.65, s * 1.19, 0.46, 0.20, 0.15),
                    (4.16, s * 1.24, 0.58, 0.15, 0.11),
                    (4.98, s * 1.31, 0.76, 0.025, 0.023),
                ],
                "enamel",
                0.54,
                24,
            )
            tube(
                m,
                [(s * 0.98, 0.37, 2.58), (s * 1.26, 0.58, 3.77), (s * 1.31, 0.76, 4.94)],
                0.029,
                "gold",
                8,
            )
    # Feet under the cross-engine binder so its emitter emerges from actual metal.
    m.pipe((-side * 0.45, 0, -2.9), (-side * 1.23, 0, -2.9), 0.18, "brushed", 16)
    # Outer actuators, common mounting centres for distinct moving leaves.
    for s in (-1, 1):
        m.pipe((s * 0.52, 0.02, -3.25), (s * 1.24, 0, -3.25), 0.077, "gold", 12)
        for up in (-1, 1):
            m.pipe((s * 0.44, up * 0.43, 1.40), (s * 0.71, up * 0.50, 1.40), 0.065, "alloy", 12)


def orrery_engine(m, side):
    loft(
        m,
        [
            (-4.05, 0, 0.12, 0.19, 0.19),
            (-3.82, 0, 0.12, 0.43, 0.43),
            (-2.9, 0, 0.12, 0.49, 0.49),
            (-1.5, 0, 0.12, 0.36, 0.36),
            (0.75, 0, 0.12, 0.47, 0.47),
            (2.60, 0, 0.02, 0.82, 0.53),
        ],
        "dark",
    )
    for z, w, h in [(-3.52, 1.36, 1.19), (-1.23, 1.49, 1.30), (1.04, 1.32, 1.14)]:
        hoop(m, z, 0, 0.19, w, h, 0.22, 0.47, "enamel")
        for dz in (-0.19, 0.19):
            hoop(m, z + dz, 0, 0.19, w * 1.012, h * 1.012, 0.07, 0.063, "gold")
        hoop(m, z, 0, 0.19, w * 0.794, h * 0.794, 0.047, 0.19, "accent")
        for i in range(8):
            a = i * TAU / 8
            m.pipe(
                (0.39 * math.cos(a), 0.14 + 0.39 * math.sin(a), z + 0.24),
                (w * 0.83 * math.cos(a + 0.16), 0.19 + h * 0.83 * math.sin(a + 0.16), z),
                0.045,
                "alloy",
                8,
            )
    for i in range(3):
        pts = []
        for j in range(19):
            t = j / 18
            a = TAU * (i / 3 + 0.29 * t)
            pts.append((1.25 * math.cos(a), 0.19 + 1.05 * math.sin(a), -3.45 + t * 4.56))
        tube(m, pts, 0.045, "gold", 8)
    # Swept mounting keel and outer spine carrying the survey registration.
    for s in (-1, 1):
        tube(
            m,
            [
                (s * 0.89, 0.0, -3.36),
                (s * 1.22, 0.18, -1.20),
                (s * 1.08, 0.14, 1.04),
                (s * 0.72, -0.1, 2.74),
            ],
            0.094,
            "accent",
        )
    loft(
        m,
        [
            (-1.96, side * 1.2, 0.16, 0.12, 0.11),
            (-1.66, side * 1.30, 0.17, 0.15, 0.19),
            (-0.58, side * 1.30, 0.17, 0.15, 0.19),
            (-0.32, side * 1.2, 0.17, 0.10, 0.095),
        ],
        "accent",
        0.35,
    )
    badge(m, -1.13, 1.455, 0.17, side, 0.94, 0.235)
    for j in range(10):
        a = TAU * j / 10
        x, y = math.cos(a), math.sin(a)
        m.pipe(
            (0.51 * x, 0.12 + 0.49 * y, -0.67),
            (0.77 * x, 0.15 + 0.69 * y, -0.54),
            0.092,
            "ceramic",
            10,
            0.065,
        )
        tube(
            m,
            [
                (0.79 * x, 0.15 + 0.70 * y, -0.53),
                (0.86 * x, 0.15 + 0.76 * y, 0.14),
                (1.06 * x, 0.19 + 0.92 * y, 0.84),
            ],
            0.043,
            "gold",
            8,
        )
    hoop(m, 2.15, 0, 0.02, 0.82, 0.60, 0.10, 0.13, "accent")


def kiln_engine(m, side):
    loft(
        m,
        [
            (-4.14, 0, 0, 0.89, 0.59),
            (-3.98, 0, 0, 1.04, 0.72),
            (-3.42, 0, 0, 1.09, 0.72),
            (-2.97, 0, -0.05, 0.81, 0.54),
            (-2.64, 0, -0.12, 0.76, 0.41),
            (1.31, 0, -0.12, 0.80, 0.44),
            (1.58, 0, -0.06, 1.09, 0.64),
            (2.41, 0, -0.06, 1.04, 0.63),
            (2.78, 0, -0.04, 0.90, 0.48),
        ],
        "dark",
        0.36,
        36,
        False,
    )
    hoop(m, -4.03, 0, 0, 1.085, 0.76, 0.19, 0.31, "accent", 0.39)
    hoop(m, -3.57, 0, 0, 1.10, 0.745, 0.08, 0.15, "brushed", 0.39)
    for s in (-1, 1):
        # Long box-section skids, three individual finned cylinders per bank.
        loft(
            m,
            [
                (-3.53, s * 0.91, -0.40, 0.13, 0.12),
                (-2.70, s * 1.05, -0.44, 0.17, 0.15),
                (1.42, s * 1.05, -0.45, 0.17, 0.15),
                (2.62, s * 0.84, -0.39, 0.12, 0.11),
            ],
            "accent",
            0.34,
        )
        for j in range(3):
            z = -2.11 + j * 1.10
            a = vec(s * 0.51, 0.09, z)
            b = vec(s * 0.99, 0.80, z + 0.20)
            m.pipe(a, b, 0.34, "dark", 12, 0.31)
            for t in (0.23, 0.40, 0.57, 0.74):
                p = a + (b - a) * t
                m.pipe(p, p + (b - a) * 0.066, 0.39, "brushed", 12)
            m.pipe(b - (b - a) * 0.12, b + (b - a) * 0.08, 0.36, "enamel", 8, 0.32)
            # Individual bronze hot headers fold down to the common collector.
            tube(
                m,
                [
                    b + vec(0, -0.08, 0.24),
                    vec(s * 1.32, 0.60, z + 0.34),
                    vec(s * 1.39, 0.17, z + 0.45),
                    vec(s * 1.31, -0.13, z + 0.63),
                ],
                0.11,
                "gold",
                12,
            )
        m.pipe((s * 1.31, -0.13, -1.73), (s * 1.31, -0.13, 1.46), 0.17, "gold", 16)
        tube(
            m,
            [(s * 1.31, -0.13, 1.46), (s * 1.23, -0.12, 1.82), (s * 0.84, -0.16, 2.34)],
            0.16,
            "brushed",
        )
    loft(
        m,
        [
            (1.43, 0, 0.04, 1.10, 0.61),
            (1.60, 0, 0.05, 1.16, 0.67),
            (2.34, 0, 0.05, 1.16, 0.67),
            (2.54, 0, 0.05, 1.06, 0.55),
        ],
        "access",
        0.28,
    )
    badge(m, 1.96, 1.166, 0.05, side, 0.70, 0.177)
    for i in range(3):
        z = -2.30 + 1.10 * i
        for s in (-1, 1):
            tube(
                m,
                [(s * 0.76, -0.24, z), (s * 0.90, -0.27, z + 0.21), (s * 0.94, -0.22, z + 0.66)],
                0.037,
                "alloy",
                8,
            )
    blade(
        m,
        [(-0.72, 0.735, 1.62), (0.72, 0.735, 1.62), (0.72, 0.735, 2.29), (-0.72, 0.735, 2.29)],
        0.009,
        "number",
    )
    for z in (-3.11, 1.63, 2.31):
        hoop(m, z, 0, 0, 1.105 if z < 0 else 1.17, 0.74, 0.055, 0.092, "accent", 0.36)
    loft(
        m,
        [
            (-2.75, 0, 0.48, 0.22, 0.08),
            (-2.52, 0, 0.59, 0.30, 0.14),
            (0.77, 0, 0.60, 0.30, 0.14),
            (1.38, 0, 0.52, 0.25, 0.10),
        ],
        "enamel",
        0.39,
    )


def vesper_engine(m, side):
    # Bifurcated wing inlets open on either side of a continuous daylight slot.
    for s in (-1, 1):
        sign = s * side
        rows = [
            (-4.67, sign * 0.79, 0.02, 0.41, 0.22),
            (-4.48, sign * 0.81, 0.06, 0.52, 0.30),
            (-3.74, sign * 0.88, 0.13, 0.57, 0.35),
            (-2.88, sign * 0.91, 0.22, 0.57, 0.36),
            (-1.62, sign * 0.85, 0.29, 0.53, 0.32),
            (-0.48, sign * 0.70, 0.22, 0.50, 0.31),
            (0.84, sign * 0.46, 0.08, 0.52, 0.33),
            (2.30, sign * 0.30, 0, 0.57, 0.38),
            (2.8, sign * 0.25, 0, 0.50, 0.36),
        ]
        loft(m, rows, "enamel", 0.53, 32, False)
        for j, (a, b) in enumerate(((0.37, 1.92), (2.0, 3.60), (3.72, 5.10), (5.22, 6.8))):
            skin_patch(m, rows, a, b, (45, 131), 0.53, "access" if j % 2 == 0 else "stripe")
        skin_patch(m, rows, 2.40, 3.08, (64, 115), 0.53, "number", 0.026)
        hoop(m, -4.59, sign * 0.8, 0.035, 0.444, 0.251, 0.15, 0.14, "accent", 0.55)
        loft(
            m,
            [(-4.62, sign * 0.80, 0.022, 0.37, 0.17), (-4.20, sign * 0.80, 0.03, 0.34, 0.15)],
            "dark",
            0.55,
            24,
            False,
        )
        # Blade tips grow from the intake shoulders, with a thin foil section.
        wing = [
            (-3.75, sign * 1.04, 0.13, 0.16, 0.11),
            (-2.73, sign * 1.34, 0.21, 0.24, 0.13),
            (-1.12, sign * 1.60, 0.31, 0.40, 0.11),
            (0.72, sign * 1.81, 0.44, 0.47, 0.085),
            (1.67, sign * 2.13, 0.54, 0.29, 0.065),
            (2.13, sign * 2.34, 0.59, 0.03, 0.024),
        ]
        loft(m, wing, "accent", 0.84)
        loft(m, [(z, x, y + 0.058, w * 0.40, h * 0.56) for z, x, y, w, h in wing], "stripe", 0.79)
        m.pipe((sign * 1.38, 0.19, -2.72), (sign * 1.88, 0.44, 0.92), 0.034, "gold", 8)
    loft(
        m,
        [
            (-2.12, 0, 0, 0.047, 0.065),
            (-0.61, 0, 0.06, 0.12, 0.12),
            (0.79, 0, 0.13, 0.56, 0.30),
            (1.69, 0, 0.13, 0.92, 0.42),
            (2.68, 0, 0.03, 0.88, 0.46),
        ],
        "brushed",
    )
    for z in (1.16, 1.38, 1.6, 1.82):
        loft(m, [(z, 0, 0.48, 0.53, 0.034), (z + 0.08, 0, 0.46, 0.56, 0.028)], "vent", 0.55, 14)
    badge(m, -2.92, 1.482, 0.218, side, 0.86, 0.18)


def outboard_patch(m, rows, a, b, side, half, exp, region, lift=0.012):
    """A plate on the outboard flank, its paint upright and reading forward from either side: on the
    starboard side the run and the sweep are taken the other way about (skin_patch's own order reads
    mirrored and upside down there)."""
    if side > 0:
        skin_patch(m, rows, b, a, (half, -half), exp, region, lift)
    else:
        skin_patch(m, rows, a, b, (180 - half, 180 + half), exp, region, lift)


def at_rows(rows, z):
    """A loft's centre x/y and radii at station z, read between its rows."""
    table = np.asarray(rows, dtype=float)
    return [float(np.interp(z, table[:, 0], table[:, k])) for k in range(1, 5)]


BASILISK_BODY = [
    (-4.52, 0, 0.03, 0.88, 0.50),
    (-4.34, 0, 0.04, 1.03, 0.60),
    (-3.55, 0, 0.05, 1.10, 0.66),
    (-2.40, 0, 0.03, 1.04, 0.62),
    (-0.60, 0, 0.0, 0.94, 0.56),
    (1.20, 0, -0.02, 0.96, 0.54),
    (2.10, 0, -0.02, 1.02, 0.52),
    (2.72, 0, -0.02, 0.90, 0.46),
]


def basilisk_engine(m, side):
    # An armoured interceptor drive: a hard-chined body, twin inlets either side of a raked
    # splitter, a heat-sink comb along the spine and a short strake on the outboard cheek.
    body = BASILISK_BODY
    exp = 0.42
    loft(m, body, "enamel", exp, 36, False)
    for j, (a, b) in enumerate(((1.1, 1.95), (2.05, 2.95), (3.05, 3.95), (4.05, 4.95), (5.05, 6.0))):
        skin_patch(m, body, a, b, (38, 142), exp, "access" if j % 2 == 0 else "stripe")
    outboard_patch(m, body, 2.15, 2.85, side, 32, exp, "number", 0.024)
    outboard_patch(m, body, 4.15, 5.6, side, 32, exp, "stripe", 0.014)
    hoop(m, -4.44, 0, 0.035, 0.955, 0.555, 0.13, 0.15, "accent", exp)
    loft(m, [(-4.47, 0, 0.035, 0.86, 0.48), (-3.95, 0, 0.04, 0.84, 0.46)], "dark", exp, 28, False)
    # The splitter: a vertical wedge, its knife edge raked forward of the lip.
    loft(
        m,
        [
            (-4.95, 0, 0.03, 0.012, 0.05),
            (-4.62, 0, 0.035, 0.05, 0.36),
            (-4.20, 0, 0.04, 0.07, 0.47),
            (-3.90, 0, 0.04, 0.06, 0.45),
        ],
        "brushed",
        0.6,
        16,
    )
    # Armour belts at three stations, and a chin keel under the whole run.
    for z in (-3.05, -1.25, 0.95):
        x, y, w, h = at_rows(body, z)
        hoop(m, z, x, y, w + 0.012, h + 0.012, 0.05, 0.085, "dark", exp)
    loft(
        m,
        [
            (-3.60, 0, -0.56, 0.10, 0.06),
            (-3.20, 0, -0.64, 0.20, 0.11),
            (1.40, 0, -0.60, 0.22, 0.11),
            (2.30, 0, -0.50, 0.12, 0.06),
        ],
        "dark",
        0.40,
    )
    # The spine and its comb: eight raked plates standing on it.
    spine = []
    for z in (-2.85, -2.70, -0.25, -0.05):
        x, y, w, h = at_rows(body, z)
        spine.append((z, 0, y + h - 0.01, 0.20 if -2.8 < z < -0.1 else 0.10, 0.05))
    loft(m, spine, "brushed", 0.5, 18)
    for i in range(8):
        z = -2.55 + i * 0.30
        top = at_rows(body, z)[1] + at_rows(body, z)[3] + 0.02
        blade(
            m,
            [(-0.33, top, z), (0.33, top, z), (0.27, top + 0.15, z + 0.11), (-0.27, top + 0.15, z + 0.11)],
            0.014,
            "vent",
            (0, 0, 1),
        )
    # Outboard strake, swept from the intake shoulder; a power conduit along the inboard flank.
    sx = side
    loft(
        m,
        [
            (-3.95, sx * 1.06, 0.10, 0.04, 0.03),
            (-3.25, sx * 1.30, 0.12, 0.11, 0.035),
            (-2.30, sx * 1.42, 0.12, 0.08, 0.028),
            (-1.65, sx * 1.27, 0.11, 0.025, 0.018),
        ],
        "accent",
        0.84,
    )
    tube(m, [(-sx * 1.02, -0.13, -3.1), (-sx * 1.0, -0.15, -1.2), (-sx * 0.97, -0.16, 1.7)], 0.048, "gold", 10)
    for z in (-2.6, -1.6, -0.6, 0.4, 1.4):
        m.pipe((-sx * 0.95, -0.15, z), (-sx * 1.06, -0.13, z + 0.03), 0.062, "dark", 10)
    x, y, w, h = at_rows(body, -1.85)
    badge(m, -1.85, w + 0.006, 0.03, side, 0.86, 0.17)


DRIVES = {"orrery": orrery_engine, "kiln": kiln_engine, "vesper": vesper_engine, "basilisk": basilisk_engine}


def engine(craft, s):
    m = Surface()
    DRIVES[craft](m, s)
    shared_engine(m, s, craft)
    return m


def rotor(craft):
    m = Surface()
    r = {"orrery": 0.88, "kiln": 0.44, "vesper": 0.245, "basilisk": 0.33}[craft]
    if craft == "orrery":
        hoop(m, 0, 0, 0, r, r, 0.065, 0.065, "gold")
    count = {"orrery": 6, "kiln": 11, "vesper": 8, "basilisk": 9}[craft]
    for i in range(count):
        a = i * TAU / count

        def p(v, t, z, angle=a):
            return (r * v * math.cos(angle + t), r * v * math.sin(angle + t), z)

        blade(
            m,
            [
                p(0.18, 0, -0.06),
                p(0.92, 0.24, -0.045),
                p(0.98, 0.51, 0.04),
                p(0.47, 0.33, 0.055),
                p(0.17, 0.30, 0.015),
            ],
            0.021,
            "gold" if i == 0 or craft == "orrery" else "alloy",
            (0, 0, -1),
        )
    m.pipe((0, 0, 0.092), (0, 0, -0.087), r * 0.23, "brushed", 20, r * 0.15)
    return m


def brake(craft, front=False, pod=False):
    m = Surface()
    w, l = {"orrery": (0.22, 0.90), "kiln": (0.32, 0.82), "vesper": (0.335, 1.12), "basilisk": (0.30, 0.86)}[craft]
    if pod:
        l *= 0.78
    elif front:
        l *= 0.93
    w *= 0.64 if pod else 1
    # A shallow-bent honeycomb leaf. Positive Z is aft of the hinge.
    rows = [
        (0, 0, 0, w * 0.72, 0.027),
        (0.06, 0, 0.012, w, 0.037),
        (l * 0.55, 0, 0.04, w * (1 if craft == "kiln" else 0.87), 0.034),
        (l, 0, 0.085, w * ({"orrery": 0.52, "kiln": 0.88, "vesper": 0.15, "basilisk": 0.62}[craft]), 0.016),
    ]
    loft(m, rows, "stripe" if not pod else "accent", 0.45, 20)
    for s in (-1, 1):
        tube(
            m,
            [
                (s * w * 0.49, -0.028, 0.07),
                (s * w * 0.44, -0.015, l * 0.53),
                (s * w * 0.20, 0.057, l * 0.92),
            ],
            0.016,
            "brushed",
            8,
        )
    return m


# Cab profiles use two continuous sills outside the pilot's working envelope.
# The centre stays open for the flight deck; the bulkheads close both ends.
SILLS = {
    "orrery": [
        (-2.29, 0.26, -0.17, 0.10, 0.11),
        (-1.99, 0.43, -0.17, 0.17, 0.18),
        (-1.29, 0.67, -0.18, 0.22, 0.23),
        (-0.40, 0.88, -0.20, 0.21, 0.29),
        (0.55, 0.94, -0.20, 0.23, 0.32),
        (1.21, 0.85, -0.17, 0.24, 0.32),
        (1.82, 0.63, -0.09, 0.21, 0.31),
        (2.24, 0.26, -0.02, 0.16, 0.22),
        (2.37, 0.10, 0, 0.07, 0.09),
    ],
    "kiln": [
        (-2.19, 0.59, -0.19, 0.19, 0.23),
        (-2.06, 0.70, -0.18, 0.26, 0.28),
        (-1.21, 0.77, -0.19, 0.26, 0.28),
        (-0.78, 0.84, -0.17, 0.30, 0.33),
        (1.19, 0.84, -0.17, 0.30, 0.33),
        (1.52, 0.84, -0.15, 0.30, 0.34),
        (1.79, 0.74, -0.17, 0.25, 0.30),
        (1.85, 0.67, -0.17, 0.18, 0.23),
    ],
    "vesper": [
        (-2.84, 0.49, -0.12, 0.045, 0.05),
        (-2.32, 0.55, -0.15, 0.14, 0.14),
        (-1.54, 0.69, -0.18, 0.20, 0.20),
        (-0.44, 0.87, -0.19, 0.19, 0.23),
        (0.48, 0.94, -0.15, 0.21, 0.25),
        (1.29, 1.10, -0.075, 0.25, 0.26),
        (1.91, 1.32, 0.03, 0.23, 0.18),
        (2.50, 1.50, 0.13, 0.12, 0.09),
        (2.75, 1.53, 0.17, 0.025, 0.025),
    ],
    # A long wedge nose; the shoulders carry the sponsons (cab()).
    "basilisk": [
        (-2.40, 0.46, -0.20, 0.10, 0.14),
        (-2.18, 0.60, -0.19, 0.20, 0.24),
        (-1.30, 0.74, -0.19, 0.25, 0.28),
        (-0.80, 0.82, -0.18, 0.28, 0.32),
        (1.15, 0.82, -0.17, 0.28, 0.32),
        (1.55, 0.80, -0.15, 0.27, 0.32),
        (1.85, 0.70, -0.16, 0.22, 0.27),
        (1.95, 0.60, -0.17, 0.14, 0.18),
    ],
}


def aft_bulkhead(m, craft):
    ends = {"orrery": (2.38, 0.80, 0.43), "kiln": (1.86, 0.97, 0.34), "vesper": (1.89, 0.67, 0.20), "basilisk": (1.95, 0.90, 0.31)}
    z, w, h = ends[craft]
    loft(
        m,
        [
            (1.13, 0, -0.18, 0.71, 0.21),
            (1.29, 0, -0.11, w * 0.97, h),
            (z - 0.18, 0, -0.12, w * (0.59 if craft == "orrery" else 0.91), h * 0.86),
            (z, 0, -0.12, w * (0.35 if craft == "orrery" else 0.77), h * 0.60),
        ],
        "access",
        0.36 if craft == "kiln" else 0.80,
    )
    for s in (-1, 1):
        for i in range(3):
            x = s * (0.14 + i * 0.105)
            m.pipe((x, -0.11, z - 0.008), (x, -0.11, z + 0.024), 0.041, "dark", 14)


def cab(craft):
    m = Surface()
    rows = []
    for z, x, y, w, h in SILLS[craft]:
        if -0.85 < z < 1.25:
            # The standard side consoles run out to x=.72. Leave the consoles
            # and pilot's hands clear of the inside of the sill.
            x = max(x, 0.79 + w)
        rows.append((z, x, y, w, h))
    exp = {"orrery": 0.87, "kiln": 0.32, "vesper": 0.69, "basilisk": 0.40}[craft]
    for s in (-1, 1):
        body = [(z, x * s, y, w, h) for z, x, y, w, h in rows]
        loft(m, body, "enamel", exp)
        angles = (40, 110) if s > 0 else (70, 140)
        for j in range(1, len(body) - 2):
            skin_patch(m, body, j + 0.07, j + 0.92, angles, exp, "access", 0.009)
        skin_patch(m, body, 2.28, 2.81, angles, exp, "number", 0.022)
        trim = [(z, s * (x + w * 0.75), y + h * 0.31, w * 0.29, h * 0.29) for z, x, y, w, h in rows]
        loft(m, trim, "accent", exp, 20)
        # Shorter fairlead with paired fork cheeks either side of each drawbar.
        tube(
            m,
            [(s * 0.18, -0.015, -2.10), (s * 0.37, -0.18, -1.70), (s * 0.67, -0.34, -1.10)],
            0.074,
            "brushed",
            12,
        )
        for dx in (-0.065, 0.065):
            x = s * 0.18 + dx
            blade(
                m,
                [
                    (x, -0.07, -2.21),
                    (x, 0.06, -2.19),
                    (x, 0.082, -2.10),
                    (x, -0.10, -1.86),
                    (x, -0.19, -1.96),
                ],
                0.022,
                "gold",
                (1, 0, 0),
            )
        m.pipe((s * 0.18 - 0.11, 0, -2.1), (s * 0.18 + 0.11, 0, -2.1), 0.050, "alloy", 16)
    loft(
        m,
        [
            (-2.18, 0, -0.20, 0.25, 0.11),
            (-1.87, 0, -0.30, 0.43, 0.12),
            (-0.84, 0, -0.42, 0.78, 0.13),
            (0.60, 0, -0.45, 0.86, 0.13),
            (1.46, 0, -0.32, 0.77, 0.14),
            (1.66, 0, -0.24, 0.53, 0.11),
        ],
        "dark",
        0.44,
        32,
    )
    aft_bulkhead(m, craft)
    if craft == "orrery":
        for s in (-1, 1):
            for z in (-1.45, -0.98, 1.34, 1.63):
                tube(
                    m,
                    [(s * 0.46, -0.32, z), (s * 0.70, -0.19, z + 0.04), (s * 0.73, -0.08, z + 0.09)],
                    0.027,
                    "gold",
                    8,
                )
            loft(
                m,
                [
                    (-1.04, s * 0.64, -0.27, 0.07, 0.08),
                    (-0.35, s * 1.13, -0.30, 0.16, 0.18),
                    (0.85, s * 1.13, -0.30, 0.16, 0.18),
                    (1.56, s * 0.66, -0.18, 0.06, 0.07),
                ],
                "accent",
                0.55,
            )
            badge(m, 0.23, 1.294, -0.29, s, 0.88, 0.205)
            for z in (1.04, 1.18, 1.32, 1.46):
                tube(
                    m,
                    [(s * 0.92, 0.057, z), (s * 0.84, 0.13, z + 0.05), (s * 0.71, 0.16, z + 0.08)],
                    0.026,
                    "gold",
                    8,
                )
        hoop(m, 1.88, 0, -0.12, 0.54, 0.36, 0.09, 0.08, "gold")
    elif craft == "kiln":
        for s in (-1, 1):
            tube(
                m,
                [
                    (s * 0.74, -0.48, -2.27),
                    (s * 1.145, -0.41, -1.35),
                    (s * 1.20, -0.40, 1.42),
                    (s * 0.92, -0.40, 1.91),
                ],
                0.065,
                "brushed",
                12,
            )
            for z in (-0.91, -0.42, 0.65, 1.23):
                m.pipe((s * 1.13, -0.23, z), (s * 1.20, -0.40, z + 0.12), 0.042, "gold", 10)
            loft(
                m,
                [
                    (-0.61, s * 1.24, -0.15, 0.07, 0.11),
                    (-0.52, s * 1.25, -0.15, 0.15, 0.17),
                    (0.50, s * 1.25, -0.15, 0.15, 0.17),
                    (0.58, s * 1.24, -0.15, 0.07, 0.11),
                ],
                "dark",
                0.28,
                18,
            )
            badge(m, -0.01, 1.405, -0.15, s, 0.94, 0.226)
            for z in (0.83, 1.03, 1.23):
                tube(
                    m,
                    [(s * 1.15, 0.11, z), (s * 1.24, 0.03, z + 0.07), (s * 1.25, -0.09, z + 0.11)],
                    0.028,
                    "brushed",
                    8,
                )
        tube(
            m,
            [(-0.84, -0.38, -2.12), (-0.57, -0.38, -2.34), (0.57, -0.38, -2.34), (0.84, -0.38, -2.12)],
            0.085,
            "brushed",
        )
    elif craft == "basilisk":
        basilisk_sponsons(m)
    else:
        for s in (-1, 1):
            vane = [
                (0.28, s * 0.96, -0.05, 0.09, 0.07),
                (0.80, s * 1.08, 0.04, 0.18, 0.09),
                (1.43, s * 1.35, 0.18, 0.27, 0.07),
                (2.56, s * 1.70, 0.37, 0.11, 0.04),
                (2.75, s * 1.78, 0.42, 0.017, 0.017),
            ]
            loft(m, vane, "accent", 0.80)
            loft(
                m,
                [
                    (-1.04, s * 0.82, -0.12, 0.125, 0.10),
                    (-0.66, s * 1.08, -0.10, 0.18, 0.15),
                    (0.33, s * 1.08, -0.10, 0.18, 0.15),
                    (0.64, s * 1.01, -0.10, 0.10, 0.10),
                ],
                "enamel",
                0.42,
                20,
            )
            badge(m, -0.16, 1.265, -0.105, s, 0.72, 0.162)
            for z in (0.78, 0.91, 1.04, 1.17):
                blade(
                    m,
                    [
                        (s * 0.86, 0.12, z),
                        (s * 0.94, 0.13, z + 0.016),
                        (s * 1.04, 0.16, z + 0.15),
                        (s * 0.96, 0.15, z + 0.13),
                    ],
                    0.013,
                    "gold",
                )
    return m


def bonnet(craft):
    m = Surface()
    w = {"orrery": 0.48, "kiln": 0.69, "vesper": 0.38, "basilisk": 0.62}[craft]
    loft(
        m,
        [
            (-2.04, 0, -0.12, 0.26, 0.047),
            (-1.77, 0, -0.10, w * 0.87, 0.065),
            (-1.04, 0, -0.081, w, 0.075),
            (-0.77, 0, -0.080, 0.56, 0.060),
        ],
        "stripe",
        0.53,
    )
    return m


def canopy(craft):
    frame, pane = Surface(), Surface()
    # Each hoop has a sill, shoulder and crown. The low bowed header is also
    # the actual mounting rail for the game's overhead switchgear and projector.
    profiles = {
        "orrery": [
            (-0.83, 0.58, 0.10, -0.18, 0.50, 0.47),
            (0.31, 0.91, 0.06, 0.34, 0.78, 0.64),
            (0.90, 0.90, 0.06, 0.97, 0.75, 0.65),
            (1.43, 0.71, 0.09, 1.41, 0.48, 0.53),
        ],
        "kiln": [
            (-0.88, 0.72, 0.10, 0.11, 0.62, 0.56),
            (0.48, 0.96, 0.13, 0.50, 0.75, 0.59),
            (1.03, 0.96, 0.13, 1.13, 0.76, 0.60),
            (1.51, 0.86, 0.13, 1.51, 0.71, 0.58),
        ],
        "vesper": [
            (-1.21, 0.49, 0.014, 0.10, 0.42, 0.51),
            (0.40, 0.86, 0.065, 0.44, 0.60, 0.56),
            (0.99, 0.89, 0.09, 1.0, 0.59, 0.56),
            (1.70, 0.69, 0.12, 1.42, 0.37, 0.48),
        ],
        # The Kiln's hoops (the header carries the overhead switchgear where the cockpit expects it).
        "basilisk": [
            (-0.88, 0.72, 0.10, 0.11, 0.62, 0.56),
            (0.48, 0.96, 0.13, 0.50, 0.75, 0.59),
            (1.03, 0.96, 0.13, 1.13, 0.76, 0.60),
            (1.51, 0.86, 0.13, 1.51, 0.71, 0.58),
        ],
    }
    rows = profiles[craft]

    def section(row, s):
        z, w, foot, topz, topw, topy = row
        # A curved crown on the observatory, bevelled on the tram, swept on the Vesper.
        return [
            vec(s * w, foot, z),
            vec(s * topw, (foot + topy) * 0.55, (z + topz) * 0.5),
            vec(s * topw * 0.87, topy - 0.047, topz),
            vec(0, topy, topz - 0.029),
        ]

    rail = 0.041 if craft in ("kiln", "basilisk") else 0.026
    # Front pane rakes back from the forward sill; leave an uninterrupted frontal view.
    first = rows[0]
    top_left, top_right = section(first, -1)[2], section(first, 1)[2]
    p = [section(first, -1)[0], section(first, 1)[0], top_right, top_left]
    pane.poly(p, (0, 0.4, -1), "alloy", [(0, 1), (1, 1), (1, 0), (0, 0)])
    for j, row in enumerate(rows):
        left, right = section(row, -1), section(row, 1)
        if j in (0, len(rows) - 1) or craft == "orrery":
            tube(
                frame, left + list(reversed(right[:-1])), rail, "gold" if craft == "orrery" else "enamel"
            )
        for s in (-1, 1):
            a = section(row, s)
            if j >= len(rows) - 1:
                continue
            b = section(rows[j + 1], s)
            tube(frame, [a[2], b[2]], rail * 1.1, "accent")
            tube(frame, [a[0], b[0]], rail * 1.25, "dark")
            for k in range(3):
                pane.poly(
                    [a[k], b[k], b[k + 1], a[k + 1]],
                    (s, 1 if k == 2 else 0.12, 0),
                    "alloy",
                    [(0, 1), (1, 1), (1, 0), (0, 0)],
                )
    if craft == "kiln":
        # Stamped steel roof, split by two skylights and carried by rear uprights.
        for s in (-1, 1):
            loft(
                frame,
                [
                    (0.05, s * 0.53, 0.52, 0.08, 0.035),
                    (0.22, s * 0.54, 0.57, 0.16, 0.049),
                    (1.33, s * 0.55, 0.59, 0.17, 0.056),
                    (1.55, s * 0.52, 0.55, 0.13, 0.046),
                ],
                "enamel",
                0.39,
                22,
            )
            tube(
                frame,
                [
                    (s * 0.64, 0.60, 0.36),
                    (s * 0.65, 0.69, 0.46),
                    (s * 0.65, 0.70, 1.27),
                    (s * 0.63, 0.62, 1.41),
                ],
                0.028,
                "brushed",
                8,
            )
        for z in (0.49, 1.31):
            loft(
                frame,
                [
                    (z, 0, 0.596, 0.65, 0.033),
                    (z + 0.12, 0, 0.61, 0.67, 0.045),
                    (z + 0.21, 0, 0.591, 0.65, 0.028),
                ],
                "accent",
                0.42,
                26,
            )
        loft(
            frame,
            [(0.18, 0, 0.55, 0.12, 0.042), (0.40, 0, 0.63, 0.13, 0.044), (1.50, 0, 0.61, 0.14, 0.039)],
            "dark",
            0.46,
            20,
        )
    elif craft == "orrery":
        # A raised observation cupola with brass glazing bars and a fluted cap.
        for j in range(7):
            a = TAU * j / 7
            pts = []
            for t in np.linspace(0, 1, 9):
                ph = t * math.pi * 0.5
                pts.append(
                    (
                        0.58 * math.cos(a) * math.cos(ph),
                        0.58 + 0.24 * math.sin(ph),
                        0.84 + 0.53 * math.sin(a) * math.cos(ph),
                    )
                )
            tube(frame, pts, 0.019, "gold", 8)
        mtop = [
            (0.53, 0, 0.786, 0.028, 0.018),
            (0.63, 0, 0.798, 0.17, 0.02),
            (0.84, 0, 0.811, 0.235, 0.033),
            (1.05, 0, 0.798, 0.17, 0.02),
            (1.15, 0, 0.786, 0.028, 0.018),
        ]
        loft(frame, mtop, "accent", 0.87, 26)
    elif craft == "basilisk":
        basilisk_roof(frame)
    else:
        # Dorsal fairing and buttresses continue the twin-keel silhouette over the cabin.
        loft(
            frame,
            [
                (0.12, 0, 0.507, 0.023, 0.019),
                (0.43, 0, 0.553, 0.088, 0.033),
                (0.85, 0, 0.593, 0.137, 0.050),
                (1.29, 0, 0.568, 0.193, 0.060),
                (1.80, 0, 0.40, 0.21, 0.075),
                (2.11, 0, 0.11, 0.10, 0.042),
            ],
            "enamel",
            0.63,
            26,
        )
        for s in (-1, 1):
            loft(
                frame,
                [
                    (1.0, s * 0.28, 0.50, 0.047, 0.030),
                    (1.39, s * 0.42, 0.46, 0.083, 0.063),
                    (1.80, s * 0.67, 0.21, 0.115, 0.062),
                    (2.18, s * 0.91, -0.02, 0.052, 0.031),
                ],
                "accent",
                0.68,
                18,
            )
    bar = [vec(0.41 * t, 0.47 - 0.035 * t * t, 0.30 + 0.14 * t * t) for t in np.linspace(-1, 1, 13)]
    tube(frame, bar, 0.022, "brushed", 10)
    for s in (-1, 1):
        tube(frame, [bar[0 if s < 0 else -1], section(rows[1], s)[2]], 0.024, "dark")
        if craft in ("kiln", "basilisk"):
            tube(frame, [section(rows[1], s)[0], section(rows[2], s)[2]], 0.039, "accent")
    return frame, pane


def seat(craft):
    m = Surface()
    mat = {"orrery": "cloth", "kiln": "rubber", "vesper": "dark", "basilisk": "rubber"}[craft]
    loft(
        m,
        [
            (0.42, 0, -0.43, 0.17, 0.04),
            (0.52, 0, -0.42, 0.25, 0.075),
            (0.80, 0, -0.43, 0.28, 0.075),
            (1.02, 0, -0.43, 0.26, 0.081),
            (1.12, 0, -0.40, 0.21, 0.044),
        ],
        mat,
        0.57,
    )
    # Shape the back in its upright frame, then tilt it back at the shoulders.
    back = Surface()
    levels = {
        "orrery": [(-0.43, 0.22), (-0.31, 0.28), (0.05, 0.31), (0.23, 0.22), (0.33, 0.15)],
        "kiln": [(-0.43, 0.25), (-0.29, 0.29), (0.12, 0.30), (0.28, 0.29), (0.34, 0.22)],
        "vesper": [(-0.43, 0.19), (-0.30, 0.24), (0.02, 0.33), (0.16, 0.31), (0.23, 0.17), (0.38, 0.14)],
        "basilisk": [(-0.43, 0.25), (-0.29, 0.29), (0.12, 0.30), (0.28, 0.29), (0.34, 0.22)],
    }[craft]
    loft(back, [(h, 0, 0, w, 0.082) for h, w in levels], "dark", 0.6)
    pads = 5 if craft == "orrery" else 3
    for i in range(pads):
        a = -0.32 + i * 0.54 / pads
        w = 0.22 if i < pads - 1 else 0.19
        loft(
            back,
            [
                (a, 0, 0.082, w * 0.91, 0.025),
                (a + 0.017, 0, 0.082, w, 0.034),
                (a + 0.54 / pads - 0.018, 0, 0.082, w, 0.034),
                (a + 0.54 / pads - 0.007, 0, 0.082, w * 0.93, 0.016),
            ],
            mat,
            0.50,
            20,
        )
    for s in (-1, 1):
        loft(
            back,
            [
                (-0.35, s * 0.21, 0.065, 0.034, 0.045),
                (-0.18, s * 0.25, 0.09, 0.051, 0.074),
                (0.07, s * 0.27, 0.09, 0.057, 0.074),
                (0.18, s * 0.21, 0.06, 0.031, 0.04),
            ],
            "accent",
            0.74,
            18,
        )
    # -90 degrees about X brings local Z up and local Y toward the driver.
    for i, (x, y, z) in enumerate(back.pos):
        back.pos[i] = vec(x, z, 1.10 - y + (z + 0.4) * 0.12)
    for i, (x, y, z) in enumerate(back.norm):
        back.norm[i] = unit(vec(x, z + 0.12 * y, -y))
    base = len(m.pos)
    m.pos += back.pos
    m.norm += back.norm
    m.uv += back.uv
    m.indices.extend(base + i for i in back.indices)
    return m


def coaming(craft):
    """Custom padded glare shield and inset data plate, in the flight deck's rig frame."""
    m = Surface()
    sweep = {"orrery": 0.43, "kiln": 0.31, "vesper": 0.54, "basilisk": 0.31}[craft]
    width = {"orrery": 0.74, "kiln": 0.79, "vesper": 0.73, "basilisk": 0.79}[craft]

    def rim(u, v):
        s = u * 2 - 1
        x = s * width
        z = -0.525 + sweep * abs(s) ** (1.45 if craft in ("kiln", "basilisk") else 2.3)
        angle = v * TAU
        return vec(x, 0.558 + 0.014 * abs(s) + 0.039 * math.sin(angle), z + 0.048 * math.cos(angle))

    m.grid(38, 20, rim, "cloth" if craft == "orrery" else "dark", False)
    for s in (-1, 1):
        edge = [rim(0.5 + s * u * 0.5, 0.052) + vec(0, 0.002, 0.003) for u in np.linspace(0.06, 0.99, 20)]
        tube(m, edge, 0.006, "gold" if craft == "orrery" else "accent", 6)
    hw = {"orrery": 0.132, "kiln": 0.14, "vesper": 0.124, "basilisk": 0.14}[craft]
    p = [(-hw, 0.583, -0.466), (hw, 0.583, -0.466), (hw, 0.526, -0.472), (-hw, 0.526, -0.472)]
    m.poly(p, (0, -0.10, 1), "badge", [(0, 0), (1, 0), (1, 1), (0, 1)])
    for s in (-1, 1):
        for j in range(3):
            x = s * (0.21 + 0.026 * j)
            z = -0.475 + sweep * (abs(x) / width) ** 2
            m.pipe((x, 0.552, z), (x, 0.565, z + 0.002), 0.0045, "gold", 8)
    return m


def grip(craft):
    m = Surface()
    w = {"orrery": 0.034, "kiln": 0.050, "vesper": 0.041, "basilisk": 0.046}[craft]
    tube(m, [(0, -0.055, 0.011), (0, 0.018, 0), (0, 0.054, -0.019)], w, "rubber", 12)
    for y in (-0.03, -0.016, 0):
        m.pipe((0, y, 0.005), (0, y + 0.005, 0.004), w * 1.055, "gold", 14)
    loft(
        m,
        [
            (-0.046, 0, 0.045, w * 0.72, 0.021),
            (-0.035, 0, 0.045, w, 0.022),
            (0.010, 0, 0.048, w, 0.019),
            (0.024, 0, 0.045, w * 0.78, 0.015),
        ],
        "accent",
        0.48,
        18,
    )
    return m


def lens(craft):
    m = Surface()
    z = {"orrery": 2.38, "kiln": 1.86, "vesper": 1.89, "basilisk": 1.95}[craft]
    for s in (-1, 1):
        for i in range(3):
            x = s * (0.14 + i * 0.105)
            m.pipe((x, -0.11, z + 0.023), (x, -0.11, z + 0.037), 0.032, "ceramic", 14)
    return m


# --- The Basilisk's gun (view/turret.gd mirrors these numbers) ---------------------------
# Cab frame: +X starboard, +Y up, +Z aft. The gun rides a sponson on the starboard shoulder; the
# port shoulder carries a matching one, its top welded shut over the gun's capacitor bank.
SPONSON_X = 1.13          # the sponsons' centre line
SPONSON_TOP = 0.19        # the base's top: the gun's bed, and the hatch's sill
HATCH = (-1.48, -0.14, 0.215, 0.13)    # z from, z to, half-width, height of the hatch's shell
HATCH_HINGE = (SPONSON_X + HATCH[2], SPONSON_TOP)   # x, y: its outboard edge (the axis runs fore and aft)
GUN_PIVOT = (SPONSON_X, SPONSON_TOP - 0.035, -0.45)  # the ring's top centre, stowed: sunk in its socket (it rises on its post)
TRUNNION_UP = 0.07        # the cradle's trunnion over the ring's top
MUZZLES = ((-0.065, 0.0, -0.93), (0.065, 0.0, -0.93))   # cradle-local
SIGHT = (SPONSON_X, SPONSON_TOP + 0.065, -1.63)          # the sight ball's centre
SIGHT_R = 0.08


def sponson_rows(s):
    return [
        (-1.76, s * 1.05, 0.12, 0.04, 0.035),
        (-1.62, s * 1.10, 0.11, 0.15, 0.075),
        (-1.40, s * SPONSON_X, 0.10, 0.215, 0.09),
        (-0.30, s * SPONSON_X, 0.10, 0.22, 0.09),
        (-0.10, s * 1.135, 0.09, 0.19, 0.08),
        (0.10, s * 1.14, 0.07, 0.11, 0.06),
        (0.22, s * 1.14, 0.05, 0.04, 0.03),
    ]


def hatch_shell(m, s, inset=0.0, region="enamel", inner="dark", height=None):
    """The upper half of an ellipse run fore and aft over the sponson's bed, its ends drawn in.
    Outer and inner skins (it is seen from below when open), its edges and end caps."""
    z0, z1, w, h = HATCH
    h = h if height is None else height
    thick = 0.018

    def scale(z):
        t = min(z - z0, z1 - z) / 0.13
        return 0.55 + 0.45 * min(1.0, max(0.0, t)) ** 0.6

    def point(u, v, off):
        z = z0 + (z1 - z0) * u
        k = scale(z)
        a = math.pi * v
        return vec(
            s * (SPONSON_X + (w - off) * k * signed(math.cos(a), 0.72)),
            SPONSON_TOP + (h - off) * k * signed(math.sin(a), 0.72) - inset,
            z,
        )

    m.grid(28, 18, lambda u, v: point(u, v, 0.0), region, s > 0)
    m.grid(28, 18, lambda u, v: point(u, v, thick), inner, s < 0)
    for v in (0.0, 1.0):
        for i in range(28):
            u0, u1 = i / 28, (i + 1) / 28
            m.poly(
                [point(u0, v, 0.0), point(u1, v, 0.0), point(u1, v, thick), point(u0, v, thick)],
                (0, -1, 0),
                "dark",
            )
    for u, n in ((0.0, -1), (1.0, 1)):
        m.poly([point(u, j / 18, 0.0) for j in range(19)], (0, 0, n), "dark")
    # The armour's access panel and the hazard band at its leading edge.
    return point


def basilisk_sponsons(m):
    for s in (-1, 1):
        rows = sponson_rows(s)
        loft(m, rows, "enamel", 0.45)
        outboard_patch(m, rows, 2.15, 2.95, s, 42, 0.45, "access", 0.02)
        outboard_patch(m, rows, 1.05, 1.95, s, 42, 0.45, "stripe", 0.012)
        # A cheek carries the sponson down to the sill where it overhangs the nose.
        loft(
            m,
            [
                (-1.70, s * 1.06, -0.03, 0.05, 0.08),
                (-1.45, s * 1.10, -0.05, 0.15, 0.14),
                (-0.85, s * 1.10, -0.05, 0.17, 0.14),
                (-0.60, s * 1.08, -0.04, 0.10, 0.10),
            ],
            "dark",
            0.45,
        )
        badge(m, -0.95, SPONSON_X + 0.222, 0.10, s, 0.62, 0.11)
        # The hinge knuckles along the outboard edge (the starboard hatch turns on them).
        for z in (-1.36, -0.82, -0.28):
            m.pipe(
                (s * HATCH_HINGE[0], HATCH_HINGE[1], z - 0.06),
                (s * HATCH_HINGE[0], HATCH_HINGE[1], z + 0.06),
                0.016,
                "brushed",
                10,
            )
    # Port: the capacitor bank, under a low finned cover (no higher than it must be: it is in the pilot's
    # view to the left, where the starboard hatch is the gun's price on the right).
    hatch_shell(m, -1, height=0.06)
    for i in range(9):
        z = -1.34 + i * 0.13
        m.pipe((-SPONSON_X - 0.12, SPONSON_TOP + 0.06, z), (-SPONSON_X + 0.12, SPONSON_TOP + 0.06, z), 0.008, "vent", 8)
    # Starboard, under the hatch: the gun's bed (two saddles for the barrels, the ring's socket),
    # and the sight's pedestal at the nose.
    x, y = SPONSON_X, SPONSON_TOP
    m.pipe((x, y - 0.02, GUN_PIVOT[2]), (x, y + 0.008, GUN_PIVOT[2]), 0.172, "brushed", 28)
    m.pipe((x, y - 0.02, GUN_PIVOT[2]), (x, y + 0.004, GUN_PIVOT[2]), 0.188, "dark", 28)
    for z in (-1.28, -0.98):
        m.pipe((x - 0.10, y - 0.004, z), (x + 0.10, y - 0.004, z), 0.012, "dark", 8)
        for dx in (-0.065, 0.065):
            m.pipe((x + dx, y + 0.0, z - 0.03), (x + dx, y + 0.0, z + 0.03), 0.014, "rubber", 10)
    m.pipe((x, y - 0.01, SIGHT[2]), (x, SIGHT[1] - SIGHT_R * 0.7, SIGHT[2]), 0.055, "brushed", 16)
    m.pipe((x, y - 0.01, SIGHT[2]), (x, y + 0.012, SIGHT[2]), 0.075, "dark", 16)


def basilisk_roof(frame):
    # Two armour plates over the hoops, split by a dorsal spine that carries the sensor mast.
    for s in (-1, 1):
        loft(
            frame,
            [
                (0.05, s * 0.36, 0.585, 0.06, 0.03),
                (0.22, s * 0.37, 0.615, 0.27, 0.045),
                (1.30, s * 0.37, 0.625, 0.28, 0.05),
                (1.52, s * 0.35, 0.585, 0.20, 0.04),
            ],
            "enamel",
            0.36,
            22,
        )
        tube(
            frame,
            [(s * 0.64, 0.60, 0.36), (s * 0.65, 0.69, 0.46), (s * 0.65, 0.70, 1.27), (s * 0.63, 0.62, 1.41)],
            0.028,
            "brushed",
            8,
        )
    loft(
        frame,
        [(0.14, 0, 0.60, 0.05, 0.03), (0.40, 0, 0.665, 0.085, 0.05), (1.44, 0, 0.66, 0.09, 0.045), (1.62, 0, 0.60, 0.04, 0.02)],
        "dark",
        0.5,
        20,
    )
    m = frame
    m.pipe((0, 0.70, 1.05), (0, 0.84, 1.10), 0.018, "brushed", 10)
    m.pipe((0, 0.84, 1.10), (0, 0.865, 1.11), 0.036, "accent", 14)


def gun_hatch():
    """The starboard hatch, local to its hinge (the axis runs fore and aft along +Z)."""
    m = Surface()
    point = hatch_shell(m, 1)
    z0, z1 = HATCH[0], HATCH[1]
    # Hazard band across its leading end, an access panel on its crown, and two grab rails.
    m.grid(
        6,
        10,
        lambda u, v: point(0.02 + 0.08 * u, 0.12 + 0.76 * v, -0.004),
        "stripe",
        True,
    )
    m.grid(8, 8, lambda u, v: point(0.30 + 0.45 * u, 0.30 + 0.40 * v, -0.004), "access", True)
    for z in (-1.05, -0.55):
        top = point((z - z0) / (z1 - z0), 0.5, -0.03)
        m.pipe(top + vec(0, 0, -0.07), top + vec(0, 0, 0.07), 0.009, "brushed", 8)
    hinge = vec(HATCH_HINGE[0], HATCH_HINGE[1], 0)
    m.pos = [p - hinge for p in m.pos]
    return m


def gun_ring():
    """The traversing ring, local to its top centre; its post runs down into the sponson."""
    m = Surface()
    m.pipe((0, -0.37, 0), (0, -0.045, 0), 0.062, "brushed", 18)
    for y in (-0.27, -0.17):
        m.pipe((0, y, 0), (0, y + 0.018, 0), 0.071, "dark", 18)
    m.pipe((0, -0.05, 0), (0, -0.008, 0), 0.155, "dark", 28)
    m.pipe((0, -0.012, 0), (0, 0.004, 0), 0.143, "brushed", 28)
    for k in range(12):
        a = TAU * k / 12
        m.pipe((0.149 * math.cos(a), -0.034, 0.149 * math.sin(a)), (0.149 * math.cos(a), -0.02, 0.149 * math.sin(a)), 0.008, "gold", 6)
    for sx in (-1, 1):
        x = sx * 0.118
        blade(
            m,
            [(x, 0.0, 0.105), (x, 0.0, -0.105), (x, 0.085, -0.07), (x, TRUNNION_UP + 0.05, 0.0), (x, 0.085, 0.07)],
            0.024,
            "enamel",
            (sx, 0, 0),
        )
        m.pipe((sx * 0.105, TRUNNION_UP, 0), (sx * 0.15, TRUNNION_UP, 0), 0.038, "gold", 16)
    return m


def gun_cradle():
    """The elevating mass, local to its trunnion: receiver, mantlet and the twin emitters (-Z)."""
    m = Surface()
    loft(
        m,
        [
            (-0.10, 0, 0, 0.092, 0.05),
            (-0.07, 0, 0.0, 0.098, 0.058),
            (0.15, 0, -0.004, 0.098, 0.058),
            (0.22, 0, -0.006, 0.072, 0.042),
        ],
        "enamel",
        0.45,
        24,
    )
    loft(m, [(-0.20, 0, 0, 0.10, 0.045), (-0.165, 0, 0, 0.112, 0.062), (-0.115, 0, 0, 0.108, 0.058)], "dark", 0.5, 24)
    skin_patch(
        m,
        [(-0.07, 0, 0.0, 0.098, 0.058), (0.15, 0, -0.004, 0.098, 0.058)],
        0.1,
        0.9,
        (50, 130),
        0.45,
        "stripe",
        0.004,
    )
    for x, _, z_tip in MUZZLES:
        m.pipe((x, 0, -0.12), (x, 0, -0.86), 0.021, "brushed", 16)
        m.pipe((x, 0, -0.84), (x, 0, z_tip), 0.03, "dark", 16)
        m.pipe((x, 0, z_tip + 0.004), (x, 0, z_tip), 0.017, "rubber", 12)
        for z in (-0.175, -0.205):
            m.pipe((x, 0, z), (x, 0, z - 0.012), 0.03, "gold", 14)
    for z in (-0.40, -0.70):
        m.pipe((-0.065, 0, z), (0.065, 0, z), 0.014, "dark", 8)
    m.pipe((0, 0.058, 0.17), (0, 0.05, -0.16), 0.016, "gold", 8)
    m.pipe((0, -0.056, 0.14), (0, -0.05, -0.12), 0.013, "brushed", 8)
    return m


def gun_coils():
    """The emitter coils round each barrel, local to the trunnion (the game lights them as it fires)."""
    m = Surface()
    for x, _, _ in MUZZLES:
        for k in range(5):
            z = -0.25 - k * 0.11
            m.pipe((x, 0, z), (x, 0, z - 0.038), 0.033, "ceramic", 16)
    return m


def sight_ball():
    """The sight: a ball turret local to its centre, its window looking down -Z."""
    m = Surface()
    r = SIGHT_R
    rows = []
    for i in range(13):
        a = -math.pi / 2 + math.pi * i / 12
        rows.append((r * math.sin(a), 0, 0, max(0.004, r * math.cos(a)), max(0.004, r * math.cos(a))))
    loft(m, rows, "dark", 1.0, 24, False)
    m.pipe((0, 0, -r * 0.72), (0, 0, -r * 0.92), r * 0.72, "brushed", 20)
    for sx in (-1, 1):
        m.pipe((sx * r * 0.98, 0, 0), (sx * (r + 0.012), 0, 0), 0.028, "gold", 12)
    return m


def sight_lens():
    m = Surface()
    m.pipe((0, 0, -SIGHT_R * 0.90), (0, 0, -SIGHT_R * 0.95), SIGHT_R * 0.56, "ceramic", 20)
    return m


def make(craft):
    ART.mkdir(parents=True, exist_ok=True)
    make_maps(craft)
    roof, glass = canopy(craft)
    parts = {
        "Port": engine(craft, -1),
        "Starboard": engine(craft, 1),
        "Rotor": rotor(craft),
        "Cab": cab(craft),
        "Seat": seat(craft),
        "Grip": grip(craft),
        "Roof": roof,
        "Glass": glass,
        "Coaming": coaming(craft),
        "AftBrake": brake(craft),
        "FrontBrake": brake(craft, front=True),
        "CabBrake": brake(craft, pod=True),
        "BrakeLenses": lens(craft),
        "Bonnet": bonnet(craft),
    }
    if craft == "basilisk":
        parts.update(
            {
                "GunHatch": gun_hatch(),
                "GunRing": gun_ring(),
                "GunCradle": gun_cradle(),
                "GunCoils": gun_coils(),
                "SightBall": sight_ball(),
                "SightLens": sight_lens(),
            }
        )
    write_glb(parts, ART / (craft + ".glb"), "Phaethon Pilot Fleet")


if __name__ == "__main__":
    for craft_id in sys.argv[1:] or FLEET:
        make(craft_id)
