"""Design aid for the STARFIGHTER grand-prix circuit (track "gp").

The circuit is a list of segments: ("S", length) straights and ("L"/"R", radius, degrees) arcs,
starting at the origin heading +x, counter-clockwise overall (turning sums to +360 deg). Two
straights are left unknown and solved so the loop closes exactly. The tool checks the track never
comes within a wall gap of itself, estimates each corner's speed from STARFIGHTER's measured turn
limits, prints the segment table to paste into sim-core.js / craft_sim.gd, and plots the layout.

Usage: python tools/design_gp.py [out.png]
The sims sample the same segments themselves; this script is not part of the game.
"""
import math
import sys

WIDTH = 64.0            # track width, m (walls at +-32)
GAP = 120.0             # minimum wall-to-wall gap between non-adjacent parts of the track
STEP = 12.0             # sample spacing, m
OMEGA = 1.0             # STARFIGHTER path turn rate it can hold near the limit, rad/s (~57 deg/s)
A_LAT = 40 * 9.81       # lateral grip it can hold, m/s^2 (cap is 50 g)
V_TOP = 1200 * 0.44704  # burner top speed, m/s

# None = solved for closure (the first along x, the second along y)
SEGS = [
    ("S", None),                              # main straight, east
    ("R", 230, 90), ("S", 450), ("L", 230, 90),   # T1-T2: hard braking, drop south and back east
    ("S", 1500),
    ("L", 1100, 70),                          # T3: fast left, flat
    ("S", 700),
    ("R", 600, 40),                           # T4 kink
    ("S", 900),
    ("L", 380, 150),                          # T5: long left, diving back into the infield (heading 180+)
    ("S", 1100),
    ("R", 260, 120),                          # T6: tight right, out of the infield, heading north-east
    ("S", 700),
    ("L", 900, 30),                           # T7: fast left onto the back straight, heading north
    ("S", None),                              # back straight, north
    ("L", 500, 90),                           # T8: onto the top straight, heading west
    ("S", 5200),
    ("R", 420, 40), ("L", 420, 80), ("R", 420, 40),   # T9-11: the esses, a lift at ~900 mph
    ("S", 1400),
    ("L", 160, 180),                          # T12: the hairpin, now heading east
    ("S", 500),
    ("R", 350, 90),                           # T13: right, heading south
    ("S", 3200),
    ("L", 1300, 90),                          # T14: the sweeper onto the main straight
]


def walk(segs):
    """Sample a segment list: returns points [(x, y, seg_index)], end (x, y, heading)."""
    x = y = h = 0.0
    pts = []
    for si, s in enumerate(segs):
        if s[0] == "S":
            n = max(1, math.ceil(s[1] / STEP))
            d = s[1] / n
            for _ in range(n):
                pts.append((x, y, si))
                x += d * math.cos(h)
                y += d * math.sin(h)
        else:
            r, deg = s[1], s[2]
            sgn = 1.0 if s[0] == "L" else -1.0
            ang = math.radians(deg)
            n = max(1, math.ceil(r * ang / STEP))
            da = ang / n
            for _ in range(n):
                pts.append((x, y, si))
                # chord of the arc step: exact on the circle
                c = 2 * r * math.sin(da / 2)
                x += c * math.cos(h + sgn * da / 2)
                y += c * math.sin(h + sgn * da / 2)
                h += sgn * da
    return pts, (x, y, h)


def solve(segs):
    unknown = [i for i, s in enumerate(segs) if s[0] == "S" and s[1] is None]
    assert len(unknown) == 2
    trial = [s if s[1] is not None else ("S", 0.0) for s in segs]
    _, (ex, ey, eh) = walk(trial)
    # headings of the two unknown straights
    h = 0.0
    heads = {}
    for i, s in enumerate(trial):
        if i in unknown:
            heads[i] = h
        if s[0] != "S":
            h += math.radians(s[2]) * (1 if s[0] == "L" else -1)
    (i1, i2) = unknown
    a1 = (math.cos(heads[i1]), math.sin(heads[i1]))
    a2 = (math.cos(heads[i2]), math.sin(heads[i2]))
    det = a1[0] * a2[1] - a1[1] * a2[0]
    l1 = (-ex * a2[1] + ey * a2[0]) / det
    l2 = (-a1[0] * ey + a1[1] * ex) / det
    out = list(segs)
    out[i1] = ("S", round(l1, 3))
    out[i2] = ("S", round(l2, 3))
    return out, math.degrees(eh)


