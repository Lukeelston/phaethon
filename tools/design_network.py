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
- twenty jump sets at the five non-corner crossings, plus J20 northbound at Mesa. A launch spur forks
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
Helios (Luke, 2026-11-20): one mountain north of E3 (helios_z, which the views mirror), and SHelios, a
scenic road off E3's north shoulder that spirals up it clockwise, crosses its top, spirals down
counter-clockwise and rejoins E3 (add_helios). Its heights are the mountain's surface (keys with the
surface's own slopes); its land is the surface either side. Since 2026-11-21 ("an unreasonably steep
mountain to climb vertically ... and plateau over the top") the dome carries a spire, 16 km high: from a
shoulder 9 km out its pitch grows to 75 degrees, then rolls over onto a plateau 6 km across; the road
leaves its inner lap for the Face, straight up the spire, across the plateau and down the far side.
Hyperion (Luke, 2026-11-21: "add another one ... 3 times - it should be inconceivable"): a second
mountain, 48 km high, in the middle of the north-west cell (hyperion_z, which the views mirror), and
SHyperion, one straight line from E2's north shoulder to E3's south that goes up its ramp (a quarter of
a circle in profile, to 88 degrees), over its summit and down its cliff (add_hyperion). That road is a
"deck road": from the ramp's foot to the run-out's end it is sampled every STEP of its deck, not of the
map (the "V" and "W" segments), and the sims carry a craft along it at its speed along the deck; its
width changes along it (200 m at its mouths, 800 m over the mountain).
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


# Grade-separated stunt bypasses leave a straight highway on one shoulder, run parallel,
# and merge back downstream. Horizontal distances in km, relief in metres above the parent.
STUNT_ROADS = [
    ("SNeedle", "E2", 174, 1, 8.5, 25, 13,
     [(0, 0), (.09, 0), (.275, 510), (.725, 510), (.91, 0), (1, 0)]),
    ("SHammer", "N2", 352, -1, 7, 35, 9,
     [(0, 0), (.09, 0), (.36, 1350), (.42, 1350), (.67, -200), (.81, 220), (.92, 0), (1, 0)]),
]


# Helios (Luke, 2026-11-20): one giant mountain north of E3, between N2 and N3, and a road that winds up
# it on a double spiral: in clockwise, an S over the exact summit, out counter-clockwise. The mountain
# is helios_z and nothing else (the views mirror that function exactly), and the road lies on it.
HELIOS = (400000.0, 549000.0, 10400.0, 36000.0)   # centre x, centre y (m), the dome's height (m: its top is inside the spire), foot radius (m)
# The spire (Luke, 2026-11-21: "I really meant like an unreasonably steep mountain to climb vertically ... I want
# to drive an increasingly steep mountain and plateau over the top to something spectacular"). Inside the
# shoulder the dome gives way to a tower: its pitch grows by the same angle with every metre in, from the
# dome's own at the shoulder to the wall's; from the wall it eases the same way to level at the rim of a flat
# plateau. (Pitch even per metre of plan, because the sims fly a road at its plan speed whatever its grade: a
# craft's pitch then changes at a steady rate up the climb and another over the crest. See add_helios.)
# (The wall at 80 deg: a 17.5 km summit, and everything along the road 5.8 times its plan length, not 3.9. A
# crest of 2,400 m: 16,155 m, and the ideal pilot's pitch falling 48 deg/s over it; of 2,880 m, 40.)
HELIOS_SPIRE = (9000.0, 3000.0, 2880.0, 75.0)   # shoulder radius, plateau radius, the crest's run in from the wall (m), the wall's pitch (deg)
HELIOS_FACE = (4.5 * KM, 600.0)          # the Face: the radius of the turns onto and off it, the straight below each shoulder (m)
HELIOS_FIT = 0.001                       # the road's height keys hold it this near the surface at every sample (m)
HELIOS_RHO, HELIOS_D = 12 * KM, 6 * KM   # the spiral's inner radius, and how far each half turn steps in or out
HELIOS_MOUTHS = ("E3", 345, 456)         # both on E3's north shoulder, travelling east: in at km 345, out at km 456
HELIOS_TURN = 9 * KM                     # the two connectors' Dubins radius
HELIOS_LEAD = 24 * KM                    # the way in: straight up the spiral's tangent to its start (Dubins all the way: 26 %)
HELIOS_UNWIND = (60 * KM, 25.0)          # the way out: one last, wider left arc to the foot (Dubins all the way: 33 %; a straight: 24 %)
HELIOS_KEY = 25                          # a height key every so many samples: the surface's own height and slope
HELIOS_FLAT = 40                         # each mouth's samples at exactly 0 m
HELIOS_GRADE = 0.22                      # the spiral laps' steepest (the Face is exempt: its limit is the wall's own pitch)
HELIOS_LAND = (60, 30.0, 600.0)          # its land: a row every 60 samples while it's over 30 m up, each side's run (m)
HELIOS_LAND_FIT = (4.0, 0.25)            # ... and more on the Face, so the views' blend between rows keeps each side within 4 m (or a quarter of its drop)

# Hyperion (Luke, 2026-11-21, of Helios: "its still not what i was talking about. Keep it as it is, and add
# another one, twice as tall. Maybe 3 times - it should be inconceivable. Then it should have a steadily
# steepening ramp until it's basically straight up, then a braking section to crest over the top, enjoy the
# view from the top, then creep over a cliff and scream down the other side. It should be wide and imposing.
# The hill climb road to end all roads. Olympus mons, but bigger."). A second mountain, in the empty middle of
# the north-west cell, and SHyperion: one straight line from E2 to E3 that goes over it. Along the road, in
# order: the ramp (a quarter of a circle in profile: its pitch grows by the same angle with every metre
# travelled, from level to the wall's), the wall, the crest (the braking section is the wall and the crest),
# the summit (level), the lip, the wall down, the run-out. Each is a whole number of the road's samples, and
# the two walls' pitches are whatever then makes the summit HYPERION_H exactly (hyperion_shape).
# The road is sampled every STEP of its DECK from the ramp's foot to the run-out's end (the "V" and "W"
# segments: walk), not every STEP of plan: at 88 degrees a sample of plan is 690 m of wall. The sims carry a
# craft along such a road (NET_DECK) at its speed along the deck (craft_sim.gd / sim-core.js).
HYPERION_H = 48000.0                     # the summit (m): three times Helios
HYPERION_MOUTHS = ("E2", 132, "E3")      # off E2's north shoulder at km 132, travelling east; onto E3's south shoulder, travelling east
HYPERION_HEADING = 60.0                  # the road's heading from one turn to the other, degrees north of east
HYPERION_TURN = 12 * KM                  # the two turns' radius (second gear wants 5.9 km)
HYPERION_APPROACH = 1350                 # samples of level straight before the ramp's foot (32.4 km)
HYPERION_UP = (2880, 70, 192)            # samples: the ramp, the wall, the crest (69.1 km, 1.7 km, 4.6 km of deck)
HYPERION_TOP = 200                       # ... the summit (4.8 km)
HYPERION_DOWN = (19, 1345, 1024)         # ... the lip, the wall down, the run-out (0.46 km, 32.3 km, 24.6 km)
HYPERION_W = (800.0, 20, 220)            # the deck's width from the approach to the far straight (the mouths are SC_W); it widens from so many samples past the first turn, over so many
HYPERION_PLATEAU = (3000.0, 1200.0)      # the summit plateau: half its width across the road, its corners' radius (its length is the summit's)
HYPERION_SKIRT = (10000.0, 8000.0)       # the mountain's sides: this much more run at the foot than the ramp's own, gone by this height
HYPERION_KEY = (24, 6, 1)                # a height key every so many samples on the ramp and the run-out, on the crest, on the lip
HYPERION_LAND = (60, 600.0)              # its land's rows: every so many samples on the mountain, each side's run (m)


