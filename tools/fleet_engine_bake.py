"""Bake the four pilot-craft engine performances. Run with Python 3 and NumPy.

The voice sources are original pressure pulses, rotating fields, blade passages
and seeded air turbulence. Each anti-alias level filters the same periodic take.
"""

import argparse
import json
import math
import wave
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1] / "godot/audio/fleet"
RATE = 44100
# Eight 720-degree firing cycles at 800 rpm, exactly representable at 44.1 kHz.
FRAMES = 52920
CYCLES = 8
TAU = math.tau
turn = np.arange(FRAMES) / FRAMES
freq = np.fft.rfftfreq(FRAMES, 1 / RATE)


def sine(cycles, phase=0):
    return np.sin(TAU * cycles * turn + phase)


def rms(x):
    return np.sqrt(np.mean(x * x))


def air(rng, centre, octaves):
    """A periodic, band-shaped pressure fluctuation with no duplicated endpoint."""
    spectrum = np.fft.rfft(rng.normal(size=FRAMES))
    shape = np.exp(-0.5 * (np.log2(np.maximum(freq, 1) / centre) / octaves) ** 2)
    x = np.fft.irfft(spectrum * shape, n=FRAMES)
    return x / rms(x)


def firing(rng, positions, strengths, modes, attack):
    """Circularly accumulate the exhaust pressure of each cylinder and its pipe."""
    duration = round(max(tau for _, tau, _ in modes) * 8 * RATE)
    t = np.arange(duration) / RATE
    envelope = 1 - np.exp(-t / attack)
    out = np.zeros(FRAMES)
    for rev in range(CYCLES):
        for i, (position, strength) in enumerate(zip(positions, strengths, strict=True)):
            start = round((rev + position) * FRAMES / CYCLES + rng.uniform(-5, 5))
            stretch = 1 + 0.018 * math.sin(i * 1.67) + rng.uniform(-0.006, 0.006)
            pulse = sum(gain * np.exp(-t / tau) * np.sin(TAU * hz * stretch * t) for hz, tau, gain in modes)
            pulse *= envelope * strength * rng.uniform(0.92, 1.08)
            np.add.at(out, (np.arange(duration) + start) % FRAMES, pulse)
    return out / rms(out)


def shrike(rng):
    # Closely staged intake/exhaust pulses, followed by a very short reflected
    # bark. Dry individual impulses stay audible on a quick tip-in.
    exhaust = firing(
        rng,
        [0, 0.116, 0.251, 0.376, 0.497, 0.62, 0.746, 0.874],
        [1, 0.70, 0.84, 0.76, 1.03, 0.75, 0.88, 0.72],
        [(104, 0.015, 1), (226, 0.008, 0.47), (492, 0.004, 0.38), (790, 0.002, 0.15)],
        0.0007,
    )
    intake = exhaust - 0.52 * np.roll(exhaust, round(0.0023 * RATE))
    piston = 0.63 * exhaust + 0.72 * np.tanh(1.45 * intake) + 0.09 * air(rng, 520, 0.8) * (1 + 0.6 * sine(64))
    # Compressor teeth passing a short intake bell with a separate dry induction hiss.
    # Rotor inertia keeps crank variation out of the high-order blade tone.
    rotor = TAU * 28 * turn + 0.010 * sine(3)
    compressor = 0.48 * np.sin(19 * rotor + 0.17 * np.sin(4 * rotor)) + 0.23 * np.sin(11 * rotor + 0.5)
    turbine = (
        compressor + 0.17 * np.sin(6 * rotor) + 0.18 * air(rng, 670, 1.1) * (0.83 + 0.17 * np.sin(4 * rotor))
    )
    return piston, turbine


def orrery(rng):
    # Three spatially offset coil groups. Their fields step through the rotor
    # in sequence; modulation produces a moving band of partials as it turns.
    shaft = TAU * 16 * turn + 0.018 * sine(2)
    field = np.zeros(FRAMES)
    for index, order in enumerate((5, 7, 11)):
        azimuth = index * TAU / 3
        field += (0.54 + 0.065 * np.cos(shaft + azimuth)) * np.sin(
            order * shaft + azimuth + 0.27 * np.sin(3 * shaft - azimuth)
        )
    primary = field + 0.38 * np.sin(3 * shaft + 0.14 * sine(5)) + 0.050 * air(rng, 210, 0.78)
    # Interleaved flux carriers sharing a low-order yoke resonance.
    ph = TAU * 24 * turn + 0.008 * sine(3)
    turbine = (
        0.44 * np.sin(13 * ph + 0.88 * np.sin(2 * ph))
        + 0.34 * np.sin(20 * ph + 0.67 * np.sin(3 * ph + 0.7))
        + 0.19 * np.sin(29 * ph + 0.9 * np.sin(ph))
        + 0.20 * np.sin(5 * ph)
        + 0.085 * air(rng, 530, 0.80)
    )
    return primary, turbine


