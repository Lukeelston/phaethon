## The analogue gauge cluster's layout. Written by tools/art_gauge_faces.py from
## tools/gauge_layout.py: change it there and run the tool again, not here.
## Flat layout: x metres along the panel's arc, y up, depths toward the pilot. On a face,
## radii are fractions of the face's radius and angles are degrees anticlockwise from three
## o'clock. uv is [centre u, centre v, radius] for a dial and [u0, v0, u1, v1] for a tile.
extends RefCounted

const R := 1.32
const HALF_W := 0.47
const Y_BOTTOM := -0.172
const SEAT := 0.01
const DOME := 0.068
const CHAPTER := 0.0025
const CHAPTER_R := 0.8
const NEEDLE_UP := 0.005
const CAP_UP := 0.0085
const GATE := 0.88
const HEAT_AMBER := 0.6
const HEAT_RED := 0.85
const G_FULL := 100.0
const G_HARD := 20.0
const GAUGES := [
	{"key": "mach", "x": 0.0, "y": 0.038, "ro": 0.129, "rg": 0.1205, "rf": 0.10122, "mouth": 0.1045, "face": 0.0515, "uv": [0.25, 0.25, 0.2425]},
	{"key": "thrL", "x": -0.2115, "y": 0.021, "ro": 0.1, "rg": 0.0915, "rf": 0.07686, "mouth": 0.074, "face": 0.03, "uv": [0.695312, 0.195312, 0.189453]},
	{"key": "thrR", "x": 0.2115, "y": 0.021, "ro": 0.1, "rg": 0.0915, "rf": 0.07686, "mouth": 0.074, "face": 0.03, "uv": [0.195312, 0.695312, 0.189453]},
	{"key": "engL", "x": -0.3775, "y": 0.006, "ro": 0.08, "rg": 0.0715, "rf": 0.06006, "mouth": 0.049, "face": 0.013, "uv": [0.648438, 0.539062, 0.143984]},
	{"key": "engR", "x": 0.3775, "y": 0.006, "ro": 0.08, "rg": 0.0715, "rf": 0.06006, "mouth": 0.049, "face": 0.013, "uv": [0.648438, 0.835938, 0.143984]},
]
# key, gauge, angle at zero, angle at full scale, length, full scale
const NEEDLES := [
	["mach", 0, 200, -20, 0.88, 16.0],
	["thrL", 1, 225, -45, 0.88, 1.0],
	["thrR", 2, 225, -45, 0.88, 1.0],
	["heatL", 3, 150, 30, 0.8, 1.0],
	["heatR", 4, 150, 30, 0.8, 1.0],
	["brkL", 3, 210, 330, 0.8, 1.0],
	["brkR", 4, 210, 330, 0.8, 1.0],
]
# lamp, gauge, centre x, centre y, width, height, tile
const TELLTALES := [
	["armed", 0, -0.445, -0.07, 0.4, 0.115, [0.003906, 0.898438, 0.101074, 0.92627]],
	["ramjet", 0, 0.445, -0.07, 0.4, 0.115, [0.10498, 0.898438, 0.202148, 0.92627]],
	["burner", 1, 0, -0.435, 0.62, 0.135, [0.206055, 0.898438, 0.32373, 0.923828]],
	["burner", 2, 0, -0.435, 0.62, 0.135, [0.206055, 0.898438, 0.32373, 0.923828]],
	["flameoutL", 1, 0, -0.615, 0.78, 0.125, [0.327637, 0.898438, 0.475586, 0.921875]],
	["flameoutR", 2, 0, -0.615, 0.78, 0.125, [0.327637, 0.898438, 0.475586, 0.921875]],
	["hotL", 3, 0.49, 0, 0.44, 0.19, [0.003906, 0.933594, 0.067383, 0.960938]],
	["hotR", 4, -0.49, 0, 0.44, 0.19, [0.003906, 0.933594, 0.067383, 0.960938]],
	["turbines", 0, -0.385, 0.085, 0.4, 0.1, [0.071289, 0.933594, 0.168457, 0.958008]],
]
# lamps key0.., gauge, inner radius, outer radius, first angle, last angle, segments
const ARCS := [
	["bat", 0, 0.855, 0.955, 236, 304, 12],
	["hpL", 1, 0.855, 0.955, 240, 300, 8],
	["hpR", 2, 0.855, 0.955, 240, 300, 8],
]
# key, centre x, centre y, half width, half height, stand-off
const WINDOWS := [
	["status", -0.25, -0.128, 0.19, 0.032, 0.016],
	["systems", 0.25, -0.128, 0.19, 0.032, 0.016],
]
const ODOMETER := [0.0, -0.1275, 0.0375, 0.012, 0.005, 6]   # the points counter: centre x, centre y, half width, half height, stand-off, drums
const SPEED_WINDOW := [-0.5, -0.62, 0.5, -0.22]   # on the centre face: left, bottom, right, top
const GEAR_WINDOW := [-0.115, 0.215, 0.115, 0.435]
# the g-meter's sub-dial on the centre face: centre x, centre y, radius, angle at zero, angle at full scale,
# needle length, the needle's height over the face and its hub's (m). A load of g reads
# log(1 + g) / log(1 + G_FULL) of the way up its scale.
const G_DIAL := [0.354, 0.18, 0.19, 225, -45, 0.158, 0.0018, 0.0036]
const LAMPS := ["backlight", "armed", "ramjet", "burner", "flameoutL", "flameoutR", "hotL", "hotR", "turbines", "bat0", "bat1", "bat2", "bat3", "bat4", "bat5", "bat6", "bat7", "bat8", "bat9", "bat10", "bat11", "hpL0", "hpL1", "hpL2", "hpL3", "hpL4", "hpL5", "hpL6", "hpL7", "hpR0", "hpR1", "hpR2", "hpR3", "hpR4", "hpR5", "hpR6", "hpR7", "lcd"]
const BLOCK_UV := [0.174316, 0.935059, 0.186035, 0.947754]
const LCD_UV := [0.193848, 0.935547, 0.197754, 0.939453]
