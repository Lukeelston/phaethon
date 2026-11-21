"""Bake indexed Shrike parts in game coordinates (+Y up, +Z aft).
Run with Python, NumPy and Pillow. The atlas and GLB are game assets. Blender
or runtime mesh generation is unnecessary. All components share one material.
"""

import itertools
import json
import math
import struct

import numpy as np
from art_shrike_finish import ART, REGIONS, SIZE, generate

TAU = math.tau


def vec(x, y, z):
    return np.array((x, y, z), dtype=float)


def unit(v):
    return v / max(np.linalg.norm(v), 1e-12)


def signed(v, p):
    return 0.0 if abs(v) < 1e-9 else math.copysign(abs(v) ** p, v)


class Mesh:
    def __init__(self):
        self.pos, self.norm, self.uv, self.indices = [], [], [], []

    def vertex(self, p, n, uv, region):
        x, y, w, h = REGIONS[region]
        self.pos.append(p)
        self.norm.append(n)
        self.uv.append(((x + 0.5 + uv[0] * (w - 1)) / SIZE, (y + 0.5 + uv[1] * (h - 1)) / SIZE))

    def grid(self, nu, nv, point, region, reverse=False, uv=lambda u, v: (u, v)):
        base = len(self.pos)
        for j in range(nv + 1):
            v = j / nv
            for i in range(nu + 1):
                u = i / nu
                du = point(min(1, u + 0.0003), v) - point(max(0, u - 0.0003), v)
                dv = point(u, min(1, v + 0.0003)) - point(u, max(0, v - 0.0003))
                n = unit(np.cross(du, dv)) * (-1 if reverse else 1)
                self.vertex(point(u, v), n, uv(u, v), region)
        for j in range(nv):
            for i in range(nu):
                a = base + j * (nu + 1) + i
                b, c, d = a + 1, a + nu + 1, a + nu + 2
                self.indices.extend((a, d, b, a, c, d) if reverse else (a, b, d, a, d, c))

    def poly(self, points, normal, region, uv=None):
        p = np.asarray(points)
        n = unit(np.asarray(normal))
        if uv is None:
            axes = np.argsort(np.abs(n))[:2]
            flat = p[:, axes]
            uv = (flat - flat.min(axis=0)) / np.maximum(np.ptp(flat, axis=0), 0.00001)
        if np.dot(np.cross(p[1] - p[0], p[2] - p[0]), n) < 0:
            p, uv = p[::-1], uv[::-1]
        base = len(self.pos)
        for pt, tex in zip(p, uv):
            self.vertex(pt, n, tex, region)
        for i in range(1, len(p) - 1):
            self.indices.extend((base, base + i, base + i + 1))

    def panel(self, points, n, region, thick=0.024, edge="carbon"):
        p = np.asarray(points)
        n = unit(np.asarray(n))
        top = p + n * thick
        self.poly(top, n, region)
        self.poly(p, -n, edge)
        for i in range(len(p)):
            j = (i + 1) % len(p)
            self.poly([p[i], p[j], top[j], top[i]], (p[i] + p[j]) * 0.5 - p.mean(axis=0), edge)

    def pipe(self, a, b, r, region="metal", sides=12, r2=None):
        a, b = np.asarray(a), np.asarray(b)
        axis = unit(b - a)
        right = unit(np.cross(axis, vec(0, 1, 0) if abs(axis[1]) < 0.92 else vec(0, 0, 1)))
        up = np.cross(axis, right)
        end = r if r2 is None else r2

        def p(u, v):
            return (
                a + (b - a) * u + (right * math.cos(TAU * v) + up * math.sin(TAU * v)) * (r + (end - r) * u)
            )

        self.grid(1, sides, p, region, True)
        self.poly([p(1, i / sides) for i in range(sides)], axis, region)
        self.poly([p(0, i / sides) for i in range(sides)], -axis, region)


def rings(mesh, sections, region, center=0, seg=48, span=(0, 1), bias=0, exponent=0.98, uv=None):
    """Loft a sequence of z/width/height stations. The inlet profile doubles
    back on itself around the polished entry radius, exposing its inner wall."""
    table = np.asarray(sections)

    def p(u, v):
        t = u * (len(table) - 1)
        i = min(int(t), len(table) - 2)
        z, w, h = table[i] + (t - i) * (table[i + 1] - table[i])
        a = TAU * (span[0] + v * (span[1] - span[0])) - math.pi / 2
        return vec(center + w * signed(math.cos(a), exponent), bias + h * signed(math.sin(a), exponent), z)

    mesh.grid(len(table) - 1, seg, p, region, True, uv or (lambda u, v: (u, v)))


