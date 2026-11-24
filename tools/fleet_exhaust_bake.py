"""Bake the four fleet exhaust one-shots, mono PCM, from checked-in field recordings.

Run python tools/fleet_exhaust_bake.py. The clips in tools/audio_src/startup
are CC0; Freesound artists and original recording IDs are in
godot/audio/startup/CREDITS.md. No external sample paths are needed.
"""
from pathlib import Path

import numpy as np
import soundfile as sf
from scipy.signal import resample_poly

from startup_audio_bake import RATE, butter, cut, damp, fade, full, loudest, mix, pitch, ramp

OUT = Path(__file__).resolve().parents[1] / "godot/audio/fleet"


def grain(name, at, span, speed, low, high, rise=.002, release=.018):
    """Band-limit before repitching; the recording supplies its own irregular attack."""
    take = cut(name, at, at + span, fin=rise, fout=release)
    return full(pitch(butter(take, "bandpass", [low, high]), speed))


def shrike(i, engage):
    # A short bark at the valve, then diminishing compressor flutter as pressure equalizes.
    speed = (1.02, 1.12, .92)[i]
    air = grain("air_pffft", (.386,.419,.523)[i], .114, speed, 410, 7500)
    t = np.arange(len(air)) / RATE
    phase = 2*np.pi*(48*t - 97*t*t)
    flutter = air * (.35 + .65 * (.5 + .5*np.cos(phase))**1.6)
    throat = grain("start_m6", (1.02,1.10,1.28)[i], .095, .83, 74, 1100)
    if not engage:
        return mix((throat, 0, .55), (damp(flutter,.009,.035), .004, .85))
    flare = grain("start_m6", .964, .48, .90, 65, 2100, .008, .09)
    return mix((throat,0,.70), (flare,.010,.95), (flutter,.032,.72),
               (damp(pitch(flutter,.83),.010,.06),.128,.30))


def orrery(i, engage):
    # Two physical induction contacts seat, then the valve vents into the plenum.
    strike = grain("relay_large", (2.034,3.666,8.912)[i], .17, .70, 120, 4600)
    vent = grain("air_pffft", (.404,.466,.553)[i], .17, .64, 150, 3200, .008)
    pump = grain("pump_bmw", .32 + .11*i, .34 if engage else .09, .61, 160, 1650, .024)
    if engage:
        return mix((strike,0,.80), (pitch(strike,1.35),.026,.27),
                   (pump,.025,.53), (vent,.085,.42))
    return mix((damp(strike,.003,.019),0,.40), (pump,.004,.17),
               (damp(vent,.013,.052),.014,.8))


def kiln(i, engage):
    # A bank catches in six pressure pulses. Low-passed recorded compressions
    # give each cylinder a different impulse; the overrun catches one to three.
    timing = (0, .029, .064, .104, .151, .208)
    levels = (1.0,.72,.85,.63,.67,.51)
    sources = (1.016,1.096,1.173,1.28,1.385,1.49)
    count = 6 if engage else i+1
    parts = []
    for j in range(count):
        at = sources[(2*i + j) % len(sources)]
        note = grain("start_m6", at,.071,.63+.025*(j%3),52,1550,.003,.012)
        parts.append((damp(note,.012,.041),timing[j],levels[j]))
    valve = grain("air_pffft", .407 + .043*i, .21 if engage else .09,.61,170,3600)
    parts.append((valve,.085 if engage else .009,.43))
    if engage:
        tail = grain("start_m6",1.48,.27,.71,55,580,.012,.08)
        parts.append((tail,.20,.45))
    return mix(*parts)


def vesper(i, engage):
    # Opposed bypass valves tear the same air at different blade speeds.
    # Use two *different* grains of the fan, keeping the turbulent component.
    air = grain("air_pffft",(.430,.508,.582)[i],.135,1.28,520,9200,.006,.03)
    first = grain("fan_1u",2.52+i*.23,.13,1.03,470,5300,.005,.025)
    second = grain("fan_1u",3.23+i*.19,.15,.93,520,5400,.006,.035)
    first = ramp(first,1.10,.72,.096)
    second = ramp(second,1.04,.68,.092)
    spacing = (.042,.050,.058)[i]
    parts = [(damp(air,.012,.030),0,.74),(first,.002,.38),
             (damp(pitch(air,.87),.013,.032),spacing,.47),(second,spacing,.32)]
    if engage:
        stream = grain("fan_1u",2.46,.46,.68,90,2600,.014,.13)
        parts.extend([(stream,.025,.65),(pitch(air,.75),.128,.35)])
    return mix(*parts)


def write_shot(path, samples, level):
    # Compare the loudest 50 ms with the matching stock events. A stock catch
    # measures -11.7 dB here; lift-offs range from -21 dB to -11 dB.
    samples = fade(butter(samples, "highpass", 38), .0015, .014)
    gain = 10 ** ((level - loudest(samples, .05)) / 20)
    samples *= gain
    # Round only the tallest peaks: retain body loudness without clipping when
    # the second bank joins its opposite-side partner. Measure after conversion.
    threshold = .50
    ceiling = 10**(-3/20)
    excess = np.maximum(np.abs(samples) - threshold, 0)
    rounded = threshold + (ceiling-threshold) * np.tanh(excess / (ceiling-threshold))
    samples = np.sign(samples) * np.minimum(np.abs(samples), rounded)
    samples = resample_poly(samples,147,160)
    samples *= min(1,ceiling/np.max(np.abs(samples)))
    samples[:14] *= np.linspace(0,1,14)
    samples[-44:] *= np.linspace(1,0,44)
    path.parent.mkdir(parents=True, exist_ok=True)
    sf.write(path,samples,44100,subtype="PCM_16")


if __name__ == "__main__":
    for name, voice in [("shrike",shrike),("orrery",orrery),("kiln",kiln),("vesper",vesper)]:
        write_shot(OUT/name/"bang.wav",voice(0,True),-11.7)
        for i, level in enumerate([-20.5,-16.5,-13]):
            write_shot(OUT/name/f"pop{i}.wav",voice(i,False),level)
