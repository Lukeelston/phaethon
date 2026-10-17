"""Engine bake: turns piano samples into engine loops for Godot's EngineAudio.

There are no oscillators here. Every sound starts as a Salamander Grand Piano recording:
  v8, v12   Combustion pulses. Each firing event drops a short grain of a piano hammer strike
            into an exhaust bank, timed by a real firing order. A cross-plane V8 gives each
            bank uneven gaps (270/180/90/180 degrees), which is where the burble comes from.
            A 60-degree V12 fires evenly every 60 degrees, which is where the scream comes from.
            Then pipe resonance (damped comb) and soft clip. The muffler is EngineAudio's,
            a fixed low-pass on the layer's bus.
  turbine   Whine is a granular freeze of high piano sustains, pitched to blade-pass,
            compressor and fan tones.
  roar      A dense cloud of hammer-release (damper) noise. EngineAudio opens a low-pass on it
            with the spool.
  burner    A dense cloud of low hammer strikes (rumble and crackle) over the roar.

Every loop is periodic by construction: grains are placed circularly and filters run to
steady state. So it loops without a seam, and EngineAudio can pitch-shift it freely.
Seeded, so a re-bake is byte-identical.

One master per layer, played at the engine's speed. An earlier design baked a loop per RPM
band and crossfaded neighbours, and a ramp "stepped through selected tones": each band had its
own timbre, so brightness pulsed at every band (measured 109-198 cents) and blends lost their
top end. Now each layer is a single performance, pitched with RPM the way a real engine's
pulses are fixed in crank angle (rpm-tied timbre comes from that, plus fixed-frequency filters
in EngineAudio). Pitching up 15x would alias, so each master is stored as a few anti-alias
levels: zero-phase low-passed copies of the same samples, an octave of pitch apart. They stay
sample-aligned, so crossfading them only fades the top octave in and out.

  python tools/engine_bake.py                       # bake into godot/audio/engines
  python tools/engine_bake.py --piano DIR --out DIR

Salamander Grand Piano V3 by Alexander Holm, CC BY 3.0 (credited in the output's CREDITS.md).
"""
import argparse
import json
import os

import numpy as np
import soundfile as sf
from scipy import signal

SR = 44100
DEFAULT_PIANO = r"C:\Users\Luke\Music\Instruments\SalamanderGrandPiano-SFZ+FLAC-V3+20200602\samples"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_OUT = os.path.join(ROOT, "godot", "audio", "engines")
TARGET_RMS_DB = -18.0

NAMES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
SAMPLED = list(range(21, 109, 3))   # A0..C8, sampled in minor thirds


