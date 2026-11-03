## Phaethon flight model: twin-engine tethered podracer, top-down slice.
## Line-for-line port of web/sim-core.js; tuning keys are identical so the lab's
## "Copy tuning JSON" pastes straight into CraftSim.new(overrides).
## Scalar floats only: GDScript float is 64-bit, Vector2 is 32-bit and would
## break parity with the JS reference. Units: m, s, N. x right, y up.
class_name CraftSim
extends RefCounted

const G := 9.81
const DEFAULTS := {
	"engineMass": 1200.0, "engineLen": 8.0, "engineGap": 6.0,
	"podMass": 500.0, "podLen": 4.0, "podWidth": 2.4,
	# forceScale: thrust, drag and the brakes times this (a heavier pod comes with the total mass over
	# the standard's, so it only changes the turning; mirrors sim-core.js)
	"forceScale": 1.0,
	# v3 (2026-10-17), mirrors sim-core.js: ~4,450 mph full lever, ~5,400 mph afterburner,
	# ~15 g grip cap, speed^2 fins, tow-bar pod. tools/handling_test.js measures it.
	"thrustMax": 350000.0, "burnerMult": 1.45, "ramjetMult": 1.9, "gate": 0.88,
	"engineCd": 0.07, "podCd": 0.035, "brakeCd": 0.04, "brakeLin": 0.0, "brakeConst": 60000.0,
	# front speed brakes (Luke: "front speed brake flaps for braking done at high speed"): flaps ahead
	# of the intakes open with the air brakes from 1,500 to 2,500 mph, adding 0.05 to the drag coefficient
	"frontBrakeCd": 0.05, "frontBrakeV0": 670.6, "frontBrakeV1": 1117.6,
	"engineGrip": 30.0, "podGrip": 10.0, "gripCapG": 15.0, "podCapG": 8.0, "finOffset": 0.2, "finK": 8.0,
	"yawDamp": 150000.0, "podYawDamp": 50000.0, "podAlignK": 1.0e6, "towK": 1.0e6, "towC": 40000.0,
	"cableLen": 16.0, "cableK": 600000.0, "cableC": 30000.0, "cableCouple": 0.2, "podAnchorW": 0.15,
	"binderK": 3.0e6, "binderC": 70000.0, "alignK": 2.0e7, "alignC": 6.0e5, "binderBreak": 3.0,
	"wallK": 6.0e6, "wallC": 1.5e5, "wallMu": 0.35, "wallDmgMin": 6.0,
	# traffic's forcefields (the Network): a softer push than a wall's, no friction, no damage; a
	# closing speed over smashV (m/s, ~1,500 mph) is the catastrophic hit
	"fieldK": 2.0e6, "fieldC": 8.0e4, "smashV": 670.0,
	"damage": false,   # wall hits cost health (and can wreck you) only when this is on
	"towLongK": 2.0e6, "towLongC": 8.0e4, "towLongSlack": 0.3,   # pod stand-off: never closer to the engines than its taut-cable spot
	"bank": 1.0, "bankDown": 3.9e-4,   # banked corners: downforce per (m/s)^2, as g, presses you into the bank (~8 g at 1,000 mph)
	"towAudit": true, "towAuditG": 3.0,   # tow-bar energy audit: drag on the speed, never harder than this (g) ...
	"towIntF0": 0.05, "towIntF1": 0.3, "towIntMax": 60.0,   # ... shifting onto the swing and spin as their share of the energy grows
	"heatThrottle": 0.15, "heatBurner": 0.12, "heatRamjet": 0.35, "coolBase": 0.05, "coolSpeed": 0.10,
	"batteryDrain": 0.08, "batteryCharge": 0.05, "repairRate": 0.12, "damagePerMs": 0.012,
	"limits": false,   # battery and heat: off (Luke: "turn off battery and heat, let it be crazy"): the burner never runs dry, engines never heat up
	"rideH": 1.5, "hoverOmega": 9.0, "hoverZeta": 0.9,
	"binderKz": 3.0e6, "binderCz": 60000.0, "towKz": 2.0e5, "towCz": 16000.0,
	"track": "circuit", "startX": 0.0, "startY": 0.0, "handling": "speed",
	"job": "",   # the job being flown ("emergency": the emergency run, which opens the shade line)
	# the dawn (the job's clock): a straight front at 1,000 mph travelling dawnDir (rad), passing
	# the start line's point dawnT0 s into the job (test_job.gd)
	"dawnSpeed": 447.04, "dawnDir": 0.0, "dawnT0": 0.0,
	"sfEngageV": 558.8, "modeBlendT": 1.0,   # live switch: STARFIGHTER engages below 1,250 mph; the handling blends over 1 s
	"seed": 1337,
}
# Handling modes, mirroring sim-core.js: named overrides on top of DEFAULTS (explicit
# overrides still win). speed = the v3 sprint model; starfighter = ~990 mph lever / 1,200
# burner, 50 g grip, ~56 deg/s at 320 mph, stiff tow bar.
# Track settings, mirroring sim-core.js TRACKS: the GP's walls deflect rather than wreck (only
# impacts harder than 25 m/s into the wall do damage, a third as much; lower friction).
const TRACKS := {
	"gp": {"wallDmgMin": 25.0, "damagePerMs": 0.004, "wallMu": 0.22},
	"gp_dunes": {"wallDmgMin": 25.0, "damagePerMs": 0.004, "wallMu": 0.22},
	"gp_glacier": {"wallDmgMin": 25.0, "damagePerMs": 0.004, "wallMu": 0.22},
	"gp_basalt": {"wallDmgMin": 25.0, "damagePerMs": 0.004, "wallMu": 0.22},
	"gp_mesa": {"wallDmgMin": 25.0, "damagePerMs": 0.004, "wallMu": 0.22},

	"eridanus": {"wallDmgMin": 25.0, "damagePerMs": 0.004, "wallMu": 0.22,
		"dawnDir": 2.495821, "dawnT0": 171.7},   # the dawn: written by tools/sync_eridanus.py from tools/tune_dawn.js
	# The Network: walls are forcefields (docs/superpowers/specs/2026-10-19-network-design.md): a
	# wall shoves you off, only a catastrophic crash (the binder breaking) costs you anything
	"network": {"wallDmgMin": 1e9, "damagePerMs": 0.0, "wallMu": 0.22},
}
const HANDLING := {
	"speed": {},
	"starfighter": {
		"thrustMax": 180000.0, "engineCd": 0.725, "podCd": 0.3625,
		"gripCapG": 50.0, "engineGrip": 90.0, "podGrip": 30.0, "podCapG": 30.0, "finK": 3.0, "yawDamp": 20000.0,
		"podAlignK": 6.0e6, "podYawDamp": 250000.0, "towK": 5.0e6, "towC": 200000.0,
	},
}
# The range: 100 miles of open desert. Speed runway along y = 0, a jump lane at y = +400
# with a kicker every 1.5 km, and a twisty lane at y = -400 that only the view draws.
const RANGE_LEN := 160934.4
const JUMP_Y := 400.0
const JUMP_W := 40.0
# kickers are long and shallow, sized for 2,000-5,000 mph (launch speed = slope x speed)
const RAMP_X0 := 8000.0
const RAMP_EVERY := 4000.0
const RAMP_H := [3.0, 6.0, 10.0, 15.0]
const RAMP_SLOPE := [0.007, 0.011, 0.0157, 0.022]
# Sprint: stop dead inside a 50 m box at mile 100. Past BOX_X + OVERRUN is a DNF.
const BOX_X := RANGE_LEN
const BOX_HALF := 25.0
const OVERRUN := 15000.0
const STOPPED := 0.5
const PAD_HALF := 40.0   # the job's medical pad: a box +-40 m along and across ...
const PAD_HOLD := 1.5    # ... held this long stopped
const CTRL := [[0.0, 0.0], [900.0, -100.0], [1700.0, 150.0], [2300.0, 700.0], [2400.0, 1300.0],
	[2000.0, 1700.0], [1400.0, 1600.0], [1100.0, 1150.0], [700.0, 1300.0], [300.0, 1800.0],
	[-400.0, 1700.0], [-900.0, 1100.0], [-800.0, 400.0], [-400.0, 80.0]]


# The grand prix, mirroring sim-core.js: a 29.3 km circuit for STARFIGHTER at ~1,000 mph,
# straights and exact arcs (tools/design_gp.py closed it), sampled every ~12 m, 64 m wide.
const GP_SEGS := [["S", 2798.158], ["R", 230.0, 90.0], ["S", 450.0], ["L", 230.0, 90.0], ["S", 1500.0], ["L", 1100.0, 70.0],
	["S", 700.0], ["R", 600.0, 40.0], ["S", 900.0], ["L", 380.0, 150.0], ["S", 1100.0], ["R", 260.0, 120.0],
	["S", 700.0], ["L", 900.0, 30.0], ["S", 1278.727], ["L", 500.0, 90.0], ["S", 5200.0], ["R", 420.0, 40.0],
	["L", 420.0, 80.0], ["R", 420.0, 40.0], ["S", 1400.0], ["L", 160.0, 180.0], ["S", 500.0], ["R", 350.0, 90.0],
	["S", 3200.0], ["L", 1300.0, 90.0]]
# <gp_variants> (tools/sync_gp_variants.py: the city GPs, the grand prix four ways; don't edit by hand)
const GP_DUNES_SEGS := [["S", 2798.158], ["R", 230.0, 90.0], ["S", 450.0], ["L", 230.0, 90.0], ["S", 1500.0], ["L", 1100.0, 70.0], ["S", 700.0], ["R", 600.0, 40.0], ["S", 900.0], ["L", 380.0, 150.0], ["S", 1100.0], ["R", 260.0, 120.0], ["S", 700.0], ["L", 900.0, 30.0], ["S", 1278.727], ["L", 500.0, 90.0], ["S", 5200.0], ["R", 420.0, 40.0], ["L", 420.0, 80.0], ["R", 420.0, 40.0], ["S", 1400.0], ["L", 160.0, 180.0], ["S", 500.0], ["R", 350.0, 90.0], ["S", 3200.0], ["L", 1300.0, 90.0]]
const GP_GLACIER_SEGS := [["S", 2798.158], ["L", 230.0, 90.0], ["S", 450.0], ["R", 230.0, 90.0], ["S", 1500.0], ["R", 1100.0, 70.0], ["S", 700.0], ["L", 600.0, 40.0], ["S", 900.0], ["R", 380.0, 150.0], ["S", 1100.0], ["L", 260.0, 120.0], ["S", 700.0], ["R", 900.0, 30.0], ["S", 1278.727], ["R", 500.0, 90.0], ["S", 5200.0], ["L", 420.0, 40.0], ["R", 420.0, 80.0], ["L", 420.0, 40.0], ["S", 1400.0], ["R", 160.0, 180.0], ["S", 500.0], ["L", 350.0, 90.0], ["S", 3200.0], ["R", 1300.0, 90.0]]
const GP_BASALT_SEGS := [["S", 5200.0], ["R", 500.0, 90.0], ["S", 1278.727], ["R", 900.0, 30.0], ["S", 700.0], ["L", 260.0, 120.0], ["S", 1100.0], ["R", 380.0, 150.0], ["S", 900.0], ["L", 600.0, 40.0], ["S", 700.0], ["R", 1100.0, 70.0], ["S", 1500.0], ["R", 230.0, 90.0], ["S", 450.0], ["L", 230.0, 90.0], ["S", 2798.158], ["R", 1300.0, 90.0], ["S", 3200.0], ["L", 350.0, 90.0], ["S", 500.0], ["R", 160.0, 180.0], ["S", 1400.0], ["L", 420.0, 40.0], ["R", 420.0, 80.0], ["L", 420.0, 40.0]]
const GP_MESA_SEGS := [["S", 5200.0], ["L", 500.0, 90.0], ["S", 1278.727], ["L", 900.0, 30.0], ["S", 700.0], ["R", 260.0, 120.0], ["S", 1100.0], ["L", 380.0, 150.0], ["S", 900.0], ["R", 600.0, 40.0], ["S", 700.0], ["L", 1100.0, 70.0], ["S", 1500.0], ["L", 230.0, 90.0], ["S", 450.0], ["R", 230.0, 90.0], ["S", 2798.158], ["L", 1300.0, 90.0], ["S", 3200.0], ["R", 350.0, 90.0], ["S", 500.0], ["L", 160.0, 180.0], ["S", 1400.0], ["R", 420.0, 40.0], ["L", 420.0, 80.0], ["R", 420.0, 40.0]]
# </gp_variants>
const GP_STEP := 12.0
const GP_WIDTH := 96.0   # wider, and every corner banked GP_BANK degrees toward its inside (Luke, 2026-10-18),
const GP_BANK := 15.0    # easing in and out over ~360 m: two passes of a (2 * GP_BANK_R + 1)-sample box (was 30: "50% smaller")
const GP_BANK_R := 7
# Eridanus, mirroring sim-core.js: the dual-purpose course (tools/design_eridanus.py), 199 km. Each
# segment names its mode: "sf" (the towns, STARFIGHTER's) 140 m wide, corners banked 10 deg; "sp"
# (the speed loop, SPEEDCRAFT's) 400 m wide, sweepers banked 3 deg (Luke: "much wider", "bank the
# speedcraft corners just slightly to help with sight"); widths ease over ~1 km between, banks over
# ~1 km in the towns and ~5 km on the loop ("quick elevation changes ... too intense").
const ERI_SEGS := [["S", 3390.539, 0.0, "sf"], ["L", 450.0, 90.0, "sf"], ["S", 900.0, 0.0, "sf"], 
	["R", 300.0, 90.0, "sf"], ["S", 700.0, 0.0, "sf"], ["L", 600.0, 60.0, "sf"], ["R", 600.0, 60.0, "sf"], 
	["S", 1500.0, 0.0, "sf"], ["S", 9000.0, 0.0, "sp"], ["L", 30000.0, 8.0, "sp"], ["R", 30000.0, 8.0, "sp"], 
	["S", 8000.0, 0.0, "sp"], ["L", 22000.0, 90.0, "sp"], ["S", 11000.0, 0.0, "sp"], ["L", 500.0, 50.0, "sf"], 
	["S", 600.0, 0.0, "sf"], ["R", 320.0, 70.0, "sf"], ["S", 500.0, 0.0, "sf"], ["L", 400.0, 80.0, "sf"], 
	["S", 1500.0, 0.0, "sf"], ["S", 4000.0, 0.0, "sp"], ["R", 15000.0, 30.0, "sp"], ["S", 1000.0, 0.0, "sp"], 
	["L", 15000.0, 30.0, "sp"], ["S", 3000.0, 0.0, "sp"], ["L", 20000.0, 30.0, "sp"], ["S", 13100.0, 0.0, "sp"], 
	["L", 16000.0, 90.0, "sp"], ["S", 36152.417, 0.0, "sp"], ["L", 700.0, 60.0, "sf"], ["S", 900.0, 0.0, "sf"], 
	["R", 350.0, 80.0, "sf"], ["S", 800.0, 0.0, "sf"], ["L", 300.0, 100.0, "sf"], ["S", 1000.0, 0.0, "sf"], 
	["R", 500.0, 50.0, "sf"], ["S", 1200.0, 0.0, "sf"], ["L", 900.0, 60.0, "sf"]]
