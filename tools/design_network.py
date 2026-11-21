"""Design aid for the Network (track "network"): a country of highways, interchanges and cities.

docs/superpowers/specs/2026-10-19-network-design.md. Phase 1, the mesh:
- three highways east-west and three north-south on the 100/300/500 km lines, 25-575 km, straight
  for 45 km either side of each crossing, symmetric S-bends between (arc +t, straight m, arc -2t,
  straight m, arc +t: a mirror image about its middle, so it comes back onto its line);
- north-south highways form a 600 m express tier, grading down before their end shafts; four
  two-way quadrant ramps join the two, each a 90 deg arc of R_RAMP starting tangent to one
  highway OFF m off its centreline on the quadrant's side and ending tangent to the other;
- five cities beside a crossing's east-west highway: each city's road is a bypass off it, a
  symmetric S (arc BY_DEG out into the quadrant, straight, arc 2 x BY_DEG back, straight, arc BY_DEG
  onto the highway again) whose far arc is the city (STARFIGHTER, its terminal at the apex). A
  bypass can be entered from either direction on its highway (a road's start only going up it, its
  end only going down it: a road from one highway to another could be entered from two of the four
  ways in);
- at each highway end a vertical shaft: its paperclip plan carries the craft through a half loop
  and rolling descent, returning onto the same highway in the opposite direction.
Phase 3, jumps and the ground (Luke: "taking a massive interchange and using it as a ramp to jump 2
miles and 1500' up to the entrance of the next ramp"):
- twenty jump sets: all four approaches at the five non-corner crossings. A launch spur forks
  from its right-hand exit ramp, rises to a lip 3 km before the crossing, and flies to a catch
  deck. The release's nine minimum speeds (2,000-4,000 mph) and lip angles (5-14 degrees)
  remain varied. Three ascent profiles add terraces, crests and saddles, with 400-1,000 m of
  added rise and gaps up to 50% longer. Catch decks pull out level before their recovery;
- four central catch roads transfer to the perpendicular highway through alternating bends,
  acceleration straights and rolling crests/dips, then descend outside its traffic lanes to merge.
  The other catches merge 44 km beyond their crossing; four carry full recovery rolls in the
  view through NET_TWISTS while retaining the level, drivable simulation path;
- an on-ramp from the open ground for each city: it starts ON_OUT out on the city's side, short of
  the crossing on the far side from its bypass, and S-bends in onto the highway (missing a jump
  drops you to the ground: the dash points you to the nearest);
- heights are keys [sample, m, slope] with Hermite cubics between (zero slopes: the old smoothstep),
  real in both sims now (the deck lock: tools/sync_network.py).
The scenic roads (Luke, 2026-11-19: "a track that drives along the side of a mountain, with the beach
on one side. Then maybe another with a massive vertical drop into the valley below ... Pacific
Northwest coastal highway but at speed. Maybe they could run on either edge of the map"):
- SCoast, down the west edge: off E1's north side, out to the coast, north along it over headlands
  and down round bays (the sea on its left, the mountain on its right), and in again onto E2;
- SDrop, down the east edge: off E3's south side, south up a mountainside to a rim 2,300 m up, off
  the rim down a 2 km dive on a viaduct, along the valley's floor, and in onto E2.
Their plans and heights are ordinary roads' (the sims know nothing else about them); SCENIC also
carries the land beside each ([sample, the height the land reaches on the left, over how far, the
same on the right, how far the land's edge lies under the deck]: view/network_scenic.gd shapes the
terrain from it), which the sims only pass along.
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
W_HWY, W_RAMP, W_CITY, W_SIDE = 400.0, 200.0, 200.0, 200.0
OFF = 100.0                       # a ramp's start: its centreline this far off the highway's, on its side
R_RAMP = 12 * KM                  # quadrant ramps and the city roads' turns (2,500 mph at 11 g)
BY_FAR = 43 * KM                  # a city's bypass leaves its highway this far from the crossing
BY_R, BY_DEG, BY_M = 7 * KM, 60.0, 3.5 * KM   # its arcs and straights: ~10 km out, ~28 km along
CITY_OUT = 3 * KM                 # the city's centre: this far past the bypass's apex
STRAIGHT = ("E2", "N2", "E3")     # dead straight edge to edge (Luke); the other three keep their S-bends
# The shafts at the highways' ends (Luke: "a vertical shaft that turns over on itself and enters the same
# road it came from"). The world's shape, along the road from the highway: flat out to the pull-up, a
# quarter arc SH_R up, SH_V straight up, a half arc SH_R over the top (upside down at the apex), SH_V
# straight down rolling half a turn (so you're the right way up again), a quarter arc SH_R out onto
# the highway the other way. The sims stay flat: the road is a paperclip in plan (out on the right of
# the highway, a bulb SH_BULB, back on its left) whose bulb carries the craft round (NET_SHAFTS: its
# curvature turns the bodies with it, nothing to steer); view/network_shaft.gd draws the plan's stretch
# between the two feet as the shape above, and sim heights are the real altitude along it.
# (world arc radius, plan bulb radius), E1-/+ through N3-/+.
# Whole 12 m radii keep 2R aligned to the 24 m sample grid and both feet exact.
# Narrow spires, broad crowns and intermediate arches each have their own silhouette.
SH_PROFILES = [
    (2400.0, 4800.0), (5400.0, 4200.0),
    (3000.0, 6000.0), (6000.0, 4800.0),
    (3600.0, 3600.0), (4200.0, 5400.0),
    (2808.0, 5400.0), (6600.0, 4800.0),
    (4008.0, 6000.0), (4800.0, 4200.0),
    (3204.0, 6600.0), (5700.0, 5100.0),
]
SH_SPLIT = 1600.0                 # the two legs leave the highway this far before its end
SH_FLAT = 296.0                   # the landing touches down this far past the highway's end
SH_KEYS = 24                      # samples between the height keys round the arcs
FLY_H, FLY_FLAT, FLY_END = 120.0, 3 * KM, 9 * KM   # the flyover: 120 m, flat for +-3 km, down by 9 km
EXPRESS_H = 600.0                 # north-south express tier, level through all nine interchanges
RAMP_LEVEL = 3 * KM               # level mouths keep every shared entrance coplanar
JZ_MARGIN = 10                    # samples past the overlap in each junction zone
GAP = 300.0                       # clear between roads outside their junction zones and crossings
UP = 30.0                         # ... or this far apart in height (a deck over a road)
G = 9.81
MPH = 0.44704
JUMP_GAP = 3218.7                 # reference gap at 3,000 mph; others scale with minimum speed
JL_FORK = 4.5                     # deg round the quadrant ramp where the spur forks straight on off it
JL_LIP, JL_KICK = 3 * KM, 4 * KM  # the lip this far short of the crossing, the kick's length
JC_W, JC_REACH, JC_PULL = 400.0, 40.0, 5 * KM
JC_FLAT, JC_DOWN, JC_MERGE = 23 * KM, 34 * KM, 44 * KM   # level through a recovery roll, then merge
JUMP_PROFILES = [
    ("ARC", 400.0, 1.0),
    ("HIGH ARC", 700.0, 1.25),
    ("SKY ARC", 1000.0, 1.5),
]
TWIST_JUMPS = (4, 8, 12, 16)
TRANSFER_JUMPS = (0, 1, 2, 3)
TRANSFER_MERGE, TRANSFER_OUT, TRANSFER_FINAL = 160 * KM, 1 * KM, 2 * KM
TRANSFER_BEND_R, TRANSFER_BEND_SECONDS = 25 * KM, 11.0
# At each selected crossing the exit ramp on your right forks: it curves to the other highway,
# while its launch spur runs straight on. The first four jumps are true highway transfers.
JUMP_AT = [(1, 1), (1, 0), (1, 2), (0, 1), (2, 1)]
JUMP_WAYS = [("E", 1), ("E", -1), ("N", 1), ("N", -1)]   # the highway it's on, the way it's taken
# Preserve the release's nine speed/angle profiles across twenty approaches. Rows follow
# JUMP_AT; columns follow JUMP_WAYS. The five surviving original approaches retain
# their minimums; profiles formerly at city corners move to these new approaches.
JUMP_ANGLES = {2000.0: 5.0, 2250.0: 6.0, 2500.0: 6.5, 2750.0: 7.5,
               3000.0: 8.5, 3250.0: 10.0, 3500.0: 11.0, 3750.0: 12.5, 4000.0: 14.0}
JUMP_SPEEDS = [
    [3000.0, 3500.0, 2500.0, 4000.0],   # centre
    [2000.0, 3250.0, 2500.0, 3750.0],   # south
    [2250.0, 3500.0, 4000.0, 2750.0],   # north
    [2500.0, 3250.0, 2000.0, 2750.0],   # west
    [3500.0, 2250.0, 3000.0, 3750.0],   # east
]
ON_OUT, ON_R, ON_AT = 4 * KM, 12 * KM, 34 * KM   # on-ramps: out from the highway, their S, start short of the crossing
CITIES = [   # name, biome, crossing (i, j) on (LINES x, LINES y), quadrant (qx, qy)
    ("ERIDANUS", "verdant", (1, 1), (1, 1)),
    ("DUNES", "desert", (0, 2), (-1, 1)),
    ("GLACIER", "ice", (2, 2), (1, 1)),
    ("BASALT", "basalt", (0, 0), (-1, -1)),
    ("MESA", "mesa", (2, 0), (1, -1)),
]


# The side roads (Luke: "different shapes, that would reasonably cause the person to actually shift, while
# still staying at 'highway' speeds"): loops off the straight highways, out over OUT_BEND and back the
# same way (each half's bends net to nothing, so the second half is the first reversed and lands back
# tangent). Their corners are 6-16 km radius: 1,800-2,900 mph at 11 g, second and third gear between
# straights long enough for top (gears: 1,330 / 2,450 / 3,470 / 4,450 mph).
OUT_BEND = [("O", 16 * KM, 26.0), ("S", 3 * KM), ("I", 16 * KM, 26.0)]   # out into the country first, in third
SHAPES = {
    "esses": [("O", 8 * KM, 30.0), ("I", 8 * KM, 60.0), ("O", 8 * KM, 30.0), ("S", 1.5 * KM)],
    "hairpin": [("S", 4 * KM), ("O", 7 * KM, 100.0), ("S", 2 * KM), ("I", 7 * KM, 100.0), ("S", 3 * KM)],
    "chicane": [("S", 12 * KM), ("O", 6 * KM, 35.0), ("I", 6 * KM, 70.0), ("O", 6 * KM, 35.0), ("S", 6 * KM)],
    "tighten": [("O", 16 * KM, 55.0), ("S", 5 * KM), ("I", 9 * KM, 55.0), ("S", 2 * KM)],
    "kinks": [("O", 10 * KM, 18.0), ("S", 3 * KM), ("I", 10 * KM, 36.0), ("S", 3 * KM), ("O", 10 * KM, 36.0), ("S", 3 * KM), ("I", 10 * KM, 18.0)],
    "crook": [("O", 7 * KM, 120.0), ("I", 11 * KM, 120.0), ("S", 2 * KM)],
}
SIDES = [   # highway, its middle along the highway (m), side (+1 its left, -1 its right), shape
    ("E2", 200 * KM, 1, "esses"), ("E2", 200 * KM, -1, "hairpin"), ("E2", 400 * KM, 1, "chicane"), ("E2", 400 * KM, -1, "tighten"),
    ("N2", 200 * KM, 1, "kinks"), ("N2", 200 * KM, -1, "crook"), ("N2", 400 * KM, 1, "hairpin"), ("N2", 400 * KM, -1, "esses"),
    ("E3", 200 * KM, 1, "crook"), ("E3", 200 * KM, -1, "chicane"), ("E3", 400 * KM, 1, "kinks"), ("E3", 400 * KM, -1, "tighten"),
]


# The scenic roads. A plan is turns and straights from its start pose ("L"/"R" radius km, degrees;
# "S" km); `stretch` names the straight whose length is found so the road ends on its highway's side
# line. Heights are keys (segment, how far through it 0..1, m, slope) on that plan; land is stations
# (segment, how far through it, left, its run m, right, its run m, gap m): a side's height is
# absolute, or ("r", m) relative to the road there. A side lower than the road falls away from it
# (and the road's edge on that side is open: view/network_world.gd); higher, it stands over it. The
# coast's sea side takes "sea" and the shelf (m of low ground between the road and the cliff's edge).
SC_W = 200.0
SCENIC = [
    dict(name="SCoast", start=(50.0, "E1", 1, 180.0), end=("E2", -1), sea=1, stretch=26,
         plan=[("R", 16, 40), ("S", 5), ("L", 16, 30), ("S", 6), ("R", 14, 80),          # 0-4: out to the coast, north
               ("S", 6), ("L", 12, 22), ("R", 10, 44), ("S", 5), ("L", 12, 40),          # 5-9
               ("S", 7), ("R", 14, 36), ("L", 9, 38), ("S", 4), ("R", 12, 44),           # 10-14
               ("S", 6), ("L", 16, 48), ("R", 11, 40), ("S", 5), ("L", 10, 36),          # 15-19
               ("S", 3), ("R", 13, 44), ("L", 15, 50), ("S", 4), ("R", 10, 50),          # 20-24
               ("L", 16, 24), ("S", 8), ("R", 14, 70), ("S", 18), ("R", 16, 20)],        # 25-29: north, and in onto E2
         heights=[(4, .12, 0, 0), (4, .96, 26, 0), (6, .55, 150, 0), (7, .6, 18, 0), (9, .5, 215, 0),
                  (10, .7, 70, 0), (11, .55, 22, 0), (12, .5, 245, 0), (14, .5, 20, 0), (16, .5, 180, 0),
                  (17, .55, 24, 0), (19, .5, 200, 0), (21, .5, 16, 0), (22, .5, 230, 0), (24, .5, 22, 0),
                  (25, .6, 120, 0), (26, .7, 30, 0), (27, .45, 0, 0)],
         land=[(4, .12, -4, 400, -4, 400, 1), (4, .5, "sea", 2600, 260, 1500, 1), (4, .96, "sea", 0, 520, 2000, 1),
               (9, .5, "sea", 0, 760, 2300, 1), (12, .5, "sea", 0, 900, 2400, 1), (16, .5, "sea", 0, 700, 2200, 1),
               (19, .5, "sea", 0, 980, 2500, 1), (22, .5, "sea", 0, 1150, 2600, 1), (24, .5, "sea", 0, 900, 2400, 1),
               (26, .7, "sea", 0, 520, 2000, 1), (27, .25, "sea", 2600, 200, 1400, 1), (27, .45, -4, 400, -4, 400, 1)]),
    dict(name="SDrop", start=(548.0, "E3", -1, 0.0), end=("E2", 1), sea=0, stretch=24,
         plan=[("R", 16, 35), ("S", 15), ("R", 14, 55),                                   # 0-2: out to the edge, south
               ("S", 6), ("L", 12, 25), ("R", 12, 50), ("L", 12, 25), ("S", 8),           # 3-7: the climb
               ("R", 10, 30), ("L", 10, 60), ("R", 10, 30), ("S", 5), ("L", 14, 18),      # 8-12: the rim
               ("S", 19),                                                                 # 13: the dive
               ("L", 16, 20), ("R", 16, 40), ("L", 16, 28), ("S", 6), ("R", 14, 30),      # 14-18: the valley
               ("L", 14, 34), ("R", 14, 30), ("S", 4), ("R", 12, 26), ("L", 12, 26),      # 19-23
               ("S", 6), ("R", 14, 70), ("S", 30), ("R", 16, 20)],                        # 24-27: south, and in onto E2
         heights=[(2, .85, 0, 0), (5, .5, 1050, .062), (8, .1, 2250, 0), (10, .5, 2330, 0), (13, .1, 2390, 0),
                  (13, .78, 330, 0), (16, .5, 190, 0), (20, .5, 90, 0), (24, .5, 0, 0)],
         land=[(2, .85, -4, 400, -4, 400, 1), (3, .6, 30, 700, ("r", 500), 1800, 1), (5, .5, 60, 1300, ("r", 800), 2200, 1),
               (8, .1, 110, 1600, ("r", 950), 2400, 1), (10, .5, 140, 1600, ("r", 1000), 2400, 1),
               (12, .5, 150, 1600, ("r", 700), 2200, 1), (13, .02, 150, 1500, ("r", 0), 1400, 1), (13, .09, 150, 1400, 170, 1400, 1),
               (13, .16, 150, 1400, 170, 1400, 1500), (13, .6, 150, 1400, 170, 1400, 500), (13, .78, ("r", -6), 1300, ("r", -6), 1300, 1),
               (16, .5, ("r", -6), 1100, ("r", -6), 1100, 1), (20, .5, ("r", -6), 900, ("r", -6), 900, 1),
               (24, .3, -4, 400, -4, 400, 1)]),
]
# One interior link in each of the four large highway cells. Mouths are specified
# as (highway, station on its map axis in km, shoulder side, driving direction).
# Interior poses are (east km, north km, heading degrees); radii are in km.
BACKROADS = [
    ("SWash", ("E3", 133, -1, 1), ("N1", 395, -1, -1), 11,
     [(162, 483, -40), (178, 460, -92), (158, 438, -151), (130, 429, -153)],
     [(0.22, 0), (0.56, 0), (0.68, 0), (0.85, 260)]),
    ("SFrost", ("E3", 455, -1, -1), ("N2", 409, -1, -1), 14,
     [(436, 485, -143), (418, 453, -125), (382, 441, -169), (348, 435, -157)],
     [(0.22, 180), (0.39, 780), (0.56, 320), (0.73, 490), (0.90, 415)]),
    ("SReed", ("E1", 249, 1, 1), ("N2", 214, 1, 1), 10,
     [(267, 115, 83), (249, 143, 139), (223, 166, 120), (231, 185, 18), (268, 188, 8)],
     [(0.09, 42), (0.20, 68), (0.32, 44), (0.47, 12), (0.64, 0), (0.77, 100)]),
    ("SRed", ("E1", 469, 1, -1), ("N3", 213, 1, 1), 12,
     [(446, 113, 139), (423, 140, 123), (413, 162, 73), (438, 181, 23), (474, 188, 21)],
     [(0.18, 0), (0.36, 0), (0.50, 0), (0.69, 0), (0.81, 150)]),
]


def backroad_mouth(parent, station, side, direction):
    axis = parent.p[:, 0 if parent.name.startswith("E") else 1]
    i = int(np.argmin(abs(axis - station * KM)))
    tx, ty = parent.t[i]
    x, y = parent.p[i] + side * OFF * np.array([-ty, tx])
    return x, y, heading_deg(tx * direction, ty * direction)


scenic_roads = []   # (road index, its SCENIC entry), filled by build()


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


def varied_arc(kind, radius, angle, mode, inner, count):
    """A forward/reverse/forward bend with exactly the original arc's endpoint.

    Symmetry about the half-angle puts the displacement on the original chord.
    Two forward arcs plus a reverse arc contribute 2*r*sin(a/2)+4*r*sin(w);
    the remaining chord is a straight at the midpoint of the reverse bend.
    """
    out = []
    part = angle / count
    wiggle = 0.14 * (radius - inner) / inner * part
    reverse = 'R' if kind == 'L' else 'L'
    straight = 2 * (radius-inner) * math.sin(math.radians(part/2)) - 4 * inner * math.sin(math.radians(wiggle))
    assert straight > 0, 'reverse bend must leave positive throttle space'
    for _ in range(count):
        out.extend([(kind, inner, part/2+wiggle, mode),
                    (reverse, inner, wiggle, mode), ('S', straight, 0, mode),
                    (reverse, inner, wiggle, mode), (kind, inner, part/2+wiggle, mode)])
    return out


def transfer_rhythm(segs, mph):
    """Alternate steering through wide sweeps, retaining entry/exit poses."""
    out = []
    for kind, radius, angle, mode in segs:
        if kind == 'S':
            out.append((kind, radius, angle, mode))
            continue
        # Short final merge curves retain their original smooth shoulder entry.
        if angle < 20:
            out.append((kind, radius, angle, mode))
            continue
        factor = 1 + 2 * 0.14 * (radius-TRANSFER_BEND_R) / TRANSFER_BEND_R
        count = max(1, math.ceil(math.radians(angle) * TRANSFER_BEND_R * factor /
                                 (mph * MPH * TRANSFER_BEND_SECONDS)))
        out += varied_arc(kind, radius, angle, mode, TRANSFER_BEND_R, count)
    return out


def s_bend(D, deg):
    """A symmetric S covering D forward: [arc deg, straight m, arc -2 deg, straight m, arc deg]."""
    t = math.radians(abs(deg))
    m = (D - 4 * S_R * math.sin(t)) / (2 * math.cos(t))
    assert m > 1000, f"S-bend: straight {m:.0f} m"
    a, b = ("L", "R") if deg > 0 else ("R", "L")
    return [(a, S_R, abs(deg), "sp"), ("S", m, 0, "sp"), (b, S_R, 2 * abs(deg), "sp"), ("S", m, 0, "sp"), (a, S_R, abs(deg), "sp")]


def highway(name, axis, line, spans):
    """axis 'x': runs west-east at y = line; 'y': south-north at x = line. STRAIGHT ones (Luke: "completely
    straight from edge to edge") are one long straight."""
    if name in STRAIGHT:
        segs = [("S", H1 - H0, 0, "sp")]
    else:
        segs = [("S", LINES[0] + ZONE - H0, 0, "sp")]
        for k in range(2):
            segs += s_bend(LINES[k + 1] - LINES[k] - 2 * ZONE, spans[k])
            segs.append(("S", 2 * ZONE if k == 0 else H1 - LINES[2] + ZONE, 0, "sp"))
    if axis == "x":
        return Road(name, "highway", H0, line, 0.0, W_HWY, segs)
    return Road(name, "highway", line, H0, 90.0, W_HWY, segs)


def heading_deg(dx, dy):
    return math.degrees(math.atan2(dy, dx))


def dubins(start, finish, radius):
    """Shortest valid CSC road between oriented poses, with exact tangent arc/line joins."""
    x, y, heading = start
    gx, gy, goal_heading = finish
    theta = math.atan2(gy - y, gx - x)
    distance = math.hypot(gx - x, gy - y) / radius
    tau = 2 * math.pi
    a = (math.radians(heading) - theta) % tau
    b = (math.radians(goal_heading) - theta) % tau
    sa, sb, ca, cb, cab = math.sin(a), math.sin(b), math.cos(a), math.cos(b), math.cos(a - b)
    candidates = []
    p2 = 2 + distance ** 2 - 2 * cab + 2 * distance * (sa - sb)
    if p2 >= 0:
        t = math.atan2(cb - ca, distance + sa - sb)
        candidates.append(("L", (-a + t) % tau, math.sqrt(p2), "L", (b - t) % tau))
    p2 = 2 + distance ** 2 - 2 * cab + 2 * distance * (-sa + sb)
    if p2 >= 0:
        t = math.atan2(ca - cb, distance - sa + sb)
        candidates.append(("R", (a - t) % tau, math.sqrt(p2), "R", (-b + t) % tau))
    p2 = -2 + distance ** 2 + 2 * cab + 2 * distance * (sa + sb)
    if p2 >= 0:
        p = math.sqrt(p2)
        t = math.atan2(-ca - cb, distance + sa + sb) - math.atan2(-2.0, p)
        candidates.append(("L", (-a + t) % tau, p, "R", (-b + t) % tau))
    p2 = -2 + distance ** 2 + 2 * cab - 2 * distance * (sa + sb)
    if p2 >= 0:
        p = math.sqrt(p2)
        t = math.atan2(ca + cb, distance - sa - sb) - math.atan2(2.0, p)
        candidates.append(("R", (a - t) % tau, p, "L", (b - t) % tau))
    turn0, a0, straight, turn1, a1 = min(candidates, key=lambda c: c[1] + c[2] + c[4])
    segments = [(turn0, radius, math.degrees(a0), "sp"), ("S", straight * radius, 0, "sp"),
                (turn1, radius, math.degrees(a1), "sp")]
    _, end = walk(segments, x, y, math.radians(heading))
    assert math.hypot(end[0] - gx, end[1] - gy) < 0.1, "Dubins route missed its target"
    return segments


def launch_keys(road, baseline, lip, slope, profile):
    """One monotone bowed climb, easing into the original ballistic lip.

    Tall ramps have mean slopes greater than their lip slopes, so a literal
    ever-steepening exponential cannot preserve their flights. Exact cubic
    derivatives avoid terraces, repeated pitch changes and downhill sections.
    """
    first = math.ceil(2700.0 / STEP)
    span = road.N - 1 - first
    length = span * STEP
    a = slope * length - 2.0 * lip
    b = 3.0 * lip - slope * length
    keys = [[0, baseline, 0.0]]
    for q in range(9):
        i = first + round(span * q / 8)
        t = (i - first) / span
        keys.append([i, baseline + (a*t+b)*t*t, (3*a*t*t+2*b*t)/length])
    return keys


def shaft_z(d, R, V):
    """A shaft's altitude and its slope (dz/ds) d m along it from the pull-up."""
    q = math.pi * R / 2
    if d <= 0:
        return 0.0, 0.0
    if d < q:                          # the pull-up
        return R * (1 - math.cos(d / R)), math.sin(d / R)
    if d < q + V:                      # straight up
        return R + d - q, 1.0
    if d < 3 * q + V:                  # over the top
        a = (d - q - V) / R
        return R + V + R * math.sin(a), math.cos(a)
    if d < 3 * q + 2 * V:              # straight down, rolling half a turn
        return R + V - (d - 3 * q - V), -1.0
    if d < 4 * q + 2 * V:              # the pull-out
        a = (d - 3 * q - 2 * V) / R
        return R - R * math.sin(a), -math.cos(a)
    return 0.0, 0.0


def shaft_keys(r, i_up, i_dn, radius, V):
    """Height keys [sample, m, slope] along a shaft: every SH_KEYS samples, the exact height and slope, so
    the sims' Hermite cubics hold the real altitude (the view's shape: view/network_shaft.gd)."""
    s = np.concatenate([[0.0], np.cumsum(r.len[:-1])])
    keys = [[0, 0.0, 0.0]] if i_up > 0 else []
    i = i_up
    while True:
        z, m = shaft_z(s[i] - s[i_up], radius, V)
        keys.append([i, z, m])
        if i >= i_dn:
            break
        i = min(i_dn, i + SH_KEYS)
    keys[-1] = [i_dn, 0.0, 0.0]
    keys.append([r.N - 1, 0.0, 0.0])
    return keys


join_off = {}   # (child road, end) -> its lateral off the parent, where that isn't OFF


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
    join_off.clear()
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
    # the shafts: a paperclip in plan, flat along the highway's right past its end, the bulb, flat back
    # along its left. A leg's flat stretch: from the split past the highway's end by the landing (the way
    # back) or by the landing and 2 SH_R (the way out: the top comes back that far over the road)
    shafts = []
    for hi in ew + ns:
        H = roads[hi]
        for end in (0, 1):
            radius, bulb_radius = SH_PROFILES[len(shafts)]
            ca = (OFF + bulb_radius) / (2 * bulb_radius)
            alpha = math.degrees(math.acos(ca))
            if end == 1:
                px, py = H.p[-1]
                u = H.t[-1]
            else:
                px, py = H.p[0]
                u = -H.t[0]
            nl = (-u[1], u[0])
            sx, sy = px - SH_SPLIT * u[0] - OFF * nl[0], py - SH_SPLIT * u[1] - OFF * nl[1]
            land = SH_SPLIT + SH_FLAT                 # flat, split to touchdown (and the plan's way back)
            out = land + 2 * radius                     # flat, split to pull-up (and the plan's way out)
            r = Road(f"T{H.name}{'+' if end else '-'}", "turn", sx, sy, heading_deg(u[0], u[1]), W_RAMP,
                     [("S", out, 0, "sp"), ("R", bulb_radius, alpha, "sp"), ("L", bulb_radius, 180.0 + 2 * alpha, "sp"),
                      ("R", bulb_radius, alpha, "sp"), ("S", out, 0, "sp")])
            # the world's length between the feet is the plan's: bulb + (out - land) back on the leg
            s_up, s_dn = out, r.len[:-1].sum() - land
            V = (s_dn - s_up - 2 * math.pi * radius) / 2.0
            assert V > 2000, f"the shaft's straight is only {V:.0f} m"
            i_up, i_dn = int(round(out / STEP)), r.N - 1 - int(round(land / STEP))
            s_up, s_dn = float(np.sum(r.len[:i_up])), float(np.sum(r.len[:i_dn]))
            V = (s_dn - s_up - 2 * math.pi * radius) / 2.0
            r.keys = shaft_keys(r, i_up, i_dn, radius, V)
            shafts.append((len(roads), i_up, i_dn, radius, V))
            joins += [(len(roads), 0, hi), (len(roads), 1, hi)]
            roads.append(r)
    # the jump sets: one each way through each crossing in JUMP_AT, off the exit ramp on that way's right
    jumps = []
    for crossing, (ci, cj) in enumerate(JUMP_AT):
        X, Y = LINES[ci], LINES[cj]
        for way, (axis, d) in enumerate(JUMP_WAYS):
            jump_id = len(jumps)
            profile = jump_id % len(JUMP_PROFILES)
            profile_name, extra_rise, gap_scale = JUMP_PROFILES[profile]
            ref = JUMP_SPEEDS[crossing][way]
            angle = JUMP_ANGLES[ref]
            gap = JUMP_GAP * ref / 3000.0 * gap_scale
            baseline = EXPRESS_H if axis == "N" else 0.0
            fx, fy = ((1.0, 0.0) if axis == "E" else (0.0, 1.0))
            fx, fy = fx * d, fy * d                  # the way it's taken
            rx, ry = fy, -fx                         # its right
            H = roads[(ew[cj] if axis == "E" else ns[ci])]
            qx, qy = int(round(-fx + rx)), int(round(-fy + ry))   # the exit's quadrant: behind and to the right
            ramp = next(k for k, R in enumerate(roads) if R.name == f"R{ci}{cj}{'E' if qx > 0 else 'W'}{'N' if qy > 0 else 'S'}")
            hdg = heading_deg(fx, fy) - JL_FORK
            a = math.radians(JL_FORK)
            ux, uy = math.cos(math.radians(hdg)), math.sin(math.radians(hdg))
            # the fork: JL_FORK round the ramp from its mouth on this highway
            u0 = -(R_RAMP + OFF) + R_RAMP * math.sin(a)   # along the way it's taken, from the crossing
            r0 = OFF + R_RAMP * (1 - math.cos(a))         # to its right
            x0, y0 = X + fx * u0 + rx * r0, Y + fy * u0 + ry * r0
            st = (-JL_LIP - u0) / math.cos(a)
            L = Road(f"J{len(jumps)}", "jump", x0, y0, hdg, W_RAMP, [("S", st, 0, "sp")])
            L.role = "launch"
            m_lip = math.tan(math.radians(angle))
            k0 = L.N - 1 - round(JL_KICK / STEP)
            h_lip = baseline + extra_rise + (L.N - 1 - k0) * STEP * m_lip / 2.0
            L.keys = launch_keys(L, baseline, h_lip - baseline, m_lip, profile)
            L.profile = profile_name
            join_off[(len(roads), 0)] = 0.0              # on the ramp's own centreline
            joins.append((len(roads), 0, ramp))
            roads.append(L)
            # The front engines reach the lip before the trailing pod. Their vertical
            # ties put the shallow, longer flights a few metres below a point-mass
            # trajectory, so those entries have 7 m of clearance instead of 3 m.
            v = ref * MPH
            c2 = 1.0 / (1.0 + m_lip * m_lip)        # cos^2 of the lip's angle
            # Extended flights need this margin at every speed: smoothing the
            # launch changes finite-step vertical velocity by ~0.09 m/s, enough
            # for J5 at its posted minimum to miss the old 3 m entry tolerance.
            entry_margin = 7.0 if gap_scale > 1.0 else 3.0
            hc = h_lip + gap * m_lip - G * gap ** 2 / (2 * v * v * c2) - entry_margin
            # Longer flights spread fast arrivals vertically. A steeper initial catch
            # intercepts them along the landing straight without enlarging the 40 m capture reach.
            mc = m_lip - G * gap / (v * v * c2) if gap_scale == 1.0 else m_lip + 0.06
            lx, ly = L.p[-1]
            cx0, cy0 = lx + ux * gap, ly + uy * gap
            uc = (cx0 - X) * fx + (cy0 - Y) * fy      # the deck's start, along the way, from the crossing
            rc = (cx0 - X) * rx + (cy0 - Y) * ry      # ... and to the right of the highway
            # straight on, a long left and a long right back onto the highway's right edge at JC_MERGE:
            # A from the along, the angle beta from the right (bisection)
            Rs = S_R
            def miss(bt):
                A = (JC_MERGE - uc - Rs * (math.sin(a) + 2 * math.sin(bt))) / math.cos(a)
                return rc + A * math.sin(a) + Rs * (2 * math.cos(bt) - math.cos(a) - 1) - OFF, A
            lo, hi = 0.0, math.radians(45.0)
            for _ in range(60):
                m = (lo + hi) / 2
                if miss(m)[0] > 0:
                    lo = m
                else:
                    hi = m
            bt = (lo + hi) / 2
            A = miss(bt)[1]
            assert A > 0 and abs(miss(bt)[0]) < 0.01, f"K{len(jumps)}: no way back ({A:.0f} m straight)"
            C = Road(f"K{len(jumps)}", "jump", cx0, cy0, hdg, JC_W,
                     [("S", A, 0, "sp"), ("L", Rs, JL_FORK + math.degrees(bt), "sp"), ("R", Rs, math.degrees(bt), "sp")])
            destination = roads.index(H)
            destination_h = baseline
            if jump_id in TRANSFER_JUMPS:
                # These land on a dedicated elevated interchange, then transfer to
                # the perpendicular highway. A distant merge permits open bends;
                # the old 40-50 km endpoints forced 300+ degree clover loops.
                # Keep the first six kilometres straight for ballistic capture.
                turn_dir = -d if axis == "E" else d
                dx, dy = (0.0, float(turn_dir)) if axis == "E" else (float(turn_dir), 0.0)
                destination = ns[ci] if axis == "E" else ew[cj]
                destination_h = EXPRESS_H if axis == "E" else 0.0
                gx = X + dx * TRANSFER_MERGE + dy * OFF
                gy = Y + dy * TRANSFER_MERGE - dx * OFF
                # Overfly the highway while high, then finish outside its correct
                # lane. This small S enters from the shoulder, without crossing
                # opposing traffic at grade or needing altitude-aware junctions.
                merge_angle = math.acos(1.0 - TRANSFER_OUT / (2 * Rs))
                merge_lead = 2 * Rs * math.sin(merge_angle) + TRANSFER_FINAL
                segs = [("S", 6000.0, 0, "sp")]
                segs += dubins((cx0 + ux * 6000.0, cy0 + uy * 6000.0, hdg),
                               (gx - dx * merge_lead + dy * TRANSFER_OUT,
                                gy - dy * merge_lead - dx * TRANSFER_OUT, heading_deg(dx, dy)), Rs)
                segs += [("L", Rs, math.degrees(merge_angle), "sp"),
                         ("R", Rs, math.degrees(merge_angle), "sp"), ("S", TRANSFER_FINAL, 0, "sp")]
                C = Road(f"K{jump_id}", "jump", cx0, cy0, hdg, JC_W, transfer_rhythm(segs, ref))
            C.role = "catch"
            C.profile = profile_name
            ip = round(JC_PULL / STEP)
            top = hc + ip * STEP * mc / 2.0          # the pull-out: a parabola to level
            i_flat = round((JC_FLAT - uc) / STEP)
            i_down = round((JC_DOWN - uc) / STEP)
            if jump_id in TRANSFER_JUMPS:
                i_flat = C.N - 1 - round(35000.0 / STEP)
                # Remain above the highway and nearby side-road mouths until the
                # outside approach, then level before the shared merge pavement.
                i_down = C.N - 1 - round(12000.0 / STEP)
            middle = round((i_flat + i_down) / 2)
            C.keys = [[0, hc, mc], [ip, top, 0.0], [i_flat, top, 0.0],
                      [middle, 0.0, 0.0],
                      [i_down, destination_h, 0.0], [C.N - 1, destination_h, 0.0]]
            # One smooth descent; the middle key carries the real derivative.
            u = (middle-i_flat)/(i_down-i_flat)
            C.keys[3][1] = top+(destination_h-top)*u*u*(3-2*u)
            C.keys[3][2] = (destination_h-top)*6*u*(1-u)/((i_down-i_flat)*STEP)
            joins.append((len(roads), 1, destination))
            roads.append(C)
            jumps.append((len(roads) - 2, len(roads) - 1, ref, h_lip, top))
    # the side roads
    for k, (hname, mid, sd, shape) in enumerate(SIDES):
        hi = next(q for q, R in enumerate(roads) if R.name == hname)
        H = roads[hi]
        half = OUT_BEND + SHAPES[shape]
        out_, in_ = ("L", "R") if sd > 0 else ("R", "L")
        def seg(q):
            if q[0] == "S":
                return ("S", q[1], 0, "sp")
            return (out_ if q[0] == "O" else in_, q[1], q[2], "sp")
        segs = [seg(q) for q in half] + [seg(q) for q in reversed(half)]
        varied = []
        for kind, radius, angle, mode in segs:
            if kind == 'S' or angle < 50 or radius <= 6000.0:
                varied.append((kind, radius, angle, mode))
            else:
                # Keep side-road bends above 6 km radius (their existing second-
                # gear floor), but interrupt hairpins/crooks with counter-steering.
                varied += varied_arc(kind, radius, angle, mode, max(6000.0, radius*0.70), math.ceil(angle/50.0))
        segs = varied
        # its length along the highway, walked from nothing: start so its middle lands at mid
        pts, end = walk(segs, 0.0, 0.0, 0.0)
        along = end[0]
        fx, fy = H.t[0]
        lat = sd * OFF
        x0 = H.x0 + fx * (mid - H1 / 2 - along / 2 + H1 / 2 - H0) - fy * lat
        y0 = H.y0 + fy * (mid - H1 / 2 - along / 2 + H1 / 2 - H0) + fx * lat
        S_ = Road(f"S{k}", "side", x0, y0, H.hdeg, W_SIDE, segs)
        S_.shape = shape
        joins += [(len(roads), 0, hi), (len(roads), 1, hi)]
        roads.append(S_)
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
    # the scenic roads: last, so every road and junction before them keeps its index
    scenic_roads.clear()
    for spec in SCENIC:
        x0, start_on, start_side, hdeg = spec["start"]
        end_on, end_side = spec["end"]
        P0 = next(R for R in roads if R.name == start_on)
        P1 = next(R for R in roads if R.name == end_on)
        assert P0.kind == "highway" and P1.kind == "highway" and abs(P0.hdeg) < 1e-9 and abs(P1.hdeg) < 1e-9
        segs = [(q[0], q[1] * KM, 0, "sp") if q[0] == "S" else (q[0], q[1] * KM, float(q[2]), "sp") for q in spec["plan"]]
        y0 = P0.y0 + start_side * OFF
        k = spec["stretch"]
        assert segs[k][0] == "S"
        # the stretch runs north or south: its length moves the end's y one for one
        _, end = walk(segs[:k], x0 * KM, y0, math.radians(hdeg))
        way = math.sin(end[2])
        assert abs(abs(way) - 1.0) < 1e-9, f"{spec['name']}: the stretch must run due north or south"
        _, end = walk(segs, x0 * KM, y0, math.radians(hdeg))
        length = segs[k][1] + (P1.y0 + end_side * OFF - end[1]) / way
        assert length > 2 * KM, f"{spec['name']}: its stretch comes out {length:.0f} m"
        segs[k] = ("S", length, 0, "sp")
        R = Road(spec["name"], "scenic", x0 * KM, y0, hdeg, SC_W, segs)
        assert abs(R.end[1] - (P1.y0 + end_side * OFF)) < 0.01 and abs(math.sin(R.end[2])) < 1e-9, f"{spec['name']} misses {end_on}"
        # where each segment starts, in samples (the sims' own count)
        R.seg0 = [0]
        for q in segs:
            R.seg0.append(R.seg0[-1] + max(1, math.ceil((q[1] if q[0] == "S" else q[1] * math.radians(q[2])) / STEP)))
        joins += [(len(roads), 0, roads.index(P0)), (len(roads), 1, roads.index(P1))]
        scenic_roads.append((len(roads), spec))
        roads.append(R)
    # Append after the existing scenic roads to preserve saved road and junction indices.
    by_name = {road.name: i for i, road in enumerate(roads)}
    for name, entry, exit_, radius, interior, relief in BACKROADS:
        parent, receiver = by_name[entry[0]], by_name[exit_[0]]
        start = backroad_mouth(roads[parent], *entry[1:])
        finish = backroad_mouth(roads[receiver], *exit_[1:])
        poses = [start] + [(x * KM, y * KM, h) for x, y, h in interior] + [finish]
        segments = []
        for a, b in zip(poses, poses[1:]):
            segments.extend(dubins(a, b, radius * KM))
        road = Road(name, "backroad", *start, 180.0, segments)
        # Hold the parent deck level through both physical joins. Rise and fall
        # with zero grade at each crest, using the simulation's Hermite heights.
        level = EXPRESS_H if entry[0].startswith("N") else 0.0
        end_level = EXPRESS_H if exit_[0].startswith("N") else 0.0
        profile = [(0, level), (.035, level), *relief, (.965, end_level), (1, end_level)]
        road.keys = [[round(f * (road.N - 1)), h, 0.0] for f, h in profile]
        joins.extend([(len(roads), 0, parent), (len(roads), 1, receiver)])
        roads.append(road)
    return roads, joins, cities, ew, ns, jumps, onramps, shafts


def scenic_at(R, seg, frac):
    """Sample `frac` of the way through segment `seg` of a scenic road's plan."""
    return int(round(R.seg0[seg] + (R.seg0[seg + 1] - R.seg0[seg]) * frac))


def scenic_table(roads):
    """[[road, sea side (1 left, -1 right, 0 none), [[sample, left m, its run m, right m, its run m, gap m], ...]], ...]:
    the land beside each scenic road. On the sea side the height is -5 (below the open ground's -4: between a
    flat end's -4 and it, the sea side begins halfway) and its run is the shelf."""
    out = []
    for r, spec in scenic_roads:
        R = roads[r]
        rows = []
        for seg, frac, left, lrun, right, rrun, gap in spec["land"]:
            i = scenic_at(R, seg, frac)
            h = R.h(i)
            side = []
            for v in (left, right):
                side.append(-5.0 if v == "sea" else (h + v[1] if isinstance(v, tuple) else float(v)))
            rows.append([i, round(side[0], 1), float(lrun), round(side[1], 1), float(rrun), float(gap)])
        assert all(a[0] < b[0] for a, b in zip(rows, rows[1:])), f"{R.name}: its land stations aren't in order"
        out.append([r, spec["sea"], rows])
    # Frostline is cut into a high saddle. Its two flanks trade sides at
    # the crest, then fade back into the existing landscape before the merge.
    r = next(i for i, road in enumerate(roads) if road.name == "SFrost")
    road = roads[r]
    rows = []
    for fraction, left, right in [
        (.045, -4, -4), (.12, 180, 90), (.26, 470, -65), (.39, 630, -190),
        (.47, 280, 230), (.56, -85, 430), (.67, 100, 210), (.75, -4, -4),
    ]:
        i = round(fraction * (road.N - 1))
        h = road.h(i)
        # At the ends the road land must meet both the deck and the base terrain.
        edge = 1 if .045 < fraction < .75 else max(1, h + 4)
        rows.append([i, max(-4, h + left) if edge == 1 else -4, 1750,
                     max(-4, h + right) if edge == 1 else -4, 2200, edge])
    out.append([r, 0, rows])
    return out


def junction(roads, c, end, p):
    """The zone where road c's end `end` joins road p: [p, a0, a1, c, b0, b1, sense]."""
    C, P = roads[c], roads[p]
    reach = (C.width + P.width) / 2
    idx = range(C.N) if end == 0 else range(C.N - 1, -1, -1)
    inside = []
    for i in idx:
        k, lat, _ = P.nearest(C.p[i])
        if C.kind == "turn" and (k == P.N - 1 or k == 0):   # a shaft's leg runs on past the highway's end: not joined there
            past = abs((C.p[i, 0] - P.p[k, 0]) * P.t[k, 0] + (C.p[i, 1] - P.p[k, 1]) * P.t[k, 1])
            if past > 2 * STEP:
                break
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
        H.keys = [[0, 0.0, 0.0]] + [[int(np.argmin(np.abs(H.p[:, 1] - y))), z, 0.0]
                                   for y, z in [(35000.0, 0.0), (55000.0, EXPRESS_H),
                                                (545000.0, EXPRESS_H), (565000.0, 0.0)]]
        H.keys.append([H.N - 1, 0.0, 0.0])
    for R in roads:
        if R.kind == "ramp":
            flat = round(RAMP_LEVEL / STEP)
            R.keys = [[0, 0.0, 0.0], [flat, 0.0, 0.0],
                      [R.N - 1 - flat, EXPRESS_H, 0.0], [R.N - 1, EXPRESS_H, 0.0]]
        elif R.kind == "side":
            base = EXPRESS_H if abs(R.hdeg - 90.0) < 0.01 else 0.0
            first = round(12000.0 / STEP)
            last = R.N - 1 - first
            # A series of broad crests and low saddles, with level mouths on the
            # same highway tier. Even ground-tier dips stay above terrain.
            R.keys = [[0, base, 0.0]]
            for q, rise in enumerate([0.0, 360.0, 60.0, 430.0, 100.0, 0.0]):
                R.keys.append([round(first+(last-first)*q/5), base+rise, 0.0])
            R.keys.append([R.N-1, base, 0.0])
    for r, spec in scenic_roads:
        R = roads[r]
        R.keys = [[0, 0.0, 0.0]] + [[scenic_at(R, seg, frac), float(h), float(m)] for seg, frac, h, m in spec["heights"]] + [[R.N - 1, 0.0, 0.0]]
        assert all(a[0] < b[0] for a, b in zip(R.keys, R.keys[1:])), f"{R.name}: its height keys aren't in order"
    return [[r, R.keys] for r, R in enumerate(roads) if R.keys]


def surface_overlaps(roads, joins, jumps):
    """Physical pavement union, separate from the highway -> ramp -> launch route graph."""
    out = []
    for launch, *_ in jumps:
        ramp = next(p for c, end, p in joins if c == launch and end == 0)
        parents = [p for c, _, p in joins if c == ramp]
        highway = min(parents, key=lambda p: roads[p].nearest(roads[launch].p[0])[2])
        out.append(junction(roads, launch, 0, highway))
    return out


def twists(roads, jumps):
    return [[jumps[k][1], round(6000.0 / STEP), round(17000.0 / STEP), 1 if n % 2 == 0 else -1]
            for n, k in enumerate(TWIST_JUMPS)]


def check(roads, joins, J, cities, ew, ns, jumps=(), onramps=(), overlaps=()):
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
        want = join_off.get((c, end), OFF)
        if abs(abs(lat) - want) > 0.5:
            bad(f"{C.name} end {end} sits {abs(lat):.2f} m off {P.name} (want {want:.0f})")
        h = math.radians(C.hdeg) if end == 0 else C.end[2]   # the pose, not the first chord
        ang = math.degrees(math.acos(min(1.0, abs(math.cos(h) * P.t[k, 0] + math.sin(h) * P.t[k, 1]))))
        if ang > (0.15 if (c, end) in join_off else 0.05):   # (a fork onto an arc: a chord's own angle)
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
    for j in list(J) + list(overlaps):
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
        if R.kind in ("highway", "turn"):
            continue   # (a shaft's plan is a paperclip by design: its legs share a wall)
        q = R.p[::sub]
        for a in range(len(q)):
            d = np.hypot(q[a + 30:, 0] - q[a, 0], q[a + 30:, 1] - q[a, 1]) if a + 30 < len(q) else np.array([])
            hit = np.where(d < R.width + GAP)[0]
            for h in hit:
                ia, ib = a * sub, (a + 30 + h) * sub
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
        angle = JUMP_ANGLES[ref]
        if abs(math.degrees(math.atan(m_lip)) - angle) > 0.05:
            bad(f"{L.name}'s lip is {math.degrees(math.atan(m_lip)):.2f} deg (want {angle})")
        gap = math.hypot(C.p[0, 0] - L.p[-1, 0], C.p[0, 1] - L.p[-1, 1])
        lands = []
        for mph in range(1500, 7001, 250):
            v = mph * MPH
            c2 = 1.0 / (1.0 + m_lip * m_lip)
            # A fast arrival can meet the rising catch a little beyond its leading edge.
            arrives_above = h_lip + gap * m_lip - G * gap ** 2 / (2 * v * v * c2) >= C.h(0)
            lands.append((mph, arrives_above and any(0.0 <= h_lip + (gap + s) * m_lip
                                  - G * (gap + s) ** 2 / (2 * v * v * c2)
                                  - C.h(s / STEP) <= JC_REACH for s in range(0, 4001, 24))))
        lo = min((m for m, ok_ in lands if ok_), default=None)
        if lo is None or lo > ref + 1 or not all(ok_ for m, ok_ in lands if m >= lo):
            bad(f"{L.name}: lands {[m for m, ok_ in lands if ok_]} (want {ref:.0f} mph and up)")
        print(f"  jump {L.name} -> {C.name}: lip {h_lip:.0f} m at {angle} deg, {gap:.0f} m to a deck "
              f"{C.h(0) - h_lip:.0f} m above it ({(C.h(0) - h_lip) / 0.3048:.0f} ft), level at {top:.0f} m; lands from {lo} mph")
    for k, r in onramps:
        O = roads[r]
        print(f"  on-ramp {O.name}: from {O.p[0, 0] / KM:.1f},{O.p[0, 1] / KM:.1f} km on the open ground")
    for r, spec in scenic_roads:
        R = roads[r]
        hs = np.array([R.h(i) for i in range(R.N)])
        grade = np.diff(hs) / R.len[:-1]
        bend = np.diff(grade) / R.len[1:-1]
        tight = min(q[1] for q in R.segs if q[0] != "S")
        print(f"  scenic {R.name}: {R.len[:-1].sum() / KM:.0f} km, x {R.p[:, 0].min() / KM:.1f}-{R.p[:, 0].max() / KM:.1f} km, "
              f"y {R.p[:, 1].min() / KM:.1f}-{R.p[:, 1].max() / KM:.1f} km, {hs.min():.0f}-{hs.max():.0f} m up, steepest {abs(grade).max() * 100:.1f}%, "
              f"tightest crest or dip {1 / abs(bend).max() / KM:.1f} km, tightest bend {tight / KM:.0f} km, "
              f"its stretch {R.segs[spec['stretch']][1] / KM:.1f} km, ends at x {R.end[0] / KM:.1f} km")
        if hs.min() < -0.01:
            bad(f"{R.name} dips to {hs.min():.1f} m")
        if abs(grade).max() > 0.30:
            bad(f"{R.name} is {abs(grade).max() * 100:.0f}% at its steepest (30 at most)")
        if not 0 < R.p[:, 0].min() and R.p[:, 0].max() < 600 * KM:
            bad(f"{R.name} leaves the map")
    return ok


def main():
    roads, joins, cities, ew, ns, jumps, onramps, shafts = build()
    J = [junction(roads, c, end, p) for c, end, p in joins]
    H = heights(roads, ew, ns)
    overlaps = surface_overlaps(roads, joins, jumps)
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
    ok = check(roads, joins, J, cities, ew, ns, jumps, onramps, overlaps)
    if km > 9000 or N > 380000:
        ok = False
        print(f"  BAD  too big: {km:.0f} km, {N} samples")
    print("NETWORK DESIGN OK" if ok else "NETWORK DESIGN NOT OK")
    if "--plot" in sys.argv:
        plot(roads, cities, sys.argv[sys.argv.index("--plot") + 1] if len(sys.argv) > sys.argv.index("--plot") + 1 else "network.png")
    return roads, J, cities, H, ok, jumps, onramps, shafts, overlaps, twists(roads, jumps)


def plot(roads, cities, out):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    fig, ax = plt.subplots(figsize=(10, 10))
    col = {"highway": "#2a6fdb", "ramp": "#6a8", "city": "#d33", "turn": "#999", "jump": "#f80", "on": "#a0a", "side": "#0a7", "scenic": "#c0f", "backroad": "#a65b28"}
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
