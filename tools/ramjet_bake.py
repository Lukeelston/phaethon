"""The ramjet's voice, baked from recordings of real rocket engines.

    python -I tools/ramjet_bake.py

Luke, 2026-11-22: "the ram jet needs its own sound signifier. First gut is saying an actual rocket engine -
just a low screaming roar". Nothing here is synthesised. Two recordings (tools/audio_src/ramjet, credited in
godot/audio/ramjet/CREDITS.md and THIRD_PARTY.md):

  shuttle_launch   Freesound 220127, klangfabrik, "shuttlelaunch.wav", CC0: a re-edit of NASA's own recordings
                   of Space Shuttle launches (the site's high-quality preview). The low body: the stack's roar
                   and crackle a few seconds after lift-off, and the ignition's first thump.
  rs25_*           NASA Stennis Space Center, "RS-25 Engine Test 2025-11-12" (NASA Image and Video Library id
                   SSC_2025-11-12_RS-25_Engine_Test): a Space Shuttle main engine run for 500 s on the Fred
                   Haise Test Stand. NASA's own film, not copyrighted. Three stretches of its sound (the start,
                   50 s of the run, the cut-off), taken from the library's "medium" copy and kept as mono
                   Vorbis. The upper band (the tearing hiss a hydrogen engine makes, which is the scream), the
                   catch as it lights and the fall as it is cut off.

What is written to godot/audio/ramjet, 48 kHz mono 16-bit:
  ramjet_body.wav     a loop: the low roar (110 Hz to 1.5 kHz, its weight at 250 to 900 Hz: where a headset's
                      speakers can play it, and where the game's own mix leaves room under the V8's chest)
  ramjet_scream.wav   a loop: the upper band (0.5 to 8 kHz), one resonance lifted so that it has a note to rise
                      when the game plays it faster with speed
  ramjet_light_N.wav  the light-up: the shuttle's ignition thump, the test engine catching over it, a low swell
  ramjet_out_N.wav    the shut-down: the test engine's own cut-off, slowed as it falls (a tape running down)
  (N: 0 for the left engine, 1 for the right, the same sound a hair slower and so lower, as the staged start's)
  manifest.json       the files, and what was measured of them (levels, the loops' seams)

Each loop's end is folded into its beginning at equal power, so it repeats without a seam; the seam is measured
(the curvature across the join against its surroundings, and the level and brightness either side of it against
how much those wander anywhere else in the loop) and the bake fails if it shows. EngineAudio sets every level:
the loops are written at one rms, the one-shots at one peak. None of this was judged by ear when it was written.
(-I: the sources are downloads. Python is run isolated so nothing beside them can be imported.)
"""
import json
import math
import sys
from pathlib import Path

import numpy as np
import soundfile as sf
from scipy import signal
from scipy.ndimage import maximum_filter1d, uniform_filter1d

RATE = 48000
ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "tools/audio_src/ramjet"
OUT = ROOT / "godot/audio/ramjet"
LOOP_RMS_DB = -18.0      # the loops' level (the engines' loops are baked at the same)
LOOP_PEAK = 0.94         # ... and their tallest crackle held under this
SHOT_PEAK = 0.7          # the one-shots' peak (the start-up's sounds are written at the same)
RIGHT = 0.965            # the right engine's one-shots: this much slower, and lower
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


def piece(name, t0, t1):
    return src(name)[int(t0 * RATE):int(t1 * RATE)].copy()


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


def swell(y, rise, hold, tau):
    """An envelope: up over `rise`, held until `hold`, then falling with time constant tau."""
    t = np.arange(len(y)) / RATE
    return y * np.minimum(t / max(rise, 1e-4), 1.0) * np.where(t < hold, 1.0, np.exp(-(t - hold) / tau))


def pitch(y, ratio):
    """Faster and higher by `ratio` (a tape sped up): under 1 makes a thing bigger and slower."""
    return signal.resample_poly(y, 1000, int(round(1000 * ratio)))


def ramp(y, r0, r1, seconds):
    """A tape whose speed runs from r0 to r1 over `seconds` and holds there (pitch and pace together)."""
    up = signal.resample_poly(y, 4, 1)
    n = int(len(y) / max(min(r0, r1), 0.05))
    t = np.arange(n) / RATE
    rate = r0 + (r1 - r0) * np.minimum(t / seconds, 1.0)
    at = np.concatenate(([0.0], np.cumsum(rate)[:-1])) * 4.0
    return np.interp(at[at < len(up) - 1], np.arange(len(up)), up)