def helios_spire():
    """The spire's own figures, from HELIOS and HELIOS_SPIRE: the dome's height and pitch (rad) at the shoulder,
    the wall's radius, pitch (rad) and height, the pitch gained per metre up the climb and lost per metre
    over the crest (rad/m), the summit's height."""
    _, _, H, R = HELIOS
    rs, rp, lc, wall = HELIOS_SPIRE
    us = rs / R
    zs = H * (1 - us * us) ** 2
    ts = math.atan(4 * H * us * (1 - us * us) / R)
    tm = math.radians(wall)
    rw = rp + lc
    a = (tm - ts) / (rs - rw)
    b = tm / lc
    zw = zs + math.log(math.cos(ts) / math.cos(tm)) / a
    return zs, ts, rw, tm, zw, a, b, zw - math.log(math.cos(tm)) / b


def helios_z(x, y):
    """The mountain. Outside the shoulder the dome: H (1 - u^2)^2, 0 at and beyond its foot (steepest, 44 %,
    about 21 km out). Inside it the spire: the climb, whose pitch is the dome's at the shoulder and grows
    by `a` a metre to the wall's; the crest, whose pitch falls by `b` a metre to nothing at the rim; the
    plateau, level. (A slope tan(t0 + a s) has height ln(cos t0 / cos(t0 + a s)) / a.) Height and slope are
    continuous everywhere; the curvature steps at the shoulder, the wall and the rim."""
    cx, cy, H, R = HELIOS
    rs, rp, lc, wall = HELIOS_SPIRE
    r = math.hypot(x - cx, y - cy)
    if r >= rs:
        u = min(r / R, 1.0)
        return H * (1 - u * u) ** 2
    zs, ts, rw, tm, zw, a, b, top = helios_spire()
    if r >= rw:
        return zs + math.log(math.cos(ts) / math.cos(ts + a * (rs - r))) / a
    if r > rp:
        return zw + math.log(math.cos(b * (r - rp)) / math.cos(tm)) / b
    return top


def _solve(f, lo, hi):
    for _ in range(200):
        mid = (lo + hi) / 2
        if f(mid) > 0.0:
            hi = mid
        else:
            lo = mid
    return (lo + hi) / 2


def hyperion_shape():
    """Hyperion's own figures, from the constants: the walls' pitches up and down (rad) that put the summit at
    HYPERION_H with every part a whole number of samples; the radii (the ramp's, the crest's, the lip's, the
    run-out's) and the walls' lengths along the deck; the heights where the parts meet; each side's run."""
    H = HYPERION_H
    n1, nw, nc = HYPERION_UP
    nl, nd, n2 = HYPERION_DOWN
    tm = _solve(lambda t: STEP * (n1 + nc) * (1 - math.cos(t)) / t + STEP * nw * math.sin(t) - H, 1.3, 1.57)
    td = _solve(lambda t: STEP * (nl + n2) * (1 - math.cos(t)) / t + STEP * nd * math.sin(t) - H, 1.3, 1.57)
    S = dict(H=H, tm=tm, td=td, R1=STEP * n1 / tm, Lw=STEP * nw, Rc=STEP * nc / tm, Rl=STEP * nl / td, Ld=STEP * nd, R2=STEP * n2 / td,
             top=STEP * HYPERION_TOP)
    S["zc"] = H - S["Rc"] * (1 - math.cos(tm))    # the crest's foot: the top of the wall
    S["zw"] = S["zc"] - S["Lw"] * math.sin(tm)    # ... and the wall's: the top of the ramp
    S["zl"] = H - S["Rl"] * (1 - math.cos(td))    # the lip's foot: the top of the wall down
    S["zo"] = S["zl"] - S["Ld"] * math.sin(td)    # ... and that wall's: the top of the run-out
    S["front"] = S["Rc"] * math.sin(tm) + S["Lw"] * math.cos(tm) + S["R1"] * math.sin(tm)    # plan, from the plateau's edge to the ramp's foot
    S["back"] = S["Rl"] * math.sin(td) + S["Ld"] * math.cos(td) + S["R2"] * math.sin(td)     # ... and to the run-out's end
    assert abs(S["zw"] - S["R1"] * (1 - math.cos(tm))) < 1e-6 and abs(S["zo"] - S["R2"] * (1 - math.cos(td))) < 1e-6
    return S


def hyperion_out(S, z, c):
    """How far out from the plateau's edge (m, in plan) the mountain stands z high, where the way out from the
    plateau makes an angle with the way the road came whose cosine is c (1: the ramp's side, -1: the cliff's,
    0: either flank). The ramp's side is the road's own profile up, the cliff's its profile down, a flank the
    ramp's with HYPERION_SKIRT more run low down; between, each by the square of its part of the direction."""
    z = min(max(z, 0.0), S["H"])
    acos = lambda v: math.acos(min(1.0, max(-1.0, v)))
    tm, td = S["tm"], S["td"]
    if z >= S["zc"]:
        front = S["Rc"] * math.sin(acos(1 - (S["H"] - z) / S["Rc"]))
    elif z >= S["zw"]:
        front = S["Rc"] * math.sin(tm) + (S["zc"] - z) / math.tan(tm)
    else:
        front = S["Rc"] * math.sin(tm) + S["Lw"] * math.cos(tm) + S["R1"] * (math.sin(tm) - math.sin(acos(1 - z / S["R1"])))
    if c >= 1.0:
        return front
    if z >= S["zl"]:
        back = S["Rl"] * math.sin(acos(1 - (S["H"] - z) / S["Rl"]))
    elif z >= S["zo"]:
        back = S["Rl"] * math.sin(td) + (S["zl"] - z) / math.tan(td)
    else:
        back = S["Rl"] * math.sin(td) + S["Ld"] * math.cos(td) + S["R2"] * (math.sin(td) - math.sin(acos(1 - z / S["R2"])))
    more, by = HYPERION_SKIRT
    side = front + (more * (1 - z / by) ** 2 if z < by else 0.0)
    c2 = c * c
    return (c2 * front if c > 0.0 else c2 * back) + (1 - c2) * side


