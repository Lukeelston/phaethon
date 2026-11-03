"""Design aid for the Network (track "network"): a country of highways, interchanges and cities.

docs/superpowers/specs/2026-10-19-network-design.md. Phase 1, the mesh:
- three highways east-west and three north-south on the 100/300/500 km lines, 25-575 km, straight
  for 45 km either side of each crossing, symmetric S-bends between (arc +t, straight m, arc -2t,
  straight m, arc +t: a mirror image about its middle, so it comes back onto its line);
- at each crossing the north-south highway flies over (the view's height, NET_HEIGHTS) and four
  two-way quadrant ramps join the two, each a 90 deg arc of R_RAMP starting tangent to one
  highway OFF m off its centreline on the quadrant's side and ending tangent to the other;
- five cities beside a crossing's east-west highway: each city's road is a bypass off it, a
  symmetric S (arc BY_DEG out into the quadrant, straight, arc 2 x BY_DEG back, straight, arc BY_DEG
  onto the highway again) whose far arc is the city (STARFIGHTER, its terminal at the apex). A
  bypass can be entered from either direction on its highway (a road's start only going up it, its
  end only going down it: a road from one highway to another could be entered from two of the four
  ways in);
- at each highway end a turnaround: a bulb (arc right a, arc left 180 + 2a, arc right a) leaving
  the highway on one side and coming back on the other, the highway's end just past the split.
Phase 3, jumps and the ground (Luke: "taking a massive interchange and using it as a ramp to jump 2
miles and 1500' up to the entrance of the next ramp"):
- four jump sets, one at each of four crossings, on the right of the way they're taken: a launch
  spur leaves the highway JL_LEAVE before the crossing, slides out to JL_LAT, and its last JL_KICK
  rises (a parabola, so the pull is even: 12 g at 4,000 mph) to a lip at JL_ANG, JL_LIP short of
  the crossing. Two miles on (JUMP_GAP) and 1,500 ft above the lip, a catch deck JC_W wide starts
  on the trajectory of JUMP_REF (3 m under it): its window's low end, since at these speeds gravity
  barely bends the line (faster arrives higher, the deck's lock reaches JC_REACH up for it; slower
  arrives under its lip and drops). The deck pulls out level over JC_PULL, crosses the
  interchange high, comes down to the ground by JC_DOWN past the crossing and merges back;
- an on-ramp from the open ground for each city: it starts ON_OUT out on the city's side, short of
  the crossing on the far side from its bypass, and S-bends in onto the highway (missing a jump
  drops you to the ground: the dash points you to the nearest);
- heights are keys [sample, m, slope] with Hermite cubics between (zero slopes: the old smoothstep),
  real in both sims now (the deck lock: tools/sync_network.py).
Roads are sampled exactly as the sims sample them (NET_STEP: straights in equal steps, arcs in
exact chords, a last point at the end). Junction zones are found by walking: a road's end samples
whose corridor overlaps its parent's (plus a margin), against the parent's nearest samples.

Prints the roads, the junctions, the checks and NETWORK DESIGN OK. --plot [out.png] draws it.
tools/sync_network.py writes it into both sims. Not part of the game.
"""
import math
import sys

import numpy as np

