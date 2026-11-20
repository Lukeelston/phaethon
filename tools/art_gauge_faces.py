"""Realism spike: the gauge cluster's dial faces.

    python -I tools/art_gauge_faces.py [--font path/to/Inter.woff2]

Plain Python with Pillow and NumPy. Draws the five faces and the lit legends into one atlas,
godot/art/cockpit/gauge_faces.png: colour in RGB, and in alpha how much of each texel is
translucent print that the backlight shines through. Also writes godot/vr/gauge_layout.gd, the
game's copy of tools/gauge_layout.py plus where everything landed in the atlas.

The faces are racing dials: heavy slanted numerals, block ticks, a coloured band where the
needle should not stay. Lettering is set in Inter (SIL Open Font License), read from Blender's
own fonts folder; only the drawn faces are kept, not the font.
"""
import json
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, str(Path(__file__).resolve().parent))
import gauge_layout as L  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
ATLAS, LAYOUT = ROOT / "godot/art/cockpit/gauge_faces.png", ROOT / "godot/vr/gauge_layout.gd"
FONT = sys.argv[sys.argv.index("--font") + 1] if "--font" in sys.argv else r"C:\Program Files\Blender Foundation\Blender 5.1\5.1\datafiles\fonts\Inter.woff2"
RES, S, FILL = 2048, 3, .97               # atlas size, supersampling, and how much of its cell a dial fills
BLACK, WHITE, ORANGE, RED, AMBER = (9, 9, 10), (238, 238, 232), (255, 98, 20), (232, 32, 26), (255, 172, 48)
CELLS = {"mach": (0, 0, 1024), "thrL": (1024, 0, 800), "thrR": (0, 1024, 800), "engL": (1024, 800, 608), "engR": (1024, 1408, 608)}
CAP = .7275                               # Inter's capital height, of its em


def font(cap_px, weight):
    f = ImageFont.truetype(FONT, max(4, round(cap_px / CAP)))
    f.set_variation_by_axes([32, weight])
    return f


class Face:
    """A square of the atlas, drawn at S times its size in the dial's own units: x right, y up,
    1 at the dial's edge."""

    def __init__(self, px, scale=None):
        self.w, self.h = (px, px) if isinstance(px, int) else px
        self.col = Image.new("RGB", (self.w * S, self.h * S), BLACK)
        self.lit = Image.new("L", (self.w * S, self.h * S), 0)
        self.k = (scale or self.w / 2 * FILL) * S
        self.cx, self.cy = self.w * S / 2, self.h * S / 2

    def at(self, x, y):
        return self.cx + x * self.k, self.cy - y * self.k

    def polar(self, r, deg):
        return self.at(r * math.cos(math.radians(deg)), r * math.sin(math.radians(deg)))

    def poly(self, points, colour, glow=255):
        ImageDraw.Draw(self.col).polygon(points, fill=colour)
        ImageDraw.Draw(self.lit).polygon(points, fill=glow)

    def tick(self, deg, r0, r1, width, colour=WHITE, glow=255):
        t = math.radians(deg)
        ox, oy = -math.sin(t) * width / 2, math.cos(t) * width / 2
        ends = [(r * math.cos(t), r * math.sin(t)) for r in (r0, r1)]
        self.poly([self.at(ends[0][0] + ox, ends[0][1] + oy), self.at(ends[1][0] + ox, ends[1][1] + oy),
                   self.at(ends[1][0] - ox, ends[1][1] - oy), self.at(ends[0][0] - ox, ends[0][1] - oy)], colour, glow)

    def band(self, a0, a1, r0, r1, colour=WHITE, glow=255):
        steps = max(2, int(abs(a1 - a0)) + 1)
        angles = np.linspace(a0, a1, steps)
        self.poly([self.polar(r1, a) for a in angles] + [self.polar(r0, a) for a in angles[::-1]], colour, glow)

    def box(self, left, bottom, right, top, width, colour=WHITE, glow=150):
        """A printed hairline round a window cut in the face."""
        for a, b in (((left, bottom), (right, bottom)), ((right, bottom), (right, top)), ((right, top), (left, top)), ((left, top), (left, bottom))):
            dx, dy = (width / 2, 0) if a[0] == b[0] else (0, width / 2)
            self.poly([self.at(a[0] - dx - dy * 0, a[1] - dy), self.at(b[0] - dx, b[1] - dy) if a[0] == b[0] else self.at(b[0], b[1] - dy),
                       self.at(b[0] + dx, b[1] + dy), self.at(a[0] + dx, a[1] + dy) if a[0] == b[0] else self.at(a[0], a[1] + dy)], colour, glow)

    def text(self, words, x, y, cap, colour=WHITE, weight=700, slant=0.0, track=0.0, glow=255, squeeze=1.0):
        """Words centred on (x, y) with capitals `cap` tall; `track` is extra spacing, of the cap height."""
        cap_px = cap * self.k
        f = font(cap_px, weight)
        gaps = track * cap_px
        widths = [f.getlength(ch) for ch in words]
        total = sum(widths) + gaps * (len(words) - 1)
        pad = int(cap_px * .6) + 4
        tile = Image.new("L", (int(total) + 2 * pad, int(cap_px * 1.6) + 2 * pad), 0)
        pen, base = pad, pad + cap_px * 1.25
        draw = ImageDraw.Draw(tile)
        for ch, w in zip(words, widths):
            draw.text((pen, base), ch, font=f, fill=255, anchor="ls")
            pen += w + gaps
        if slant:
            tile = tile.transform(tile.size, Image.AFFINE, (1, slant, -slant * (base - cap_px / 2), 0, 1, 0), Image.BICUBIC)
        if squeeze != 1.0:
            tile = tile.resize((max(1, int(tile.width * squeeze)), tile.height), Image.LANCZOS)
            total, pad = total * squeeze, pad * squeeze
        px, py = self.at(x, y)
        corner = (int(round(px - pad - total / 2)), int(round(py - (base - cap_px / 2))))
        self.col.paste(colour, corner, tile)
        self.lit.paste(Image.new("L", tile.size, glow), corner, tile)

    def image(self):
        rgba = self.col.convert("RGBA")
        rgba.putalpha(self.lit)
        return rgba.resize((self.w, self.h), Image.LANCZOS)


