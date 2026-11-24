"""Cut deployable access doors out of the shipped cab skin, preserving its UVs and baked AO.

Run after tools/art_pilot_fleet.py when either cab changes. The original closed mesh
remains the only one loaded until first arming; the open swap carries the same finish.
"""
import json
from pathlib import Path
import struct
from types import SimpleNamespace

import numpy as np

from art_pilot_fleet_finish import REGIONS
from art_shrike_airframe import write_glb

ART = Path(__file__).resolve().parents[1] / "godot/art/pilot_fleet"
# Each crop is an actual section of skin. The lowered face is inside the shoulder;
# the two Kiln jaws share their centre plane. Positions in cab metres (+Z aft).
DOORS = {
    "orrery": {
        "PortDoor": ((-0.83, -0.105, -1.59), (-0.49, 0.30, -1.23)),
        "StarboardDoor": ((0.49, -0.105, -1.59), (0.83, 0.30, -1.23)),
        "BowDoor": ((0.35, -0.115, -2.00), (0.69, 0.26, -1.64)),
    },
    "kiln": {
        "PortJaw": ((0.53, 0.0, -2.075), (0.70, 0.25, -1.18)),
        "StarboardJaw": ((0.70, 0.0, -2.075), (0.87, 0.25, -1.18)),
    },
}


def cab_faces(path, part_name="Cab"):
    raw = path.read_bytes()
    length = struct.unpack_from("<I", raw, 12)[0]
    doc = json.loads(raw[20:20 + length])
    blob = memoryview(raw)[28 + length:]

    def array(index):
        acc = doc["accessors"][index]
        view = doc["bufferViews"][acc["bufferView"]]
        dtype = {5126: "<f4", 5123: "<u2", 5121: "u1"}[acc["componentType"]]
        columns = {"VEC3": 3, "VEC2": 2, "VEC4": 4, "SCALAR": 1}[acc["type"]]
        return np.frombuffer(blob, dtype, count=acc["count"] * columns,
                             offset=view.get("byteOffset", 0) + acc.get("byteOffset", 0)).reshape(-1, columns)

    mesh = next(m for m in doc["meshes"] if m["name"] == part_name)["primitives"][0]
    a = mesh["attributes"]
    vertices = np.column_stack((array(a["POSITION"]), array(a["NORMAL"]),
                                array(a["TEXCOORD_0"]), array(a["COLOR_0"])[:, 3] / 255.0))
    return vertices[array(mesh["indices"]).reshape(-1, 3)]


def partition(poly, axis, value, sign):
    """Split a convex polygon. Every interpolant follows the same edge parameter."""
    inner, outer = [], []
    prev = poly[-1]
    before = sign * (prev[axis] - value)
    for vertex in poly:
        now = sign * (vertex[axis] - value)
        if (before < 0) != (now < 0):
            hit = prev + (vertex - prev) * (before / (before - now))
            inner.append(hit)
            outer.append(hit)
        (inner if now >= 0 else outer).append(vertex)
        prev, before = vertex, now
    return inner, outer


def crop(poly, low, high):
    if (np.max(poly, axis=0)[:3] <= low).any() or (np.min(poly, axis=0)[:3] >= high).any():
        return [], [poly]
    scraps = []
    for axis in range(3):
        for value, sign in [(low[axis], 1), (high[axis], -1)]:
            poly, outside = partition(poly, axis, value, sign)
            if len(outside) >= 3:
                scraps.append(outside)
            if len(poly) < 3:
                return [], scraps
    return poly, scraps


def mesh(polygons):
    indices, data, lookup = [], [], {}
    for poly in polygons:
        for i in range(1, len(poly) - 1):
            tri = np.asarray([poly[0], poly[i], poly[i + 1]])
            p = tri[:, :3].astype("f4")
            if np.linalg.norm(np.cross(p[1] - p[0], p[2] - p[0])) < 1e-11:
                continue
            for vert in tri:
                key = tuple(vert.astype("f4"))
                if key not in lookup:
                    lookup[key] = len(data)
                    data.append(vert)
                indices.append(lookup[key])
    verts = np.asarray(data)
    norms = verts[:, 3:6]
    return SimpleNamespace(pos=verts[:, :3], norm=norms / np.linalg.norm(norms, axis=1)[:, None],
                           uv=verts[:, 6:8], indices=indices, baked_ao=verts[:, 8])


def line_orrery_door(polygons, low, high):
    """Give the hinged skin its exposed reverse and a return along the cut edge."""
    low, high = np.array(low), np.array(high)
    center = (low + high) / 2
    tile_x, tile_y, tile_w, tile_h = REGIONS["brushed"]
    lined = list(polygons)
    for polygon in polygons:
        front = np.asarray(polygon)
        back = front.copy()
        back[:, :3] = center + (back[:, :3] - center) * (0.98, 1.0, 0.98)
        back[:, 1] -= 0.008
        back[:, 3:6] *= -1
        uv = (front[:, [0, 2]] - low[[0, 2]]) / (high - low)[[0, 2]]
        back[:, 6:8] = ((tile_x + 4, tile_y + 4) + uv * (tile_w - 8, tile_h - 8)) / 1024
        lined.append(back[::-1])
        for i in range(len(front)):
            j = (i + 1) % len(front)
            a, b = front[i, :3], front[j, :3]
            if not any((np.isclose(a, plane) & np.isclose(b, plane)).any() for plane in (low, high)):
                continue
            rim = np.array([front[j], front[i], back[i], back[j]])
            normal = np.cross(a - b, back[i, :3] - a)
            length = np.linalg.norm(normal)
            if length > 1e-11:
                rim[:, 3:6] = normal / length
                rim[:2, 6:8] = back[[j, i], 6:8]
                lined.append(rim)
    return lined


def bake(craft):
    remaining = list(cab_faces(ART / (craft + ".glb")))
    parts = {}
    for name, (low, high) in DOORS[craft].items():
        cut, rest = [], []
        for polygon in remaining:
            cropped, scraps = crop(polygon, low, high)
            if len(cropped) >= 3:
                cut.append(cropped)
            rest.extend(scraps)
        parts[name] = mesh(line_orrery_door(cut, low, high) if craft == "orrery" else cut)
        remaining = rest
    parts["OpenCab"] = mesh(remaining)
    write_glb(parts, ART / (craft + "_bay.glb"), "Phaethon flush fleet bays")


if __name__ == "__main__":
    for vehicle in DOORS:
        bake(vehicle)
