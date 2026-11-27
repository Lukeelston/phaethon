"""Cut the trailer from the recordings (tests/film_trailer.gd, tests/film_trailer_garage.gd) to an edit list.
    python tools/trailer/assemble.py CAPTURES EDIT.json OUT.mp4 [--score=SCORE.wav] [--work=DIR] [--sheet=SHEET.jpg]
CAPTURES holds a folder a recording: f########.png (a picture a frame, 30 a second), f.wav (the game's own sound) and
shots.txt (the recording's SHOT lines: where each shot begins and ends, in frames).
The edit list is a JSON array, in order. An entry is one of
    {"src": "garage", "shot": "hall", "in": 1.0, "dur": 4.0}     a piece of a shot: from `in` seconds after its start
    {"card": "PHAETHON", "sub": "Two engines. One cockpit.", "dur": 4.0}     words on black
and may also have
    "label": "VESPER", "note": "Star Command"      a name low on the left for the length of the piece (and a line under it)
    "title": "THE GARAGE"                          a heading across the middle, for the first 2.2 seconds
    "gain": -6                                     the game's sound in this piece, dB (it is levelled first: see LEVEL)
    "fade_in": 0.5, "fade_out": 0.5                the picture from and to black, seconds
    "music": 0.5                                   the score's level from here on (0 to 1; it eases over 1.5 s)
Cuts are hard cuts; the game's sound is cross-faded 40 ms across each. Every shot is entered 3 frames in from its
SHOT line, so a frame either side of a cut in the recording is never used.
Needs NumPy, SciPy, Pillow and ffmpeg (libx264, aac).
"""
import json
import os
import re
import struct
import subprocess
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy.io import wavfile

FPS = 30
SR = 48000
W, H = 1280, 720
HANDLE = 3
LEVEL = {"garage": -30.0, "garage2": -22.0, "default": -17.0}      # what each piece of the game's sound is brought to, dB RMS (by its recording)
MAX_BOOST = 14.0
FONT_DIR = "/usr/share/fonts/opentype/inter/"


def font(weight, size):
    return ImageFont.truetype(os.path.join(FONT_DIR, "InterDisplay-%s.otf" % weight), size)


def spaced(draw, xy, text, fnt, fill, tracking, anchor="l"):
    """Text with letter spacing (Pillow has none): drawn a letter at a time. Returns its width."""
    widths = [draw.textlength(ch, font=fnt) + tracking for ch in text]
    total = sum(widths) - tracking
    x, y = xy
    if anchor == "m":
        x -= total / 2
    for ch, w in zip(text, widths):
        draw.text((x, y), ch, font=fnt, fill=fill)
        x += w
    return total


def overlay(entry, t, dur):
    """The words over a frame t seconds into a piece: an RGBA picture, or None."""
    if not any(k in entry for k in ("label", "title", "card")):
        return None
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    ease = lambda a, b: float(np.clip((t - a) / (b - a), 0, 1)) if b > a else 1.0
    if "label" in entry:
        a = min(ease(0.1, 0.4), 1 - ease(dur - 0.35, dur - 0.1))
        if a > 0:
            layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
            dl = ImageDraw.Draw(layer)
            x, y = 64, H - 118
            dl.rectangle([x, y + 6, x + 3, y + 62], fill=(255, 138, 40, 255))
            for off in ((2, 2),):
                spaced(dl, (x + 18 + off[0], y + off[1]), entry["label"], font("SemiBold", 34), (0, 0, 0, 150), 5)
            spaced(dl, (x + 18, y), entry["label"], font("SemiBold", 34), (255, 255, 255, 255), 5)
            if entry.get("note"):
                spaced(dl, (x + 20, y + 44), entry["note"].upper(), font("Medium", 15), (0, 0, 0, 150), 3)
                spaced(dl, (x + 19, y + 43), entry["note"].upper(), font("Medium", 15), (225, 232, 238, 255), 3)
            layer.putalpha(layer.getchannel("A").point(lambda v: int(v * a)))
            img = Image.alpha_composite(img, layer)
    if "title" in entry:
        a = min(ease(0.15, 0.6), 1 - ease(1.7, 2.2))
        if a > 0:
            layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
            dl = ImageDraw.Draw(layer)
            grow = 14 * ease(0.0, 2.2)
            f = font("Bold", 64)
            spaced(dl, (W / 2 + 3, H / 2 - 40 + 3), entry["title"], f, (0, 0, 0, 140), 18 + grow, "m")
            wide = spaced(dl, (W / 2, H / 2 - 40), entry["title"], f, (255, 255, 255, 255), 18 + grow, "m")
            dl.rectangle([W / 2 - wide / 2, H / 2 + 44, W / 2 + wide / 2, H / 2 + 46], fill=(255, 138, 40, 255))
            layer.putalpha(layer.getchannel("A").point(lambda v: int(v * a)))
            img = Image.alpha_composite(img, layer)
    if "card" in entry:
        a = min(ease(0.2, 0.9), 1 - ease(dur - 0.9, dur - 0.2))
        layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        dl = ImageDraw.Draw(layer)
        big = entry.get("size", 104)
        grow = 10 * ease(0.0, dur)
        wide = spaced(dl, (W / 2, H / 2 - big * 0.72), entry["card"], font("Bold", big), (255, 255, 255, 255), big * 0.22 + grow, "m")
        if entry.get("sub"):
            dl.rectangle([W / 2 - 60, H / 2 + big * 0.42, W / 2 + 60, H / 2 + big * 0.42 + 2], fill=(255, 138, 40, 255))
            spaced(dl, (W / 2, H / 2 + big * 0.42 + 24), entry["sub"].upper(), font("Medium", 20), (214, 222, 230, 255), 6, "m")
        if entry.get("foot"):
            spaced(dl, (W / 2, H - 96), entry["foot"].upper(), font("Medium", 14), (150, 160, 170, 255), 4, "m")
        layer.putalpha(layer.getchannel("A").point(lambda v: int(v * a)))
        img = Image.alpha_composite(img, layer)
    return img


