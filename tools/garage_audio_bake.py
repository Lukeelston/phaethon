"""Build the garage foley from the project's CC0 field recordings.

Run python tools/garage_audio_bake.py. See godot/audio/startup/CREDITS.md for
the original fan, motor, air valve, button, breaker and contactor recordings.
"""
from pathlib import Path

import numpy as np
from scipy import signal
from scipy.ndimage import median_filter
import soundfile as sf

from startup_audio_bake import RATE, butter, cut, damp, fade, full, mix, pitch, src

DEST = Path(__file__).resolve().parents[1] / "godot/audio/workshop"
OUTPUT_RATE = 32000


def fold(samples, seconds, overlap):
    """Join two points inside a stationary recording at equal power."""
    n, cross = round(seconds * RATE), round(overlap * RATE)
    assert len(samples) >= n + cross
    result = samples[:n].copy()
    angle = np.linspace(0.0, np.pi / 2, cross)
    result[:cross] = samples[n:n + cross] * np.cos(angle) + result[:cross] * np.sin(angle)
    return result


def fan_air(samples):
    """Separate the recorded airflow from the narrow blade and bearing tones."""
    freq, power = signal.welch(samples, RATE, nperseg=8192)
    air_floor = median_filter(power, size=35)
    gain = np.sqrt(np.minimum(1.0, 2.7 * air_floor / np.maximum(power, 1e-14)))
    spectrum = np.fft.rfft(samples)
    spectrum *= np.interp(np.fft.rfftfreq(len(samples), 1 / RATE), freq, gain)
    return np.fft.irfft(spectrum, n=len(samples))


def write_wav(name, samples, loop=False, peak=.52):
    samples = full(samples - np.mean(samples)) * peak
    if loop:
        # Give the resampling filter real neighbouring samples across the seam.
        n = round(len(samples) * OUTPUT_RATE / RATE)
        resampled = signal.resample_poly(np.tile(samples, 3), 2, 3)[n:2 * n]
    else:
        resampled = signal.resample_poly(fade(samples, .0015, .018), 2, 3)
    sf.write(DEST / (name + ".wav"), resampled, OUTPUT_RATE, subtype="PCM_16")


def ventilation():
    # A full-speed server rotor, slowed to an extraction fan; the rattle lives
    # at the grille. Across the hall only the low, diffuse return reaches us.
    rotor = pitch(src("fan_1u")[int(2.58 * RATE):int(6.44 * RATE)], .49)
    air = fan_air(rotor)
    grille = full(butter(air, "bandpass", (75, 470))) * .66
    grille += full(butter(air, "bandpass", (450, 2200))) * .54
    grille += full(butter(rotor, "bandpass", (310, 1000))) * .13
    room = full(butter(air, "bandpass", (44, 210))) * .70
    # A second, more distant fan wets the room bed. Its different recording
    # phase and speed keep the localized intake distinct inside the same hall.
    distant = pitch(src("fan_1u")[int(2.32 * RATE):int(6.35 * RATE)], .45)
    room += .45 * full(butter(fan_air(distant[:len(room)]), "bandpass", (135, 670)))
    write_wav("intake", fold(grille, 6.7, .85), loop=True)
    write_wav("hall_air", fold(room, 7.0, .72), loop=True)


def step(index, heel, toe, speed, roll, scuff):
    # The two impulses are separately recorded. A low-pass removes the metal
    # chatter: a heavy enclosed heel meets first, then the forefoot loads.
    source, contact = heel
    sole = cut(source, contact, contact + .23, snap=True)
    sole = pitch(sole, speed)
    heel_body = full(butter(sole, "bandpass", (48, 212)))
    heel_body += .37 * full(butter(sole, "bandpass", (200, 710)))
    heel_body = damp(heel_body, .019, .038)
    source, contact = toe
    toe_body = cut(source, contact, contact + .16, snap=True)
    toe_body = damp(butter(pitch(toe_body, speed + .19), "bandpass", (100, 1280)), .011, .027)
    tread = cut("air_pffft", scuff, scuff + .13)
    tread = damp(fade(butter(tread, "bandpass", (580, 2900)), .017, .020), .027, .025)
    dry = mix((full(heel_body), 0.0, 1.0), (full(toe_body), roll, .41),
              (full(tread), roll - .012, .12))
    wall = butter(dry, "lowpass", 1250)
    write_wav("sole_%d" % index, mix((dry, 0.0, 1.0), (wall, .019, .070), (wall, .042, .042)))


def door():
    # Stable section of the powered tool and a rolling fan bearing. The game
    # ramps this loop up, reverses or cuts it on the door's own movement clock.
    gearbox = pitch(src("whir_dremel")[int(8.0 * RATE):int(10.0 * RATE)], .47)
    rail = pitch(src("fan_1u")[int(3.0 * RATE):int(5.4 * RATE)], .68)
    drive = full(butter(gearbox[:len(rail)], "bandpass", (95, 1550)))
    drive += .29 * full(butter(rail, "bandpass", (125, 2450)))
    write_wav("door_motor", fold(drive, 2.7, .34), loop=True)
    catch = damp(butter(pitch(cut("relay_large", 3.57, 3.86, snap=True), .68),
                        "bandpass", (70, 2400)), .023, .042)
    seal = damp(fade(butter(cut("air_pffft", .51, .71), "lowpass", 1800), .016, .028), .015, .035)
    write_wav("door_seal", mix((full(seal), 0.0, .19), (full(catch), .033, .91)))


def wheel_bearing():
    # Keep the uneven roll of a working pump spindle, without the electrical
    # note or the switch-off at its end. This part is turned by hand.
    spindle = pitch(src("prime_pump")[int(1.04 * RATE):int(4.18 * RATE)], .72)
    grain = fan_air(spindle)
    body = full(butter(grain, "bandpass", (140, 820)))
    race = full(butter(grain, "bandpass", (710, 1900)))
    write_wav("wheel_bearing", fold(body + .54 * race, 3.1, .46), loop=True)


def main():
    DEST.mkdir(parents=True, exist_ok=True)
    ventilation()
    # Different takes, loading rates and heel-to-ball roll, rather than six
    # pitch shifts of the same transient.
    contacts = [
        (("btn_heavy", .11), ("sw_breaker_kyles", 1.64), .53, .047, .55),
        (("sw_breaker_kyles", .20), ("sw_heavy_metal", 5.59), .57, .043, .68),
        (("relay_large", 3.57), ("sw_breaker_kyles", .20), .52, .061, .48),
        (("sw_breaker_kyles", 1.64), ("btn_heavy", .11), .49, .051, .59),
        (("relay_large", 5.79), ("sw_heavy_metal", 17.85), .55, .056, .50),
        (("sw_heavy_metal", 18.31), ("btn_heavy", .11), .48, .038, .62),
    ]
    for index, take in enumerate(contacts, 1):
        step(index, *take)
    door()
    wheel_bearing()


if __name__ == "__main__":
    main()
