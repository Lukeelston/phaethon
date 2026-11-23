"""EngineAudio gate: does the sound actually follow the levers?

Runs godot/tests/test_engine_audio.gd fifteen times in parallel: V8, V12 and turbine solo, the
same three --flat (every gain held at 1, low-pass open, and no twin detune, pops or bark, so
only the crossfader can move the level), the overrun pops solo, the full mix, the second
engine's own run (--profile=second) with the second engine solo, the bass rotor solo, and
everything mixed, the turbines' own run (--profile=turbine: flat out through turbine_mph,
then the air brakes) with the turbines solo and the V8 solo, and the ramjet's run (--profile=ramjet:
the burner, the ramjet armed at 1,500 mph and held to 6,000, the boost three seconds, disarmed) with
the ramjet's voice solo and with everything mixed.
The lever run tops out near 3,700 mph, under the 4,500 the turbines light at, so its turbine
solo holds the run-up's turbine test on from 9.5 s (--runup-turbines): the voice's own checks
(pitch, split, pan, flameout) are made there, and where it lights is checked on its own run.
Each run records the game's master bus.
Then it measures the recordings against the RPM each run logged:
  pitch     V8/V12 firing pitch (subharmonic summation; for the V8, that or the octave under it,
            which its uneven cylinders sound on purpose) and turbine blade-pass line, within 3%
            of the logged RPM, wherever the RPM holds steady across the window (the turbines:
            wherever they are in)
  turbines  the second stage: nothing from them until the craft reaches turbine_mph[0] (under
            -60 dBFS, at least 30 dB under their full level), they light within 200 mph of it,
            the whine winds up from 0.4 of its pitch, and under turbine_off_mph they stop
  shift     as the turbines light the V8's note drops to turbine_shift of its revs' pitch, then
            climbs with the speed until it has faded out under them
  split     left lever 0.87, right 0.15: each channel carries its own engine on pitch, and each
            engine is at least 9 dB louder on its own side
  flameout  a dead left engine drops the pistons out of the left channel (at least 9 dB)
  relight   after the reignite, the left engine is back on pitch
  second    the second engine lights within 150 mph of second_on_mph, right side ~0.3 s after
            the left, coughs ~0.7 s before it catches, is silent before and dead after (below
            second_off_mph), its doublet pitch (rpm / 60, above 1,800 rpm) follows the lever, and it is rumbly
            at full lever: >= 35% of its energy under 150 Hz, centroid <= 300 Hz. On a steady
            lever it winds up with speed: x(1 + 0.7 * progress 1,500 -> 4,500 mph), within 2%.
  rotor     the bass rotor is bassy at low speed (below 300 mph: >= 85% under 200 Hz, centroid
            <= 160 Hz), winds up
            with speed (its brightness follows its pitch: correlation >= 0.95, 0.75-1.35 octaves
            per octave), and steps back >= 6 dB once the second engine runs
  twin      on equal levers the right engine runs 0.1-0.6% fast and the two beat: the V12's mono
            level breathes (150 ms level sd >= 0.8 dB) where the flat run, with no detune, holds
            still
  bark      a lever stab revs up in <= 0.2 s (median) and flares 4-20% past the lever
  pops      lifting off at high revs pops (both after the burner drop and through the blips),
            and nothing pops at idle, on the rev, on a hold, in the burner or through the
            flameout; popping stretches stand >= 40 dB over the quiet ones
  ramjet    the ramjet's own voice (a roar with its weight at 45 to 350 Hz and a tear at 90 to
            500 Hz): nothing of it on the burner before the ramjet is armed or two seconds after
            it is disarmed (under -60 dBFS, 30 dB under its level lit); armed, it is up within a
            quarter of a second and for its first 0.4 s stands 1 to 12 dB over where it settles
            (one light-up, one shut-down); it follows the speed (from 4,600 to 6,000 mph no quieter,
            its 180-710 Hz band within 1 dB of the climb the game logs for its tear, and the tear
            played at least 6% faster); the held boost lifts it (at least 1 dB
            at 180-710 Hz, the tear played at least 15% faster) and letting go drops it back;
            disarmed it is 12 dB down in half a second. In the mix the ramjet and the burner are
            told apart: the voice is at least half of what the mix has between 90 and 710 Hz (the
            layers that share that band step back for it), the mix is no quieter than on the
            burner, the turbines' whine still stands 10 dB proud of it, and the mix does not clip
  one tone  flat runs, slow rev: brightness doesn't pulse grossly with band position (no more
            than 100 cents, or 1.5x its typical wander at unrelated spacings, or the most it
            wanders at any of them); the bake's level-correlation gate is the precise guard
  steady    flat runs: each channel's 150 ms level stays within 2.5 dB of a smooth curve in RPM
            while both engines share an RPM, lever blips included. Crossfade artifacts are local
            holds of several dB
Exit 0 = every check passes on at least 90% of its windows.

  python tools/engine_audio_check.py [--out DIR] [--plot]     (--plot draws a spectrogram PNG)
  python tools/engine_audio_check.py --listen                  the listening copy only: engine_listen.wav
  python tools/engine_audio_check.py --reuse [--out DIR]       measure the captures already there

Headless captures mix through Godot's Dummy driver in 93 ms bursts, so pitch can only change
~11 times a second: fine for these checks, but it records as stepping through tones. The
listening copy runs in Movie Maker mode instead (a small window opens): one mix per frame at
96 fps, the cadence the game has on a sound card in the headset.
"""
import argparse
import csv
import glob
import os
import shutil
import subprocess
import sys

import numpy as np
import soundfile as sf

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CYL = {"v8": 8, "v12": 12}
BLADE_HZ = 2400.0
PAN_LOUD = 1.6   # Godot's panner at +-0.6 on a mono source: 1.6x near side, 0.4x far side
WIN = 0.25
# Gross stepping only: brightness may not pulse with band position by more than this many
# cents AND more than 1.5x chance AND more than chance ever reaches. The stepping band design read 109-198; the fixed design
# 13-83 (its noise). The bake's level-correlation gate is the precise guard.
MAX_SWING = 100.0


def godot_exe():
    exe = shutil.which("Godot_v4.7.1-stable_win64_console.exe")
    if exe:
        return exe
    hits = glob.glob(os.path.join(os.environ.get("LOCALAPPDATA", ""), "Microsoft", "WinGet", "Packages",
                                  "GodotEngine.GodotEngine_*", "Godot_v*win64_console.exe"))
    if not hits:
        sys.exit("Godot console exe not found")
    return hits[0]