def note_name(m):
    return "%s%d" % (NAMES[m % 12], m // 12 - 1)


def hz(m):
    return 440.0 * 2.0 ** ((m - 69) / 12.0)


def nearest_sampled(f):
    return min(SAMPLED, key=lambda m: abs(np.log2(hz(m) / f)))


class Piano:
    """Loads Salamander FLACs as mono float at SR, cached."""

    def __init__(self, root):
        self.root = root
        self.cache = {}

    def _load(self, name):
        if name not in self.cache:
            x, sr = sf.read(os.path.join(self.root, name + ".flac"), dtype="float64", always_2d=True)
            x = x.mean(axis=1)
            if sr != SR:
                g = np.gcd(SR, sr)
                x = signal.resample_poly(x, SR // g, sr // g)
            self.cache[name] = x
        return self.cache[name]

    def note(self, midi, vel):
        return self._load("%sv%d" % (note_name(midi), vel))

    def release(self, midi):
        return self._load("rel%d" % (midi - 20))   # rel1 = A0 = MIDI 21


# ---------------------------------------------------------------- DSP helpers

def onset(x, thr=0.05):
    a = np.abs(x)
    return max(0, int(np.argmax(a > thr * a.max())) - int(0.002 * SR))


def butter(x, fc, kind, order=2):
    sos = signal.butter(order, fc, kind, fs=SR, output="sos")
    return signal.sosfilt(sos, x)


def circular(fn, x):
    """Run a filter to steady state on a loop: filter three copies, keep the last."""
    n = len(x)
    return fn(np.tile(x, 3))[2 * n:]


def resample(g, ratio):
    """Play grain g at `ratio` times speed (ratio > 1 raises pitch, shortens)."""
    if abs(ratio - 1.0) < 1e-6:
        return g
    t = np.arange(0.0, len(g) - 1, ratio)
    return np.interp(t, np.arange(len(g)), g)


def place(buf, g, pos, gain=1.0):
    """Add grain g into loop buf at fractional sample position pos, wrapping around the end."""
    n = len(buf)
    i0 = int(np.floor(pos))
    frac = pos - i0
    k = np.arange(len(g) + 1)
    gs = np.interp(k - frac, np.arange(len(g)), g, left=0.0, right=0.0) * gain
    i0 %= n
    first = min(len(gs), n - i0)
    buf[i0:i0 + first] += gs[:first]
    rest = gs[first:]
    while len(rest):   # a grain longer than the loop wraps more than once
        m = min(len(rest), n)
        buf[:m] += rest[:m]
        rest = rest[m:]


def pipe(x, delay_s, g):
    """Exhaust pipe resonance: comb with a low-pass in the feedback (damped, not metallic)."""
    d = max(2, int(round(delay_s * SR)))
    a = np.zeros(d + 2)
    a[0] = 1.0
    a[d] = -g / 2
    a[d + 1] = -g / 2
    return circular(lambda v: signal.lfilter([1.0], a, v), x)


def soft_clip(x, drive):
    x = x / (np.sqrt(np.mean(x * x)) + 1e-12) * 0.25   # drive is relative to a fixed level
    return np.tanh(drive * x)


def hann(n):
    return 0.5 - 0.5 * np.cos(2 * np.pi * np.arange(n) / max(1, n - 1))


def normalize(x, rms_db=TARGET_RMS_DB):
    x = x - x.mean()
    x *= 10 ** (rms_db / 20) / (np.sqrt(np.mean(x * x)) + 1e-12)
    peak = np.max(np.abs(x))
    if peak > 0.97:   # soft-limit only the peaks
        x = np.where(np.abs(x) > 0.8, np.sign(x) * (0.8 + 0.17 * np.tanh((np.abs(x) - 0.8) / 0.17)), x)
    return x


# ---------------------------------------------------------------- grains

def strike(piano, midi, vel, length, tau, lp):
    """A combustion pulse: the first `length` s of a hammer strike, decaying with time constant tau."""
    x = piano.note(midi, vel)
    i = onset(x)
    g = x[i:i + int(length * SR)].copy()
    t = np.arange(len(g)) / SR
    env = np.exp(-t / tau)
    ramp = int(0.0005 * SR)
    env[:ramp] *= 0.5 - 0.5 * np.cos(np.pi * np.arange(ramp) / ramp)
    g = butter(g * env, lp, "lowpass")
    return g / np.max(np.abs(g))


def damper(piano, midi, length):
    """A mechanical click: the start of a key's hammer-release noise."""
    x = piano.release(midi)
    i = onset(x, 0.1)
    n = int(length * SR)
    g = x[i:i + n] * hann(2 * n)[n:]   # falling half of a Hann window
    return g / (np.max(np.abs(g)) + 1e-12)


# ---------------------------------------------------------------- engines

V8 = {
    "name": "v8", "cyl": 8,
    # GM cross-plane firing order 1-8-4-3-6-5-7-2, one event every 90 degrees of the 720-degree
    # cycle. Odd cylinders on bank A, even on bank B, so each bank hears 270/180/90/180: the lope.
    "events": [(0, 0), (90, 1), (180, 1), (270, 0), (360, 1), (450, 0), (540, 0), (630, 1)],
    # One piano key and velocity layer per bank. Mixing keys or layers inside a bank makes every
    # pulse a different tone and the train stops being heard as a pitch (measured: corr < 0.3).
    # Life comes from per-event gain and crank-angle jitter instead. The burble is set by
    # bank_gain: a louder bank A leaves the per-bank 270/180/90/180 rhythm audible.
    "bank_notes": [21, 21], "bank_vels": [16, 16], "bank_gain": [1.0, 0.6], "grain_s": 0.09, "tau": 0.016, "grain_lp": 1400,
    "click": 0.18, "pipes": [(0.0051, 0.35), (0.0055, 0.35)], "drive": 2.4,
    "jitter_deg": 1.4, "gain_sd": 0.10, "cyl_sd": 0.07,
    # The master runs at rate_at rpm, its hammer grains slowed to grain_speed (a fat idle thud
    # that shortens with RPM like a real crank-angle pulse). EngineAudio plays it up to p_max.
    "rate_at": 800, "grain_speed": 0.6, "p_max": 12.0,
}
V12 = {
    "name": "v12", "cyl": 12,
    # 60-degree V12: even firing every 60 degrees, alternating banks, so each bank is an even 120.
    "events": [(60 * k, k % 2) for k in range(12)],
    # Matched banks and pipes: an even-firing V12 with a symmetric exhaust is one smooth pitch.
    "bank_notes": [36, 36], "bank_vels": [16, 16], "bank_gain": [1.0, 1.0], "grain_s": 0.04, "tau": 0.0055, "grain_lp": 4200,
    "click": 0.10, "pipes": [(0.0031, 0.35), (0.0031, 0.35)], "drive": 1.7,
    "jitter_deg": 0.6, "gain_sd": 0.06, "cyl_sd": 0.05,
    "rate_at": 1000, "grain_speed": 0.7, "p_max": 15.5,
}
# Engine cycles in each piston master. Pitched up 12x, a 48-cycle loop still only repeats every
# 0.6 s, so its per-pulse variation never settles into an audible pattern.
N_CYC = 48
# Anti-alias levels sit an octave of pitch apart; level j plays alone at pitch 2^j.
MIP = 2.0
# Gate: neighbouring levels are copies of one master, so they must correlate at least this well,
# or a crossfade between them would be a timbre change again.
MIN_MIP_RHO = 0.9
# Gate: blended with EngineAudio's crossfade law, rendered at the pitch they play, every level
# crossfade holds the level within this many dB at 25, 50 and 75% of the way across.
MAX_XFADE_DB = 1.0
# Gate: at least half of every piston master's energy sits on firing harmonics (cyl per 720-degree
# cycle), so the ear hears the firing pitch and not a pipe drone or the lope.
MIN_FIRE = 0.5


def bake_piston(piano, spec, n_cyc, rng):
    """The layer's master: n_cyc engine cycles at spec['rate_at'] rpm. Returns (loop, true rpm)."""
    cycle = 120.0 / spec["rate_at"]           # one 720-degree cycle (two revolutions), s
    n = int(round(n_cyc * cycle * SR))
    cyc = n / n_cyc                           # samples per cycle (fractional is fine)
    rpm_true = 120.0 * SR / cyc
    speed = spec["grain_speed"]
    pools = [[resample(strike(piano, m, v, spec["grain_s"], spec["tau"], spec["grain_lp"]), speed)]
             for m, v in zip(spec["bank_notes"], spec["bank_vels"])]
    clicks = [resample(damper(piano, m, 0.012), speed) for m in spec["bank_notes"]]
    cyl_gain = 1.0 + spec["cyl_sd"] * rng.standard_normal(len(spec["events"]))
    gain_sd = spec["gain_sd"]
    banks = [np.zeros(n), np.zeros(n)]
    jitter = spec["jitter_deg"] / 720.0 * cyc
    for c in range(n_cyc):
        for k, (deg, bank) in enumerate(spec["events"]):
            pos = (c + deg / 720.0) * cyc + jitter * rng.standard_normal()
            pool = pools[bank]
            g = pool[rng.integers(len(pool))]
            g = resample(g, 1.0 + 0.008 * rng.standard_normal())
            gain = cyl_gain[k] * float(np.exp(gain_sd * rng.standard_normal()))
            place(banks[bank], g, pos, gain)
            place(banks[bank], clicks[bank], pos, gain * spec["click"])
    out = np.zeros(n)
    # bank levels apply after the clip (which normalizes)
    for b, (delay, fb), level in zip(banks, spec["pipes"], spec["bank_gain"]):
        out += level * soft_clip(pipe(b, delay, fb), spec["drive"])
    out = circular(lambda v: butter(v, 30, "highpass"), out)
    return normalize(out), rpm_true


def bandlimit(x, fc):
    """Zero-phase, circular low-pass: a raised-cosine taper from fc/2 up to fc."""
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1.0 / SR)
    g = np.clip((fc - f) / (0.5 * fc), 0.0, 1.0)
    return np.fft.irfft(X * (0.5 - 0.5 * np.cos(np.pi * g)), len(x))


def mip_levels(x, p_max):
    """Anti-alias copies of one loop. Level j plays alone at pitch 2^j and shares the octave up
    to 2^(j+1) with level j+1, so it keeps only what stays under ~20 kHz up there. Zero-phase
    and circular (FFT), so every level is sample-aligned with the master and seamless."""
    count = 1
    while MIP ** (count - 1) < p_max:
        count += 1
    return [bandlimit(x, 20000.0 / min(MIP ** (j + 1), p_max)) for j in range(count)]


def freeze(piano, target_hz, vel, n, rng, grain_s=0.08, hop_s=0.02):
    """Granular freeze of a piano sustain at target_hz: a steady, slightly shimmering tone."""
    m = nearest_sampled(target_hz)
    x = piano.note(m, vel)
    i = onset(x)
    src = x[i + int(0.12 * SR): i + int(0.9 * SR)]
    # flatten the piano's decay so every grain is equally loud (zero-phase, so no startup dip)
    env = signal.sosfiltfilt(signal.butter(1, 6, "lowpass", fs=SR, output="sos"), src * src)
    src = src / np.sqrt(env.clip(1e-12))
    ratio = target_hz / hz(m)
    gl = int(grain_s * SR)
    w = hann(gl)
    buf = np.zeros(n)
    hop = hop_s * SR
    for j in range(int(np.ceil(n / hop))):
        start = rng.integers(0, len(src) - int(gl * ratio) - 2)
        g = resample(src[start:start + int(gl * ratio) + 2], ratio)[:gl]
        place(buf, g * w[:len(g)], j * hop)
    return buf / (np.sqrt(np.mean(buf * buf)) + 1e-12)


def cloud(grains, n, density, rng, ratio_range, gain_sd):
    """Granular cloud: grains scattered at random through the loop (Poisson, `density` per second)."""
    buf = np.zeros(n)
    for _ in range(int(density * n / SR)):
        g = grains[rng.integers(len(grains))]
        g = resample(g, float(np.exp(rng.uniform(*np.log(ratio_range)))))
        place(buf, g, rng.uniform(0, n), float(np.exp(gain_sd * rng.standard_normal())))
    return buf / (np.sqrt(np.mean(buf * buf)) + 1e-12)


def release_grains(piano, length_s, count):
    """Short windowed slices of hammer-release noise from across the keyboard."""
    out = []
    gl = int(length_s * SR)
    for m in np.linspace(21, 108, count).astype(int):
        x = piano.release(int(m))
        i = onset(x, 0.1)
        for k in range(3):
            seg = x[i + k * gl // 2: i + k * gl // 2 + gl]
            if len(seg) == gl:
                out.append(seg * hann(gl) / (np.max(np.abs(seg)) + 1e-12))
    return out


TURBINE = {
    "name": "turbine",
    # spool n: 0.25 idle, 1.0 full lever, ~1.2 ramjet. Blade-pass whine at 2400 n Hz,
    # a compressor tone at 0.62x and a fan tone at 1/7.3x of it. The master is the idle whine.
    "rate_at": 0.25, "blade_hz": 2400.0, "p_max": 5.0,
}


def bake_whine(piano, loop_s, rng):
    """The turbine master: the idle whine. Pitched with the spool, so it can't step between
    tones; the roar is its own loop, filtered with the spool in EngineAudio."""
    n = int(loop_s * SR)
    f1 = TURBINE["blade_hz"] * TURBINE["rate_at"]
    whine = freeze(piano, f1, 8, n, rng)
    comp = freeze(piano, f1 * 0.62, 9, n, rng)
    fan = freeze(piano, f1 / 7.3, 11, n, rng, grain_s=0.12, hop_s=0.03)
    return normalize(0.55 * whine + 0.35 * comp + 0.45 * fan)


def bake_burner(piano, loop_s, roar_bed, rng):
    n = int(loop_s * SR)
    thumps = [strike(piano, m, v, 0.07, 0.012, 900) for m in (21, 24, 27, 30, 33) for v in (12, 16)]
    rumble = cloud(thumps, n, 260, rng, (0.7, 1.3), 0.5)
    roar = circular(lambda v: butter(v, 1800, "lowpass"), roar_bed[:n])
    roar /= np.sqrt(np.mean(roar * roar)) + 1e-12
    out = soft_clip(0.8 * rumble + 0.7 * roar, 2.0)
    out = circular(lambda v: butter(butter(v, 2600, "lowpass"), 30, "highpass"), out)
    return normalize(out)


# ---------------------------------------------------------------- checks

def harmonic_share(x, n_cyc, per_cycle, lo=20.0, hi=5000.0):
    """Share of the loop's energy (lo..hi Hz) sitting exactly on the harmonics of a frequency
    that repeats `per_cycle` times per engine cycle. A loop holds a whole number of cycles, so
    those harmonics land exactly on FFT bins: no window, no estimator bias.
    per_cycle = 1: the whole 720-degree pattern (V8 lope included); cyl: the firing pitch."""
    p = np.abs(np.fft.rfft(x)) ** 2
    k = np.arange(len(p))
    f = k * SR / len(x)
    band = (f >= lo) & (f <= hi)
    on = band & (k % (n_cyc * per_cycle) == 0)
    return float(p[on].sum() / p[band].sum())


def line_hz(x, f_expect, span=0.15):
    """Strongest spectral line within +-span of f_expect."""
    spec = np.abs(np.fft.rfft(x * np.hanning(len(x))))
    f = np.fft.rfftfreq(len(x), 1.0 / SR)
    sel = (f > f_expect * (1 - span)) & (f < f_expect * (1 + span))
    return float(f[sel][np.argmax(spec[sel])])


def render(x, ratio, n, start=0.0):
    """What EngineAudio plays: loop x from source sample `start`, at `ratio` speed, for n samples."""
    pos = (start + np.arange(n) * ratio) % len(x)
    return np.interp(pos, np.arange(len(x)), x, period=len(x))


def xfade_gains(t, rho):
    """EngineAudio's crossfade law: linear shapes, normalized so two signals correlated rho keep
    constant power. rho 0 is equal power, rho 1 is a plain linear crossfade."""
    a, b = 1.0 - t, t
    g = 1.0 / np.sqrt(a * a + b * b + 2.0 * rho * a * b)
    return a * g, b * g


def xfade_level_db(lo, hi, pitch, rho, t):
    """Level of the blend t of the way from band lo to band hi, both played at `pitch` from the
    same position (they share a timebase), relative to the bands' own level."""
    n = SR // 2
    a, c = render(lo, pitch, n), render(hi, pitch, n)
    wa, wb = xfade_gains(t, rho)
    mix = wa * a + wb * c
    return 10 * np.log10(np.mean(mix * mix) / (0.5 * (np.mean(a * a) + np.mean(c * c))))


def seam_ratio(x):
    """Curvature across the loop point relative to the largest curvature in the 1024 samples
    (23 ms) on either side. A click spikes the second difference far above its surroundings; a
    continuous seam doesn't, and 23 ms holds a few real pulse onsets to compare a pulse that
    lands on the seam against. (Comparing the raw jump to the loop's step distribution misfires
    on a nearly pure tone, where every step is large.) Below 1: as smooth as its surroundings."""
    k = 1024
    w = np.concatenate([x[-(k + 2):], x[:k + 2]])
    d2 = np.abs(np.diff(w, 2))
    seam = d2[k:k + 2].max()                   # the two second differences that span the join
    return float(seam / (np.concatenate([d2[:k - 2], d2[k + 4:]]).max() + 1e-12))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--piano", default=DEFAULT_PIANO, help="Salamander samples/ folder")
    ap.add_argument("--out", default=DEFAULT_OUT)
    ap.add_argument("--seed", type=int, default=1337)
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)
    piano = Piano(args.piano)
    rng = np.random.default_rng(args.seed)
    manifest = {"sr": SR, "rms_db": TARGET_RMS_DB, "layers": {}}
    fails = 0

    def write(name, x):
        sf.write(os.path.join(args.out, name), x.astype(np.float32), SR, subtype="PCM_16")

    def write_levels(name, unit, master, rate_at, p_max, extra, fc=None):
        """Write a master's anti-alias levels (or, with fc, one level band-limited to fc) and gate
        their crossfades. Returns the fail count."""
        bad = 0
        levels = mip_levels(master, p_max) if fc is None else [bandlimit(master, fc)]
        bands = []
        for j, x in enumerate(levels):
            fname = "%s_mip%d.wav" % (name, j)
            write(fname, x)
            seam = seam_ratio(x)
            bad += 0 if seam < 1 else 1
            bands.append({"file": fname, "at": round(rate_at * MIP ** j, 4)})
            if seam >= 1:
                print("  FAIL %s seam %.2f" % (fname, seam))
        for j in range(len(levels) - 1):
            a, b = levels[j], levels[j + 1]
            rho = float(np.dot(a, b) / (np.linalg.norm(a) * np.linalg.norm(b)))
            bands[j]["rho_next"] = round(rho, 4)
            p_lo, p_hi = MIP ** j, MIP ** (j + 1)
            lv = [xfade_level_db(a, b, min(p_lo ** (1 - t) * p_hi ** t, p_max), rho, t) for t in (0.25, 0.5, 0.75)]
            ok = rho >= MIN_MIP_RHO and max(abs(v) for v in lv) <= MAX_XFADE_DB
            bad += 0 if ok else 1
            print("  %s %s level %d|%d (pitch %gx|%gx)  correlation %.3f  crossfade %s dB" % (
                "ok  " if ok else "FAIL", name, j, j + 1, p_lo, p_hi, rho, " ".join("%+.1f" % v for v in lv)))
        manifest["layers"][name] = dict(unit=unit, sync=True, rate_at=round(rate_at, 4), bands=bands, **extra)
        return bad

    for spec in (V8, V12):
        master, rpm_true = bake_piston(piano, spec, N_CYC, rng)
        cyc = harmonic_share(master, N_CYC, 1)
        fire = harmonic_share(master, N_CYC, spec["cyl"])
        ok = fire >= MIN_FIRE and seam_ratio(master) < 1
        fails += 0 if ok else 1
        print("  %s %s master  %.1f rpm, %.2f s  on cycle harmonics %3.0f%%, on firing harmonics %3.0f%%" % (
            "ok  " if ok else "FAIL", spec["name"], rpm_true, len(master) / SR, 100 * cyc, 100 * fire))
        fails += write_levels(spec["name"], "rpm", master, rpm_true, spec["p_max"], {"cyl": spec["cyl"]})

    whine = bake_whine(piano, 6.0, rng)
    f1 = TURBINE["blade_hz"] * TURBINE["rate_at"]
    got = line_hz(whine, f1)
    ok = abs(got - f1) / f1 < 0.03 and seam_ratio(whine) < 1   # piano stretch tuning: a few cents off
    fails += 0 if ok else 1
    print("  %s turbine master  blade-pass %.0f Hz, line at %.0f" % ("ok  " if ok else "FAIL", f1, got))
    # One level, band-limited to what survives the top pitch (20 kHz / 5 = 4 kHz at idle). The
    # whine is tonal and unmuffled, so anti-alias levels fading its top octave in and out pumped
    # its brightness once per octave of spool (measured 73 cents); one level can't pump.
    fails += write_levels("turbine", "spool", whine, TURBINE["rate_at"], 1.0, {"blade_hz": TURBINE["blade_hz"]},
                          fc=20000.0 / TURBINE["p_max"])

    roar_bed = cloud(release_grains(piano, 0.03, 24), int(3.0 * SR), 3000, rng, (0.7, 1.4), 0.4)
    roar = normalize(circular(lambda v: butter(v, 40, "highpass"), roar_bed))
    write("roar.wav", roar)
    seam = seam_ratio(roar)
    fails += 0 if seam < 1 else 1
    print("  %s roar.wav       seam %.2f" % ("ok  " if seam < 1 else "FAIL", seam))
    manifest["layers"]["roar"] = {"unit": "spool", "bands": [{"file": "roar.wav", "at": 1.0}]}

    x = bake_burner(piano, 3.0, roar_bed, rng)
    write("burner.wav", x)
    seam = seam_ratio(x)
    fails += 0 if seam < 1 else 1
    print("  %s %-14s seam %.2f" % ("ok  " if seam < 1 else "FAIL", "burner.wav", seam))
    manifest["layers"]["burner"] = {"unit": "spool", "bands": [{"file": "burner.wav", "at": 1.0}]}

    with open(os.path.join(args.out, "manifest.json"), "w") as f:
        json.dump(manifest, f, indent=1)
    used = {b["file"] for layer in manifest["layers"].values() for b in layer["bands"]}
    for name in os.listdir(args.out):   # loops from an older layout of this tool's own output
        if name.endswith(".wav") and name not in used:
            os.remove(os.path.join(args.out, name))
    with open(os.path.join(args.out, "CREDITS.md"), "w") as f:
        f.write("# Engine loops\n\nBaked by `tools/engine_bake.py` from the **Salamander Grand Piano V3** "
                "(Yamaha C5) by Alexander Holm, licensed CC BY 3.0 "
                "(https://creativecommons.org/licenses/by/3.0/), via the FreePats SFZ+FLAC edition. "
                "Every engine sound here is resampled, granulated and filtered piano: hammer strikes "
                "become combustion pulses, sustains become turbine whine, damper noise becomes roar.\n")
    print("BAKE", "PASS" if fails == 0 else "FAIL (%d)" % fails, "->", args.out)
    raise SystemExit(1 if fails else 0)


if __name__ == "__main__":
    main()