def read_wav(path):
    """A recording's sound as floats (rate, [n, 2]). The movie writer's is 32-bit PCM; one whose recording was cut short
    has no sizes in its header, so the data is read to the end of the file whatever the header says."""
    raw = open(path, "rb").read()
    at = raw.index(b"fmt ")
    _, channels, rate, _, align, bits = struct.unpack("<HHIIHH", raw[at + 8:at + 24])
    at = raw.index(b"data", at) + 8
    count = (len(raw) - at) // align
    data = np.frombuffer(raw, dtype={16: "<i2", 32: "<i4"}[bits], count=count * channels, offset=at).reshape(-1, channels)
    data = data.astype(np.float64) / float(2 ** (bits - 1))
    return rate, (data if channels == 2 else np.repeat(data, 2, axis=1))


def shots_of(folder):
    """{shot: (first frame, last frame)} from a recording's SHOT lines."""
    found = {}
    for line in open(os.path.join(folder, "shots.txt")):
        m = re.match(r"SHOT (\S+) (begin|end) (\d+)", line)
        if m:
            a = found.setdefault(m.group(1), [None, None])
            a[0 if m.group(2) == "begin" else 1] = int(m.group(3))
    return {k: (v[0], v[1]) for k, v in found.items() if v[0] is not None and v[1] is not None}


