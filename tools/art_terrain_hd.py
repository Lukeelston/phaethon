"""Realism spike: a seamless relief map for the Network's terrain.

    blender --background --python tools/art_terrain_hd.py

network_terrain.gdshader reads it at two world scales (2,048 m and 256 m a tile, both dividing
the terrain's own coordinate period) to give its flat-shaded facets ridges, gullies and scree.
Red and green: the surface's slope east and north. Blue: how sheltered the spot is (gullies
low, ridge lines high), for shading and for where rock shows through.
"""
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from art_coaming_hd import box, f32, png  # noqa: E402
from art_sky_hd import RES, spread, value  # noqa: E402

OUT = Path(__file__).resolve().parents[1] / "godot/art/terrain/terrain_detail.png"


def main():
    OUT.parent.mkdir(parents=True, exist_ok=True)
    height = np.zeros((RES, RES), f32)
    weight = np.ones((RES, RES), f32)
    for k, cells in enumerate((4, 8, 16, 32, 64, 128)):
        ridge = (1 - np.abs(2 * value(cells) - 1))**2              # sharp crests, round valleys
        height += .5**k * ridge * weight
        weight = np.clip(ridge * 1.6, 0, 1)                         # detail gathers on the crests, as on eroded rock
    height = spread(height)
    dx = (np.roll(height, -1, 1) - np.roll(height, 1, 1)) * .5 * RES / 12.0
    dy = (np.roll(height, -1, 0) - np.roll(height, 1, 0)) * .5 * RES / 12.0
    wide = np.pad(height, 24, mode="wrap")
    shelter = spread(height - box(wide, 12)[24:-24, 24:-24])        # above or below its surroundings
    png(OUT, (np.dstack([np.clip(dx * .5 + .5, 0, 1), np.clip(dy * .5 + .5, 0, 1), shelter]) * 255).astype(np.uint8))
    print("Wrote", OUT, OUT.stat().st_size, "bytes; slope range", float(dx.min()), float(dx.max()), flush=True)


if __name__ == "__main__":
    main()