def collar(mesh, z, w, h, depth, region, center=0, exponent=0.7, bias=0):
    rings(
        mesh,
        [
            (z - depth / 2, w * 0.988, h * 0.986),
            (z - depth * 0.3, w, h),
            (z + depth * 0.3, w, h),
            (z + depth * 0.5, w * 0.989, h * 0.988),
        ],
        region,
        center,
        40,
        exponent=exponent,
        bias=bias,
    )


def aerofoil(mesh, base, side, span, cant, sweep, chord, region="fin"):
    """Closed tapered foil. Roots are thick and rounded, tips nearly knife edged.
    Both faces carry the number upright with leading edge forward."""
    base = np.array(base)
    spread = vec(side * math.sin(cant), math.cos(cant), 0)
    cross = vec(math.cos(cant), -side * math.sin(cant), 0)

    def point(u, v, face):
        thickness = (0.11 * (1 - v) + 0.022 * v) * math.sin(math.pi * math.sqrt(max(u, 0.0))) ** 0.80
        return (
            base
            + spread * (span * v)
            + vec(0, 0, sweep * (v**1.18) + chord * (1 - 0.74 * v) * u)
            + cross * face * (thickness + 0.007)
        )

    for face in (-1, 1):
        mesh.grid(
            14,
            8,
            lambda u, v, face=face: point(u, v, face),
            region,
            reverse=face > 0,
            uv=lambda u, v, face=face: (1 - u if face > 0 else u, 1 - v),
        )
    for u in (0, 1):
        mesh.grid(
            1, 8, lambda t, v, u=u: point(u, v, 2 * t - 1), "metal" if u == 0 else "carbon", reverse=u == 0
        )
    mesh.grid(14, 1, lambda u, t: point(u, 1, 2 * t - 1), "bronze", reverse=True)


def brake(front):
    m = Mesh()
    width, length = (0.93, 1.30) if front else (0.95, 1.19)
    outline = [
        (-0.46, 0.0),
        (0.46, 0.0),
        (0.50, 0.14),
        (0.43, 0.78),
        (0.30, 1),
        (-0.30, 1),
        (-0.43, 0.78),
        (-0.50, 0.14),
    ]
    p = [vec(x * width, 0.024, z * length) for x, z in outline]
    uv = [(x + 0.5, z) for x, z in outline]
    m.poly(p, (0, 1, 0), "brake", uv)
    lower = [v + vec(0, -0.045, 0) for v in p]
    m.poly(lower, (0, -1, 0), "carbon", uv)
    for i in range(len(p)):
        j = (i + 1) % len(p)
        m.poly([p[i], lower[i], lower[j], p[j]], (p[i] + p[j]) * 0.5 - vec(0, 0, length / 2), "metal")
    for x in (-0.32, 0.32):
        m.pipe((x, -0.036, 0.13), (x * 0.60, -0.04, length * 0.82), 0.035, "metal", 8, 0.016)
        m.pipe((x - 0.08, 0.019, 0.045), (x + 0.08, 0.019, 0.045), 0.044, "bronze", 12)
    return m


def impeller():
    m = Mesh()
    for i in range(19):
        angle = TAU * i / 19

        def p(u, v, angle=angle):
            r = 0.085 + 0.264 * v
            a = angle + 0.51 * v + 0.30 * u * (1 - 0.44 * v)
            return vec(
                r * math.cos(a),
                r * math.sin(a),
                0.055 * (u - 0.5) + 0.023 * v - 0.022 * math.sin(math.pi * u),
            )

        m.grid(3, 5, p, "metal", False)
        # Thin rounded leading edge catches light in a front three-quarter view.
        m.grid(1, 5, lambda u, v: p(0, v) + vec(0, 0, 0.008 * u), "ivory", True)
    rings(
        m,
        [
            (-0.218, 0.012, 0.012),
            (-0.205, 0.046, 0.046),
            (-0.14, 0.103, 0.103),
            (-0.06, 0.132, 0.132),
            (0.038, 0.137, 0.137),
        ],
        "metal",
    )
    collar(m, -0.099, 0.123, 0.123, 0.018, "bronze")
    return m