STEP = 24.0                       # NET_STEP, m
KM = 1000.0
LINES = [100 * KM, 300 * KM, 500 * KM]
H0, H1 = 25 * KM, 575 * KM        # each highway's extent along its axis
ZONE = 45 * KM                    # straight either side of a crossing
S_R = 45 * KM                     # S-bend arcs (4,000 mph needs 30 km at 11 g)
S_DEG = [16.0, -13.0, 20.0, -15.0, 14.0, -18.0, 17.0, -19.0, 21.0, -14.0, 13.0, -20.0]   # per span, signs alternate sides
W_HWY, W_RAMP, W_CITY = 400.0, 200.0, 200.0
OFF = 100.0                       # a ramp's start: its centreline this far off the highway's, on its side
R_RAMP = 12 * KM                  # quadrant ramps and the city roads' turns (2,500 mph at 11 g)
BY_FAR = 43 * KM                  # a city's bypass leaves its highway this far from the crossing
BY_R, BY_DEG, BY_M = 7 * KM, 60.0, 3.5 * KM   # its arcs and straights: ~10 km out, ~28 km along
CITY_OUT = 3 * KM                 # the city's centre: this far past the bypass's apex
R_BULB = 6 * KM                   # turnarounds (1,800 mph at 11 g)
BULB_BACK = 1600.0                # the bulb leaves this far before the highway's end
FLY_H, FLY_FLAT, FLY_END = 120.0, 3 * KM, 9 * KM   # the flyover: 120 m, flat for +-3 km, down by 9 km
JZ_MARGIN = 10                    # samples past the overlap in each junction zone
GAP = 300.0                       # clear between roads outside their junction zones and crossings
UP = 30.0                         # ... or this far apart in height (a deck over a road)
G = 9.81
MPH = 0.44704
JUMP_GAP = 3218.7                 # 2 miles, lip to catch deck
JUMP_UP = 457.2                   # 1,500 ft
JL_ANG = 8.5                      # the lip's angle, deg (4,000 mph: 2 mi and 1,500 ft up in 1.8 s)
JL_LEAVE, JL_LIP, JL_KICK, JL_LAT = 32 * KM, 13 * KM, 4 * KM, 800.0
JUMP_REF = 3000.0                 # mph: the slowest that lands (the catch deck's lip is on its line)
JC_W, JC_REACH, JC_PULL = 400.0, 40.0, 5 * KM
JC_FLAT, JC_DOWN, JC_MERGE = 14 * KM, 28 * KM, 38 * KM   # level to, down by, merged by (past the crossing)
JUMPS = [   # highway (E/N index), crossing (i, j), the way it's taken (+1 up its samples)
    ("E", 1, (1, 1), 1),
    ("N", 1, (1, 0), 1),
    ("E", 2, (1, 2), -1),
    ("N", 0, (0, 1), -1),
]
ON_OUT, ON_R, ON_AT = 4 * KM, 12 * KM, 34 * KM   # on-ramps: out from the highway, their S, start short of the crossing
CITIES = [   # name, biome, crossing (i, j) on (LINES x, LINES y), quadrant (qx, qy)
    ("ERIDANUS", "verdant", (1, 1), (1, 1)),
    ("DUNES", "desert", (0, 2), (-1, 1)),
    ("GLACIER", "ice", (2, 2), (1, 1)),
    ("BASALT", "basalt", (0, 0), (-1, -1)),
    ("MESA", "mesa", (2, 0), (1, -1)),
]


def walk(segs, x, y, h):
    """The sims' sampling: points before each step, then the end point. -> (pts [(x, y)], end pose)."""
    pts = []
    for s in segs:
        if s[0] == "S":
            n = max(1, math.ceil(s[1] / STEP))
            d = s[1] / n
            for _ in range(n):
                pts.append((x, y))
                x += d * math.cos(h)
                y += d * math.sin(h)
        else:
            r, sn, ang = s[1], (1.0 if s[0] == "L" else -1.0), math.radians(s[2])
            n = max(1, math.ceil(r * ang / STEP))
            da = ang / n
            c = 2 * r * math.sin(da / 2)
            for _ in range(n):
                pts.append((x, y))
                x += c * math.cos(h + sn * da / 2)
                y += c * math.sin(h + sn * da / 2)
                h += sn * da
    pts.append((x, y))
    return pts, (x, y, h)


def hermite(keys, i):
    """Height at (fractional) sample i: Hermite cubics between keys [sample, m, slope], 0 outside."""
    for k in range(len(keys) - 1):
        a, b = keys[k], keys[k + 1]
        if a[0] <= i <= b[0]:
            n = max(1, b[0] - a[0])
            u = (i - a[0]) / n
            d = n * STEP
            u2, u3 = u * u, u * u * u
            return ((2 * u3 - 3 * u2 + 1) * a[1] + (u3 - 2 * u2 + u) * d * a[2]
                    + (-2 * u3 + 3 * u2) * b[1] + (u3 - u2) * d * b[2])
    return 0.0


