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
    ok = check_shade(segs, pts) and ok
    ok = check_ramps(segs, pts) and ok
    print("DESIGN", "OK" if ok else "NOT OK")
    if len(sys.argv) > 1:
        plot(sys.argv[1], segs, pts, length, lap, sf_t)


# --- the shade line and the pad (docs/superpowers/specs/2026-10-19-emergency-run-design.md) ---
# A privately owned covered STARFIGHTER line: it leaves the Descent ~9 mi before the start town,
# peels west, corkscrews up under its canopy, winds south upside down, corkscrews back and merges
# into the start town's mouth. Headings: the Descent runs south; R turns west of it.
SHADE_FROM_KM = 14.5              # where it leaves: this far up the Descent from the start town's mouth
SHADE_W = 120.0                   # its width, m (tighter than a town's 140)
SHADE_JZ = 120                    # junction zones: the samples at each end that share the loop's road
SHADE_SEGS = [
    ("R", 1200, 40, "sf"), ("S", 500, 0, "sf"), ("L", 1200, 40, "sf"),   # peel away west: 600 m clear by sample ~112
    ("S", 1500, 0, "sf"),                                                # the corkscrew in, then the canopy
    ("R", 600, 30, "sf"), ("S", None, 0, "sf"),                          # the canopy's winding middle: out south-west ...
    ("L", 350, 70, "sf"), ("S", 700, 0, "sf"),                           # ... an S-bend ...
    ("R", 300, 40, "sf"), ("S", 600, 0, "sf"),
    ("L", 500, 30, "sf"), ("S", None, 0, "sf"),                          # ... and back south-east, still west of the loop
    ("R", 450, 30, "sf"),
    ("S", 1500, 0, "sf"),                                                # the corkscrew out
    ("L", 1200, 40, "sf"), ("S", 500, 0, "sf"), ("R", 1200, 40, "sf"),   # merge into the town's mouth
]
CORKSCREW = 110                   # samples (1.32 km): 180 deg in >= 2.2 s at 1,200 mph, <= 82 deg/s
CANOPY_H = SHADE_W / 2 + 2.0      # the canopy's underside above the ground, m (view only): the 120 m road
                                  # stands 120 m tall on edge mid-corkscrew, so its centre must be up here by then
# The dawn (the emergency run's clock), from tools/tune_dawn.js: the front's heading (deg, the way
# it travels) and when it passes the start line's point (s into the job). sync_eridanus.py writes them.
# The covered ramps (Luke, 2026-10-19: "a 'receiving' and 'outgoing' onramp ... such that the
# vehicle can reach speed inside of a structure before being exposed to light"): on the loop at
# each end of each town, RAMP_MI long: SPEEDCRAFT reaches 4,000 mph from 1,200 on full lever in
# 3.9 mi, and full brakes take it from 4,000 to 1,250 in 4.1 mi (tools: the range, straight).
RAMP_MI = 4.0
RAMPS = None   # [[first, last], ...] main samples (design_ramps)
DAWN_DIR_DEG = 143
DAWN_T0 = 156.7


def wrap(a):
    return math.atan2(math.sin(a), math.cos(a))


def walk_h(segs, x=0.0, y=0.0, h=0.0):
    """dg.walk from (x, y, h), keeping each sample's tangent heading: [(x, y, h)], end (x, y, h)."""
    out = []
    for s in segs:
        if s[0] == "S":
            n = max(1, math.ceil(s[1] / STEP))
            d = s[1] / n
            for _ in range(n):
                out.append((x, y, h))
                x += d * math.cos(h)
                y += d * math.sin(h)
        else:
            sgn = 1.0 if s[0] == "L" else -1.0
            ang = math.radians(s[2])
            n = max(1, math.ceil(s[1] * ang / STEP))
            da = ang / n
            for _ in range(n):
                out.append((x, y, h))
                c = 2 * s[1] * math.sin(da / 2)
                x += c * math.cos(h + sgn * da / 2)
                y += c * math.sin(h + sgn * da / 2)
                h += sgn * da
    return out, (x, y, h)