hyperion_at = {}   # the summit's centre and the road's way over it, set when the road is laid (add_hyperion): cx, cy, ux, uy


def hyperion_z(x, y):
    """The mountain: HYPERION_H on its plateau (a rounded rectangle about the summit's centre, as long as the
    summit and HYPERION_PLATEAU wide), and round it the height at which hyperion_out, in the direction straight
    out from the plateau's edge, is the distance out from that edge. The views mirror this exactly
    (view/hyperion.gd). Ahead of and behind the plateau's straight ends the direction is the road's own, so
    across the middle 3.6 km the mountain is the road's profile exactly: a face, not a ridge."""
    S = hyperion_shape()
    cx, cy, ux, uy = hyperion_at["cx"], hyperion_at["cy"], hyperion_at["ux"], hyperion_at["uy"]
    half, corner = HYPERION_PLATEAU
    u = (x - cx) * ux + (y - cy) * uy          # along the road
    v = -(x - cx) * uy + (y - cy) * ux         # to its left
    qu, qv = abs(u) - (S["top"] / 2 - corner), abs(v) - (half - corner)
    mu, mv = max(qu, 0.0), max(qv, 0.0)
    m = math.hypot(mu, mv)
    out = m + min(max(qu, qv), 0.0) - corner
    if out <= 0.0:
        return S["H"]
    c = -math.copysign(mu, u) / m if m > 0.0 else 0.0      # the cosine of the way out against the way the road came
    if out >= hyperion_out(S, 0.0, c):
        return 0.0
    lo, hi = 0.0, S["H"]
    for _ in range(60):
        mid = (lo + hi) / 2
        if hyperion_out(S, mid, c) > out:
            lo = mid
        else:
            hi = mid
    return (lo + hi) / 2


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
        elif s[0] == "W":
            # a wall: straight in plan, s[1] m of deck at a pitch of s[2] degrees, a sample every STEP of the deck
            n = max(1, round(s[1] / STEP))
            d = s[1] / n * math.cos(math.radians(s[2]))
            for _ in range(n):
                pts.append((x, y))
                x += d * math.cos(h)
                y += d * math.sin(h)
        elif s[0] == "V":
            # a vertical arc: straight in plan, the deck a circle of radius s[1] in profile from a pitch of s[2]
            # degrees to one of s[4], a sample every STEP of the deck (each step's plan: its chord's)
            a0, a1 = math.radians(s[2]), math.radians(s[4])
            n = max(1, round(s[1] * abs(a1 - a0) / STEP))
            da = (a1 - a0) / n
            c = 2 * s[1] * math.sin(abs(da) / 2)
            for k in range(n):
                pts.append((x, y))
                d = c * math.cos(a0 + (k + 0.5) * da)
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


def seg_samples(s):
    """How many samples a segment is walked in (walk)."""
    if s[0] == "W":
        return max(1, round(s[1] / STEP))
    if s[0] == "V":
        return max(1, round(s[1] * abs(math.radians(s[4]) - math.radians(s[2])) / STEP))
    return max(1, math.ceil((s[1] if s[0] == "S" else s[1] * math.radians(s[2])) / STEP))


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
            n = seg_samples(s)
            if s[3] == "sf":
                self.mode[i:i + n] = 0
            i += n
        self.wid = None     # its width at every sample, where that isn't `width` all along (SHyperion)
        self.deck = False   # sampled along its deck, and flown at the speed along it (SHyperion)

    def w(self, i):
        return self.width if self.wid is None else float(self.wid[i])

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


def add_jump(roads, joins, jumps, ew, ns, ci, cj, axis, d, ref):
    """Fork from the right-hand interchange ramp, fly the gap, then rejoin the highway."""
    X, Y = LINES[ci], LINES[cj]
    jump_id = len(jumps)
    profile = jump_id % len(JUMP_PROFILES)
    profile_name, extra_rise, gap_scale = JUMP_PROFILES[profile]
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


def hermite_all(keys, N):
    """hermite() at every whole sample 0..N-1 in one pass (a road with hundreds of keys)."""
    out = np.zeros(N)
    for a, b in zip(keys, keys[1:]):
        n = max(1, b[0] - a[0])
        u = (np.arange(a[0], b[0] + 1) - a[0]) / n
        d = n * STEP
        u2, u3 = u * u, u * u * u
        out[a[0]:b[0] + 1] = ((2 * u3 - 3 * u2 + 1) * a[1] + (u3 - 2 * u2 + u) * d * a[2]
                              + (-2 * u3 + 3 * u2) * b[1] + (u3 - u2) * d * b[2])
    return out