def sweep(a0, a1, value):
    return a0 + (a1 - a0) * value


def numerals(face, a0, a1, count, radius, cap, hot_from=None, hot=RED):
    for n in range(count + 1):
        t = math.radians(sweep(a0, a1, n / count))
        face.text(str(n), radius * math.cos(t), radius * math.sin(t), cap, hot if hot_from is not None and n >= hot_from else WHITE,
                  weight=800, slant=.17)


def mach_face():
    f = Face(CELLS["mach"][2])
    a0, a1 = 200, -20
    for i in range(41):                                               # a block every Mach, a bar at the halves, fifths between
        zone = RED if i / 5 >= 7 else WHITE
        if i % 5 == 0:
            f.tick(sweep(a0, a1, i / 40), .84, .975, .026, zone)
        else:
            f.tick(sweep(a0, a1, i / 40), .925, .975, .009, zone)
    for i in range(8):
        f.tick(sweep(a0, a1, (i + .5) / 8), .885, .975, .014, RED if i >= 7 else WHITE)
    f.band(a0, a1, .975, .985)
    f.band(sweep(a0, a1, 7 / 8), a1, .802, .836, RED)                 # the last Mach is the craft's limit
    numerals(f, a0, a1, 8, .69, .15, hot_from=7)
    f.text("MACH", 0, .515, .07, weight=700, track=.22, glow=220)
    f.text("GEAR", -.225, .325, .042, weight=600, track=.16, glow=170)
    f.text("MPH", 0, -.705, .07, weight=700, track=.22, glow=220)
    f.text("BAT", -.628, -.668, .05, weight=600, track=.14, glow=170)
    f.box(*L.SPEED_WINDOW, .008)
    f.box(*L.GEAR_WINDOW, .008)
    return f.image()