def capture(out_dir):
    procs = {}
    for run in ["v8", "v12", "turbine", "v8_flat", "v12_flat", "turbine_flat", "pops", "all", "second", "rotor",
                "second_all", "turbine_run", "v8_run", "ramjet", "ramjet_all"]:
        wav = os.path.join(out_dir, "engine_%s.wav" % run)
        args = [godot_exe(), "--headless", "--path", os.path.join(ROOT, "godot"), "-s",
                "res://tests/test_engine_audio.gd", "--", "--out=" + wav.replace("\\", "/")]
        if run not in ("all", "second_all", "ramjet_all"):
            args.append("--solo=" + run.split("_")[0])
        if run.startswith("ramjet"):   # the ramjet's run: the burner, the ramjet armed and held, the boost, disarmed
            args.append("--profile=ramjet")
        if run.endswith("_flat"):
            args.append("--flat")
        if run.startswith("second") or run == "rotor":
            args.append("--profile=second")
        if run.endswith("_run"):       # the turbines' run: flat out through turbine_mph, then the brakes
            args.append("--profile=turbine")
        if run == "turbine":           # the lever run never reaches turbine_mph[0]: the run-up's turbine test holds them in
            args.append("--runup-turbines")
        procs[run] = (subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True), wav)
    fails = 0
    for solo, (p, wav) in procs.items():
        out, _ = p.communicate(timeout=180)
        gate = [l for l in out.splitlines() if l.startswith(("  ok", "  FAIL", "capture:", "ENGINE AUDIO"))]
        print("[%s]\n  %s" % (solo, "\n  ".join(gate)))
        fails += 0 if p.returncode == 0 else 1
    return {s: w for s, (_, w) in procs.items()}, fails


def listen(out_dir):
    """The full mix, recorded one mix per rendered frame (Movie Maker, 96 fps), as heard in game:
    the main run and the second engine's run."""
    for name, extra in (("engine_listen", []), ("engine_listen_second", ["--profile=second"])):
        wav = os.path.join(out_dir, name + ".wav")
        avi = os.path.join(out_dir, "_listen.avi")
        args = [godot_exe(), "--path", os.path.join(ROOT, "godot"), "--resolution", "160x90",
                "--write-movie", avi, "--fixed-fps", "96", "-s", "res://tests/test_engine_audio.gd",
                "--", "--out=" + wav.replace("\\", "/")] + extra
        out = subprocess.run(args, capture_output=True, text=True, timeout=600).stdout
        if os.path.exists(avi):
            os.remove(avi)
        print("\n".join(l for l in out.splitlines() if l.startswith(("  ok", "  FAIL", "capture:", "ENGINE AUDIO"))))
        print("listening copy ->", wav)


def load(wav):
    x, sr = sf.read(wav, dtype="float64")
    with open(os.path.splitext(wav)[0] + ".csv") as f:
        rows = list(csv.DictReader(f))
    log = {k: np.array([float(r[k]) for r in rows]) for k in rows[0] if k != "mode"}
    return x, sr, log


def at(log, key, t):
    return float(np.interp(t, log["t"], log[key]))


def seg(x, sr, t, win=WIN):
    i = int((t - win / 2) * sr)
    return x[max(0, i):i + int(win * sr)]


def span(layer, f):
    """How long to listen for a pitch. A piston engine that fires unevenly (the V8 lopes and
    misses, on purpose) puts a line on every order of its 720-degree cycle, f / cyl apart: 6 Hz
    at a 700 rpm idle. A quarter second cannot tell the firing line from its neighbours there
    (its window is 8 Hz wide), so pistons get at least four engine cycles."""
    return max(WIN, 4.0 * CYL[layer] / f) if layer in CYL else WIN


def spectrum(s, sr):
    nfft = 1 << 17
    return np.abs(np.fft.rfft(s * np.hanning(len(s)), nfft)), sr / nfft


def pitch(s, sr, f_exp, lowest=0.7):
    """Subharmonic summation (Hermes 1988) over candidates from `lowest` to 1.43 times f_exp."""
    X, df = spectrum(s, sr)
    c = f_exp * np.exp(np.linspace(np.log(lowest), np.log(1.43), int(800 * np.log(1.43 / lowest) / np.log(1.43 / 0.7))))
    score = np.zeros_like(c)
    for k in range(1, 9):
        idx = np.clip((k * c / df).astype(int), 0, len(X) - 1)
        score += 0.84 ** (k - 1) * X[idx]
    return float(c[np.argmax(score)])


def line(s, sr, f_exp, span=0.06):
    return line_strength(s, sr, f_exp, span)[0]


def line_strength(s, sr, f_exp, span=0.06):
    """Strongest line within +-span of f_exp: (frequency, magnitude, dB above the median of +-20%)."""
    X, df = spectrum(s, sr)
    lo, hi = int(f_exp * (1 - span) / df), int(np.ceil(f_exp * (1 + span) / df)) + 1
    k = lo + int(np.argmax(X[lo:hi]))
    floor = np.median(X[int(f_exp * 0.8 / df):int(f_exp * 1.2 / df)])
    return k * df, float(X[k]), float(20 * np.log10(X[k] / (floor + 1e-12)))


def expect(layer, log, side, t):
    if layer == "turbine":
        return BLADE_HZ * at(log, "turb" + side, t)
    return at(log, layer + side, t) * CYL[layer] / 120.0


# The V8's alternate cylinders pull hard and soft, on purpose (tools/engine_bake.py cyl_trim):
# that is a second note an octave under the firing pitch, with lines at 1/2, 3/2, 5/2 of it.
# Searched only around the firing pitch, the summation locks onto 3/4 of it at high revs (the
# pitch whose harmonics collect the 3/2 and 9/2 lines; measured, every one of 14 misses in 87
# windows read x0.750-0.753). So the V8 is searched down past the octave, and its note may be
# either: both follow the levers.
OCTAVE_UNDER = {"v8"}


def measure(layer, s, sr, f):
    if layer == "turbine":
        return line(s, sr, f)
    if layer in OCTAVE_UNDER:
        got = pitch(s, sr, f, 0.35)
        return got * 2.0 if abs(got / (f / 2.0) - 1) < 0.03 else got
    return pitch(s, sr, f)


def steady(layer, log, side, t):
    half = span(layer, max(expect(layer, log, side, t), 1.0)) / 2   # across all that the pitch is measured over
    a, b = expect(layer, log, side, t - half), expect(layer, log, side, t + half)
    return abs(a / b - 1) < 0.03


def level_dips(x, sr, log, layer):
    """Flat runs only: each channel's 150 ms level, every 10 ms, wherever both engines sit at the
    same RPM (so a dip can't be the other engine leaving or beating), minus a smooth (cubic) fit
    against log RPM. With the gains held flat, level may still drift with RPM (the fixed muffler
    trims more as the pulses brighten), but only smoothly. A crossfade artifact is local: two
    interfering bands held 5-8 dB off for 0.3-1.2 s (measured 2026-10-17), which no cubic follows.
    Per channel, because that is what each ear gets.
    The V8's level is taken over at least two engine cycles: it lopes on purpose, and 150 ms of
    a 700 rpm idle is seven pulses of an eight-pulse pattern, so a shorter window reads the lope
    itself as a dip. Every level crossfade sits above 1,600 rpm, where two cycles are back
    under 150 ms."""
    ts = np.arange(0.4, log["t"][-1] - 0.4, 0.01)
    keys = ("turbL", "turbR") if layer == "turbine" else (layer + "L", layer + "R")
    a, b = np.interp(ts, log["t"], log[keys[0]]), np.interp(ts, log["t"], log[keys[1]])
    # "Same RPM" means the same to 0.05%: two engines even 0.2% apart drift through each other's
    # phase (a real twin-engine beat, ~1 s period, +-3 dB). That's the imbalance being audible,
    # not a crossfade, and it would make this check a coin toss after the reignite.
    sym = (np.abs(a / b - 1) < 0.0005) & (ts > 1.0)
    lr = np.log2(np.maximum(a[sym], 1e-3))
    out = []
    ws = np.maximum(0.15, 240.0 / np.maximum(a[sym], 100.0)) if layer == "v8" else np.full(int(sym.sum()), 0.15)
    for ch in (x[:, 0], x[:, 1]):
        db = np.array([10 * np.log10(np.mean(ch[max(0, int((t - w / 2) * sr)):int((t + w / 2) * sr)] ** 2) + 1e-12)
                       for t, w in zip(ts[sym], ws)])
        out.append(db - np.polyval(np.polyfit(lr, db, 3), lr))
    resid = np.concatenate(out)
    return resid, len(resid)