def engine(side):
    m = Mesh()
    for cx in (-0.55, 0.55):
        rings(
            m,
            [(-3.54, 0.34, 0.34), (-3.85, 0.362, 0.362), (-3.99, 0.381, 0.381), (-4.08, 0.401, 0.404)],
            "carbon",
            cx,
        )
        rings(
            m,
            [
                (-4.08, 0.401, 0.404),
                (-4.127, 0.422, 0.424),
                (-4.141, 0.45, 0.447),
                (-4.120, 0.476, 0.469),
                (-4.07, 0.495, 0.48),
            ],
            "metal",
            cx,
        )
        rings(
            m,
            [(-4.07, 0.495, 0.48), (-3.95, 0.520, 0.50), (-3.81, 0.535, 0.516), (-3.59, 0.541, 0.519)],
            "teal",
            cx,
        )
        collar(m, -3.84, 0.539, 0.520, 0.043, "bronze", cx, 0.98)
        rings(
            m,
            [
                (-3.59, 0.541, 0.519),
                (-3.38, 0.544, 0.516),
                (-3.01, 0.552, 0.504),
                (-2.63, 0.557, 0.470),
                (-1.94, 0.532, 0.405),
            ],
            "ivory",
            cx,
        )
        collar(m, -3.56, 0.545, 0.523, 0.052, "carbon", cx, 0.98)
        m.pipe((cx, 0, -3.60), (cx, 0, -3.57), 0.362, "carbon", 32)
        for i in range(13):
            a = TAU * i / 13

            # The stator sits behind the spinner.
            def stat(u, v, a=a, cx=cx):
                theta = a - 0.24 * v + 0.105 * u
                r = 0.13 + 0.228 * v
                return vec(cx + r * math.cos(theta), r * math.sin(theta), -3.65 - 0.025 * u + 0.015 * v)

            m.grid(2, 3, stat, "carbon")
    stations = [
        (-3.20, 0.12, 0.13),
        (-3.05, 0.52, 0.36),
        (-2.74, 0.91, 0.458),
        (-2.36, 1.18, 0.492),
        (-1.94, 1.19, 0.502),
        (-1.4, 1.15, 0.52),
        (-0.72, 1.11, 0.535),
        (0, 1.13, 0.54),
        (0.7, 1.17, 0.501),
        (1.2, 1.16, 0.470),
        (1.72, 1.085, 0.454),
        (2.05, 0.985, 0.431),
        (2.28, 0.94, 0.385),
    ]
    rings(m, stations, "skin", seg=64, exponent=0.72)
    # The sleeve carries combustion heat into overlapping scalloped exhaust petals.
    rings(
        m,
        [(1.80, 0.96, 0.40), (2.18, 1.04, 0.44), (2.86, 1.07, 0.45), (3.41, 1.03, 0.429), (3.94, 1.00, 0.37)],
        "carbon",
        seg=48,
        exponent=0.58,
    )
    for z, w, h in [(2.18, 1.06, 0.458), (2.66, 1.091, 0.471), (3.04, 1.092, 0.469)]:
        collar(m, z, w, h, 0.082, "metal", exponent=0.58)
    for i in range(18):
        span = ((i + 0.045) / 18, (i + 0.955) / 18)
        rings(
            m,
            [(2.20, 1.048, 0.446), (2.37, 1.075, 0.455), (2.90, 1.077, 0.456), (3.34, 1.046, 0.446)],
            "exhaust",
            seg=4,
            span=span,
            exponent=0.57,
            uv=lambda u, v: (v, u),
        )

        def petal(u, v, i=i):
            a = TAU * ((i + 0.035 + 0.93 * v) / 18) - math.pi / 2
            scallop = 0.12 * math.sin(math.pi * v)
            w, h = (1.063 - 0.080 * u, 0.451 - 0.098 * u)
            z = 3.23 + u * (0.88 + scallop)
            return vec(w * signed(math.cos(a), 0.60), h * signed(math.sin(a), 0.60), z)

        m.grid(4, 6, petal, "exhaust", True, uv=lambda u, v: (v, u))
        m.grid(
            1,
            6,
            lambda t, v: petal(1, v) * vec(1 - 0.052 * t, 1 - 0.072 * t, 1) + vec(0, 0, -0.10 * t),
            "metal",
            True,
        )
    for flank in (-1, 1):
        # Carbon cheeks carry the binder and the front speed-brake hinges.
        cheek = [
            vec(flank * 1.17, -0.22, -3.31),
            vec(flank * 1.17, -0.27, -2.51),
            vec(flank * 1.17, -0.10, -2.15),
            vec(flank * 1.17, 0.23, -2.30),
            vec(flank * 1.17, 0.26, -3.07),
        ]
        m.panel(cheek, (flank, 0, 0), "carbon", 0.046)
        m.pipe((flank * 0.99, 0, -2.93), (flank * 1.192, 0, -2.93), 0.26, "carbon", 20)

        # Exposed fluid return line with two bolted saddles, below the brakes.
        def port(x, y, z, flank=flank):
            return vec(flank * x, y, z)

        points = [
            port(0.99, -0.27, -1.51),
            port(1.11, -0.25, -1.32),
            port(1.15, -0.24, 0.49),
            port(1.07, -0.25, 0.83),
        ]
        for a, b in itertools.pairwise(points):
            m.pipe(a, b, 0.030, "bronze", 10)
        for z in (-1.16, 0.29):
            m.pipe(port(1.128, -0.246, z - 0.042), port(1.131, -0.246, z + 0.042), 0.045, "metal", 10)
        for i in range(5):
            z = 0.10 + 0.134 * i
            r = [
                port(1.102, -0.11, z),
                port(1.13, 0.19, z + 0.06),
                port(1.14, 0.20, z + 0.098),
                port(1.117, -0.11, z + 0.056),
            ]
            m.panel(r, (flank, 0, 0), "carbon", 0.032)
    aerofoil(m, (side * 0.77, 0.25, -0.54), side, 1.62, 0.76, 2.46, 2.05)
    # Forked tow yoke encloses the same eye to which the simulated cable attaches.
    for x in (-0.16, 0.16):
        m.pipe((x, -0.24, 2.63), (x * 0.32, -0.91, 3.41), 0.093, "carbon", 10, 0.061)
    m.pipe((-0.108, -0.95, 3.45), (0.108, -0.95, 3.45), 0.112, "metal", 20)
    return m


