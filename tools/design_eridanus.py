"""Design aid for Eridanus, the dual-purpose circuit (track "eridanus"): a huge lap in two modes.

Luke (2026-10-18): "a much much larger course where you switch to speedcraft to get as fast as
possible on long straights and sweeping curves, then brake back down, flip back to starfighter
and run the turns" - the Nordschleife + GP, or the full Circuit de la Sarthe, at podracer scale.

  speed loop    SPEEDCRAFT (the range's handling: 15 g grip, ~4,450 mph on the lever, 5,400 on
                the burner). Straights of 10-30 km and sweepers sized for its grip: flat out at
                ~4,000 mph needs r ~22 km. 400 m wide, banked 3 deg (2026-10-19; was 240, flat).
  GP section    STARFIGHTER (50 g, ~1,200 mph): the turns, r 300-900, 140 m wide, banked 10 deg (was 15).
  the switch    STARFIGHTER only engages below ~1,250 mph, so every way into the GP section is
                a long braking zone (~9 km from 4,000 mph), with countdown boards.

Phaethon fell into the river Eridanus; his sisters became poplars weeping amber on its banks.
The GP section is the river town; the speed loop runs out across the valley's plains.

Same method as tools/design_gp.py (walk / solve reused): straights ("S", m) and arcs ("L"/"R",
radius m, degrees), counter-clockwise from the origin heading +x, two straights solved so it
closes. Each segment also names its mode ("sf" / "sp"), and so its width and corner model.

Usage: python tools/design_eridanus.py [out.png]
"""
import math
import sys
import os

sys.path.insert(0, os.path.dirname(__file__))
import design_gp as dg

STEP = dg.STEP
G = 9.81
MPH = 0.44704
W_SF, W_SP = 140.0, 400.0         # track width in each mode's sections, m
GAP = 200.0                       # wall-to-wall gap between non-adjacent parts
SF_TOP, SP_TOP = 1200 * MPH, 4450 * MPH   # STARFIGHTER burner top; SPEEDCRAFT lever top
SF_A, SP_A = 40 * G, 11 * G       # lateral grip each can sustain (SPEEDCRAFT: ~14 g on a full lever split, ~10 on a brake)
SF_OMEGA = 1.0                    # STARFIGHTER path turn rate it can hold, rad/s

# (kind, length or radius, degrees, mode)
SEGS = [
    # --- the GP section, part one: the river town (STARFIGHTER) ---
    ("S", None, 0, "sf"),                        # start / finish along the river, east
    ("L", 450, 90, "sf"),                        # T1
    ("S", 900, 0, "sf"),
    ("R", 300, 90, "sf"),                        # T2
    ("S", 700, 0, "sf"),
    ("L", 600, 60, "sf"), ("R", 600, 60, "sf"),  # T3-T4: the poplar esses
    ("S", 1500, 0, "sf"),                        # out of town over the bridge: flip to SPEEDCRAFT
    # --- the speed loop (SPEEDCRAFT) ---
    ("S", 9000, 0, "sp"),                        # the Long Straight (the Mulsanne), east ...
    ("L", 30000, 8, "sp"), ("R", 30000, 8, "sp"),   # ... its flat-out kink ...
    ("S", 8000, 0, "sp"),                        # ... and on
    ("L", 22000, 90, "sp"),                      # the Great Sweeper: flat out
    ("S", 11000, 0, "sp"),                       # north along the lake: brake, flip to STARFIGHTER
    # --- the Lake Village (STARFIGHTER) ---
    ("L", 500, 50, "sf"),                        # V1
    ("S", 600, 0, "sf"),
    ("R", 320, 70, "sf"),                        # V2
    ("S", 500, 0, "sf"),
    ("L", 400, 80, "sf"),                        # V3
    ("S", 1500, 0, "sf"),                        # out of the village: flip to SPEEDCRAFT
    # --- the speed loop again ---
    ("S", 4000, 0, "sp"),                        # the plains straight ...
    ("R", 15000, 30, "sp"), ("S", 1000, 0, "sp"), ("L", 15000, 30, "sp"),   # ... the plains esses, ~2,900 mph, a breath between
    ("S", 3000, 0, "sp"),
    ("L", 20000, 30, "sp"),                      # the Long Left
    ("S", 13100, 0, "sp"),                       # the back straight, west
    ("L", 16000, 90, "sp"),                      # the Hill Curve, ~3,300 mph
    ("S", None, 0, "sp"),                        # the Descent, south: its last ~10 km the braking zone, flip back to STARFIGHTER
    # --- the GP section, part two ---
    ("L", 700, 60, "sf"),                        # T5: the first turn after the braking zone
    ("S", 900, 0, "sf"),
    ("R", 350, 80, "sf"),                        # T6
    ("S", 800, 0, "sf"),
    ("L", 300, 100, "sf"),                       # T7: the mill
    ("S", 1000, 0, "sf"),
    ("R", 500, 50, "sf"),                        # T8
    ("S", 1200, 0, "sf"),
    ("L", 900, 60, "sf"),                        # T9 onto the start straight
]