# <shade> written by tools/sync_eridanus.py: the shade line (a private covered STARFIGHTER line
# into the start town, tools/design_eridanus.py) and the lake town's medical pad
const SHADE_SEGS := [["R", 1200.0, 40.0, "sf"], ["S", 500.0, 0.0, "sf"], ["L", 1200.0, 40.0, "sf"], ["S", 1500.0, 0.0, "sf"], ["R", 600.0, 30.0, "sf"], ["S", 3569.081, 0.0, "sf"], ["L", 350.0, 70.0, "sf"], ["S", 700.0, 0.0, "sf"], ["R", 300.0, 40.0, "sf"], ["S", 600.0, 0.0, "sf"], ["L", 500.0, 30.0, "sf"], ["S", 2365.036, 0.0, "sf"], ["R", 450.0, 30.0, "sf"], ["S", 1500.0, 0.0, "sf"], ["L", 1200.0, 40.0, "sf"], ["S", 500.0, 0.0, "sf"], ["R", 1200.0, 40.0, "sf"]]
const ERI_SHADE := {"name": "shade", "segs": SHADE_SEGS, "from": 14838, "join": 16046, "width": 120.0, "jz": 120, "covered": [237, 1341], "roll": [[182, 292, 0.0, 180.0], [1050, 1160, 180.0, 0.0]], "height": 62.0}
const ERI_PAD := 6932
const ERI_RAMPS := [[747, 1283], [6124, 6660], [6995, 7532], [15509, 16045]]   # the covered ramps at each end of each town: [first, last] main samples
# </shade>
# <network> (tools/sync_network.py from tools/design_network.py: don't edit by hand)
const NET_STEP := 24.0
# [name, x, y, heading deg, width, [[kind, length or radius, deg, mode], ...]]
const NET_ROADS := [
	["E1", 25000.0, 100000.0, 0.0, 400.0, [["S", 120000.0, 0.0, "sp"], ["L", 45000.0, 16.0, "sp"], ["S", 31409.384254095403, 0.0, "sp"], ["R", 45000.0, 32.0, "sp"], ["S", 31409.384254095403, 0.0, "sp"], ["L", 45000.0, 16.0, "sp"], ["S", 90000.0, 0.0, "sp"], ["R", 45000.0, 13.0, "sp"], ["S", 35668.58872733586, 0.0, "sp"], ["L", 45000.0, 26.0, "sp"], ["S", 35668.58872733586, 0.0, "sp"], ["R", 45000.0, 13.0, "sp"], ["S", 120000.0, 0.0, "sp"]]],
	["E2", 25000.0, 300000.0, 0.0, 400.0, [["S", 120000.0, 0.0, "sp"], ["L", 45000.0, 20.0, "sp"], ["S", 25772.456402216954, 0.0, "sp"], ["R", 45000.0, 40.0, "sp"], ["S", 25772.456402216954, 0.0, "sp"], ["L", 45000.0, 20.0, "sp"], ["S", 90000.0, 0.0, "sp"], ["R", 45000.0, 15.0, "sp"], ["S", 32824.76260375352, 0.0, "sp"], ["L", 45000.0, 30.0, "sp"], ["S", 32824.76260375352, 0.0, "sp"], ["R", 45000.0, 15.0, "sp"], ["S", 120000.0, 0.0, "sp"]]],
	["E3", 25000.0, 500000.0, 0.0, 400.0, [["S", 120000.0, 0.0, "sp"], ["L", 45000.0, 14.0, "sp"], ["S", 34244.22935835813, 0.0, "sp"], ["R", 45000.0, 28.0, "sp"], ["S", 34244.22935835813, 0.0, "sp"], ["L", 45000.0, 14.0, "sp"], ["S", 90000.0, 0.0, "sp"], ["R", 45000.0, 18.0, "sp"], ["S", 28587.64967214313, 0.0, "sp"], ["L", 45000.0, 36.0, "sp"], ["S", 28587.64967214313, 0.0, "sp"], ["R", 45000.0, 18.0, "sp"], ["S", 120000.0, 0.0, "sp"]]],
	["N1", 100000.0, 25000.0, 90.0, 400.0, [["S", 120000.0, 0.0, "sp"], ["L", 45000.0, 17.0, "sp"], ["S", 29997.285275513706, 0.0, "sp"], ["R", 45000.0, 34.0, "sp"], ["S", 29997.285275513706, 0.0, "sp"], ["L", 45000.0, 17.0, "sp"], ["S", 90000.0, 0.0, "sp"], ["R", 45000.0, 19.0, "sp"], ["S", 27179.652269197013, 0.0, "sp"], ["L", 45000.0, 38.0, "sp"], ["S", 27179.652269197013, 0.0, "sp"], ["R", 45000.0, 19.0, "sp"], ["S", 120000.0, 0.0, "sp"]]],
	["N2", 300000.0, 25000.0, 90.0, 400.0, [["S", 120000.0, 0.0, "sp"], ["L", 45000.0, 21.0, "sp"], ["S", 24365.211496849173, 0.0, "sp"], ["R", 45000.0, 42.0, "sp"], ["S", 24365.211496849173, 0.0, "sp"], ["L", 45000.0, 21.0, "sp"], ["S", 90000.0, 0.0, "sp"], ["R", 45000.0, 14.0, "sp"], ["S", 34244.22935835813, 0.0, "sp"], ["L", 45000.0, 28.0, "sp"], ["S", 34244.22935835813, 0.0, "sp"], ["R", 45000.0, 14.0, "sp"], ["S", 120000.0, 0.0, "sp"]]],
	["N3", 500000.0, 25000.0, 90.0, 400.0, [["S", 120000.0, 0.0, "sp"], ["L", 45000.0, 13.0, "sp"], ["S", 35668.58872733586, 0.0, "sp"], ["R", 45000.0, 26.0, "sp"], ["S", 35668.58872733586, 0.0, "sp"], ["L", 45000.0, 13.0, "sp"], ["S", 90000.0, 0.0, "sp"], ["R", 45000.0, 20.0, "sp"], ["S", 25772.456402216954, 0.0, "sp"], ["L", 45000.0, 40.0, "sp"], ["S", 25772.456402216954, 0.0, "sp"], ["R", 45000.0, 20.0, "sp"], ["S", 120000.0, 0.0, "sp"]]],
	["R00WS", 87900.0, 99900.0, 0.0, 200.0, [["R", 12000.0, 90.0, "sp"]]],
	["R00WN", 87900.0, 100100.0, 0.0, 200.0, [["L", 12000.0, 90.0, "sp"]]],
	["R00ES", 112100.0, 99900.0, 180.0, 200.0, [["L", 12000.0, 90.0, "sp"]]],
	["R00EN", 112100.0, 100100.0, 180.0, 200.0, [["R", 12000.0, 90.0, "sp"]]],
	["R01WS", 87900.0, 299900.0, 0.0, 200.0, [["R", 12000.0, 90.0, "sp"]]],
	["R01WN", 87900.0, 300100.0, 0.0, 200.0, [["L", 12000.0, 90.0, "sp"]]],
	["R01ES", 112100.0, 299900.0, 180.0, 200.0, [["L", 12000.0, 90.0, "sp"]]],
	["R01EN", 112100.0, 300100.0, 180.0, 200.0, [["R", 12000.0, 90.0, "sp"]]],
	["R02WS", 87900.0, 499900.0, 0.0, 200.0, [["R", 12000.0, 90.0, "sp"]]],
	["R02WN", 87900.0, 500100.0, 0.0, 200.0, [["L", 12000.0, 90.0, "sp"]]],
	["R02ES", 112100.0, 499900.0, 180.0, 200.0, [["L", 12000.0, 90.0, "sp"]]],
	["R02EN", 112100.0, 500100.0, 180.0, 200.0, [["R", 12000.0, 90.0, "sp"]]],
	["R10WS", 287900.0, 99900.0, 0.0, 200.0, [["R", 12000.0, 90.0, "sp"]]],
	["R10WN", 287900.0, 100100.0, 0.0, 200.0, [["L", 12000.0, 90.0, "sp"]]],
	["R10ES", 312100.0, 99900.0, 180.0, 200.0, [["L", 12000.0, 90.0, "sp"]]],
	["R10EN", 312100.0, 100100.0, 180.0, 200.0, [["R", 12000.0, 90.0, "sp"]]],
	["R11WS", 287900.0, 299900.0, 0.0, 200.0, [["R", 12000.0, 90.0, "sp"]]],
	["R11WN", 287900.0, 300100.0, 0.0, 200.0, [["L", 12000.0, 90.0, "sp"]]],
	["R11ES", 312100.0, 299900.0, 180.0, 200.0, [["L", 12000.0, 90.0, "sp"]]],
	["R11EN", 312100.0, 300100.0, 180.0, 200.0, [["R", 12000.0, 90.0, "sp"]]],
	["R12WS", 287900.0, 499900.0, 0.0, 200.0, [["R", 12000.0, 90.0, "sp"]]],
	["R12WN", 287900.0, 500100.0, 0.0, 200.0, [["L", 12000.0, 90.0, "sp"]]],
	["R12ES", 312100.0, 499900.0, 180.0, 200.0, [["L", 12000.0, 90.0, "sp"]]],
	["R12EN", 312100.0, 500100.0, 180.0, 200.0, [["R", 12000.0, 90.0, "sp"]]],
	["R20WS", 487900.0, 99900.0, 0.0, 200.0, [["R", 12000.0, 90.0, "sp"]]],
	["R20WN", 487900.0, 100100.0, 0.0, 200.0, [["L", 12000.0, 90.0, "sp"]]],
	["R20ES", 512100.0, 99900.0, 180.0, 200.0, [["L", 12000.0, 90.0, "sp"]]],
	["R20EN", 512100.0, 100100.0, 180.0, 200.0, [["R", 12000.0, 90.0, "sp"]]],
	["R21WS", 487900.0, 299900.0, 0.0, 200.0, [["R", 12000.0, 90.0, "sp"]]],
	["R21WN", 487900.0, 300100.0, 0.0, 200.0, [["L", 12000.0, 90.0, "sp"]]],
	["R21ES", 512100.0, 299900.0, 180.0, 200.0, [["L", 12000.0, 90.0, "sp"]]],
	["R21EN", 512100.0, 300100.0, 180.0, 200.0, [["R", 12000.0, 90.0, "sp"]]],
	["R22WS", 487900.0, 499900.0, 0.0, 200.0, [["R", 12000.0, 90.0, "sp"]]],
	["R22WN", 487900.0, 500100.0, 0.0, 200.0, [["L", 12000.0, 90.0, "sp"]]],
	["R22ES", 512100.0, 499900.0, 180.0, 200.0, [["L", 12000.0, 90.0, "sp"]]],
	["R22EN", 512100.0, 500100.0, 180.0, 200.0, [["R", 12000.0, 90.0, "sp"]]],
	["Eridanus", 343000.0, 300100.0, 180.0, 200.0, [["R", 7000.0, 60.0, "sp"], ["S", 3500.0, 0.0, "sp"], ["L", 7000.0, 120.0, "sf"], ["S", 3500.0, 0.0, "sp"], ["R", 7000.0, 60.0, "sp"]]],
	["Dunes", 57000.0, 500100.0, 0.0, 200.0, [["L", 7000.0, 60.0, "sp"], ["S", 3500.0, 0.0, "sp"], ["R", 7000.0, 120.0, "sf"], ["S", 3500.0, 0.0, "sp"], ["L", 7000.0, 60.0, "sp"]]],
	["Glacier", 543000.0, 500100.0, 180.0, 200.0, [["R", 7000.0, 60.0, "sp"], ["S", 3500.0, 0.0, "sp"], ["L", 7000.0, 120.0, "sf"], ["S", 3500.0, 0.0, "sp"], ["R", 7000.0, 60.0, "sp"]]],
	["Basalt", 57000.0, 99900.0, 0.0, 200.0, [["R", 7000.0, 60.0, "sp"], ["S", 3500.0, 0.0, "sp"], ["L", 7000.0, 120.0, "sf"], ["S", 3500.0, 0.0, "sp"], ["R", 7000.0, 60.0, "sp"]]],
	["Mesa", 543000.0, 99900.0, 180.0, 200.0, [["L", 7000.0, 60.0, "sp"], ["S", 3500.0, 0.0, "sp"], ["R", 7000.0, 120.0, "sf"], ["S", 3500.0, 0.0, "sp"], ["L", 7000.0, 60.0, "sp"]]],
	["TE1-", 26600.0, 100100.0, -180.0, 200.0, [["R", 6000.0, 59.447122451642976, "sp"], ["L", 6000.0, 298.89424490328594, "sp"], ["R", 6000.0, 59.447122451642976, "sp"]]],
	["TE1+", 573400.0000000542, 99900.00000000012, 3.8246170044598787e-13, 200.0, [["R", 6000.0, 59.447122451642976, "sp"], ["L", 6000.0, 298.89424490328594, "sp"], ["R", 6000.0, 59.447122451642976, "sp"]]],
	["TE2-", 26600.0, 300100.0, -180.0, 200.0, [["R", 6000.0, 59.447122451642976, "sp"], ["L", 6000.0, 298.89424490328594, "sp"], ["R", 6000.0, 59.447122451642976, "sp"]]],
	["TE2+", 573399.9999999488, 299899.99999999924, -3.26739873311754e-13, 200.0, [["R", 6000.0, 59.447122451642976, "sp"], ["L", 6000.0, 298.89424490328594, "sp"], ["R", 6000.0, 59.447122451642976, "sp"]]],
	["TE3-", 26600.0, 500100.0, -180.0, 200.0, [["R", 6000.0, 59.447122451642976, "sp"], ["L", 6000.0, 298.89424490328594, "sp"], ["R", 6000.0, 59.447122451642976, "sp"]]],
	["TE3+", 573399.9999999489, 499900.000000001, 3.7730572313033416e-13, 200.0, [["R", 6000.0, 59.447122451642976, "sp"], ["L", 6000.0, 298.89424490328594, "sp"], ["R", 6000.0, 59.447122451642976, "sp"]]],
	["TN1-", 99900.0, 26600.0, -90.0, 200.0, [["R", 6000.0, 59.447122451642976, "sp"], ["L", 6000.0, 298.89424490328594, "sp"], ["R", 6000.0, 59.447122451642976, "sp"]]],
	["TN1+", 100099.99999999856, 573399.9999999264, 90.0000000000011, 200.0, [["R", 6000.0, 59.447122451642976, "sp"], ["L", 6000.0, 298.89424490328594, "sp"], ["R", 6000.0, 59.447122451642976, "sp"]]],
	["TN2-", 299900.0, 26600.0, -90.0, 200.0, [["R", 6000.0, 59.447122451642976, "sp"], ["L", 6000.0, 298.89424490328594, "sp"], ["R", 6000.0, 59.447122451642976, "sp"]]],
	["TN2+", 300099.9999999948, 573399.9999999453, 90.00000000000979, 200.0, [["R", 6000.0, 59.447122451642976, "sp"], ["L", 6000.0, 298.89424490328594, "sp"], ["R", 6000.0, 59.447122451642976, "sp"]]],
	["TN3-", 499900.0, 26600.0, -90.0, 200.0, [["R", 6000.0, 59.447122451642976, "sp"], ["L", 6000.0, 298.89424490328594, "sp"], ["R", 6000.0, 59.447122451642976, "sp"]]],
	["TN3+", 500099.9999999891, 573400.0000000342, 90.00000000000406, 200.0, [["R", 6000.0, 59.447122451642976, "sp"], ["L", 6000.0, 298.89424490328594, "sp"], ["R", 6000.0, 59.447122451642976, "sp"]]],
	["J0", 268000.0, 299900.0, 0.0, 200.0, [["R", 45000.0, 7.1506790378981435, "sp"], ["L", 45000.0, 7.1506790378981435, "sp"], ["S", 7796.8754358438055, 0.0, "sp"]]],
	["K0", 290218.6999999926, 299200.00000000047, 0.0, 400.0, [["S", 36578.175435843805, 0.0, "sp"], ["L", 45000.0, 7.1506790378981435, "sp"], ["R", 45000.0, 7.1506790378981435, "sp"]]],
	["J1", 300100.0, 68000.0, 90.0, 200.0, [["R", 45000.0, 7.1506790378981435, "sp"], ["L", 45000.0, 7.1506790378981435, "sp"], ["S", 7796.8754358438055, 0.0, "sp"]]],
	["K1", 300799.9999999999, 90218.69999999818, 90.0, 400.0, [["S", 36578.175435843805, 0.0, "sp"], ["L", 45000.0, 7.1506790378981435, "sp"], ["R", 45000.0, 7.1506790378981435, "sp"]]],
	["J2", 332000.0, 500100.0, -180.0, 200.0, [["R", 45000.0, 7.1506790378981435, "sp"], ["L", 45000.0, 7.1506790378981435, "sp"], ["S", 7796.8754358438055, 0.0, "sp"]]],
	["K2", 309781.3000000074, 500799.9999999994, -180.0, 400.0, [["S", 36578.175435843805, 0.0, "sp"], ["L", 45000.0, 7.1506790378981435, "sp"], ["R", 45000.0, 7.1506790378981435, "sp"]]],
	["J3", 99900.0, 332000.0, -90.0, 200.0, [["R", 45000.0, 7.1506790378981435, "sp"], ["L", 45000.0, 7.1506790378981435, "sp"], ["S", 7796.8754358438055, 0.0, "sp"]]],
	["K3", 99199.99999999994, 309781.3000000074, -90.0, 400.0, [["S", 36578.175435843805, 0.0, "sp"], ["L", 45000.0, 7.1506790378981435, "sp"], ["R", 45000.0, 7.1506790378981435, "sp"]]],
	["OEridanus", 266000.0, 304000.0, 0.0, 200.0, [["R", 12000.0, 33.12294020774379, "sp"], ["L", 12000.0, 33.12294020774379, "sp"]]],
	["ODunes", 134000.0, 504000.0, 180.0, 200.0, [["L", 12000.0, 33.12294020774379, "sp"], ["R", 12000.0, 33.12294020774379, "sp"]]],
	["OGlacier", 466000.0, 504000.0, 0.0, 200.0, [["R", 12000.0, 33.12294020774379, "sp"], ["L", 12000.0, 33.12294020774379, "sp"]]],
	["OBasalt", 134000.0, 96000.0, 180.0, 200.0, [["R", 12000.0, 33.12294020774379, "sp"], ["L", 12000.0, 33.12294020774379, "sp"]]],
	["OMesa", 466000.0, 96000.0, 0.0, 200.0, [["L", 12000.0, 33.12294020774379, "sp"], ["R", 12000.0, 33.12294020774379, "sp"]]],
]
# [parent road, a0, a1, child road, b0, b1, sense]: the two roads are one through these samples
const NET_JUNCTIONS := [
	[0, 2611, 2731, 6, 0, 101, 1], [3, 2611, 2731, 6, 685, 786, -1], [0, 2611, 2731, 7, 0, 101, 1], [3, 3519, 3639, 7, 685, 786, 1], [0, 3519, 3639, 8, 0, 101, -1], [3, 2611, 2731, 8, 685, 786, -1],
	[0, 3519, 3639, 9, 0, 101, -1], [3, 3519, 3639, 9, 685, 786, 1], [1, 2611, 2731, 10, 0, 101, 1], [3, 11088, 11208, 10, 685, 786, -1], [1, 2611, 2731, 11, 0, 101, 1], [3, 11996, 12116, 11, 685, 786, 1],
	[1, 3519, 3639, 12, 0, 101, -1], [3, 11088, 11208, 12, 685, 786, -1], [1, 3519, 3639, 13, 0, 101, -1], [3, 11996, 12116, 13, 685, 786, 1], [2, 2611, 2731, 14, 0, 101, 1], [3, 19592, 19712, 14, 685, 786, -1],
	[2, 2611, 2731, 15, 0, 101, 1], [3, 20500, 20620, 15, 685, 786, 1], [2, 3519, 3639, 16, 0, 101, -1], [3, 19592, 19712, 16, 685, 786, -1], [2, 3519, 3639, 17, 0, 101, -1], [3, 20500, 20620, 17, 685, 786, 1],
	[0, 11075, 11195, 18, 0, 101, 1], [4, 2611, 2731, 18, 685, 786, -1], [0, 11075, 11195, 19, 0, 101, 1], [4, 3519, 3639, 19, 685, 786, 1], [0, 11983, 12103, 20, 0, 101, -1], [4, 2611, 2731, 20, 685, 786, -1],
	[0, 11983, 12103, 21, 0, 101, -1], [4, 3519, 3639, 21, 685, 786, 1], [1, 11128, 11248, 22, 0, 101, 1], [4, 11144, 11264, 22, 685, 786, -1], [1, 11128, 11248, 23, 0, 101, 1], [4, 12052, 12172, 23, 685, 786, 1],
	[1, 12036, 12156, 24, 0, 101, -1], [4, 11144, 11264, 24, 685, 786, -1], [1, 12036, 12156, 25, 0, 101, -1], [4, 12052, 12172, 25, 685, 786, 1], [2, 11050, 11170, 26, 0, 101, 1], [4, 19583, 19703, 26, 685, 786, -1],
	[2, 11050, 11170, 27, 0, 101, 1], [4, 20491, 20611, 27, 685, 786, 1], [2, 11958, 12078, 28, 0, 101, -1], [4, 19583, 19703, 28, 685, 786, -1], [2, 11958, 12078, 29, 0, 101, -1], [4, 20491, 20611, 29, 685, 786, 1],
	[0, 19502, 19622, 30, 0, 101, 1], [5, 2611, 2731, 30, 685, 786, -1], [0, 19502, 19622, 31, 0, 101, 1], [5, 3519, 3639, 31, 685, 786, 1], [0, 20410, 20530, 32, 0, 101, -1], [5, 2611, 2731, 32, 685, 786, -1],
	[0, 20410, 20530, 33, 0, 101, -1], [5, 3519, 3639, 33, 685, 786, 1], [1, 19578, 19698, 34, 0, 101, 1], [5, 11038, 11158, 34, 685, 786, -1], [1, 19578, 19698, 35, 0, 101, 1], [5, 11946, 12066, 35, 685, 786, 1],
	[1, 20486, 20606, 36, 0, 101, -1], [5, 11038, 11158, 36, 685, 786, -1], [1, 20486, 20606, 37, 0, 101, -1], [5, 11946, 12066, 37, 685, 786, 1], [2, 19543, 19663, 38, 0, 101, 1], [5, 19555, 19675, 38, 685, 786, -1],
	[2, 19543, 19663, 39, 0, 101, 1], [5, 20463, 20583, 39, 685, 786, 1], [2, 20451, 20571, 40, 0, 101, -1], [5, 19555, 19675, 40, 685, 786, -1], [2, 20451, 20571, 41, 0, 101, -1], [5, 20463, 20583, 41, 685, 786, 1],
	[1, 13345, 13444, 42, 0, 80, -1], [1, 12267, 12366, 42, 1435, 1515, -1], [2, 1323, 1422, 43, 0, 80, 1], [2, 2401, 2500, 43, 1435, 1515, 1], [2, 21760, 21859, 44, 0, 80, -1], [2, 20682, 20781, 44, 1435, 1515, -1],
	[0, 1323, 1422, 45, 0, 80, 1], [0, 2401, 2500, 45, 1435, 1515, 1], [0, 21719, 21818, 46, 0, 80, -1], [0, 20641, 20740, 46, 1435, 1515, -1], [0, 0, 77, 47, 0, 74, -1], [0, 0, 77, 47, 1751, 1825, 1],
	[0, 23064, 23141, 48, 0, 74, 1], [0, 23064, 23141, 48, 1751, 1825, -1], [1, 0, 77, 49, 0, 74, -1], [1, 0, 77, 49, 1751, 1825, 1], [1, 23140, 23217, 50, 0, 74, 1], [1, 23140, 23217, 50, 1751, 1825, -1],
	[2, 0, 77, 51, 0, 74, -1], [2, 0, 77, 51, 1751, 1825, 1], [2, 23105, 23182, 52, 0, 74, 1], [2, 23105, 23182, 52, 1751, 1825, -1], [3, 0, 77, 53, 0, 74, -1], [3, 0, 77, 53, 1751, 1825, 1],
	[3, 23154, 23231, 54, 0, 74, 1], [3, 23154, 23231, 54, 1751, 1825, -1], [4, 0, 77, 55, 0, 74, -1], [4, 0, 77, 55, 1751, 1825, 1], [4, 23145, 23222, 56, 0, 74, 1], [4, 23145, 23222, 56, 1751, 1825, -1],
	[5, 0, 77, 57, 0, 74, -1], [5, 0, 77, 57, 1751, 1825, 1], [5, 23117, 23194, 58, 0, 74, 1], [5, 23117, 23194, 58, 1751, 1825, -1], [1, 10299, 10505, 59, 0, 187, 1], [1, 12990, 13235, 60, 1768, 1995, 1],
	[4, 1782, 1988, 61, 0, 187, 1], [4, 4473, 4718, 62, 1768, 1995, 1], [2, 12701, 12907, 63, 0, 187, -1], [2, 9971, 10216, 64, 1768, 1995, -1], [3, 12739, 12945, 65, 0, 187, -1], [3, 10009, 10254, 66, 1768, 1995, -1],
	[1, 10662, 10782, 67, 479, 580, 1], [2, 3985, 4105, 68, 479, 580, -1], [2, 19077, 19197, 69, 479, 580, 1], [0, 3985, 4105, 70, 479, 580, -1], [0, 19036, 19156, 71, 479, 580, 1],
]
# [name, biome, centre x, centre y, road, terminal sample]
const NET_CITIES := [
	["ERIDANUS", "verdant", 329137.64169443276, 313131.07863207115, 42, 757],
	["DUNES", "desert", 70862.35830556872, 513131.0786320711, 43, 757],
	["GLACIER", "ice", 529137.6416944333, 513131.07863207115, 44, 757],
	["BASALT", "basalt", 70862.35830556872, 86868.92136793051, 45, 757],
	["MESA", "mesa", 529137.6416944332, 86868.92136793045, 46, 757],
]
# the roads' heights: [road, [[sample, m, slope], ...]], Hermite between keys (flyovers, jumps)
const NET_HEIGHTS := [
	[3, [[2750, 0.0, 0.0], [3000, 120.0, 0.0], [3250, 120.0, 0.0], [3500, 0.0, 0.0], [11227, 0.0, 0.0], [11477, 120.0, 0.0], [11727, 120.0, 0.0], [11977, 0.0, 0.0], [19731, 0.0, 0.0], [19981, 120.0, 0.0], [20231, 120.0, 0.0], [20481, 0.0, 0.0]]],
	[4, [[2750, 0.0, 0.0], [3000, 120.0, 0.0], [3250, 120.0, 0.0], [3500, 0.0, 0.0], [11283, 0.0, 0.0], [11533, 120.0, 0.0], [11783, 120.0, 0.0], [12033, 0.0, 0.0], [19722, 0.0, 0.0], [19972, 120.0, 0.0], [20222, 120.0, 0.0], [20472, 0.0, 0.0]]],
	[5, [[2750, 0.0, 0.0], [3000, 120.0, 0.0], [3250, 120.0, 0.0], [3500, 0.0, 0.0], [11177, 0.0, 0.0], [11427, 120.0, 0.0], [11677, 120.0, 0.0], [11927, 0.0, 0.0], [19694, 0.0, 0.0], [19944, 120.0, 0.0], [20194, 120.0, 0.0], [20444, 0.0, 0.0]]],
	[59, [[628, 0.0, 0.0], [795, 299.49980670365215, 0.1494510013491278]]],
	[60, [[0, 748.6536860839753, 0.13150334629453153], [208, 1076.886038435126, 0.0], [991, 1076.886038435126, 0.0], [1574, 0.0, 0.0]]],
	[61, [[628, 0.0, 0.0], [795, 299.49980670365215, 0.1494510013491278]]],
	[62, [[0, 748.6536860839753, 0.13150334629453153], [208, 1076.886038435126, 0.0], [991, 1076.886038435126, 0.0], [1574, 0.0, 0.0]]],
	[63, [[628, 0.0, 0.0], [795, 299.49980670365215, 0.1494510013491278]]],
	[64, [[0, 748.6536860839753, 0.13150334629453153], [208, 1076.886038435126, 0.0], [991, 1076.886038435126, 0.0], [1574, 0.0, 0.0]]],
	[65, [[628, 0.0, 0.0], [795, 299.49980670365215, 0.1494510013491278]]],
	[66, [[0, 748.6536860839753, 0.13150334629453153], [208, 1076.886038435126, 0.0], [991, 1076.886038435126, 0.0], [1574, 0.0, 0.0]]],
]
# [launch road (its end is a lip), catch deck, the slowest that lands (mph)]
const NET_JUMPS := [[59, 60, 3000.0], [61, 62, 3000.0], [63, 64, 3000.0], [65, 66, 3000.0]]
# [city, road]: the on-ramps from the open ground (their start is open)
const NET_ONRAMPS := [[0, 67], [1, 68], [2, 69], [3, 70], [4, 71]]
# </network>
# The courses: widths per mode (else GP_WIDTH, constant); width_r: the width-easing box (samples);
# banks: per mode, degrees (else GP_BANK in the corners), each eased by two passes of its own box,
# bank_r (samples; else GP_BANK_R).
const COURSES := {
	"gp": {"segs": GP_SEGS, "checkpoints": 12},
	"gp_dunes": {"segs": GP_DUNES_SEGS, "checkpoints": 12},
	"gp_glacier": {"segs": GP_GLACIER_SEGS, "checkpoints": 12},
	"gp_basalt": {"segs": GP_BASALT_SEGS, "checkpoints": 12},
	"gp_mesa": {"segs": GP_MESA_SEGS, "checkpoints": 12},

	"eridanus": {"segs": ERI_SEGS, "checkpoints": 24, "widths": {"sf": 140.0, "sp": 400.0}, "width_r": 40,
		"banks": {"sf": 10.0, "sp": 3.0}, "bank_r": {"sf": 20, "sp": 100}, "branches": [ERI_SHADE], "pad": ERI_PAD, "ramps": ERI_RAMPS},
}
var track_name := ""   # the course's name ("gp", "eridanus") on a course
var course := false    # on a course (COURSES): banked corners push
var tmode := PackedByteArray()   # courses: per sample, 0 a STARFIGHTER ("sf") section, 1 SPEEDCRAFT ("sp")


