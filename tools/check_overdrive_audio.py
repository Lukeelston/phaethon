"""Measure real solo V8/V12 recordings from test_overdrive_audio.gd.

Usage: python tools/check_overdrive_audio.py /absolute/path/to/captures.json
The Godot test must first run with --capture-only --out-dir=/absolute/path.
This checker uses PCM pitch, not AudioStreamPlayer's reported pitch scale.
"""
import json
import math
import pathlib
import sys

import numpy as np
import soundfile as sf

from engine_audio_check import pitch


def main():
    records = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
    failures = []
    measured = {}
    for record in records:
        layer = record["layer"]
        ratio = float(record["speed_ratio"])
        data, rate = sf.read(record["wav"], dtype="float64", always_2d=True)
        expected = float(record["target_rpm"]) * {"v8": 8, "v12": 12}[layer] / 120.0
        notes = []
        for center in (0.5, 0.8, 1.1):
            start, stop = int((center - 0.15) * rate), int((center + 0.15) * rate)
            notes.append(pitch(data[start:stop, 0], rate, expected))
        actual = float(np.median(notes))
        error = abs(actual / expected - 1.0)
        rms_db = 10.0 * math.log10(max(float(np.mean(data * data)), 1e-20))
        peak_db = 20.0 * math.log10(max(float(np.max(np.abs(data))), 1e-10))
        checks = {
            "pitch matches requested engine RPM": error < 0.03,
            "all measured windows remain on pitch": all(abs(note / expected - 1.0) < 0.03 for note in notes),
            "captured audible unclipped signal": len(data) / rate >= 1.3 and rms_db > -60.0 and peak_db < -0.01,
        }
        for label, passed in checks.items():
            if not passed:
                failures.append(f"{layer} x{ratio:g}: {label}")
        measured.setdefault(layer, {})[ratio] = actual
        print(f"{layer} x{ratio:g}: measured {actual:.1f} Hz, target {expected:.1f} Hz, "
              f"error {error:.2%}, RMS {rms_db:.1f} dBFS, peak {peak_db:.1f} dBFS")
    for layer in ("v8", "v12"):
        notes = measured.get(layer, {})
        if not all(ratio in notes for ratio in (1.2, 2.0, 3.0, 4.0, 8.0)):
            failures.append(f"{layer}: missing speed captures")
            continue
        ordered = [notes[ratio] for ratio in (1.2, 2.0, 3.0, 4.0, 8.0)]
        if not all(b > a * 1.01 for a, b in zip(ordered, ordered[1:])):
            failures.append(f"{layer}: recorded pitch plateaus or falls")
        if not notes[3.0] - notes[2.0] > notes[4.0] - notes[3.0] > 0.0:
            failures.append(f"{layer}: equal-speed pitch increments do not taper")
    for failure in failures:
        print("FAIL", failure)
    print(f"OVERDRIVE AUDIO CAPTURE {'FAIL' if failures else 'PASS'} "
          f"({len(records)} captures, {len(failures)} failures)")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