def thrust_face(letter):
    f = Face(CELLS["thrL"][2])
    a0, a1 = 225, -45
    gate = L.GATE * 10
    for i in range(21):
        zone = ORANGE if i / 2 >= gate else WHITE
        if i % 2 == 0:
            f.tick(sweep(a0, a1, i / 20), .84, .975, .03, zone)
        else:
            f.tick(sweep(a0, a1, i / 20), .90, .975, .013, zone)
    f.band(a0, a1, .975, .985)
    f.band(sweep(a0, a1, L.GATE), a1, .802, .838, ORANGE)             # past the burner gate
    g = math.radians(sweep(a0, a1, L.GATE))
    tip, back = (.775 * math.cos(g), .775 * math.sin(g)), (.838 * math.cos(g), .838 * math.sin(g))
    side = (-math.sin(g) * .035, math.cos(g) * .035)
    f.poly([f.at(*tip), f.at(back[0] + side[0], back[1] + side[1]), f.at(back[0] - side[0], back[1] - side[1])], ORANGE)
    numerals(f, a0, a1, 10, .675, .14, hot_from=9, hot=ORANGE)
    f.text(letter, 0, .405, .2, weight=800, slant=.17)
    f.text("THRUST", 0, .25, .062, weight=700, track=.22, glow=220)
    f.text("% x 10", 0, -.275, .052, weight=600, track=.16, glow=170)
    f.text("ENGINE", 0, -.775, .05, weight=600, track=.2, glow=170)
    return f.image()


def engine_face(letter, side):
    f = Face(CELLS["engL"][2])
    for a0, a1, name, y in ((150, 30, "HEAT", .47), (210, 330, "BRAKE", -.47)):
        for i in range(9):
            hot = name == "HEAT" and i / 8 >= L.HEAT_RED
            warm = name == "HEAT" and i / 8 >= L.HEAT_AMBER
            f.tick(sweep(a0, a1, i / 8), .84 if i % 2 == 0 else .905, .975, .036 if i % 2 == 0 else .016, RED if hot else AMBER if warm else WHITE)
        f.band(a0, a1, .975, .987)
        f.text(name, 0, y, .115, weight=700, track=.2, glow=220)
    f.band(sweep(150, 30, L.HEAT_AMBER), sweep(150, 30, L.HEAT_RED), .802, .842, AMBER)
    f.band(sweep(150, 30, L.HEAT_RED), 30, .802, .842, RED)
    f.band(sweep(210, 330, .75), 330, .802, .842, WHITE, 200)         # the last quarter of the brakes' travel
    f.text(letter, side * .49, 0, .21, weight=800, slant=.17)
    return f.image()


def legend(words, gauge, width, height):
    """A lit legend's own tile: white on black, the game tints it with its lamp's colour."""
    scale = CELLS[L.GAUGES[gauge][0]][2] / 2 * FILL
    f = Face((int(round(width * scale)), int(round(height * scale))), scale)
    cap = height * .62
    cap_px = cap * f.k
    face = font(cap_px, 800)
    wide = sum(face.getlength(ch) for ch in words) + .1 * cap_px * (len(words) - 1)
    f.text(words, 0, 0, cap, weight=800, track=.1, squeeze=min(1.0, width * .92 * f.k / wide))   # set narrower if it is too long
    return f.image()


def block():
    f = Face((32, 32), 16)
    ImageDraw.Draw(f.col).rounded_rectangle([4 * S, 3 * S, 28 * S, 29 * S], 3 * S, fill=WHITE)
    ImageDraw.Draw(f.lit).rounded_rectangle([4 * S, 3 * S, 28 * S, 29 * S], 3 * S, fill=255)
    return f.image()


def gd(value):
    return json.dumps(value).replace("true", "true")