def main_samples(segs, pts):
    return walk_h(as_plain(segs))[0]


def solve_open(segs, start, end):
    """Two unknown straights (None) sized so the walk from `start` ends on `end`'s point."""
    unknown = [i for i, s in enumerate(segs) if s[0] == "S" and s[1] is None]
    assert len(unknown) == 2
    trial = [(s[0], 0.0, s[2], s[3]) if s[1] is None else s for s in segs]
    _, (ex, ey, _) = walk_h(as_plain(trial), *start)
    h = start[2]
    heads = {}
    for i, s in enumerate(trial):
        if i in unknown:
            heads[i] = h
        if s[0] != "S":
            h += math.radians(s[2]) * (1 if s[0] == "L" else -1)
    i1, i2 = unknown
    a1 = (math.cos(heads[i1]), math.sin(heads[i1]))
    a2 = (math.cos(heads[i2]), math.sin(heads[i2]))
    dx, dy = end[0] - ex, end[1] - ey
    det = a1[0] * a2[1] - a1[1] * a2[0]
    l1 = (dx * a2[1] - dy * a2[0]) / det
    l2 = (a1[0] * dy - a1[1] * dx) / det
    assert l1 > 300 and l2 > 300, f"solve_open: straights {l1:.0f}, {l2:.0f} m"
    out = list(segs)
    out[i1] = ("S", round(l1, 3), 0, segs[i1][3])
    out[i2] = ("S", round(l2, 3), 0, segs[i2][3])
    return out


def mouth(segs, pts, which):
    """The start town's mouth: the last speed-loop -> town step round the lap."""
    assert which == "start"
    for i in range(len(pts) - 1, 0, -1):
        if segs[pts[i][2]][3] == "sf" and segs[pts[i - 1][2]][3] == "sp":
            return i
    raise ValueError("no mouth")


