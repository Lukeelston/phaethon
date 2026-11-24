"""Bake the four full-boost tear loops. Run python tools/fleet_ramjet_bake.py.

All audible material comes from the steady RS-25 test recording already credited
in godot/audio/ramjet/CREDITS.md (NASA Stennis, 2025-11-12). Times below refer
to the trimmed rs25_steady source. Each loop overlays the same shuttle roar.
"""
from pathlib import Path

import numpy as np
import soundfile as sf

import ramjet_bake as rocket

RATE = rocket.RATE
FOLD = int(.6 * RATE)
OUT = Path(__file__).resolve().parents[1] / "godot/audio/fleet"


def exhaust(at, slowdown, seconds):
    """A section of the test stand's pressure crackle at a new tape speed."""
    lead = .30
    segment = rocket.engine_crackle("rs25_steady", at, at + (seconds + lead + .1) / slowdown)
    start = round(lead * RATE)
    samples = rocket.slow(segment, slowdown)[start:start + round(seconds * RATE)]
    return samples / np.sqrt(np.mean(samples ** 2))


def shrike(seconds):
    # Close, fast nozzle. Preserve steep pressure fronts above the chest note.
    raw = exhaust(34.74, 8.2, seconds)
    dry = rocket.peaking(raw, 390, 3.8, .8)
    grit = rocket.butter(dry, "highpass", 260)
    return .83 * dry + .34 * np.tanh(2.1 * grit)


def orrery(seconds):
    # Two broad exhaust resonances trade places as the fields precess. The
    # motion changes colour without putting a pitched oscillator into the mix.
    raw = exhaust(27.8, 11.2, seconds)
    t = np.arange(len(raw)) / RATE
    phase = 2 * np.pi * .79 * t + .45 * np.sin(2 * np.pi * .19 * t)
    blend = .5 + .5 * np.sin(phase)
    low = rocket.peaking(raw, 160, 7, 1.1)
    high = rocket.peaking(raw, 510, 8, 1.25)
    return low * blend + high * (1 - blend)


def kiln(seconds):
    # Uneven exhaust packets riding the longer pressure wave. The slow drift
    # and second lobe give the thump a trailing shoulder at each discharge.
    raw = exhaust(15.35, 13.1, seconds)
    t = np.arange(len(raw)) / RATE
    phase = 2 * np.pi * 8.15 * t + 1.3 * np.sin(2 * np.pi * .56 * t)
    valve = (.5 + .5 * np.cos(phase)) ** 2
    chamber = rocket.peaking(raw, 122, 3.2, .9)
    return chamber * (.55 + .87 * valve + .12 * np.cos(phase - 1.42))


def vesper(seconds):
    # Independent jet cores through two different nozzle lengths. Their
    # mid-band edges pass one another gently over a common smooth bass.
    left = exhaust(8.22, 10.7, seconds)
    right = exhaust(38.94, 8.95, seconds)
    bed = rocket.butter(left + right, "lowpass", 200)
    left = rocket.peaking(rocket.butter(left, "bandpass", [170, 790]), 310, 3, .85)
    right = rocket.peaking(rocket.butter(right, "bandpass", [230, 970]), 575, 4, 1)
    t = np.arange(len(bed)) / RATE
    bias = .18 * np.sin(2 * np.pi * .44 * t + .55 * np.sin(2 * np.pi * .31 * t))
    return .58 * bed + (.92 + bias) * left + (.92 - bias) * right


def bake(name, recipe, duration):
    length = round(duration * RATE)
    raw = recipe(duration + FOLD / RATE)
    loop = rocket.level_out(rocket.seamless(raw, length, FOLD))
    peak = 10 ** ((rocket.LOOP_RMS_DB + rocket.TEAR_CREST_DB) / 20)
    loop = rocket.finish_loop(loop, peak)
    # Choose among eight edits of the same continuous ring so the importer's
    # boundary lies in an ordinary stretch for both brightness and dynamics.
    for offset in range(0, length, length // 8):
        candidate = np.roll(loop, offset)
        level, usual_level, brightness, usual_brightness = rocket.seam_steps(candidate)
        if (rocket.seam_ratio(candidate) < 1 and level <= max(1., usual_level)
                and brightness <= max(60., usual_brightness)):
            loop = candidate
            break
    else:
        raise ValueError(f"{name} has no clean edit")
    if not -19.5 <= rocket.rms_db(loop) <= -17.9 or np.max(np.abs(loop)) > peak + 1e-6:
        raise ValueError(f"{name} exceeds the rocket board level limits")
    path = OUT / name / "ramtear.wav"
    path.parent.mkdir(parents=True, exist_ok=True)
    sf.write(path, loop, RATE, subtype="PCM_16")
    skew, peaks, half = rocket.tear_of(loop)
    print(f"{name} {len(loop)/RATE:.2f}s, {rocket.rms_db(loop):.1f} dBFS RMS, "
          f"median {half:.0f} Hz, {peaks:.1f} peaks/s, pressure slope skew {skew:.2f}, "
          f"seam {rocket.seam_ratio(loop):.3f}")


if __name__ == "__main__":
    bake("shrike", shrike, 7.7)
    bake("orrery", orrery, 8.7)
    bake("kiln", kiln, 7.3)
    bake("vesper", vesper, 8.3)