def body_point(table, u, perimeter):
    step = u * (len(table) - 1)
    i = min(int(step), len(table) - 2)
    z, x, y, w, h = table[i] + (step - i) * (table[i + 1] - table[i])
    a = TAU * perimeter - math.pi / 2
    return vec(x + w * signed(math.cos(a), 0.78), y + h * signed(math.sin(a), 0.78), z)


def faired_section(mesh, stations, region, span=(0, 1), segments=24, uv=lambda u, v: (u, v)):
    """Loft a cambered body from z, x, y, half-width and half-height stations."""
    table = np.asarray(stations)
    mesh.grid(
        len(stations) - 1,
        segments,
        lambda u, v: body_point(table, u, span[0] + v * (span[1] - span[0])),
        region,
        True,
        uv,
    )


def tail_strip(mesh, side, lo, hi, lens):
    """A curved lamp inset in the dark transom. The mounting pocket is wider than its lens."""

    def point(u, v):
        t = lo + (hi - lo) * u
        z = 2.29 - 0.17 * t - 0.33 * t * t
        y = -0.041 + 0.092 * t + 0.016 * math.sin(math.pi * t)
        a = TAU * v
        radius = (0.020 if lens else 0.031) * (1 - 0.5 * t * t)
        return vec(
            side * (0.08 + 0.81 * t),
            y + radius * math.cos(a),
            z + (0.014 if lens else -0.005) + radius * math.sin(a),
        )

    mesh.grid(6, 8, point, "metal" if lens else "carbon", reverse=side > 0)


def tail_lamps():
    lens = Mesh()
    for side in (-1, 1):
        for i in range(8):
            tail_strip(lens, side, (i + 0.06) / 8, (i + 0.94) / 8, True)
    return lens


