"""Extend anti-alias levels from the existing engine master performance.

Run after engine_bake.py when rebuilding the audio assets. Existing band boundaries
remain unchanged. Refilter the previous final levels too: they must stay safe
through the entire crossfade to the next level, not only at their own band pitch.
"""
from copy import deepcopy
import hashlib
import json
from pathlib import Path

import numpy as np
import soundfile as sf

from engine_bake import bandlimit

ROOT = Path(__file__).resolve().parents[1]
DIR = ROOT / "godot/audio/engines"
MANIFEST = DIR / "manifest.json"
# Playback pitches, plus the count of early levels whose filter range is unchanged.
LAYERS = {"v8": ([1, 2, 4, 8, 16, 32, 64], 3),
          "v12": ([1, 2, 4, 8, 16, 32, 64], 3),
          "second": ([1, 2, 4, 8, 16], 1),
          "turbine": ([1, 5, 10, 20], 1)}


def main():
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    originals = {}
    results = []
    for name, (pitches, preserved) in LAYERS.items():
        spec = manifest["layers"][name]
        bands = deepcopy(spec["bands"][:preserved])
        for band in bands:
            path = DIR / band["file"]
            originals[path] = hashlib.sha256(path.read_bytes()).hexdigest()
        master, rate = sf.read(DIR / bands[0]["file"])
        assert master.ndim == 1 and rate == 44100
        for index in range(preserved, len(pitches)):
            pitch = pitches[index]
            supported_pitch = pitches[min(index + 1, len(pitches) - 1)]
            cutoff = 20000.0 / supported_pitch
            samples = bandlimit(master, cutoff)
            path = DIR / (name + "_mip" + str(index) + ".wav")
            sf.write(path, samples, rate, subtype="PCM_16")
            written, _ = sf.read(path)
            spectrum = np.abs(np.fft.rfft(written)) ** 2
            frequencies = np.fft.rfftfreq(len(written), 1.0 / rate)
            alias_share = float(spectrum[frequencies > 20000.0 / pitch].sum() / spectrum.sum())
            assert alias_share < 1e-5, (name, pitch, alias_share)
            seam = abs(written[0] - written[-1])
            assert seam <= max(1e-4, np.abs(np.diff(written)).max() * 1.1)
            previous, _ = sf.read(DIR / bands[-1]["file"])
            rho = float(np.dot(previous, written) / (np.linalg.norm(previous) * np.linalg.norm(written)))
            assert 0.0 < rho <= 1.000001
            bands[-1]["rho_next"] = round(min(rho, 1.0), 4)
            bands.append({"file": path.name, "at": pitch * spec["rate_at"]})
            results.append({"file": path.name, "pitch": pitch, "alias_energy_share": alias_share, "correlation": rho})
        spec["bands"] = bands
        # Check the actual correlated mixes, including the old/new boundary.
        worst_transition = 0.0
        for index in range(len(bands) - 1):
            a, _ = sf.read(DIR / bands[index]["file"])
            b, _ = sf.read(DIR / bands[index + 1]["file"])
            rho = bands[index]["rho_next"]
            for t in (0.0, 0.25, 0.5, 0.75, 1.0):
                pitch = pitches[index] ** (1 - t) * pitches[index + 1] ** t
                mixed = ((1 - t) * a + t * b) / np.sqrt((1 - t) ** 2 + t ** 2 + 2 * rho * t * (1 - t))
                energy = np.abs(np.fft.rfft(mixed)) ** 2
                share = float(energy[frequencies > 20000.0 / pitch].sum() / energy.sum())
                assert share < 1e-5, (name, pitch, share)
                worst_transition = max(worst_transition, share)
        results.append({"layer": name, "worst_transition_alias_share": worst_transition})
    for path, digest in originals.items():
        assert hashlib.sha256(path.read_bytes()).hexdigest() == digest, path
    MANIFEST.write_text(json.dumps(manifest, indent=1) + "\n", encoding="utf-8")
    for path in DIR.glob("*.wav.import"):
        lines = path.read_text(encoding="utf-8").splitlines()
        assert sum(line.startswith("compress/mode=") for line in lines) == 1, path
        lines = ["compress/mode=0" if line.startswith("compress/mode=") else line for line in lines]
        path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(json.dumps({"early_levels_unchanged": len(originals), "filtered_levels": results}, indent=2))


if __name__ == "__main__":
    main()
