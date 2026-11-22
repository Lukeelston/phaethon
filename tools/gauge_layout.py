"""The analogue gauge cluster's layout, shared by the tools that build it.

    tools/art_gauges_hd.py     the binnacle: cowl, fascia, tubes, trim rings (Blender)
    tools/art_gauge_faces.py   the dial faces, and godot/vr/gauge_layout.gd for the game

Everything is in the instrument panel's flat layout (vr/dashboard.gd): x metres along the arc,
y up, d toward the pilot from the old panel's face. Five tubes in a row, the centre one
largest and proudest, each aimed at the arc's axis so the pilot looks straight down it.
Angles on a face are degrees anticlockwise from three o'clock, as the pilot sees them.
"""
import math

R_ARC = 1.32                       # the panel's arc radius (vr/dashboard.gd R)
HALF_W, Y_BOTTOM, D_BACK = .470, -.172, -.060
RING = .0085                       # trim ring width at each tube's mouth
SEAT = .010                        # the glass sits this far inside the mouth
DOME = .068                        # the glass's rise, as a fraction of its diameter
CHAPTER, CHAPTER_R = .0025, .80    # the raised scale ring: height, and where it starts (of the face radius)
NEEDLE_UP, CAP_UP = .0050, .0085   # needle and hub cap heights above the face

# key, x, y, outer radius, mouth depth, recess from mouth to face
GAUGES = [
    ("mach", .0000, .038, .129, .1045, .053),
    ("thrL", -.2115, .021, .100, .0740, .044),
    ("thrR", .2115, .021, .100, .0740, .044),
    ("engL", -.3775, .006, .080, .0490, .036),
    ("engR", .3775, .006, .080, .0490, .036),
]


def glass_radius(ro):
    return ro - RING


def face_radius(ro):
    return .84 * (ro - RING)


def funnel_radius(gauge, d):
    """The inner wall's radius at depth d: a cone from the glass seat down to the face."""
    _, _, _, ro, mouth, recess = gauge
    top, bottom = mouth - SEAT, mouth - recess
    t = min(max((d - bottom) / (top - bottom), 0.0), 1.0)
    return face_radius(ro) + (glass_radius(ro) - face_radius(ro)) * t


def check():
    """A tube may overlap its bigger neighbour's wall, never its dial or the inside of its tube."""
    for big, small in ((0, 1), (0, 2), (1, 3), (2, 4)):
        a, b = GAUGES[big], GAUGES[small]
        apart = math.hypot(a[1] - b[1], a[2] - b[2])
        assert apart - face_radius(b[3]) >= a[3] - .0005, (b[0], "dial under", a[0])
        assert apart - b[3] >= funnel_radius(a, b[4]) + .0004, (b[0], "pokes into", a[0], apart - b[3], funnel_radius(a, b[4]))


def to_panel(x, y, d):
    """Flat layout -> the panel's own frame (Godot axes: x right, y up, z toward the pilot)."""
    phi = x / R_ARC
    return (R_ARC - d) * math.sin(phi), y, R_ARC - (R_ARC - d) * math.cos(phi)


def frame(x, y):
    """A flat fitting's origin and axes (right, up, toward the pilot) where it meets the arc."""
    phi = x / R_ARC
    return ((R_ARC * math.sin(phi), y, R_ARC - R_ARC * math.cos(phi)),
            (math.cos(phi), 0.0, math.sin(phi)), (0.0, 1.0, 0.0), (-math.sin(phi), 0.0, math.cos(phi)))


# The two flat LCD strips under the outer tubes: centre x, centre y, half width, half height,
# and how far the flat module's face stands off the curved fascia at its middle.
WINDOWS = [("status", -.250, -.128, .190, .032, .016), ("systems", .250, -.128, .190, .032, .016)]

