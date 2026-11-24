"""Bake the four pilot racers' staged starts, ignition catches and cockpit calls.

Run python tools/fleet_startup_bake.py. Physical layers come from the checked-in
CC0 solenoid, BMW M6, fuel pump, air valve and Dremel recordings
credited in godot/audio/startup/CREDITS.md. The modal strikes, coil resonance,
blade passages and firing order below are original, deterministic DSP. The game
only plays the rendered mono 48 kHz PCM files. The stock bank is read-only.
"""


import numpy as np
import soundfile as sf
from scipy import signal

import startup_audio_bake as field

RATE = field.RATE
OUT = field.ROOT / "godot/audio/fleet"
CRAFT = ("shrike", "orrery", "kiln", "vesper")


def clock(seconds):
    return np.arange(round(seconds * RATE)) / RATE


def phase(frequency):
    return 2 * np.pi * np.cumsum(frequency) / RATE


def noise(t, seed, low, high):
    white = np.random.default_rng(seed).normal(size=t.size)
    return field.full(field.butter(white, "bandpass", (low, high)))


def shape(x, attack, release):
    return field.fade(x, attack, release)


def recorded(name, at, duration, speed=1, low=40, high=6800):
    x = field.cut(name, at, at + duration, fin=.002, fout=.025)
    return field.full(field.butter(field.pitch(x, speed), "bandpass", (low, high)))


def crank_train(t, speed, firing=False):
    # Six unequal compression or exhaust pulses. Both rate and intensity vary
    # over the firing cycle. The pressure body and manifold ring are broadband.
    weights = [.90, .69, .97, .80, .64, 1.0]
    angles = [0, .93, 2.02, 2.92, 4.05, 5.06]
    output = np.zeros_like(t)
    turn = 0.0
    while turn < len(t) / RATE:
        shots = speed * ((30 + 18*np.exp(-turn/.25)) if firing else (12 + 8*min(turn, 1)))
        for angle, weight in zip(angles, weights):
            at = turn + angle / shots
            i = round(at * RATE)
            if i >= t.size:
                break
            local = t[:min(t.size-i, round(.14 * RATE))]
            thump = np.sin(2*np.pi*(56*local + .57*(1-np.exp(-local/.014))))*np.exp(-local/.032)
            ring = .32*np.sin(2*np.pi*181*local)*np.exp(-local/.019)
            output[i:i+len(local)] += weight*(thump+ring)*np.minimum(local/.0018, 1)
        turn += 6 / shots
    return output


def machine(craft, t, side, firing):
    speed = 1.0 if side == 0 else .961
    seed = 142 + side + CRAFT.index(craft)*17 + 2*int(firing)
    ramp = 1-np.exp(-t/(.15 if firing else .40))
    fall = np.exp(-t/.57) if firing else np.ones_like(t)
    if craft == "shrike":
        gear = phase(speed*(78 + 53*ramp + 41*fall*int(firing)))
        mesh = np.sin(gear*5 + .45*np.sin(gear)) + .31*np.sin(gear*9)
        air = noise(t, seed, 650, 5750) * (.65+.35*np.cos(gear))
        return .25*mesh + air*.42
    if craft == "orrery":
        # A passing exciter rotates past three coils. Their beat speeds up with the rotor.
        rotor = phase(speed*(3 + 8*ramp))
        coil = phase(speed*(98+64*ramp+24*fall*int(firing)))
        return sum(gain*(.58+.42*np.cos(rotor+k*2*np.pi/3)) *
                   np.sin(mult*coil + .31*np.sin(rotor))
                   for k, (mult, gain) in enumerate([(1,.51),(2.007,.35),(3.014,.19)])) + .14*noise(t, seed, 120, 2800)
    if craft == "kiln":
        return crank_train(t, speed, firing) + .3*noise(t, seed, 90, 1550)
    duct = phase(speed*(135 + 131*ramp + 73*fall*int(firing)))
    second = phase(speed*(139 + 132*ramp + 64*fall*int(firing)))
    airflow = noise(t, seed, 280, 4100)
    return .26*np.sin(duct) + .20*np.sin(second) + .12*np.sin(2*duct) + .67*airflow


