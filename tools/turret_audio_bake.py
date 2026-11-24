"""Bake the Basilisk gun's sounds (view/gunnery.gd) into godot/audio/turret/*.wav.

Usage: python tools/turret_audio_bake.py
Synthesised (numpy only, a fixed seed: the same bytes every run), mono, 44.1 kHz, 16-bit:
  fire     a plasma emitter's shot: a hard click, a chest thump, a falling zap with some grit
  deploy   the hatch unlatching, the lift's servo winding up, the ring locking out
  stow     the same, run down, ending in the hatch's latch
  impact   a bolt striking: a crack and a hiss of thrown grit
  burst    a vehicle going up: a low boom, a roll, a crackling tail
Levels are peak-normalised per sound; the game sets their volumes (gunnery.gd's players).
"""

import wave
from pathlib import Path

import numpy as np

RATE = 44100
OUT = Path(__file__).resolve().parents[1] / "godot/audio/turret"
rng = np.random.default_rng(1729)


def t_axis(seconds):
    return np.arange(int(seconds * RATE)) / RATE


def env(t, attack, decay):
    a = np.clip(t / max(attack, 1e-5), 0, 1)
    return a * np.exp(-np.maximum(t - attack, 0) / decay)


def lowpass(x, cutoff):
    # one-pole, run twice for a gentler slope
    k = np.exp(-2 * np.pi * cutoff / RATE)
    for _ in range(2):
        y = np.empty_like(x)
        acc = 0.0
        for i, v in enumerate(x):
            acc = (1 - k) * v + k * acc
            y[i] = acc
        x = y
    return x


def highpass(x, cutoff):
    return x - lowpass(x, cutoff)


def sweep(t, f0, f1, tau):
    f = f1 + (f0 - f1) * np.exp(-t / tau)
    return np.sin(2 * np.pi * np.cumsum(f) / RATE)


def clunk(t, at, pitch=170.0, level=1.0):
    u = np.maximum(t - at, 0) * (t >= at)
    body = np.sin(2 * np.pi * pitch * u) * env(u, 0.001, 0.035)
    tick = rng.normal(0, 1, len(t)) * env(u, 0.0005, 0.006)
    ring = np.sin(2 * np.pi * pitch * 4.3 * u) * env(u, 0.001, 0.02) * 0.4
    return (body + highpass(tick, 900) * 0.8 + ring) * level * (t >= at)


def fire():
    t = t_axis(0.42)
    click = highpass(rng.normal(0, 1, len(t)), 2500) * env(t, 0.0003, 0.004) * 0.9
    thump = np.sin(2 * np.pi * np.cumsum(55 + 60 * np.exp(-t / 0.02)) / RATE) * env(t, 0.002, 0.06)
    zap = sweep(t, 2400, 260, 0.045)
    grit = 1 + 0.35 * np.sign(np.sin(2 * np.pi * 37 * t))
    zap = np.tanh(2.2 * zap * grit) * env(t, 0.001, 0.07) * 0.55
    hiss = lowpass(highpass(rng.normal(0, 1, len(t)), 1800), 7000) * env(t, 0.002, 0.05) * 0.16
    tail = lowpass(rng.normal(0, 1, len(t)), 600) * env(t, 0.01, 0.12) * 0.4
    body = np.sin(2 * np.pi * np.cumsum(140 + 120 * np.exp(-t / 0.03)) / RATE) * env(t, 0.002, 0.09) * 0.7
    # (a headset gives back little under 80 Hz: the shot's weight is put at 80-350 Hz)
    return click * 0.6 + thump * 1.4 + body + zap * 0.8 + hiss + tail


def servo(t, start, end, f0, f1):
    on = (t >= start) & (t <= end)
    u = np.clip((t - start) / (end - start), 0, 1)
    f = f0 + (f1 - f0) * u ** 0.7
    phase = 2 * np.pi * np.cumsum(f) / RATE
    tone = np.sin(phase) + 0.5 * np.sin(2 * phase) + 0.25 * np.sin(3 * phase + 0.4) + 0.12 * np.sin(5 * phase)
    fade = np.clip((t - start) / 0.05, 0, 1) * np.clip((end - t) / 0.06, 0, 1)
    hydraulic = lowpass(rng.normal(0, 1, len(t)), 900) * 0.6
    return (tone * 0.5 + hydraulic) * fade * on


def deploy():
    t = t_axis(1.35)
    return (
        clunk(t, 0.0, 210, 1.0)
        + clunk(t, 0.05, 140, 0.5)
        + servo(t, 0.08, 1.02, 95, 230)
        + clunk(t, 1.05, 120, 1.2)
        + clunk(t, 1.08, 300, 0.35)
    )


def stow():
    t = t_axis(1.35)
    return clunk(t, 0.0, 150, 0.6) + servo(t, 0.04, 1.0, 220, 90) + clunk(t, 1.02, 230, 1.1) + clunk(t, 1.06, 160, 0.6)


def impact():
    t = t_axis(0.6)
    crack = highpass(rng.normal(0, 1, len(t)), 1200) * env(t, 0.0004, 0.012)
    thud = np.sin(2 * np.pi * np.cumsum(70 + 90 * np.exp(-t / 0.015)) / RATE) * env(t, 0.002, 0.05) * 0.8
    grit = lowpass(highpass(rng.normal(0, 1, len(t)), 2500), 9000)
    grit *= env(t, 0.01, 0.16) * (0.6 + 0.4 * (rng.random(len(t)) > 0.97))
    return crack * 0.6 + thud * 1.3 + grit * 0.3


def burst():
    t = t_axis(2.6)
    boom = lowpass(rng.normal(0, 1, len(t)), 180) * env(t, 0.004, 0.45) * 3.2
    thump = np.sin(2 * np.pi * np.cumsum(34 + 50 * np.exp(-t / 0.05)) / RATE) * env(t, 0.003, 0.35) * 1.2
    roll = lowpass(rng.normal(0, 1, len(t)), 420) * env(t, 0.05, 0.8) * 1.6
    chest = np.sin(2 * np.pi * np.cumsum(70 + 80 * np.exp(-t / 0.08)) / RATE) * env(t, 0.004, 0.3) * 1.3
    pops = np.zeros(len(t))
    for _ in range(46):
        at = 0.08 + rng.random() ** 1.6 * 2.1
        u = np.maximum(t - at, 0) * (t >= at)
        pops += highpass(rng.normal(0, 1, len(t)), 1500) * env(u, 0.0003, 0.004) * (t >= at) * rng.uniform(0.2, 0.7)
    flash = highpass(rng.normal(0, 1, len(t)), 3000) * env(t, 0.0005, 0.02) * 0.35
    return boom + thump + chest + roll + pops * np.exp(-t / 1.2) * 0.4 + flash


def write(name, x, peak=0.89):
    x = np.asarray(x, dtype=float)
    x = x - np.mean(x)
    fade = np.ones(len(x))
    n = int(0.01 * RATE)
    fade[-n:] = np.linspace(1, 0, n)
    x *= fade
    x *= peak / max(1e-9, np.max(np.abs(x)))
    data = (x * 32767).astype("<i2").tobytes()
    OUT.mkdir(parents=True, exist_ok=True)
    with wave.open(str(OUT / (name + ".wav")), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(data)
    print(name, "%.2f s" % (len(x) / RATE))


if __name__ == "__main__":
    write("fire", fire(), 0.8)
    write("deploy", deploy(), 0.7)
    write("stow", stow(), 0.7)
    write("impact", impact(), 0.8)
    write("burst", burst(), 0.9)