# The points counter (Luke: "points on an odometer roller, with a digital readout next to it of the
# feat"): a small drum counter in the fascia between the two strips, under the centre dial. Its
# window's centre x and y, half width and half height, how far its face stands off the fascia, and
# how many drums. The feat is read on the strip beside it (the systems strip's lower line).
ODOMETER = (.0, -.1275, .0375, .0120, .0050, 6)

# ---- what each face shows (radii as fractions of the face radius) ----
# needle: key, gauge, a0 (value 0), a1 (value 1), length, shown full scale
NEEDLES = [
    ("mach", 0, 200, -20, .88, 16.0),
    ("thrL", 1, 225, -45, .88, 1.0), ("thrR", 2, 225, -45, .88, 1.0),
    ("heatL", 3, 150, 30, .80, 1.0), ("heatR", 4, 150, 30, .80, 1.0),
    ("brkL", 3, 210, 330, .80, 1.0), ("brkR", 4, 210, 330, .80, 1.0),
]
GATE = .88                         # the burner gate on the thrust scale (vr/dashboard.gd GATE)
HEAT_AMBER, HEAT_RED = .60, .85

# lit legends: lamp, gauge, centre x, centre y, width, height, the words
TELLTALES = [
    ("armed", 0, -.445, -.070, .40, .115, "ARMED"), ("ramjet", 0, .445, -.070, .40, .115, "RAMJET"),
    ("burner", 1, 0, -.435, .62, .135, "BURNER"), ("burner", 2, 0, -.435, .62, .135, "BURNER"),
    ("flameoutL", 1, 0, -.615, .78, .125, "FLAMEOUT"), ("flameoutR", 2, 0, -.615, .78, .125, "FLAMEOUT"),
    ("hotL", 3, .49, 0, .44, .19, "HOT"), ("hotR", 4, -.49, 0, .44, .19, "HOT"),
    # left of the hub, over ARMED: the needle is past it (Mach 2.4) long before the turbines light
    ("turbines", 0, -.385, .085, .40, .10, "TURBINES"),
]
# lit arcs: key, gauge, inner r, outer r, a0, a1, segments
ARCS = [("bat", 0, .855, .955, 236, 304, 12), ("hpL", 1, .855, .955, 240, 300, 8), ("hpR", 2, .855, .955, 240, 300, 8)]
# digital windows on the centre face: left, bottom, right, top
SPEED_WINDOW = (-.50, -.62, .50, -.22)
GEAR_WINDOW = (-.115, .215, .115, .435)

# The g-meter (Luke: "a g-force meter ... a real instrument, not just a number"): a sub-dial on the
# centre face, right of the hub and over RAMJET (the mirror of TURBINES), with a needle of its own
# and a tell-tale left at the highest load of the last few seconds. The craft pulls 35 g off the
# line, 20 to 35 in the turns it is flown through and over 100 on full air brakes at Mach 7
# (tests/probe_g.gd, tests/probe_slide.gd --small), and stands at 1 g at rest, so the scale is drawn
# in decades: g_scale() is how far up it a load reads, 0..1.
G_FULL = 100.0                     # the top of the scale, g
G_HARD, G_LIMIT = 20.0, 50.0       # the amber band (a hard turn: the upper third) and the red one
G_MARKS = (0, 1, 2, 5, 10, 20, 50, 100)   # its ticks; the decades carry figures
# centre x, centre y, radius (of the face radius); the angle at zero and at full scale; the needle's
# length (of the face radius); its height over the face and its hub's (m): under the Mach needle
G_DIAL = (.354, .180, .190, 225, -45, .158, .0018, .0036)


def g_scale(g):
    return math.log1p(max(g, 0.0)) / math.log1p(G_FULL)


LAMPS = ["backlight", "armed", "ramjet", "burner", "flameoutL", "flameoutR", "hotL", "hotR", "turbines"]
for _key, _g, _r0, _r1, _a0, _a1, _n in ARCS:
    LAMPS += ["%s%d" % (_key, i) for i in range(_n)]
LAMPS.append("lcd")

check()