class Body:
	var m: float
	var inertia: float
	var x := 0.0
	var y := 0.0
	var vx := 0.0
	var vy := 0.0
	var th := 0.0
	var w := 0.0
	var fx := 0.0
	var fy := 0.0
	var t := 0.0
	var hint := 0
	var contact := [false, false]
	var heat := 0.3
	var health := 1.0
	var flameout := false
	var sputter := 1.0
	var sputter_t := 0.0
	var thrust := 0.0
	var front := 0.0   # the front speed brakes' deployment, 0..1 (the view's flaps)
	var z := 0.0
	var vz := 0.0
	var grip := 1.0
	var path := 0   # the road its hint is on: 0 the main road, k + 1 branch k
	var touch := {}   # the obstacles (ids) it's touching (one 'bump' a contact)
	var off_road := false   # the Network: off the roads (off a lip, on the open ground): no walls, the hover over the terrain
	var lock := false       # ... just caught by a road, easing onto its surface

	func _init(mass: float, moment: float) -> void:
		m = mass
		inertia = moment


## A branch road (the shade line, tools/design_eridanus.py), mirroring sim-core.js buildBranch:
## its segments walked from the main road's sample from_i (that point and heading), sampled as
## the courses are, one width, unbanked, ending on main's join_i (its last sample's segment runs
## on along the main road's). Open ended. Locked unless the job opens it.
class TrackPath:
	var name := ""
	var px := PackedFloat64Array()
	var py := PackedFloat64Array()
	var tx := PackedFloat64Array()
	var ty := PackedFloat64Array()
	var nx := PackedFloat64Array()
	var ny := PackedFloat64Array()
	var len := PackedFloat64Array()
	var w := PackedFloat64Array()
	var bank := PackedFloat64Array()
	var N := 0
	var length := 0.0
	var from_i := 0
	var join_i := 0
	var jz := 0
	var covered := Vector2i.ZERO   # the canopy's samples, first to last
	var roll: Array = []   # the corkscrews: [first sample, last sample, deg from, deg to], in order
	var height := 0.0      # the road's height under the canopy (m), turned over
	var open := false
	var mode := PackedByteArray()   # the Network: per sample, 0 STARFIGHTER ("sf"), 1 SPEEDCRAFT
	var jx: Array = []              # the Network: the junctions this road is in (indices into junctions)
	var role := ""                  # the Network: "launch" (its end is a lip), "catch" (a deck that catches jumps), "on" (from the open ground)
	var open0 := true               # the Network: no junction holds its first sample (run off it: off the roads)
	var open1 := true               # ... its last


var P: Dictionary
var eL: Body
var eR: Body
var pod: Body
var bodies: Array