def pod():
    m = Mesh()
    # A low spine blends into the deck behind the canopy. Narrow fins leave the middle open.
    spine = [
        (0.98, 0, 0.10, 0.04, 0.04),
        (1.20, 0, 0.16, 0.25, 0.18),
        (1.39, 0, 0.19, 0.34, 0.23),
        (1.62, 0, 0.16, 0.33, 0.21),
        (1.88, 0, 0.11, 0.26, 0.17),
        (2.10, 0, 0.042, 0.18, 0.105),
        (2.24, 0, -0.025, 0.045, 0.055),
    ]
    faired_section(m, spine, "teal", (0, 0.34), 10)
    faired_section(m, spine, "spine", (0.34, 0.66), 16, lambda u, v: (1 - v, u))
    faired_section(m, spine, "teal", (0.66, 1), 10)
    deck = np.asarray(spine)
    # Raised extractor blades sit on the curved hatch, with a dark gap beneath their rear edges.
    for side in (-1, 1):
        for station in (0.37, 0.445, 0.52, 0.595):

            def hood(u, v, side=side, station=station):
                arc = 0.5 + side * (0.039 + 0.103 * v)
                t = station + 0.037 * u + 0.022 * v
                return body_point(deck, t, arc) + vec(-side * 0.002, 0.004 + 0.017 * u, 0)

            m.grid(1, 5, hood, "teal", reverse=side > 0)
            m.grid(
                1, 5, lambda u, v, hood=hood: hood(1, v) - vec(0, 0.018 * u, 0), "carbon", reverse=side > 0
            )
    for s in (-1, 1):
        aerofoil(m, (s * 0.91, -0.17, -0.48), s, 0.77, 1.22, 1.13, 1.34)
        # Raised hips carry the brake hinges. The glass and nose cage keep their sightlines.
        hip = [
            (-1.08, s * 0.89, -0.21, 0.035, 0.045),
            (-0.82, s * 0.98, -0.215, 0.115, 0.118),
            (-0.45, s * 1.045, -0.216, 0.155, 0.163),
            (0.04, s * 1.055, -0.215, 0.164, 0.177),
            (0.55, s * 1.04, -0.19, 0.18, 0.175),
            (0.81, s * 1.03, -0.18, 0.191, 0.165),
            (1.16, s * 0.997, -0.155, 0.185, 0.151),
            (1.48, s * 0.92, -0.133, 0.167, 0.14),
            (1.76, s * 0.79, -0.13, 0.139, 0.125),
            (1.99, s * 0.61, -0.143, 0.09, 0.091),
        ]
        for a, b, ink in [
            (0, 0.09, "carbon"),
            (0.09, 0.41, "coachwork"),
            (0.41, 0.59, "teal"),
            (0.59, 0.91, "coachwork"),
            (0.91, 1, "carbon"),
        ]:
            faired_section(
                m,
                hip,
                ink,
                (a, b),
                8,
                uv=(lambda u, v: (1 - u, 1 - v)) if a == 0.09 else (lambda u, v: (u, v)),
            )
        # Painted rails along the open nose carry the same taper as the sidepods.
        rail = [
            (-2.11, s * 0.22, -0.104, 0.035, 0.025),
            (-1.91, s * 0.47, -0.102, 0.047, 0.032),
            (-1.62, s * 0.69, -0.117, 0.061, 0.041),
            (-1.32, s * 0.83, -0.151, 0.068, 0.05),
            (-1.04, s * 0.925, -0.18, 0.084, 0.062),
            (-0.79, s * 1.005, -0.194, 0.074, 0.061),
        ]
        faired_section(m, rail, "ivory", segments=14)
        aerofoil(m, (s * 0.27, 0.10, 1.27), s, 0.61, 0.53, 0.48, 0.65, "teal")
        # A machined heat shield, flared lip, dark throat and recessed centerbody per trim jet.
        nozzle = [
            (1.51, 0.20, 0.145),
            (1.79, 0.228, 0.166),
            (2.04, 0.215, 0.155),
            (2.23, 0.190, 0.144),
            (2.28, 0.187, 0.142),
            (2.30, 0.171, 0.128),
            (2.27, 0.151, 0.109),
            (2.16, 0.14, 0.098),
        ]
        rings(m, nozzle, "exhaust", s * 0.56, 36, bias=-0.221, exponent=0.82)
        collar(m, 2.224, 0.194, 0.149, 0.033, "metal", s * 0.56, bias=-0.221)
        m.pipe((s * 0.56, -0.221, 2.08), (s * 0.56, -0.221, 2.15), 0.136, "carbon", 24)
        rings(
            m,
            [(2.145, 0.081, 0.063), (2.18, 0.072, 0.056), (2.236, 0.014, 0.012)],
            "bronze",
            s * 0.56,
            24,
            bias=-0.221,
        )
        tail_strip(m, s, 0, 1, False)
        # Vertical diffuser fences under the tail tuck up into the rear floor.
        for x in (0.25, 0.69):
            m.panel(
                [
                    vec(s * x, -0.33, 1.31),
                    vec(s * x, -0.47, 1.40),
                    vec(s * x, -0.39, 2.09),
                    vec(s * x, -0.28, 2.16),
                ],
                (s, 0, 0),
                "carbon",
                0.024,
            )
    return m


