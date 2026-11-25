"""Make the Shrike's UV atlas. Geometry uses the named rectangles in this file."""

from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / "godot/art/shrike"
SIZE = 2048
REGIONS = {"skin": (4, 4, 2040, 1016)}
for i, name in enumerate(("fin", "exhaust", "carbon", "metal", "brake", "ivory", "bronze", "teal")):
    REGIONS[name] = (4 + (i % 4) * 512, 1028 + (i // 4) * 512, 504, 504)

# Subdivide the formerly plain teal swatch. All new hardware still uses the same atlas.
REGIONS.update(teal=(1540, 1540, 248, 248), grip=(1796, 1540, 248, 248), coachwork=(1540, 1796, 504, 248))
REGIONS.update(bronze=(1028, 1540, 248, 504), spine=(1284, 1540, 248, 504))
TEAL, DARK, IVORY, GOLD = (21, 90, 95), (23, 33, 37), (218, 214, 191), (213, 140, 65)
PAINT = {
    "skin": TEAL,
    "fin": IVORY,
    "exhaust": (98, 95, 101),
    "carbon": (42, 49, 52),
    "metal": (140, 150, 151),
    "brake": TEAL,
    "ivory": IVORY,
    "bronze": (167, 119, 73),
    "teal": TEAL,
    "grip": (40, 45, 44),
    "coachwork": TEAL,
    "spine": TEAL,
}
PROPERTIES = {
    "skin": (95, 0),
    "fin": (101, 0),
    "exhaust": (115, 210),
    "carbon": (133, 0),
    "metal": (91, 255),
    "brake": (116, 0),
    "ivory": (102, 0),
    "bronze": (104, 255),
    "teal": (100, 0),
    "grip": (194, 0),
    "coachwork": (97, 0),
    "spine": (96, 0),
}
FONT = ROOT / "godot/art/signs/RG2014EM.ttf"


def plate(size, color):
    return Image.new("RGB", size, color)


def sheet(name, w, h):
    base = plate((w, h), PAINT[name])
    relief = Image.new("L", (w, h), 128)
    color, depth = ImageDraw.Draw(base), ImageDraw.Draw(relief)

    def path(points, ink, width, height=None):
        color.line(points, fill=ink, width=width, joint="curve")
        if height is not None:
            depth.line(points, fill=height, width=width, joint="curve")

    def panel(box, radius=12):
        for draw, fill, line in ((color, (39, 53, 54), 3), (depth, 81, 4)):
            draw.rounded_rectangle(box, radius, outline=fill, width=line)
        x, y, r, b = box
        for xx in (x + 12, r - 12):
            for yy in (y + 11, b - 11):
                color.ellipse((xx - 3, yy - 3, xx + 3, yy + 3), fill=(112, 122, 118))
                depth.ellipse((xx - 3, yy - 3, xx + 3, yy + 3), fill=89)
                color.line((xx - 2, yy + 1, xx + 2, yy - 1), fill=DARK, width=2)

    def words(at, label, size, ink):
        color.text(at, label, font=ImageFont.truetype(str(FONT), size), fill=ink, anchor="mm", stroke_width=0)

    if name == "skin":
        # Two longitudinal sides. In the unwrap the seam is on the keel and
        # the crown runs across the centre. Paint flows continuously over both.
        for sign in (-1, 1):

            def side(y, sign=sign):
                return round(h / 2 + sign * y)

            def band(points, ink):
                color.polygon([(x, side(y)) for x, y in points], fill=ink)

            band(
                [
                    (0, 28),
                    (600, 68),
                    (1220, 155),
                    (2000, 114),
                    (w, 105),
                    (w, 270),
                    (1610, 268),
                    (910, 202),
                    (460, 146),
                    (0, 124),
                ],
                IVORY,
            )
            path(
                [(0, side(134)), (460, side(155)), (904, side(211)), (1610, side(277)), (w, side(278))],
                GOLD,
                6,
            )
            band([(0, 327), (720, 303), (1260, 329), (w, 309), (w, 510), (0, 510)], (39, 52, 55))
            for x in (260, 820, 1200, 1720):
                for y in (82, 291):
                    color.ellipse((x - 3, side(y) - 3, x + 3, side(y) + 3), fill=(130, 140, 135))
                    depth.ellipse((x - 3, side(y) - 3, x + 3, side(y) + 3), fill=79)
            # Opposite flanks read correctly from outside the ship.
            stripe = Image.new("RGBA", (430, 79))
            sd = ImageDraw.Draw(stripe)
            sd.text((211, 38), "SHRIKE   RS", font=ImageFont.truetype(str(FONT), 55), fill=DARK, anchor="mm")
            if sign < 0:
                stripe = stripe.transpose(Image.Transpose.ROTATE_180)
            base.paste(stripe, (1200, side(203) - 39), stripe)
            for x in (505, 540, 575):
                band([(x, 67), (x + 14, 69), (x + 42, 139), (x + 24, 138)], TEAL)
        panel((762, 437, 1149, 575), 14)
        number = Image.new("RGBA", (132, 114))
        ImageDraw.Draw(number).text(
            (66, 57), "27", font=ImageFont.truetype(str(FONT), 96), fill=IVORY, anchor="mm"
        )
        number = number.transpose(Image.Transpose.ROTATE_90)
        base.paste(number, (953 - number.width // 2, 506 - number.height // 2), number)
        for x in (171, 638, 1314, 1790):
            path(
                [(x + 26, 0), (x, 188), (x - 25, 360), (x - 25, 658), (x, 854), (x + 26, h)],
                (58, 75, 75),
                2,
                95,
            )
        for x in (280, 1405):
            panel((x, 446, x + 224, 562), 10)
            for j in range(4):
                path([(x + 42, 471 + j * 18), (x + 178, 471 + j * 18)], DARK, 6, 85)
    elif name == "spine":
        # The center stripe tapers with the aft deck. Captive quarter-turns and
        # the raised louvers follow the same removable service panel.
        color.polygon([(112, 0), (137, 0), (132, h), (122, h)], fill=IVORY)
        path([(145, 0), (140, h)], GOLD, 3)
        panel((18, 76, 229, 386), 15)
        for yy in (105, 346):
            for xx in (34, 212):
                color.ellipse((xx - 4, yy - 4, xx + 4, yy + 4), fill=(153, 155, 143))
                path([(xx - 2, yy + 1), (xx + 2, yy - 1)], DARK, 2, 94)
        words((73, 322), "LIFT", 16, IVORY)
    elif name == "coachwork":
        color.polygon([(0, 57), (151, 71), (w, 25), (w, 111), (178, 142), (0, 114)], fill=IVORY)
        path([(0, 120), (178, 148), (w, 117)], GOLD, 3)
        words((w * 0.58, 83), "27", 49, DARK)
        for x in (24, w - 25):
            color.ellipse((x - 3, 183, x + 3, 189), fill=(136, 148, 145))
            depth.ellipse((x - 3, 183, x + 3, 189), fill=78)
    elif name == "fin":
        color.polygon([(0, 0), (w, 0), (w, 87), (0, 145)], fill=TEAL)
        color.polygon([(0, 155), (w, 97), (w, 110), (0, 169)], fill=GOLD)
        color.polygon([(0, 383), (w, 478), (w, h), (0, h)], fill=DARK)
        words((w * 0.53, h * 0.52), "27", 145, DARK)
        words((w * 0.55, h * 0.74), "SHRIKE  /  RS", 24, TEAL)
    elif name == "brake":
        panel((15, 16, w - 16, h - 15), 22)
        color.polygon([(0, 28), (w, 28), (w, 79), (0, 107)], fill=IVORY)
        color.polygon([(0, 116), (w, 87), (w, 97), (0, 127)], fill=GOLD)
        for i in range(3):
            y = 195 + i * 67
            path([(82, y), (343, y), (391, y - 19)], DARK, 13, 73)
            path([(85, y + 7), (343, y + 7), (395, y - 14)], (102, 130, 126), 3, 153)
        words((187, 407), "AIR BRAKE", 31, IVORY)
    x, y = np.meshgrid(np.arange(w), np.arange(h))
    rng = np.random.default_rng(110 + list(REGIONS).index(name))
    grain = rng.normal(0, 1.65, (h, w))
    rgb = np.asarray(base, dtype=np.float32).copy()
    bump = np.asarray(relief.filter(ImageFilter.GaussianBlur(0.85)), dtype=np.float32)
    rough, metallic = PROPERTIES[name]
    if name == "exhaust":
        patina = np.array([(84, 87, 94), (97, 101, 114), (112, 100, 114), (146, 113, 89), (115, 121, 128)])
        for c in range(3):
            rgb[:, :, c] = np.interp(
                y / h + 0.016 * np.sin(x / 32), np.linspace(0, 1, len(patina)), patina[:, c]
            )
        grain += 2 * np.sin(y * 0.43) + 1.7 * np.sin(x * 0.76)
    if name == "grip":
        # Molded crossed ribs have a rounded crest in both the normal and roughness maps.
        diamond = np.maximum(np.cos((x + y) * np.pi / 9), np.cos((x - y) * np.pi / 9))
        rib = np.clip((diamond - 0.42) * 2.2, 0, 1)
        bump += 13 * rib
        grain += 5 * rib
    if name == "carbon":
        weave = np.where(((x // 8 + y // 8) % 2) == 0, np.cos((x + y) * 0.7), np.cos((x - y) * 0.7))
        grain += 3.5 * weave
        bump += 1.1 * weave
    if name in ("metal", "bronze"):
        grain += rng.normal(0, 2.5, (h, 1)) + 0.6 * np.sin(x * 0.72)
    if name in ("skin", "fin", "brake"):
        # Edge burnishing and dirt follow stamped panel recesses, leaving large
        # uninterrupted paint fields clean enough to read in motion.
        groove = np.maximum(0, 128 - bump) / 55
        grain -= 6 * groove
    rgb += grain[:, :, None]
    dy, dx = np.gradient(bump)
    normal = np.dstack((-dx * 0.049, dy * 0.049, np.ones_like(dx)))
    normal /= np.maximum(np.linalg.norm(normal, axis=2, keepdims=True), 0.001)
    orm = np.stack(
        (
            255 - np.maximum(128 - bump, 0) * 0.72,
            rough + grain * 1.7 + (128 - bump) * 0.22,
            np.full_like(grain, metallic),
            np.full_like(grain, 255 if name in ("skin", "fin", "brake", "ivory", "teal", "coachwork", "spine") else 0),
        ),
        axis=-1,
    )
    return [Image.fromarray(np.uint8(np.clip(v, 0, 255))) for v in (rgb, orm, (normal + 1) * 127.5)]


def generate():
    ART.mkdir(parents=True, exist_ok=True)
    atlases = [plate((SIZE, SIZE), DARK), Image.new("RGBA", (SIZE, SIZE), (255, 110, 0, 0)),
               plate((SIZE, SIZE), (128, 128, 255))]
    for name, (x, y, w, h) in REGIONS.items():
        for target, part in zip(atlases, sheet(name, w, h)):
            # Four texels of edge extrusion protect the first filtered mip levels.
            padded = np.pad(np.asarray(part), ((4, 4), (4, 4), (0, 0)), mode="edge")
            target.paste(Image.fromarray(padded), (x - 4, y - 4))
    for target, name in zip(atlases, ("livery", "orm", "normal")):
        target.save(ART / (name + ".png"), optimize=True)


if __name__ == "__main__":
    generate()