class Road:
    def __init__(self, name, kind, x, y, hdeg, width, segs):
        self.name, self.kind, self.width, self.segs = name, kind, width, segs
        self.keys = []      # height keys [sample, m, slope]
        self.role = ""      # "launch" (its end is a lip), "catch" (a deck that catches jumps), "on" (from the open ground)
        self.x0, self.y0, self.hdeg = x, y, hdeg
        pts, self.end = walk(segs, x, y, math.radians(hdeg))
        self.p = np.array(pts)
        d = np.diff(self.p, axis=0)
        L = np.hypot(d[:, 0], d[:, 1])
        t = d / L[:, None]
        eh = self.end[2]
        self.t = np.vstack([t, [math.cos(eh), math.sin(eh)]])
        self.len = np.append(L, STEP)
        self.N = len(self.p)
        # per-sample mode: 1 SPEEDCRAFT, 0 STARFIGHTER
        self.mode = np.ones(self.N, dtype=int)
        i = 0
        for s in segs:
            n = max(1, math.ceil((s[1] if s[0] == "S" else s[1] * math.radians(s[2])) / STEP))
            if s[3] == "sf":
                self.mode[i:i + n] = 0
            i += n

    def h(self, i):
        return hermite(self.keys, i)

    def nearest(self, q):
        """Nearest sample index and signed lateral offset (left +) of point q."""
        d = np.hypot(self.p[:, 0] - q[0], self.p[:, 1] - q[1])
        i = int(np.argmin(d))
        n = (-self.t[i, 1], self.t[i, 0])
        lat = (q[0] - self.p[i, 0]) * n[0] + (q[1] - self.p[i, 1]) * n[1]
        return i, lat, float(d[i])


def s_bend(D, deg):
    """A symmetric S covering D forward: [arc deg, straight m, arc -2 deg, straight m, arc deg]."""
    t = math.radians(abs(deg))
    m = (D - 4 * S_R * math.sin(t)) / (2 * math.cos(t))
    assert m > 1000, f"S-bend: straight {m:.0f} m"
    a, b = ("L", "R") if deg > 0 else ("R", "L")
    return [(a, S_R, abs(deg), "sp"), ("S", m, 0, "sp"), (b, S_R, 2 * abs(deg), "sp"), ("S", m, 0, "sp"), (a, S_R, abs(deg), "sp")]


def highway(name, axis, line, spans):
    """axis 'x': runs west-east at y = line; 'y': south-north at x = line."""
    segs = [("S", LINES[0] + ZONE - H0, 0, "sp")]
    for k in range(2):
        segs += s_bend(LINES[k + 1] - LINES[k] - 2 * ZONE, spans[k])
        segs.append(("S", 2 * ZONE if k == 0 else H1 - LINES[2] + ZONE, 0, "sp"))
    if axis == "x":
        return Road(name, "highway", H0, line, 0.0, W_HWY, segs)
    return Road(name, "highway", line, H0, 90.0, W_HWY, segs)


def heading_deg(dx, dy):
    return math.degrees(math.atan2(dy, dx))