def pod_brake(side):
    """Handed leaf centered on its hinge, with lettering readable from either flank."""
    m = Mesh()
    outline = [
        (0, -0.11),
        (0.06, -0.153),
        (0.62, -0.135),
        (0.83, -0.076),
        (0.89, 0.022),
        (0.78, 0.102),
        (0.18, 0.156),
        (0.025, 0.114),
    ]
    pts = [vec(-side * 0.16 * z * z, y + 0.037 * z, z) for z, y in outline]
    uv = [(1 - z / 0.89 if side > 0 else z / 0.89, 0.5 - y / 0.32) for z, y in outline]
    inside = [p + vec(-side * 0.027, 0, 0) for p in pts]
    m.poly(pts, (side, 0, 0.12), "coachwork", uv)
    m.poly(inside, (-side, 0, -0.12), "carbon", uv)
    for i in range(len(pts)):
        j = (i + 1) % len(pts)
        m.poly([pts[i], inside[i], inside[j], pts[j]], (pts[i] + pts[j]) / 2 - vec(0, 0, 0.42), "metal")
    for y in (-0.077, 0.061):
        m.pipe((-side * 0.044, y, 0.055), (-side * 0.125, y * 0.4, 0.61), 0.013, "bronze", 8, 0.008)
    m.pipe((-side * 0.01, -0.133, 0.026), (-side * 0.01, 0.13, 0.026), 0.022, "metal", 14)
    return m


# Ring stations run vertically up the lever, with an offset toward the palm.
def sleeve(mesh, stations, region, segments=28):
    def point(u, v):
        t = u * (len(stations) - 1)
        k = min(int(t), len(stations) - 2)
        y, w, d, z = np.asarray(stations[k]) * (1 - t + k) + np.asarray(stations[k + 1]) * (t - k)
        a = v * TAU
        return vec(w * signed(math.cos(a), 0.74), y, z + d * signed(math.sin(a), 0.8))

    mesh.grid(len(stations) - 1, segments, point, region)


def race_grip():
    """Palm swell, graphite finger ribs and an alloy crown. Coordinates match the lever stem."""
    m = Mesh()

    sleeve(
        m,
        [(-0.070, 0.017, 0.021, 0.003), (-0.064, 0.023, 0.026, 0.002), (-0.060, 0.024, 0.027, 0.001)],
        "metal",
    )
    sleeve(
        m,
        [
            (-0.061, 0.024, 0.026, 0.001),
            (-0.053, 0.027, 0.030, 0.003),
            (-0.034, 0.030, 0.033, 0.005),
            (-0.006, 0.033, 0.037, 0.008),
            (0.018, 0.034, 0.036, 0.006),
            (0.036, 0.032, 0.032, 0.002),
        ],
        "grip",
    )
    for y, w, d, shift in [
        (-0.047, 0.029, 0.032, 0.004),
        (-0.030, 0.0317, 0.0355, 0.006),
        (-0.011, 0.034, 0.038, 0.007),
    ]:
        sleeve(
            m,
            [(y - 0.0018, w, d, shift), (y, w + 0.0006, d + 0.0006, shift), (y + 0.0017, w, d, shift)],
            "carbon",
        )
    sleeve(
        m,
        [
            (0.035, 0.032, 0.033, 0.002),
            (0.041, 0.034, 0.035, 0.002),
            (0.047, 0.033, 0.035, 0.001),
            (0.052, 0.027, 0.028, -0.002),
            (0.054, 0.009, 0.012, -0.003),
        ],
        "teal",
    )
    sleeve(m, [(0.040, 0.0345, 0.0357, 0.002), (0.042, 0.0347, 0.0359, 0.002)], "bronze")
    # Transverse pivot pin shows through both cheeks of the trigger housing.
    m.pipe((-0.031, 0.030, -0.016), (0.031, 0.030, -0.016), 0.006, "metal", 16)
    return m