def design_shade(segs, pts):
    """SHADE (the branch's spec, sample indices on the main track) and PAD_I."""
    main = main_samples(segs, pts)
    join = mouth(segs, pts, "start")
    frm = join - round(SHADE_FROM_KM * 1000 / STEP)
    solved = solve_open(SHADE_SEGS, main[frm], main[join])
    b, _ = walk_h(as_plain(solved), *main[frm])
    n = len(b)
    peel = sum(max(1, math.ceil((s[1] * math.radians(s[2]) if s[0] != "S" else s[1]) / STEP)) for s in solved[:3])
    c_in = (peel, peel + CORKSCREW, 0.0, 180.0)
    c_out = (n - peel - CORKSCREW, n - peel, 180.0, 0.0)
    shade = {"name": "shade", "from": frm, "join": join, "segs": [list(s) for s in solved], "width": SHADE_W,
             "covered": [peel + CORKSCREW // 2, n - 1], "roll": [list(c_in), list(c_out)], "jz": SHADE_JZ}
    # the pad: the middle of the lake town's last straight, heading out to the loop
    lake_exit = max(si for si, s in enumerate(segs) if s[3] == "sf" and s[0] == "S" and si < 20)
    first = next(i for i, p in enumerate(pts) if p[2] == lake_exit)
    run = sum(1 for p in pts if p[2] == lake_exit)
    return shade, first + run // 2


def walk_branch(shade, main):
    return walk_h(as_plain([tuple(s) for s in shade["segs"]]), *main[shade["from"]])


def min_clearance(bpts, main, main_w):
    """Wall-to-wall gap (m) between these branch samples and the loop's road (main_w: its widths)."""
    cell = 1000.0
    grid = {}
    for i, p in enumerate(main):
        grid.setdefault((int(p[0] // cell), int(p[1] // cell)), []).append(i)
    best = 1e9
    for p in bpts[::2]:
        cx, cy = int(p[0] // cell), int(p[1] // cell)
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                for i in grid.get((cx + dx, cy + dy), []):
                    q = main[i]
                    d = math.hypot(p[0] - q[0], p[1] - q[1]) - main_w[i] / 2 - SHADE_W / 2
                    best = min(best, d)
    return best


def self_clearance(bpts, skip=250):
    """Wall-to-wall gap (m) between non-adjacent parts of the branch."""
    best = 1e9
    for i in range(0, len(bpts), 4):
        for j in range(i + skip, len(bpts), 4):
            best = min(best, math.hypot(bpts[i][0] - bpts[j][0], bpts[i][1] - bpts[j][1]) - SHADE_W)
    return best


def straight_run_around(segs, pts, i):
    s = segs[pts[i][2]]
    return s[1] if s[0] == "S" else 0.0


def branch_len(b, end):
    pts = b + [end]
    return sum(math.hypot(pts[k + 1][0] - pts[k][0], pts[k + 1][1] - pts[k][1]) for k in range(len(b)))


def design_ramps(segs, pts):
    """The covered ramps: [[first, last]] main samples, RAMP_MI along the loop from each town's
    exit (outgoing) and up to each town's mouth (receiving), in lap order."""
    n = len(pts)
    mode = [segs[p[2]][3] for p in pts]
    walk = lambda i, j: math.hypot(pts[j % n][0] - pts[i % n][0], pts[j % n][1] - pts[i % n][1])
    out = []
    for i in range(n):
        if mode[i] == mode[i - 1]:
            continue
        acc, k = 0.0, 0
        if mode[i] == "sp":   # an exit: outgoing, from here on
            while acc < RAMP_MI * 1609.344:
                acc += walk(i + k, i + k + 1)
                k += 1
            out.append([i, i + k - 1])
        else:                 # a mouth: receiving, up to here
            while acc < RAMP_MI * 1609.344:
                k += 1
                acc += walk(i - k, i - k + 1)
            out.append([i - k, i - 1])
    return out


def check_ramps(segs, pts):
    global RAMPS
    RAMPS = design_ramps(segs, pts)
    mode = [segs[p[2]][3] for p in pts]
    assert len(RAMPS) == 4, RAMPS
    for a, b in RAMPS:
        assert all(mode[i % len(pts)] == "sp" for i in range(a, b + 1)), "a ramp on the loop only"
    for (a0, a1), (b0, b1) in zip(RAMPS, RAMPS[1:]):
        assert a1 < b0, "ramps apart"
    if SHADE:   # the shade line leaves the loop outside the start town's receiving ramp
        last = [r for r in RAMPS if r[1] == SHADE["join"] - 1][0]
        assert SHADE["from"] + SHADE["jz"] < last[0], (SHADE["from"], last)
    print("RAMPS OK", RAMPS)
    return True


def check_shade(segs, pts):
    """The shade line and the medical pad (docs/superpowers/specs/2026-10-19-emergency-run-design.md)."""
    global SHADE, PAD_I
    SHADE, PAD_I = design_shade(segs, pts)
    main = main_samples(segs, pts)
    b, end = walk_branch(SHADE, main)
    j = main[SHADE["join"]]
    assert math.hypot(end[0] - j[0], end[1] - j[1]) < 0.01 and abs(wrap(end[2] - j[2])) < 1e-4, "closes onto the join"
    assert SHADE["join"] == mouth(segs, pts, "start"), "runs into the start town's mouth"
    clear = min_clearance(b[SHADE["jz"]:-SHADE["jz"]], main, [width(segs[p[2]]) for p in pts])
    assert clear >= 300.0, f"300 m clear of the loop outside the junctions ({clear:.0f})"
    own = self_clearance(b)
    assert own >= 300.0, f"300 m clear of itself between non-adjacent parts ({own:.0f})"
    assert all(r[1] - r[0] >= 100 for r in SHADE["roll"]), "corkscrews >= 1.2 km: <= 90 deg/s at 1,200 mph"
    assert SHADE["covered"][1] == len(b) - 1, "covered all the way into the town"
    assert segs[pts[PAD_I][2]][3] == "sf" and straight_run_around(segs, pts, PAD_I) >= 600.0, "the pad: on a lake-town straight"
    print("SHADE OK", round(branch_len(b, end) / 1609.344, 1), "mi;",
          f"clear of the loop by {clear:.0f} m; pad at sample {PAD_I}")
    return True


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