def build():
    roads = []
    ew, ns = [], []
    span = iter(S_DEG)
    for k, yl in enumerate(LINES):
        ew.append(len(roads))
        roads.append(highway(f"E{k + 1}", "x", yl, [next(span), next(span)]))
    for k, xl in enumerate(LINES):
        ns.append(len(roads))
        roads.append(highway(f"N{k + 1}", "y", xl, [next(span), next(span)]))
    joins = []   # (child road, which end 0/1, parent road)
    # quadrant ramps
    for i, X in enumerate(LINES):
        for j, Y in enumerate(LINES):
            for qx in (-1, 1):
                for qy in (-1, 1):
                    turn = "R" if qx * qy > 0 else "L"
                    r = Road(f"R{i}{j}{'E' if qx > 0 else 'W'}{'N' if qy > 0 else 'S'}", "ramp",
                             X + qx * (R_RAMP + OFF), Y + qy * OFF, 180.0 if qx > 0 else 0.0, W_RAMP,
                             [(turn, R_RAMP, 90.0, "sp")])
                    joins += [(len(roads), 0, ew[j]), (len(roads), 1, ns[i])]
                    roads.append(r)
    # cities
    cities = []
    for name, biome, (i, j), (qx, qy) in CITIES:
        X, Y = LINES[i], LINES[j]
        turn, back = ("R", "L") if qx * qy > 0 else ("L", "R")
        segs = [(turn, BY_R, BY_DEG, "sp"), ("S", BY_M, 0, "sp"), (back, BY_R, 2 * BY_DEG, "sf"),
                ("S", BY_M, 0, "sp"), (turn, BY_R, BY_DEG, "sp")]
        r = Road(name.title(), "city", X + qx * BY_FAR, Y + qy * OFF, 180.0 if qx > 0 else 0.0, W_CITY, segs)
        sf = np.where(r.mode == 0)[0]
        term = int((sf[0] + sf[-1]) // 2)
        cx, cy = r.p[term, 0], r.p[term, 1] + qy * CITY_OUT
        assert abs(r.end[1] - (Y + qy * OFF)) < 0.5, f"{name}'s bypass misses its highway by {r.end[1] - (Y + qy * OFF):.2f} m"
        cities.append((name, biome, cx, cy, len(roads), term))
        joins += [(len(roads), 0, ew[j]), (len(roads), 1, ew[j])]
        roads.append(r)
    # turnarounds
    ca = (OFF + R_BULB) / (2 * R_BULB)
    alpha = math.degrees(math.acos(ca))
    for hi in ew + ns:
        H = roads[hi]
        for end in (0, 1):
            if end == 1:
                px, py = H.p[-1]
                u = H.t[-1]
            else:
                px, py = H.p[0]
                u = -H.t[0]
            nl = (-u[1], u[0])
            sx, sy = px - BULB_BACK * u[0] - OFF * nl[0], py - BULB_BACK * u[1] - OFF * nl[1]
            r = Road(f"T{H.name}{'+' if end else '-'}", "turn", sx, sy, heading_deg(u[0], u[1]), W_RAMP,
                     [("R", R_BULB, alpha, "sp"), ("L", R_BULB, 180.0 + 2 * alpha, "sp"), ("R", R_BULB, alpha, "sp")])
            joins += [(len(roads), 0, hi), (len(roads), 1, hi)]
            roads.append(r)
    # jump sets
    jumps = []
    for axis, li, (ci, cj), d in JUMPS:
        H = roads[(ew if axis == "E" else ns)[li]]
        X, Y = LINES[ci], LINES[cj]
        fx, fy = ((1.0, 0.0) if axis == "E" else (0.0, 1.0))
        fx, fy = fx * d, fy * d                  # the way it's taken
        rx, ry = fy, -fx                         # its right
        hdg = heading_deg(fx, fy)
        th = math.degrees(math.acos(1.0 - (JL_LAT - OFF) / (2 * S_R)))
        s_len = 2 * S_R * math.sin(math.radians(th))
        # the launch spur: out to JL_LAT on the right (an S: right then left), straight to the lip
        x0, y0 = X - fx * JL_LEAVE + rx * OFF, Y - fy * JL_LEAVE + ry * OFF
        st = JL_LEAVE - JL_LIP - s_len
        L = Road(f"J{len(jumps)}", "jump", x0, y0, hdg, W_RAMP,
                 [("R", S_R, th, "sp"), ("L", S_R, th, "sp"), ("S", st, 0, "sp")])
        L.role = "launch"
        m_lip = math.tan(math.radians(JL_ANG))
        k0 = L.N - 1 - round(JL_KICK / STEP)
        h_lip = (L.N - 1 - k0) * STEP * m_lip / 2.0   # a parabola from level: the even pull
        L.keys = [[k0, 0.0, 0.0], [L.N - 1, h_lip, m_lip]]
        joins.append((len(roads), 0, roads.index(H)))
        roads.append(L)
        # the catch deck, two miles on: on JUMP_REF's line, 3 m under it
        v = JUMP_REF * MPH
        c2 = 1.0 / (1.0 + m_lip * m_lip)        # cos^2 of the lip's angle
        hc = h_lip + JUMP_GAP * m_lip - G * JUMP_GAP ** 2 / (2 * v * v * c2) - 3.0
        mc = m_lip - G * JUMP_GAP / (v * v * c2)
        lx, ly = L.p[-1]
        cx0, cy0 = lx + fx * JUMP_GAP, ly + fy * JUMP_GAP
        along = JC_MERGE - s_len + JL_LIP - JUMP_GAP   # catch start (crossing - JL_LIP + gap) to the S
        C = Road(f"K{len(jumps)}", "jump", cx0, cy0, hdg, JC_W,
                 [("S", along, 0, "sp"), ("L", S_R, th, "sp"), ("R", S_R, th, "sp")])
        C.role = "catch"
        ip = round(JC_PULL / STEP)
        top = hc + ip * STEP * mc / 2.0          # the pull-out: a parabola to level
        u_c0 = -JL_LIP + JUMP_GAP                # the deck's start, from the crossing
        i_flat = round((JC_FLAT - u_c0) / STEP)
        i_down = round((JC_DOWN - u_c0) / STEP)
        C.keys = [[0, hc, mc], [ip, top, 0.0], [i_flat, top, 0.0], [i_down, 0.0, 0.0]]
        joins.append((len(roads), 1, roads.index(H)))
        roads.append(C)
        jumps.append((len(roads) - 2, len(roads) - 1, JUMP_REF, h_lip, top))
    # on-ramps from the open ground, one a city
    onramps = []
    for k, (name, biome, (i, j), (qx, qy)) in enumerate(CITIES):
        H = roads[ew[j]]
        X, Y = LINES[i], LINES[j]
        d = qx                                   # toward the bypass's side of the crossing
        fx, fy = float(d), 0.0
        side = 1.0 if qy > 0 else -1.0           # the city's side
        th = math.degrees(math.acos(1.0 - (ON_OUT - OFF) / (2 * ON_R)))
        # left of the way it's taken is +y going east: the S turns toward the highway
        toward_left = (side > 0) != (d > 0)      # the highway is on its left
        t1, t2 = ("L", "R") if toward_left else ("R", "L")
        x0, y0 = X - fx * ON_AT, Y + side * ON_OUT
        O = Road(f"O{name.title()}", "on", x0, y0, heading_deg(fx, fy), W_RAMP,
                 [(t1, ON_R, th, "sp"), (t2, ON_R, th, "sp")])
        O.role = "on"
        joins.append((len(roads), 1, roads.index(H)))
        roads.append(O)
        onramps.append((k, len(roads) - 1))
    return roads, joins, cities, ew, ns, jumps, onramps


def junction(roads, c, end, p):
    """The zone where road c's end `end` joins road p: [p, a0, a1, c, b0, b1, sense]."""
    C, P = roads[c], roads[p]
    reach = (C.width + P.width) / 2
    idx = range(C.N) if end == 0 else range(C.N - 1, -1, -1)
    inside = []
    for i in idx:
        k, lat, _ = P.nearest(C.p[i])
        if abs(lat) < reach:
            inside.append((i, k))
        else:
            break
    assert len(inside) >= 3, f"{C.name} end {end} never meets {P.name}"
    bs = [q[0] for q in inside]
    b0, b1 = min(bs), max(bs)
    b0, b1 = max(0, b0 - (JZ_MARGIN if end == 1 else 0)), min(C.N - 1, b1 + (JZ_MARGIN if end == 0 else 0))
    ka = P.nearest(C.p[b0])[0]
    kb = P.nearest(C.p[b1])[0]
    a0, a1 = max(0, min(ka, kb) - JZ_MARGIN), min(P.N - 1, max(ka, kb) + JZ_MARGIN)
    sense = 1 if float(np.dot(C.t[(b0 + b1) // 2], P.t[P.nearest(C.p[(b0 + b1) // 2])[0]])) > 0 else -1
    return [p, a0, a1, c, b0, b1, sense]


def heights(roads, ew, ns):
    """The roads' height keys [i, m, slope]: each north-south highway's flyovers round each crossing
    (set on the roads too), and the jump roads' (set in build). -> [[road, keys], ...]"""
    for hi in ns:
        H = roads[hi]
        keys = []
        for Y in LINES:
            ic = int(np.argmin(np.abs(H.p[:, 1] - Y)))
            f, e = int(FLY_FLAT / STEP), int(FLY_END / STEP)
            keys += [[ic - e, 0.0, 0.0], [ic - f, FLY_H, 0.0], [ic + f, FLY_H, 0.0], [ic + e, 0.0, 0.0]]
        H.keys = keys
    return [[r, R.keys] for r, R in enumerate(roads) if R.keys]


def check(roads, joins, J, cities, ew, ns, jumps=(), onramps=()):
    ok = True

    def bad(msg):
        nonlocal ok
        ok = False
        print("  BAD  " + msg)

    # the highways pass through every crossing on their lines, square to each other
    for hi in ew + ns:
        H = roads[hi]
        for c in LINES:
            line = H.y0 if hi in ew else H.x0
            q = (c, line) if hi in ew else (line, c)
            _, lat, d = H.nearest(q)
            if d > STEP:
                bad(f"{H.name} misses the crossing at {q[0] / KM:.0f},{q[1] / KM:.0f} km by {d:.1f} m")
    # each ramp end on its parent within 0.5 m of OFF, along it within 0.01 deg
    for c, end, p in joins:
        C, P = roads[c], roads[p]
        i = 0 if end == 0 else C.N - 1
        k, lat, _ = P.nearest(C.p[i])
        if abs(abs(lat) - OFF) > 0.5:
            bad(f"{C.name} end {end} sits {abs(lat):.2f} m off {P.name} (want {OFF:.0f})")
        h = math.radians(C.hdeg) if end == 0 else C.end[2]   # the pose, not the first chord
        ang = math.degrees(math.acos(min(1.0, abs(math.cos(h) * P.t[k, 0] + math.sin(h) * P.t[k, 1]))))
        if ang > 0.05:
            bad(f"{C.name} end {end} meets {P.name} at {ang:.3f} deg")
    # junction zones on a road: at most two overlap (a pair of ramps side by side, a turnaround's
    # two ends): the sims take the deepest of the roads a body's zones offer
    by_road = {}
    for n, j in enumerate(J):
        by_road.setdefault(j[0], []).append((j[1], j[2]))
        by_road.setdefault(j[3], []).append((j[4], j[5]))
    most = 0
    for r, zs in by_road.items():
        ev = sorted([(a, 1) for a, b in zs] + [(b + 1, -1) for a, b in zs])
        k = 0
        for _, d in ev:
            k += d
            most = max(most, k)
    if most > 2:
        bad(f"{most} junction zones overlap somewhere (at most 2)")
    print(f"  at most {most} junction zones overlap")
    # clearance: no two roads within GAP outside their junction zones and the crossings' flyovers
    zone = {}
    for j in J:
        zone.setdefault((j[0], j[3]), []).append((j[1], j[2]))
        zone.setdefault((j[3], j[0]), []).append((j[4], j[5]))
    sub = 4
    own = {}
    for j in J:
        own.setdefault(j[0], []).append((j[1], j[2]))
        own.setdefault(j[3], []).append((j[4], j[5]))

    def in_zone(r, i, m=sub):
        return any(a - m <= i <= b + m for a, b in own.get(r, []))
    GORE = 100   # samples past a zone where diverging roads only need not overlap (the gore opening up)
    GORE_LONG = 600   # ... a jump road's or on-ramp's: their S-bends are gentle (a launch spur is taken at 4,000 mph)
    cell = 2000.0
    grid = {}
    for ri, R in enumerate(roads):
        for i in range(0, R.N, sub):
            grid.setdefault((int(R.p[i, 0] // cell), int(R.p[i, 1] // cell)), []).append((ri, i))
    worst = {}
    for (cx, cy), items in grid.items():
        near = []
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                near += grid.get((cx + dx, cy + dy), [])
        for ri, i in items:
            for rj, j in near:
                if rj <= ri:
                    continue
                A, B = roads[ri], roads[rj]
                d = math.hypot(A.p[i, 0] - B.p[j, 0], A.p[i, 1] - B.p[j, 1]) - (A.width + B.width) / 2
                if d >= GAP:
                    continue
                if abs(A.h(i) - B.h(j)) > UP:
                    continue   # a deck over a road
                gore_i = GORE_LONG if roads[ri].kind in ("jump", "on") else GORE
                gore_j = GORE_LONG if roads[rj].kind in ("jump", "on") else GORE
                if d >= -1.0 and (in_zone(ri, i, gore_i) or in_zone(rj, j, gore_j)):
                    continue
                if any(z[0] - sub <= i <= z[1] + sub for z in zone.get((ri, rj), [])) or any(z[0] - sub <= j <= z[1] + sub for z in zone.get((rj, ri), [])):
                    continue
                if in_zone(ri, i) and in_zone(rj, j):
                    continue   # two roads joining a third side by side
                if A.kind == "highway" and B.kind == "highway" and min(abs(A.p[i, 0] - c) + abs(A.p[i, 1] - e) for c in LINES for e in LINES) < FLY_END:
                    continue
                key = (ri, rj)
                if key not in worst or d < worst[key][0]:
                    worst[key] = (d, A.p[i] / KM)
    for (ri, rj), (d, at) in worst.items():
        bad(f"{roads[ri].name} and {roads[rj].name} {d:.0f} m apart at {at[0]:.1f},{at[1]:.1f} km (want {GAP:.0f})")
    # self-clearance of the turnarounds and city roads (non-adjacent parts)
    for R in roads:
        if R.kind == "highway":
            continue
        q = R.p[::sub]
        for a in range(len(q)):
            d = np.hypot(q[a + 30:, 0] - q[a, 0], q[a + 30:, 1] - q[a, 1]) if a + 30 < len(q) else np.array([])
            hit = np.where(d < R.width + GAP)[0]
            for h in hit:
                ia, ib = a * sub, (a + 30 + h) * sub
                if R.kind == "turn" and (ia < 200 and ib > R.N - 200):
                    continue   # its two ends, side by side at the split
                bad(f"{R.name} comes within {d[h]:.0f} m of itself ({ia}, {ib})")
                break
    # every city reaches every other
    adj = {i: set() for i in range(len(roads))}
    for j in J:
        adj[j[0]].add(j[3])
        adj[j[3]].add(j[0])
    seen, todo = {cities[0][4]}, [cities[0][4]]
    while todo:
        r = todo.pop()
        for n in adj[r]:
            if n not in seen:
                seen.add(n)
                todo.append(n)
    for c in cities:
        if c[4] not in seen:
            bad(f"{c[0]} is unreachable")
    if len(seen) != len(roads):
        bad(f"{len(roads) - len(seen)} roads unreachable")
    # the jumps: the lip's angle, and who lands (the trajectory against the deck's lip: a speed
    # lands if it arrives over the deck's start and within JC_REACH of it)
    for li, ci, ref, h_lip, top in jumps:
        L, C = roads[li], roads[ci]
        m_lip = (L.h(L.N - 1) - L.h(L.N - 1 - 0.01)) / (0.01 * STEP)
        if abs(math.degrees(math.atan(m_lip)) - JL_ANG) > 0.05:
            bad(f"{L.name}'s lip is {math.degrees(math.atan(m_lip)):.2f} deg (want {JL_ANG})")
        gap = math.hypot(C.p[0, 0] - L.p[-1, 0], C.p[0, 1] - L.p[-1, 1])
        lands = []
        for mph in range(2000, 7001, 250):
            v = mph * MPH
            c2 = 1.0 / (1.0 + m_lip * m_lip)
            y = h_lip + gap * m_lip - G * gap * gap / (2 * v * v * c2)
            dz = y - C.h(0)
            lands.append((mph, 0.0 <= dz <= JC_REACH))
        lo = min((m for m, ok_ in lands if ok_), default=None)
        if lo is None or lo > ref + 1 or not all(ok_ for m, ok_ in lands if m >= lo):
            bad(f"{L.name}: lands {[m for m, ok_ in lands if ok_]} (want {ref:.0f} mph and up)")
        print(f"  jump {L.name} -> {C.name}: lip {h_lip:.0f} m at {JL_ANG} deg, {gap:.0f} m to a deck "
              f"{C.h(0) - h_lip:.0f} m above it ({(C.h(0) - h_lip) / 0.3048:.0f} ft), level at {top:.0f} m; lands from {lo} mph")
    for k, r in onramps:
        O = roads[r]
        print(f"  on-ramp {O.name}: from {O.p[0, 0] / KM:.1f},{O.p[0, 1] / KM:.1f} km on the open ground")
    return ok


def main():
    roads, joins, cities, ew, ns, jumps, onramps = build()
    J = [junction(roads, c, end, p) for c, end, p in joins]
    H = heights(roads, ew, ns)
    km = sum(float(R.len[:-1].sum()) for R in roads) / KM
    N = sum(R.N for R in roads)
    kinds = {}
    for R in roads:
        kinds.setdefault(R.kind, [0, 0.0])
        kinds[R.kind][0] += 1
        kinds[R.kind][1] += float(R.len[:-1].sum()) / KM
    print(f"{len(roads)} roads, {km:.0f} km, {N} samples at {STEP:.0f} m; " +
          ", ".join(f"{k}: {n} ({l:.0f} km)" for k, (n, l) in kinds.items()))
    print(f"{len(J)} junctions; zones {min(j[2] - j[1] for j in J)}-{max(j[2] - j[1] for j in J)} parent samples")
    for name, biome, cx, cy, r, i in cities:
        print(f"  {name:<9} {biome:<8} at {cx / KM:.0f},{cy / KM:.0f} km: {roads[r].name} sample {i} of {roads[r].N}")
    ok = check(roads, joins, J, cities, ew, ns, jumps, onramps)
    if km > 6000 or N > 250000:
        ok = False
        print(f"  BAD  too big: {km:.0f} km, {N} samples")
    print("NETWORK DESIGN OK" if ok else "NETWORK DESIGN NOT OK")
    if "--plot" in sys.argv:
        plot(roads, cities, sys.argv[sys.argv.index("--plot") + 1] if len(sys.argv) > sys.argv.index("--plot") + 1 else "network.png")
    return roads, J, cities, H, ok, jumps, onramps


def plot(roads, cities, out):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    fig, ax = plt.subplots(figsize=(10, 10))
    col = {"highway": "#2a6fdb", "ramp": "#6a8", "city": "#d33", "turn": "#999", "jump": "#f80", "on": "#a0a"}
    for R in roads:
        ax.plot(R.p[:, 0] / KM, R.p[:, 1] / KM, color=col[R.kind], lw=1.6 if R.kind == "highway" else 0.9)
    for name, biome, cx, cy, r, i in cities:
        ax.plot(cx / KM, cy / KM, "o", color="k")
        ax.annotate(f"{name} ({biome})", (cx / KM, cy / KM), textcoords="offset points", xytext=(6, 6), fontsize=9)
    ax.set_aspect("equal")
    ax.set_xlabel("km east")
    ax.set_ylabel("km north")
    ax.grid(alpha=0.3)
    fig.savefig(out, dpi=110, bbox_inches="tight")
    print("plot ->", out)


if __name__ == "__main__":
    main()
