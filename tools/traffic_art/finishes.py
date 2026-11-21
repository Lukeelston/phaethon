"""Original fleet paint, mechanical trims, lenses and markings in a shared 2K atlas."""

from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw

CELL, PAD, COLS, ROWS = 256, 8, 8, 4
# sRGB color, instance-paint coverage, roughness, metallic, emission.
FINISH = {
    "paint": ((225, 226, 222), 1, 0.34, 0.38, 0),
    "band": ((233, 233, 219), 1, 0.31, 0.36, 0),
    "graphite": ((40, 48, 51), 0, 0.62, 0.34, 0),
    "glass": ((41, 68, 81), 0, 0.19, 0.34, 0),
    "alloy": ((153, 161, 159), 0, 0.43, 0.80, 0),
    "hot": ((107, 88, 75), 0, 0.49, 0.73, 0),
    "grille": ((51, 61, 63), 0, 0.64, 0.43, 0),
    "vents": ((68, 78, 80), 0, 0.58, 0.56, 0),
    "cargo": ((204, 202, 186), 1, 0.59, 0.37, 0),
    "hatch": ((208, 204, 184), 1, 0.49, 0.34, 0),
    "freight_id": ((32, 55, 57), 0, 0.55, 0.22, 0),
    "ivory": ((208, 212, 201), 0, 0.38, 0.30, 0),
    "white_lens": ((189, 225, 235), 0, 0.24, 0.12, 0.72),
    "red_lens": ((237, 53, 37), 0, 0.31, 0.11, 0.82),
    "amber": ((248, 156, 52), 0, 0.29, 0.12, 0.75),
    "drive": ((89, 183, 225), 0, 0.34, 0.25, 0.78),
    "rubber": ((32, 36, 37), 0, 0.88, 0.02, 0),
    "hub": ((110, 118, 117), 0, 0.40, 0.72, 0),
    "roof": ((157, 159, 152), 0, 0.57, 0.52, 0),
    "hazard": ((209, 153, 61), 0, 0.59, 0.32, 0),
    "rail": ((41, 76, 86), 0, 0.43, 0.43, 0),
    "oxide": ((180, 86, 43), 0, 0.45, 0.33, 0),
    "cabin": ((38, 65, 78), 0, 0.22, 0.40, 0),
    "service": ((131, 143, 146), 0, 0.49, 0.59, 0),
    "route": ((23, 33, 33), 0, 0.48, 0.13, 0),
    "airline": ((228, 227, 215), 0, 0.36, 0.34, 0),
    "glassband": ((206, 210, 204), 0, 0.34, 0.30, 0),
    "plate": ((34, 47, 49), 0, 0.48, 0.14, 0),
    "vega": ((220, 222, 212), 0.85, 0.36, 0.32, 0),
    "kestrel": ((220, 222, 212), 0.85, 0.36, 0.32, 0),
    "marrow": ((220, 222, 212), 0.85, 0.36, 0.32, 0),
    "tallow": ((220, 222, 212), 0.85, 0.36, 0.32, 0),
}
INDEX = {k: i for i, k in enumerate(FINISH)}
LETTER = {
    "A": "01110/10001/11111/10001/10001",
    "B": "11110/10001/11110/10001/11110",
    "C": "01111/10000/10000/10000/01111",
    "D": "11110/10001/10001/10001/11110",
    "E": "11111/10000/11110/10000/11111",
    "F": "11111/10000/11110/10000/10000",
    "G": "01111/10000/10111/10001/01111",
    "H": "10001/10001/11111/10001/10001",
    "I": "111/010/010/010/111",
    "K": "10001/10010/11100/10010/10001",
    "L": "10000/10000/10000/10000/11111",
    "M": "10001/11011/10101/10001/10001",
    "N": "10001/11001/10101/10011/10001",
    "O": "01110/10001/10001/10001/01110",
    "P": "11110/10001/11110/10000/10000",
    "R": "11110/10001/11110/10010/10001",
    "S": "01111/10000/01110/00001/11110",
    "T": "11111/00100/00100/00100/00100",
    "U": "10001/10001/10001/10001/01110",
    "V": "10001/10001/10001/01010/00100",
    "W": "10001/10001/10101/11011/10001",
    "Y": "10001/01010/00100/00100/00100",
    "0": "01110/10001/10001/10001/01110",
    "1": "010/110/010/010/111",
    "2": "11110/00001/01110/10000/11111",
    "3": "11110/00001/01110/00001/11110",
    "4": "10010/10010/11111/00010/00010",
    "6": "01111/10000/11110/10001/01110",
    "7": "11111/00010/00100/01000/01000",
    "8": "01110/10001/01110/10001/01110",
    "9": "01110/10001/01111/00001/11110",
    " ": "00/00/00/00/00",
    "-": "000/000/111/000/000",
}


