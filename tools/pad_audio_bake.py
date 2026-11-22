"""Bake the pad's mono recordings. Run python tools/pad_audio_bake.py from the checkout."""
import numpy as np
import soundfile as sf
from startup_audio_bake import ROOT, RATE, butter, cut, damp, fade, finish, full, loop, mix, pitch

OUT = ROOT / "godot/audio/pad"
# Each station keys its local call sign, followed by the same rising clearance note.
# Shared initials get a second letter. One unit is 70 ms, including the spaces between marks.
CALLS = {
    "eridanus": ".", "dunes": "-..", "glacier": "--.", "basalt": "-...",
    "mesa": "--", "coast": "-.-.", "drop": "-.. .-.", "wash": ".--",
    "frost": "..-.", "reed": ".-.", "red": ".-. -..", "needle": "-.",
    "hammer": "....", "gap": "--. .-", "helios": ".... .", "summit": "...",
    # Mount Hyperion's two bays (merged after these sixteen were made): H Y and H S.
    "hyperion": ".... -.--", "hyperion_summit": ".... ...",
}


def dispatch(code):
    # A real mechanical buzzer through a small horn. Isolate its reedy upper harmonics
    # and key them like a telegraph. The higher answering note always means cleared.
    reed = butter(cut("buzzer_bursts", 3.60, 4.03), "bandpass", (910, 2300))
    answer = pitch(reed, 1.5)
    parts = []
    start = 0
    for mark in code:
        if mark == " ":
            start += .14
            continue
        length = .07 if mark == "." else .21
        parts.append((fade(reed[:round(length * RATE)], .009, .018), start, .78))
        start += length + .07
    parts.append((fade(answer[:round(.235 * RATE)], .012, .07), start + .05, 1.0))
    return mix(*parts)


def write(name, samples):
    sf.write(OUT / (name + ".wav"), samples, RATE, subtype="PCM_16")


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    # Ground unit: two seconds of a truck's steady idle and a cooling fan, folded at the seam.
    diesel = full(butter(loop("start_truck", 3.5, 2.3), "lowpass", 650))
    fan = full(butter(loop("fan_1u", 4.0, 2.3), "bandpass", (320, 2400)))
    bed = diesel * .88 + fan * .31
    write("cart", full(bed - np.mean(bed)) * .7)

    # The collar snaps free first. The heavier plug hits the deck a little later, then bounces.
    collar = cut("solenoid_12v", 1.0, 1.12, snap=True)
    hit = full(butter(pitch(cut("sw_breaker_kyles", 1.58, 1.97), .70), "lowpass", 2400))
    ring = damp(pitch(cut("guard_zippo5", 2.16, 2.44), .76), .06, .07)
    write("lead", finish(mix((collar, 0, .62), (hit, .23, 1), (ring, .35, .39), (ring, .49, .13))))

    # Gate gearbox: contactor, electric motor under load, end-stop against the raised boom.
    contact = cut("solenoid_12v", 1.0, 1.11, snap=True)
    drive = full(butter(pitch(cut("pump_bmw", .08, 1.37, fin=.055, fout=.11), 1.27),
                        "bandpass", (180, 3600)))
    stop = full(butter(cut("relay_large", 3.57, 3.92, fout=.09), "lowpass", 3200))
    write("gate", finish(mix((contact, 0, .38), (drive, .045, .65), (stop, .985, .83))))
    for station, code in CALLS.items():
        write("clear_" + station, finish(dispatch(code)))


if __name__ == "__main__":
    main()