# track: "circuit" (parallel arrays below) or "range" (ramps)
var kind := "circuit"
var ramps: Array = []   # [x0, len, h] per kicker
var N := 0
var track_length := 0.0
var checkpoints := 8
var tpx := PackedFloat64Array()
var tpy := PackedFloat64Array()
var ttx := PackedFloat64Array()
var tty := PackedFloat64Array()
var tnx := PackedFloat64Array()
var tny := PackedFloat64Array()
var tlen := PackedFloat64Array()
var tw := PackedFloat64Array()
var tb := PackedFloat64Array()   # GP: bank per sample, radians (+ = tilted down to the left, a left-hander)
var branches: Array[TrackPath] = []   # courses: the branch roads (Eridanus: the shade line)
var gate: Array = []   # per branch, this pass: null (not at its split), true (admitted), false (shut)
var pod_path := 0      # the pod's path last step (laps carry on from a branch's join)
var pad := -1          # courses: the job's medical pad (main sample), -1 for none
var mouth := -1        # courses: the start town's mouth, where the loop last turns into a town
var covered_ramps: Array = []   # courses: the covered ramps at each end of each town, [first, last] main samples
var tcover := PackedByteArray()   # per main sample: 1 under a covered ramp (shelter from the dawn)
## The job (the emergency run), empty when there's none: stage "out" | "drop" | "home" | "done" |
## "failed", t (s since its clock started, on the first move), t0 (when, null until then), held
## (s stopped on the pad), route "open" | "shade", margin (s), reason "" | "dawn" | "crash", prev_d.
var job: Dictionary = {}
## The Network (kind "network", tools/design_network.py): its roads (open TrackPaths, a body's path
## is its road), the junction table ([a, a0, a1, b, b0, b1, sense]: through those samples roads a and
## b are one), the cities ({name, biome, cx, cy, road, i}: i the terminal's sample), and the state:
## from (the city last reached), t0 (when the clock started, -1 until the first move), found
## ({city: true}), prev (the pod's Vector2i(road, sample) a step ago, x -1 for none).
var roads: Array[TrackPath] = []
var junctions: Array = []
var cities: Array = []
var net: Dictionary = {}
## Moving obstacles (the Network's traffic, driven outside the sim), mirroring sim-core.js: each
## {id, x, y, vx, vy, r}, advanced along its velocity every step; a body's circles feel their forcefields.
var obstacles: Array = []
var _net_h := {}   # road -> its height keys [[sample, m, slope], ...] (flyovers, jumps), Hermite between
var jumps: Array = []      # the Network's jumps: [launch road, catch deck, the slowest that lands (mph)] (NET_JUMPS)
var onramps: Array = []    # ... its on-ramps from the open ground: [city, road] (NET_ONRAMPS)
var _net_cells := {}   # the Network's grid: a NET_CELL square's key -> [[road, first, last sample], ...] (sample runs in it)
var on_ground := false   # the Network: the pod off the roads and down on the open ground (once per spell)
const NET_CELL := 2048.0
const NET_EDGE := 300.0
const LOCK_W := 4.0          # the deck lock's catch: a critically damped spring ...
const LOCK_A := 20.0 * G     # ... capped (a deck's pull-out at 4,300 mph is ~10 g: the catch has to follow it)
const JC_REACH := 40.0       # a catch deck reaches this far up for a jump
const CORK_EASE := 0.15   # each corkscrew's roll rate ramps up and down over this share of it

# race and craft state
var battery := 1.0
var armed := false
var mode := "normal"
# Live handling switch, mirroring sim-core.js: inp.handling asks for "speed" or "starfighter";
# STARFIGHTER only engages below P.sfEngageV, then the handling keys blend over P.modeBlendT s.
var hwant := "speed"
var hblend := 0.0
var _hk: Array = []      # the handling keys that blend (not given explicitly in the overrides)
var _h0 := {}
var _h1 := {}
var binder_broken := false
var _tow_u := -1.0          # tow bar's stored energy last substep (-1 = none yet), for the energy audit
var crash_t := 0.0
var time := 0.0
var lap := 0
var lap_start := -1.0   # -1 means not started (JS null)
var last_lap := -1.0
var best_lap := -1.0
var visited := {}
var checkpoint := 0
var progress_i := 0
var cables := [{"f": 0.0}, {"f": 0.0}]
var events: Array = []
var run_start := -1.0   # range run timer; -1 = not started (JS null)
var last_run := -1.0
var best_run := -1.0
var finished := false
var run_active := false
var result: Dictionary = {}   # empty = no result (JS null); else {type, t, err}
var pair_th := 0.0
var binder_stretch := 0.0

var _rng := 1
var _n_i := 0
var _n_lat := 0.0
var _n_w := 0.0
var _n_nx := 0.0
var _n_ny := 0.0
var _n_t := 0.0   # how far along sample _n_i's segment the nearest point lies, 0..1
var _n_off := false   # the nearest point is past an end of a branch (no road there)
var _n_tx := 0.0   # (branches and the Network) the tangent at _n_i ...
var _n_ty := 0.0
var _n_over := -INF   # ... and past an end, how far (m; negative short of it; -INF not an end sample)
var _pvx := 0.0
var _pvy := 0.0


var _overrides := {}


func _init(overrides: Dictionary = {}) -> void:
	_overrides = overrides.duplicate()
	P = DEFAULTS.duplicate()
	# the grand prix is a STARFIGHTER track unless a handling is asked for
	var hname: String = overrides.get("handling", "starfighter" if COURSES.has(overrides.get("track", "")) else DEFAULTS.handling)
	P.merge(HANDLING.get(hname, {}), true)
	P.merge(TRACKS.get(overrides.get("track", ""), {}), true)
	P.merge(overrides, true)
	P.handling = hname
	hwant = hname
	hblend = 1.0 if hname == "starfighter" else 0.0
	for k in HANDLING.starfighter:
		if not overrides.has(k):
			_hk.append(k)
			_h0[k] = HANDLING.speed.get(k, DEFAULTS[k])
			_h1[k] = HANDLING.starfighter[k]
	_rng = int(P.seed) & 0xFFFFFFFF
	if _rng == 0:
		_rng = 1
	if P.track == "range":
		kind = "range"
		_build_range()
	elif P.track == "network":
		_build_network()
	elif COURSES.has(P.track):
		_build_course(P.track)
	else:
		_build_track()
	var e_i: float = P.engineMass * pow(P.engineLen, 2) / 12.0
	var p_i: float = P.podMass * (pow(P.podLen, 2) + pow(P.podWidth, 2)) / 12.0
	eL = Body.new(P.engineMass, e_i)
	eR = Body.new(P.engineMass, e_i)
	pod = Body.new(P.podMass, p_i)
	bodies = [eL, eR, pod]
	# branches open only on the job that authorizes them (the shade line: the emergency run)
	for B in branches:
		B.open = P.job == "emergency"
	if P.job == "emergency" and pad >= 0:
		job = _new_job()
	if kind == "network":
		var sc := int(P.get("startCity", 0))
		net = {"from": sc, "t0": -1.0, "found": {sc: true}, "prev": Vector2i(-1, -1)}
	pod.x = float(P.startX) + 30.0   # range spawn point (respawn backs off 30 m)
	pod.y = float(P.startY)
	respawn(-1 if kind == "network" else 0)   # the Network: at the start city
	visited[0] = true


## Switch handling mode in place (Godot only: the game's in-cockpit toggle; not part of the
## JS parity surface). Presets only change per-step tuning, never masses or the track, so
## nothing built in _init goes stale. Restart or respawn afterwards.
func set_handling(name: String) -> void:
	_overrides["handling"] = name
	P = DEFAULTS.duplicate()
	P.merge(HANDLING.get(name, {}), true)
	P.merge(TRACKS.get(_overrides.get("track", ""), {}), true)
	P.merge(_overrides, true)
	hwant = name
	hblend = 1.0 if name == "starfighter" else 0.0


func _build_range() -> void:
	var i := 0
	while RAMP_X0 + RAMP_EVERY * i < RANGE_LEN - 500.0:
		var h: float = RAMP_H[i % 4]
		ramps.append([RAMP_X0 + RAMP_EVERY * i, h / RAMP_SLOPE[i % 4], h])
		i += 1
	track_length = RANGE_LEN


## Ground height under (x, y): kickers on the range's jump lane, flat everywhere else.
func ground(x: float, y: float) -> float:
	if kind != "range" or absf(y - JUMP_Y) > JUMP_W / 2.0 or x < RAMP_X0:
		return 0.0
	var idx := int(floor((x - RAMP_X0) / RAMP_EVERY))
	if idx >= ramps.size():
		return 0.0
	var r: Array = ramps[idx]
	var u: float = x - r[0]
	if u <= r[1]:
		return r[2] * u / r[1]
	if u <= r[1] + r[2]:
		return r[2] - (u - r[1])
	return 0.0


## Repulsor hover: spring-damper toward ride height, push-only, plus gravity. Exactly
## balanced on flat ground, so flat tracks are unchanged. Grip fades as a body lifts clear.
func _hover(b: Body, dt: float, az: float) -> void:
	if kind == "network" and not b.off_road:
		_rail_hover(b, dt)
		return
	var h := ground(b.x, b.y)
	var dhdt := (ground(b.x + b.vx * dt, b.y + b.vy * dt) - h) / dt
	var w: float = P.hoverOmega
	var up := maxf(0.0, G + w * w * (P.rideH - (b.z - h)) - 2.0 * P.hoverZeta * w * (b.vz - dhdt))
	b.vz += (up - G + az) * dt
	b.z += b.vz * dt
	if b.z - h < 0.3:
		b.z = h + 0.3
		if b.vz < dhdt:
			if dhdt - b.vz > 12.0:
				events.append({"type": "land", "v": dhdt - b.vz})
			b.vz = dhdt
	b.grip = clampf(1.0 - (b.z - h - P.rideH - 0.5) / 1.5, 0.0, 1.0)


## The Network's deck lock, mirroring sim-core.js railHover: a body on a road rides its surface (the
## road's forcefield holds it down as well as up: at 4,000 mph any crest tighter than 326 km would
## throw you off). Just caught (lock), it eases on: a critically damped spring, capped at LOCK_A.
func _road_f(b: Body) -> float:
	var R: TrackPath = roads[b.path]
	var i := b.hint
	return float(i) + clampf(((b.x - R.px[i]) * R.tx[i] + (b.y - R.py[i]) * R.ty[i]) / R.len[i], -1.0, 2.0)


func _rail_hover(b: Body, dt: float) -> void:
	var R: TrackPath = roads[b.path]
	var i := b.hint
	var f := _road_f(b)
	var lat := (b.x - R.px[i]) * R.nx[i] + (b.y - R.py[i]) * R.ny[i]
	var vl := b.vx * R.nx[i] + b.vy * R.ny[i]
	var h := road_h(b.path, f) + net_edge(R.w[i], lat).x
	var vs := b.vx * R.tx[i] + b.vy * R.ty[i]
	var dhdt := (road_h(b.path, f + vs * dt / R.len[i]) + net_edge(R.w[i], lat + vl * dt).x - h) / dt
	if b.lock:
		var acc := clampf(LOCK_W * LOCK_W * (h + P.rideH - b.z) - 2.0 * LOCK_W * (b.vz - dhdt), -LOCK_A, LOCK_A)
		b.vz += acc * dt
		b.z += b.vz * dt
		if absf(b.z - h - P.rideH) < 0.05 and absf(b.vz - dhdt) < 0.5:
			b.lock = false
		b.grip = clampf(1.0 - (b.z - h - P.rideH - 0.5) / 1.5, 0.0, 1.0)
		return
	b.z = h + P.rideH
	b.vz = dhdt
	b.grip = 1.0


## Off the roads, mirroring sim-core.js goFree: off an open end (a launch spur's lip, a highway's end).
func _go_free(b: Body) -> void:
	b.off_road = true
	b.lock = false
	b.contact = [false, false]
	if b == pod:
		events.append({"type": "airborne", "road": b.path, "lip": roads[b.path].role == "launch", "v": sqrt(b.vx * b.vx + b.vy * b.vy), "vz": b.vz})


## The roads near (x, y), mirroring sim-core.js netNear: per run in its grid cell (and the next cells
## if it's within NET_EDGE of an edge), the nearest point (every 8th sample, then the 8 either side).
## -> [[road, i, lat, w, nx, ny, off], ...]
func net_near(x: float, y: float) -> Array:
	var out: Array = []
	var cx := int(floor(x / NET_CELL))
	var cy := int(floor(y / NET_CELL))
	var fx := x - float(cx) * NET_CELL
	var fy := y - float(cy) * NET_CELL
	for dx in [-1, 0, 1]:
		if (dx < 0 and fx > NET_EDGE) or (dx > 0 and fx < NET_CELL - NET_EDGE):
			continue
		for dy in [-1, 0, 1]:
			if (dy < 0 and fy > NET_EDGE) or (dy > 0 and fy < NET_CELL - NET_EDGE):
				continue
			var runs = _net_cells.get((cx + dx) * 4096 + (cy + dy))
			if runs == null:
				continue
			for run: Array in runs:
				var r: int = run[0]
				var R: TrackPath = roads[r]
				var bi: int = run[1]
				var bd := INF
				var i: int = run[1]
				while i <= int(run[2]):
					var d := (x - R.px[i]) * (x - R.px[i]) + (y - R.py[i]) * (y - R.py[i])
					if d < bd:
						bd = d
						bi = i
					i += 8
				_nearest_branch(R, x, y, bi, 8)
				out.append([r, _n_i, _n_lat, _n_w, _n_nx, _n_ny, _n_off])
	return out


## A body off the roads, mirroring sim-core.js freeContact: caught by a road it touches down inside
## (a catch deck reaches JC_REACH up for a jump; slower, under its lip, the deck turns it down), else
## held off the roads' walls from outside near the ground.
func _free_contact(b: Body, circles: Array, dt: float) -> void:
	var ns := net_near(b.x, b.y)
	for n: Array in ns:
		var R: TrackPath = roads[n[0]]
		if n[6] or absf(n[2]) > float(n[3]) / 2.0 - 2.0:
			continue
		var i: int = n[1]
		var u := clampf(((b.x - R.px[i]) * R.tx[i] + (b.y - R.py[i]) * R.ty[i]) / R.len[i], -1.0, 2.0)
		var h := road_h(n[0], float(i) + u) + net_edge(float(n[3]), float(n[2])).x
		var dz: float = b.z - h - P.rideH
		if dz >= -3.0 and dz <= (JC_REACH if R.role == "catch" else 2.5):
			var vs := b.vx * R.tx[i] + b.vy * R.ty[i]
			var dhdt := (road_h(n[0], float(i) + u + vs * dt / R.len[i]) - h) / dt
			b.off_road = false
			b.path = n[0]
			b.hint = i
			b.contact = [false, false]
			b.lock = absf(dz) > 0.05 or absf(b.vz - dhdt) > 0.5
			if b == pod:
				events.append({"type": "catch" if R.role == "catch" else "onroad", "road": n[0], "v": absf(b.vz - dhdt), "dz": dz})
				on_ground = false
			return
		if R.role == "catch" and dz < -3.0 and dz > -80.0:   # under the deck's lip: turned down
			var vs2 := b.vx * R.tx[i] + b.vy * R.ty[i]
			var dhdt2 := (road_h(n[0], float(i) + u + vs2 * dt / R.len[i]) - h) / dt
			if dz > -8.0:
				b.z = h + P.rideH - 8.0
			if b.vz > dhdt2 - 2.0:
				b.vz = dhdt2 - 2.0
	# walls from outside, near the ground
	for n: Array in ns:
		if n[6]:
			continue
		var R: TrackPath = roads[n[0]]
		var h := net_height(n[0], float(n[1])) + net_edge(float(n[3]), float(n[3]) / 2.0).x   # (at the wall's foot: the ramp's top)
		if absf(b.z - h - P.rideH) > 25.0:
			continue
		for c: Array in circles:
			var cx: float = c[0]
			var cy: float = c[1]
			var r: float = c[2]
			_nearest_branch(R, cx, cy, n[1], 4)
			var al := absf(_n_lat)
			var pen := _n_w / 2.0 + r - al
			if _n_off or al < _n_w / 2.0 - 2.0 or pen <= 0.0:
				continue
			var sgn := 1.0 if _n_lat > 0.0 else -1.0
			var nx := _n_nx * sgn
			var ny := _n_ny * sgn
			_point_vel(b, cx, cy)
			var vx := _pvx
			var vy := _pvy
			var vn := vx * nx + vy * ny
			var fn: float = P.wallK * pen - (P.wallC * vn if vn < 0.0 else 0.0)
			var tx := -ny
			var ty := nx
			var vt := vx * tx + vy * ty
			var ft: float = -signf(vt) * minf(P.wallMu * fn, absf(vt) * b.m / dt)
			_apply_at(b, fn * nx + ft * tx, fn * ny + ft * ty, cx, cy)
	if b == pod and not on_ground and b.z - P.rideH < 1.0:
		on_ground = true
		events.append({"type": "ground"})


## xorshift32, bit-identical to the JS reference.
func rand() -> float:
	var x := _rng
	x ^= (x << 13) & 0xFFFFFFFF
	x ^= x >> 17
	x ^= (x << 5) & 0xFFFFFFFF
	_rng = x
	return float(x) / 4294967296.0


static func wrap_angle(a: float) -> float:
	return atan2(sin(a), cos(a))


func _cr(a: float, b: float, c: float, d: float, t: float, t2: float, t3: float) -> float:
	return 0.5 * (2.0 * b + (-a + c) * t + (2.0 * a - 5.0 * b + 4.0 * c - d) * t2 + (-a + 3.0 * b - 3.0 * c + d) * t3)


