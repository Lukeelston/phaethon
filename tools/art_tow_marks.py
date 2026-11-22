"""The tow links' painted marks: stencils, a hazard band and the draft gear's data plate.

    python -I tools/art_tow_marks.py [--font path/to/Inter.woff2]

Plain Python with Pillow. Writes one small atlas, godot/art/tow/marks.png, that view/tow_link.gd
wraps round each barrel as a few painted patches (its MARK table is this file's CELLS). Everything
else on a link is geometry and the shared machined finish; these are the things a fitter paints on
afterwards, and paint is the one finish a vertex colour on polished steel cannot give.

    white     a plain patch: what the boot, the conduit's sheath and other one-colour parts map to
    hazard    yellow and black, at 45 degrees, repeating every 64 texels
    id        the link's part number and its working load (the game's own limit: 120 kN reads red)
    no_step   what every long thing an engineer could stand on is stencilled with
    pinch     at the barrel's mouth, where the rod runs in
    plate     the draft gear's riveted data plate

Lettering is Inter (SIL Open Font License) from Blender's fonts folder, with a stencil's bridges cut
through its round letters; only the drawn marks are kept, not the font.
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "godot/art/tow/marks.png"
FONT = sys.argv[sys.argv.index("--font") + 1] if "--font" in sys.argv else r"C:\Program Files\Blender Foundation\Blender 5.1\5.1\datafiles\fonts\Inter.woff2"
W, H, S = 1024, 512, 4                      # the atlas, and how many times over it is drawn before it is shrunk
CAP = .7275                                 # Inter's capital height, of its em
# x, y, width, height in texels (tow_link.gd's MARK is these, a texel in from each edge)
CELLS = {"white": (0, 0, 64, 64), "hazard": (64, 0, 256, 128), "id": (0, 144, 640, 80), "no_step": (0, 232, 640, 80),
         "pinch": (0, 320, 640, 80), "plate": (656, 144, 352, 128)}
INK, CHALK = (16, 16, 17), (232, 232, 226)
YELLOW, RED, DARK, ALLOY = (238, 184, 14), (150, 20, 14), (20, 20, 22), (158, 160, 165)
BRIDGED = "OQ0DC8"                          # the letters a stencil has to hold the middles of


def font(cap_px, weight=760):
    f = ImageFont.truetype(FONT, max(4, round(cap_px / CAP)))
    f.set_variation_by_axes([32, weight])
    return f


def stencil(draw, text, box, cap_px, fill, ground, weight=760, track=.09):
    """One line of capitals centred in `box` (x, y, w, h, in the drawing's own pixels), its round
    letters bridged; shrunk to fit the box's width if it must be."""
    x, y, w, h = box
    while True:
        f = font(cap_px, weight)
        gap = cap_px * track
        widths = [draw.textlength(ch, font=f) for ch in text]
        total = sum(widths) + gap * (len(text) - 1)
        if total <= w or cap_px < 8:
            break
        cap_px *= .96
    pen = x + (w - total) / 2
    base = y + h / 2 + cap_px / 2
    for ch, wide in zip(text, widths):
        draw.text((pen, base), ch, font=f, fill=fill, anchor="ls")
        if ch in BRIDGED:
            mid, half = pen + wide / 2, max(1, cap_px * .055)
            draw.rectangle([mid - half, base - cap_px * 1.1, mid + half, base + cap_px * .1], fill=ground)
        pen += wide + gap


def patch(name, ground):
    """A cell's own drawing, S times its size, and a pen for it."""
    w, h = CELLS[name][2] * S, CELLS[name][3] * S
    image = Image.new("RGB", (w, h), ground)
    return image, ImageDraw.Draw(image), w, h


def main():
    big = Image.new("RGB", (W * S, H * S), (96, 96, 98))
    pen = ImageDraw.Draw(big)

    def place(name, image, bleed=4):
        """Into the atlas, its own edge colour run a few texels past its sides (for the small mipmaps)."""
        x, y, w, h = CELLS[name]
        pen.rectangle([(x - bleed) * S, (y - bleed) * S, (x + w + bleed) * S - 1, (y + h + bleed) * S - 1], fill=image.getpixel((2, 2)))
        big.paste(image, (x * S, y * S))

    image, draw, w, h = patch("white", (255, 255, 255))
    place("white", image, 8)
    # the hazard band: stripes at 45 degrees, 32 texels each, so any 64 texels across are one whole repeat
    image, draw, w, h = patch("hazard", YELLOW)
    for k in range(-h // (32 * S) - 2, w // (32 * S) + 2, 2):
        x0 = k * 32 * S
        draw.polygon([(x0, 0), (x0 + 32 * S, 0), (x0 + 32 * S + h, h), (x0 + h, h)], fill=INK)
    place("hazard", image, 0)
    for name, ground, ink, text in [("id", DARK, CHALK, "TOW LINK 7T-4410   WLL 120 kN"), ("no_step", RED, CHALK, "NO STEP   NO HANDHOLD"),
                                    ("pinch", YELLOW, INK, "PINCH POINT   KEEP CLEAR")]:
        image, draw, w, h = patch(name, ground)
        draw.rectangle([5 * S, 5 * S, w - 5 * S, h - 5 * S], outline=ink, width=2 * S)
        stencil(draw, text, (22 * S, 0, w - 44 * S, h), 34 * S, ink, ground)
        place(name, image)
    # the data plate: bare alloy, a struck border, a rivet in each corner, three lines of small print
    image, draw, w, h = patch("plate", ALLOY)
    draw.rectangle([5 * S, 5 * S, w - 5 * S, h - 5 * S], outline=INK, width=2 * S)
    for cx, cy in [(17, 17), (w / S - 17, 17), (17, h / S - 17), (w / S - 17, h / S - 17)]:
        draw.ellipse([(cx - 5) * S, (cy - 5) * S, (cx + 5) * S, (cy + 5) * S], fill=(96, 98, 104), outline=INK, width=S)
    for row, (text, cap, weight) in enumerate([("DRAFT GEAR  DG-120", 19, 800), ("N2 CHARGE 2.1 MPa", 16, 640), ("INSPECT 400 FLT HR   S/N 0417", 13, 600)]):
        box = (30 * S, (14 + row * 34) * S, w - 60 * S, 32 * S)
        f = font(cap * S, weight)
        draw.text((w / 2, box[1] + box[3] / 2 + cap * S / 2), text, font=f, fill=INK, anchor="ms")
    place("plate", image)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    big.resize((W, H), Image.LANCZOS).save(OUT, optimize=True)
    print(OUT, (W, H), CELLS)


if __name__ == "__main__":
    main()
