"""Compact indexed glTF meshes. Vehicle coordinates are +Y up and -Z forward."""

import json
import math
import struct
import numpy as np
from finishes import INDEX, COLS, ROWS, CELL, PAD


def unit(v):
    a = np.array(v, dtype=float)
    return a / max(1e-12, np.linalg.norm(a))


class Model:
    def __init__(self, detailed):
        self.detailed = detailed
        self.vertices = []
        self.lookup = {}
        self.indices = []

    def face(self, pts, finish, uv=None, normals=None):
        pts = np.array(pts, float)
        n = unit(np.cross(pts[1] - pts[0], pts[2] - pts[0]))
        if np.linalg.norm(n) < 0.5:
            return
        if uv is None:
            uv = [(0, 1), (1, 1), (1, 0), (0, 0)][: len(pts)]
        idx = INDEX[finish]
        ids = []
        for j, (p, (u, v)) in enumerate(zip(pts, uv)):
            nu = n if normals is None else normals[j]
            tex = (
                (idx % COLS + (PAD + 0.5 + u * (CELL - 2 * PAD - 1)) / CELL) / COLS,
                (idx // COLS + (PAD + 0.5 + v * (CELL - 2 * PAD - 1)) / CELL) / ROWS,
            )
            vert = tuple(np.round((*p, *nu, *tex), 6))
            if vert not in self.lookup:
                self.lookup[vert] = len(self.vertices)
                self.vertices.append(vert)
            ids.append(self.lookup[vert])
        for j in range(1, len(ids) - 1):
            self.indices.extend((ids[0], ids[j], ids[j + 1]))

    def box(self, pos, size, mat):
        x, y, z = pos
        w, h, l = np.array(size) * 0.5
        ring = [(-w, -h), (w, -h), (w, h), (-w, h)]
        pts = [[(x + a, y + b, z + c) for a, b in ring] for c in (-l, l)]
        self.skin(pts, mat)

    def skin(self, rings, mat, smooth=False):
        rows = np.array(rings)
        n = len(rows[0])
        last = len(rows) - 1
        ns = (
            [
                [
                    unit(
                        np.cross(
                            row[(i + 1) % n] - row[i - 1],
                            rows[min(j + 1, last), i] - rows[max(j - 1, 0), i],
                        )
                    )
                    for i in range(n)
                ]
                for j, row in enumerate(rows)
            ]
            if smooth
            else None
        )
        for j in range(last):
            for i in range(n):
                k = (i + 1) % n
                # On a right side (+X), the nose is on the viewer's right. Keep a single continuous finish along the length.
                uv = [
                    (j / last, 1),
                    (j / last, 0),
                    ((j + 1) / last, 0),
                    ((j + 1) / last, 1),
                ]
                self.face(
                    [rows[j, i], rows[j, k], rows[j + 1, k], rows[j + 1, i]],
                    mat if isinstance(mat, str) else mat[i],
                    uv,
                    [ns[j][i], ns[j][k], ns[j + 1][k], ns[j + 1][i]] if ns else None,
                )
        for row in (rows[0][::-1], rows[-1]):
            normal = unit(np.cross(row[1] - row[0], row[2] - row[0]))
            axes = np.flatnonzero(np.arange(3) != np.argmax(abs(normal)))
            coordinates = row[:, axes]
            coords = (coordinates - coordinates.min(axis=0)) / np.maximum(
                np.ptp(coordinates, axis=0), 1e-8
            )
            for i in range(1, n - 1):
                ix = [0, i, i + 1]
                self.face(
                    row[ix],
                    mat if isinstance(mat, str) else mat[0],
                    [(coords[k, 0], 1 - coords[k, 1]) for k in ix],
                )

    def hull(self, sections, mat, cx=0, smooth=False):
        # z, full width, sill height, crown height, and crown-to-belt width ratio.
        rings = []
        for z, w, lo, hi, roof in sections:
            w *= 0.5
            h = hi - lo
            ring = [
                (-w, lo + h * 0.28),
                (-w * 0.78, lo),
                (w * 0.78, lo),
                (w, lo + h * 0.28),
                (w * 0.97, lo + h * 0.62),
                (w * roof, hi - h * 0.08),
                (w * roof * 0.82, hi),
                (-w * roof * 0.82, hi),
                (-w * roof, hi - h * 0.08),
                (-w * 0.97, lo + h * 0.62),
            ]
            rings.append([(cx + x, y, z) for x, y in ring])
        self.skin(rings, mat, smooth)

    def barrel(self, a, b, profile, mat, n=10, cap="same"):
        a = np.array(a)
        b = np.array(b)
        axis = unit(b - a)
        u = unit(np.cross((0, 1, 0) if abs(axis[1]) < 0.9 else (0, 0, 1), axis))
        v = np.cross(axis, u)
        ns = [
            u * math.cos(math.tau * j / n) + v * math.sin(math.tau * j / n)
            for j in range(n)
        ]
        rings = [[a + (b - a) * t + rad * d for d in ns] for t, rad in profile]
        for j in range(len(rings) - 1):
            f = mat if isinstance(mat, str) else mat[j]
            slope = (profile[j][1] - profile[j + 1][1]) / (
                max(
                    np.linalg.norm(b - a) * (profile[j + 1][0] - profile[j][0]), 0.00001
                )
            )
            normals = [unit(d + axis * slope) for d in ns]
            for k in range(n):
                l = (k + 1) % n
                self.face(
                    [rings[j][k], rings[j][l], rings[j + 1][l], rings[j + 1][k]],
                    f,
                    [
                        (k / n, profile[j][0]),
                        ((k + 1) / n, profile[j][0]),
                        ((k + 1) / n, profile[j + 1][0]),
                        (k / n, profile[j + 1][0]),
                    ],
                    [normals[k], normals[l], normals[l], normals[k]],
                )
        f = mat if isinstance(mat, str) else mat[0]
        for ring, reverse in ((rings[0], True), (rings[-1], False)):
            for k in range(1, n - 1):
                idx = [0, k + 1, k] if reverse else [0, k, k + 1]
                tex = [
                    (
                        0.5 + 0.5 * math.cos(math.tau * i / n),
                        0.5 - 0.5 * math.sin(math.tau * i / n),
                    )
                    for i in idx
                ]
                self.face([ring[i] for i in idx], f if cap == "same" else cap, tex)

    def bar(self, a, b, r, mat, n=6):
        self.barrel(a, b, [(0, r), (1, r)], mat, n)

    def side(self, s, x, z, y, l, h, mat):
        # z grows towards the tail. Outward winding and readable lettering for both sides.
        z0 = z + s * l / 2
        z1 = z - s * l / 2
        self.face(
            [(s * x, y, z0), (s * x, y, z1), (s * x, y + h, z1), (s * x, y + h, z0)],
            mat,
        )

    def end(self, back, z, x, y, w, h, mat):
        sign = 1 if back else -1
        self.face(
            [
                (x - sign * w / 2, y, z),
                (x + sign * w / 2, y, z),
                (x + sign * w / 2, y + h, z),
                (x - sign * w / 2, y + h, z),
            ],
            mat,
        )

    def top(self, x, y, z, w, l, mat):
        self.face(
            [
                (x - w / 2, y, z + l / 2),
                (x + w / 2, y, z + l / 2),
                (x + w / 2, y, z - l / 2),
                (x - w / 2, y, z - l / 2),
            ],
            mat,
        )

    def fin(self, points, thickness, mat):
        # Extrude a convex outline; winding is chosen against the extrusion vector.
        p = np.array(points)
        d = np.array(thickness) * 0.5
        normal = unit(np.cross(p[1] - p[0], p[2] - p[0]))
        if np.dot(normal, d) < 0:
            p = p[::-1]
        for verts in (p + d, (p - d)[::-1]):
            for j in range(1, len(p) - 1):
                self.face(verts[[0, j, j + 1]], mat)
        for i in range(len(p)):
            j = (i + 1) % len(p)
            self.face([p[i] - d, p[j] - d, p[j] + d, p[i] + d], mat)


def write_glb(path, models, rotate):
    data = bytearray()
    views = []
    access = []
    meshes = []

    def array(vals, dtype, size, ctype, target, limits=False):
        vals = np.ascontiguousarray(vals, dtype=dtype)
        data.extend(bytes((-len(data)) % 4))
        offset = len(data)
        data.extend(vals.tobytes())
        views.append(
            dict(buffer=0, byteOffset=offset, byteLength=vals.nbytes, target=target)
        )
        a = dict(
            bufferView=len(views) - 1, componentType=ctype, count=len(vals), type=size
        )
        if limits:
            a.update(min=vals.min(axis=0).tolist(), max=vals.max(axis=0).tolist())
        access.append(a)
        return len(access) - 1

    for name, m in models:
        arr = np.array(m.vertices)
        p = arr[:, :3].copy()
        n = arr[:, 3:6].copy()
        if rotate:
            for dest in (p, n):
                dest[:, [0, 2]] = dest[:, [2, 0]] * [-1, 1]
        assert len(p) < 65536 and np.isfinite(arr).all()
        attrs = {
            "POSITION": array(p, "<f4", "VEC3", 5126, 34962, True),
            "NORMAL": array(n, "<f4", "VEC3", 5126, 34962),
            "TEXCOORD_0": array(arr[:, 6:], "<f4", "VEC2", 5126, 34962),
        }
        meshes.append(
            {
                "name": name,
                "primitives": [
                    {
                        "attributes": attrs,
                        "indices": array(m.indices, "<u2", "SCALAR", 5123, 34963),
                        "material": 0,
                    }
                ],
            }
        )
    nodes = [{"name": name, "mesh": i} for i, (name, m) in enumerate(models)]
    obj = {
        "asset": {"version": "2.0", "generator": "Phaethon fleet workshop"},
        "scene": 0,
        "scenes": [{"nodes": list(range(len(nodes)))}],
        "nodes": nodes,
        "meshes": meshes,
        "accessors": access,
        "bufferViews": views,
        "buffers": [{"byteLength": len(data)}],
        "images": [{"uri": "fleet_color.png"}],
        "textures": [{"source": 0}],
        "materials": [
            {
                "name": "Fleet paint",
                "pbrMetallicRoughness": {
                    "baseColorTexture": {"index": 0},
                    "roughnessFactor": 0.45,
                    "metallicFactor": 0.28,
                },
            }
        ],
    }
    meta = json.dumps(obj, separators=(",", ":")).encode()
    meta += b" " * ((-len(meta)) % 4)
    data += bytes((-len(data)) % 4)
    path.write_bytes(
        struct.pack("<4sII", b"glTF", 2, 28 + len(meta) + len(data))
        + struct.pack("<I4s", len(meta), b"JSON")
        + meta
        + struct.pack("<I4s", len(data), b"BIN\0")
        + data
    )