func _build_track() -> void:
	var per := 48
	var n := CTRL.size()
	for i in n:
		var p0: Array = CTRL[(i - 1 + n) % n]
		var p1: Array = CTRL[i]
		var p2: Array = CTRL[(i + 1) % n]
		var p3: Array = CTRL[(i + 2) % n]
		for k in per:
			var t := float(k) / per
			var t2 := t * t
			var t3 := t2 * t
			tpx.append(_cr(p0[0], p1[0], p2[0], p3[0], t, t2, t3))
			tpy.append(_cr(p0[1], p1[1], p2[1], p3[1], t, t2, t3))
	N = tpx.size()
	# Packed arrays are value types: resize each one directly, not through a loop variable.
	ttx.resize(N)
	tty.resize(N)
	tnx.resize(N)
	tny.resize(N)
	tlen.resize(N)
	tw.resize(N)
	var s := 0.0
	for i in N:
		var j := (i + 1) % N
		var dx := tpx[j] - tpx[i]
		var dy := tpy[j] - tpy[i]
		var l := sqrt(dx * dx + dy * dy)
		ttx[i] = dx / l
		tty[i] = dy / l
		tnx[i] = -tty[i]
		tny[i] = ttx[i]
		tlen[i] = l
		s += l
		tw[i] = 82.0 + 24.0 * sin(float(i) / N * PI * 6.0 + 0.6)
	track_length = s


func _build_course(name: String) -> void:
	track_name = name
	course = true
	var C: Dictionary = COURSES[name]
	checkpoints = C.checkpoints
	var x := 0.0
	var y := 0.0
	var h := 0.0
	var raw := PackedFloat64Array()
	var wraw := PackedFloat64Array()
	for sg in C.segs:
		var m: String = sg[3] if sg.size() > 3 else "sf"
		var w: float = C.widths[m] if C.has("widths") else GP_WIDTH
		if sg[0] == "S":
			var n := maxi(1, int(ceil(sg[1] / GP_STEP)))
			var d: float = sg[1] / n
			for k in n:
				tpx.append(x)
				tpy.append(y)
				raw.append(0.0)
				wraw.append(w)
				tmode.append(0 if m == "sf" else 1)
				x += d * cos(h)
				y += d * sin(h)
		else:
			var r: float = sg[1]
			var sn := 1.0 if sg[0] == "L" else -1.0
			var ang: float = sg[2] * PI / 180.0
			var n := maxi(1, int(ceil(r * ang / GP_STEP)))
			var da := ang / n
			var c := 2.0 * r * sin(da / 2.0)
			for k in n:
				tpx.append(x)
				tpy.append(y)
				var bdeg: float = C.banks[m] if C.has("banks") else (GP_BANK if m == "sf" else 0.0)
				raw.append(sn * bdeg * PI / 180.0)
				wraw.append(w)
				tmode.append(0 if m == "sf" else 1)
				x += c * cos(h + sn * da / 2.0)
				y += c * sin(h + sn * da / 2.0)
				h += sn * da
	N = tpx.size()
	ttx.resize(N)
	tty.resize(N)
	tnx.resize(N)
	tny.resize(N)
	tlen.resize(N)
	tw.resize(N)
	var width: PackedFloat64Array = _smooth_box(wraw, C.width_r) if C.has("widths") else wraw
	var s := 0.0
	for i in N:
		var j := (i + 1) % N
		var dx := tpx[j] - tpx[i]
		var dy := tpy[j] - tpy[i]
		var l := sqrt(dx * dx + dy * dy)
		ttx[i] = dx / l
		tty[i] = dy / l
		tnx[i] = -tty[i]
		tny[i] = ttx[i]
		tlen[i] = l
		s += l
		tw[i] = width[i]
	track_length = s
	if C.has("bank_r"):
		tb = PackedFloat64Array()
		tb.resize(N)
		for m in ["sf", "sp"]:
			var part := PackedFloat64Array()
			part.resize(N)
			for i in N:
				part[i] = raw[i] if tmode[i] == (0 if m == "sf" else 1) else 0.0
			var r: int = C.bank_r[m]
			var sm := _smooth_run(_smooth_run(part, r), r)
			for i in N:
				tb[i] += sm[i]
	else:
		tb = _smooth_bank(_smooth_bank(raw))
	for Bd in C.get("branches", []):
		branches.append(_build_branch(Bd))
	pad = C.get("pad", -1)
	covered_ramps = C.get("ramps", []).duplicate(true)
	tcover.resize(N)
	for r in covered_ramps:
		for i in range(int(r[0]), int(r[1]) + 1):
			tcover[posmod(i, N)] = 1
	for i in range(N - 1, 0, -1):
		if tmode[i] == 0 and tmode[i - 1] == 1:
			mouth = i
			break


## The Network, mirroring sim-core.js buildNetwork: open roads, each walked from its own pose as a
## branch is from its split (NET_STEP samples, a mode per segment; the last sample keeps the end
## heading), and the junction table.
func _build_network() -> void:
	kind = "network"
	track_name = "network"
	for rd in NET_ROADS:
		var B := TrackPath.new()
		B.name = rd[0]
		var x: float = rd[1]
		var y: float = rd[2]
		var h: float = rd[3] * PI / 180.0
		var width: float = rd[4]
		var md := 1
		for sg in rd[5]:
			md = 0 if sg[3] == "sf" else 1
			if sg[0] == "S":
				var n := maxi(1, int(ceil(sg[1] / NET_STEP)))
				var d: float = sg[1] / n
				for k in n:
					B.px.append(x)
					B.py.append(y)
					B.mode.append(md)
					x += d * cos(h)
					y += d * sin(h)
			else:
				var r: float = sg[1]
				var sn := 1.0 if sg[0] == "L" else -1.0
				var ang: float = sg[2] * PI / 180.0
				var n := maxi(1, int(ceil(r * ang / NET_STEP)))
				var da := ang / n
				var c := 2.0 * r * sin(da / 2.0)
				for k in n:
					B.px.append(x)
					B.py.append(y)
					B.mode.append(md)
					x += c * cos(h + sn * da / 2.0)
					y += c * sin(h + sn * da / 2.0)
					h += sn * da
		B.px.append(x)
		B.py.append(y)
		B.mode.append(md)
		B.N = B.px.size()
		for a in [B.tx, B.ty, B.nx, B.ny, B.len, B.w, B.bank]:
			a.resize(B.N)
		var s := 0.0
		for i in B.N:
			var dx := B.px[i + 1] - B.px[i] if i + 1 < B.N else NET_STEP * cos(h)
			var dy := B.py[i + 1] - B.py[i] if i + 1 < B.N else NET_STEP * sin(h)
			var l := sqrt(dx * dx + dy * dy)
			B.tx[i] = dx / l
			B.ty[i] = dy / l
			B.nx[i] = -B.ty[i]
			B.ny[i] = B.tx[i]
			B.len[i] = l
			s += l
			B.w[i] = width
			B.bank[i] = 0.0
		B.length = s
		roads.append(B)
	for k in NET_JUNCTIONS.size():
		var J: Array = NET_JUNCTIONS[k]
		junctions.append(J)
		roads[int(J[0])].jx.append(k)
		roads[int(J[3])].jx.append(k)
	for c in NET_CITIES:
		cities.append({"name": c[0], "biome": c[1], "cx": float(c[2]), "cy": float(c[3]), "road": int(c[4]), "i": int(c[5])})
	for hk in NET_HEIGHTS:
		_net_h[int(hk[0])] = hk[1]
	# Phase 3, mirroring sim-core.js: roles, open ends, the grid
	jumps = NET_JUMPS.duplicate(true)
	onramps = NET_ONRAMPS.duplicate(true)
	for jp in NET_JUMPS:
		roads[int(jp[0])].role = "launch"
		roads[int(jp[1])].role = "catch"
	for op in NET_ONRAMPS:
		roads[int(op[1])].role = "on"
	for J: Array in junctions:
		for e in [[int(J[0]), int(J[1]), int(J[2])], [int(J[3]), int(J[4]), int(J[5])]]:
			if e[1] <= 0:
				roads[e[0]].open0 = false
			if e[2] >= roads[e[0]].N - 1:
				roads[e[0]].open1 = false
	for r in roads.size():
		var R: TrackPath = roads[r]
		var key := -2147483648
		var run: Array = []
		for i in R.N:
			var k := net_cell(R.px[i], R.py[i])
			if k != key:
				key = k
				run = [r, i, i]
				if not _net_cells.has(k):
					_net_cells[k] = []
				_net_cells[k].append(run)
			else:
				run[2] = i


## The grid's key for (x, y) (NET_CELL squares), mirroring sim-core.js netCell.
static func net_cell(x: float, y: float) -> int:
	return int(floor(x / NET_CELL)) * 4096 + int(floor(y / NET_CELL))


## A road's height at (fractional) sample i: Hermite cubics between its keys [sample, m, slope] (zero
## slopes: a smoothstep), 0 off them. Real in the sims now (the deck lock), the view's decks too.
func net_height(road: int, i: float) -> float:
	var keys: Array = _net_h.get(road, [])
	for k in range(0, keys.size() - 1):
		var a: Array = keys[k]
		var b: Array = keys[k + 1]
		if i >= float(a[0]) and i <= float(b[0]):
			var n := maxi(1, int(b[0]) - int(a[0]))
			var u := (i - float(a[0])) / float(n)
			var d := float(n) * NET_STEP
			var u2 := u * u
			var u3 := u2 * u
			return (2.0 * u3 - 3.0 * u2 + 1.0) * float(a[1]) + (u3 - 2.0 * u2 + u) * d * float(a[2]) + (-2.0 * u3 + 3.0 * u2) * float(b[1]) + (u3 - u2) * d * float(b[2])
	return 0.0


## The Network's edges ramp up (Luke, 2026-10-20: "make the walls ramp up on the sides rather than a
## hard stop? Let the craft drift a bit"), mirroring sim-core.js netEdge: the outer EDGE_FRAC of each
## side (EDGE_MIN-EDGE_MAX m) banks up toward the wall, EDGE_ANG at it, as u^1.5 across (a quarter-pipe).
## -> Vector2(its height there (m), its bank (rad)) at `lat` m off the centreline of a road `w` wide.
const EDGE_FRAC := 0.15
const EDGE_MIN := 30.0
const EDGE_MAX := 60.0
const EDGE_ANG := 18.0 * PI / 180.0
static func net_edge_span(w: float) -> float:   # each ramp's width across (m)
	return clampf(w * EDGE_FRAC, EDGE_MIN, EDGE_MAX)


static func net_edge(w: float, lat: float) -> Vector2:
	var E := clampf(w * EDGE_FRAC, EDGE_MIN, EDGE_MAX)
	var u := (absf(lat) - (w / 2.0 - E)) / E
	if u <= 0.0:
		return Vector2.ZERO
	var v := minf(u, 1.0)
	var r := sqrt(v)
	return Vector2(E * tan(EDGE_ANG) * v * v * r / 2.5, EDGE_ANG * v * r)


## ... and past its ends (a body off its last sample, the step before it's freed), on at the end's slope.
func road_h(road: int, f: float) -> float:
	var N: int = roads[road].N
	if f > float(N - 1):
		return net_height(road, float(N - 1)) + (f - float(N - 1)) * (net_height(road, float(N - 1)) - net_height(road, float(N) - 1.01)) / 0.01
	if f < 0.0:
		return net_height(road, 0.0) + f * (net_height(road, 0.01) - net_height(road, 0.0)) / 0.01
	return net_height(road, f)


## Is any of the road's deck off the ground between samples lo and hi (inclusive)? Elsewhere
## net_height is exactly 0.
func _deck_between(road: int, lo: float, hi: float) -> bool:
	var keys: Array = _net_h.get(road, [])
	for k in range(0, keys.size() - 1):
		var a: Array = keys[k]
		var b: Array = keys[k + 1]
		if (float(a[1]) != 0.0 or float(b[1]) != 0.0) and hi >= float(a[0]) and lo <= float(b[0]):
			return true
	return false


func _build_branch(Bd: Dictionary) -> TrackPath:
	var B := TrackPath.new()
	B.name = Bd.name
	var f: int = Bd.from
	var x := tpx[f]
	var y := tpy[f]
	var h := atan2(tty[f], ttx[f])
	for sg in Bd.segs:
		if sg[0] == "S":
			var n := maxi(1, int(ceil(sg[1] / GP_STEP)))
			var d: float = sg[1] / n
			for k in n:
				B.px.append(x)
				B.py.append(y)
				x += d * cos(h)
				y += d * sin(h)
		else:
			var r: float = sg[1]
			var sn := 1.0 if sg[0] == "L" else -1.0
			var ang: float = sg[2] * PI / 180.0
			var n := maxi(1, int(ceil(r * ang / GP_STEP)))
			var da := ang / n
			var c := 2.0 * r * sin(da / 2.0)
			for k in n:
				B.px.append(x)
				B.py.append(y)
				x += c * cos(h + sn * da / 2.0)
				y += c * sin(h + sn * da / 2.0)
				h += sn * da
	B.px.append(x)
	B.py.append(y)
	B.N = B.px.size()
	for a in [B.tx, B.ty, B.nx, B.ny, B.len, B.w, B.bank]:
		a.resize(B.N)
	var j: int = Bd.join
	var s := 0.0
	for i in B.N:
		var dx := B.px[i + 1] - B.px[i] if i + 1 < B.N else ttx[j] * tlen[j]
		var dy := B.py[i + 1] - B.py[i] if i + 1 < B.N else tty[j] * tlen[j]
		var l := sqrt(dx * dx + dy * dy)
		B.tx[i] = dx / l
		B.ty[i] = dy / l
		B.nx[i] = -B.ty[i]
		B.ny[i] = B.tx[i]
		B.len[i] = l
		s += l
		B.w[i] = Bd.width
		B.bank[i] = 0.0
	B.length = s
	B.from_i = Bd.from
	B.join_i = j
	B.jz = Bd.jz
	B.covered = Vector2i(Bd.covered[0], Bd.covered[1])
	B.roll = Bd.roll.duplicate(true)
	B.height = Bd.height
	return B


## A centred moving average round the closed loop (box of 2 * r + 1 samples; banks: GP_BANK_R).
static func _smooth_box(a: PackedFloat64Array, r: int) -> PackedFloat64Array:
	var n := a.size()
	var out := PackedFloat64Array()
	out.resize(n)
	for i in n:
		var acc := 0.0
		for k in range(-r, r + 1):
			acc += a[posmod(i + k, n)]
		out[i] = acc / (2 * r + 1)
	return out


static func _smooth_bank(a: PackedFloat64Array) -> PackedFloat64Array:
	return _smooth_box(a, GP_BANK_R)


## The same average as a running sum: O(N) for the wide boxes (a 5 km bank ramp is 400 samples).
static func _smooth_run(a: PackedFloat64Array, r: int) -> PackedFloat64Array:
	var n := a.size()
	var w := 2 * r + 1
	var out := PackedFloat64Array()
	out.resize(n)
	var acc := 0.0
	for k in range(-r, r + 1):
		acc += a[posmod(k, n)]
	for i in n:
		out[i] = acc / w
		acc += a[posmod(i + r + 1, n)] - a[posmod(i - r, n)]
	return out


## Nearest centreline point in a window around hint. Results land in _n_*.
func _nearest(x: float, y: float, hint: int, win: int) -> void:
	var bd := INF
	_n_off = false
	for k in range(-win, win + 1):
		var i := posmod(hint + k, N)
		var t := clampf(((x - tpx[i]) * ttx[i] + (y - tpy[i]) * tty[i]) / tlen[i], 0.0, 1.0)
		var px := tpx[i] + ttx[i] * tlen[i] * t
		var py := tpy[i] + tty[i] * tlen[i] * t
		var d := (x - px) * (x - px) + (y - py) * (y - py)
		if d < bd:
			bd = d
			_n_i = i
			_n_lat = (x - tpx[i]) * tnx[i] + (y - tpy[i]) * tny[i]
			_n_w = tw[i]
			_n_nx = tnx[i]
			_n_ny = tny[i]
			_n_t = t


## The same on an open-ended branch: the window stops at its ends, and a point past either end
## is off it (_n_off: no road there, however close to the centreline's line).
func _nearest_branch(B: TrackPath, x: float, y: float, hint: int, win: int) -> void:
	var bd := INF
	# the arrays in locals (the same sums; a member lookup each time cost ~40% of the search, which
	# is most of a Network step)
	var bx := B.px
	var by := B.py
	var btx := B.tx
	var bty := B.ty
	var bl := B.len
	for i in range(maxi(0, hint - win), mini(B.N - 1, hint + win) + 1):
		var u := ((x - bx[i]) * btx[i] + (y - by[i]) * bty[i]) / bl[i]
		var t := clampf(u, 0.0, 1.0)
		var px := bx[i] + btx[i] * bl[i] * t
		var py := by[i] + bty[i] * bl[i] * t
		var d := (x - px) * (x - px) + (y - py) * (y - py)
		if d < bd:
			bd = d
			_n_i = i
			_n_lat = (x - bx[i]) * B.nx[i] + (y - by[i]) * B.ny[i]
			_n_w = B.w[i]
			_n_nx = B.nx[i]
			_n_ny = B.ny[i]
			_n_t = t
			_n_off = (i == 0 and u < 0.0) or (i == B.N - 1 and u > 1.0)
			_n_tx = btx[i]
			_n_ty = bty[i]
			_n_over = (u - 1.0) * bl[i] if i == B.N - 1 else (-u * bl[i] if i == 0 else -INF)


