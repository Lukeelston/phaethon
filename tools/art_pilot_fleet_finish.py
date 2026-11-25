"""Paint and packed ORM/paint-coat atlas for the four pilot craft."""

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
REGIONS["cloth"] = (768, 256, 128, 256)
REGIONS["bolster"] = (896, 256, 128, 256)
FLEET = {
    "orrery": ("ORRERY", "IX", "HELIOCENTRIC  /  SURVEY DIVISION", "#eee2bd", "#166363", "#c69956"),
    "kiln": ("KILN", "06", "FOUNDRY  /  HEAVY RECOVERY", "#bf4636", "#f5af44", "#ad734e"),
    "vesper": ("VESPER", "V3", "NIGHT FLIGHT  /  COMPETITION", "#6b5894", "#d5e2e8", "#d69f97"),
    "basilisk": ("BASILISK", "B7", "GAZE-SLAVED  /  PURSUIT GUNSHIP", "#474e49", "#e59a2c", "#8c7353"),
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


def make_maps(craft, *, star_command=False):
    name, number, division, paint, accent, trim = FLEET[craft]
    if star_command:
        assert craft == "vesper"
        division = "STAR COMMAND  /  FLIGHT DIVISION"
        paint, accent, trim = "#f4f4eb", "#95e139", "#7238bd"
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
    # A is a finish mask, never opacity. Paint is dielectric even over metal;
    # only the exposed alloys get conductor response. The shader coats paint only.
    orm = Image.new("RGBA", base.size, (250, 123, 0, 128))
    bump = Image.new("L", base.size, 128)
    d, m, h = ImageDraw.Draw(base), ImageDraw.Draw(orm), ImageDraw.Draw(bump)
    rough = [103, 109, 88, 156, 100, 206, 154, 221, 174, 103, 115, 100]
    metal = [0, 0, 255, 0, 255, 0, 0, 0, 0, 0, 0, 255]
    coated = {"enamel", "accent", "stripe", "access"}
    for i, (key, color) in enumerate(zip(TILES, colors)):
        x, y, w, t = REGIONS[key]
        box = (x, y, x + w - 1, y + t - 1)
        d.rectangle(box, fill=color)
        m.rectangle(box, fill=(249, rough[i], metal[i], 255 if key in coated else 0))
        if key in ("vent", "rubber", "cloth", "brushed"):
            pitch = {"vent": 24, "rubber": 13, "cloth": 5, "brushed": 6}[key]
            for j in range(8, t - 7, pitch):
                h.line(
                    (x + 4, y + j, x + w - 5, y + j),
                    fill=97 if key == "vent" else 117,
                    width=3 if key == "vent" else 1,
                )
                if key == "vent":
                    d.rounded_rectangle(
                        (x + 8, y + j, x + 247, y + j + 11), 4, fill="#182127", outline="#647078", width=2
                    )
                if key == "cloth" and j < w - 7:
                    h.line((x + j, y + 4, x + j, y + t - 5), fill=138, width=1)
        if key == "stripe":
            d.polygon([(x, y + 44), (x + 256, y + 100), (x + 256, y + 174), (x, y + 118)], fill=accent)
            d.line((x, y + 135, x + 255, y + 191), fill=trim, width=5)
            if star_command:
                # Red bands cross the white top of each swept wing and engine cover.
                band = Image.new("RGB", (w, t), paint)
                mark = ImageDraw.Draw(band)
                for offset in range(-64, 320, 90):
                    mark.polygon([(offset, 0), (offset + 25, 0),
                                  (offset - 39, t), (offset - 64, t)], fill="#d33948")
                mark.rectangle((0, t - 38, w - 1, t - 1), fill=trim)
                base.paste(band, (x, y))
        if key == "access":
            if star_command:
                d.rectangle(box, fill=trim)
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
                    m.ellipse((x + dx - 3, y + dy - 3, x + dx + 3, y + dy + 3), fill=(226, 119, 255, 0))
    # Coloured vinyl has the accent's hue but its own dry, uncoated finish.
    d.rectangle((896, 256, 1023, 511), fill=accent)
    m.rectangle((896, 256, 1023, 511), fill=(249, 184, 0, 0))
    # Dedicated number island for engine service covers and cab fenders.
    d.rectangle((768, 640, 1023, 767), fill=accent)
    d.line((779, 657, 779, 749), fill="#27333b", width=5)
    d.text((893, 704), number, font=font(86, True), anchor="mm", fill="#25343b")
    d.line((996, 665, 996, 743), fill=trim, width=6)
    m.rectangle((768, 640, 1023, 767), fill=(247, 111, 0, 255))
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
    # Body islands span metres: strong per-texel noise reads as centimetre-wide
    # hammering. Keep enamel clean; retain the fuller grain in fabric and metal.
    paint_mask = np.asarray(orm)[:, :, 3].astype(float) / 255
    fine_scale = 1 - 0.70 * paint_mask
    broad_scale = 1 - 0.60 * paint_mask
    image = (np.asarray(base).astype(float)
             + (grain * fine_scale)[:, :, None]
             + ((np.asarray(coarse).astype(float) - 128) * 0.029 * broad_scale)[:, :, None])
    stem = craft + "_star_command" if star_command else craft
    Image.fromarray(np.uint8(image.clip(0, 255))).save(ART / (stem + ".webp"), quality=94, method=6)
    if craft == "orrery":
        height = np.asarray(bump).astype(float) / 255 + grain * 0.0016
        dy, dx = np.gradient(height * 3)
        norm = np.stack((-dx, dy, np.ones_like(dx)), axis=2)
        norm /= np.linalg.norm(norm, axis=2)[:, :, None]
        Image.fromarray(np.uint8((norm * 0.5 + 0.5) * 255)).save(ART / "finish_normal.png", optimize=True)
        arr = np.asarray(orm).copy()
        # Each material has its own manufacturing texture. Most variation lives
        # in roughness, leaving the livery and its lettering clean and readable.
        for i, key in enumerate((*TILES, "bolster")):
            x, y, w, t = REGIONS[key]
            yy, xx = np.mgrid[:t, :w]
            random = np.random.default_rng(1104 + i)
            fine = random.normal(0, 1, (t, w))
            broad = np.asarray(Image.fromarray(random.integers(0, 255, (9, 9), dtype=np.uint8)).resize(
                (w, t), Image.Resampling.BICUBIC), dtype=float) / 255 - 0.5
            if key in ("alloy", "gold", "brushed"):
                variation = random.normal(0, 5, (t, 1)) + fine * 1.0 + broad * 7
            elif key == "cloth":
                variation = 4 * np.sin(xx * 1.25) * np.sin(yy * 1.25) + fine + broad * 5
            elif key in ("rubber", "ceramic", "dark", "vent", "bolster"):
                variation = fine * 2.4 + broad * 13
            else:
                variation = fine * 1.1 + broad * 10
            patch = arr[y:y+t, x:x+w]
            patch[:, :, 1] = np.clip(patch[:, :, 1].astype(float) + variation, 35, 245)
        # All UVs stop four pixels short of island edges. Extrude that padding
        # so the normal/ORM mip filters cannot borrow a neighbouring finish.
        normal = np.asarray(Image.open(ART / "finish_normal.png")).copy()
        for x, y, w, t in REGIONS.values():
            for atlas in (arr, normal):
                region = atlas[y:y+t, x:x+w]
                region[:] = np.pad(region[4:-4, 4:-4], ((4,4),(4,4),(0,0)), mode="edge")
        Image.fromarray(normal).save(ART / "finish_normal.png", optimize=True)
        Image.fromarray(arr).save(ART / "finish_orm.png", optimize=True)
    template = (ART.parent / "shrike/enamel.tres").read_text(encoding="utf-8")
    for old, new in (
        ("shrike/livery.png", f"pilot_fleet/{craft}.webp"),
        ("shrike/normal.png", "pilot_fleet/finish_normal.png"),
        ("shrike/orm.png", "pilot_fleet/finish_orm.png"),
    ):
        template = template.replace(old, new)
    (ART / (craft + ".tres")).write_text(template, encoding="utf-8")