def starter(craft, side):
    speed = 1 - .035*side
    contact = recorded("solenoid_12v", .97, .155, speed)
    t = clock(.84)
    prime_signal = machine(craft, t, side, False)
    if craft == "kiln":
        # Only the contactor and fuel pressure build before the starter engages.
        prime_signal = recorded("pump_bmw", .025, 1.08, .78*speed)[:len(t)]
    motor = recorded("whir_dremel", .14+.035*side, 1.3, .93*speed, 240, 5400)
    prime = shape(.36*prime_signal + .16*motor[:len(t)], .16, .09)
    t = clock(.83)
    crank = machine(craft, t, side, False)
    pinion = recorded("start_m6", .22, .63, speed, 320, 4900)
    amounts = {"shrike": (.68, .76), "orrery": (.98, .13), "kiln": (.90, .32), "vesper": (.85, .10)}
    signature, mechanical = amounts[craft]
    throw = field.mix((shape(crank, .012, .055), 0, signature), (pinion, .01, mechanical))
    return field.mix((contact, 0, .16), (prime, .012, .55),
                     (contact, field.PRIME_S-.011, .30), (throw, field.PRIME_S, 1.0))


def catch(craft):
    length = {"shrike": .95, "orrery": 1.58, "kiln": 1.35, "vesper": 1.48}[craft]
    t = clock(length)
    body = machine(craft, t, 0, True)
    body = shape(body*np.exp(-t/(length*.48)), .005, .13)
    if craft == "shrike":
        return field.mix((body, 0, .53), (field.damp(recorded("start_m6", .91, .81, 1.18), .13, .16), 0, .85))
    if craft == "kiln":
        return field.mix((body, 0, 1.0), (field.damp(recorded("start_m6", .95, 1.04, .71, 55, 900), .18, .26), .014, .48))
    if craft == "orrery":
        whir = recorded("whir_dremel", .52, 1.25, .69, 350, 1800)
        return field.mix((body, 0, 1), (field.damp(whir, .08, .42), .025, .20))
    pressure = recorded("air_pffft", .206, .83, .77, 180, 3600)
    return field.mix((body, 0, .91), (field.damp(pressure, .12, .25), .018, .47))


def chime(craft):
    # Pitched resonators are struck briefly and decay independently. The intervals
    # and number of strikes identify which cockpit woke up, even over the fans.
    voices = {
        "shrike": ([(0, 860), (.11, 1289)], [.99, 2.03, 3.95], [.16, .065, .035]),
        "orrery": ([(0, 422), (.23, 633), (.48, 842)], [1, 2.68, 4.13], [.34, .21, .15]),
        "kiln": ([(0, 236), (.27, 314)], [1, 1.56, 3.42], [.23, .13, .09]),
        "vesper": ([(0, 618), (.18, 777)], [1, 1.006, 2], [.33, .30, .10]),
    }
    notes, ratios, decays = voices[craft]
    strikes = []
    for at, hz in notes:
        t = clock(1.22)
        voice = sum(gain*np.sin(2*np.pi*hz*r*t)*np.exp(-t/tau)
                    for gain, r, tau in zip([.7,.29,.13], ratios, decays))
        strikes.append((shape(voice, .016 if craft == "vesper" else .0025, .08), at, 1))
    return field.mix(*strikes)


def level(x):
    # K-weighted peak 400 ms window at 48 kHz, matching startup_audio_bake.
    k = signal.lfilter(*field.K2, signal.lfilter(*field.K1, x))
    power = np.cumsum(np.r_[0., k*k])
    n = min(k.size, round(.4*RATE))
    return 10*np.log10(np.max(power[n:] - power[:-n])/n + 1e-12)


def bake():
    for craft in CRAFT:
        directory = OUT / craft
        directory.mkdir(parents=True, exist_ok=True)
        effects = {"starter_0": starter(craft, 0), "starter_1": starter(craft, 1),
                   "catch": catch(craft), "chime": chime(craft)}
        for name, samples in effects.items():
            reference, _ = sf.read(field.OUT / (name+".wav"))
            signal_out = field.finish(samples)
            # Match each legacy one-shot, retaining the mixer's engine and cockpit faders.
            delta = level(reference) - level(signal_out)
            if delta > 20*np.log10(.86/max(abs(signal_out))):
                signal_out = field.finish(field.limit(signal_out, max(2., delta + 1)))
            gain = min(10**((level(reference)-level(signal_out))/20), .86/max(abs(signal_out)))
            signal_out *= gain
            sf.write(directory/(name+".wav"), signal_out, RATE, subtype="PCM_16")
            print(f"{craft}/{name} {len(signal_out)/RATE:.2f}s mix delta {level(signal_out)-level(reference):+.1f}dB")


if __name__ == "__main__":
    bake()