## Nearest centreline point on a path (0 the main road, k + 1 branch k; on the Network: road path),
## into the _n_ fields.
func _nearest_on(path: int, x: float, y: float, hint: int, win: int) -> void:
	if kind == "network":
		_nearest_branch(roads[path], x, y, hint, win)
	elif path == 0:
		_nearest(x, y, hint, win)
	else:
		_nearest_branch(branches[path - 1], x, y, hint, win)


## How deep inside its road the last nearest point is, with radius r (negative inside; INF off a branch's end).
func _depth(r: float) -> float:
	return INF if _n_off else absf(_n_lat) + r - _n_w / 2.0


## The same on the Network, for the last nearest point on road `path`: a closed road end (a junction
## holds it: a highway's dead end inside its turnaround's zone) is a wall across the road, as deep as
## the circle is past the end plus r; an open end has none (INF: past it you're off the roads).
## Treating a closed end as INF too (no road here) made the junction's other road win however far off
## it was: past a highway's end, its turnaround's centreline is ~300 m to the side, 210 m of "wall"
## and a 1.3e9 N kick in one step, the binder torn (Luke's speeds jumping to 10,000-63,000 km/h at
## mile ~0 and ~346). Elsewhere it is _depth.
func _deep(path: int, r: float) -> float:
	if kind != "network":
		return _depth(r)
	var R: TrackPath = roads[path]
	var side := absf(_n_lat) + r - _n_w / 2.0
	if not ((_n_i == R.N - 1 and not R.open1) or (_n_i == 0 and not R.open0)):
		return INF if _n_off else side
	return maxf(side, _n_over + r)


## ... and whether that wall is the end's (1 the far end, -1 the first; 0 the sides)
func _end_cap(path: int, r: float) -> int:
	if kind != "network":
		return 0
	var R: TrackPath = roads[path]
	if not ((_n_i == R.N - 1 and not R.open1) or (_n_i == 0 and not R.open0)) or not (_n_over + r > absf(_n_lat) + r - _n_w / 2.0):
		return 0
	return 1 if _n_i == R.N - 1 else -1


## A signed sample gap round the main loop.
func _cyc(d: int) -> int:
	if float(d) > N / 2.0:
		return d - N
	if float(d) < -N / 2.0:
		return d + N
	return d


## The other road at a junction, Vector2i(path, hint there), or x = -1 for none. A body on the
## main road sees a branch within jz samples of its split, and only once its craft has passed the
## gate; a body on a branch sees the main road within jz samples of either end.
func _junction_alt(b: Body) -> Vector2i:
	for k in branches.size():
		var B: TrackPath = branches[k]
		if b.path == 0:
			var d := _cyc(b.hint - B.from_i)
			if gate[k] == true and absi(d) <= B.jz:
				return Vector2i(k + 1, clampi(d, 0, B.N - 1))
		elif b.path == k + 1:
			if b.hint < B.jz:
				return Vector2i(0, (B.from_i + b.hint) % N)
			if b.hint > B.N - 1 - B.jz:
				return Vector2i(0, posmod(B.join_i - (B.N - 1 - b.hint), N))
	return Vector2i(-1, 0)


## The Network's other roads at a body's junctions, [Vector2i(path, hint there), ...]: every
## junction whose zone on the body's road holds its hint, mapped linearly onto the other road's zone.
func _net_alts(b: Body) -> Array:
	var out: Array = []
	for k in roads[b.path].jx:
		var J: Array = junctions[k]
		var f0: int
		var f1: int
		var t0: int
		var t1: int
		var q: int
		if int(J[0]) == b.path and b.hint >= int(J[1]) and b.hint <= int(J[2]):
			f0 = J[1]
			f1 = J[2]
			t0 = J[4]
			t1 = J[5]
			q = J[3]
		elif int(J[3]) == b.path and b.hint >= int(J[4]) and b.hint <= int(J[5]):
			f0 = J[4]
			f1 = J[5]
			t0 = J[1]
			t1 = J[2]
			q = J[0]
		else:
			continue
		var u := float(b.hint - f0) / float(f1 - f0) if f1 > f0 else 0.0
		var m := t0 + u * (t1 - t0) if int(J[6]) > 0 else t1 - u * (t1 - t0)
		out.append(Vector2i(q, int(round(m))))
	return out


## The gates: a branch joins a craft's roads only if the craft reached its split's zone at or below
## sfEngageV (and the job opened it). Arrive faster and it stays shut for that pass, so the main
## wall holds. Decided once a pass, on the pod's speed as the first body comes into the zone;
## cleared once no body is in the zone or on the branch.
func _update_gates() -> void:
	for k in branches.size():
		var B: TrackPath = branches[k]
		var busy := false
		for b: Body in bodies:
			if b.path == k + 1 or (b.path == 0 and absi(_cyc(b.hint - B.from_i)) <= B.jz):
				busy = true
		if not busy:
			gate[k] = null
		elif gate[k] == null:
			gate[k] = B.open and sqrt(pod.vx * pod.vx + pod.vy * pod.vy) <= P.sfEngageV


## For the view: a branch road's roll at (fractional) sample i, radians: the corkscrews turn it
## over (0 -> 180 deg) and back, the rate easing up and down over CORK_EASE of each so it peaks at
## 1 / (1 - CORK_EASE) of the mean (~86 deg/s at 1,200 mph); 0 on the main road.
func roll_at(path: int, i: float) -> float:
	if path <= 0:
		return 0.0
	var B: TrackPath = branches[path - 1]
	var deg := 0.0
	for r in B.roll:
		if i >= r[1]:
			deg = r[3]
		elif i > r[0]:
			deg = lerpf(r[2], r[3], cork((i - r[0]) / float(r[1] - r[0])))
			break
		else:
			break
	return deg_to_rad(deg)


## For the view: a branch road's centreline height at (fractional) sample i. A road stood on edge
## is its width tall, so as a corkscrew turns it the centre climbs with the sine of the turn to the
## canopy's height (half the width and a bit: the low edge never meets the ground) by the time
## it's on edge, and holds there, turned over; back down the same way. 0 on the main road.
func branch_height(path: int, i: float) -> float:
	if path <= 0:
		return 0.0
	var r := roll_at(path, i)
	var h: float = branches[path - 1].height
	return h * sin(r) if r < PI / 2.0 else h


## The corkscrew's share of its turn at u (0..1): its rate ramps up over CORK_EASE, holds, ramps down.
static func cork(u: float) -> float:
	var a := CORK_EASE
	if u < a:
		return u * u / (2.0 * a) / (1.0 - a)
	if u > 1.0 - a:
		return 1.0 - (1.0 - u) * (1.0 - u) / (2.0 * a) / (1.0 - a)
	return (u - a / 2.0) / (1.0 - a)


func _apply_at(b: Body, fx: float, fy: float, px: float, py: float) -> void:
	b.fx += fx
	b.fy += fy
	b.t += (px - b.x) * fy - (py - b.y) * fx


func _point_vel(b: Body, px: float, py: float) -> void:
	_pvx = b.vx - b.w * (py - b.y)
	_pvy = b.vy + b.w * (px - b.x)


## For the view (not the physics): the banked GP's surface at (x, y), near sample `hint`:
## Vector2(height above the desert, bank radians + = tilted down to the left). Corners pivot on
## their inside edge, so it stays at ground level and the outside climbs (96 m at 30 deg: 55 m);
## past the outside wall a 45-degree berm runs back down. (0, 0) everywhere else.
## On a branch (path k + 1): its centreline's height (branch_height) and no bank (the turn over is
## roll_at's).
func surface_at(x: float, y: float, hint: int, path := 0) -> Vector2:
	if kind == "network":   # the deck's height (the flyovers), and the edges' ramps (net_edge: banked
		# toward the middle, + = down to the left as the GP's); the ramp from the hint's own sample
		# (no search: its width and frame are the same for metres around)
		var e := Vector2.ZERO
		if path >= 0 and path < roads.size():
			var R: TrackPath = roads[path]
			var ih := clampi(hint, 0, R.N - 1)
			var lat := (x - R.px[ih]) * R.nx[ih] + (y - R.py[ih]) * R.ny[ih]
			e = net_edge(R.w[ih], lat)
			e.y *= -signf(lat)
		if not _deck_between(path, hint - 40, hint + 41):   # no flyover the search could reach: the ground,
			return e                                       # without the search (~35 us; the view asks ~20 times a frame)
		_nearest_on(path, x, y, hint, 40)
		return Vector2(net_height(path, _n_i + _n_t) + e.x, e.y)
	if path > 0:
		_nearest_on(path, x, y, hint, 40)
		return Vector2(branch_height(path, _n_i + _n_t), 0.0)
	if tb.is_empty():
		return Vector2.ZERO
	_nearest(x, y, hint, 40)
	var bk: float = lerpf(tb[_n_i], tb[(_n_i + 1) % N], _n_t)
	return Vector2(bank_height(_n_w / 2.0, _n_lat, bk), bk)


## Height of the banked surface `off` metres left of the centreline, half-width hw, bank bk.
static func bank_height(hw: float, off: float, bk: float) -> float:
	var t := tan(bk)
	var base := hw * absf(t) - clampf(off, -hw, hw) * t
	return maxf(0.0, base - maxf(0.0, absf(off) - hw))   # the berm outside: down at 45 deg


## Range: back to the start line, run cleared (the Y button).
## A fresh start (the player's restart), mirroring sim-core.js: whole engines and pod, full
## battery, cool engines; the range goes back to its start line, a circuit to its grid with the
## lap count reset. Crashes still respawn through respawn(), keeping the damage.
func restart() -> void:
	crash_t = 0.0
	finished = false
	run_active = false
	run_start = -1.0
	result = {}
	for e in [eL, eR]:
		e.health = 1.0
		e.heat = 0.3 if P.limits else 0.0
	pod.health = 1.0
	battery = 1.0
	if kind == "range":
		pod.x = 30.0
		pod.y = 0.0
		respawn()
	elif kind == "network":
		respawn()
	else:
		lap = 0
		lap_start = -1.0
		visited = {0: true}
		checkpoint = 0
		respawn(0)
	if not job.is_empty():
		job = _new_job()   # the job starts over (its clock on the next first move)


func respawn(ci: int = -1, at_idx: int = -1) -> void:   # at_idx: a debug start at that track sample (views only)
	# The Network: at a city's terminal (the last city reached unless ci names one), facing up its road
	if kind == "network":
		var c: Dictionary = cities[ci if ci >= 0 else int(net.from)]
		respawn_on(c.road, c.i, 1)
		return
	# Circuit: back at a checkpoint. Range: 30 m behind where the pod is, facing +x.
	var idx := 0
	var ax: float
	var ay: float
	var atx := 1.0
	var aty := 0.0
	var anx := 0.0
	var any := 1.0
	if kind == "range":
		ax = maxf(0.0, pod.x - 30.0)
		ay = pod.y
	else:
		var c := checkpoint if ci < 0 else ci
		idx = int(round(float(c) * N / checkpoints)) % N
		if at_idx >= 0:
			idx = at_idx % N
		ax = tpx[idx]
		ay = tpy[idx]
		atx = ttx[idx]
		aty = tty[idx]
		anx = tnx[idx]
		any = tny[idx]
	_place(ax, ay, atx, aty, anx, any, idx, 0)


## The Network: on road `road` at sample i, facing up it (dir 1) or down it (-1).
func respawn_on(road: int, i: int, dir := 1) -> void:
	var B: TrackPath = roads[road]
	var d := -1.0 if dir < 0 else 1.0
	_place(B.px[i], B.py[i], B.tx[i] * d, B.ty[i] * d, B.nx[i] * d, B.ny[i] * d, i, road)
	if not net.is_empty():
		net.t0 = -1.0
		net.prev = Vector2i(-1, -1)


func _place(ax: float, ay: float, atx: float, aty: float, anx: float, any: float, idx: int, path: int) -> void:
	# engines placed so each cable is exactly at length: a stretched spawn makes the stiff
	# cables yank the pod forward on the first step
	var lat: float = P.engineGap / 2.0 - P.podAnchorW * P.podWidth / 2.0
	var ahead: float = sqrt(P.cableLen * P.cableLen - lat * lat) + P.podLen / 2.0 + P.engineLen / 2.0
	var th := atan2(aty, atx)
	for pair in [[eL, 1.0], [eR, -1.0], [pod, 0.0]]:
		var b: Body = pair[0]
		var side: float = pair[1]
		var fwd := 0.0 if side == 0.0 else ahead
		b.x = ax + atx * fwd + anx * side * P.engineGap / 2.0
		b.y = ay + aty * fwd + any * side * P.engineGap / 2.0
		b.vx = 0.0
		b.vy = 0.0
		b.w = 0.0
		b.th = th
		b.hint = idx
		b.path = path
		b.contact = [false, false]
		b.z = (net_height(path, float(idx)) if kind == "network" else ground(b.x, b.y)) + P.rideH
		b.vz = 0.0
		b.grip = 1.0
		b.off_road = false
		b.lock = false
	on_ground = false
	for e: Body in [eL, eR]:
		e.heat = minf(e.heat, 0.5) if P.limits else 0.0
		e.flameout = false
		e.sputter = 1.0
		e.sputter_t = 0.0
	if pod.health <= 0.0:
		pod.health = 1.0
	binder_broken = false
	_tow_u = -1.0
	crash_t = 0.0
	progress_i = idx
	gate = []
	gate.resize(branches.size())   # all null: no pass in progress
	pod_path = 0


## At a junction the two roads are one (a union): a body takes the road it's deeper inside, when
## it's off its own or the other is 10 m deeper, and a wall is wherever it's off both.
func _collide_walls(b: Body, circles: Array, dt: float) -> void:
	# (the Network searches 16 samples, not 40: a body moves under a sample a step, and the
	# junctions' linear maps are within 10 samples of the true nearest: the search is ~60% of a step)
	var win := 16 if kind == "network" else 40
	_nearest_on(b.path, b.x, b.y, b.hint, win)
	b.hint = _n_i
	# the other roads here: one at most off a course's main road, any number on the Network (the
	# body takes the deepest, under the same rule)
	var alts: Array = []
	if kind == "network":
		alts = _net_alts(b)
	elif not branches.is_empty():
		var a1 := _junction_alt(b)
		if a1.x >= 0:
			alts = [a1]
	var others: Array = []   # Vector2i(path, hint)
	if not alts.is_empty():
		var d_own := _deep(b.path, 0.0)
		var own_i := _n_i
		var mi: Array = []
		var md: Array = []
		for a: Vector2i in alts:
			_nearest_on(a.x, b.x, b.y, a.y, win)
			mi.append(_n_i)
			md.append(_deep(a.x, 0.0))
		var bi := 0
		for k in range(1, md.size()):
			if md[k] < md[bi]:
				bi = k
		var d_alt: float = md[bi]
		if d_alt < d_own and (d_own > 0.0 or d_alt < d_own - 10.0):
			others.append(Vector2i(b.path, own_i))
			b.path = alts[bi].x
			b.hint = mi[bi]
			for k in alts.size():
				if k != bi:
					others.append(Vector2i(alts[k].x, mi[k]))
		else:
			for k in alts.size():
				others.append(Vector2i(alts[k].x, mi[k]))
	if kind == "network":   # off an open end: off the roads (a lip, a highway's end)
		var Rw: TrackPath = roads[b.path]
		_nearest_on(b.path, b.x, b.y, b.hint, 2)
		if _n_off and ((_n_i == 0 and Rw.open0) or (_n_i == Rw.N - 1 and Rw.open1)):
			_go_free(b)
			return
	for ci in circles.size():
		var cx: float = circles[ci][0]
		var cy: float = circles[ci][1]
		var r: float = circles[ci][2]
		_nearest_on(b.path, cx, cy, b.hint, 12)
		var pen := _deep(b.path, r)
		var lat := _n_lat
		var wnx := _n_nx
		var wny := _n_ny
		var cap := _end_cap(b.path, r)   # a closed end pushes back along the road
		var ctx := _n_tx
		var cty := _n_ty
		for o: Vector2i in others:
			_nearest_on(o.x, cx, cy, o.y, 12)
			var pm := _deep(o.x, r)
			if pm < pen:
				pen = pm
				lat = _n_lat
				wnx = _n_nx
				wny = _n_ny
				cap = _end_cap(o.x, r)
				ctx = _n_tx
				cty = _n_ty
		if pen <= 0.0 or pen == INF:   # (INF: past an open end, no wall)
			b.contact[ci] = false
			continue
		var sgn := -1.0 if lat > 0.0 else 1.0
		var nx: float = -cap * ctx if cap != 0 else wnx * sgn
		var ny: float = -cap * cty if cap != 0 else wny * sgn
		_point_vel(b, cx, cy)
		var vx := _pvx
		var vy := _pvy
		var vn := vx * nx + vy * ny
		if not b.contact[ci]:
			var dmg: float = P.damagePerMs * maxf(0.0, -vn - P.wallDmgMin)
			if P.damage:   # off by default (Luke): a hit still registers (and buzzes), it just costs nothing
				if b == pod:
					pod.health -= dmg
				else:
					b.health = maxf(0.0, b.health - dmg)
			var who := "pod" if b == pod else ("L" if b == eL else "R")
			if dmg > 0.05:
				events.append({"type": "hit", "who": who, "dmg": dmg})
			else:
				events.append({"type": "scrape", "who": who})   # contact without (much) damage
			b.contact[ci] = true
		var fn: float = P.wallK * pen - (P.wallC * vn if vn < 0.0 else 0.0)
		var tx := -ny
		var ty := nx
		var vt := vx * tx + vy * ty
		var ft: float = -signf(vt) * minf(P.wallMu * fn, absf(vt) * b.m / dt)
		_apply_at(b, fn * nx + ft * tx, fn * ny + ft * ty, cx, cy)