def butter(y, kind, hz, order=2):
    return signal.sosfilt(signal.butter(order, hz, kind, fs=RATE, output="sos"), y)


def peaking(y, hz, db, q):
    """One resonance lifted (or cut): an equaliser's bell at `hz`."""
    a = 10 ** (db / 40)
    w = 2 * math.pi * hz / RATE
    alpha = math.sin(w) / (2 * q)
    b = [1 + alpha * a, -2 * math.cos(w), 1 - alpha * a]
    den = [1 + alpha / a, -2 * math.cos(w), 1 - alpha / a]
    return signal.lfilter(np.array(b) / den[0], np.array(den) / den[0], y)


def mix(*parts):
    """Layers: (samples, start seconds, gain)."""
    n = max(int(at * RATE) + len(y) for y, at, _ in parts)
    out = np.zeros(n)
    for y, at, gain in parts:
        i = int(at * RATE)
        out[i:i + len(y)] += y * gain
    return out


def limit(y, ceiling, attack=0.001, release=0.05):
    """Hold a sound's tallest peaks under `ceiling` (linear): gain rides down just ahead of a peak and comes
    back over `release`. The body of the sound is not touched."""
    n = max(1, int(attack * RATE))
    env = maximum_filter1d(np.abs(y), size=2 * n + 1)
    want = np.minimum(1.0, ceiling / np.maximum(env, 1e-9))
    keep = math.exp(-1.0 / (release * RATE))
    gain = np.empty_like(want)
    cur = 1.0
    for i, g in enumerate(want):
        cur = min(g, 1.0 - (1.0 - cur) * keep)
        gain[i] = cur
    return y * np.minimum(want, np.convolve(gain, np.ones(n) / n, mode="same"))


def rms_db(y):
    return 10 * math.log10(float(np.mean(y * y)) + 1e-20)


def level_out(y, seconds=1.2, strength=0.7, most_db=3.0):
    """Take a loop's slow swells out (a swell that came round every few seconds would give the repeat away):
    its level over `seconds`, wrapped round the loop, is brought `strength` of the way to its mean, by no more
    than most_db. The crackle, which is far quicker, is left alone."""
    power = uniform_filter1d(y * y, size=int(seconds * RATE), mode="wrap")
    db = 10 * np.log10(power / power.mean())
    return y * 10 ** (np.clip(-strength * db, -most_db, most_db) / 20)


def seamless(y, n, fold):
    """`n` samples of y that repeat without a seam: what follows them is folded into their beginning at equal
    power, so the last sample runs straight on into the first."""
    k = np.linspace(0, math.pi / 2, fold)
    out = y[:n].copy()
    out[:fold] = y[:fold] * np.sin(k) + y[n:n + fold] * np.cos(k)
    return out


def seam_ratio(x):
    """tools/engine_bake.py's measure: the curvature across the loop point against the largest in the 1,024
    samples either side. Under 1: as smooth as its surroundings."""
    k = 1024
    w = np.concatenate([x[-(k + 2):], x[:k + 2]])
    d2 = np.abs(np.diff(w, 2))
    seam = d2[k:k + 2].max()
    return float(seam / (np.concatenate([d2[:k - 2], d2[k + 4:]]).max() + 1e-12))


def centroid(y):
    spec = np.abs(np.fft.rfft(y * np.hanning(len(y)))) ** 2
    f = np.fft.rfftfreq(len(y), 1 / RATE)
    return float(np.sum(f * spec) / np.sum(spec))