def add_helios(roads, joins):
    """SHelios: off E3's north shoulder, up the mountain's west side to the spiral's start, round it clockwise
    (a half turn, then as much of the next, HELIOS_D further in, as leaves room to turn), the Face (a
    tighter right turn that ends pointing at the centre, straight up the spire's fall line, over the rim,
    across the plateau through its exact centre, down the far face and a left turn off it: the way in,
    turned half round about the summit), round it counter-clockwise (the rest of that lap and a quarter,
    each further out), and back onto E3. Its plan's spiral is explicit arcs; Dubins only joins it to E3.
    Its heights are the mountain's own.

    What the sims do with a grade (sim-core.js railHover, craft_sim.gd _rail_hover): a body on a road is
    held on its deck, down as well as up, whatever the crest or dip, and nothing but a shaft's climb pulls
    gravity along a road. So the Face is flown at the plan speed the pilot holds: the climb is free, a craft
    never leaves the deck over the rim (a crest a craft could follow unheld at 1,500 m/s is 229 km in
    radius; let go at the wall, climbing 4.9 km/s as the tests' pilot does, it would coast 1,200 km up:
    there is no flight to design), and its pitch changes at (plan speed) x (pitch per metre): the reason
    the spire's pitch is even per metre of plan. What that costs: at a pitch t everything along the road is
    1 / cos t its plan length (3.9 at the wall): the speed over the surface, and the craft's own bodies,
    which the sims keep their plan distance apart."""
    cx, cy, H, foot = HELIOS
    rho, d = HELIOS_RHO, HELIOS_D
    rs, rp, lc, wall = HELIOS_SPIRE
    zs, ts, rw, tm, zw, pitch_up, pitch_over, top = helios_spire()
    radius, below = HELIOS_FACE
    parent = next(i for i, R in enumerate(roads) if R.name == HELIOS_MOUTHS[0])
    start = backroad_mouth(roads[parent], HELIOS_MOUTHS[1], 1, 1)
    finish = backroad_mouth(roads[parent], HELIOS_MOUTHS[2], 1, 1)
    # The Face's plan. Its straight starts `reach` from the centre, on the dome below the shoulder. The inner
    # lap (radius `lap` about a point d / 2 east of the centre, clockwise from E18) is left `phi` round it by a
    # right turn of `radius` whose centre is then sqrt(reach^2 + radius^2) from the mountain's: the turn's
    # tangent through the summit is `reach` long. Every radius of the spire and `reach` itself are whole
    # samples, and the straight is whole samples long, so each of the surface's joins lies on a sample.
    reach, lap = rs + below, rho + 0.5 * d
    assert all(abs(v / STEP - round(v / STEP)) < 1e-9 for v in (reach, rs, rw, rp)), "the spire's radii and the Face's reach must be whole samples"
    cos_phi = (reach ** 2 + radius ** 2 - (d / 2) ** 2 - (lap - radius) ** 2) / (d * (lap - radius))
    assert -1.0 < cos_phi < 1.0, f"SHelios: no turn of {radius:.0f} m off the inner lap reaches the Face"
    phi = math.acos(cos_phi)
    tcx, tcy = d / 2 + (lap - radius) * math.cos(phi), -(lap - radius) * math.sin(phi)   # the turn's centre, from the mountain's
    bearing = math.atan2(-tcy, -tcx) + math.acos(radius / math.hypot(tcx, tcy))          # ... and from it, where the straight starts
    turn = (-phi - bearing) % (2 * math.pi)
    assert math.radians(20.0) < turn < math.radians(200.0), f"SHelios: the turn onto the Face is {math.degrees(turn):.0f} deg"
    fx, fy = tcx + radius * math.cos(bearing), tcy + radius * math.sin(bearing)          # the straight's start, from the centre
    fh = math.degrees(bearing) - 90.0                                                    # ... and its heading
    lx, ly, lh = d / 2 + lap * math.cos(phi), -lap * math.sin(phi), -90.0 - math.degrees(phi)   # where the lap is left
    spiral = [("R", rho + 1.5 * d, 180.0, "sp"), ("R", lap, math.degrees(phi), "sp"),     # in: W24, over the north, E18, part way round the south
              ("R", radius, math.degrees(turn), "sp"), ("S", 2 * reach, 0, "sp"),         # the Face: the turn on, up, over and down
              ("L", radius, math.degrees(turn), "sp"),                                    # ... and the turn off
              ("L", lap, math.degrees(phi), "sp"), ("L", rho + 1.5 * d, 90.0, "sp")]      # out: the rest of that lap to W18, the south point (heading east)
    way = [("W24", cx - rho - 2 * d, cy, 90.0), ("E18", cx + rho + d, cy, -90.0), ("turn on", cx + lx, cy + ly, lh),
           ("face", cx + fx, cy + fy, fh), ("face's end", cx - fx, cy - fy, fh), ("turn off", cx - lx, cy - ly, lh),
           ("W18", cx - rho - d, cy, -90.0), ("south", cx + d / 2, cy - rho - 1.5 * d, 0.0)]

    def connector(a, b):
        segs = dubins(a, b, HELIOS_TURN)
        assert segs[1][1] > KM and all(1.0 < q[2] < 180.0 for q in (segs[0], segs[2])), f"SHelios: Dubins looped or collapsed ({segs})"
        return segs
    # In: Dubins to a pose on the spiral's tangent, HELIOS_LEAD short of its start, and straight up it
    # (the mountain's steepest ring is where a direct Dubins would cut across the slope).
    segs = connector(start, (way[0][1], way[0][2] - HELIOS_LEAD, 90.0)) + [("S", HELIOS_LEAD, 0, "sp")]
    first = len(segs)
    # Out: the last quarter turn unwinds on one wider arc to the foot, and Dubins from there.
    segs += spiral + [("L", HELIOS_UNWIND[0], HELIOS_UNWIND[1], "sp")]
    _, end = walk(segs, start[0], start[1], math.radians(start[2]))
    segs += connector((end[0], end[1], math.degrees(end[2])), finish)
    road = Road("SHelios", "scenic", *start, SC_W, segs)
    seg0 = [0]   # where each segment starts, in samples
    for q in segs:
        seg0.append(seg0[-1] + max(1, math.ceil((q[1] if q[0] == "S" else q[1] * math.radians(q[2])) / STEP)))
    assert seg0[-1] == road.N - 1
    road.way = []
    for n, (name, x, y, hdeg) in enumerate(way):
        i = seg0[first + n]
        miss = math.hypot(road.p[i, 0] - x, road.p[i, 1] - y)
        turn = math.degrees(math.acos(min(1.0, road.t[i, 0] * math.cos(math.radians(hdeg)) + road.t[i, 1] * math.sin(math.radians(hdeg)))))
        assert miss < 30.0 and turn < 0.5, f"SHelios misses {name} by {miss:.1f} m, {turn:.2f} deg"
        road.way.append((name, i))
    r = np.hypot(road.p[:, 0] - cx, road.p[:, 1] - cy)
    # the connectors' Dubins stretches keep off the mountain's steep ring
    assert r[:seg0[3] + 1].min() > 30 * KM and r[seg0[-4]:].min() > 30 * KM, "SHelios: a connector cuts in under 30 km"
    # The Face's samples: its straight is whole samples of exactly STEP, through the exact centre, so the
    # shoulders, the walls and the rims are samples too. `on`/`off`: where the lap is left and rejoined.
    f0, f1 = seg0[first + 3], seg0[first + 4]
    k = lambda q: round((reach - q) / STEP)
    face = dict(on=seg0[first + 2], start=f0, shoulder=f0 + k(rs), wall=f0 + k(rw), rim=f0 + k(rp), centre=f0 + k(0.0),
                rim2=f1 - k(rp), wall2=f1 - k(rw), shoulder2=f1 - k(rs), end=f1, off=seg0[first + 5])
    assert f1 - f0 == 2 * k(0.0) and abs(road.len[f0:f1] - STEP).max() < 1e-6, "SHelios: the Face's straight isn't whole samples"
    for name, q in [("shoulder", rs), ("wall", rw), ("rim", rp), ("centre", 0.0)]:
        for i in {face[name], face.get(name + "2", face[name])}:
            assert abs(r[i] - q) < 1e-3, f"SHelios: the Face's {name} is {abs(r[i] - q):.4f} m off sample {i}"
    # Heights: the surface's own, and its own slope along the road, so the sims' Hermite cubics lie on
    # the mountain between keys; both mouths exactly level on the open ground. A slope is the surface's
    # rise per sample over STEP (the sims' Hermite counts every sample as STEP long; a segment's are a
    # shade shorter), measured a quarter of a millimetre either way along the road's own chords: over whole
    # samples, as it was on the dome, it strays where the Face's pitch runs away from a cubic.
    z = [helios_z(x, y) for x, y in road.p]
    for i in range(face["rim"], face["rim2"] + 1):
        assert abs(z[i] - top) < 1e-9
        z[i] = top             # (the two rims' samples are the plateau's: level, to the last bit)
    last, flat = road.N - 1, HELIOS_FLAT
    assert max(z[:flat + 1]) == 0.0 and max(z[last - flat:]) == 0.0, "SHelios: a mouth is on the mountain"

    def key(i, e=1e-5):
        if z[i] == 0.0 or face["rim"] <= i <= face["rim2"]:   # off the mountain (both mouths' HELIOS_FLAT samples too), or on the plateau: level
            return [i, z[i], 0.0]
        ahead = helios_z(*(road.p[i] + e * (road.p[i + 1] - road.p[i])))
        behind = helios_z(*(road.p[i] - e * (road.p[i] - road.p[i - 1])))
        return [i, z[i], (ahead - behind) / (2 * e * STEP)]
    # A cubic can't span a jump in curvature: the road's own where a new segment starts, the surface's at
    # the foot, the shoulder, the wall and the rim. Each has a key on it, or (the foot, which no sample is
    # on) on the sample either side. Between those, a key every HELIOS_KEY samples, and more wherever the
    # cubic between two would leave the surface by HELIOS_FIT at a sample (the Face: up to one a sample).
    must = set(range(0, last, HELIOS_KEY)) | {flat, last - flat, last} | set(seg0[1:-1])
    for i in range(last):
        if any((r[i] - q) * (r[i + 1] - q) <= 0.0 for q in (foot, rs, rw, rp)):
            must |= {i, i + 1}

    def between(a, b):
        ka, kb = key(a), key(b)
        if b - a < 2 or max(abs(hermite([ka, kb], i) - z[i]) for i in range(a + 1, b)) <= HELIOS_FIT:
            return []
        m = (a + b) // 2
        return between(a, m) + [m] + between(m, b)
    must = sorted(must)
    for a, b in zip(must, must[1:]):
        road.keys += [key(a)] + [key(i) for i in between(a, b)]
    road.keys.append(key(last))
    # Where every key is level and alike (off the mountain, and across the plateau) only each such run's
    # two ends are kept (the same heights exactly: the sims look a height up through the keys).
    level = [q[2] == 0.0 for q in road.keys]
    same = [n > 0 and q[1] == road.keys[n - 1][1] for n, q in enumerate(road.keys)]
    road.keys = [q for n, q in enumerate(road.keys) if not (0 < n < len(level) - 1 and level[n - 1] and level[n] and level[n + 1] and same[n] and same[n + 1])]
    assert all(p[0] < q[0] for p, q in zip(road.keys, road.keys[1:])), "SHelios: its height keys aren't in order"
    hs = hermite_all(road.keys, road.N)
    assert all(abs(hs[i] - road.h(i)) < 1e-9 for i in range(0, road.N, 997))
    grade = np.abs(np.diff(hs)) / road.len[:-1]
    off = float(np.abs(hs - np.array(z)).max())
    # ... and between the samples, where the sims fly: against the surface under the middle of each chord
    half = float(max(abs(road.h(i + 0.5) - helios_z(*((road.p[i] + road.p[i + 1]) / 2))) for i in range(last)))
    # The laps keep HELIOS_GRADE. The Face (from where the lap is left to where it is rejoined) keeps the
    # wall's own pitch; up it the grade grows at every sample from the shoulder to the wall, falls at every
    # one from the wall to the rim, and the plateau between the rims is level. Down it, the same reversed.
    laps = np.concatenate([grade[:face["on"]], grade[face["off"]:]])
    assert laps.max() <= HELIOS_GRADE, f"SHelios' laps are {laps.max() * 100:.1f}%"
    steep = int(np.argmax(grade))
    assert grade.max() <= math.tan(tm) + 1e-9 and face["on"] <= steep < face["off"], f"SHelios is {grade.max() * 100:.1f}% at sample {steep}"
    up = np.diff(hs)[face["shoulder"]:face["rim"]]
    down = -np.diff(hs)[face["rim2"]:face["shoulder2"]][::-1]
    n_up = face["wall"] - face["shoulder"]
    for g in (up, down):
        assert np.all(np.diff(g[:n_up]) > 0.0) and np.all(np.diff(g[n_up - 1:]) < 0.0), "SHelios: the Face's grade doesn't grow to the wall and ease to the rim"
    assert abs(hs[face["rim"]:face["rim2"] + 1] - top).max() < 1e-6, "SHelios: the plateau isn't level"
    assert (face["rim2"] - face["rim"]) * STEP >= 3 * KM, "SHelios: under 3 km of level road on the plateau"
    assert abs(hs.max() - top) < 1e-6 and hs.min() >= 0.0 and off <= HELIOS_FIT + 1e-9 and half < 0.02, f"SHelios: {hs.min():.2f}-{hs.max():.2f} m, {off:.4f} m off the surface at a sample, {half:.4f} m between"
    # The profile's true radii (of the curve the road draws in the vertical plane, not 1 / the grade's change):
    # (1 + g^2)^1.5 / |g'|, tightest at the rim over the crest and at the shoulder up the climb.
    g = np.diff(hs[f0:f1 + 1]) / STEP
    rad = (1 + ((g[1:] + g[:-1]) / 2) ** 2) ** 1.5 / np.maximum(np.abs(np.diff(g)) / STEP, 1e-12)
    n0 = face["shoulder"] - f0
    crest = float(rad[face["wall"] - f0:face["rim"] - f0 - 1].min())
    dip = float(rad[n0:face["wall"] - f0 - 1].min())
    lap_at = int(np.argmax(np.where((np.arange(last) < face["on"]) | (np.arange(last) >= face["off"]), grade, 0.0)))
    road.helios = (float(laps.max()), lap_at, float(hs.max()), off, half, float(grade.max()), steep, crest, dip)
    road.face = face
    joins.extend([(len(roads), 0, parent), (len(roads), 1, parent)])
    scenic_roads.append((len(roads), dict(name="SHelios", sea=0)))   # (no plan, heights or land spec: all made here)
    roads.append(road)