## Traffic's forcefields, mirroring sim-core.js collideObstacles: a body's circle inside an obstacle
## is pushed straight out (a spring and a damper on the closing speed, no friction, no damage);
## touching one starts a "bump" (once per contact); closing faster than smashV is the catastrophic
## hit: a "smash" and a crash.
func _collide_obstacles(b: Body, circles: Array) -> void:
	var inside := {}
	for o in obstacles:
		var ox: float = o.x
		var oy: float = o.y
		var orr: float = o.r
		for c in circles:
			var cx: float = c[0]
			var cy: float = c[1]
			var r: float = c[2]
			var dx: float = cx - ox
			var dy: float = cy - oy
			var reach: float = r + orr + 1.0
			if dx * dx + dy * dy > reach * reach:   # well clear (the test below skips it too), without the
				continue                             # sqrt: a city's ~100 obstacles x 3 bodies x 4 steps a frame
			var d := sqrt(dx * dx + dy * dy)
			var pen: float = r + orr - d
			if pen <= 0.0 or d < 1e-6:
				continue
			var nx := dx / d
			var ny := dy / d
			_point_vel(b, cx, cy)
			var vn: float = (_pvx - o.vx) * nx + (_pvy - o.vy) * ny
			if not b.touch.has(o.id) and not inside.has(o.id):
				if -vn > P.smashV and crash_t <= 0.0:
					events.append({"type": "smash", "id": o.id, "v": -vn})
					crash_t = 1.6
				else:
					events.append({"type": "bump", "who": "pod" if b == pod else ("L" if b == eL else "R"), "id": o.id, "v": maxf(0.0, -vn)})
			inside[o.id] = true
			var fn: float = P.fieldK * pen - (P.fieldC * vn if vn < 0.0 else 0.0)
			_apply_at(b, fn * nx, fn * ny, cx, cy)
	b.touch = inside


func _engine_circles(e: Body) -> Array:
	var c := cos(e.th)
	var s := sin(e.th)
	var o: float = P.engineLen / 2.0 - 1.2
	return [[e.x + c * o, e.y + s * o, 1.2], [e.x - c * o, e.y - s * o, 1.2]]


func _body_push(a: Body, ca: Array, b: Body, cb: Array) -> void:
	for p in ca:
		for q in cb:
			var dx: float = q[0] - p[0]
			var dy: float = q[1] - p[1]
			var d := sqrt(dx * dx + dy * dy)
			var pen: float = p[2] + q[2] - d
			if pen <= 0.0 or d < 1e-6:
				continue
			var nx := dx / d
			var ny := dy / d
			var f := 1.0e6 * pen
			_apply_at(b, f * nx, f * ny, q[0], q[1])
			_apply_at(a, -f * nx, -f * ny, p[0], p[1])


## One fixed step. input keys: thrL, thrR, brkL, brkR (0..1), repair, reignite (bool).
func step(inp: Dictionary, dt: float) -> void:
	var L := eL
	var R := eR
	var Pd := pod
	for o in obstacles:
		o.x += o.vx * dt
		o.y += o.vy * dt
	if crash_t > 0.0:
		crash_t -= dt
		if crash_t <= 0.0:
			if finished:   # back to the start line
				pod.x = 30.0
				pod.y = 0.0
				finished = false
				result = {}
			respawn()
		return
	var hask: String = inp.get("handling", "")
	if hask == "speed" or hask == "starfighter":
		hwant = hask
	if pod.path > 0 and kind != "network":
		hwant = "starfighter"   # a shade line is a STARFIGHTER line (its corkscrews are paced for it)
	var htgt := 0.0
	if hwant == "starfighter":
		htgt = 1.0 if hblend > 0.0 or sqrt(pod.vx * pod.vx + pod.vy * pod.vy) <= P.sfEngageV else 0.0
	if hblend != htgt:
		hblend = minf(htgt, hblend + dt / P.modeBlendT) if htgt > hblend else maxf(htgt, hblend - dt / P.modeBlendT)
		for k in _hk:
			P[k] = _h1[k] if hblend == 1.0 else (_h0[k] if hblend == 0.0 else _h0[k] + (_h1[k] - _h0[k]) * hblend)
		P.handling = "starfighter" if hblend >= 0.5 else "speed"
		if hblend == htgt:
			events.append({"type": "handling", "mode": P.handling})
	# Vertical ties: the binder holds both engines at one height and the tow bar lifts the
	# pod toward their mean, so a one-sided ramp hit lifts the whole craft instead of
	# flinging one engine skyward. Exactly zero when heights match (flat ground).
	var az := [0.0, 0.0, 0.0]
	if not binder_broken:
		var fz: float = P.binderKz * (R.z - L.z) + P.binderCz * (R.vz - L.vz)
		az[0] += fz / L.m
		az[1] -= fz / R.m
	var ftz: float = P.towKz * ((L.z + R.z) / 2.0 - Pd.z) + P.towCz * ((L.vz + R.vz) / 2.0 - Pd.vz)
	az[2] += ftz / Pd.m
	az[0] -= ftz / 2.0 / L.m
	az[1] -= ftz / 2.0 / R.m
	for k in 3:
		var b: Body = bodies[k]
		b.fx = 0.0
		b.fy = 0.0
		b.t = 0.0
		_hover(b, dt, az[k])
	time += dt
	var repair: bool = inp.get("repair", false)
	var reignite: bool = inp.get("reignite", false)
	# the burner: an explicit inp.burner (the headset's trigger throttles light it from the left stick,
	# so the levers stay under the gate and still throttle and steer on it), else both levers past
	# the gate (the keyboard, a gamepad, the replays); mirroring sim-core.js
	var lit: bool = bool(inp.burner) if inp.has("burner") else (inp.thrL >= P.gate and inp.thrR >= P.gate)
	var in_gate: bool = lit and not repair
	var ramjet := armed and in_gate
	var burner := not ramjet and in_gate and battery > 0.0
	mode = "ramjet" if ramjet else ("burner" if burner else "normal")
	if burner and P.limits:
		battery = maxf(0.0, battery - P.batteryDrain * dt)
	elif not in_gate:
		battery = minf(1.0, battery + P.batteryCharge * dt)
	var speed := sqrt(Pd.vx * Pd.vx + Pd.vy * Pd.vy)

	var gm: float = float(inp.get("thrMul", 1.0))   # the gearbox's pull (its ratio, at its revs; 1 without one)
	for side in [[L, inp.thrL, inp.brkL], [R, inp.thrR, inp.brkR]]:
		var e: Body = side[0]
		var thr: float = side[1]
		var brk: float = side[2]
		var c := cos(e.th)
		var s := sin(e.th)
		var gain := 0.0
		if not e.flameout and P.limits:
			gain = maxf(0.0, thr - 0.6) * P.heatThrottle + (P.heatBurner if burner else 0.0) + (P.heatRamjet if ramjet else 0.0)
		var cool: float = P.coolBase + P.coolSpeed * minf(1.5, speed / 200.0) + (0.15 if e.flameout else 0.0)
		e.heat = clampf(e.heat + (gain - cool) * dt, 0.0, 1.25)
		if e.heat >= 1.0 and not e.flameout:
			e.flameout = true
			events.append({"type": "flameout", "who": "L" if e == L else "R"})
		if e.flameout and reignite and e.heat < 0.6:
			e.flameout = false
		if repair:
			e.health = minf(1.0, e.health + P.repairRate * dt)
		e.sputter_t -= dt
		if e.sputter_t <= 0.0:
			e.sputter_t = 0.15
			e.sputter = 0.3 if rand() < (0.5 - e.health) * 1.2 else 1.0
		var lever: float = minf(thr, P.gate) / P.gate
		if repair:
			lever = minf(lever, 0.6)
		var mult: float = P.ramjetMult if ramjet else (P.burnerMult if burner else 1.0)
		var thrust: float = 0.0 if e.flameout else P.thrustMax * lever * mult * (0.45 + 0.55 * e.health) * e.sputter
		e.thrust = thrust / P.thrustMax
		e.fx += thrust * P.forceScale * gm * c
		e.fy += thrust * P.forceScale * gm * s
		# Air brake = quadratic drag plus a linear term, so the flaps still bite at low speed.
		var v := sqrt(e.vx * e.vx + e.vy * e.vy)
		# A constant term keeps the brakes biting across a 100x speed range (smoothed below 2 m/s).
		e.front = brk * smoothstep(P.frontBrakeV0, P.frontBrakeV1, v) if P.frontBrakeCd > 0.0 else 0.0
		var cd: float = (P.engineCd + P.brakeCd * brk + P.frontBrakeCd * e.front) * P.forceScale
		var bl: float = (P.brakeLin * brk + P.brakeConst * brk / maxf(v, 2.0)) * P.forceScale
		e.fx -= cd * v * e.vx + bl * e.vx
		e.fy -= cd * v * e.vy + bl * e.vy
		var fxp: float = e.x - c * P.finOffset
		var fyp: float = e.y - s * P.finOffset
		_point_vel(e, fxp, fyp)
		var vlat := -s * _pvx + c * _pvy
		var cap: float = e.m * P.gripCapG * G * (1.0 - 0.45 * brk)
		var flat := clampf(-e.m * P.engineGrip * vlat, -cap, cap) * e.grip
		_apply_at(e, -s * flat, c * flat, fxp, fyp)
		e.t -= P.yawDamp * e.w
		# Aero fins: restoring torque toward the direction of travel, growing with speed^2.
		if v > 1.0:
			e.t -= P.finK * v * v * sin(wrap_angle(e.th - atan2(e.vy, e.vx)))

	if not binder_broken:
		var dx := R.x - L.x
		var dy := R.y - L.y
		var d := sqrt(dx * dx + dy * dy)
		var ax := dx / d
		var ay := dy / d
		var dvx := R.vx - L.vx
		var dvy := R.vy - L.vy
		var stretch: float = d - P.engineGap
		var f: float = P.binderK * stretch + P.binderC * (dvx * ax + dvy * ay)
		R.fx -= f * ax
		R.fy -= f * ay
		L.fx += f * ax
		L.fy += f * ay
		# Forward is +90 deg from the L->R axis. Align both engines to it and feed the
		# reaction back into the pair as a force couple so angular momentum holds.
		var fwx := -ay
		var fwy := ax
		var thf := atan2(fwy, fwx)
		var wf := (ax * dvy - ay * dvx) / d
		var tq_sum := 0.0
		for e: Body in [L, R]:
			var tq: float = -P.alignK * wrap_angle(e.th - thf) - P.alignC * (e.w - wf)
			e.t += tq
			tq_sum += tq
		var sc := -tq_sum / d
		R.fx += sc * fwx
		R.fy += sc * fwy
		L.fx -= sc * fwx
		L.fy -= sc * fwy
		pair_th = thf
		binder_stretch = stretch
		if absf(stretch) > P.binderBreak:
			binder_broken = true
			events.append({"type": "binder"})
			crash_t = 1.6

	var pc := cos(Pd.th)
	var ps := sin(Pd.th)
	for k in 2:
		var e: Body = L if k == 0 else R
		var side := 1.0 if k == 0 else -1.0
		var ec := cos(e.th)
		var es := sin(e.th)
		var ex: float = e.x - ec * P.engineLen / 2.0
		var ey: float = e.y - es * P.engineLen / 2.0
		var aw: float = side * P.podAnchorW * P.podWidth / 2.0
		var px: float = Pd.x + pc * P.podLen / 2.0 - ps * aw
		var py: float = Pd.y + ps * P.podLen / 2.0 + pc * aw
		var dx := ex - px
		var dy := ey - py
		var d := sqrt(dx * dx + dy * dy)
		cables[k] = {"ex": ex, "ey": ey, "px": px, "py": py, "f": 0.0, "slack": d < P.cableLen}
		if d <= P.cableLen:
			continue
		var nx := dx / d
		var ny := dy / d
		_point_vel(e, ex, ey)
		var evx := _pvx
		var evy := _pvy
		_point_vel(Pd, px, py)
		var f: float = P.cableK * (d - P.cableLen) + P.cableC * ((evx - _pvx) * nx + (evy - _pvy) * ny)
		if f <= 0.0:
			continue
		cables[k].f = f
		_apply_at(Pd, f * nx, f * ny, px, py)
		# Bridle: most tension reaches the pair through the binder so pod sway
		# yanks the craft without steering it (see spec section 3).
		var own: float = P.cableCouple + (1.0 - P.cableCouple) / 2.0
		var other: Body = R if k == 0 else L
		e.fx -= f * nx * own
		e.fy -= f * ny * own
		other.fx -= f * nx * (1.0 - own)
		other.fy -= f * ny * (1.0 - own)

	var pb := minf(inp.brkL, inp.brkR)
	var pv := sqrt(Pd.vx * Pd.vx + Pd.vy * Pd.vy)
	var pcd: float = (P.podCd + 0.5 * P.brakeCd * pb) * P.forceScale
	var pbl: float = 0.5 * (P.brakeLin * pb + P.brakeConst * pb / maxf(pv, 2.0)) * P.forceScale
	Pd.fx -= pcd * pv * Pd.vx + pbl * Pd.vx
	Pd.fy -= pcd * pv * Pd.vy + pbl * Pd.vy
	var qx := Pd.x - pc * 1.2
	var qy := Pd.y - ps * 1.2
	_point_vel(Pd, qx, qy)
	var pcap: float = Pd.m * P.podCapG * G
	var plat := clampf(-Pd.m * P.podGrip * (-ps * _pvx + pc * _pvy), -pcap, pcap) * Pd.grip
	_apply_at(Pd, -ps * plat, pc * plat, qx, qy)
	# Tow bar: hold the pod on the engines' centreline (lateral spring-damper toward the
	# point straight behind the pair) and align its heading to theirs; reaction to the engines.
	if not binder_broken:
		var pf := cos(pair_th)
		var ps2 := sin(pair_th)
		var lx := -ps2
		var ly := pf
		var back: float = P.engineLen / 2.0 + P.cableLen + P.podLen / 2.0
		var mxp := (L.x + R.x) / 2.0
		var myp := (L.y + R.y) / 2.0
		var wpair := (L.w + R.w) / 2.0
		var tx := mxp - pf * back
		var ty := myp - ps2 * back
		var tvx := (L.vx + R.vx) / 2.0 + wpair * ps2 * back
		var tvy := (L.vy + R.vy) / 2.0 - wpair * pf * back
		var te := (Pd.x - tx) * lx + (Pd.y - ty) * ly
		var tev := (Pd.vx - tvx) * lx + (Pd.vy - tvy) * ly
		var ft: float = -P.towK * te - P.towC * tev
		Pd.fx += ft * lx
		Pd.fy += ft * ly
		L.fx -= ft * lx / 2.0
		L.fy -= ft * ly / 2.0
		R.fx -= ft * lx / 2.0
		R.fy -= ft * ly / 2.0
		# Stand-off: the pod never closes on the engines past its taut-cable spot. Brake hard (or
		# spin the pair) and the cables go slack: without this the pod flew on into the engines
		# and knocked them about (Luke: "the pod flies forward and throws the engines off
		# balance"). Compression only (the cables already pull), along the pair's axis through
		# its centre, equal and opposite on the engines: it can't twist them or make energy.
		# (its spot: where the diagonal cables are just taut, as respawn() lays them out, plus a
		# little slack, so it only ever meets a real overrun and never fights the cables)
		var lat_c: float = P.engineGap / 2.0 - P.podAnchorW * P.podWidth / 2.0
		var rest: float = sqrt(P.cableLen * P.cableLen - lat_c * lat_c) + P.podLen / 2.0 + P.engineLen / 2.0
		var el: float = (Pd.x - tx) * pf + (Pd.y - ty) * ps2 - (back - rest) - P.towLongSlack
		if el > 0.0 and P.towLongK > 0.0:
			var elv := (Pd.vx - (L.vx + R.vx) / 2.0) * pf + (Pd.vy - (L.vy + R.vy) / 2.0) * ps2
			var fl: float = minf(0.0, -P.towLongK * el - P.towLongC * elv)
			Pd.fx += fl * pf
			Pd.fy += fl * ps2
			L.fx -= fl * pf / 2.0
			L.fy -= fl * ps2 / 2.0
			R.fx -= fl * pf / 2.0
			R.fy -= fl * ps2 / 2.0
		var pod_tw: float = P.podAlignK * wrap_angle(Pd.th - pair_th) + P.podYawDamp * (Pd.w - wpair)
		Pd.t -= pod_tw
		# Energy audit. The tow bar is one-way on purpose (the pod follows the engines without
		# yawing them back: that trailer feedback made the pair sway), so its pull and the pod's
		# twist have no equal and opposite, and that let it create energy: the pod whirled round a
		# pivoting pair, or swung by a spinning one after wall hits, gained speed from nothing and
		# the craft pinballed (pod 159 -> 495 km/h coasting with no thrust). So each substep,
		# whatever power these forces put in beyond what their springs gave up is taken back out.
		# Normal flight is untouched (yaw response, coast-down and the GP lap identical), and it
		# can never add energy (tests/test_energy.gd).
		if P.towAudit:
			var mvx := (L.vx + R.vx) / 2.0
			var mvy := (L.vy + R.vy) / 2.0
			var p_in: float = ft * ((Pd.vx - mvx) * lx + (Pd.vy - mvy) * ly) - pod_tw * Pd.w
			var dth := wrap_angle(Pd.th - pair_th)
			var u: float = 0.5 * P.towK * te * te + 0.5 * P.podAlignK * dth * dth
			if _tow_u >= 0.0:
				var created: float = p_in + (u - _tow_u) / dt
				if created > 0.0:
					# Where it comes out depends on where the craft's energy is. Travelling (nearly
					# all of it is speed down the track), it comes out of the speed, gently (never
					# past towAuditG); taking it out of the swing there would deaden the steering,
					# since every yaw step swings the pod. Whirling (much of it is swing and spin
					# about the centre of mass: the pod whirled round a pivoting pair, or pinballing
					# off walls), it comes out of the swing and spin, where it was made.
					var msum: float = Pd.m + L.m + R.m
					var cvx: float = (Pd.m * Pd.vx + L.m * L.vx + R.m * R.vx) / msum
					var cvy: float = (Pd.m * Pd.vy + L.m * L.vy + R.m * R.vy) / msum
					var ke := 0.0    # speed
					var rot := 0.0   # spin
					var kin := 0.0   # swing and spin about the centre of mass
					for b: Body in [Pd, L, R]:
						ke += 0.5 * b.m * (b.vx * b.vx + b.vy * b.vy)
						rot += 0.5 * b.inertia * b.w * b.w
						kin += 0.5 * b.m * ((b.vx - cvx) * (b.vx - cvx) + (b.vy - cvy) * (b.vy - cvy))
					kin += rot
					var c_int: float = created * smoothstep(P.towIntF0, P.towIntF1, kin / maxf(ke + rot, 1.0))
					var c_lin: float = created - c_int
					if c_int > 0.0 and kin > 1.0:
						var gi: float = minf(c_int / (2.0 * kin), P.towIntMax)
						for b: Body in [Pd, L, R]:
							b.fx -= gi * b.m * (b.vx - cvx)
							b.fy -= gi * b.m * (b.vy - cvy)
							b.t -= gi * b.inertia * b.w
					if c_lin > 0.0 and ke > 1.0:
						var vrms: float = sqrt(2.0 * ke / msum)
						var gam: float = minf(c_lin / (2.0 * ke), P.towAuditG * G / maxf(vrms, 1.0))
						for b: Body in [Pd, L, R]:
							b.fx -= gam * b.m * b.vx
							b.fy -= gam * b.m * b.vy
			_tow_u = u

	# Banked corners: the surface tilts toward the inside, so its push has a part toward the
	# corner's centre: gravity's (g tan bank) plus downforce's (bankDown v^2 sin bank).
	if course:
		for b: Body in bodies:
			var bk: float = tb[b.hint] if b.path == 0 else branches[b.path - 1].bank[b.hint]
			if bk == 0.0:
				continue
			var v2 := b.vx * b.vx + b.vy * b.vy
			var fb: float = P.bank * b.m * (G * tan(bk) + P.bankDown * v2 * sin(bk)) * b.grip
			b.fx += fb * (tnx[b.hint] if b.path == 0 else branches[b.path - 1].nx[b.hint])
			b.fy += fb * (tny[b.hint] if b.path == 0 else branches[b.path - 1].ny[b.hint])
	# The Network's edges: their ramp pushes you back toward the middle, as the GP's banking does
	# toward a corner's (mirroring sim-core.js)
	if kind == "network":
		for b: Body in bodies:
			if b.off_road:
				continue
			var RB: TrackPath = roads[b.path]
			var ib := b.hint
			var latb := (b.x - RB.px[ib]) * RB.nx[ib] + (b.y - RB.py[ib]) * RB.ny[ib]
			var bke := net_edge(RB.w[ib], latb).y
			if bke == 0.0:
				continue
			var v2e := b.vx * b.vx + b.vy * b.vy
			var fe: float = P.bank * b.m * (G * tan(bke) + P.bankDown * v2e * sin(bke)) * b.grip * (-1.0 if latb > 0.0 else 1.0)
			b.fx += fe * RB.nx[ib]
			b.fy += fe * RB.ny[ib]
	var cl := _engine_circles(L)
	var cr := _engine_circles(R)
	var cp := [[Pd.x, Pd.y, 1.6]]
	if not branches.is_empty():
		_update_gates()
	if kind == "network":
		for bc in [[L, cl], [R, cr], [Pd, cp]]:
			if bc[0].off_road:
				_free_contact(bc[0], bc[1], dt)
			else:
				_collide_walls(bc[0], bc[1], dt)
	elif kind == "circuit":
		_collide_walls(L, cl, dt)
		_collide_walls(R, cr, dt)
		_collide_walls(Pd, cp, dt)
	if not obstacles.is_empty():
		_collide_obstacles(L, cl)
		_collide_obstacles(R, cr)
		_collide_obstacles(Pd, cp)
	_body_push(L, cl, Pd, cp)
	_body_push(R, cr, Pd, cp)
	_body_push(L, cl, R, cr)

	for b: Body in bodies:
		# in the air (the Network, off the roads), the forces along its path act along it, mirroring
		# sim-core.js: thrust minus drag scales its climb as it scales its speed (only gravity bends the line)
		if kind == "network" and b.off_road:
			var vh := sqrt(b.vx * b.vx + b.vy * b.vy)
			if vh > 50.0:
				b.vz += (b.fx * b.vx + b.fy * b.vy) / (b.m * vh) * (b.vz / vh) * dt
		b.vx += b.fx / b.m * dt
		b.vy += b.fy / b.m * dt
		b.w += b.t / b.inertia * dt
		b.w *= 1.0 - 0.5 * dt
		b.x += b.vx * dt
		b.y += b.vy * dt
		b.th += b.w * dt
	if Pd.health <= 0.0 and crash_t <= 0.0:
		events.append({"type": "wreck"})
		crash_t = 1.6
		Pd.health = 0.0
	if kind == "network":
		_net_step(inp)
		return

	if kind == "range":
		# Sprint: the clock starts on the first lever input and stops when the pod sits still
		# inside the box. Overrunning by OVERRUN, or crashing mid-run, is a DNF back to the start.
		if not run_active and result.is_empty() and inp.thrL + inp.thrR > 0.02:
			run_active = true
			run_start = time
		if run_active:
			var in_box := absf(Pd.x - BOX_X) <= BOX_HALF and absf(Pd.y) <= BOX_HALF
			var end := {}
			if in_box and pv < STOPPED:
				var t := time - run_start
				end = {"type": "finish", "t": t, "err": sqrt((Pd.x - BOX_X) * (Pd.x - BOX_X) + Pd.y * Pd.y)}
				last_run = t
				best_run = t if best_run < 0.0 else minf(best_run, t)
			elif Pd.x > BOX_X + OVERRUN:
				end = {"type": "overrun"}
			elif crash_t > 0.0:
				end = {"type": "crash"}
			if not end.is_empty():
				run_active = false
				result = end
				events.append(end)
				if end.type != "finish":
					finished = true
					crash_t = maxf(crash_t, 1.6)
		return
	if kind != "circuit":
		return
	# Laps: count when the pod wraps past the start having visited every checkpoint. On the main
	# road only: on a branch the pod keeps its progress, and back on the main road it carries on
	# from that checkpoint (a shortcut visits none of the ones it skipped).
	if Pd.path != 0:
		pod_path = Pd.path
	else:
		var prev := progress_i
		var cur := Pd.hint
		var cps := checkpoints
		var cpi := int(floor(float(cur) * cps / N))
		if pod_path != 0:
			pod_path = 0
			checkpoint = cpi
		if cpi != checkpoint and posmod(cpi - checkpoint + cps, cps) == 1:
			checkpoint = cpi
			visited[cpi] = true
		if lap_start < 0.0 and pv > 2.0:
			lap_start = time
		if prev > N * 0.9 and cur < N * 0.1 and visited.size() >= cps - 1 and lap_start >= 0.0:
			last_lap = time - lap_start
			best_lap = last_lap if best_lap < 0.0 else minf(best_lap, last_lap)
			lap += 1
			lap_start = time
			visited = {0: true}
			events.append({"type": "lap", "t": last_lap})
		progress_i = cur
	if not job.is_empty():
		_job_step(inp, dt, pv)


