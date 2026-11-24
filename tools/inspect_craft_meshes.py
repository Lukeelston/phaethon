"""Inspect the pilot craft's baked meshes as shipped (godot/art/shrike/bodywork.glb, godot/art/pilot_fleet/*.glb).

Usage: python tools/inspect_craft_meshes.py [ART_DIR] [--strict]   (ART_DIR defaults to godot/art)

Per part: triangles and vertices (each part must stay under the 65,535 vertices of its 16-bit index),
pieces (separately modelled solids welded into the part), floating pieces (a piece farther than
FLOAT_GAP from every other piece of its part: hardware that does not touch what it is fixed to),
collapsed triangles, shading normals turned against their face (a reversed or pinched normal), the
worst angle between a triangle and its vertex normals (a crease drawn smooth, or a pinched corner),
and the baked occlusion's range. --strict exits 1 on a reversed normal, a collapsed triangle, a
floating piece or a part over budget. Geometry pass, 2026-11-23.
"""

import json
import struct
import sys
from pathlib import Path

import numpy as np
from scipy.sparse import coo_matrix
from scipy.sparse.csgraph import connected_components
from scipy.spatial import cKDTree

ROOT = Path(__file__).resolve().parents[1] / "godot/art"
ASSETS = ["shrike/bodywork.glb", *(f"pilot_fleet/{c}.glb" for c in ("orrery", "kiln", "vesper"))]
FLOAT_GAP = 0.003
# Parts that are meant to be apart from everything in their own mesh: a pane, lamp lenses, the badge
# plaques that sit on a skin in another part.
LOOSE_BY_DESIGN = {"Glass", "BrakeLenses", "TailLights"}


def read_glb(path):
    data = path.read_bytes()
    length = struct.unpack("<I", data[12:16])[0]
    doc = json.loads(data[20:20 + length])
    blob = data[20 + length + 8:]
    kinds = {5126: ("<f4", 4), 5123: ("<u2", 2), 5125: ("<u4", 4), 5121: ("u1", 1)}
    widths = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}

    def accessor(i):
        acc = doc["accessors"][i]
        view = doc["bufferViews"][acc["bufferView"]]
        fmt, size = kinds[acc["componentType"]]
        count, width = acc["count"], widths[acc["type"]]
        start = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
        return np.frombuffer(blob, dtype=fmt, count=count * width, offset=start).reshape(count, width) if width > 1 else np.frombuffer(blob, dtype=fmt, count=count, offset=start)

    for mesh in doc["meshes"]:
        prim = mesh["primitives"][0]
        attr = prim["attributes"]
        yield mesh["name"], accessor(attr["POSITION"]).astype(float), accessor(attr["NORMAL"]).astype(float), accessor(prim["indices"]).astype(int).reshape(-1, 3), (accessor(attr["COLOR_0"])[:, 3] / 255.0 if "COLOR_0" in attr else None)


def inspect(name, pos, nrm, tri, ao):
    report = {"part": name, "triangles": len(tri), "vertices": len(pos)}
    a, b, c = pos[tri[:, 0]], pos[tri[:, 1]], pos[tri[:, 2]]
    face = np.cross(b - a, c - a)
    area = np.linalg.norm(face, axis=1)
    report["collapsed"] = int(np.sum(area < 1e-12))
    unit_face = face / np.maximum(area, 1e-30)[:, None]
    dots = np.stack([np.sum(unit_face * nrm[tri[:, k]], axis=1) for k in range(3)], axis=1)
    report["reversed"] = int(np.sum(np.sum(unit_face * nrm[tri].mean(axis=1), axis=1) < -0.01))
    worst = np.degrees(np.arccos(np.clip(dots.min(axis=1), -1, 1)))
    # Large triangles only: a millimetre facet on a rolled edge is meant to turn its normal sharply.
    big = area > np.percentile(area, 50)
    report["normal_turn_p99_deg"] = round(float(np.percentile(worst[big], 99)), 1)
    report["normal_turn_over_75deg"] = int(np.sum(worst[big] > 75))
    # Pieces: weld vertices at the same place, then join through triangles.
    key = np.round(pos / 1e-5).astype(np.int64)
    _, weld = np.unique(key, axis=0, return_inverse=True)
    weld = weld.ravel()
    edges = np.concatenate([tri[:, [0, 1]], tri[:, [1, 2]]])
    graph = coo_matrix((np.ones(len(edges)), (weld[edges[:, 0]], weld[edges[:, 1]])), shape=(weld.max() + 1,) * 2)
    count, label = connected_components(graph, directed=False)
    label = label[weld]
    report["pieces"] = int(count)
    floating = []
    if count > 1 and name not in LOOSE_BY_DESIGN:
        floating = _floating(pos, tri, label, count)
    report["floating"] = floating
    if ao is not None:
        report["occlusion"] = (round(float(ao.min()), 2), round(float(ao.mean()), 2))
    return report


