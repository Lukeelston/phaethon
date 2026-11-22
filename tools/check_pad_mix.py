"""Check a seated Glacier capture made by record_pad_audio.gd with --stems.

    python tools/check_pad_mix.py path/to/pad.wav path/to/godot.log
"""
import argparse
import re
from pathlib import Path

import numpy as np
import soundfile as sf


def db(value):
    return 20 * np.log10(np.maximum(value, 1e-12))


def loudest_50ms(audio, rate):
    size = round(rate * .05)
    # A moving window catches the plug's impact even when it straddles two blocks.
    energy = np.concatenate(([0.0], np.cumsum(np.mean(audio ** 2, axis=1))))
    return db(np.sqrt(np.max(energy[size:] - energy[:-size]) / size))


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("mix", type=Path)
    p.add_argument("log", type=Path)
    args = p.parse_args()
    master, rate = sf.read(args.mix, always_2d=True)
    stems = {}
    for bus in ("StartPad", "Engines"):
        path = args.mix.with_name(f"{args.mix.stem}_{bus}.wav")
        stems[bus], hz = sf.read(path, always_2d=True)
        if hz != rate or stems[bus].shape != master.shape or master.shape[1] != 2:
            raise SystemExit(f"{bus} must be a matching simultaneous stereo capture")
    markers = {label: float(t) for t, label in re.findall(
        r"^PAD MIX ([0-9.]+) ([^\r\n]+)", args.log.read_text(encoding="utf-8"), re.M)}
    drop = markers["both engines running, lead drops"]
    lift = markers["brake released, gate lifts"]
    clear = markers["gate clear, station answers"]
    idle = stems["Engines"][round((lift - 1.1) * rate):round((lift - .15) * rate)]
    baseline = loudest_50ms(idle, rate)
    peak = db(np.abs(master).max())
    print(f"Master {len(master)/rate:.2f} s, {rate} Hz stereo, peak {peak:.1f} dBFS")
    print(f"Engines at idle, loudest 50 ms stereo RMS {baseline:.1f} dBFS")
    ok = -45 < baseline < -6 and peak < -.05
    # Compare transient levels with idle and confirm panning survives the real 3D mixer.
    windows = [
        ("cart", .20, 1.30, "right", -20, -3),
        ("lead", drop - .15, drop + .68, "right", -9, 7),
        ("gate", lift + .10, clear - .08, "right", -9, 7),
        ("clearance", clear + .10, clear + 1.12, "left", -9, 7),
    ]
    for name, start, end, side, low, high in windows:
        y = stems["StartPad"][round(start * rate):round(end * rate)]
        level = loudest_50ms(y, rate)
        left, right = db(np.sqrt(np.mean(y ** 2, axis=0)))
        pan = (right - left) if side == "right" else (left - right)
        passed = low <= level - baseline <= high and pan > .4
        print(f"{name:10s} {level:5.1f} dBFS, {level-baseline:+.1f} dB re idle, "
              f"{side} {pan:+.1f} dB  {'PASS' if passed else 'FAIL'}")
        ok &= passed
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
