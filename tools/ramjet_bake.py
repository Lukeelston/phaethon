"""The ramjet's voice, baked from recordings of real rocket engines.

    python -I tools/ramjet_bake.py

Luke, 2026-11-22: "the ram jet needs its own sound signifier. First gut is saying an actual rocket engine -
just a low screaming roar". And after flying the first cut of it: "I like the ramjet sound, but I feel like it's
a few octaves too high. It's correct on the ripping/shredding sound", with a launch's raw sound for what he
meant. That first cut put its weight at 400 Hz to 3 kHz (half its energy over 407 Hz); the launch he pointed
at has half its energy under 70 Hz and 90% under 284 Hz. So this is the same two recordings re-cut and run
slower, as a tape is run slower (pitch and pace together: the tear's crackle comes down with its pitch, which
is what his launch does: its loudness flutters at 50 Hz where the first cut's fluttered at 220).
Nothing here is synthesised. Two recordings (tools/audio_src/ramjet, credited in godot/audio/ramjet/CREDITS.md
and THIRD_PARTY.md):

  shuttle_launch   Freesound 220127, klangfabrik, "shuttlelaunch.wav", CC0: a re-edit of NASA's own recordings
                   of Space Shuttle launches (the site's high-quality preview). The roar: the stack climbing
                   away, 35 s to 43 s in, the stretch of it that tears hardest (the skewness of the wave's rate
                   of change is -0.8 there, against +0.4 to -0.4 in the stretch the first cut used). And the
                   ignition's first thump.
  rs25_*           NASA Stennis Space Center, "RS-25 Engine Test 2025-11-12" (NASA Image and Video Library id
                   SSC_2025-11-12_RS-25_Engine_Test): a Space Shuttle main engine run for 500 s on the Fred
                   Haise Test Stand. NASA's own film, not copyrighted. Three stretches of its sound (the start,
                   50 s of the run, the cut-off), taken from the library's "medium" copy and kept as mono
                   Vorbis. The tear: three quarters of a second of the engine's crackle (0.5 to 14 kHz)
                   run eleven times slower, three and a half octaves down. And the catch as it lights and
                   the fall as it is cut off, run four times slower.

What is written to godot/audio/ramjet, 48 kHz mono 16-bit:
  ramjet_body.wav     a loop: the roar. The shuttle run 1.3 times slower: half its energy under 70 Hz, its
                      weight from 45 to 350 Hz, its crackle's edge left on it (nothing is cut but what lies
                      under 40 Hz, which nothing here can play)
  ramjet_tear.wav     a loop: the tear, 45 Hz to 1.3 kHz with its weight at 90 to 500 Hz, where a headset's own
                      speakers (little under 90 Hz) can play the voice
  ramjet_light_N.wav  the light-up: the shuttle's ignition thump (run 1.5 times slower), the test engine's
                      crackle over it two octaves down (an octave over where the tear settles), a low swell
  ramjet_out_N.wav    the shut-down: the test engine's last third of a second at power, two octaves down and
                      slowed further as it falls (a tape running down), over the roar running down with it
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
LOOP_PEAK = 0.94         # ... and the roar's tallest crackle held under this (it never gets there: its peaks stand 13 dB over its rms)
TEAR_CREST_DB = 13.0     # the tear's tallest peaks held this far over its rms, as the roar's own are. Left as recorded they
                         # stand 17 dB over and more: played at the level the tear needs, each engine's would land 4 dB over
                         # the Engines bus's limiter, which would shave them anyway and duck the whole mix with each one.
SHOT_PEAK = 0.7          # the one-shots' peak (the start-up's sounds are written at the same)
RIGHT = 0.965            # the right engine's one-shots: this much slower, and lower
BODY_SLOW = 1.3          # the roar: the shuttle's tape run this many times slower (0.38 of an octave down)
TEAR_SLOW = 11.0         # the tear: the test engine's, three and a half octaves down
SHOT_SLOW = 4.0          # the test engine in the light-up and the shut-down: two octaves down
THUMP_SLOW = 1.3         # the shuttle's ignition thump in the light-up
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


def slow(y, times):
    """A tape run `times` slower: lower and longer by that much, nothing else done to it."""
    return signal.resample_poly(y, int(round(100 * times)), 100)


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


def tear_of(y):
    """How a sound tears: the skewness of the wave's rate of change (a crackling sound's pressure moves faster one
    way than the other), the peaks a second its envelope throws over three times its rms, and the frequency
    under which half its energy lies."""
    d = np.diff(y)
    d = d - d.mean()
    skew = float((d ** 3).mean() / (d ** 2).mean() ** 1.5)
    z = y - y.mean()
    rms = math.sqrt(float((z ** 2).mean()))
    peaks, _ = signal.find_peaks(np.abs(signal.hilbert(z)), height=3.0 * rms, distance=int(RATE * 0.004))
    f, p = signal.welch(y, RATE, nperseg=16384, noverlap=8192)
    keep = f >= 20.0
    half = float(f[keep][np.searchsorted(np.cumsum(p[keep]) / p[keep].sum(), 0.5)])
    return skew, len(peaks) / (len(y) / RATE), half


# ---- the sounds ----

BODY_S, TEAR_S, FOLD_S = 9.0, 7.0, 0.6      # (lengths that share no small multiple: the pair repeats after 63 s)


def engine_crackle(name, t0, t1, lead=0.3):
    """A stretch of the test engine's film, its crackle alone: 0.5 to 14 kHz (under that the recording is the
    stand's rumble and the camera's handling; the filter is run in over `lead` seconds before the stretch)."""
    y = butter(butter(piece(name, t0 - lead, t1), "highpass", 500.0), "lowpass", 14000.0)
    return y[int(lead * RATE):]


def body_loop():
    """The roar: the shuttle's stack 35 s into the re-edit, the stretch of it that tears hardest, run BODY_SLOW
    times slower. Only what lies under 40 Hz is taken off (a headset cannot play it and it eats the mix's
    headroom): its top is its crackle's edge, and is left on it."""
    lead = 0.5
    y = slow(piece("shuttle_launch", 34.6, 34.6 + (lead + BODY_S + FOLD_S + 0.3) / BODY_SLOW), BODY_SLOW)
    y = butter(y, "highpass", 40.0)[int(lead * RATE):]
    y = seamless(y, int(BODY_S * RATE), int(FOLD_S * RATE))
    return level_out(y)


