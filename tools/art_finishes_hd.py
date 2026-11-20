"""Realism spike: tiling surface finishes for the code-built cockpit fittings.

    blender --background --python tools/art_finishes_hd.py

craft_materials.gd wraps these round consoles, switches, pedals and straps by triplanar
projection, one 128 mm tile each: a shade map (multiplies the part's colour), a tangent normal
map and a roughness map (green channel). Every map wraps seamlessly on both axes.
"""
import math
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from art_coaming_hd import f32, png, smooth  # noqa: E402

OUT = Path(__file__).resolve().parents[1] / "godot/art/finish"
RES, TILE = 512, .128
RNG = np.random.default_rng(4107)


def tile(cells_y, cells_x=None, octaves=1):
    """Seamless value noise over the tile, 0-1, with this many lattice cells each way."""
    cells_x = cells_x or cells_y
    total, norm = np.zeros((RES, RES), f32), 0.0
    for k in range(octaves):
        cy, cx = min(RES, cells_y * 2**k), min(RES, cells_x * 2**k)
        lattice = RNG.random((cy, cx), dtype=f32)
        y, x = (np.arange(RES) + .5) * cy / RES, (np.arange(RES) + .5) * cx / RES
        yi, xi = np.floor(y).astype(int), np.floor(x).astype(int)
        fy, fx = smooth(y - yi)[:, None], smooth(x - xi)[None, :]
        y0, y1, x0, x1 = yi % cy, (yi + 1) % cy, xi % cx, (xi + 1) % cx
        top = lattice[np.ix_(y0, x0)] * (1 - fx) + lattice[np.ix_(y0, x1)] * fx
        bot = lattice[np.ix_(y1, x0)] * (1 - fx) + lattice[np.ix_(y1, x1)] * fx
        total += .5**k * (top * (1 - fy) + bot * fy)
        norm += .5**k
    return total / norm


def pebbles(cells):
    """Seamless grain: 1 on each pebble, falling to 0 in the creases between them."""
    points = RNG.random((cells, cells, 2), dtype=f32)
    y, x = np.broadcast_arrays(((np.arange(RES) + .5) * cells / RES)[:, None], ((np.arange(RES) + .5) * cells / RES)[None, :])
    yi, xi = np.floor(y).astype(int), np.floor(x).astype(int)
    f1 = np.full((RES, RES), 9, f32)
    f2 = f1.copy()
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            p = points[(yi + dy) % cells, (xi + dx) % cells]
            d = np.hypot(yi + dy + p[..., 0] - y, xi + dx + p[..., 1] - x).astype(f32)
            f2 = np.where(d < f1, f1, np.minimum(f2, d))
            f1 = np.minimum(f1, d)
    return smooth((f2 - f1) / .24)


def write(name, height, rough, shade):
    k = RES / TILE
    dx = (np.roll(height, -1, 1) - np.roll(height, 1, 1)) * .5
    dy = (np.roll(height, -1, 0) - np.roll(height, 1, 0)) * .5
    n = np.dstack([-dx * k, dy * k, np.ones_like(height)])
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    grey = lambda a: np.repeat(np.clip(a, 0, 1)[..., None] * 255, 3, axis=2).astype(np.uint8)
    png(OUT / f"{name}_normal.png", np.rint((n * .5 + .5) * 255).astype(np.uint8))
    png(OUT / f"{name}_data.png", np.dstack([np.ones_like(rough), np.clip(rough, .04, 1), np.zeros_like(rough)]).__mul__(255).astype(np.uint8))
    png(OUT / f"{name}_shade.png", grey(shade))
    print("FINISH", name, f"roughness {rough.min():.2f}-{rough.max():.2f}", flush=True)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    handled = tile(6, octaves=2)                                     # where hands have polished or dulled it
    # powder coat: a fine pebbled skin, matte, a little glossier where it is touched
    pebble = tile(128, octaves=2)
    write("powder", (pebble - .5) * 2.4e-5 + (tile(48) - .5) * 8e-6, .76 - .12 * smooth((handled - .45) * 4) + (pebble - .5) * .06,
          1 - .07 * pebble - .05 * handled)
    # machined aluminium: fine brushing along one axis, with the odd deeper line
    brush = tile(RES, 3)
    line = smooth((tile(RES, 2) - .9) * 14)
    write("machined", (brush - .5) * 3e-6 - 6e-6 * line, .27 + (brush - .5) * .14 + .1 * line + (handled - .5) * .06, 1 - .08 * brush - .06 * line)
    # satin stainless tube (the nose cage): a coarser brush that blurs what it mirrors
    satin = tile(RES, 2)
    write("satin", (satin - .5) * 6e-6, .44 + (satin - .5) * .16 + (handled - .5) * .08, 1 - .1 * satin)
    # moulded rubber and webbing: a stippled skin
    stipple = smooth((tile(160) - .35) * 3)
    write("rubber", stipple * 1.8e-5 + (tile(RES) - .5) * 4e-6, .9 - .05 * stipple + (handled - .5) * .08, 1 - .1 * stipple - .04 * handled)
    # seat leather: pebbled grain and slow creases, glossier where it is sat on
    grain = pebbles(160)
    write("leather", (grain - 1) * 5.5e-5 + (tile(20, octaves=2) - .5) * 7e-5, .58 + .14 * (1 - grain) - .12 * smooth((handled - .5) * 4),
          (.84 + .2 * grain) * (1 - .05 * handled))
    # harness webbing: a plain weave, 1.6 mm a thread
    u, v = np.meshgrid((np.arange(RES) + .5) * 80 / RES, (np.arange(RES) + .5) * 80 / RES)
    over = (np.floor(u) + np.floor(v)) % 2
    weave = (over * np.sin(math.pi * u)**2 + (1 - over) * np.sin(math.pi * v)**2).astype(f32)
    write("webbing", weave * 7e-5, .82 - .06 * weave + (handled - .5) * .06, .86 + .14 * weave)
    # enamel on the guards and gates: orange peel under a soft gloss
    peel = tile(40, octaves=3)
    write("paint", (peel - .5) * 1.5e-5, .36 + .16 * smooth((handled - .5) * 4) + (peel - .5) * .04, 1 - .04 * handled - .02 * peel)


if __name__ == "__main__":
    main()