def throttle_link():
    m = Mesh()
    # Covers the lower swivel. A polished strut emerges through a wiper seal, with a
    # ferrule below the grip. All pieces rotate together on the existing pivot.
    sleeve(
        m,
        [
            (0.055, 0.015, 0.015, 0),
            (0.11, 0.014, 0.014, 0),
            (0.275, 0.012, 0.012, 0),
            (0.304, 0.013, 0.013, 0),
        ],
        "metal",
        20,
    )
    rows = [(0.017, 0.033, 0.034, 0)]
    for i in range(6):
        y = 0.022 + i * 0.013
        r = 0.034 - 0.0027 * i
        rows.extend(
            [
                (y, r * 0.87, r * 0.87, 0),
                (y + 0.004, r, r, 0),
                (y + 0.007, r, r, 0),
                (y + 0.012, r * 0.83, r * 0.83, 0),
            ]
        )
    sleeve(m, rows, "grip", 20)
    sleeve(m, [(0.10, 0.016, 0.016, 0), (0.105, 0.017, 0.017, 0), (0.112, 0.016, 0.016, 0)], "metal", 20)
    sleeve(
        m,
        [
            (0.276, 0.014, 0.014, 0),
            (0.280, 0.018, 0.018, 0),
            (0.289, 0.019, 0.019, 0),
            (0.295, 0.016, 0.016, 0),
        ],
        "bronze",
        20,
    )
    return m


def brake_paddle():
    m = Mesh()
    # Bow the blade away from the grip. Its lower tip sweeps in as the pilot squeezes.
    outline = [
        (-0.004, 0),
        (0.000, -0.009),
        (-0.019, -0.039),
        (-0.023, -0.068),
        (-0.016, -0.082),
        (-0.021, -0.086),
        (-0.031, -0.073),
        (-0.030, -0.039),
        (-0.013, -0.007),
    ]
    pts = [vec(-0.011, y, z) for z, y in outline]
    m.panel(pts, (1, 0, 0), "metal", 0.022, "carbon")
    for i in range(3):
        y = -0.044 - i * 0.008
        m.pipe((-0.0115, y, -0.029), (0.0115, y, -0.029), 0.0016, "bronze", 8)
    return m


def seat_pan():
    # Both seat meshes are authored in cockpit rig coordinates so the VR harness
    # and lever clearances are identical to the chase-view installation.
    m = Mesh()
    faired_section(
        m,
        [
            (0.635, 0, 0.142, 0.17, 0.044),
            (0.67, 0, 0.147, 0.267, 0.055),
            (0.80, 0, 0.143, 0.286, 0.061),
            (1.00, 0, 0.144, 0.282, 0.052),
            (1.095, 0, 0.155, 0.225, 0.025),
        ],
        "carbon",
    )
    for z, end in [(0.654, 0.778), (0.783, 0.908), (0.913, 1.045)]:
        faired_section(
            m,
            [
                (z, 0, 0.176, 0.222, 0.012),
                (z + 0.018, 0, 0.181, 0.243, 0.026),
                (end - 0.018, 0, 0.182, 0.242, 0.026),
                (end, 0, 0.178, 0.221, 0.012),
            ],
            "grip",
        )
    for side in (-1, 1):
        faired_section(
            m,
            [
                (0.64, side * 0.204, 0.183, 0.018, 0.020),
                (0.71, side * 0.245, 0.19, 0.049, 0.049),
                (0.88, side * 0.255, 0.202, 0.048, 0.070),
                (1.01, side * 0.254, 0.205, 0.045, 0.063),
                (1.08, side * 0.228, 0.192, 0.026, 0.030),
            ],
            "teal",
            segments=18,
        )
    return m