def width(seg):
    return W_SF if seg[3] == "sf" else W_SP


def vlimit(seg):
    if seg[0] == "S":
        return SF_TOP if seg[3] == "sf" else SP_TOP
    r = seg[1]
    if seg[3] == "sf":
        return min(SF_OMEGA * r, math.sqrt(SF_A * r), SF_TOP)
    return min(math.sqrt(SP_A * r), SP_TOP)


def as_plain(segs):
    return [("S", s[1]) if s[0] == "S" else (s[0], s[1], s[2]) for s in segs]


def main():
    turn_net = sum((s[2] if s[0] == "L" else -s[2]) for s in SEGS if s[0] != "S")
    print(f"net turning {turn_net} (need 360)")
    solved, turn = dg.solve(as_plain(SEGS))
    segs = [(s[0], sv[1], s[2], s[3]) for s, sv in zip(SEGS, solved)]
    pts, (ex, ey, eh) = dg.walk(as_plain(segs))
    n = len(pts)
    length = sum(math.hypot(pts[(i + 1) % n][0] - pts[i][0], pts[(i + 1) % n][1] - pts[i][1]) for i in range(n))
    sf_len = sum(STEP for p in pts if segs[p[2]][3] == "sf")
    print(f"total turning {turn:.3f} deg, closure {math.hypot(ex, ey):.4f} m, length {length / 1000:.1f} km "
          f"(GP section {sf_len / 1000:.1f} km, speed loop {(length - sf_len) / 1000:.1f} km), {n} samples")
    ok = abs(turn - 360) < 1e-6 and math.hypot(ex, ey) < 0.01
    for i, s in enumerate(segs):
        tag = "SF" if s[3] == "sf" else "SP"
        if s[0] == "S":
            print(f"  {i:2d} {tag} S {s[1]:10.1f}")
            if s[1] < 400:
                print("     ^ too short"); ok = False
        else:
            print(f"  {i:2d} {tag} {s[0]} r={s[1]:6.0f} {s[2]:4.0f} deg  ~{vlimit(s) / MPH:5.0f} mph")
    worst = (1e9, None)
    skip = int(2500 / STEP)
    for i in range(0, n, 6):
        for j in range(i + skip, n - (skip if i < skip else 0), 6):
            d = math.hypot(pts[i][0] - pts[j][0], pts[i][1] - pts[j][1])
            need = (width(segs[pts[i][2]]) + width(segs[pts[j][2]])) / 2 + GAP
            if d - need < worst[0]:
                worst = (d - need, (i, j, d, need))
    print(f"closest non-adjacent approach: {worst[1][2]:.0f} m (need {worst[1][3]:.0f}), margin {worst[0]:.0f} m")
    ok = ok and worst[0] >= 0
    v = [vlimit(segs[si]) for (_, _, si) in pts]
    for _ in range(3):
        for i in range(n - 1, -1, -1):
            dec = (18 if segs[pts[i][2]][3] == "sp" else 15) * G
            v[i] = min(v[i], math.sqrt(v[(i + 1) % n] ** 2 + 2 * dec * STEP))
        for i in range(n):
            acc = (14 if segs[pts[i][2]][3] == "sp" else 9) * G
            v[i] = min(v[i], math.sqrt(v[i - 1] ** 2 + 2 * acc * STEP))
    lap = sum(STEP / max(vv, 1) for vv in v)
    sf_t = sum(STEP / max(v[i], 1) for i in range(n) if segs[pts[i][2]][3] == "sf")
    print(f"ideal lap ~{lap:.0f} s ({lap / 60:.1f} min): GP section {sf_t:.0f} s, speed loop {lap - sf_t:.0f} s; "
          f"average {length / lap / MPH:.0f} mph, top {max(v) / MPH:.0f} mph")
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    print(f"footprint {(max(xs) - min(xs)) / 1000:.1f} x {(max(ys) - min(ys)) / 1000:.1f} km")
    print("SEGMENTS:", [list(s) for s in segs])
    print("DESIGN", "OK" if ok else "NOT OK")
    if len(sys.argv) > 1:
        plot(sys.argv[1], segs, pts, length, lap, sf_t)


