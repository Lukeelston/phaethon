"""The start-up's sounds, baked from real recordings.

    python -I tools/startup_audio_bake.py [--match FOLDER]

Luke, after the eleventh flight: the start-up "sound[s] like an 80's racing arcade box. Use real free
assets if you must". Every sound here is cut from a field recording (tools/audio_src/startup, all
CC0 from Freesound: godot/audio/startup/CREDITS.md), trimmed, layered and levelled; nothing is
synthesised. Written to godot/audio/startup as 48 kHz mono 16-bit WAV, each peaking at -3 dB, with
a manifest that gives the game each sound's takes and its level.

--match FOLDER: the old synthesised bank dumped as <name>.wav. Prints, for each new sound, the level
that makes it as loud as the old one was (K-weighted, loudest 50 ms or 400 ms window). The levels in
SOUNDS below were set from that once; none of this has been judged by ear.
(-I: the sources are downloads. Python is run isolated so nothing beside them can be imported.)
"""
import json
import math
import sys
from pathlib import Path

import numpy as np
import soundfile as sf
from scipy import signal
from scipy.ndimage import maximum_filter1d

RATE = 48000
ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "tools/audio_src/startup"
OUT = ROOT / "godot/audio/startup"
PEAK = 0.7
_cache = {}


# ---- tools ----

