"""Repaint the existing coaming's enamel, preserving its chips and metalwork.
Run with Python, Pillow and NumPy from any directory. The material reuses the
original normal and ORM maps. Only the selected livery is submitted for drawing.
"""
from pathlib import Path

import numpy as np
from PIL import Image

ART = Path(__file__).resolve().parents[1] / "godot/art/cockpit"
with Image.open(ART / "coaming_hd_CoamingHD_Base.png") as original:
    rgb = np.asarray(original.convert("RGB").resize((2048, 2048), Image.Resampling.LANCZOS), dtype=np.float32)
red, green, blue = rgb.transpose(2, 0, 1)
# Hue and saturation isolate the enamel, leaving the stitched leather intact.
mask = np.clip((red - green - 35) / 36, 0, 1) * np.clip((green - blue - 14) / 20, 0, 1)
shade = np.clip(red / 193, 0, 1.25)
paint = np.array([20, 103, 107]) * shade[..., None]
result = rgb + mask[..., None] * (paint - rgb)
Image.fromarray(np.uint8(np.clip(result, 0, 255))).save(ART / "shrike_coaming.webp", quality=92, method=6)
