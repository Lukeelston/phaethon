"""Bake two metres of periodically repeating road aggregate. Run with NumPy and Pillow.

R stores mineral brightness, GB store the two signed surface slopes, and A stores
low-frequency binder variation. The same field is sampled at rolling and traffic scales.
"""

from pathlib import Path

import numpy as np
from PIL import Image


SIZE = 1024
METRES = 2.0
DEST = Path(__file__).resolve().parents[1] / "godot" / "art" / "road" / "pavement_detail.png"


def band_noise(rng, sigma_x, sigma_y):
    """Periodic Gaussian-filtered field with unit standard deviation."""
    fx = np.fft.rfftfreq(SIZE)[None, :]
    fy = np.fft.fftfreq(SIZE)[:, None]
    response = np.exp(-2 * np.pi**2 * ((fx * sigma_x)**2 + (fy * sigma_y)**2))
    field = np.fft.irfft2(np.fft.rfft2(rng.standard_normal((SIZE, SIZE))) * response)
    return (field - field.mean()) / field.std()


def fractured_stone(rng, cells, x, y):
    """Jittered angular chips. The gap between the two closest sites locates each rim."""
    x, y = x * cells / SIZE, y * cells / SIZE
    cell_x, cell_y = np.floor(x).astype(int), np.floor(y).astype(int)
    dx, dy = x - cell_x, y - cell_y
    jitter_x, jitter_y, value = rng.random((3, cells, cells))
    first = np.full_like(x, 8.0)
    second = first.copy()
    mineral = np.zeros_like(x)
    for j in (-1, 0, 1):
        for i in (-1, 0, 1):
            key = ((cell_y + j) % cells, (cell_x + i) % cells)
            u = dx - i - (0.13 + 0.74 * jitter_x[key])
            v = dy - j - (0.13 + 0.74 * jitter_y[key])
            distance = u*u + v*v
            closer = distance < first
            mineral = np.where(closer, value[key], mineral)
            second = np.minimum(second, np.where(closer, first, distance))
            first = np.minimum(first, distance)
    rim = np.clip((second - first - 0.055) * 4.0, 0, 1)
    # Some grain faces lie below the binder. The exposed ones catch the sun.
    return rim, mineral


def bake():
    rng = np.random.default_rng(47051)
    y, x = np.indices((SIZE, SIZE), dtype=float)
    x += band_noise(rng, 2.4, 2.4) * 0.63
    y += band_noise(rng, 2.4, 2.4) * 0.63
    chip, mineral = fractured_stone(rng, 99, x, y)
    sand, sand_mineral = fractured_stone(rng, 242, x, y)
    clumps = band_noise(rng, 11, 9)
    pore = np.clip(-band_noise(rng, 1.8, 2.1) - 0.95 - 0.24 * clumps, 0, 1)
    fleck = np.clip((mineral - 0.68) * 3.2, 0, 1) * chip
    brightness = (0.42 + chip * (0.06 + 0.23 * mineral) + 0.14 * fleck
                  + 0.14 * sand * (sand_mineral - 0.45) + 0.026 * clumps - 0.14 * pore)
    brightness += 0.019 * rng.standard_normal((SIZE, SIZE))

    height_mm = chip * (0.28 + 0.72 * mineral) + sand * 0.22 - 0.61 * pore
    metres_per_pixel = METRES / SIZE
    slopes = []
    for axis in (1, 0):
        gradient = (np.roll(height_mm, -1, axis) - np.roll(height_mm, 1, axis)) / (2000.0 * metres_per_pixel)
        slopes.append(0.5 + gradient * 1.8)

    binder = (0.5 + 0.091 * band_noise(rng, 39, 32) + 0.047 * band_noise(rng, 11, 11)
              + 0.038 * band_noise(rng, 30, 3) + 0.015 * clumps)
    packed = np.stack([brightness, *slopes, binder], axis=2)
    DEST.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(np.rint(255 * np.clip(packed, 0, 1)).astype(np.uint8)).save(DEST)


if __name__ == "__main__":
    bake()