def helios_land(road):
    """SHelios' NET_SCENIC rows: a bench cut into the mountain. Every HELIOS_LAND[0] samples while the
    road is on it (and one row either side of that stretch), each side's land reaches the mountain's own
    height at the far end of its run."""
    every, above, run = HELIOS_LAND
    on = [i for i in range(0, road.N, every) if helios_z(*road.p[i]) > above]
    assert on == list(range(on[0], on[-1] + every, every)), "SHelios leaves the mountain and comes back"
    assert on[0] >= every and on[-1] + every <= road.N - 1

    def sides(i):
        x, y = road.p[i]
        nx, ny = -road.t[i, 1], road.t[i, 0]   # its left
        out = road.width / 2 + run
        return (round(max(-4.0, helios_z(x + nx * out, y + ny * out)), 2), round(max(-4.0, helios_z(x - nx * out, y - ny * out)), 2))
    # On the Face the land beside the road climbs kilometres between two rows, and the views blend a side's
    # height from row to row (a smoothstep of the samples between: view/network_scenic.gd setup) to ask
    # whether it lies under the road (that edge is open). More rows there, until that blend is within
    # HELIOS_LAND_FIT of the side's real height at every sample: metres, or that part of its drop from the road.
    near, part = HELIOS_LAND_FIT

    def between(a, b):
        sa, sb = sides(a), sides(b)
        for i in range(a + 1, b):
            u = (i - a) / (b - a)
            u = u * u * (3 - 2 * u)
            h = road.h(i)
            if any(abs(p + (q - p) * u - s) > max(near, part * abs(s - h)) for p, q, s in zip(sa, sb, sides(i))):
                m = (a + b) // 2
                return between(a, m) + [m] + between(m, b)
        return []
    at = [on[0] - every] + on + [on[-1] + every]
    rows = []
    for a, b in zip(at, at[1:] + [None]):
        more = between(a, b) if b is not None and b > road.face["on"] and a < road.face["off"] else []
        for i in [a] + more:
            rows.append([i, sides(i)[0], run, sides(i)[1], run, 1])
    return rows