def tear_loop():
    """The tear: a second of the test engine's crackle at full power (35 s into the kept stretch of its run, where
    it crackles hardest) run TEAR_SLOW times slower. Three and a half octaves down its band is 45 Hz to 1.3 kHz
    and its crackle comes at a dozen and a half hard peaks a second, as the launch Luke pointed at does (16):
    a rip, not a hiss."""
    lead = 0.4
    y = slow(engine_crackle("rs25_steady", 35.0, 35.0 + (lead + TEAR_S + FOLD_S + 0.3) / TEAR_SLOW), TEAR_SLOW)
    y = y[int(lead * RATE):]
    y = seamless(y, int(TEAR_S * RATE), int(FOLD_S * RATE))
    return level_out(y)


def light_up(speed):
    """The catch, 1.9 s: the shuttle's ignition thump (taken from where it is already 7 dB under its top, so it
    lands hard; run THUMP_SLOW times slower), the test engine's crackle over it just after it has caught (run
    SHOT_SLOW times slower: an octave over where the tear settles, so the catch is brighter than what follows),
    and a low swell that hands over to the loops."""
    bang = full(fade(slow(piece("shuttle_launch", 0.37, 1.05), THUMP_SLOW), 0.004, 0.4))
    catch = slow(engine_crackle("rs25_start", 7.62, 8.07), SHOT_SLOW)
    catch = full(swell(fade(catch, 0.01, 0.4), 0.02, 0.6, 0.35))
    low = butter(piece("shuttle_launch", 1.45, 3.3), "lowpass", 350.0)
    low = full(swell(fade(low, 0.02, 0.5), 0.12, 0.5, 0.4))
    y = mix((bang, 0.0, 1.0), (catch, 0.03, 0.8), (low, 0.07, 0.7))[:int(1.9 * RATE)]
    y = fade(y, 0.001, 0.3)
    return pitch(y, speed) if speed != 1.0 else y


def shut_down(speed):
    """The fall, 1.5 s: the test engine's last third of a second at power before its cut-off, run SHOT_SLOW times
    slower and then run down as a tape runs down (to 0.6 of that speed in 0.8 s) so its note falls as it dies,
    over the low thump the engine gave as it was throttled back and the roar's own stretch of the shuttle running
    down with it. It begins at its top: the game starts it as the loops begin to fall."""
    cut = slow(engine_crackle("rs25_stop", 17.72, 18.07), SHOT_SLOW)
    cut = ramp(fade(cut, 0.003, 0.3), 1.0, 0.6, 0.8)
    cut = full(swell(cut, 0.003, 0.10, 0.35))
    thump = butter(piece("rs25_stop", 12.18, 13.0), "lowpass", 500.0)
    thump = full(swell(fade(thump, 0.005, 0.3), 0.01, 0.08, 0.2))
    low = butter(slow(piece("shuttle_launch", 36.0, 37.3), BODY_SLOW), "highpass", 40.0)
    low = full(swell(ramp(fade(low, 0.003, 0.3), 1.0, 0.6, 0.8), 0.003, 0.08, 0.3))
    y = fade(mix((cut, 0.0, 1.0), (thump, 0.0, 0.5), (low, 0.0, 0.8))[:int(1.5 * RATE)], 0.001, 0.25)
    return pitch(y, speed) if speed != 1.0 else y