func _new_job() -> Dictionary:
	# exposed: out in the open on the way home; safe: back under cover since (the margin taken then)
	return {"stage": "out", "t": 0.0, "t0": null, "held": 0.0, "route": "open", "margin": 0.0, "reason": "", "prev_d": null,
		"exposed": false, "safe": false}


## For the view: where the job's countdown counts to now, {x, y}: the lake town's pad on the way
## out; from the drop on, the deadline home: the start town's receiving ramp's entrance on the
## loop, or the canopy's start once on the shade line short of it. Empty once back under cover
## (safe) or the job's over.
func job_deadline() -> Dictionary:
	if job.is_empty() or job.stage == "out":
		return {"x": tpx[pad], "y": tpy[pad]} if pad >= 0 else {}
	if job.safe or job.stage == "done" or job.stage == "failed":
		return {}
	if pod.path > 0:
		var B: TrackPath = branches[pod.path - 1]
		if pod.hint < B.covered.x:
			return {"x": B.px[B.covered.x], "y": B.py[B.covered.x]}
	var d := mouth
	for r in covered_ramps:
		if int(r[1]) == mouth - 1:
			d = int(r[0])
	return {"x": tpx[d], "y": tpy[d]}


## The job's clock (s since its first move; 0 before it).
func job_time() -> float:
	return 0.0 if job.is_empty() or job.t0 == null else time - float(job.t0)


## When the dawn front reaches (x, y), in the job's seconds.
func t_lit(x: float, y: float) -> float:
	return P.dawnT0 + (x * cos(P.dawnDir) + y * sin(P.dawnDir)) / P.dawnSpeed


## The job (the emergency run), mirroring sim-core.js jobStep: its clock starts on the first move.
## Out to the lake town's pad (stopped in its box PAD_HOLD s: the drop), then home to the start
## town's mouth before the dawn front. The towns are shelter, and so is the shade line past its
## canopy's start; caught in the open, the job fails. Each route's margin is taken at its own
## deadline: the open loop's at the mouth, the shade line's as the pod goes under the canopy.
## The Network's clock, mirroring sim-core.js netStep: it starts on the first move; crossing a
## city's terminal (its sample on its road, either way) is arriving there: from another city, an
## "arrive" event with the time since leaving it; then the clock runs from this city.
func _net_step(inp: Dictionary) -> void:
	var cur := Vector2i(pod.path, pod.hint)
	if float(net.t0) < 0.0:
		if float(inp.thrL) + float(inp.thrR) <= 0.02:
			net.prev = cur
			return
		net.t0 = time
	if pod.off_road:   # off the roads: no terminals crossed
		net.prev = Vector2i(-1, -1)
		return
	var prev: Vector2i = net.prev
	if prev.x == cur.x:
		for k in cities.size():
			var c: Dictionary = cities[k]
			if c.road != cur.x or (prev.y >= c.i) == (cur.y >= c.i):
				continue
			if k != int(net.from):
				events.append({"type": "arrive", "city": k, "from": int(net.from), "t": time - float(net.t0)})
				net.found[k] = true
			net.from = k
			net.t0 = time
	net.prev = cur


func _job_step(inp: Dictionary, dt: float, pv: float) -> void:
	var Pd := pod
	if job.stage == "done" or job.stage == "failed":
		return
	if job.t0 == null:
		if inp.thrL + inp.thrR <= 0.02:
			return
		job.t0 = time
	var t: float = time - job.t0
	job.t = t
	if crash_t > 0.0:   # wrecked this step
		job.reason = "crash"
		_job_to("failed")
		return
	var lit := t_lit(Pd.x, Pd.y)
	var covered: bool = Pd.path > 0 and Pd.hint >= branches[Pd.path - 1].covered.x
	# under the canopy you've made it: coming off the shade line the main road joins under it (the
	# join's zone, short of the mouth), and the town is shelter from there
	var merging := false
	if Pd.path == 0 and job.route == "shade" and not branches.is_empty():
		var dj := _cyc(Pd.hint - branches[0].join_i)
		merging = dj >= -branches[0].jz and dj <= 0
	# shelter: a town, a covered ramp, the shade line's canopy
	var sheltered: bool = covered or merging or (Pd.path == 0 and (tmode[Pd.hint] == 0 or tcover[Pd.hint] == 1))
	if not sheltered and t >= lit:
		job.reason = "dawn"
		events.append({"type": "dawn"})
		_job_to("failed")
		crash_t = 1.6
		return
	# home: the deadline is getting back under cover after the open loop (a receiving ramp, or the
	# shade line's canopy); the margin is taken there
	if job.stage == "home":
		if not sheltered:
			job.exposed = true
		elif job.exposed and not job.safe:
			job.safe = true
			job.route = "shade" if covered else "open"
			job.margin = lit - t
	if job.stage == "out" or job.stage == "drop":
		var dx := Pd.x - tpx[pad]
		var dy := Pd.y - tpy[pad]
		var on_pad: bool = Pd.path == 0 and absf(dx * ttx[pad] + dy * tty[pad]) <= PAD_HALF and absf(dx * tnx[pad] + dy * tny[pad]) <= PAD_HALF
		if job.stage == "out":
			job.held = job.held + dt if on_pad and pv < STOPPED else 0.0
			if job.held >= PAD_HOLD - 1e-9:
				_job_to("drop")
		elif not on_pad:
			_job_to("home")
	elif job.stage == "home":
		var d = _cyc(Pd.hint - mouth) if Pd.path == 0 else null
		if d != null and d >= 0 and d < 100 and job.prev_d != null and job.prev_d < 0 and job.prev_d > -100:   # crossed the mouth, coming home
			if not job.safe:   # never out in the open: the mouth's
				job.margin = t_lit(tpx[mouth], tpy[mouth]) - t
			_job_to("done", {"route": job.route, "margin": job.margin})
		job.prev_d = d


func _job_to(stage: String, extra: Dictionary = {}) -> void:
	job.stage = stage
	var e := {"type": "job", "stage": stage}
	e.merge(extra)
	events.append(e)