def add_hyperion(roads, joins):
    """SHyperion: off E2's north shoulder, one left turn, and a straight line over Mount Hyperion to a right
    turn onto E3's south shoulder. The mountain is laid where the road puts it (hyperion_at)."""
    S = hyperion_shape()
    tm, td = math.degrees(S["tm"]), math.degrees(S["td"])
    wide, w_from, w_over = HYPERION_W
    p0 = next(i for i, R in enumerate(roads) if R.name == HYPERION_MOUTHS[0])
    p1 = next(i for i, R in enumerate(roads) if R.name == HYPERION_MOUTHS[2])
    assert roads[p0].hdeg == 0.0 and roads[p1].hdeg == 0.0
    start = backroad_mouth(roads[p0], HYPERION_MOUTHS[1], 1, 1)

    def plan(far):
        return [("L", HYPERION_TURN, HYPERION_HEADING, "sp"), ("S", HYPERION_APPROACH * STEP, 0, "sp"),
                ("V", S["R1"], 0.0, "sp", tm), ("W", S["Lw"], tm, "sp"), ("V", S["Rc"], tm, "sp", 0.0),
                ("S", S["top"], 0, "sp"),
                ("V", S["Rl"], 0.0, "sp", -td), ("W", S["Ld"], -td, "sp"), ("V", S["R2"], -td, "sp", 0.0),
                ("S", far, 0, "sp"), ("R", HYPERION_TURN, HYPERION_HEADING, "sp")]
    # the far straight is whatever lands the road on E3's shoulder: the walk's end moves a metre north for
    # every 1 / sin(heading) of it
    goal = roads[p1].y0 - OFF
    far = 100 * KM
    for _ in range(3):
        _, end = walk(plan(far), start[0], start[1], math.radians(start[2]))
        far += (goal - end[1]) / math.sin(math.radians(HYPERION_HEADING))
    assert far > 20 * KM
    road = Road("SHyperion", "scenic", *start, SC_W, plan(far))
    assert abs(road.end[1] - goal) < 1e-3 and abs(math.sin(road.end[2])) < 1e-9, f"SHyperion misses {HYPERION_MOUTHS[2]} by {road.end[1] - goal:.4f} m"
    road.deck = True
    seg0 = [0]
    for q in road.segs:
        seg0.append(seg0[-1] + seg_samples(q))
    assert seg0[-1] == road.N - 1
    names = ["turn", "approach", "ramp", "wall", "crest", "summit", "lip", "drop", "runout", "far", "turn2"]
    at = {name: seg0[k] for k, name in enumerate(names)}
    at["end"] = at["far"]           # the run-out's end is the far straight's start
    at["centre"] = (at["summit"] + at["lip"]) // 2
    at["stop"] = at["centre"]
    # the mountain, where the road puts it: the summit's middle sample, and the road's way over it
    c = at["centre"]
    assert (at["lip"] - at["summit"]) % 2 == 0
    hyperion_at.update(cx=float(road.p[c, 0]), cy=float(road.p[c, 1]), ux=float(road.t[c, 0]), uy=float(road.t[c, 1]))
    # its width: SC_W at each mouth and round each turn, HYPERION_W between
    a, b = at["approach"] + w_from, at["turn2"] - w_from - w_over
    assert a + w_over < at["ramp"] and b > at["far"]
    road.wkeys = [[0, SC_W], [a, SC_W], [a + w_over, wide], [b, wide], [b + w_over, SC_W], [road.N - 1, SC_W]]
    road.wid = np.interp(np.arange(road.N), [k[0] for k in road.wkeys], [k[1] for k in road.wkeys])
    # Heights: along the deck, part by part. z and the deck's pitch at every sample of the mountain, exactly:
    # a "V" turns the pitch evenly with the deck's length, a "W" holds it.
    z = np.zeros(road.N)
    pitch = np.zeros(road.N)
    zi, k = 0.0, at["ramp"]
    for q in road.segs[2:9]:
        n = seg_samples(q)
        if q[0] == "V":
            a0, a1 = math.radians(q[2]), math.radians(q[4])
            kap = (a1 - a0) / (q[1] * abs(a1 - a0))                 # the pitch gained per metre of deck
            ds = q[1] * abs(a1 - a0) / n
            for j in range(n):
                pitch[k + j] = a0 + kap * ds * j
                z[k + j] = zi + (math.cos(a0) - math.cos(a0 + kap * ds * j)) / kap
            zi += (math.cos(a0) - math.cos(a1)) / kap
        elif q[0] == "W":
            a0 = math.radians(q[2])
            for j in range(n):
                pitch[k + j] = a0
                z[k + j] = zi + q[1] / n * j * math.sin(a0)
            zi += q[1] * math.sin(a0)
        else:
            assert abs(zi - S["H"]) < 1e-6, f"SHyperion's summit comes out at {zi:.4f} m"
            zi = S["H"]
            z[k:k + n] = zi
        k += n
    assert k == at["end"] and abs(zi) < 1e-6, f"SHyperion's run-out ends {zi:.6f} m up"
    z[at["summit"]:at["lip"] + 1] = S["H"]
    # every sample from the foot to the run-out's end is STEP of deck from the next (what the sims' deck rule rests on)
    deck = np.hypot(road.len[at["ramp"]:at["end"]], np.diff(z[at["ramp"]:at["end"] + 1]))
    assert abs(deck - STEP).max() < 0.25, f"SHyperion's deck samples are {deck.min():.2f}-{deck.max():.2f} m"

    def key(i):
        return [i, float(z[i]), float(math.sin(pitch[i]))]      # (the sims' Hermite counts every sample as STEP long: here STEP of deck)
    every_big, every_crest, every_lip = HYPERION_KEY
    must = {0, at["ramp"], at["end"], road.N - 1}
    for name, nxt, every in [("ramp", "wall", every_big), ("wall", "crest", 10 ** 9), ("crest", "summit", every_crest), ("summit", "lip", 10 ** 9),
                             ("lip", "drop", every_lip), ("drop", "runout", 10 ** 9), ("runout", "end", every_big)]:
        must |= set(range(at[name], at[nxt], every)) | {at[nxt]}
    road.keys = [key(i) for i in sorted(must)]
    hs = hermite_all(road.keys, road.N)
    off = float(np.abs(hs - z).max())
    # ... and against the mountain itself, which is the same profile found another way (hyperion_z): at every
    # sample, and under the middle of every chord (the deck is a chord between samples: on the lip's 297 m
    # radius that stands a quarter of a metre inside the circle)
    surf = max(abs(hyperion_z(*road.p[i]) - z[i]) for i in range(at["ramp"] - 40, at["end"] + 41))
    half = max(abs(road.h(i + 0.5) - hyperion_z(*((road.p[i] + road.p[i + 1]) / 2))) * math.cos((pitch[i] + pitch[i + 1]) / 2) for i in range(at["ramp"], at["end"]))
    assert off < 1e-3 and surf < 1e-3 and half < 0.3, f"SHyperion: {off:.6f} m off its own heights, {surf:.6f} m off the mountain at a sample, {half:.3f} m between"
    assert abs(hs.max() - S["H"]) < 1e-6 and hs.min() > -1e-6
    # the ramp's pitch grows at every sample from the foot to the wall, and falls at every one over the crest; the
    # lip's falls and the run-out's rises; the summit is level
    assert np.all(np.diff(pitch[at["ramp"]:at["wall"] + 1]) > 0) and np.all(np.diff(pitch[at["crest"]:at["summit"] + 1]) < 0)
    assert np.all(np.diff(pitch[at["lip"]:at["drop"] + 1]) < 0) and np.all(np.diff(pitch[at["runout"]:at["end"] + 1]) > 0)
    road.hyperion = dict(S=S, at=at, off=off, surf=surf, half=half, far=far, z=z, pitch=pitch,
                         plan=float(road.len[at["ramp"]:at["end"]].sum()), deck=float(deck.sum()))
    joins.extend([(len(roads), 0, p0), (len(roads), 1, p1)])
    scenic_roads.append((len(roads), dict(name="SHyperion", sea=0)))
    roads.append(road)