def seat_back():
    m = Mesh()

    # Rotate the longitudinal loft upright with its upholstered face toward the windscreen.
    def upright(rows, region):
        start = len(m.pos)
        faired_section(m, rows, region, segments=24)
        for i in range(start, len(m.pos)):
            x, y, z = m.pos[i]
            m.pos[i] = vec(x, z, 1.095 - y - 0.08 * (z - 0.49))
            x, y, z = m.norm[i]
            m.norm[i] = unit(vec(x, z - 0.08 * y, -y))

    upright(
        [
            (0.20, 0, 0, 0.23, 0.032),
            (0.27, 0, 0, 0.27, 0.053),
            (0.48, 0, 0, 0.283, 0.057),
            (0.72, 0, 0, 0.282, 0.052),
            (0.81, 0, 0, 0.235, 0.042),
            (0.89, 0, 0, 0.143, 0.035),
            (0.923, 0, 0, 0.115, 0.025),
        ],
        "carbon",
    )
    for bot, top, width in [
        (0.28, 0.47, 0.188),
        (0.475, 0.685, 0.204),
        (0.69, 0.776, 0.188),
        (0.80, 0.92, 0.124),
    ]:
        upright(
            [
                (bot, 0, 0.049, width * 0.83, 0.013),
                (bot + 0.018, 0, 0.053, width, 0.023),
                (top - 0.018, 0, 0.054, width, 0.023),
                (top, 0, 0.047, width * 0.83, 0.011),
            ],
            "grip",
        )
    for side in (-1, 1):
        upright(
            [
                (0.255, side * 0.213, 0.027, 0.022, 0.021),
                (0.36, side * 0.237, 0.042, 0.047, 0.055),
                (0.61, side * 0.247, 0.050, 0.048, 0.065),
                (0.735, side * 0.244, 0.049, 0.049, 0.056),
                (0.803, side * 0.201, 0.03, 0.028, 0.025),
            ],
            "teal",
        )
    return m


def write_glb(parts):
    blob = bytearray()
    views, accessors, meshes, nodes = [], [], [], []

    def accessor(data, typ, component, fmt, buffer_target):
        arr = np.asarray(data, dtype=fmt)
        blob.extend(b"\0" * ((-len(blob)) % 4))
        start = len(blob)
        blob.extend(arr.tobytes())
        views.append({"buffer": 0, "byteOffset": start, "byteLength": arr.nbytes, "target": buffer_target})
        acc = {"bufferView": len(views) - 1, "componentType": component, "count": len(arr), "type": typ}
        if typ == "VEC3":
            acc.update(min=arr.min(axis=0).tolist(), max=arr.max(axis=0).tolist())
        accessors.append(acc)
        return len(accessors) - 1

    for name, m in parts.items():
        assert len(m.pos) < 65535 and np.isfinite(m.pos).all() and np.isfinite(m.norm).all()
        normals = np.asarray(m.norm)
        assert np.min(np.linalg.norm(normals, axis=1)) > 0.95, name
        attr = {
            key: accessor(values, shape, 5126, "<f4", 34962)
            for key, values, shape in (
                ("POSITION", m.pos, "VEC3"),
                ("NORMAL", m.norm, "VEC3"),
                ("TEXCOORD_0", m.uv, "VEC2"),
            )
        }
        idx = accessor(m.indices, "SCALAR", 5123, "<u2", 34963)
        meshes.append({"name": name, "primitives": [{"attributes": attr, "indices": idx}]})
        nodes.append({"name": name, "mesh": len(meshes) - 1})
        print(name, len(m.indices) // 3, "triangles")
    blob.extend(b"\0" * ((-len(blob)) % 4))
    doc = {
        "asset": {"version": "2.0", "generator": "Phaethon Shrike tooling"},
        "scene": 0,
        "scenes": [{"nodes": list(range(len(nodes)))}],
        "nodes": nodes,
        "meshes": meshes,
        "buffers": [{"byteLength": len(blob)}],
        "bufferViews": views,
        "accessors": accessors,
    }
    js = json.dumps(doc, separators=(",", ":")).encode()
    js += b" " * ((-len(js)) % 4)
    (ART / "bodywork.glb").write_bytes(
        struct.pack("<4sII", b"glTF", 2, 28 + len(js) + len(blob))
        + struct.pack("<I4s", len(js), b"JSON")
        + js
        + struct.pack("<I4s", len(blob), b"BIN\0")
        + blob
    )


if __name__ == "__main__":
    generate()
    write_glb(
        {
            "Port": engine(-1),
            "Starboard": engine(1),
            "Compressor": impeller(),
            "ForwardBrake": brake(True),
            "AftBrake": brake(False),
            "PodStrakes": pod(),
            "PortPodBrake": pod_brake(-1),
            "StarboardPodBrake": pod_brake(1),
            "TailLights": tail_lamps(),
            "PilotGrip": race_grip(),
            "ThrottleLink": throttle_link(),
            "BrakePaddle": brake_paddle(),
            "SeatBack": seat_back(),
            "SeatPan": seat_pan(),
        }
    )