def seam_steps(x, window=0.25):
    """Across the join, and everywhere else: how far the level (dB) and the brightness (cents of spectral
    centroid) step from one `window` to the next. -> (level step at the seam, the 95th percentile of the level
    steps elsewhere, brightness step at the seam, the 95th percentile elsewhere)."""
    n = int(window * RATE)
    wrapped = np.concatenate([x, x[:2 * n]])
    hops = range(0, len(x), n // 2)
    lev = np.array([rms_db(wrapped[i:i + n]) for i in hops])
    cen = np.array([1200 * math.log2(centroid(wrapped[i:i + n])) for i in hops])
    dl, dc = np.abs(lev[2:] - lev[:-2]), np.abs(cen[2:] - cen[:-2])      # window i against the one that follows it
    seam_l = abs(rms_db(x[-n:]) - rms_db(x[:n]))
    seam_c = abs(1200 * math.log2(centroid(x[-n:]) / centroid(x[:n])))
    return seam_l, float(np.percentile(dl, 95)), seam_c, float(np.percentile(dc, 95))


def band_db(y, lo, hi):
    b = signal.sosfilt(signal.butter(4, [lo, hi], "bandpass", fs=RATE, output="sos"), y)
    return rms_db(b)


# ---- the sounds ----

BODY_S, SCREAM_S, FOLD_S = 9.0, 7.0, 0.6      # (lengths that share no small multiple: the pair repeats after 63 s)


def body_loop():
    """The low roar: the shuttle's stack 24 s into the re-edit, where it is loud, steady and still crackles.
    Its bottom is taken off (under 110 Hz a headset cannot play it, and from there to 250 Hz the game's V8 and
    second engine are 10 dB over anything put beside them: measured, the first cut of this loop, weighted at
    180 Hz, changed the recorded mix under 400 Hz by 0.3 dB), its weight lifted at 420 Hz, where the mix has
    room, and everything over 1.5 kHz left to the scream's loop."""
    y = piece("shuttle_launch", 23.0, 23.0 + 1.4 + BODY_S + FOLD_S + 0.5)
    y = butter(butter(y, "highpass", 110.0), "lowpass", 1500.0)
    y = peaking(y, 420.0, 5.0, 0.7)
    y = y[int(1.4 * RATE):]
    y = seamless(y, int(BODY_S * RATE), int(FOLD_S * RATE))
    return level_out(y)


def scream_loop():
    """The upper band: the test engine at full power, from 500 Hz up. One resonance is lifted (6 dB at 2.3 kHz)
    so the band has a note: played faster as the craft gains speed, that note climbs."""
    y = piece("rs25_steady", 4.0, 4.0 + 1.0 + SCREAM_S + FOLD_S + 0.5)
    y = butter(butter(y, "highpass", 500.0), "lowpass", 8000.0)
    y = peaking(y, 2300.0, 6.0, 2.5)
    y = y[int(1.0 * RATE):]
    y = seamless(y, int(SCREAM_S * RATE), int(FOLD_S * RATE))
    return level_out(y)


def light_up(speed):
    """The catch, 1.9 s: the shuttle's ignition thump (taken from where it is already 10 dB under its top, so it
    lands hard), the test engine catching over it (its own start, from where it is already climbing), and a low
    swell that hands over to the loops."""
    bang = full(fade(piece("shuttle_launch", 0.345, 1.05), 0.003, 0.3))
    catch = butter(piece("rs25_start", 7.30, 9.1), "highpass", 400.0)
    catch = full(swell(fade(catch, 0.01, 0.4), 0.02, 0.75, 0.35))
    low = butter(piece("shuttle_launch", 1.45, 3.3), "lowpass", 350.0)
    low = full(swell(fade(low, 0.02, 0.5), 0.12, 0.5, 0.4))
    y = mix((bang, 0.0, 1.0), (catch, 0.03, 0.8), (low, 0.07, 0.7))
    return pitch(y, speed) if speed != 1.0 else y


def shut_down(speed):
    """The fall, 1.5 s: the test engine's own cut-off (15 dB in a second), run down as a tape runs down (to 0.6 of
    its speed in 0.8 s) so its note falls as it dies, over the low thump the engine gave as it was throttled back.
    It begins at its top: the game starts it as the loops begin to fall."""
    cut = piece("rs25_stop", 17.72, 19.45)
    cut = ramp(fade(cut, 0.003, 0.3), 1.0, 0.6, 0.8)
    cut = full(swell(cut, 0.003, 0.10, 0.45))
    thump = butter(piece("rs25_stop", 12.18, 13.0), "lowpass", 500.0)
    thump = full(swell(fade(thump, 0.005, 0.3), 0.01, 0.08, 0.2))
    # ... and the low roar running down with it (the body loop's own stretch of the shuttle), so the fall has weight
    low = butter(butter(piece("shuttle_launch", 30.0, 31.4), "highpass", 60.0), "lowpass", 600.0)
    low = full(swell(ramp(fade(low, 0.003, 0.3), 1.0, 0.6, 0.8), 0.003, 0.08, 0.3))
    y = fade(mix((cut, 0.0, 1.0), (thump, 0.0, 0.5), (low, 0.0, 0.8))[:int(1.5 * RATE)], 0.001, 0.25)
    return pitch(y, speed) if speed != 1.0 else y


def finish_loop(y):
    """A loop at its level, its tallest crackle held under LOOP_PEAK, the join made good again afterwards."""
    y = y - y.mean()
    y = y * (10 ** (LOOP_RMS_DB / 20) / math.sqrt(float(np.mean(y * y))))
    n = len(y)
    y = limit(np.concatenate([y[-RATE:], y, y[:RATE]]), LOOP_PEAK)[RATE:RATE + n]      # (limited as a loop: wrapped)
    return y


def finish_shot(y):
    y = butter(y - y.mean(), "highpass", 30.0)
    y = fade(y, 0.001, 0.02)
    return y * (SHOT_PEAK / np.abs(y).max())


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    fails = 0
    manifest = {"rate": RATE, "rms_db": LOOP_RMS_DB, "layers": {}, "oneshots": {}}
    for layer, name, make in (("ramjet", "ramjet_body.wav", body_loop), ("ramscream", "ramjet_scream.wav", scream_loop)):
        y = finish_loop(make())
        sf.write(str(OUT / name), y, RATE, subtype="PCM_16")
        seam = seam_ratio(y)
        step_l, usual_l, step_c, usual_c = seam_steps(y)
        swing = [rms_db(y[i:i + RATE]) for i in range(0, len(y) - RATE + 1, RATE // 2)]
        ok = seam < 1.0 and step_l <= max(usual_l, 1.0) and step_c <= max(usual_c, 60.0) and float(np.abs(y).max()) < 1.0
        fails += 0 if ok else 1
        print("  %s %-18s %.1f s  rms %.1f dB  peak %.1f dB  seam %.2f; across it the level steps %.1f dB (elsewhere up to %.1f), "
              "the brightness %.0f cents (elsewhere up to %.0f); second to second the level holds within %.1f dB" % (
                  "ok  " if ok else "FAIL", name, len(y) / RATE, rms_db(y), 20 * math.log10(np.abs(y).max()), seam, step_l, usual_l, step_c, usual_c,
                  max(swing) - min(swing)))
        print("       bands: 60-250 Hz %.1f dB, 250-1k %.1f, 1k-2k %.1f, 2k-4k %.1f, 4k-8k %.1f; centroid %.0f Hz" % (
            band_db(y, 60, 250), band_db(y, 250, 1000), band_db(y, 1000, 2000), band_db(y, 2000, 4000), band_db(y, 4000, 8000), centroid(y)))
        manifest["layers"][layer] = {"unit": "speed", "bands": [{"file": name, "at": 1.0}], "seconds": round(len(y) / RATE, 3),
                                     "seam": round(seam, 3), "seam_level_db": round(step_l, 2), "seam_cents": round(step_c, 1),
                                     "peak_db": round(20 * math.log10(np.abs(y).max()), 2), "centroid_hz": round(centroid(y))}
    for shot, make in (("light", light_up), ("out", shut_down)):
        files = []
        for k, speed in enumerate((1.0, RIGHT)):
            y = finish_shot(make(speed))
            name = "ramjet_%s_%d.wav" % (shot, k)
            sf.write(str(OUT / name), y, RATE, subtype="PCM_16")
            files.append(name)
            env = np.sqrt(uniform_filter1d(y * y, size=int(0.02 * RATE)))
            top = int(np.argmax(env))
            first = int(np.argmax(env > env.max() * 10 ** (-20 / 20)))
            gone = len(env) - int(np.argmax(env[::-1] > env.max() * 10 ** (-20 / 20)))
            print("  ok   %-18s %.2f s  rms %.1f dB  from 20 dB under its top to its top in %.0f ms; back 20 dB under it at %.2f s; centroid %.0f Hz" % (
                name, len(y) / RATE, rms_db(y), 1000.0 * (top - first) / RATE, gone / RATE, centroid(y)))
        manifest["oneshots"][shot] = files
    (OUT / "manifest.json").write_text(json.dumps(manifest, indent="\t") + "\n", encoding="utf-8", newline="\n")
    print("RAMJET BAKE", "PASS" if fails == 0 else "FAIL (%d)" % fails, "->", OUT)
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()