def finish_loop(y, peak=LOOP_PEAK):
    """A loop at its level, its tallest crackle held under `peak`, limited as a loop (wrapped, so the join stays good)."""
    y = y - y.mean()
    y = y * (10 ** (LOOP_RMS_DB / 20) / math.sqrt(float(np.mean(y * y))))
    n = len(y)
    y = limit(np.concatenate([y[-RATE:], y, y[:RATE]]), peak)[RATE:RATE + n]
    return y


def finish_shot(y):
    y = butter(y - y.mean(), "highpass", 30.0)
    y = fade(y, 0.001, 0.02)
    return y * (SHOT_PEAK / np.abs(y).max())


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    fails = 0
    manifest = {"rate": RATE, "rms_db": LOOP_RMS_DB, "layers": {}, "oneshots": {}}
    for layer, name, make in (("ramjet", "ramjet_body.wav", body_loop), ("ramtear", "ramjet_tear.wav", tear_loop)):
        y = finish_loop(make(), 10 ** ((LOOP_RMS_DB + TEAR_CREST_DB) / 20) if layer == "ramtear" else LOOP_PEAK)
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
        skew, peaks, half = tear_of(y)
        print("       bands: 45-90 Hz %.1f dB, 90-180 %.1f, 180-355 %.1f, 355-710 %.1f, 710-1.4k %.1f, 1.4k-2.8k %.1f; half its energy under %.0f Hz, "
              "centroid %.0f Hz; over 90 Hz %.1f dB" % (band_db(y, 45, 90), band_db(y, 90, 180), band_db(y, 180, 355), band_db(y, 355, 710),
                                                    band_db(y, 710, 1400), band_db(y, 1400, 2800), half, centroid(y), rms_db(butter(y, "highpass", 90.0, 4))))
        print("       its tear: the skewness of its rate of change %.2f, %.0f hard peaks a second" % (skew, peaks))
        manifest["layers"][layer] = {"unit": "speed", "bands": [{"file": name, "at": 1.0}], "seconds": round(len(y) / RATE, 3),
                                     "seam": round(seam, 3), "seam_level_db": round(step_l, 2), "seam_cents": round(step_c, 1),
                                     "peak_db": round(20 * math.log10(np.abs(y).max()), 2), "centroid_hz": round(centroid(y)),
                                     "half_hz": round(half), "skew": round(skew, 2), "peaks_s": round(peaks, 1)}
    for shot, make in (("light", light_up), ("out", shut_down)):
        files = []
        for k, speed in enumerate((1.0, RIGHT)):
            y = finish_shot(make(speed))
            name = "ramjet_%s_%d.wav" % (shot, k)
            sf.write(str(OUT / name), y, RATE, subtype="PCM_16")
            files.append(name)
            env = np.sqrt(np.maximum(uniform_filter1d(y * y, size=int(0.02 * RATE)), 0.0))
            top = int(np.argmax(env))
            first = int(np.argmax(env > env.max() * 10 ** (-20 / 20)))
            gone = len(env) - int(np.argmax(env[::-1] > env.max() * 10 ** (-20 / 20)))
            print("  ok   %-18s %.2f s  rms %.1f dB  from 20 dB under its top to its top in %.0f ms; back 20 dB under it at %.2f s; centroid %.0f Hz" % (
                name, len(y) / RATE, rms_db(y), 1000.0 * (top - first) / RATE, gone / RATE, centroid(y)))
        manifest["oneshots"][shot] = files
    (OUT / "manifest.json").write_text(json.dumps(manifest, indent="\t") + "\n", encoding="utf-8", newline="\n")
    for stale in ("ramjet_scream.wav", "ramjet_scream.wav.import"):      # (the first cut's upper loop: the tear took its place)
        if (OUT / stale).exists():
            (OUT / stale).unlink()
    print("RAMJET BAKE", "PASS" if fails == 0 else "FAIL (%d)" % fails, "->", OUT)
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()