def main():
    caps, edit_path, out_path = sys.argv[1:4]
    score_path = ""
    work = os.path.join(os.path.dirname(os.path.abspath(out_path)), "assemble-work")
    sheet = ""
    for a in sys.argv[4:]:
        if a.startswith("--score="):
            score_path = a.split("=", 1)[1]
        elif a.startswith("--work="):
            work = a.split("=", 1)[1]
        elif a.startswith("--sheet="):
            sheet = a.split("=", 1)[1]
    edit = json.load(open(edit_path))
    frames_dir = os.path.join(work, "frames")
    subprocess.run(["rm", "-rf", frames_dir])
    os.makedirs(frames_dir, exist_ok=True)
    shots, sound = {}, {}
    total = sum(round(e["dur"] * FPS) for e in edit)
    mix = np.zeros((total * SR // FPS + SR, 2))
    music_gain = np.ones(total * SR // FPS + SR)
    level_now, n, problems, thumbs = 1.0, 0, [], []
    for k, e in enumerate(edit):
        count = round(e["dur"] * FPS)
        at = n * SR // FPS
        if "music" in e:
            ramp = int(1.5 * SR)
            music_gain[at:at + ramp] = np.linspace(level_now, e["music"], ramp)
            music_gain[at + ramp:] = e["music"]
            level_now = e["music"]
        first = 0
        if "src" in e:
            folder = os.path.join(caps, e["src"])
            if e["src"] not in shots and not os.path.exists(os.path.join(folder, "shots.txt")):
                shots[e["src"]] = {}      # (a draft, before that recording is made)
            if e["src"] not in shots:
                shots[e["src"]] = shots_of(folder)
                rate, sound[e["src"]] = read_wav(os.path.join(folder, "f.wav"))
                assert rate == SR, "the recording's sound is at %d Hz" % rate
            if e["shot"] not in shots[e["src"]]:
                problems.append("%s has no shot %s" % (e["src"], e["shot"]))
                e = {"card": e["shot"], "dur": e["dur"], "size": 40}      # (a draft: its place kept, in words on black)
        if "src" in e:
            begin, end = shots[e["src"]][e["shot"]]
            first = begin + HANDLE + round(e.get("in", 0.0) * FPS)
            if first + count > end - HANDLE:
                problems.append("%s/%s: %.2f s from %.2f s runs past the shot (%.2f s long)" % (e["src"], e["shot"], e["dur"], e.get("in", 0.0), (end - begin) / FPS))
            # the game's sound for the piece, levelled, with 40 ms either side for the cross-fade
            pad = int(0.04 * SR)
            a = first * SR // FPS
            seg = sound[e["src"]][max(a - pad, 0):a + count * SR // FPS + pad].copy()
            rms = np.sqrt(np.mean(seg ** 2)) + 1e-9 if len(seg) else 1.0
            want = LEVEL.get(e["src"], LEVEL["default"]) + e.get("gain", 0.0)
            gain = min(10 ** (want / 20.0) / rms, 10 ** (MAX_BOOST / 20.0))
            ramp = np.minimum(np.arange(len(seg)) / (2.0 * pad), 1.0)
            seg *= (ramp * ramp[::-1] * gain)[:, None]
            to = max(at - pad, 0)
            mix[to:to + len(seg)] += seg[:len(mix) - to]
        for i in range(count):
            t = i / FPS
            target = os.path.join(frames_dir, "%06d.png" % n)
            words = overlay(e, t, e["dur"])
            dark = 1.0
            if e.get("fade_in"):
                dark = min(dark, t / e["fade_in"])
            if e.get("fade_out"):
                dark = min(dark, (e["dur"] - t) / e["fade_out"])
            source = os.path.join(caps, e["src"], "f%08d.png" % (first + i)) if "src" in e else ""
            if source and not os.path.exists(source):
                problems.append("missing " + source)
                source = ""
            if source and words is None and dark >= 1.0:
                os.symlink(source, target)
            else:
                img = Image.open(source).convert("RGB") if source else Image.new("RGB", (W, H), (5, 7, 10))
                if dark < 1.0:
                    img = Image.eval(img, lambda v, d=max(dark, 0.0): int(v * d * d))
                if words is not None:
                    img = Image.alpha_composite(img.convert("RGBA"), words).convert("RGB")
                img.save(target, compress_level=1)
            if sheet and i == count // 2:
                thumbs.append((n, k, e.get("shot", e.get("card", "")), target))
            n += 1
    for p in problems:
        print("EDIT PROBLEM: " + p)
    game_rms = np.sqrt(np.mean(mix ** 2))
    if score_path:
        rate, music = read_wav(score_path)
        assert rate == SR
        m = min(len(music), len(mix))
        mix[:m] += music[:m] * music_gain[:m, None]
    mix = mix[:total * SR // FPS]
    tail = int(1.2 * SR)
    mix[-tail:] *= np.linspace(1, 0, tail)[:, None]
    mix = np.tanh(mix * 1.15) / np.tanh(1.15)      # a soft ceiling
    mix *= 0.94 / max(np.max(np.abs(mix)), 1e-9)
    wav = os.path.join(work, "mix.wav")
    wavfile.write(wav, SR, (mix * 32767).astype(np.int16))
    print("%d frames (%.1f s); the game's sound %.1f dB RMS before the score; the mix %.1f dB RMS" % (n, n / FPS, 20 * np.log10(game_rms + 1e-9), 20 * np.log10(np.sqrt(np.mean(mix ** 2)))))
    if sheet:
        cols = 8
        tw, th = 320, 180
        rows = (len(thumbs) + cols - 1) // cols
        s = Image.new("RGB", (tw * cols, th * rows))
        for j, (frame, k, name, path) in enumerate(thumbs):
            im = Image.open(path).convert("RGB").resize((tw, th))
            ImageDraw.Draw(im).text((4, 2), "%d %.1fs %s" % (k, frame / FPS, name), fill=(255, 255, 0))
            s.paste(im, ((j % cols) * tw, (j // cols) * th))
        s.save(sheet, quality=85)
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-framerate", str(FPS), "-i", os.path.join(frames_dir, "%06d.png"), "-i", wav,
        "-c:v", "libx264", "-preset", "slow", "-crf", "20", "-pix_fmt", "yuv420p", "-color_primaries", "bt709", "-color_trc", "bt709", "-colorspace", "bt709",
        "-vf", "scale=out_color_matrix=bt709", "-c:a", "aac", "-b:a", "256k", "-movflags", "+faststart", "-shortest", out_path], check=True)
    print("wrote %s (%.1f MB)" % (out_path, os.path.getsize(out_path) / 1e6))


if __name__ == "__main__":
    main()
