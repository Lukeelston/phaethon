"""Livery masks for the pilot craft's painted atlases (Luke, 2026-11-23: "Will you make it so that all
vehicles can have a color option?"; view/livery.gd, view/fleet_finish.gdshader).

Each mask says, texel by texel, how much of the atlas is each of the craft's own colours that a livery
repaints: the shader moves just that share to the livery's colour and keeps the rest, so a panel line, a
fastener, a printed number or name, a number plate or a bare metal tile stays as it was made, and the
edge between paint and band is as soft as the atlas's own. The weights come from the atlases' own
drawings with their grain and mottling taken out (the same tools, run with a random generator that draws
nothing), so they fit the atlases exactly, anti-aliased edges included; each sheet is drawn twice, with
its lettering and without, and a texel counts only where both agree, so lettering keeps its own colour
whatever it is printed on.

Both masks are RGBA, by what each colour is in the craft's design (the livery's own part in brackets):
      R  the enamel, its body colour             (paint)
      G  its bands, accent panels, number plates (pin)
      B  its thin trim lines and pinstripes      (stripe)
      A  the dark lettering printed on a band or a plate: left dark, unless the band goes dark (then
         in the paint, so a number on a black band still reads)
  pilot fleet (tools/art_pilot_fleet_finish.py), art/pilot_fleet/<id>_livery.png: the enamel tile and
      the enamel ground of the stripe tile and the access panel; the accent tile and the stripe tile's
      accent band; the stripe tile's trim line; the number island's ground, rule and number (each craft
      prints its own number there: a mask each). Not the badge.
  Shrike RS (tools/art_shrike_finish.py), art/shrike/livery_mask.png: the teal, the ivory bands and the
      gold pinstripe over the skin, fin, brake, spine, teal and coachwork sheets (not the exhaust, carbon,
      metal, bronze, grip or plain ivory sheets).

python tools/art_livery_masks.py [--check]   (--check: report only, write nothing)
"""

import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parent))
import art_pilot_fleet_finish as Fleet  # noqa: E402
import art_shrike_finish as Shrike  # noqa: E402


class Still:
    """A random generator that draws nothing: the atlases' grain and mottling come out zero."""

    def normal(self, loc=0.0, scale=1.0, size=None):
        return np.zeros(size)

    def integers(self, low, high=None, size=None, dtype=np.int64):
        return np.full(size, 128, dtype=dtype)


class Unlettered:
    """While in effect, nothing is lettered: ImageDraw's text draws nothing."""

    def __enter__(self):
        self.real = ImageDraw.ImageDraw.text
        ImageDraw.ImageDraw.text = lambda *a, **k: None

    def __exit__(self, *exc):
        ImageDraw.ImageDraw.text = self.real


def hex_rgb(code):
    code = code.lstrip("#")
    return tuple(int(code[i : i + 2], 16) for i in (0, 2, 4))


def weights(pixels, palette, wanted):
    """Each pixel as a blend of two palette colours (its nearest such pair, in sRGB as the tools drew
    and anti-aliased them): the share of each `wanted` colour in it, and how far it is from that blend."""
    p = pixels.reshape(-1, 3).astype(float)
    cols = np.asarray(palette, dtype=float)
    best = np.full(len(p), np.inf)
    first = np.zeros(len(p), dtype=int)
    second = np.zeros(len(p), dtype=int)
    along = np.zeros(len(p))
    for i in range(len(cols)):
        for j in range(i, len(cols)):
            a, ab = cols[i], cols[j] - cols[i]
            span = float(ab @ ab)
            t = np.zeros(len(p)) if span == 0 else np.clip(((p - a) @ ab) / span, 0.0, 1.0)
            miss = np.linalg.norm(p - (a + t[:, None] * ab), axis=1)
            better = miss < best
            best[better], first[better], second[better], along[better] = miss[better], i, j, t[better]
    shares = []
    for colour in wanted:
        k = palette.index(colour) if colour in palette else -1
        shares.append(((first == k) * (1.0 - along) + (second == k) * along).reshape(pixels.shape[:2]))
    return np.dstack(shares), best.reshape(pixels.shape[:2])


def drawn(pixels, colours):
    """Those of `colours` drawn in a sheet (any texel exactly so)."""
    flat = pixels.reshape(-1, 3)
    return [c for c in colours if np.any(np.all(flat == np.asarray(c), axis=1))]


def shares(lettered, bare, keys, others, ink, ground):
    """Each key colour's share of each texel, counted only where the sheet with and without its
    lettering agree; then the share of the dark `ink` lettered over the key colour `ground` (an index in
    `keys`); and the worst fit."""
    palette = drawn(lettered, list(keys) + list(others) + [ink])
    with_text, miss = weights(lettered, palette, list(keys) + [ink])
    without, _ = weights(bare, drawn(bare, list(keys) + list(others) + [ink]), keys)
    lettering = np.minimum(with_text[:, :, -1], without[:, :, ground])
    return np.dstack([np.minimum(with_text[:, :, :-1], without), lettering]), miss.max()


def fleet_base(craft):
    """The craft's atlas as drawn, before its grain and mottling (make_maps with nothing random)."""
    captured = {}
    real = np.random.default_rng, Image.Image.save, Path.write_text
    np.random.default_rng = lambda *a, **k: Still()
    Image.Image.save = lambda self, fp, *a, **k: captured.__setitem__(Path(fp).name, self.copy())
    Path.write_text = lambda self, *a, **k: None
    try:
        Fleet.make_maps(craft)
    finally:
        np.random.default_rng, Image.Image.save, Path.write_text = real
    return np.asarray(captured[craft + ".webp"].convert("RGB"))