def kiln(rng):
    # Six cylinders feeding two unequal headers. Firing intervals, hot-bank
    # gains, collector echo and settling times are deliberately asymmetric.
    pos = [0, 0.158, 0.340, 0.492, 0.682, 0.818]
    primary = firing(
        rng,
        pos,
        [1, 0.68, 0.91, 1.14, 0.70, 0.81],
        [(57, 0.039, 1.05), (110, 0.027, 0.68), (193, 0.016, 0.52), (364, 0.009, 0.24)],
        0.0012,
    )
    primary += 0.27 * np.roll(primary, round(0.0097 * RATE)) - 0.17 * np.roll(primary, round(0.0161 * RATE))
    primary = np.tanh(0.94 * primary) + 0.10 * air(rng, 265, 0.88) * (0.7 + 0.3 * sine(48))
    # A small turbulent power-recovery turbo is driven by the exhaust train.
    # The collector takes up individual pressure pulses. A heavy shaft keeps
    # the turbo tone steady while the exhaust underneath still has six beats.
    rotor = TAU * 35 * turn + 0.013 * sine(48) + 0.008 * sine(8)
    flutter = 1 + 0.055 * sine(48) + 0.026 * sine(24, 0.41)
    turbine = flutter * (
        0.36 * np.sin(9 * rotor) + 0.22 * np.sin(17 * rotor + 0.36 * np.sin(rotor)) + 0.22 * air(rng, 420, 1.1)
    ) + 0.21 * sine(96, 0.3)
    return primary, turbine


def vesper(rng):
    # Two ducts share one drive. Different blade counts and duct resonances
    # identify the two paths. Twin carriers a few Hz apart would cancel and
    # return several times a second, increasingly fast as playback speeds up.
    a = TAU * 18 * turn + 0.010 * sine(2)
    b = a + 0.009 * sine(3, 0.4)
    breath = air(rng, 340, 1.16)
    primary = (
        0.65 * np.sin(5 * a + 0.13 * np.sin(2 * a))
        + 0.37 * np.sin(9 * b + 0.14 * np.sin(3 * b))
        + 0.16 * np.sin(13 * a + 0.85)
        + 0.11 * np.sin(17 * b - 0.52)
        + 0.15 * breath
    )
    left = TAU * 31 * turn + 0.007 * sine(3)
    right = left + 0.008 * sine(2)
    turbine = (
        0.40 * np.sin(17 * left + 0.17 * np.sin(left))
        + 0.35 * np.sin(13 * right + 0.12 * np.sin(right))
        + 0.24 * np.sin(8 * left)
        + 0.18 * np.sin(5 * right)
        + 0.19 * air(rng, 840, 0.94)
        + 0.15 * air(rng, 245, 0.7)
    )
    return primary, turbine


def levels(master, pitches):
    spectrum = np.fft.rfft(master - np.mean(master))
    result = []
    for i in range(len(pitches)):
        cutoff = 19500 / pitches[min(i + 1, len(pitches) - 1)]
        taper = np.clip((freq - 0.78 * cutoff) / (0.22 * cutoff), 0, 1)
        samples = np.fft.irfft(spectrum * (0.5 + 0.5 * np.cos(np.pi * taper)), n=FRAMES)
        result.append(samples * (10 ** (-18 / 20) / rms(samples)))
    # Place the loop point on a modest-slope, modest-curvature sample for
    # every band at once. Rolling all levels equally preserves phase alignment.
    cost = np.zeros(FRAMES)
    for x in result:
        delta = x - np.roll(x, 1)
        cost += abs(delta) / rms(delta) + abs(delta - np.roll(delta, -1)) / rms(delta - np.roll(delta, -1))
    seam = int(np.argmin(cost))
    return [np.roll(x, -seam) for x in result]


def write_layer(folder, name, master):
    piston = name == "v8"
    pitches = (1, 2, 4, 8, 16, 32, 64) if piston else (1, 5, 10, 20)
    rate_at = 800.0 if piston else 0.25
    bands = []
    previous = None
    for i, (pitch, x) in enumerate(zip(pitches, levels(master, pitches), strict=True)):
        assert np.isfinite(x).all() and np.max(np.abs(x)) < 0.96
        pcm = np.rint(x * 32767).astype("<i2")
        path = folder / f"{name}_mip{i}.wav"
        with wave.open(str(path), "wb") as stream:
            stream.setparams((1, 2, RATE, FRAMES, "NONE", "not compressed"))
            stream.writeframes(pcm.tobytes())
        measured = pcm.astype(float) / 32767
        spectrum = np.abs(np.fft.rfft(measured)) ** 2
        safe_to = pitches[min(i + 1, len(pitches) - 1)]
        assert spectrum[freq > 20000 / safe_to].sum() / spectrum.sum() < 1e-7
        if previous is not None:
            rho = np.mean(previous * measured) / (rms(previous) * rms(measured))
            assert rho >= 0.88, (folder.name, name, i, rho)
            bands[-1]["rho_next"] = round(min(float(rho), 1), 4)
        bands.append({"file": path.name, "at": rate_at * pitch})
        previous = measured
    return {"unit": "rpm" if piston else "spool", "sync": True, "rate_at": rate_at, "bands": bands}


VOICES = {"shrike": shrike, "orrery": orrery, "kiln": kiln, "vesper": vesper}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=ROOT)
    args = parser.parse_args()
    for seed, (vehicle, voice) in enumerate(VOICES.items(), 401):
        primary, turbine = voice(np.random.default_rng(seed))
        folder = args.out / vehicle
        folder.mkdir(parents=True, exist_ok=True)
        spec = {
            name: write_layer(folder, name, master) for name, master in (("v8", primary), ("turbine", turbine))
        }
        print(f"{vehicle}: {sum(len(layer['bands']) for layer in spec.values())} phase-locked loops")
        # The other two fleet bakers write these single-speed parts. Only the
        # playback fields apply across recordings; spectral stats belong to each take.
        spec["ramtear"] = {"unit": "speed", "bands": [{"file": "ramtear.wav", "at": 1.0}]}
        shots = {"bang": "bang.wav", "pops": ["pop0.wav", "pop1.wav", "pop2.wav"]}
        (folder / "engine.json").write_text(
            json.dumps({"layers": spec, "oneshots": shots}, indent=2) + "\n", encoding="utf-8"
        )


if __name__ == "__main__":
    main()
