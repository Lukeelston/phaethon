"""Per-vertex ambient occlusion for the craft tools' meshes (art_shrike_airframe, art_pilot_fleet).

Geometry pass, 2026-11-23. Each part is welded from many separate pieces: hoops on a body, pipes in a
saddle, a pad on a seat. With no occlusion where they meet, every piece is lit as if it floated, and
that more than anything reads as assembled from primitives. This bakes how much of the sky each vertex
sees, within a short reach, into the vertex colour's alpha; the craft's shader multiplies its ambient
light by it (view/fleet_finish.gdshader). Nothing is computed at runtime.

NumPy and SciPy only: the part's surface is sampled into a voxel shell, and a fixed fan of
cosine-weighted rays is marched from each vertex through it. Deterministic for a given mesh.
"""

import math

import numpy as np
from scipy import ndimage

RAYS = 48


def _hemisphere(count):
    """Cosine-weighted directions about +Z, a Fibonacci spiral so they cover evenly."""
    golden = math.pi * (3 - math.sqrt(5))
    k = np.arange(count) + 0.5
    r = np.sqrt(k / count)
    a = k * golden
    return np.stack((r * np.cos(a), r * np.sin(a), np.sqrt(1 - r * r)), axis=1)


def _surface_points(tris, step):
    """Points over every triangle no farther than `step` apart."""
    a, b, c = tris[:, 0], tris[:, 1], tris[:, 2]
    edge = np.max(np.stack([np.linalg.norm(b - a, axis=1), np.linalg.norm(c - b, axis=1), np.linalg.norm(a - c, axis=1)]), axis=0)
    count = np.clip(np.ceil(edge / step).astype(int), 1, 600)
    for n in np.unique(count):
        group = np.where(count == n)[0]
        i, j = np.meshgrid(np.arange(n + 1), np.arange(n + 1), indexing="ij")
        keep = (i + j) <= n
        w1, w2 = i[keep] / n, j[keep] / n
        w0 = 1 - w1 - w2
        for chunk in np.array_split(group, max(1, len(group) * len(w0) // 2_000_000 + 1)):
            yield (a[chunk, None] * w0[None, :, None] + b[chunk, None] * w1[None, :, None] + c[chunk, None] * w2[None, :, None]).reshape(-1, 3)


def bake(positions, normals, indices, reach=None, floor=0.22):
    """Ambient visibility per vertex, 1 open to `floor` enclosed. `reach` defaults to a fraction of
    the part's size: a contact shadow, not a global darkening."""
    pos = np.asarray(positions, dtype=float)
    nrm = np.asarray(normals, dtype=float)
    tri = np.asarray(indices).reshape(-1, 3)
    lo, hi = pos.min(axis=0), pos.max(axis=0)
    extent = float(np.max(hi - lo))
    cell = max(extent / 420, 0.0012)
    if reach is None:
        reach = min(max(extent * 0.07, 0.025), 0.32)
    pad = reach + 4 * cell
    origin = lo - pad
    dims = np.ceil((hi - lo + 2 * pad) / cell).astype(int) + 1
    shell = np.zeros(dims, dtype=bool)
    for points in _surface_points(pos[tri], cell * 0.5):
        idx = np.floor((points - origin) / cell).astype(int)
        shell[idx[:, 0], idx[:, 1], idx[:, 2]] = True
    # A shell two cells thick: a ray stepping diagonally cannot slip between its voxels.
    shell = ndimage.binary_dilation(shell, iterations=1)

    fan = _hemisphere(RAYS)
    steps = np.arange(1, int(math.ceil(reach / (cell * 0.75))) + 1) * (reach / math.ceil(reach / (cell * 0.75)))
    falloff = 1 - steps / reach  # a near hit shades more than one at the edge of the reach
    visible = np.ones(len(pos))
    for start in range(0, len(pos), 512):
        p = pos[start:start + 512]
        n = nrm[start:start + 512]
        helper = np.where(np.abs(n[:, :1]) < 0.9, np.array([[1.0, 0, 0]]), np.array([[0, 1.0, 0]]))
        t = np.cross(n, helper)
        t /= np.linalg.norm(t, axis=1)[:, None]
        b = np.cross(n, t)
        # Turn each vertex's fan by its own angle so neighbouring vertices sample different gaps.
        spin = (np.arange(start, start + len(p)) * 2.399963) % (2 * math.pi)
        cs, sn = np.cos(spin)[:, None], np.sin(spin)[:, None]
        t, b = t * cs + b * sn, b * cs - t * sn
        dirs = fan[None, :, 0, None] * t[:, None] + fan[None, :, 1, None] * b[:, None] + fan[None, :, 2, None] * n[:, None]
        # Start clear of the part's own shell.
        o = p + n * (cell * 2.6)
        pts = o[:, None, None, :] + dirs[:, :, None, :] * steps[None, None, :, None]
        idx = np.floor((pts - origin) / cell).astype(int)
        np.clip(idx, 0, dims - 1, out=idx)
        hit = shell[idx[..., 0], idx[..., 1], idx[..., 2]]
        first = np.where(hit.any(axis=2), hit.argmax(axis=2), -1)
        shade = np.where(first >= 0, falloff[np.maximum(first, 0)], 0.0)
        visible[start:start + len(p)] = 1 - shade.mean(axis=1)
    visible = _smooth(pos, tri, visible)
    return np.clip(floor + (1 - floor) * visible, floor, 1.0)


def _smooth(pos, tri, value, rounds=2):
    """Average across welded vertices (same place, separate pieces' seams), then a light one-ring blur:
    48 rays leave a little grain, which on a dense pressing would read as dirt."""
    key = np.round(pos / 1e-5).astype(np.int64)
    _, weld = np.unique(key, axis=0, return_inverse=True)
    weld = weld.ravel()
    groups = np.bincount(weld)
    value = (np.bincount(weld, value) / groups)[weld]
    edges = np.concatenate([tri[:, [0, 1]], tri[:, [1, 2]], tri[:, [2, 0]]])
    edges = np.concatenate([edges, edges[:, ::-1]])
    for _ in range(rounds):
        total = np.bincount(edges[:, 0], value[edges[:, 1]], minlength=len(value))
        count = np.bincount(edges[:, 0], minlength=len(value))
        value = np.where(count > 0, 0.5 * value + 0.5 * total / np.maximum(count, 1), value)
        value = (np.bincount(weld, value) / groups)[weld]
    return value