def src(name):
    """A source recording, mono at RATE."""
    if name not in _cache:
        path = next(SRC.glob(name + "__*.ogg"))
        x, rate = sf.read(str(path), always_2d=True, dtype="float64")
        x = x.mean(axis=1)
        if rate != RATE:
            g = math.gcd(RATE, rate)
            x = signal.resample_poly(x, RATE // g, rate // g)
        _cache[name] = x
    return _cache[name]


def onset(x, near, span=0.06, db=-26.0):
    """Where the sound near `near` seconds really begins: the first sample within `db` of its peak."""
    a, b = max(0, int((near - span) * RATE)), int((near + span) * RATE)
    seg = np.abs(x[a:b])
    return (a + int(np.argmax(seg > seg.max() * 10 ** (db / 20)))) / RATE


def cut(name, t0, t1, fin=0.002, fout=0.02, snap=False, lead=0.003):
    """A piece of a source, faded at both ends and brought to full scale (the recordings come at every
    level: a layer's gain in mix() is then its level against the others). snap: start `lead` before the
    onset nearest t0."""
    x = src(name)
    if snap:
        d = t1 - t0
        t0 = onset(x, t0) - lead
        t1 = t0 + d
    y = x[int(t0 * RATE):int(t1 * RATE)].copy()
    return full(fade(y, fin, fout))


def full(y):
    return y / max(float(np.abs(y).max()), 1e-9)


def fade(y, fin=0.002, fout=0.02):
    y = y.copy()
    a, b = min(len(y), int(fin * RATE)), min(len(y), int(fout * RATE))
    if a > 1:
        y[:a] *= 0.5 - 0.5 * np.cos(np.linspace(0, math.pi, a))
    if b > 1:
        y[-b:] *= 0.5 + 0.5 * np.cos(np.linspace(0, math.pi, b))
    return y


def damp(y, hold, tau):
    """Let a ring die sooner: full level for `hold` seconds, then falling with time constant tau."""
    t = np.arange(len(y)) / RATE
    return y * np.where(t < hold, 1.0, np.exp(-(t - hold) / tau))


def swell(y, rise, hold, tau):
    """An envelope: up over `rise`, held until `hold`, then falling with time constant tau."""
    t = np.arange(len(y)) / RATE
    return y * np.minimum(t / max(rise, 1e-4), 1.0) * np.where(t < hold, 1.0, np.exp(-(t - hold) / tau))


def pitch(y, ratio):
    """Faster and higher by `ratio` (a tape sped up): under 1 makes a thing bigger and slower."""
    return signal.resample_poly(y, 1000, int(round(1000 * ratio)))


def butter(y, kind, hz, order=2):
    return signal.sosfilt(signal.butter(order, hz, kind, fs=RATE, output="sos"), y)


def mix(*parts):
    """Layers: (samples, start seconds, gain)."""
    n = max(int(at * RATE) + len(y) for y, at, _ in parts)
    out = np.zeros(n)
    for y, at, gain in parts:
        i = int(at * RATE)
        out[i:i + len(y)] += y * gain
    return out


def splice(a, b, over=0.05):
    """b after a, crossfaded at equal power over `over` seconds."""
    n = int(over * RATE)
    k = np.linspace(0, math.pi / 2, n)
    out = np.concatenate([a[:-n], a[-n:] * np.cos(k) + b[:n] * np.sin(k), b[n:]])
    return out


def loop(name, t0, seconds, over=0.5):
    """A piece that repeats without a seam: its end is folded into its beginning."""
    x = src(name)
    n, f = int(seconds * RATE), int(over * RATE)
    seg = x[int(t0 * RATE):int(t0 * RATE) + n + f].copy()
    k = np.linspace(0, math.pi / 2, f)
    out = seg[:n]
    out[:f] = seg[:f] * np.sin(k) + seg[n:n + f] * np.cos(k)
    return out


def limit(y, drop_db, attack=0.001, release=0.06):
    """Hold a sound's few tallest peaks `drop_db` under where they were, so the body of it can be
    played louder: gain rides down just ahead of a peak and recovers over `release`."""
    n = max(1, int(attack * RATE))
    env = maximum_filter1d(np.abs(y), size=2 * n + 1)
    want = np.minimum(1.0, np.abs(y).max() * 10 ** (-drop_db / 20) / np.maximum(env, 1e-9))
    keep = math.exp(-1.0 / (release * RATE))
    gain = np.empty_like(want)
    cur = 1.0
    for i, g in enumerate(want):
        cur = min(g, 1.0 - (1.0 - cur) * keep)
        gain[i] = cur
    return y * np.convolve(gain, np.ones(n) / n, mode="same")


def finish(y, tail=True):
    y = butter(y - y.mean(), "highpass", 28.0)
    if tail:
        y = fade(y, 0.001, 0.012)
    return y * (PEAK / np.abs(y).max())


K1 = ([1.53512485958697, -2.69169618940638, 1.19839281085285], [1.0, -1.69065929318241, 0.73248077421585])
K2 = ([1.0, -2.0, 1.0], [1.0, -1.99004745483398, 0.99007225036621])


def loudest(y, window):
    """K-weighted level (LUFS-like) of the loudest `window` seconds."""
    k = signal.lfilter(*K2, signal.lfilter(*K1, y))
    n = max(1, min(len(k), int(window * RATE)))
    power = np.convolve(k * k, np.ones(n) / n, mode="valid")
    return -0.691 + 10 * math.log10(power.max() + 1e-12)


# ---- the sounds ----

def toggle(at, heavy=False):
    """One throw of the heavy metal switch: the snap, and its box ringing (cut short: a pod, not a wall box)."""
    return damp(cut("sw_heavy_metal", at, at + 0.24, snap=True), 0.03, 0.045)


def paddle(at):
    """The brake's broad paddle: a toggle on a plate, a size bigger (slowed), its long ring cut short."""
    return damp(pitch(cut("sw_toggle1", at, at + 0.42, snap=True), 0.88), 0.045, 0.06)


def guard(at, seconds):
    """The red guard: a small hinged metal cover (a lighter's lid, slowed to a bigger one, its ting damped)."""
    return damp(pitch(cut("guard_zippo5", at, at + seconds, snap=True), 0.84), 0.16, 0.05)


def starter(body_from, speed):
    """An engine's starter: the solenoid's clack, 1.6 s of a real starter turning an engine that does not
    fire, then the starter let go and spinning down (the recording's own ending)."""
    crank = src("crank_wont")
    t0 = onset(crank, 0.5, 0.1) - 0.004
    first = fade(crank[int(t0 * RATE):int((t0 + 0.36) * RATE)].copy(), 0.002, 0.0)
    body = crank[int(body_from * RATE):int((body_from + 1.33) * RATE)].copy()
    turning = splice(first, body, 0.06)[:int(1.6 * RATE)]
    down = fade(crank[int(9.32 * RATE):int(9.84 * RATE)].copy(), 0.0, 0.06)
    whole = pitch(splice(turning, down, 0.05), speed)
    clack = damp(butter(cut("solenoid_12v", 1.0, 1.1, snap=True), "highpass", 70.0), 0.03, 0.03)
    return mix((clack, 0.0, 0.3), (full(limit(butter(whole, "highpass", 60.0), 7.0)), 0.025, 1.0))


def build():
    out = {}
    # the BATT and ENGINE toggles: two takes each way, so two throws in a row are not one sample
    out["toggle_on"] = [toggle(1.39), toggle(4.23)]
    out["toggle_off"] = [toggle(2.98), toggle(5.60)]
    out["paddle_on"] = [paddle(0.03)]
    out["paddle_off"] = [paddle(0.90)]
    out["guard_up"] = [guard(0.11, 0.27)]
    out["guard_down"] = [guard(2.04, 0.31)]
    # the start button: a big sprung button going in, and coming back 0.2 s later
    out["button"] = [pitch(cut("btn_heavy", 0.10, 0.37, snap=True), 0.9)]
    # the battery bus: a large contactor pulling in, and the cooling fans and gyros winding up behind it
    contactor = cut("relay_large", 1.78, 2.66, fin=0.01, fout=0.08)
    wind_up = swell(cut("fan_1u", 0.05, 2.9, fout=0.3), 0.01, 1.5, 0.55)
    out["power"] = [mix((contactor, 0.0, 1.0), (wind_up, 0.2, 0.3))]
    opening = cut("relay_large", 11.08, 11.86, fin=0.01, fout=0.08)
    wind_down = cut("fan_1u", 6.55, 7.5, fin=0.01, fout=0.2)
    out["down"] = [mix((opening, 0.0, 1.0), (wind_down, 0.12, 0.3))]
    # ... and what is left running with the battery on and the engines dark: the fans, looped
    out["avionics"] = [butter(loop("fan_1u", 3.9, 2.2), "lowpass", 9000.0)]
    # the self-test passing, the turbines proved: an airliner's cabin chime (high, then low)
    out["chime"] = [cut("chime_cabin", 0.0, 2.2, fin=0.001, fout=0.5)]
    # ENGINE: the fuel pumps prime ...
    out["pump"] = [cut("pump_bmw", 0.025, 1.52, fin=0.003, fout=0.12)]
    # ... and the binder strikes: a crackle of sparks, a coil's buzz that settles, mains hum under it
    crackle = swell(cut("arc_elec", 0.02, 0.9), 0.002, 0.06, 0.16)
    buzz = swell(cut("arc_tesla", 0.07, 1.45, fout=0.2), 0.02, 0.3, 0.3)
    hum = swell(cut("hum_60", 0.5, 1.95, fout=0.2), 0.12, 0.5, 0.3)
    out["arc"] = [mix((crackle, 0.0, 1.0), (buzz, 0.015, 0.4), (hum, 0.03, 0.4))]
    # the starters: the same machine each side, a different stretch of it and a hair slower on the right
    out["starter"] = [starter(2.2, 1.0), starter(5.1, 0.965)]
    # an engine catching: a five-litre V8 firing up (its low end), and a truck's first bark (its top)
    whump = swell(cut("start_50", 0.185, 1.75, fout=0.3), 0.004, 0.45, 0.4)
    bark = swell(butter(cut("start_truck", 0.36, 1.5, fout=0.2), "highpass", 350.0), 0.01, 0.2, 0.28)
    out["catch"] = [mix((whump, 0.0, 1.0), (bark, 0.01, 0.3))]
    # the parking brake: a heavy breaker's throw for the clamp, and air
    thunk = damp(pitch(cut("sw_breaker_kyles", 1.60, 2.0, snap=True), 0.8), 0.07, 0.07)
    puff = cut("air_pffft", 1.545, 1.67, fin=0.004, fout=0.04)
    out["clamp"] = [mix((thunk, 0.0, 1.0), (puff, 0.06, 0.45))]
    unlatch = damp(pitch(cut("sw_breaker_kyles", 0.085, 0.47), 0.85), 0.16, 0.07)
    hiss = butter(cut("air_pffft", 0.205, 1.2, fin=0.004, fout=0.3), "lowpass", 9500.0)
    out["release"] = [mix((unlatch, 0.0, 0.8), (hiss, 0.1, 0.7))]
    # a refused control: an interlock relay knocking twice, a buzzer's short answer under the first
    knock = full(damp(butter(cut("solenoid_12v", 1.0, 1.1, snap=True), "highpass", 250.0), 0.03, 0.03))
    bzz = butter(cut("buzzer_bursts", 2.04, 2.2, fin=0.01, fout=0.03), "lowpass", 3000.0)
    out["refuse"] = [mix((knock, 0.0, 1.0), (bzz, 0.01, 0.3), (knock, 0.15, 0.7))]
    return out


# name: [level dB, the window its loudness is judged over, the old sound it stands in for (or its level against one)]
SOUNDS = {
    "toggle_on": [-8.5, 0.05, "click"], "toggle_off": [-8.5, 0.05, "click"],
    "paddle_on": [-11.0, 0.05, "click"], "paddle_off": [-11.0, 0.05, "click"],
    "guard_up": [-5.0, 0.05, "clack"], "guard_down": [-4.0, 0.05, "clack"],
    "button": [-6.0, 0.05, "button"],
    "power": [-8.5, 0.4, "power"], "down": [-15.0, 0.4, "down"], "avionics": [-31.0, 0.4, ("power", -16.0)],
    "chime": [-14.0, 0.4, "chime"],
    "pump": [-6.0, 0.4, ("arc", -6.0)], "arc": [-10.0, 0.4, "arc"],
    # (the starter is 2 dB under a match with the old one, the catch 5 under: recorded in the game's own
    # mix, a matched starter peaked at -1 dB with the engine coughing under it. The catch's weight is all
    # below 500 Hz and the engine's voice is coming up under it. A refusal is 4 dB under a match: knocks,
    # not tones. The WAVs' .import files are set to PCM (compress/mode=0), as the engines' are: the game
    # reads their frames.)
    "starter": [-8.5, 0.4, "starter"], "catch": [-8.5, 0.4, ("starter", 1.0)],
    "clamp": [-6.0, 0.05, "clamp"], "release": [-7.5, 0.4, "release"],
    "refuse": [-4.0, 0.05, "refuse"],
}
LOOPS = ["avionics"]


def main():
    match = Path(sys.argv[sys.argv.index("--match") + 1]) if "--match" in sys.argv else None
    OUT.mkdir(parents=True, exist_ok=True)
    built = build()
    manifest = {"rate": RATE, "sounds": {}}
    for name, takes in built.items():
        level, window, stands_for = SOUNDS[name]
        files, loud = [], []
        for i, y in enumerate(takes):
            y = finish(y, tail=name not in LOOPS)
            f = "%s%s.wav" % (name, "_%d" % i if len(takes) > 1 else "")
            sf.write(str(OUT / f), y, RATE, subtype="PCM_16")
            files.append(f)
            loud.append(loudest(y, window))
        note = ""
        if match:
            old_name, offset = stands_for if isinstance(stands_for, tuple) else (stands_for, 0.0)
            old, rate = sf.read(str(match / (old_name + ".wav")), dtype="float64")
            g = math.gcd(RATE, rate)
            old = signal.resample_poly(old, RATE // g, rate // g)
            old_levels = {"click": -9.0, "clack": -8.0, "button": -7.0, "power": -10.0, "down": -12.0, "chime": -14.0,
                          "arc": -8.0, "starter": -9.0, "clamp": -6.0, "release": -6.0, "refuse": -12.0}
            want = loudest(old, window) + old_levels[old_name] + offset
            note = "   as loud as the old %s%+.0f at %.1f dB" % (old_name, offset, want - float(np.mean(loud)))
        entry = {"files": files, "level_db": level}
        if name in LOOPS:
            entry["loop"] = True
        manifest["sounds"][name] = entry
        print("%-11s %d take(s) %5.2f s  loudest %5.1f  level %5.1f%s" % (name, len(takes), len(takes[0]) / RATE, float(np.mean(loud)), level, note))
    (OUT / "manifest.json").write_text(json.dumps(manifest, indent="\t") + "\n", encoding="utf-8", newline="\n")
    print("Wrote", len(manifest["sounds"]), "sounds to", OUT)


if __name__ == "__main__":
    main()
