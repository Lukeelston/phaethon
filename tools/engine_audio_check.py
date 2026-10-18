"""EngineAudio gate: does the sound actually follow the levers?

Runs godot/tests/test_engine_audio.gd nine times in parallel: V8, V12 and turbine solo, the
same three --flat (every gain held at 1, low-pass open, so only the crossfader can move the
level), the full mix, and the second engine's own run (--profile=second) solo and mixed.
Each run records the game's master bus.
Then it measures the recordings against the RPM each run logged:
  pitch     V8/V12 firing pitch (subharmonic summation) and turbine blade-pass line, within 3%
            of the logged RPM, wherever the RPM holds steady across the window
  split     left lever 0.87, right 0.15: each channel carries its own engine on pitch, and each
            engine is at least 9 dB louder on its own side
  flameout  a dead left engine drops the pistons out of the left channel (at least 9 dB)
  relight   after the reignite, the left engine is back on pitch
  second    the second engine lights within 150 mph of second_on_mph, right side ~0.3 s after
            the left, coughs ~0.7 s before it catches, is silent before and dead after (below
            second_off_mph), its doublet pitch (rpm / 60, above 1,800 rpm) follows the lever, and it is rumbly
            at full lever: >= 35% of its energy under 150 Hz, centroid <= 300 Hz
  one tone  flat runs, slow rev: brightness doesn't pulse with band position (no more than 50
            cents or than it wanders at unrelated spacings), so a ramp is one rising tone
  steady    flat runs: each channel's 150 ms level stays within 2.5 dB of a smooth curve in RPM
            while both engines share an RPM, lever blips included. Crossfade artifacts are local
            holds of several dB
Exit 0 = every check passes on at least 90% of its windows.

  python tools/engine_audio_check.py [--out DIR] [--plot]     (--plot draws a spectrogram PNG)
  python tools/engine_audio_check.py --listen                  the listening copy only: engine_listen.wav

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
# cents: brightness may not pulse with band position more than this, or than chance. The fixed
# design measured 13-42 cents over five runs (chance 30-69, itself noisy); the stepping band
# design measured 109-198. 50 sits between with margin both ways.
MAX_SWING = 50.0


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
    for run in ["v8", "v12", "turbine", "v8_flat", "v12_flat", "turbine_flat", "all", "second", "second_all"]:
        wav = os.path.join(out_dir, "engine_%s.wav" % run)
        args = [godot_exe(), "--headless", "--path", os.path.join(ROOT, "godot"), "-s",
                "res://tests/test_engine_audio.gd", "--", "--out=" + wav.replace("\\", "/")]
        if run not in ("all", "second_all"):
            args.append("--solo=" + run.split("_")[0])
        if run.endswith("_flat"):
            args.append("--flat")
        if run.startswith("second"):
            args.append("--profile=second")
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


def seg(x, sr, t):
    i = int((t - WIN / 2) * sr)
    return x[max(0, i):i + int(WIN * sr)]


def spectrum(s, sr):
    nfft = 1 << 17
    return np.abs(np.fft.rfft(s * np.hanning(len(s)), nfft)), sr / nfft


def pitch(s, sr, f_exp):
    """Subharmonic summation (Hermes 1988) over candidates within -30%/+43% of f_exp."""
    X, df = spectrum(s, sr)
    c = f_exp * np.exp(np.linspace(np.log(0.7), np.log(1.43), 800))
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


def measure(layer, s, sr, f):
    return line(s, sr, f) if layer == "turbine" else pitch(s, sr, f)


def steady(layer, log, side, t):
    a, b = expect(layer, log, side, t - WIN / 2), expect(layer, log, side, t + WIN / 2)
    return abs(a / b - 1) < 0.03


def level_dips(x, sr, log, layer):
    """Flat runs only: each channel's 150 ms level, every 10 ms, wherever both engines sit at the
    same RPM (so a dip can't be the other engine leaving or beating), minus a smooth (cubic) fit
    against log RPM. With the gains held flat, level may still drift with RPM (the fixed muffler
    trims more as the pulses brighten), but only smoothly. A crossfade artifact is local: two
    interfering bands held 5-8 dB off for 0.3-1.2 s (measured 2026-10-17), which no cubic follows.
    Per channel, because that is what each ear gets."""
    ts = np.arange(0.4, log["t"][-1] - 0.4, 0.01)
    w = int(0.15 * sr)
    keys = ("turbL", "turbR") if layer == "turbine" else (layer + "L", layer + "R")
    a, b = np.interp(ts, log["t"], log[keys[0]]), np.interp(ts, log["t"], log[keys[1]])
    # "Same RPM" means the same to 0.05%: two engines even 0.2% apart drift through each other's
    # phase (a real twin-engine beat, ~1 s period, +-3 dB). That's the imbalance being audible,
    # not a crossfade, and it would make this check a coin toss after the reignite.
    sym = (np.abs(a / b - 1) < 0.0005) & (ts > 1.0)
    lr = np.log2(np.maximum(a[sym], 1e-3))
    out = []
    for ch in (x[:, 0], x[:, 1]):
        db = np.array([10 * np.log10(np.mean(ch[int(t * sr) - w // 2:int(t * sr) + w // 2] ** 2) + 1e-12) for t in ts[sym]])
        out.append(db - np.polyval(np.polyfit(lr, db, 3), lr))
    resid = np.concatenate(out)
    return resid, len(resid)


def timbre_swing(x, sr, log, layer):
    """Flat runs only, on the slow rev (2.6-8 s): brightness (spectral centroid, 60 ms) minus its
    smooth trend against RPM, averaged by where the RPM sits between two baked bands (5 bins).
    If each band sounds like its own tone, brightness swings with band position and a ramp
    "steps through selected tones" (measured 2026-10-17: 109 cents V8, 198 cents V12).
    A lumpy engine's brightness wanders anyway, so the same swing is also measured against
    unrelated spacings (1.6x, 2.5x, 3.1x): the noise floor. Returns (swing at the bands' own
    spacing, noise floor), or None for a single-loop layer, which has nothing to step between."""
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
    noise = [swing((np.log2(at) / np.log2(p) + o) % 1.0) for p in (1.6, 2.5, 3.1) for o in (0.0, 0.33)]
    return swing(u - np.floor(u)), float(np.median(noise))


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
        n += 1
        hits += abs(measure(layer, seg(mono, sr, t), sr, fl) / fl - 1) < 0.03
    tally.add("%s pitch follows the levers" % layer, hits, n)
    fx, fsr, flog = load(flat_wav)
    dips, n = level_dips(fx, fsr, flog, layer)
    tally.add("%s steady through crossfades (%+.1f..%+.1f dB)" % (layer, dips.min(), dips.max()),
              int((np.abs(dips) <= 2.5).sum()), n, 0.995)
    tone = timbre_swing(fx, fsr, flog, layer)
    if tone is None:
        tally.add("%s one tone through the rev (single loop)" % layer, 1, 1, 1.0)
    else:
        tally.add("%s one tone through the rev (swing %.0f cents, chance %.0f)" % (layer, tone[0], tone[1]),
                  int(tone[0] <= max(MAX_SWING, tone[1])), 1, 1.0)
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
            got, peak, prom = line_strength(seg(near, sr, t), sr, f)
            n += 1
            hits += abs(got / f - 1) < 0.03 and prom >= 12.0
            if side == "L":
                _, far_peak, _ = line_strength(seg(far, sr, t), sr, got, span=0.01)
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
    # Rumbly where it matters: the steady full-lever hold (it lights at speed, so that's where it
    # lives). Averaging in the idle under braking flattered an engine that buzzed at full power.
    hold = (log["thrL"] > 0.86) & (log["thrL"] < 0.88) & (log["secStL"] == 3) & (t > 9.2)
    if not hold.any():
        tally.add("second rumbly at full lever (no full-lever hold in the log)", 0, 1, 1.0)
        return
    a = mono[int((t[hold][0] + 0.2) * sr):int(t[hold][-1] * sr)]
    X = np.abs(np.fft.rfft(a * np.hanning(len(a)))) ** 2
    f = np.fft.rfftfreq(len(a), 1 / sr)
    low = X[(f > 20) & (f < 150)].sum() / X[f > 20].sum()
    cen = np.sum(f * X) / np.sum(X)
    tally.add("second rumbly at full lever (%.0f rpm): %.0f%% under 150 Hz, centroid %.0f Hz" % (
        np.mean(log["secL"][hold]), 100 * low, cen), int(low >= 0.35 and cen <= 300), 1, 1.0)


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
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)
    if args.listen:
        listen(args.out)
        return
    wavs, fails = capture(args.out)
    tally = Tally()
    for layer in ("v8", "v12", "turbine"):
        check_layer(layer, wavs[layer], wavs[layer + "_flat"], tally)
    check_second(wavs["second"], tally)
    if args.plot:
        plot(wavs["all"], os.path.join(args.out, "engine_all.png"))
    fails += sum(not ok for ok in tally.rows)
    print("ENGINE AUDIO CHECK", "PASS" if fails == 0 else "FAIL (%d)" % fails)
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()
