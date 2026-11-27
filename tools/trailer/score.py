"""The trailer's score: an original piece made here in code (NumPy and SciPy only: no samples, no recordings).
D minor at 120 beats a minute, so a bar is two seconds and the film's cuts can sit on its beats.
    python tools/trailer/score.py OUT.wav [--sections=intro:0,garage:4,start:17,flight:22,arms:35,finale:49,end:53,tail:57]
Sections are given in bars. What plays in each:
    intro    a low drone and a few plucked notes
    garage   a soft pulse in the bass, a pad, a light hat, a plucked arpeggio
    start    the beat drops out: the pad held, a heartbeat, a riser into the next section's first beat
    flight   the full beat: kick, hats, a clap on two and four, sixteenths in the bass, the arpeggio an octave up
    arms     the same, harder: the chords turn to i-VII-VI-V, the bass is driven, a tom figure every fourth bar
    finale   everything, the arpeggio doubled
    end      one hit, and its tail (to `tail`)
"""
import sys
import numpy as np
from scipy import signal
from scipy.io import wavfile

SR = 48000
BPM = 120.0
BEAT = 60.0 / BPM
BAR = 4 * BEAT
rng = np.random.default_rng(7)


def hz(note):      # MIDI note number to Hz
    return 440.0 * 2 ** ((note - 69) / 12.0)


def lp(x, f, order=2):
    return signal.sosfilt(signal.butter(order, min(f, SR * 0.45), "low", fs=SR, output="sos"), x)


def hp(x, f, order=2):
    return signal.sosfilt(signal.butter(order, f, "high", fs=SR, output="sos"), x)


def bp(x, lo, hi):
    return signal.sosfilt(signal.butter(2, [lo, min(hi, SR * 0.45)], "band", fs=SR, output="sos"), x)


def env(n, a, d, s=0.0, r=0.0, hold=None):
    """Attack to 1, decay to s (exponential), hold, release: n samples in all."""
    t = np.arange(n) / SR
    e = np.minimum(t / max(a, 1e-4), 1.0)
    e *= s + (1 - s) * np.exp(-np.maximum(t - a, 0) / max(d, 1e-4))
    if r > 0:
        e *= np.clip((n / SR - t) / r, 0, 1)
    return e


class Mix:
    def __init__(self, seconds):
        self.n = int(seconds * SR)
        self.bus = {}

    def add(self, bus, t, x, gain=1.0, pan=0.0):
        """A mono (or stereo) sound into a bus at t seconds."""
        b = self.bus.setdefault(bus, np.zeros((self.n, 2)))
        i = int(t * SR)
        if i >= self.n or i + len(x) <= 0:
            return
        if x.ndim == 1:
            x = np.stack([x * np.sqrt(0.5 * (1 - pan)), x * np.sqrt(0.5 * (1 + pan))], axis=1) * np.sqrt(2)
        m = min(len(x), self.n - i)
        b[i:i + m] += x[:m] * gain


def saw(f, n, detune=0.0, phase=None):
    t = np.arange(n) / SR
    ph = rng.random() if phase is None else phase
    return signal.sawtooth(2 * np.pi * (f * (1 + detune) * t + ph))


def kick(v=1.0):
    n = int(0.32 * SR)
    t = np.arange(n) / SR
    f = 46 + 110 * np.exp(-t / 0.035)
    x = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.11)
    x += 0.25 * hp(rng.standard_normal(n), 2500) * np.exp(-t / 0.004)
    return np.tanh(1.6 * x) * v


def clap(v=1.0):
    n = int(0.28 * SR)
    t = np.arange(n) / SR
    x = bp(rng.standard_normal(n), 900, 4200)
    e = np.exp(-t / 0.085)
    for k in (0.0, 0.011, 0.023):
        e += 0.7 * np.exp(-np.abs(t - k) / 0.004)
    return x * e * 0.35 * v + 0.25 * v * np.sin(2 * np.pi * 185 * t) * np.exp(-t / 0.05)


def hat(open_=False, v=1.0):
    n = int((0.16 if open_ else 0.045) * SR)
    t = np.arange(n) / SR
    return hp(rng.standard_normal(n), 7500, 4) * np.exp(-t / (0.055 if open_ else 0.012)) * 0.3 * v