def plot(path, segs, pts, length, lap, sf_t):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    fig, axes = plt.subplots(1, 2, figsize=(16, 8.5), gridspec_kw={"width_ratios": [1.45, 1]})
    for ax, zoom in zip(axes, [False, True]):
        ax.set_facecolor("#cfe3b8")
        for mode, col, lw in [("sp", "#2a6fbf", 3.2), ("sf", "#c0392b", 2.2)]:
            xs, ys = [], []
            for (x, y, si) in pts + [pts[0]]:
                if segs[si][3] == mode:
                    xs.append(x / 1000)
                    ys.append(y / 1000)
                else:
                    if xs:
                        ax.plot(xs, ys, color=col, linewidth=lw, solid_capstyle="round")
                    xs, ys = [], []
            if xs:
                ax.plot(xs, ys, color=col, linewidth=lw, solid_capstyle="round")
        seen = set()
        for (x, y, si) in pts:
            s = segs[si]
            if si in seen or s[0] == "S":
                continue
            seen.add(si)
            if zoom == (s[3] == "sf"):
                label = f"r{s[1] / 1000:.0f} km ~{vlimit(s) / MPH:.0f}" if s[3] == "sp" else f"r{s[1]:.0f} ~{vlimit(s) / MPH:.0f}"
                ax.annotate(label, (x / 1000, y / 1000), fontsize=7, xytext=(4, 4), textcoords="offset points")
        ax.plot(0, 0, "^", color="#22aa22", markersize=10)
        ax.set_aspect("equal")
        ax.set_xlabel("km")
        if zoom:
            sx = [p[0] / 1000 for p in pts if segs[p[2]][3] == "sf"]
            sy = [p[1] / 1000 for p in pts if segs[p[2]][3] == "sf"]
            ax.set_xlim(min(sx) - 0.8, max(sx) + 0.8)
            ax.set_ylim(min(sy) - 0.8, max(sy) + 0.8)
            ax.set_title(f"the GP section (STARFIGHTER, red): {sf_t:.0f} s of the lap")
        else:
            ax.set_title(f"ERIDANUS: {length / 1000:.0f} km lap, ideal ~{lap / 60:.1f} min\n"
                         f"blue = speed loop (SPEEDCRAFT, 400 m wide), red = GP section (STARFIGHTER, 140 m)")
    fig.tight_layout()
    fig.savefig(path, dpi=100)
    print("plot:", path)


if __name__ == "__main__":
    main()