def main():
    atlas = Image.new("RGBA", (RES, RES), BLACK + (0,))
    uv = lambda x, y, w, h: [round(x / RES, 6), round(y / RES, 6), round((x + w) / RES, 6), round((y + h) / RES, 6)]
    for key, image in (("mach", mach_face()), ("thrL", thrust_face("L")), ("thrR", thrust_face("R")), ("engL", engine_face("L", -1)),
                       ("engR", engine_face("R", 1))):
        atlas.paste(image, CELLS[key][:2])
    # the lit legends, each drawn once, then the arcs' block and the LCDs' dark glass
    tiles, pen, row = {}, 8, 1840
    telltales = []
    for lamp, gauge, x, y, w, h, words in L.TELLTALES:
        if words not in tiles:
            tile = legend(words, gauge, w, h)
            if pen + tile.width + 8 > 1016:
                pen, row = 8, row + 72
            atlas.paste(tile, (pen, row))
            tiles[words] = uv(pen, row, tile.width, tile.height)
            pen += tile.width + 8
        telltales.append([lamp, gauge, x, y, w, h, tiles[words]])
    if pen + 64 > 1016:
        pen, row = 8, row + 72
    atlas.paste(block(), (pen, row))
    block_uv = uv(pen + 4, row + 3, 24, 26)
    lcd = Image.new("RGBA", (16, 16), (7, 9, 10, 0))
    atlas.paste(lcd, (pen + 40, row))
    lcd_uv = uv(pen + 44, row + 4, 8, 8)
    ATLAS.parent.mkdir(parents=True, exist_ok=True)
    atlas.save(ATLAS)

    gauges = []
    for key, x, y, ro, mouth, recess in L.GAUGES:
        cx, cy, size = CELLS[key]
        gauges.append({"key": key, "x": x, "y": y, "ro": ro, "rg": round(L.glass_radius(ro), 5), "rf": round(L.face_radius(ro), 5),
                       "mouth": mouth, "face": round(mouth - recess, 5),
                       "uv": [round((cx + size / 2) / RES, 6), round((cy + size / 2) / RES, 6), round(size / 2 * FILL / RES, 6)]})
    lines = ["## The analogue gauge cluster's layout. Written by tools/art_gauge_faces.py from",
             "## tools/gauge_layout.py: change it there and run the tool again, not here.",
             "## Flat layout: x metres along the panel's arc, y up, depths toward the pilot. On a face,",
             "## radii are fractions of the face's radius and angles are degrees anticlockwise from three",
             "## o'clock. uv is [centre u, centre v, radius] for a dial and [u0, v0, u1, v1] for a tile.",
             "extends RefCounted", ""]
    for name, value in (("R", L.R_ARC), ("HALF_W", L.HALF_W), ("Y_BOTTOM", L.Y_BOTTOM), ("SEAT", L.SEAT), ("DOME", L.DOME), ("CHAPTER", L.CHAPTER),
                        ("CHAPTER_R", L.CHAPTER_R), ("NEEDLE_UP", L.NEEDLE_UP), ("CAP_UP", L.CAP_UP), ("GATE", L.GATE),
                        ("HEAT_AMBER", L.HEAT_AMBER), ("HEAT_RED", L.HEAT_RED)):
        lines.append("const %s := %s" % (name, repr(float(value))))
    lines.append("const GAUGES := [\n\t%s,\n]" % ",\n\t".join(gd(g) for g in gauges))
    lines.append("# key, gauge, angle at zero, angle at full scale, length, full scale")
    lines.append("const NEEDLES := [\n\t%s,\n]" % ",\n\t".join(gd(list(n)) for n in L.NEEDLES))
    lines.append("# lamp, gauge, centre x, centre y, width, height, tile")
    lines.append("const TELLTALES := [\n\t%s,\n]" % ",\n\t".join(gd(t) for t in telltales))
    lines.append("# lamps key0.., gauge, inner radius, outer radius, first angle, last angle, segments")
    lines.append("const ARCS := [\n\t%s,\n]" % ",\n\t".join(gd(list(a)) for a in L.ARCS))
    lines.append("# key, centre x, centre y, half width, half height, stand-off")
    lines.append("const WINDOWS := [\n\t%s,\n]" % ",\n\t".join(gd(list(w)) for w in L.WINDOWS))
    lines.append("const SPEED_WINDOW := %s   # on the centre face: left, bottom, right, top" % gd(list(L.SPEED_WINDOW)))
    lines.append("const GEAR_WINDOW := %s" % gd(list(L.GEAR_WINDOW)))
    lines.append("const LAMPS := %s" % gd(L.LAMPS))
    lines.append("const BLOCK_UV := %s" % gd(block_uv))
    lines.append("const LCD_UV := %s" % gd(lcd_uv))
    LAYOUT.write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
    print("Wrote", ATLAS, ATLAS.stat().st_size, "bytes;", LAYOUT.name, len(L.LAMPS), "lamps,", len(telltales), "legends")


if __name__ == "__main__":
    main()