def tom(note, v=1.0):
    n = int(0.4 * SR)
    t = np.arange(n) / SR
    f = hz(note) * (1 + 0.6 * np.exp(-t / 0.03))
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.14) * v


def bass(note, dur, bright=600.0, drive=1.0):
    n = int((dur + 0.05) * SR)
    f = hz(note)
    x = saw(f, n, 0.0, 0.0) * 0.6 + np.sign(np.sin(2 * np.pi * f * 0.5 * np.arange(n) / SR)) * 0.3
    x += np.sin(2 * np.pi * f * np.arange(n) / SR) * 0.5
    e = env(n, 0.004, dur * 0.55, 0.25, 0.03)
    # a filter that shuts as the note dies: three fixed bands cross-faded (cheap, and smooth enough)
    y = lp(x, bright * 0.5) * (1 - e) + lp(x, bright * 2.2) * e
    return np.tanh(drive * y * e) / np.tanh(drive)


def pluck(note, dur=0.35, bright=3200.0):
    n = int((dur + 0.3) * SR)
    f = hz(note)
    x = saw(f, n, 0.0015) * 0.5 + saw(f, n, -0.0015) * 0.5
    e = env(n, 0.003, dur * 0.4, 0.0, 0.05)
    return (lp(x, bright * 0.25) * (1 - e) + lp(x, bright) * e) * e


def pad(notes, dur, bright=1400.0):
    n = int((dur + 1.6) * SR)
    out = np.zeros((n, 2))
    for note in notes:
        f = hz(note)
        for ch in (0, 1):
            x = sum(saw(f, n, d) for d in (rng.normal(0, 0.003), rng.normal(0, 0.003), rng.normal(0, 0.003))) / 3
            out[:, ch] += x
    t = np.arange(n) / SR
    e = np.minimum(t / 0.7, 1.0) * np.clip((dur + 1.5 - t) / 1.5, 0, 1)
    wob = 0.5 + 0.5 * np.sin(2 * np.pi * 0.12 * t + rng.random() * 6.28)
    dark = np.stack([lp(out[:, 0], bright * 0.45), lp(out[:, 1], bright * 0.45)], axis=1)
    lite = np.stack([lp(out[:, 0], bright * 1.6), lp(out[:, 1], bright * 1.6)], axis=1)
    return (dark * (1 - wob[:, None]) + lite * wob[:, None]) * e[:, None] / len(notes)


def riser(dur):
    n = int(dur * SR)
    t = np.arange(n) / SR
    k = t / dur
    x = rng.standard_normal(n)
    bands = [bp(x, lo, lo * 1.8) for lo in (300, 700, 1600, 3600, 7000)]
    out = np.zeros(n)
    for i, b in enumerate(bands):
        out += b * np.clip(1 - np.abs(k * 4.4 - i) / 1.2, 0, 1)
    f = hz(38) * 2 ** (k * 2.0)
    out = out * 0.5 + 0.18 * lp(signal.sawtooth(2 * np.pi * np.cumsum(f) / SR), 2400)
    return out * k ** 2.2


def impact():
    n = int(4.0 * SR)
    t = np.arange(n) / SR
    f = 34 + 50 * np.exp(-t / 0.12)
    sub = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.9)
    crash = lp(rng.standard_normal(n), 900) * np.exp(-t / 0.5) * 0.8 + hp(rng.standard_normal(n), 3000) * np.exp(-t / 0.7) * 0.12
    return np.tanh(1.5 * (sub + crash))


def reverb(x, seconds=2.2, tone=4200.0):
    n = int(seconds * SR)
    t = np.arange(n) / SR
    out = np.zeros_like(x)
    for ch in (0, 1):
        ir = lp(rng.standard_normal(n), tone) * np.exp(-t / (seconds / 5.5))
        ir[: int(0.012 * SR)] = 0
        out[:, ch] = signal.fftconvolve(x[:, ch], ir, mode="full")[: len(x)]
    return out * 0.05


def delay(x, time, fb=0.42, n_taps=6):
    out = np.zeros_like(x)
    d = int(time * SR)
    for k in range(1, n_taps + 1):
        g = fb ** k
        src = x[:-d * k] if d * k < len(x) else x[:0]
        if len(src) == 0:
            break
        tap = np.zeros_like(x)
        tap[d * k:] = src[:, ::-1] if k % 2 else src      # ping-pong
        out += tap * g
    return out


