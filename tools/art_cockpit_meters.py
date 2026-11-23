"""Print the four auxiliary instrument cards. Run with Python and Pillow."""
from math import cos, sin, radians
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

DEST = Path(__file__).resolve().parents[1] / "godot/art/pilot_fleet/cockpit_meters.png"
TILE = 512


def typeface(size, mono=False):
    for name in (("consolab.ttf", "DejaVuSansMono-Bold.ttf") if mono else ("arialbd.ttf", "DejaVuSans-Bold.ttf")):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            pass
    return ImageFont.load_default(size=size)


def card(base):
    tile = Image.new("RGB", (TILE, TILE), base)
    return tile, ImageDraw.Draw(tile)


def label(d, at, words, size, ink, mono=False):
    d.text(at, words, font=typeface(size, mono), fill=ink, anchor="mm")


def brake_card():
    im, d = card("#172027")
    white, red = "#e6e7e2", "#ff6847"
    d.rectangle((0, 0, 20, 512), fill=red)
    label(d, (264, 73), "BRAKE BIAS", 58, white)
    d.line((41, 135, 473, 135), fill="#626f74", width=3)
    # The physical cursor travels from 13 to 87 percent of the card's width.
    for i in range(21):
        x = round(512 * (.13 + .74*i/20))
        y = 245 if i % 5 == 0 else 269
        d.line((x, y, x, 313), fill=white if 2 <= i <= 18 else red, width=6 if i % 5 == 0 else 3)
    label(d, (256, 194), "0", 51, white, True)
    for x, s in [(90, "PORT"), (409, "STBD")]:
        label(d, (x, 421), s, 40, white, True)
    return im


def compass_card():
    im, d = card("#183537")
    gold, paper = "#d0a669", "#f2e5c6"
    for r in [236, 229, 163]:
        d.ellipse((256-r, 256-r, 256+r, 256+r), outline=gold, width=3)
    for i in range(72):
        a = radians(i*5-90)
        inner = 193 if i % 6 == 0 else 206 if i % 2 == 0 else 215
        d.line((256+inner*cos(a), 256+inner*sin(a), 256+226*cos(a), 256+226*sin(a)),
               fill=paper if i % 6 == 0 else gold, width=5 if i % 6 == 0 else 2)
    for a, title in enumerate("NESW"):
        angle = radians(a*90-90)
        label(d, (256+156*cos(angle), 256+156*sin(angle)), title, 45, paper)
    for deg in (45, 135, 225, 315):
        a = radians(deg)
        for r in [50, 90]:
            d.line((256+(r-20)*cos(a), 256+(r-20)*sin(a), 256+r*cos(a), 256+r*sin(a)), fill=gold, width=2)
    label(d, (256, 323), "AZIMUTH", 19, gold)
    return im


def load_card():
    im, d = card("#e4d7b9")
    black, orange = "#24292a", "#aa3b22"
    d.rectangle((0, 0, 512, 101), fill=black)
    label(d, (256, 52), "DRAWBAR LOAD", 46, "#f3ddaf")
    for y, name in [(222, "L"), (351, "R")]:
        label(d, (49, y), name, 61, black)
        d.rounded_rectangle((88,y-21,447,y+21), radius=8, fill=black)
        for i in range(11):
            x = 99 + round(335*i/10)
            d.line((x, y-26, x, y-43 if i%5==0 else y-35), fill=black, width=4)
        d.rectangle((375,y-18,436,y+18), fill=orange)
    label(d, (101, 445), "0", 37, black, True)
    label(d, (399, 445), "100%", 37, black, True)
    return im


def slip_card():
    im, d = card("#201c33")
    lilac, white = "#b49aff", "#f2f1ff"
    label(d, (256, 74), "LATERAL G", 57, white)
    path = []
    for i in range(101):
        v = i / 50 - 1
        path.append((256 + 189.44*v, 302-57*v*v))
    d.line(path, fill=lilac, width=9)
    for value in [-1, -.5, 0, .5, 1]:
        x, y = 256+189.44*value, 302-57*value*value
        d.line((x, y+17, x, y+35), fill=white, width=4)
    for x, title in [(74, "20"), (256, "0"), (438, "20")]:
        label(d, (x, 411), title, 43, lilac, True)
    return im


if __name__ == "__main__":
    atlas = Image.new("RGB", (1024, 1024))
    for i, tile in enumerate([brake_card(), compass_card(), load_card(), slip_card()]):
        atlas.paste(tile, (i % 2 * TILE, i // 2 * TILE))
    atlas.save(DEST, optimize=True)