def timbre_swing(x, sr, log, layer):
    """Flat runs only, on the slow rev (2.6-8 s): brightness (spectral centroid, 60 ms) minus its
    smooth trend against RPM, averaged by where the RPM sits between two baked bands (5 bins).
    If each band sounds like its own tone, brightness swings with band position and a ramp
    "steps through selected tones" (measured 2026-10-17: 109 cents V8, 198 cents V12). A lumpy
    engine's brightness wanders anyway (the fixed design read 13-83 cents over runs), so the
    swing is also measured against unrelated spacings: the noise floor. This in-game check
    only catches gross stepping; the precise guard is the bake's gate that neighbouring levels
    correlate >= 0.9 (copies of one master; independent bands measured 0.14-0.73).
    (Widening it to the whole run made it worse: a cubic can't follow the V12's brightness
    from 1,100 to 13,400 rpm under its fixed muffler, and the misfit aliases into the bins.)
    The noise floor is its typical size and its largest: an engine that misses on purpose (the
    V8, since 2026-11-19) makes brightness jump from window to window, 226 cents sd against 57
    for the smooth one, and its swing at unrelated spacings then ranges from 68 to 217 cents.
    1.5x the median called a 105-cent swing at the bands stepping, 3 cents over; it was chance.
    Returns (swing at the bands' own spacing, typical noise, largest noise), or None for a
    single-loop layer."""
    import json
    man = json.load(open(os.path.join(ROOT, "godot", "audio", "engines", "manifest.json")))
    bands = np.array([b["at"] for b in man["layers"][layer]["bands"]])
    if len(bands) < 2:
        return None
    key = "turbL" if layer == "turbine" else layer + "L"
    mono = x.mean(axis=1)
    ts = np.arange(2.6, 8.0, 0.02)
    at = np.interp(ts, log["t"], log[key])
    w = int(0.06 * sr)
    f = np.fft.rfftfreq(w, 1 / sr)
    c = []
    for t in ts:
        i0 = int(t * sr) - w // 2
        X = np.abs(np.fft.rfft(mono[i0:i0 + w] * np.hanning(w))) ** 2
        c.append(np.log2(np.sum(f * X) / np.sum(X)))
    c = np.array(c)
    r = (c - np.polyval(np.polyfit(np.log2(at), c, 2), np.log2(at))) * 1200

    def swing(frac):
        e = np.linspace(0, 1, 6)
        m = [r[(frac >= e[i]) & (frac < e[i + 1])].mean() for i in range(5)]
        return max(m) - min(m)
    u = np.interp(np.log(at), np.log(bands), np.arange(len(bands)))
    noise = [swing((np.log2(at) / np.log2(p) + o) % 1.0) for p in (1.45, 1.6, 1.75, 2.5, 2.75, 3.1, 3.3) for o in (0.0, 0.33)]
    return swing(u - np.floor(u)), float(np.median(noise)), float(np.max(noise))


class Tally:
    def __init__(self):
        self.rows = []

    def add(self, name, hits, n, need=0.9):
        ok = n > 0 and hits / n >= need
        self.rows.append(ok)
        print("  %s %-44s %3d/%3d windows (%3.0f%%)" % ("ok  " if ok else "FAIL", name, hits, n, 100 * hits / max(1, n)))


def check_layer(layer, wav, flat_wav, tally):
    x, sr, log = load(wav)
    mono, left, right = x.mean(axis=1), x[:, 0], x[:, 1]
    print("[%s]" % layer)
    ts = np.arange(0.4, log["t"][-1] - 0.2, 0.1)
    hits = n = 0
    for t in ts:
        if not (t < 14.8 or 19.5 < t < 20.9 or t > 26.0):
            continue
        fl, fr = expect(layer, log, "L", t), expect(layer, log, "R", t)
        if abs(fl / fr - 1) > 0.01 or not steady(layer, log, "L", t):
            continue
        if layer == "turbine" and at(log, "stage", t) < 0.35:   # not lit yet, or barely
            continue
        n += 1
        hits += abs(measure(layer, seg(mono, sr, t, span(layer, fl)), sr, fl) / fl - 1) < 0.03
    tally.add("%s pitch follows the levers" % layer, hits, n)
    fx, fsr, flog = load(flat_wav)
    dips, n = level_dips(fx, fsr, flog, layer)
    tally.add("%s steady through crossfades (%+.1f..%+.1f dB)" % (layer, dips.min(), dips.max()),
              int((np.abs(dips) <= 2.5).sum()), n, 0.995)
    tone = timbre_swing(fx, fsr, flog, layer)
    if tone is None:
        tally.add("%s one tone through the rev (single loop)" % layer, 1, 1, 1.0)
    else:
        tally.add("%s one tone through the rev (swing %.0f cents, chance %.0f, up to %.0f)" % (layer, tone[0], tone[1], tone[2]),
                  int(tone[0] <= max(MAX_SWING, 1.5 * tone[1], tone[2])), 1, 1.0)
    # Split. Pitch-tracking a whole channel fails here by design: the screaming left engine's
    # bleed can out-shout the idling right engine's quiet layer (measured 6-8 dB for the V12),
    # which is how two engines really sound. So test what the split promises, separately:
    #   split  each channel carries its own engine's firing line, on pitch, >= 12 dB proud
    #   pan    the screaming left engine's line is >= 9 dB louder on the left (the panner gives
    #          1.6x vs 0.4x = 12 dB). Only the loud engine: the quiet one's far-side line sits under
    #          the loud engine's own roar, which would measure the roar, not the pan.
    hits = n = pan_hits = pan_n = 0
    for t in ts[(ts > 16.0) & (ts < 18.9)]:
        for side, near, far in (("L", left, right), ("R", right, left)):
            f = expect(layer, log, side, t)
            got, peak, prom = line_strength(seg(near, sr, t, span(layer, f)), sr, f)
            n += 1
            hits += abs(got / f - 1) < 0.03 and prom >= 12.0
            if side == "L":
                _, far_peak, _ = line_strength(seg(far, sr, t, span(layer, f)), sr, got, span=0.01)
                pan_n += 1
                pan_hits += 20 * np.log10(peak / far_peak) >= 9.0
    tally.add("%s split: each channel carries its engine" % layer, hits, n)
    tally.add("%s pan: left engine louder on the left" % layer, pan_hits, pan_n)
    if layer == "turbine":
        # The wind-down glides ~60%/s, so the pitch moves +-7% inside one window: the measured
        # line must sit within 3% of the range the expected pitch sweeps across the window.
        hits = n = 0
        for t in ts[(ts > 21.2) & (ts < 23.0)]:
            a, b = expect(layer, log, "L", t - WIN / 2), expect(layer, log, "L", t + WIN / 2)
            m = measure(layer, seg(left, sr, t), sr, expect(layer, log, "L", t))
            n += 1
            hits += min(a, b) * 0.97 <= m <= max(a, b) * 1.03
        tally.add("turbine flameout: left whine winds down on cue", hits, n)
        return
    def lr_db(t0, t1):
        a = slice(int(t0 * sr), int(t1 * sr))
        return 10 * np.log10(np.mean(left[a] ** 2) / np.mean(right[a] ** 2))
    before, after = lr_db(19.6, 20.9), lr_db(21.8, 23.9)
    drop = before - after
    tally.add("%s flameout: L/R %+.1f dB -> %+.1f dB (drop %.1f)" % (layer, before, after, drop),
              int(drop >= 9.0), 1, 1.0)