def main():
    out_path = sys.argv[1]
    sec = {"intro": 0, "garage": 4, "start": 17, "flight": 22, "arms": 35, "finale": 49, "end": 53, "tail": 57}
    for a in sys.argv[2:]:
        if a.startswith("--sections="):
            for part in a.split("=", 1)[1].split(","):
                k, v = part.split(":")
                sec[k] = float(v)
    order = ["intro", "garage", "start", "flight", "arms", "finale", "end", "tail"]

    def section(bar):
        name = order[0]
        for k in order:
            if bar >= sec[k]:
                name = k
        return name

    total_bars = int(np.ceil(sec["tail"]))
    m = Mix(sec["tail"] * BAR + 1.0)
    D = 38      # D2
    prog_a = [[50, 57, 62, 65], [46, 53, 58, 62], [41, 53, 57, 60], [48, 55, 60, 64]]      # Dm  Bb  F  C
    prog_b = [[50, 57, 62, 65], [48, 55, 60, 64], [46, 53, 58, 62], [45, 52, 57, 61]]      # Dm  C  Bb  A
    roots_a = [38, 34, 41, 36]
    roots_b = [38, 36, 34, 33]
    kicks = []
    for bar in range(total_bars):
        s = section(bar)
        if s in ("end", "tail"):
            continue
        t0 = bar * BAR
        hard = s in ("arms", "finale")
        prog, roots = (prog_b, roots_b) if hard else (prog_a, roots_a)
        local = int(bar - sec[s])
        step = (local // 2) % 4
        chord, root = prog[step], roots[step]
        # the pad: a chord every two bars
        if local % 2 == 0 or bar == int(np.ceil(sec[s])):
            bright = {"intro": 700, "garage": 1100, "start": 900, "flight": 1700, "arms": 2000, "finale": 2400}[s]
            m.add("pad", t0, pad(chord, 2 * BAR if local % 2 == 0 else BAR, bright), {"intro": 0.5, "garage": 0.5, "start": 0.65, "flight": 0.55, "arms": 0.55, "finale": 0.6}[s])
        if s == "intro":
            m.add("drone", t0, lp(saw(hz(D - 12), int(BAR * SR) + 2400, 0.0), 160) * 0.5, 0.6)
            for k, (beat, note) in enumerate([(0, 62), (1.5, 69), (3, 65)] if bar % 2 == 0 else [(0.5, 74), (2.5, 69)]):
                m.add("arp", t0 + beat * BEAT, pluck(note, 0.9, 2200), 0.5, (-1) ** k * 0.4)
            continue
        if s == "start":
            m.add("drone", t0, lp(saw(hz(D - 12), int(BAR * SR) + 2400, 0.0), 180) * 0.5, 0.7)
            for beat in (0, 0.75):      # a heartbeat
                m.add("kick", t0 + beat * BEAT, kick(0.55 if beat else 0.8))
            if bar == int(sec["flight"]) - 1:
                for k in range(8):      # the last bar: sixteenths rising on the toms
                    m.add("drum", t0 + (2 + k * 0.25) * BEAT, tom(38 + k, 0.35 + 0.05 * k), 0.8, (k % 2) * 0.6 - 0.3)
            continue
        # the beat
        full = s in ("flight", "arms", "finale")
        for beat in range(4):
            if full:
                kicks.append(t0 + beat * BEAT)
                m.add("kick", t0 + beat * BEAT, kick())
                if beat in (1, 3):
                    m.add("drum", t0 + beat * BEAT, clap(1.0 if hard else 0.8), 0.9)
                m.add("hat", t0 + (beat + 0.5) * BEAT, hat(True, 0.9), 0.8, 0.2)
            elif local >= 4 and beat in (0, 2):
                kicks.append(t0 + beat * BEAT)
                m.add("kick", t0 + beat * BEAT, kick(0.6))
            if full or local >= 2:
                for sub in range(4 if full else 2):
                    m.add("hat", t0 + (beat + sub / (4.0 if full else 2.0)) * BEAT, hat(False, 0.55 + 0.25 * (sub % 2 == 0)), 0.6 if full else 0.4, -0.25)
        # the bass: eighths in the garage, sixteenths once the beat is in (the off-beats an octave up now and then)
        div = 4 if full else 2
        for k in range(4 * div):
            note = root
            if full and k % 8 in (3, 6):
                note = root + 12
            if hard and k % 16 == 15:
                note = root + 10
            if full and k % 4 == 0:
                continue      # the kick's place
            m.add("bass", t0 + k * BEAT / div, bass(note, BEAT / div * 0.9, 900 if hard else (650 if full else 380), 2.6 if hard else 1.4), 0.5 if full else 0.42)
        # the arpeggio: the chord's notes up and over, sixteenths
        if s != "garage" or local >= 4:
            up = 12 if full else 0
            shape = [0, 1, 2, 3, 2, 1, 2, 3, 0, 2, 1, 3, 2, 3, 1, 2]
            for k in range(16):
                if s == "garage" and k % 2:
                    continue
                note = chord[shape[k]] + 12 + up
                m.add("arp", t0 + k * BEAT / 4, pluck(note, 0.22, 4200 if full else 2600), 0.34 if full else 0.3, 0.5 * np.sin(k * 1.9))
                if s == "finale":
                    m.add("arp", t0 + k * BEAT / 4, pluck(note + 12, 0.18, 5200), 0.16, -0.5 * np.sin(k * 1.9))
        if hard and local % 4 == 3:
            for k, n_ in enumerate([50, 50, 45, 45, 41, 41, 38, 38]):
                m.add("drum", t0 + (2 + k * 0.25) * BEAT, tom(n_, 0.5), 0.8, 0.5 - k / 7.0)
    # risers into the beat's entries, and a hit on each
    for name, bars in (("flight", 4), ("arms", 2), ("finale", 2), ("end", 2)):
        t = sec[name] * BAR
        m.add("fx", t - bars * BAR, riser(bars * BAR), 0.55)
        m.add("hit", t, impact(), 0.9 if name in ("flight", "end") else 0.6)
    m.add("hit", sec["garage"] * BAR, impact(), 0.35)
    end_t = sec["end"] * BAR
    m.add("pad", end_t, pad([38, 50, 57, 62], 5.0, 900), 0.6)
    m.add("drone", end_t, lp(saw(hz(D - 12), int(6 * SR), 0.0), 150) * env(int(6 * SR), 0.01, 2.5, 0.0, 1.0), 0.6)
    # the mix: the pad, the bass and the arpeggio duck under each kick
    duck = np.ones(m.n)
    w = int(0.26 * SR)
    shape = 1 - 0.55 * np.exp(-np.arange(w) / (0.09 * SR))
    for t in kicks:
        i = int(t * SR)
        if i + w < m.n:
            duck[i:i + w] = np.minimum(duck[i:i + w], shape)
    z = lambda k: m.bus.get(k, np.zeros((m.n, 2)))
    arp = z("arp")
    arp = arp + delay(arp, BEAT * 0.75)
    wet = reverb(arp * 0.8 + z("pad") * 0.5 + z("drum") * 0.6 + z("hit") * 0.9 + z("fx") * 0.5)
    music = (z("pad") * 0.9 + z("bass") * 1.0 + arp * 0.9 + z("drone")) * duck[:, None]
    music += z("kick") * 0.95 + z("drum") * 0.7 + z("hat") * 0.5 + z("fx") + z("hit") + wet
    music = np.stack([hp(music[:, 0], 24), hp(music[:, 1], 24)], axis=1)
    music = np.tanh(music * 0.9)
    # fade in over the first bar and out over the tail's last two seconds
    n = len(music)
    t = np.arange(n) / SR
    music *= (np.minimum(t / 1.5, 1.0) * np.clip((n / SR - t) / 2.0, 0, 1))[:, None]
    music *= 0.89 / np.max(np.abs(music))
    wavfile.write(out_path, SR, (music * 32767).astype(np.int16))
    print("score: %.1f s, %d bars, peak %.2f, RMS %.3f" % (n / SR, total_bars, np.max(np.abs(music)), np.sqrt(np.mean(music ** 2))))


if __name__ == "__main__":
    main()
