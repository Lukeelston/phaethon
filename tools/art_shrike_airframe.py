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


def pod():
    m = Mesh()
    for s in (-1, 1):
        aerofoil(m, (s * 0.91, -0.17, -0.48), s, 0.77, 1.22, 1.13, 1.34)
        # Fairings at the sides taper to the two trim jets.
        rings(
            m,
            [
                (0.24, 0.032, 0.042),
                (0.52, 0.093, 0.102),
                (1.05, 0.156, 0.173),
                (1.5, 0.162, 0.145),
                (1.76, 0.108, 0.104),
            ],
            "teal",
            s * 0.90,
            28,
            bias=-0.20,
        )
        collar(m, 1.44, 0.166, 0.153, 0.067, "ivory", s * 0.90, bias=-0.20)
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
        }
    )