def corner_speed(r):
    return min(OMEGA * r, math.sqrt(A_LAT * r), V_TOP)


def main():
    segs, turn = solve(SEGS)
    pts, (ex, ey, eh) = walk(segs)
    length = len(pts) and sum(math.hypot(pts[(i + 1) % len(pts)][0] - pts[i][0], pts[(i + 1) % len(pts)][1] - pts[i][1]) for i in range(len(pts)))
    print(f"total turning {turn:.3f} deg, closure error {math.hypot(ex, ey):.4f} m, length {length:.0f} m, {len(pts)} samples")
    ok = abs(turn - 360) < 1e-6 and math.hypot(ex, ey) < 0.01
    for i, s in enumerate(segs):
        if s[0] == "S":
            print(f"  {i:2d} S {s[1]:9.3f}")
            if s[1] < 300:
                print("     ^ too short"); ok = False
        else:
            v = corner_speed(s[1])
            print(f"  {i:2d} {s[0]} r={s[1]:5.0f} {s[2]:4.0f} deg   ~{v / 0.44704:5.0f} mph")
    # self-clearance: centrelines of non-adjacent parts at least WIDTH + GAP apart
    n = len(pts)
    worst = (1e9, None)
    skip = int(1500 / STEP)
    for i in range(0, n, 3):
        for j in range(i + skip, n - (skip if i < skip else 0), 3):
            d = math.hypot(pts[i][0] - pts[j][0], pts[i][1] - pts[j][1])
            if d < worst[0]:
                worst = (d, (i, j))
    print(f"closest non-adjacent approach {worst[0]:.0f} m (need {WIDTH + GAP:.0f})")
    ok = ok and worst[0] >= WIDTH + GAP
    # rough lap estimate: every sample at the slower of its corner speed and braking from the next corner
    vmax = []
    for (x, y, si) in pts:
        s = segs[si]
        vmax.append(V_TOP if s[0] == "S" else corner_speed(s[1]))
    decel = 15 * 9.81
    accel = 9 * 9.81
    v = vmax[:]
    for _ in range(2):
        for i in range(n - 1, -1, -1):
            v[i] = min(v[i], math.sqrt(v[(i + 1) % n] ** 2 + 2 * decel * STEP))
        for i in range(n):
            v[i] = min(v[i], math.sqrt(v[i - 1] ** 2 + 2 * accel * STEP))
    lap = sum(STEP / max(vv, 1) for vv in v)
    print(f"ideal lap ~{lap:.1f} s, average {length / lap / 0.44704:.0f} mph, top {max(v) / 0.44704:.0f} mph")
    print("SEGMENTS:", [list(s) for s in segs])
    print("DESIGN", "OK" if ok else "NOT OK")
    if len(sys.argv) > 1:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
        fig, ax = plt.subplots(figsize=(9, 9))
        xs = [p[0] for p in pts] + [pts[0][0]]
        ys = [p[1] for p in pts] + [pts[0][1]]
        ax.plot(xs, ys, color="#333", linewidth=WIDTH / 40)
        sc = ax.scatter([p[0] for p in pts], [p[1] for p in pts], c=[vv / 0.44704 for vv in v], s=2, cmap="plasma")
        fig.colorbar(sc, ax=ax, shrink=0.6, label="ideal speed, mph")
        seen = set()
        for (x, y, si) in pts:
            s = segs[si]
            if si not in seen and s[0] != "S":
                seen.add(si)
                ax.annotate(f"{si}: r{s[1]:.0f}", (x, y), fontsize=7)
        ax.plot([0], [0], "g^", markersize=10)
        ax.set_aspect("equal")
        ax.set_title(f"GP circuit: {length / 1000:.1f} km, ideal lap {lap:.0f} s")
        fig.savefig(sys.argv[1], dpi=110)
        print("plot:", sys.argv[1])


if __name__ == "__main__":
    main()