def hyperion_land(road):
    """SHyperion's NET_SCENIC rows. Its land is the mountain's own surface (the views ask view/hyperion.gd), level
    with the deck either side across the face: a row every HYPERION_LAND[0] samples while it is on the mountain
    (and one either side), each side's height the deck's own."""
    every, run = HYPERION_LAND
    at = road.hyperion["at"]
    rows = []
    for i in list(range(at["ramp"] - every, at["end"] + every, every)) + [at["end"] + every]:
        h = round(max(-4.0, road.h(i)), 2) if at["ramp"] < i < at["end"] else -4.0
        rows.append([i, h, run, h, run, 1])
    return rows


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
    jumps = []
    for crossing, (ci, cj) in enumerate(JUMP_AT):
        for way, (axis, direction) in enumerate(JUMP_WAYS):
            add_jump(roads, joins, jumps, ew, ns, ci, cj, axis, direction, JUMP_SPEEDS[crossing][way])

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
    # Append new roads after the backroads so prior routes, jump IDs and saved positions stay valid.
    add_jump(roads, joins, jumps, ew, ns, 2, 0, "N", 1, 3250.0)  # J20, Mesa northbound
    for name, parent_name, station, side, radius, angle, middle, height_keys in STUNT_ROADS:
        parent = by_name[parent_name]
        start = backroad_mouth(roads[parent], station, side, 1)
        outward, inward = ("L", "R") if side > 0 else ("R", "L")
        a, b = (outward, radius * KM, angle, "sp"), (inward, radius * KM, angle, "sp")
        road = Road(name, "stunt", *start, W_RAMP, [a, b, ("S", middle * KM, 0, "sp"), b, a])
        tier = EXPRESS_H if parent_name.startswith("N") else 0.0
        road.keys = [[round(f * (road.N - 1)), tier + dz, 0.0] for f, dz in height_keys]
        joins.extend([(len(roads), 0, parent), (len(roads), 1, parent)])
        roads.append(road)
    # The long straight is the sealed section. The sweeping open feeders reach
    # highway exits while the pressure galleries occupy opposite map corners.
    southwest = (28 * KM, 28 * KM, 45.0)
    northeast = (572 * KM, 572 * KM, 45.0)
    parent, receiver = by_name["E1"], by_name["E3"]
    entry = backroad_mouth(roads[parent], 43, -1, -1)
    exit_pose = backroad_mouth(roads[receiver], 557, 1, -1)
    inlet = dubins(entry, southwest, 8 * KM)
    outlet = dubins(northeast, exit_pose, 8 * KM)
    diagonal = math.dist(southwest[:2], northeast[:2])
    tube = Road("SAurora", "tube", *entry, W_RAMP,
                inlet + [("S", diagonal, 0, "sp")] + outlet)
    first = len(walk(inlet, *entry[:2], math.radians(entry[2]))[0]) - 1
    last = first + math.ceil(diagonal / STEP)
    # Align both airlocks with the streamed pavement chunks (40 samples).
    tube.tube_span = (math.ceil(first / 40) * 40, last // 40 * 40)
    end = tube.N - 1
    tube.keys = [[i, h, 0.0] for i, h in [(0, 0), (150, 0),
                 (first, 2400), (last, 2400), (end - 150, 0), (end, 0)]]
    joins.extend([(len(roads), 0, parent), (len(roads), 1, receiver)])
    roads.append(tube)
    # Helios last of all: every road and junction before it keeps its index.
    add_helios(roads, joins)
    # ... and Hyperion after it, for the same reason.
    add_hyperion(roads, joins)
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
        if "land" not in spec:
            continue   # (SHelios: its rows are the mountain's own, last below)
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
    # Helios is a bench cut into its mountain from foot to foot.
    r = next(i for i, road in enumerate(roads) if road.name == "SHelios")
    out.append([r, 0, helios_land(roads[r])])
    # Hyperion's road is on its mountain from the ramp's foot to the run-out's end.
    r = next(i for i, road in enumerate(roads) if road.name == "SHyperion")
    out.append([r, 0, hyperion_land(roads[r])])
    return out


def width_table(roads):
    """[[road, [[sample, width m], ...]], ...]: the roads whose width changes along them (level between keys'
    ends, a straight line from key to key)."""
    return [[r, [[int(k[0]), float(k[1])] for k in R.wkeys]] for r, R in enumerate(roads) if R.wid is not None]


def deck_table(roads):
    """The roads sampled along their deck, which the sims fly at the speed along it."""
    return [r for r, R in enumerate(roads) if R.deck]


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
        if "heights" not in spec:
            continue   # (SHelios: its keys are the mountain's surface, set as it's built)
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
    out = [[jumps[k][1], round(6000.0 / STEP), round(17000.0 / STEP), 1 if n % 2 == 0 else -1]
            for n, k in enumerate(TWIST_JUMPS)]
    r = next(i for i, road in enumerate(roads) if road.name == "SNeedle")
    # Keep the entire inverted stretch on the level central straight, with upright runouts.
    out.append([r, round(.32 * (roads[r].N - 1)), round(.68 * (roads[r].N - 1)), 1])
    return out


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
                d = math.hypot(A.p[i, 0] - B.p[j, 0], A.p[i, 1] - B.p[j, 1]) - (A.w(i) + B.w(j)) / 2
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
        if R.kind in ("highway", "turn") or R.deck:
            continue   # (a shaft's plan is a paperclip by design: its legs share a wall; Hyperion's road is one straight line, a wall's samples a metre apart in plan)
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
        tight = min(q[1] for q in R.segs if q[0] in ("L", "R"))
        stretch = f"its stretch {R.segs[spec['stretch']][1] / KM:.1f} km, " if "stretch" in spec else ""
        print(f"  scenic {R.name}: {R.len[:-1].sum() / KM:.0f} km, x {R.p[:, 0].min() / KM:.1f}-{R.p[:, 0].max() / KM:.1f} km, "
              f"y {R.p[:, 1].min() / KM:.1f}-{R.p[:, 1].max() / KM:.1f} km, {hs.min():.0f}-{hs.max():.0f} m up, steepest {abs(grade).max() * 100:.1f}%, "
              f"tightest crest or dip {1 / abs(bend).max() / KM:.1f} km, tightest bend {tight / KM:.0f} km, "
              f"{stretch}ends at x {R.end[0] / KM:.1f} km")
        if hasattr(R, "helios"):
            steep, at, top, off, half, wall, wall_at, crest, dip = R.helios
            F = R.face
            print(f"    {R.N} samples, {len(R.keys)} height keys within {off * 1000:.1f} mm of the mountain at every sample ({half * 1000:.1f} mm between), "
                  f"summit {top:.2f} m, its laps' steepest {steep * 100:.2f}% at sample {at}; " + ", ".join(f"{name} {i}" for name, i in R.way))
            print(f"    the Face: samples {F['on']}-{F['off']} (off the lap, and on again), straight {F['start']}-{F['end']}; shoulder {F['shoulder']}, wall {F['wall']}, rim {F['rim']}, "
                  f"centre {F['centre']}, rim {F['rim2']}, wall {F['wall2']}, shoulder {F['shoulder2']}; steepest {wall * 100:.1f}% ({math.degrees(math.atan(wall)):.2f} deg) "
                  f"at sample {wall_at}; {(F['rim2'] - F['rim']) * STEP / KM:.1f} km level; tightest crest {crest:.0f} m (at the rim), tightest dip {dip:.0f} m (at the shoulder)")
            grade = np.concatenate([grade[:F["on"]], grade[F["off"]:]])   # (the Face's own limit is the wall's pitch: add_helios holds it)
        if hasattr(R, "hyperion"):
            Y = R.hyperion
            S, at = Y["S"], Y["at"]
            print(f"    {R.N} samples, {len(R.keys)} height keys within {Y['off'] * 1000:.3f} mm of its heights and {Y['surf'] * 1000:.3f} mm of the mountain at every sample ({Y['half'] * 1000:.0f} mm between: the chords); "
                  f"summit {hs.max():.2f} m at {hyperion_at['cx'] / KM:.3f},{hyperion_at['cy'] / KM:.3f} km; its deck {Y['deck'] / KM:.2f} km over {Y['plan'] / KM:.2f} km of plan, a sample every {STEP:.0f} m of deck")
            print(f"    up: ramp {at['ramp']}-{at['wall']} (radius {S['R1']:.1f} m, to {math.degrees(S['tm']):.3f} deg, top {S['zw']:.1f} m), wall to {at['crest']} ({S['Lw']:.0f} m), crest to {at['summit']} (radius {S['Rc']:.1f} m); "
                  f"summit {at['summit']}-{at['lip']} ({S['top']:.0f} m, centre {at['centre']}); down: lip to {at['drop']} (radius {S['Rl']:.1f} m, to {math.degrees(S['td']):.3f} deg), wall to {at['runout']} ({S['Ld']:.0f} m), "
                  f"run-out to {at['end']} (radius {S['R2']:.1f} m); far straight {Y['far'] / KM:.2f} km; the mountain's foot {S['front'] / KM:.2f} km before the plateau, {S['back'] / KM:.2f} km behind, {(S['front'] + HYPERION_SKIRT[0]) / KM:.2f} km to each side; "
                  f"width {[(int(k[0]), int(k[1])) for k in R.wkeys]}")
            grade = np.concatenate([grade[:at["ramp"]], grade[at["end"]:]])   # (the mountain's own pitch is its design: add_hyperion holds it)
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
    # Budget the new diagonal separately to preserve the existing roads' limit
    # (raised from 9,100 km and 380,000 samples for SHelios: about 370 km, 15,400 samples).
    tube_km = kinds["tube"][1]
    tube_samples = sum(r.N for r in roads if r.kind == "tube")
    # (... and from 9,600 km and 400,000 samples for SHyperion: 242 km of plan, 12,900 samples)
    if km - tube_km > 9900 or N - tube_samples > 420000 or tube_km > 980 or tube_samples > 41000:
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
    col = {"highway": "#2a6fdb", "ramp": "#6a8", "city": "#d33", "turn": "#999", "jump": "#f80", "on": "#a0a", "side": "#0a7", "scenic": "#c0f", "backroad": "#a65b28", "stunt": "#d04470"}
    col["tube"] = "#23b7bd"
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