# the fleet atlas's sheets a livery repaints, and which of the craft's colours it repaints in each
FLEET_SHEETS = {
    "enamel": (0, 0, 256, 256, ("paint",)),
    "accent": (256, 0, 256, 256, ("accent",)),
    "bolster": (896, 256, 128, 256, ("accent",)),
    "stripe": (256, 512, 256, 256, ("paint", "accent", "trim")),
    "access": (512, 512, 256, 256, ("paint",)),
    "number": (768, 640, 256, 128, ("accent", "trim")),
}
FLEET_CHANNEL = {"paint": 0, "accent": 1, "trim": 2}
# ... and every other colour the tool draws in them: the access panel's outline, its fasteners and their
# rims, the number island's rule; and the ink its number is printed in
FLEET_FIXED = ("#575955", "#94938c", "#424440", "#27333b")
FLEET_INK = "#25343b"


def fleet_mask(craft):
    lettered = fleet_base(craft)
    with Unlettered():
        bare = fleet_base(craft)
    _, _, _, paint, accent, trim = Fleet.FLEET[craft]
    own = {"paint": hex_rgb(paint), "accent": hex_rgb(accent), "trim": hex_rgb(trim)}
    mask = np.zeros((1024, 1024, 4))
    report = []
    for name, (x, y, w, h, keys) in FLEET_SHEETS.items():
        area = (slice(y, y + h), slice(x, x + w))
        for key in keys:
            assert np.any(np.all(lettered[area] == np.asarray(own[key]), axis=2)), f"{craft} {name}: no {key} {own[key]}"
        ground = keys.index("accent") if "accent" in keys else 0
        share, miss = shares(lettered[area], bare[area], [own[k] for k in keys], [hex_rgb(c) for c in FLEET_FIXED],
                             hex_rgb(FLEET_INK), ground)
        for k, key in enumerate(keys):
            mask[area + (FLEET_CHANNEL[key],)] = share[:, :, k]
        mask[area + (3,)] = share[:, :, -1]
        report.append(f"{name} worst fit {miss:.1f}")
    return mask, report


def shrike_sheets():
    """Each sheet of the Shrike's atlas as drawn (art_shrike_finish.sheet's own canvas, before grain)."""
    canvas = {}
    real_plate = Shrike.plate

    def keep(size, color):
        image = real_plate(size, color)
        canvas.setdefault("first", image)
        return image

    Shrike.plate = keep
    try:
        sheets = {}
        for name, (x, y, w, h) in Shrike.REGIONS.items():
            canvas.clear()
            Shrike.sheet(name, w, h)
            sheets[name] = np.asarray(canvas["first"].convert("RGB"))
        return sheets
    finally:
        Shrike.plate = real_plate


SHRIKE_SHEETS = ("skin", "fin", "brake", "spine", "teal", "coachwork")
SHRIKE_KEYS = (Shrike.TEAL, Shrike.IVORY, Shrike.GOLD)      # R, G, B
# ... and every other colour art_shrike_finish.sheet draws in those sheets: lettering and louvres, the lower
# band, panel outlines, fasteners, panel seams, the brake's ribs
SHRIKE_FIXED = (Shrike.DARK, (39, 52, 55), (39, 53, 54), (112, 122, 118), (130, 140, 135), (58, 75, 75),
                (153, 155, 143), (136, 148, 145), (102, 130, 126))


def shrike_mask():
    lettered = shrike_sheets()
    with Unlettered():
        bare = shrike_sheets()
    mask = np.zeros((Shrike.SIZE, Shrike.SIZE, 4))
    report = []
    for name in SHRIKE_SHEETS:
        x, y, w, h = Shrike.REGIONS[name]
        share, miss = shares(lettered[name], bare[name], SHRIKE_KEYS, SHRIKE_FIXED[1:], Shrike.DARK, 1)
        # (the atlas pads each sheet with four texels of its own edge: so does its mask)
        mask[y - 4 : y + h + 4, x - 4 : x + w + 4] = np.pad(share, ((4, 4), (4, 4), (0, 0)), mode="edge")
        report.append(f"{name} worst fit {miss:.1f}")
    return mask, report


def to_png(mask):
    return Image.fromarray(np.uint8(np.clip(np.rint(mask * 255), 0, 255)))


def main():
    write = "--check" not in sys.argv
    for craft in Fleet.FLEET:
        mask, report = fleet_mask(craft)
        # the mask against the atlas as shipped: where it says "all enamel", the texel is the enamel and its grain
        atlas = np.asarray(Image.open(Fleet.ART / (craft + ".webp")).convert("RGB")).astype(float)
        dev = np.abs(atlas[mask[:, :, 0] > 0.999] - np.asarray(hex_rgb(Fleet.FLEET[craft][3]), dtype=float)).max(axis=1)
        print(f"{craft}: {'; '.join(report)}; enamel texels in the shipped atlas within {np.percentile(dev, 99):.0f} "
              f"of the enamel (99%), {dev.max():.0f} at the most (its lossy edges)")
        if write:
            to_png(mask).save(Fleet.ART / (craft + "_livery.png"), optimize=True)
    mask, report = shrike_mask()
    atlas = np.asarray(Image.open(Shrike.ART / "livery.png").convert("RGB")).astype(float)
    dev = np.abs(atlas[mask[:, :, 0] > 0.999] - np.asarray(Shrike.TEAL, dtype=float)).max(axis=1)
    print(f"shrike: {'; '.join(report)}; teal texels in the shipped atlas within {dev.max():.0f} of the teal")
    if write:
        to_png(mask).save(Shrike.ART / "livery_mask.png", optimize=True)


if __name__ == "__main__":
    main()