def stencil(d, text, box, color):
    rows = [LETTER[ch].split("/") for ch in text]
    x, y, x2, y2 = box
    unit = (x2 - x) / (sum(len(r[0]) + 1 for r in rows) - 1)
    for glyph in rows:
        for i, row in enumerate(glyph):
            for j, p in enumerate(row):
                if p == "1":
                    d.rectangle(
                        (
                            round(x + j * unit),
                            round(y + i * (y2 - y) / 5),
                            round(x + (j + 1) * unit - 0.35),
                            round(y + (i + 1) * (y2 - y) / 5 - 0.35),
                        ),
                        fill=color,
                    )
        x += (len(glyph[0]) + 1) * unit


def build_atlas(folder: Path):
    size = CELL - 2 * PAD
    y, x = np.mgrid[:size, :size]
    atlas = Image.new("RGB", (COLS * CELL, ROWS * CELL))
    props = Image.new("RGBA", atlas.size)
    for j, (name, (base, mask, rough, metal, glow)) in enumerate(FINISH.items()):
        rng = np.random.default_rng(295 + j)
        grain = rng.normal(0, 1.2, x.shape)
        wash = (
            1 + 0.022 * np.cos(x / 77 + y / 105) + 0.012 * np.sin(y / 31) + grain / 255
        )
        if name in ("glass", "cabin"):
            wash = (
                0.76
                + 0.42 * (1 - y / size)
                + 0.13 * np.sin((x * 0.23 + y) / 28)
                + 0.06 * np.exp(-(((x * 0.68 - y + 64) / 22) ** 2))
            )
        if name in ("cargo", "roof"):
            phase = x * 2 * np.pi / (27 if name == "cargo" else 23)
            wash += 0.12 * np.cos(phase) - 0.23 * np.exp(
                -(((np.sin(phase / 2)) / 0.23) ** 2)
            )
        if name == "hot":
            wash += 0.18 * np.sin(y / 24) + 0.06 * np.cos(x / 8)
        pix = np.clip(wash[:, :, None] * base, 0, 255).astype(np.uint8)
        img = Image.fromarray(pix)
        d = ImageDraw.Draw(img)
        data = Image.new(
            "RGBA", img.size, tuple(round(v * 255) for v in (mask, rough, metal, glow))
        )
        q = ImageDraw.Draw(data)
        if name in ("paint", "hatch", "service", "roof", "cargo"):
            dark = tuple(int(c * 0.69) for c in base)
            edge = tuple(min(255, int(c * 1.13)) for c in base)
            if name in ("hatch", "service"):
                d.rounded_rectangle((9, 12, 230, 229), radius=11, outline=dark, width=3)
                d.line((22, 230, 218, 230), fill=edge, width=2)
            for a in (14, 225):
                for b in (16, 223):
                    d.ellipse((a - 2, b - 2, a + 2, b + 2), fill=dark)
                    d.point((a - 1, b - 1), fill=edge)
            if name == "service":
                d.rounded_rectangle((57, 95, 177, 118), radius=8, fill=(50, 61, 64))
                d.rectangle((67, 98, 163, 104), fill=(146, 152, 147))
                stencil(d, "LIFT", (87, 131, 147, 151), (52, 64, 65))
        if name in ("band", "airline"):
            for a, b, c in [(140, 188, (34, 65, 73)), (192, 201, (188, 120, 55))]:
                poly = [
                    (0, a),
                    (91, a),
                    (164, a - 46),
                    (240, a - 46),
                    (240, b - 46),
                    (164, b - 46),
                    (91, b),
                    (0, b),
                ]
                d.polygon(poly, fill=c)
                q.polygon(poly, fill=(0, 100, 96, 0))
        if name == "grille":
            for row in range(-1, 29):
                for col in range(-1, 22):
                    a = col * 12 + 6 * (row % 2)
                    b = row * 9
                    d.polygon(
                        [
                            (a - 4, b - 3),
                            (a + 3, b - 3),
                            (a + 5, b),
                            (a + 3, b + 3),
                            (a - 4, b + 3),
                            (a - 6, b),
                        ],
                        fill=(20, 27, 29),
                    )
        if name == "vents":
            for b in range(8, size, 18):
                d.rounded_rectangle((4, b, 235, b + 10), radius=3, fill=(22, 30, 32))
                d.line((7, b + 11, 231, b + 11), fill=(137, 144, 138), width=2)
        if name in ("white_lens", "red_lens", "amber", "drive"):
            for b in range(9, size, 22):
                d.rectangle((5, b, 234, b + 3), fill=tuple(int(v * 0.61) for v in base))
            for a in range(18, size, 44):
                d.line((a, 4, a, 235), fill=tuple(int(v * 0.72) for v in base), width=2)
        if name == "rubber":
            for xx in range(-size, 2 * size, 28):
                d.line((xx, 0, xx + 88, 120, xx, 240), fill=(22, 26, 26), width=4)
        if name == "hub":
            d.ellipse((18, 18, 222, 222), outline=(69, 79, 78), width=8)
            for a in np.arange(8) * np.pi / 4:
                u = 120 + 51 * np.cos(a)
                v = 120 + 51 * np.sin(a)
                d.ellipse((u - 6, v - 6, u + 6, v + 6), fill=(52, 61, 63))
            d.ellipse(
                (92, 92, 148, 148), fill=(152, 157, 150), outline=(61, 74, 75), width=4
            )
        if name == "hazard":
            for a in range(-180, 300, 64):
                d.polygon(
                    [(a, 0), (a + 27, 0), (a + 143, 240), (a + 116, 240)],
                    fill=(52, 57, 52),
                )
        if name == "glassband":
            for a in (18, 77, 136, 195):
                d.rounded_rectangle(
                    (a, 85, a + 27, 147), radius=12, fill=(137, 155, 159)
                )
                d.rounded_rectangle(
                    (a + 3, 88, a + 24, 144), radius=9, fill=(39, 64, 77)
                )
        if name in ("freight_id", "plate", "route"):
            title, sub = {
                "freight_id": ("E2", "INTERMODAL"),
                "plate": ("N-74", "NETWORK"),
                "route": ("E2", "ERIDANUS"),
            }[name]
            ink = (242, 177, 83) if name == "route" else (224, 225, 203)
            stencil(d, title, (25, 29, 214, 145), ink)
            stencil(d, sub, (19, 175, 221, 211), ink)
            if name == "route":
                stencil(q, title, (25, 29, 214, 145), (0, 155, 20, 155))
                stencil(q, sub, (19, 175, 221, 211), (0, 155, 20, 120))
        if name in ("vega", "kestrel", "marrow", "tallow"):
            num = {"vega": "07", "kestrel": "14", "marrow": "28", "tallow": "61"}[name]
            d.polygon([(14, 18), (220, 18), (200, 213), (8, 213)], fill=(31, 46, 52))
            q.polygon([(14, 18), (220, 18), (200, 213), (8, 213)], fill=(0, 117, 59, 0))
            stencil(d, num, (38, 40, 185, 148), (232, 232, 213))
            stencil(d, name.upper(), (24, 174, 185, 195), (225, 167, 97))
        for target, source in ((atlas, img), (props, data)):
            tile = np.pad(
                np.asarray(source), ((PAD, PAD), (PAD, PAD), (0, 0)), mode="edge"
            )
            target.paste(Image.fromarray(tile), ((j % COLS) * CELL, (j // COLS) * CELL))
    atlas.save(folder / "fleet_color.png", optimize=True)
    props.save(folder / "fleet_finish.png", optimize=True)