SECOND_ON_MPH, SECOND_OFF_MPH = 1500.0, 1300.0   # EngineAudio.TUNE second_on_mph / second_off_mph
TURBINE_ON_MPH, TURBINE_START = 4500.0, 0.4      # EngineAudio.TUNE turbine_mph[0], turbine_start
TURBINE_OFF_MPH = 4200.0                          # EngineAudio.TUNE turbine_off_mph
TURBINE_SHIFT = 0.76                              # EngineAudio.TUNE turbine_shift


def check_turbines(wav, tally):
    """The turbines are the second stage, on the turbine-only capture of their own run (flat out
    through turbine_mph, then the air brakes): silent on pistons alone, lit as the craft passes
    turbine_mph[0], winding up from low, and stopping once it is under turbine_off_mph."""
    print("[turbines]")
    x, sr, log = load(wav)
    mono = x.mean(axis=1)
    ts = np.arange(0.5, log["t"][-1] - 0.3, 0.05)
    w = int(0.1 * sr)
    db = np.array([10 * np.log10(np.mean(mono[int(t * sr) - w // 2:int(t * sr) + w // 2] ** 2) + 1e-12) for t in ts])
    mph = np.interp(ts, log["t"], log["mph"])
    stage = np.interp(ts, log["t"], log["stage"])
    full = float(np.median(db[stage > 0.9])) if (stage > 0.9).any() else 0.0
    reached = mph >= TURBINE_ON_MPH
    if not reached.any():
        tally.add("the run reaches turbine_mph[0] (top %.0f mph of %.0f)" % (mph.max(), TURBINE_ON_MPH), 0, 1, 1.0)
        return
    before = db[(mph < TURBINE_ON_MPH - 150) & (ts < ts[np.argmax(reached)])]
    # (a layer at rest still plays at -80 dB, so its floor is about -75 dBFS, not digital silence)
    tally.add("turbines silent on pistons alone (%.0f dBFS, %.0f dB under their full level)" % (before.max(), full - before.max()),
              int((stage > 0.9).any() and before.max() <= -60.0 and before.max() <= full - 30.0), 1, 1.0)
    lit = db > full - 30.0
    mph_on = float(mph[np.argmax(lit)]) if lit.any() else 0.0
    tally.add("turbines light at %.0f mph (threshold %.0f)" % (mph_on, TURBINE_ON_MPH),
              int(TURBINE_ON_MPH - 50 <= mph_on <= TURBINE_ON_MPH + 200), 1, 1.0)
    # the whine's pitch over what the lever alone would give it (turbine_n: 0.25 at idle, 1 at full)
    wound = np.interp(ts, log["t"], log["turbL"] / np.maximum(0.25 + 0.75 * log["sL"], 0.02))
    t_on = ts[np.argmax(lit)] if lit.any() else 0.0
    start = float(wound[(ts > t_on - 0.2) & (ts < t_on + 0.2)].min())
    after = float(wound[(ts > t_on + 3.0) & (ts < t_on + 3.5)].mean())
    tally.add("the whine winds up: x%.2f of its pitch as it lights, x%.2f three seconds on" % (start, after),
              int(start <= TURBINE_START + 0.2 and after >= 0.97), 1, 1.0)
    # under turbine_off_mph they stop: the stage goes out (turbine_tau[1]) and the whine winds down
    slowed = (mph < TURBINE_OFF_MPH) & (ts > ts[np.argmax(reached)])
    t_off = float(ts[np.argmax(slowed)]) if slowed.any() else ts[-1]
    drop2 = full - float(db[(ts > t_off + 1.9) & (ts < t_off + 2.1)].mean()) if t_off + 2.1 < ts[-1] else 0.0
    drop4 = full - float(db[(ts > t_off + 3.9) & (ts < t_off + 4.1)].mean()) if t_off + 4.1 < ts[-1] else 0.0
    tally.add("under %.0f mph they stop: %.0f dB down two seconds on, %.0f dB four seconds on" % (TURBINE_OFF_MPH, drop2, drop4),
              int(slowed.any() and drop2 >= 20.0 and drop4 >= 30.0 and drop4 > drop2 + 3.0), 1, 1.0)   # (measured 2026-11-21: 29 and 38 dB)


def check_shift(wav, tally):
    """The pistons' shift, on the V8-only capture of the turbines' run: as the turbines light the
    V8's note drops to turbine_shift of its revs' pitch, as on an upshift, then climbs with the
    speed until it has faded out under them."""
    print("[shift]")
    x, sr, log = load(wav)
    mono = x.mean(axis=1)
    reached = log["mph"] >= TURBINE_ON_MPH
    if not reached.any():
        tally.add("the run reaches turbine_mph[0] (top %.0f mph of %.0f)" % (log["mph"].max(), TURBINE_ON_MPH), 0, 1, 1.0)
        return
    t_on = float(log["t"][np.argmax(reached)])

    def heard(t):
        f = expect("v8", log, "L", t)
        return measure("v8", seg(mono, sr, t, span("v8", f)), sr, f)
    logged = expect("v8", log, "L", t_on + 0.5) / expect("v8", log, "L", t_on - 0.5)
    got = heard(t_on + 0.5) / heard(t_on - 0.5)
    tally.add("the V8 shifts down as the turbines light: x%.2f heard, x%.2f logged (turbine_shift %.2f)" % (got, logged, TURBINE_SHIFT),
              int(abs(got / logged - 1) < 0.04 and abs(logged - TURBINE_SHIFT) < 0.06), 1, 1.0)
    # ... then it climbs. The note moves inside one window, so (as for the turbines' wind-down) the
    # measured pitch must sit within 3% of the range the logged pitch sweeps across the window.
    hits = n = 0
    last = t_on + 0.5
    for t in np.arange(t_on + 0.5, log["t"][-1] - 0.5, 0.1):
        if at(log, "stage", t) > 0.7 or at(log, "thrL", t) < 0.9:   # faded out under the turbines, or the levers shut
            break
        f = expect("v8", log, "L", t)
        half = span("v8", f) / 2
        a, b = expect("v8", log, "L", t - half), expect("v8", log, "L", t + half)
        n += 1
        hits += min(a, b) * 0.97 <= heard(t) <= max(a, b) * 1.03
        last = t
    climbed = expect("v8", log, "L", last) / expect("v8", log, "L", t_on + 0.5)
    tally.add("... then climbs with the speed (x%.2f in %.1f s)" % (climbed, last - t_on - 0.5), hits, n)
    tally.add("... and by then is well over where it shifted to", int(climbed >= 1.15), 1, 1.0)


def band(x, sr, lo, hi):
    """x between lo and hi Hz (4th-order Butterworth)."""
    from scipy import signal
    return signal.sosfilt(signal.butter(4, [lo, hi], "bandpass", fs=sr, output="sos"), x, axis=0)


TEAR_BAND = (90.0, 710.0)    # Hz: what a headset's own speakers can play of the ramjet's voice (in its deep cut the voice's weight
                             # is under this, 40 to 300 Hz; this is the part of it that must still be the voice's on those speakers)
VOICE_SHARE_DB = -3.0        # the voice's own level in that band against the mix's: -3 dB is half of what is there
RIP_BAND = (180.0, 710.0)    # Hz: the upper half of it, where the voice's climb with speed and with the boost shows


def check_ramjet(wav, mix_wav, tally):
    """The ramjet's own voice, on the capture of it alone over the ramjet's run (the burner from 1 s, the
    ramjet armed at 1,500 mph and held as the craft runs up to 6,000, the boost three seconds, disarmed):
    silent off the ramjet, up at once and boldly as it lights, following the speed, taking the boost, and
    dying as it is shut down. Then the same run with everything mixed: the ramjet told from the burner."""
    print("[ramjet]")
    x, sr, log = load(wav)
    t = log["t"]
    on, boosted = log["ramOn"] > 0.5, log["boost"] > 0.5
    if not on.any() or not boosted.any() or on[-1]:
        tally.add("the run lights the ramjet, holds the boost and shuts it down", 0, 1, 1.0)
        return
    t_on = float(t[np.argmax(on)])
    t_off = float(t[len(on) - np.argmax(on[::-1])])
    t_b0 = float(t[np.argmax(boosted)])
    t_b1 = float(t[len(boosted) - np.argmax(boosted[::-1])])
    tear = band(x, sr, TEAR_BAND[0], TEAR_BAND[1])
    rip = band(x, sr, RIP_BAND[0], RIP_BAND[1])

    def lvl(t0, t1, y=x):   # each ear's mean power, dB
        a = y[int(t0 * sr):int(t1 * sr)]
        return 10 * np.log10(np.mean(a * a) + 1e-14)

    def bright(t0, t1):
        # (where the voice's weight sits, 45 Hz to 1.4 kHz: over that is its crackle's edge, a hundredth of its energy
        # and too fitful from second to second to weigh)
        a = x[int(t0 * sr):int(t1 * sr)].mean(axis=1)
        X = np.abs(np.fft.rfft(a * np.hanning(len(a)))) ** 2
        f = np.fft.rfftfreq(len(a), 1 / sr)
        keep = (f >= 45.0) & (f <= 1400.0)
        return float(np.sum(f[keep] * X[keep]) / np.sum(X[keep]))
    # (the burner is lit from 1 s: what is heard before the ramjet is armed is everything that is not the ramjet's)
    before, after = lvl(1.5, t_on - 0.3), lvl(t_off + 2.0, t[-1] - 0.2)
    steady = lvl(t_b0 - 3.0, t_b0 - 0.2)
    tally.add("ramjet silent off the ramjet: %.0f dBFS on the burner before, %.0f after; %.0f lit" % (before, after, steady),
              int(before <= -60.0 and after <= -60.0 and steady - max(before, after) >= 30.0), 1, 1.0)
    # the light-up. The headless driver mixes in 93 ms bursts, so "at once" is read to a quarter of a second.
    settled = lvl(t_on + 2.2, t_on + 3.2)   # (its light-up's shot is 1.9 s long)
    ws = np.arange(t_on - 0.2, t_on + 1.0, 0.01)
    up = np.array([lvl(w, w + 0.05) for w in ws]) >= settled - 3.0
    t_up = float(ws[np.argmax(up)] - t_on) if up.any() else 9.0
    bold = lvl(t_on + 0.1, t_on + 0.5) - settled
    tally.add("ramjet lights: up %.2f s after it is armed, its first 0.4 s %.1f dB over where it settles (%d light-up, %d shut-down)" % (
        t_up, bold, log["ramLit"][-1], log["ramOuts"][-1]),
        int(-0.15 <= t_up <= 0.25 and 1.0 <= bold <= 12.0 and log["ramLit"][-1] == 1 and log["ramOuts"][-1] == 1), 1, 1.0)   # (measured on the lowered voice, three runs: 2.0 to 3.1 dB; on the deep one, three: 2.2 to 2.5)
    # it follows the speed: the first four seconds after its light-up's shot has gone (1.9 s) against the last four
    # before the boost. Its level hardly moves with the speed (it is as loud at 3,000 mph as the limiters leave room
    # for); what climbs is the tear, in level and in pace. A 45-700 Hz crackle's level wanders a dB from half second to
    # half second, which is as much as the climb, so it is read over four seconds; and how bright it measures wanders
    # by more than the climb, so the pace is taken from the game's own log. What is asked is that the band does not
    # fall and keeps within a dB of the climb the game logs for the tear; the law itself (so many dB and so much faster
    # at 3,000, 5,000 and 7,000 mph) is tests/test_ramjet_audio.gd's. (Measured 2026-11-22: level +0.1 dB, the band
    # +0.4 dB, the game's own figure +0.6 dB, x1.09 faster.) In the deep cut the roar carries the voice and the tear sits
    # 6 dB under it, so most of this band is the roar's and it climbs less: +0.2 to +0.7 dB in four runs, the spread
    # being where in their loops the two engines happened to start. "Does not fall" is read to half a dB for that.
    a0, a1, b0, b1 = t_on + 2.2, t_on + 6.2, t_b0 - 4.1, t_b0 - 0.1
    rise, rise_s = lvl(b0, b1) - lvl(a0, a1), lvl(b0, b1, rip) - lvl(a0, a1, rip)
    said = at(log, "ramTearDb", (b0 + b1) / 2) - at(log, "ramTearDb", (a0 + a1) / 2)
    faster = at(log, "ramTearAt", (b0 + b1) / 2) / at(log, "ramTearAt", (a0 + a1) / 2)
    tally.add("ramjet follows the speed: %.0f -> %.0f mph, level %+.1f dB, its %d-%d Hz band %+.1f dB (the game's own figure for its tear %+.1f dB), its tear played x%.2f faster" % (
        at(log, "mph", (a0 + a1) / 2), at(log, "mph", (b0 + b1) / 2), rise, RIP_BAND[0], RIP_BAND[1], rise_s, said, faster),
        int(rise >= -0.5 and rise_s >= -0.5 and said >= 0.3 and abs(rise_s - said) <= 1.0 and faster >= 1.06), 1, 1.0)
    # the boost: the voice alone is at the Engines bus's limiter already, so a stage harder is heard less as level than as
    # the tear played faster and harder: read where that shows, in the upper half of its band
    lift, lift_s = lvl(t_b0 + 0.5, t_b1 - 0.1) - lvl(t_b0 - 1.5, t_b0 - 0.1), lvl(t_b0 + 0.5, t_b1 - 0.1, rip) - lvl(t_b0 - 1.5, t_b0 - 0.1, rip)
    back_s = lvl(t_b0 + 0.5, t_b1 - 0.1, rip) - lvl(t_b1 + 0.5, t_b1 + 1.5, rip)
    harder = at(log, "ramTearAt", (t_b0 + t_b1) / 2) / at(log, "ramTearAt", t_b0 - 0.5)
    tally.add("ramjet takes the boost: %+.1f dB while it is held (%+.1f dB at %d-%d Hz, its tear played x%.2f faster), %.1f dB back down there once it is let go" % (
        lift, lift_s, RIP_BAND[0], RIP_BAND[1], harder, back_s), int(lift >= 0.0 and lift_s >= 1.0 and back_s >= 1.0 and harder >= 1.15), 1, 1.0)   # (measured: +0.7 to +1.1, +1.8 to +2.0, x1.28, 2.0 to 2.2; on the deep voice +1.1 to +2.1, +2.4 to +3.1, x1.28, 2.2 to 2.7)
    last = lvl(t_off - 1.0, t_off - 0.1)
    fall, gone = last - lvl(t_off + 0.5, t_off + 0.7), lvl(t_off + 2.0, t_off + 2.5)
    note = at(log, "ramTearAt", t_off + 0.4) / at(log, "ramTearAt", t_off - 0.2)
    tally.add("ramjet dies on the shut-down: %.0f dB down half a second on, %.0f dBFS two seconds on (its loops' note x%.2f as they go)" % (fall, gone, note),
              int(fall >= 12.0 and gone <= -60.0 and note <= 0.8), 1, 1.0)
    # ... and in the mix. The voice's band is the pistons' and the second engine's too, and they step back for it, so
    # the band's level hardly moves as the ramjet lights; what changes is whose it is. So: how much of what the mix
    # has in the tear's band is the voice (its own capture against the mix's, the same stretch of the same run),
    # and that the mix on the ramjet is no quieter than on the burner (the burner is what is left when it is disarmed).
    mx, msr, mlog = load(mix_wav)
    mt = mlog["t"]
    m_on = mlog["ramOn"] > 0.5
    m_off = float(mt[len(m_on) - np.argmax(m_on[::-1])])
    m_b0 = float(mt[np.argmax(mlog["boost"] > 0.5)])
    ms = band(mx, msr, TEAR_BAND[0], TEAR_BAND[1])

    def mlvl(t0, t1, y):
        a = y[int(t0 * msr):int(t1 * msr)]
        return 10 * np.log10(np.mean(a * a) + 1e-14)
    ram, burn = (m_b0 - 2.0, m_b0 - 0.2), (m_off + 1.5, m_off + 2.8)
    share = lvl(t_b0 - 2.0, t_b0 - 0.2, tear) - mlvl(*ram, ms)
    d_s, d_all = mlvl(*ram, ms) - mlvl(*burn, ms), mlvl(*ram, mx) - mlvl(*burn, mx)
    tally.add("ramjet told from the burner in the mix: its voice is %+.1f dB of what the mix has at %d-%d Hz (that band %+.1f dB on the burner's, the whole mix %+.1f dB; %.0f against %.0f mph)" % (
        share, TEAR_BAND[0], TEAR_BAND[1], d_s, d_all, at(mlog, "mph", sum(ram) / 2), at(mlog, "mph", sum(burn) / 2)),
        int(share >= VOICE_SHARE_DB and d_all >= -1.0), 1, 1.0)
    # the turbines' whine under it: its blade-pass line still proud of the mix, in each ear
    hits = n = 0
    worst = 99.0
    for tc in np.arange(ram[0], ram[1], 0.1):
        for side, ch in (("L", mx[:, 0]), ("R", mx[:, 1])):
            f = expect("turbine", mlog, side, tc)
            _, _, prom = line_strength(seg(ch, msr, tc), msr, f)
            n += 1
            hits += prom >= 10.0
            worst = min(worst, prom)
    tally.add("the turbines' whine still stands proud of the mix under the ramjet (10 dB or more; least %.0f dB)" % worst, hits, n)
    peak = 20 * np.log10(np.abs(mx).max() + 1e-12)
    tally.add("the mix on the ramjet and the boost does not clip (peak %.1f dBFS)" % peak, int(peak < -0.05), 1, 1.0)


def check_second(wav, tally):
    """The second engine's run (solo): when it lights, how it catches, that it follows the lever,
    that it dies, and that it is rumbly."""
    x, sr, log = load(wav)
    mono = x.mean(axis=1)
    t = log["t"]
    print("[second]")

    def first(side, state):
        hit = np.where(log["secSt" + side] == state)[0]
        return (float(t[hit[0]]), int(hit[0])) if len(hit) else (None, None)

    def rms_db(t0, t1):
        a = mono[int(t0 * sr):int(t1 * sr)]
        return 10 * np.log10(np.mean(a * a) + 1e-20)
    crank_l, i_crank = first("L", 2)
    crank_r, _ = first("R", 2)
    run_l, _ = first("L", 3)
    run_r, _ = first("R", 3)
    stop_l, i_stop = first("L", 4)
    if None in (crank_l, crank_r, run_l, run_r, stop_l):
        tally.add("second engine: lit, caught and stopped (it never got there)", 0, 1, 1.0)
        return
    mph_on, mph_off = log["mph"][i_crank], log["mph"][i_stop]
    tally.add("second lights at %.0f mph (threshold %.0f)" % (mph_on, SECOND_ON_MPH),
              int(SECOND_ON_MPH <= mph_on <= SECOND_ON_MPH + 150), 1, 1.0)
    tally.add("second right side lights %.2f s after the left" % (crank_r - crank_l), int(0.2 <= crank_r - crank_l <= 0.45), 1, 1.0)
    tally.add("second coughs %.2f s before it catches" % (run_l - crank_l), int(0.55 <= run_l - crank_l <= 0.85), 1, 1.0)
    before = rms_db(0.5, crank_l - 0.2)   # the log samples state every 50 ms: stay clear of the first cough
    running = rms_db(run_r + 0.5, stop_l - 0.2)
    after = rms_db(stop_l + 1.2, t[-1] - 0.1)
    tally.add("second silent before (%.0f dBFS), loud running (%.0f dBFS)" % (before, running),
              int(before < -60 and running > -30), 1, 1.0)
    tally.add("second dies at %.0f mph (threshold %.0f): %.0f dBFS after" % (mph_off, SECOND_OFF_MPH, after),
              int(SECOND_OFF_MPH - 150 <= mph_off <= SECOND_OFF_MPH and after < -50), 1, 1.0)
    hits = n = 0
    for tc in np.arange(run_r + 0.4, stop_l - 0.3, 0.1):
        fl, fr = np.interp(tc, t, log["secL"]) / 60.0, np.interp(tc, t, log["secR"]) / 60.0
        a, b = np.interp(tc - WIN / 2, t, log["secL"]), np.interp(tc + WIN / 2, t, log["secL"])
        # below 1,800 rpm the doublets come slower than 30 Hz: a rhythm, not a pitch to track
        if fl < 30.0 or abs(fl / fr - 1) > 0.01 or abs(a / b - 1) > 0.03:
            continue
        n += 1
        hits += abs(pitch(seg(mono, sr, tc), sr, fl) / fl - 1) < 0.03
    tally.add("second doublet pitch follows the lever", hits, n)
    # Winds up with speed: the lift the runtime applies on top of the lever (its rpm over what
    # the lever alone gives, lerp(600, 3800, spool)) must match 1 + 0.7 * progress from 1,500 to
    # 4,500 mph, and reach ~x1.5 by the hold. (A ratio of rpm between two speeds misled: the
    # design only gives x1.25 between 2,400 and 3,700 mph, and a still-rising spool inflated it.)
    held = (log["thrL"] > 0.86) & (log["thrL"] < 0.88) & (log["secStL"] == 3) & (t > 9.2) & (log["secSpL"] > 0)
    if held.any():
        lever_rpm = 600.0 + 3200.0 * log["secSpL"][held]
        lift = log["secL"][held] / lever_rpm
        want = 1.0 + 0.7 * np.clip((log["mph"][held] - SECOND_ON_MPH) / (4500.0 - SECOND_ON_MPH), 0.0, 1.0)
        err = np.max(np.abs(lift / want - 1))
        tally.add("second winds up with speed: x%.2f at %.0f mph on a steady lever (formula %.2f, max err %.1f%%)" % (
            np.mean(lift), np.mean(log["mph"][held]), np.mean(want), 100 * err), int(np.mean(lift) >= 1.4 and err < 0.02), 1, 1.0)
    else:
        tally.add("second winds up with speed (no steady-lever hold in the log)", 0, 1, 1.0)
    # Rumbly where it matters: the steady full-lever hold (it lights at speed, so that's where it
    # lives). Averaging in the idle under braking flattered an engine that buzzed at full power.
    hold = (log["thrL"] > 0.86) & (log["thrL"] < 0.88) & (log["secStL"] == 3) & (t > 9.2)
    if not hold.any():
        tally.add("second rumbly at full lever (no full-lever hold in the log)", 0, 1, 1.0)
        return
    # Per channel, as each ear hears it: in a mono sum the two engines' lows partly cancel at
    # their random relative phase (measured 53% mono vs 68% per channel, same capture).
    lows, cens = [], []
    for ch in (x[:, 0], x[:, 1]):
        a = ch[int((t[hold][0] + 0.2) * sr):int(t[hold][-1] * sr)]
        X = np.abs(np.fft.rfft(a * np.hanning(len(a)))) ** 2
        f = np.fft.rfftfreq(len(a), 1 / sr)
        lows.append(X[(f > 20) & (f < 150)].sum() / X[f > 20].sum())
        cens.append(np.sum(f * X) / np.sum(X))
    low, cen = float(np.mean(lows)), float(np.mean(cens))
    tally.add("second rumbly at full lever (%.0f rpm): %.0f%% under 150 Hz, centroid %.0f Hz" % (
        np.mean(log["secL"][hold]), 100 * low, cen), int(low >= 0.35 and cen <= 300), 1, 1.0)


def check_rotor(wav, tally):
    """The bass rotor (solo, second-engine run): bassy at low speed, winding up with speed, and
    stepping back once the second engine runs. It's a beating, shimmering rumble with no clean
    line to track at 3%, so its pitch is followed through where its energy sits: the spectral
    centroid has to move in octaves with the logged rotor pitch."""
    x, sr, log = load(wav)
    mono = x.mean(axis=1)
    t = log["t"]
    print("[rotor]")
    crank = np.where(log["secStL"] == 2)[0]
    run_r = np.where(log["secStR"] == 3)[0]
    if not len(crank) or not len(run_r):
        tally.add("rotor: second engine never lit in this run", 0, 1, 1.0)
        return
    crank, run_r = t[crank[0]], t[run_r[0]]

    def spec(a):
        X = np.abs(np.fft.rfft(a * np.hanning(len(a)))) ** 2
        f = np.fft.rfftfreq(len(a), 1 / sr)
        return X, f
    slow = (log["mph"] > 1) & (log["mph"] < 300) & (log["thrL"] > 0.5)
    # Bassy = the energy sits low: nearly all of it under 200 Hz (the drone's 28-80 Hz stages plus
    # their partials) and a low centroid. Per channel, as each ear hears it (see check_second).
    lows, cens = [], []
    for ch in (x[:, 0], x[:, 1]):
        X, f = spec(ch[int(t[slow][0] * sr):int(t[slow][-1] * sr)])
        lows.append(X[(f > 15) & (f < 200)].sum() / X[f > 15].sum())
        cens.append(np.sum(f * X) / np.sum(X))
    low, cen = float(np.mean(lows)), float(np.mean(cens))
    tally.add("rotor bassy below 300 mph: %.0f%% under 200 Hz, centroid %.0f Hz" % (100 * low, cen),
              int(low >= 0.85 and cen <= 160), 1, 1.0)
    w = int(0.2 * sr)
    c, pp = [], []
    for tc in np.arange(1.1, crank - 0.1, 0.05):
        X, f = spec(mono[int(tc * sr) - w // 2:int(tc * sr) + w // 2])
        c.append(np.log2(np.sum(f * X) / np.sum(X)))
        pp.append(np.log2(np.interp(tc, t, log["rotL"])))
    c, pp = np.array(c), np.array(pp)
    r = np.corrcoef(c, pp)[0, 1]
    slope = np.polyfit(pp, c, 1)[0]
    tally.add("rotor winds up with speed: brightness follows pitch (r %.3f, %.2f oct/oct over %.1f oct)" % (
        r, slope, pp.max() - pp.min()), int(r >= 0.95 and 0.75 <= slope <= 1.35), 1, 1.0)

    def lvl(t0, t1):
        a = mono[int(t0 * sr):int(t1 * sr)]
        return 10 * np.log10(np.mean(a * a) + 1e-20)
    drop = lvl(crank - 0.6, crank - 0.1) - lvl(run_r + 1.0, run_r + 2.0)
    tally.add("rotor steps back for the second engine: %.1f dB" % drop, int(drop >= 6.0), 1, 1.0)


def check_polish(v8_wav, v8_flat_wav, pops_wav, tally, twin_wav, twin_flat_wav):
    """Twin beat, rev flare and overrun pops, on the main lever run."""
    print("[polish]")
    x, sr, log = load(v8_wav)
    fx, fsr, flog = load(v8_flat_wav)
    t = log["t"]
    # The twin beat is read on the V12. Two engines beat where their sound repeats exactly, and
    # the V8 is now built not to (it misses, and its upper harmonics jitter): its level still
    # breathes, 0.6 dB against 0.2 flat, but the V12 is the layer that carries the beat.
    bx, bsr, blog = load(twin_wav)
    bfx, bfsr, _ = load(twin_flat_wav)
    hold = (blog["t"] > 8.3) & (blog["t"] < 9.9)   # both levers at 0.87, spool settled

    def breath(x, sr):
        mono = x.mean(axis=1)
        w = int(0.15 * sr)
        lv = np.array([10 * np.log10(np.mean(mono[int(q * sr) - w // 2:int(q * sr) + w // 2] ** 2)) for q in np.arange(8.3, 9.9, 0.02)])
        # the turbines light inside this hold and the V12 comes up with them: take that slope out
        q = np.arange(len(lv))
        return float(np.std(lv - np.polyval(np.polyfit(q, lv, 2), q)))
    ratio = blog["v12R"][hold] / blog["v12L"][hold]
    sd, sd_flat = breath(bx, bsr), breath(bfx, bfsr)
    tally.add("twin: right engine %.2f-%.2f%% fast, level breathes %.1f dB (flat, no detune: %.1f dB)" % (
        100 * (ratio.min() - 1), 100 * (ratio.max() - 1), sd, sd_flat),
        int(1.001 <= ratio.min() and ratio.max() <= 1.006 and sd >= 0.8 and sd_flat <= 0.6), 1, 1.0)

    # Bark: every lever stab in the blips (lever up >= 0.4 between frames)
    lev = np.minimum(log["thrL"], 0.88) / 0.88
    stabs = np.where((np.diff(lev) > 0.4) & (t[1:] > 27.0))[0] + 1
    t90s, flares = [], []
    for i in stabs:
        sel = (t >= t[i]) & (t < t[i] + 0.6)
        sp, tt = log["sL"][sel], t[sel]
        start, tgt = log["sL"][i - 1], lev[i]
        if tgt - start < 0.3:
            continue
        t90s.append(tt[np.argmax(sp >= start + 0.9 * (tgt - start))] - t[i])
        flares.append(100 * (sp.max() - tgt) / (tgt - start))
    if t90s:
        t90, flare = float(np.median(t90s)), float(np.median(flares))
        tally.add("bark: lever stabs rev to 90%% in %.2f s, flare %.0f%% (median of %d)" % (t90, flare, len(t90s)),
                  int(t90 <= 0.2 and 4 <= flare <= 20), 1, 1.0)
    else:
        tally.add("bark: no lever stabs found in the blips", 0, 1, 1.0)

    # Pops: where they fire (the counters) and what they sound like (the pops-only capture)
    px, psr, plog = load(pops_wav)
    pt = plog["t"]
    pops = plog["popsL"] + plog["popsR"]

    def fired(a, b):
        return int(np.interp(b, pt, pops) - np.interp(a, pt, pops))
    quiet = fired(0.3, 12.4) + fired(21.5, 26.5)
    lifts = [fired(12.5, 14.0), fired(27.5, 30.4)]
    m = px.mean(axis=1)

    def lv(a, b):
        s = m[int(a * psr):int(b * psr)]
        return 10 * np.log10(np.mean(s * s) + 1e-20)
    contrast = min(lv(12.5, 14.0), lv(27.5, 30.4)) - max(lv(0.3, 12.4), lv(21.5, 26.5))
    tally.add("pops: %d after the burner drop, %d through the blips, %d anywhere quiet; %.0f dB over silence" % (
        lifts[0], lifts[1], quiet, contrast), int(min(lifts) >= 3 and quiet == 0 and contrast >= 40), 1, 1.0)


def plot(wav, png):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from scipy import signal
    x, sr, log = load(wav)
    fig, axes = plt.subplots(2, 1, figsize=(13, 8), sharex=True)
    for ax, ch, side, name in ((axes[0], x[:, 0], "L", "left channel"), (axes[1], x[:, 1], "R", "right channel")):
        f, t, S = signal.spectrogram(ch, sr, nperseg=4096, noverlap=3584)
        ax.pcolormesh(t, f, 10 * np.log10(S + 1e-14), shading="auto", cmap="magma", vmin=-120, vmax=-50)
        ax.plot(log["t"], log["v8" + side] * 8 / 120, color="#7fd4ff", lw=1, label="V8 firing")
        ax.plot(log["t"], log["v12" + side] * 12 / 120, color="#9cff9c", lw=1, label="V12 firing")
        ax.plot(log["t"], log["turb" + side] * BLADE_HZ, color="#ffffff", lw=1, ls="--", label="turbine blade-pass")
        ax.set_yscale("symlog", linthresh=100)
        ax.set_ylim(30, 8000)
        ax.set_ylabel("Hz (%s)" % name)
        ax.legend(loc="upper left", fontsize=8)
    for t0, label in ((0, "idle"), (2, "rev"), (10, "burner"), (12.5, "0.5"), (15, "split L.87/R.15"),
                      (19, "idle"), (21, "L flameout"), (24, "reignite")):
        axes[0].axvline(t0, color="w", lw=0.5, alpha=0.5)
        axes[0].text(t0 + 0.1, 6000, label, color="w", fontsize=8)
    axes[1].set_xlabel("s")
    fig.suptitle("EngineAudio capture from Godot: levers -> V8 + V12 + turbine (lines: logged RPM)")
    fig.tight_layout()
    fig.savefig(png, dpi=110)
    print("plot ->", png)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", default=os.path.join(ROOT, "godot", "shots"))
    ap.add_argument("--plot", action="store_true")
    ap.add_argument("--listen", action="store_true", help="only record the Movie Maker listening copy")
    ap.add_argument("--reuse", action="store_true", help="measure the captures already in --out, without recording again")
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)
    if args.listen:
        listen(args.out)
        return
    if args.reuse:
        wavs, fails = {os.path.basename(w)[7:-4]: w for w in glob.glob(os.path.join(args.out, "engine_*.wav"))}, 0
    else:
        wavs, fails = capture(args.out)
    tally = Tally()
    for layer in ("v8", "v12", "turbine"):
        check_layer(layer, wavs[layer], wavs[layer + "_flat"], tally)
    check_turbines(wavs["turbine_run"], tally)
    check_shift(wavs["v8_run"], tally)
    check_ramjet(wavs["ramjet"], wavs["ramjet_all"], tally)
    check_second(wavs["second"], tally)
    check_rotor(wavs["rotor"], tally)
    check_polish(wavs["v8"], wavs["v8_flat"], wavs["pops"], tally, wavs["v12"], wavs["v12_flat"])
    if args.plot:
        plot(wavs["all"], os.path.join(args.out, "engine_all.png"))
    fails += sum(not ok for ok in tally.rows)
    print("ENGINE AUDIO CHECK", "PASS" if fails == 0 else "FAIL (%d)" % fails)
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()
