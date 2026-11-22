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


def ramp(y, r0, r1, seconds):
    """A machine run up to speed, as a tape would be: played at r0 of its speed at first, reaching r1
    after `seconds` and holding it (pitch and pace together)."""
    up = signal.resample_poly(y, 4, 1)                       # (finer steps for the reading below)
    n = int(len(y) / max(min(r0, r1), 0.05))
    t = np.arange(n) / RATE
    rate = r0 + (r1 - r0) * np.minimum(t / seconds, 1.0)
    at = np.concatenate(([0.0], np.cumsum(rate)[:-1])) * 4.0
    return np.interp(at[at < len(up) - 1], np.arange(len(up)), up)


# The staged start (Luke, after the seventeenth flight: "Replace the two V8 startup sounds with a staged
# supercar style start - Brief pre-starter whine, then starter engage"). One sound an engine, played when
# its start is asked for, laid out on the start-up's own clock (vr/startup_sequence.gd CRANK_S: the engine
# catches 1.6 s after its starter's sound begins, and the catch is the next sound):
#   0.00 .. PRIME_S   the electrics: an ignition's relays, a fuel pump priming, a small motor's whine running up
#   PRIME_S .. 1.6    the starter thrown in (its solenoid, then a high-geared starter spinning a big engine,
#                     the engine's own turning coming up under it)
#   1.6 ..            the starter let go as the engine fires
# engine_audio.gd keeps the engine's own voice still for the same PRIME_S (TUNE.start_prime_s).
PRIME_S = 0.80
CRANK_S = 1.6


def staged_start(speed, whine_from, engage):
    """One engine's start, to the catch. speed: this engine's machinery against the other's (a hair slower
    is lower); whine_from: which stretch of the motor's whir it gets; engage: when its starter goes in."""
    # the electrics: two relays and the fuel pump coming up behind them (a car's ignition switched on) ...
    pump = src("prime_pump")
    p0 = onset(pump, 0.10, 0.05) - 0.004
    prime = fade(pump[int(p0 * RATE):int((p0 + CRANK_S + 0.1) * RATE)].copy(), 0.002, 0.25)
    prime = full(butter(pitch(prime, speed), "highpass", 90.0))
    # ... and the whine: a small electric motor run up to speed, its mains hum taken out, rising for half a
    # second and held; it gives way as the starter loads the bus
    whir = src("whir_dremel")
    w0 = onset(whir, 0.08, 0.05) + whine_from
    whine = butter(butter(whir[int(w0 * RATE):int((w0 + 1.4) * RATE)].copy(), "highpass", 480.0), "lowpass", 9000.0)
    whine = ramp(whine, 0.56 * speed, 1.0 * speed, 0.5)[:int((engage + 0.22) * RATE)]
    t = np.arange(len(whine)) / RATE
    whine = full(whine * np.minimum(t / 0.3, 1.0) ** 1.5 * np.where(t < engage, 1.0, np.exp(-(t - engage) / 0.07)))
    # the starter: its solenoid, then a V10's starter (bright, quick) kept clear of that engine's own lows,
    # and lengthened by a repeat of its steady middle to reach the catch
    m6 = src("start_m6")
    s0 = onset(m6, 0.215, 0.05) - 0.004
    span = CRANK_S - engage + 0.14
    first = m6[int(s0 * RATE):int((s0 + 0.50) * RATE)].copy()
    again = m6[int((s0 + 0.30) * RATE):int((s0 + 0.655) * RATE)].copy()
    spin = butter(splice(fade(first, 0.002, 0.0), again, 0.06), "highpass", 320.0)
    spin = pitch(spin, speed)
    while len(spin) < int(span * RATE):                      # (a slower engine's is a little longer already)
        spin = splice(spin, butter(pitch(again, speed), "highpass", 320.0), 0.06)
    spin = full(limit(fade(spin[:int(span * RATE)], 0.002, 0.13), 5.0))
    # the engine turning over under it: that recording's own compressions, coming up to the catch
    turning = butter(m6[int((s0 + 0.17) * RATE):int((s0 + 0.66) * RATE)].copy(), "lowpass", 260.0)
    turning = full(fade(pitch(turning, speed), 0.12, 0.05))
    turn_at = CRANK_S + 0.03 - len(turning) / RATE
    clack = damp(butter(cut("solenoid_12v", 1.0, 1.1, snap=True), "highpass", 70.0), 0.03, 0.03)
    # (at its top the whine sits 3 to 5 dB under the starter's own stretch, measured: a thing heard before it, not
    # behind it. The starter going in is the tallest thing in it by 10 dB: held 6 dB down, so the rest can be heard.)
    return limit(mix((prime, 0.0, 0.5), (whine, 0.03, 0.62), (clack, engage - 0.012, 0.3), (spin, engage, 1.0), (turning, turn_at, 0.4)), 6.0)


def catch_flare():
    """An engine firing: a Lamborghini's own first second and a half (it fires, flares and comes back toward
    its idle), with a V10 lighting under it for the weight a phone leaves out; gone under the engine's own
    voice by the end."""
    lambo = src("start_lambo")
    f0 = onset(lambo, 1.01, 0.06, db=-20.0) - 0.004
    flare = swell(fade(lambo[int(f0 * RATE):int((f0 + 1.9) * RATE)].copy(), 0.002, 0.5), 0.003, 1.15, 0.5)
    m6 = src("start_m6")
    l0 = onset(m6, 0.215, 0.05) + 0.655
    low = butter(m6[int(l0 * RATE):int((l0 + 1.5) * RATE)].copy(), "lowpass", 210.0)
    low = swell(fade(low, 0.004, 0.3), 0.004, 0.55, 0.4)
    return mix((full(flare), 0.0, 1.0), (full(low), 0.0, 0.5))


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
    # the staged start: the same machinery each side, a hair slower (and so lower) on the right, its starter going
    # in a moment later
    out["starter"] = [staged_start(1.0, 0.0, PRIME_S), staged_start(0.965, 0.0, PRIME_S + 0.04)]
    # ... and the engine catching: it fires, flares and settles
    out["catch"] = [catch_flare()]
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
    # (the old starter was 2 dB under a match with the synthesised one, the old catch 5 under: recorded in the
    # game's own mix, a matched starter peaked at -1 dB with the engine coughing under it. The staged start
    # that replaced them on 2026-11-22 was set against those two by the same measure: see the levels below
    # and tools/audio_src/startup's CREDITS. A refusal is 4 dB under a match: knocks, not tones. The WAVs'
    # .import files are set to PCM (compress/mode=0), as the engines' are: the game reads their frames.)
    # (the staged start, set in the game's own mix against the start it replaced, both recorded with
    # tests/record_startup.gd: its starter's stretch as loud as the old cranking was, -20.5 dB rms, which
    # puts its whine 3 dB under that and 6 dB over the fans; its catch left as loud as the old catch, -18.8.
    # The mix peaks at -5.9 dBFS through the start, where the old one peaked at -5.5.)
    "starter": [-6.5, 0.4, "starter"], "catch": [-8.5, 0.4, ("starter", 1.0)],
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