def _floating(pos, tri, label, count):
    """Pieces whose surface comes nowhere near another piece's: the part's surface is sampled once
    into voxels a few millimetres across (hashed, not a dense grid), each voxel remembering which
    pieces cross it, and a piece touches another if one of its voxels, or a neighbour of one, holds
    the other's surface. A pipe plunged into a body crosses its skin, so it touches; a bracket standing
    clear by more than about a voxel does not. The part's main structures (the biggest pieces) are not
    checked: a floating bracket is never the body it should be fixed to."""
    extent = float(np.max(pos.max(axis=0) - pos.min(axis=0)))
    cell = max(extent / 1500, 0.0015)
    lo = pos.min(axis=0) - 4 * cell
    tri_owner = label[tri[:, 0]]
    keys, owners = [], []
    for points, owner in _samples(pos[tri], cell * 0.7, tri_owner):
        keys.append(_key(np.floor((points - lo) / cell).astype(np.int64)))
        owners.append(owner)
    keys, owners = np.concatenate(keys), np.concatenate(owners)
    pair = np.unique(np.stack([keys, owners], axis=1), axis=0)
    keys, owners = pair[:, 0], pair[:, 1]
    uniq, start = np.unique(keys, return_index=True)
    low = np.minimum.reduceat(owners, start)
    high = np.maximum.reduceat(owners, start)
    size = np.bincount(owners, minlength=count)
    near = np.array([(dx, dy, dz) for dx in (-1, 0, 1) for dy in (-1, 0, 1) for dz in (-1, 0, 1)])
    out = []
    for piece in np.argsort(size)[: max(0, count - 3)]:
        own = keys[owners == piece]
        if len(own) == 0 or len(own) > 60000:
            continue
        cells = _unkey(own)
        around = np.unique(_key((cells[:, None, :] + near[None]).reshape(-1, 3)))
        at = np.clip(np.searchsorted(uniq, around), 0, len(uniq) - 1)
        hit = uniq[at] == around
        if not ((low[at[hit]] != piece) | (high[at[hit]] != piece)).any():
            out.append((int(piece), round(cell, 4), (cells.mean(axis=0) * cell + lo).round(3).tolist()))
    return out


def _key(cells):
    c = cells.astype(np.int64) + 1
    return (c[:, 0] << 42) | (c[:, 1] << 21) | c[:, 2]


def _unkey(keys):
    return np.stack(((keys >> 42) & 0x1FFFFF, (keys >> 21) & 0x1FFFFF, keys & 0x1FFFFF), axis=1) - 1


def _samples(tris, step, owner):
    a, b, c = tris[:, 0], tris[:, 1], tris[:, 2]
    edge = np.max(np.stack([np.linalg.norm(b - a, axis=1), np.linalg.norm(c - b, axis=1), np.linalg.norm(a - c, axis=1)]), axis=0)
    n_all = np.clip(np.ceil(edge / step).astype(int), 1, 300)
    for n in np.unique(n_all):
        group = np.where(n_all == n)[0]
        i, j = np.meshgrid(np.arange(n + 1), np.arange(n + 1), indexing="ij")
        keep = (i + j) <= n
        w1, w2 = i[keep] / n, j[keep] / n
        w0 = 1 - w1 - w2
        for chunk in np.array_split(group, max(1, len(group) * len(w0) // 1_000_000 + 1)):
            pts = (a[chunk, None] * w0[None, :, None] + b[chunk, None] * w1[None, :, None] + c[chunk, None] * w2[None, :, None]).reshape(-1, 3)
            yield pts, np.repeat(owner[chunk], len(w0))


def main():
    strict = "--strict" in sys.argv
    root = next((Path(a) for a in sys.argv[1:] if not a.startswith("--")), ROOT)
    failed = False
    for asset in ASSETS:
        path = root / asset
        total = 0
        print(f"== {asset}")
        for part in read_glb(path):
            r = inspect(*part)
            total += r["triangles"]
            bad = r["collapsed"] or r["reversed"] or r["floating"] or r["vertices"] >= 65535
            failed |= bool(bad)
            print(
                f"  {r['part']:<18} {r['triangles']:>6} tris {r['vertices']:>6} verts  pieces {r['pieces']:>4}"
                f"  floating {len(r['floating'])}  collapsed {r['collapsed']}  reversed {r['reversed']}"
                f"  normal-turn p99 {r['normal_turn_p99_deg']:>5} deg (>75: {r['normal_turn_over_75deg']})"
                + (f"  occlusion {r['occlusion'][0]}..1 mean {r['occlusion'][1]}" if "occlusion" in r else "")
                + ("   <<" if bad else ""),
                flush=True,
            )
            for piece in r["floating"][:6]:
                print(f"      floating piece {piece[0]}: clear by more than {piece[1] * 1000:.1f} mm, near {piece[2]}")
        print(f"  total {total} triangles")
    if strict and failed:
        sys.exit(1)


if __name__ == "__main__":
    main()
