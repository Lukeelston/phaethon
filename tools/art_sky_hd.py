"""Realism spike: a seamless cloud map for the Network's sky.

    python -I tools/art_sky_hd.py

Plain Python with Pillow and NumPy. view/network_clouds.gdshader reads it at several scales:
    red    weather: where the cloud fields are and where the sky is clear (read very large)
    green  cumulus: heaped, rounded cells that clump into banks
    blue   how the cumulus is lit: bright on the side of each heap that faces the primary sun,
           dark in its lee (the sun's bearing is fixed in the world, so this can be drawn in)
    alpha  cirrus: long combed streaks for the high, thin layer
Every channel wraps on both axes.
"""
from pathlib import Path

import numpy as np
from PIL import Image

OUT = Path(__file__).resolve().parents[1] / "godot/art/sky/cloud_cover.png"
RES = 2048
RNG = np.random.default_rng(1208)
f32 = np.float32
Y, X = np.meshgrid((np.arange(RES) + .5).astype(f32), (np.arange(RES) + .5).astype(f32), indexing="ij")


def smooth(t):
    t = np.clip(t, 0, 1)
    return t * t * (3 - 2 * t)


def value(cells_y, cells_x=None, warp=None):
    """Seamless value noise, optionally read through a displacement (in texels)."""
    cells_x = cells_x or cells_y
    lattice = RNG.random((cells_y, cells_x), dtype=f32)
    y, x = (Y + (warp[0] if warp else 0)) * cells_y / RES, (X + (warp[1] if warp else 0)) * cells_x / RES
    yi, xi = np.floor(y).astype(int), np.floor(x).astype(int)
    fy, fx = smooth(y - yi), smooth(x - xi)
    a, b = lattice[yi % cells_y, xi % cells_x], lattice[yi % cells_y, (xi + 1) % cells_x]
    c, d = lattice[(yi + 1) % cells_y, xi % cells_x], lattice[(yi + 1) % cells_y, (xi + 1) % cells_x]
    return (a + (b - a) * fx) + ((c + (d - c) * fx) - (a + (b - a) * fx)) * fy


def billow(cells, warp=None):
    """1 at the middle of each rounded cell, falling to 0 where neighbours meet; wraps."""
    points = RNG.random((cells, cells, 2), dtype=f32)
    y, x = (Y + (warp[0] if warp else 0)) * cells / RES, (X + (warp[1] if warp else 0)) * cells / RES
    yi, xi = np.floor(y).astype(int), np.floor(x).astype(int)
    nearest = np.full(Y.shape, 9, f32)
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            p = points[(yi + dy) % cells, (xi + dx) % cells]
            nearest = np.minimum(nearest, np.hypot(yi + dy + p[..., 0] - y, xi + dx + p[..., 1] - x))
    return np.clip(1 - nearest, 0, 1)


def stack(make, cells, octaves, gain=.5, **more):
    total = sum(gain**k * make(cells * 2**k, **more) for k in range(octaves))
    return total / sum(gain**k for k in range(octaves))


def spread(a, lo=1, hi=99):
    lo, hi = np.percentile(a, lo), np.percentile(a, hi)
    return np.clip((a - lo) / (hi - lo), 0, 1).astype(f32)


def main():
    OUT.parent.mkdir(parents=True, exist_ok=True)
    # a slow displacement shared by the cumulus and its erosion, so cells lean and smear together
    warp = ((stack(value, 5, 3) - .5) * 90, (stack(value, 5, 3) - .5) * 90)
    weather = spread(stack(value, 3, 5))
    # heaps: rounded cells over three sizes, gathered into banks by a broader swell
    heaps = stack(billow, 7, 4, gain=.5, warp=warp)
    banks = spread(stack(value, 5, 3, warp=warp))
    cumulus = spread(heaps * (.4 + .8 * banks))
    # toward the sun (CraftView.SUN_ROT: +0.68 x, +0.53 z) the shader would read the map 520 m on;
    # at its 48 km a tile that is 22 texels, so the comparison is made here once
    reach = 520 / 48000 * RES
    ahead = np.roll(cumulus, (-int(round(.5332 / .866 * reach)), -int(round(.6824 / .866 * reach))), axis=(0, 1))
    sunlit = np.clip(.5 + (cumulus - ahead) * 5.0, 0, 1)
    # cirrus: long cells combed one way, then feathered
    combed = stack(lambda c, **k: value(c * 6, c, **k), 5, 4, gain=.6, warp=(warp[0] * 1.6, warp[1] * 1.6))
    cirrus = spread(combed * (.5 + .5 * stack(value, 4, 3)), 3, 99.5)
    rgba = np.dstack([weather, cumulus, sunlit, cirrus])
    Image.fromarray((rgba * 255).astype(np.uint8), "RGBA").save(OUT)
    print("Wrote", OUT, OUT.stat().st_size, "bytes", flush=True)


if __name__ == "__main__":
    main()
