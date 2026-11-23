"""Paint and finish atlas for the three pilot craft. Run via art_pilot_fleet.py."""

from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ART = Path(__file__).resolve().parents[1] / "godot/art/pilot_fleet"
TILES = (
    "enamel",
    "accent",
    "alloy",
    "dark",
    "gold",
    "rubber",
    "ceramic",
    "cloth",
    "vent",
    "stripe",
    "access",
    "brushed",
)
REGIONS = {key: (256 * (i % 4), 256 * (i // 4), 256, 256) for i, key in enumerate(TILES)}
REGIONS["brushed"] = (768, 512, 256, 124)
REGIONS["number"] = (768, 640, 256, 128)
REGIONS["badge"] = (0, 768, 1024, 256)
FLEET = {
    "orrery": ("ORRERY", "IX", "HELIOCENTRIC  /  SURVEY DIVISION", "#eee2bd", "#166363", "#c69956"),
    "kiln": ("KILN", "06", "FOUNDRY  /  HEAVY RECOVERY", "#bf4636", "#f5af44", "#ad734e"),
    "vesper": ("VESPER", "V3", "NIGHT FLIGHT  /  COMPETITION", "#6b5894", "#d5e2e8", "#d69f97"),
}


def font(size, bold=False):
    for path in (
        ("C:/Windows/Fonts/bahnschrift.ttf", "DejaVuSans-Bold.ttf")
        if bold
        else ("C:/Windows/Fonts/consola.ttf", "DejaVuSansMono.ttf")
    ):
        try:
            return ImageFont.truetype(path, size)
        except OSError:
            pass
    return ImageFont.load_default(size=size)


def make_maps(craft):
    name, number, division, paint, accent, trim = FLEET[craft]
    colors = [
        paint,
        accent,
        "#a5b0ae",
        "#38424b",
        trim,
        "#3d4143",
        "#ddd4bd",
        "#655450",
        "#37444d",
        paint,
        paint,
        "#879597",
    ]
    base = Image.new("RGB", (1024, 1024))
    orm = Image.new("RGB", base.size, (250, 106, 130))
    bump = Image.new("L", base.size, 128)
    d, m, h = ImageDraw.Draw(base), ImageDraw.Draw(orm), ImageDraw.Draw(bump)
    rough = [84, 93, 87, 149, 82, 196, 124, 213, 163, 86, 100, 105]
    metal = [65, 51, 232, 176, 210, 12, 9, 5, 173, 65, 65, 238]
    for i, (key, color) in enumerate(zip(TILES, colors)):
        x, y, w, t = REGIONS[key]
        box = (x, y, x + w - 1, y + t - 1)
        d.rectangle(box, fill=color)
        m.rectangle(box, fill=(249, rough[i], metal[i]))
        if key in ("vent", "rubber", "cloth", "brushed"):
            pitch = {"vent": 24, "rubber": 13, "cloth": 5, "brushed": 6}[key]
            for j in range(8, 249, pitch):
                h.line(
                    (x + 4, y + j, x + 251, y + j),
                    fill=97 if key == "vent" else 117,
                    width=3 if key == "vent" else 1,
                )
                if key == "vent":
                    d.rounded_rectangle(
                        (x + 8, y + j, x + 247, y + j + 11), 4, fill="#182127", outline="#647078", width=2
                    )
                if key == "cloth":
                    h.line((x + j, y + 4, x + j, y + 251), fill=138, width=1)
        if key == "stripe":
            d.polygon([(x, y + 44), (x + 256, y + 100), (x + 256, y + 174), (x, y + 118)], fill=accent)
            d.line((x, y + 135, x + 255, y + 191), fill=trim, width=5)
        if key == "access":
            rect = (x + 10, y + 11, x + 245, y + 244)
            d.rounded_rectangle(rect, 14, outline="#575955", width=2)
            h.rounded_rectangle(rect, 14, outline=78, width=3)
            for dx in (21, 234):
                for dy in (22, 233):
                    d.ellipse(
                        (x + dx - 3, y + dy - 3, x + dx + 3, y + dy + 3),
                        fill="#94938c",
                        outline="#424440",
                    )
                    h.ellipse((x + dx - 3, y + dy - 3, x + dx + 3, y + dy + 3), fill=159)
    # Dedicated number island for engine service covers and cab fenders.
    d.rectangle((768, 640, 1023, 767), fill=accent)
    d.line((779, 657, 779, 749), fill="#27333b", width=5)
    d.text((893, 704), number, font=font(86, True), anchor="mm", fill="#25343b")
    d.line((996, 665, 996, 743), fill=trim, width=6)
    m.rectangle((768, 640, 1023, 767), fill=(247, 96, 51))
    h.rectangle((768, 640, 1023, 767), fill=129)
    d.rectangle((0, 768, 1023, 1023), fill="#25343b")
    d.rounded_rectangle((12, 780, 1011, 1011), 15, outline=trim, width=5)
    d.line((42, 945, 970, 945), fill=accent, width=4)
    d.text((50, 798), name, font=font(114, True), fill="#f2e9db", stroke_width=1)
    d.text((967, 811), number, font=font(90, True), anchor="rt", fill=accent)
    d.text((54, 958), division, font=font(29), fill="#e1e2dc")
    for x in (29, 993):
        for y in (798, 994):
            d.ellipse((x - 4, y - 4, x + 4, y + 4), fill="#a7b1ae")
    rng = np.random.default_rng(82)
    grain = rng.normal(0, 1.8, (1024, 1024))
    coarse = Image.fromarray(rng.integers(0, 255, (32, 32), dtype=np.uint8)).resize(
        (1024, 1024), Image.Resampling.BICUBIC
    )
    image = (
        np.asarray(base).astype(float)
        + grain[:, :, None]
        + (np.asarray(coarse).astype(float)[:, :, None] - 128) * 0.029
    )
    Image.fromarray(np.uint8(image.clip(0, 255))).save(ART / (craft + ".webp"), quality=94, method=6)
    if craft == "orrery":
        height = np.asarray(bump).astype(float) / 255 + grain * 0.0016
        dy, dx = np.gradient(height * 3)
        norm = np.stack((-dx, dy, np.ones_like(dx)), axis=2)
        norm /= np.linalg.norm(norm, axis=2)[:, :, None]
        Image.fromarray(np.uint8((norm * 0.5 + 0.5) * 255)).save(ART / "finish_normal.png", optimize=True)
        arr = np.asarray(orm).copy()
        arr[:, :, 1] = (arr[:, :, 1].astype(float) + grain * 1.8).clip(0, 255).astype("uint8")
        Image.fromarray(arr).save(ART / "finish_orm.png", optimize=True)
    template = (ART.parent / "shrike/enamel.tres").read_text(encoding="utf-8")
    for old, new in (
        ("shrike/livery.png", f"pilot_fleet/{craft}.webp"),
        ("shrike/normal.png", "pilot_fleet/finish_normal.png"),
        ("shrike/orm.png", "pilot_fleet/finish_orm.png"),
    ):
        template = template.replace(old, new)
    (ART / (craft + ".tres")).write_text(template, encoding="utf-8")
