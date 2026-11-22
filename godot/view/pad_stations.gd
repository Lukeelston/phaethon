## Local ground equipment on the port edge of each personal bay. Everything on the stand
## is folded into a single two-surface mesh when the pad changes address.
extends RefCounted

const Kit := preload("res://view/mesh_kit.gd")
const INK := Color("#203136")
const IRON := Color("#4b6469")
const BONE := Color("#e1dcc4")
const BRASS := Color("#dcb567")
const ICE := Color("#85dbe4")
const OXIDE := Color("#ae533a")
const MARINE := Color("#317976")
const SAFFRON := Color("#e9aa45")
const LAMP := Color("#fff1be")

# The shop's name while held, its departure board when released, and its service-deck paint.
const LEGENDS := {
	"eridanus": ["SOLAR WORKS", "CLEAR SKIES", BRASS],
	"dunes": ["SHADE LOFT", "MIND THE SAND", SAFFRON],
	"glacier": ["NORTH OPTICS", "STAY FROSTY", ICE],
	"basalt": ["HOT SHOP", "MIND THE SLAG", OXIDE],
	"mesa": ["RELAY ROOM", "RELAY OUT", MARINE],
	"coast": ["LIGHT STATION", "FAIR WINDS", BONE],
	"drop": ["PLUMB HOUSE", "EYES AHEAD", SAFFRON],
	"wash": ["WIND DESK", "READ THE SOCK", OXIDE],
	"frost": ["SNOW SURVEY", "WATCH FOR ICE", ICE],
	"reed": ["PUMP HOUSE", "KEEP DRY", MARINE],
	"red": ["CORE SHED", "LOOSE GRAVEL", OXIDE],
	"needle": ["GYRO BENCH", "FULL ROLL", BRASS],
	"hammer": ["DROP TEST", "STEEP GRADE", SAFFRON],
	"gap": ["TIMING HUT", "BUILD SPEED", BONE],
	"helios": ["BASE CAMP", "CLIMB AHEAD", OXIDE],
	"summit": ["HIGH STATION", "RIM AHEAD", ICE],
	# (Mount Hyperion's two bays, added when the mountain was: its foot and its summit)
	"hyperion": ["RAMP WORKS", "POINT IT UP", SAFFRON],
	"hyperion_summit": ["BRINK WATCH", "CREEP TO THE LIP", ICE],
}

var metal: Array = []
var enamel: Array = []  # instrument faces and retroreflective paint that read after dark


func make(id: String, pad_to_station: Transform3D, cart: Vector3, ahead: float) -> ArrayMesh:
	# Each site has a different tool in silhouette. The same little enamel sign is bolted
	# to all sixteen, as if one network electrician made the rounds.
	_box(Vector3(0, 0.19, 0), Vector3(5.25, 0.36, 2.45), IRON)
	for x in [-1.85, 1.85]:
		_box(Vector3(x, 1.22, 0.65), Vector3(0.16, 2.3, 0.18), IRON)
	_box(Vector3(0, 2.52, 1.0), Vector3(5.2, 1.04, 0.15), INK)
	_box(Vector3(0, 2.06, 1.09), Vector3(5.12, 0.065, 0.035), BRASS, Vector3.ZERO, true)
	match id:
		"eridanus":
			_solar_iris()
		"dunes":
			_shade_loft()
		"glacier":
			_optics()
		"basalt":
			_foundry()
		"mesa":
			_relay_dish()
		"coast":
			_lighthouse()
		"drop":
			_plumb_bob()
		"wash":
			_windsock()
		"frost":
			_snow_staff()
		"reed":
			_pump()
		"red":
			_core_rack()
		"needle":
			_gyro()
		"hammer":
			_drop_tester()
		"gap":
			_timing_clock()
		"helios":
			_route_relief()
		"summit":
			_radome()
		"hyperion":
			_ramp_profile()
		"hyperion_summit":
			_brink_gallows()
	_service_deck(pad_to_station, cart, ahead, LEGENDS[id][2])
	var mesh := Kit.compound(metal)
	Kit.compound(enamel, mesh)
	mesh.surface_set_material(0, Kit.vertex_colors())
	mesh.surface_set_material(1, Kit.vertex_colors(true))
	return mesh


## Hyperion's foot: the ramp's own profile in rail, level at the shop floor and straight up at its
## head, a marker a third of the way round where a craft would be, a mast under the vertical end.
func _ramp_profile() -> void:
	var foot := Vector3(-1.9, 1.3, 0)
	var radius := 6.6
	_tube(Vector3(foot.x, 0.36, 0), foot, 0.30, 0.22, IRON, 8)
	var last := foot
	for k in range(1, 9):
		var a := (PI / 2.0) * k / 8.0
		var p := foot + Vector3(sin(a) * radius * 0.55, (1.0 - cos(a)) * radius, 0)
		_tube(last, p, 0.15, 0.15, BRASS, 8)
		_box(p, Vector3(0.52, 0.10, 0.62), IRON, Vector3(0, 0, a))
		if k == 3:
			_box(p + Vector3(-0.10, 0.20, 0.36), Vector3(0.60, 0.24, 0.10), OXIDE, Vector3(0, 0, a), true)
		last = p
	_tube(Vector3(last.x, 0.36, 0), last, 0.14, 0.09, IRON, 6)
	_tube(last, last + Vector3(0, 0.95, 0), 0.04, 0.04, BONE)
	_box(last + Vector3(0.36, 0.72, 0), Vector3(0.70, 0.36, 0.05), SAFFRON)


## Hyperion's summit: a watchman's lamp hung out over a block cut square like the brink itself,
## a ring round the lamp to find it by against a black sky.
func _brink_gallows() -> void:
	_box(Vector3(0.95, 1.12, 0), Vector3(2.7, 1.52, 1.9), IRON)
	_tube(Vector3(1.55, 1.88, 0), Vector3(1.55, 7.6, 0), 0.24, 0.16, INK, 8)
	_tube(Vector3(1.55, 7.45, 0), Vector3(-1.75, 7.45, 0), 0.13, 0.10, INK, 8)
	_tube(Vector3(1.55, 5.6, 0), Vector3(-0.2, 7.40, 0), 0.07, 0.07, IRON, 6)
	var lamp := Vector3(-1.75, 6.05, 0)
	_tube(Vector3(lamp.x, 7.40, 0), lamp + Vector3(0, 0.42, 0), 0.03, 0.03, BONE, 5)
	_tube(lamp + Vector3(0, -0.42, 0), lamp + Vector3(0, 0.42, 0), 0.36, 0.22, LAMP, 10, true)
	_hoop(lamp, 0.95, 0.06, ICE)
	for k in 4:
		_box(Vector3(-0.38 + 0.02 * k, 0.45 + 0.36 * k, 0), Vector3(0.09, 0.10, 1.9), SAFFRON, Vector3.ZERO, true)


## The shop marks its own power cart and paints a walking lane to the right engine.
## These parts share the station's draw call, even though their positions are fixed to the apron.
func _service_deck(pad_to_station: Transform3D, cart: Vector3, ahead: float, paint: Color) -> void:
	var first := metal.size()
	_box(cart + Vector3(0, 1.14, 0), Vector3(1.04, 0.052, 1.72), paint)
	for x in [-0.76, 0.76]:
		_box(cart + Vector3(x, 0.61, 0), Vector3(0.035, 0.30, 1.72), paint)
	var length := ahead + 2.0
	for x in [7.25, 9.15]:
		_box(Vector3(x, 0.10, -length / 2), Vector3(0.18, 0.025, length), paint)
	for k in 6:
		_box(Vector3(8.20, 0.102, -length + k * 0.88), Vector3(1.88, 0.025, 0.25), paint, Vector3(0, -0.30, 0))
	for k in range(first, metal.size()):
		metal[k][1] = pad_to_station * metal[k][1]


func _box(p: Vector3, size: Vector3, c: Color, rot := Vector3.ZERO, luminous := false) -> void:
	(enamel if luminous else metal).append([Kit.box(size), Kit.at(p, rot), c])


## A tapered tube between two arbitrary fittings, with its bottom radius at a.
func _tube(a: Vector3, b: Vector3, bottom: float, top: float, c: Color, sides := 12, luminous := false) -> void:
	var along := b - a
	var xf := Transform3D(Basis(Quaternion(Vector3.UP, along.normalized())), (a + b) / 2.0)
	(enamel if luminous else metal).append([Kit.cyl(top, bottom, along.length(), sides), xf, c])


func _hoop(p: Vector3, radius: float, thickness: float, c: Color, tilt := Vector3(PI / 2.0, 0, 0)) -> void:
	var hoop := TorusMesh.new()
	hoop.inner_radius = radius - thickness
	hoop.outer_radius = radius + thickness
	hoop.rings = 28
	hoop.ring_segments = 6
	metal.append([hoop, Kit.at(p, tilt), c])


func _tripod(h: float, spread: float, c: Color) -> void:
	for k in 3:
		var angle := TAU * k / 3.0
		_tube(Vector3(cos(angle) * spread, 0.35, sin(angle) * spread * 0.67), Vector3(0, h, 0), 0.18, 0.12, c)


## The Eridanus solar works' aperture in miniature: eight folded brass shutters around open sky.
func _solar_iris() -> void:
	_tripod(5.25, 1.8, MARINE)
	var hub := Vector3(0, 6.2, 0)
	_hoop(hub, 2.05, 0.15, MARINE)
	for k in 8:
		var a := TAU * k / 8.0
		var radial := Vector3(cos(a), sin(a), 0)
		_box(hub + radial * 1.49, Vector3(1.44, 0.4, 0.32), BRASS if k % 2 == 0 else BONE, Vector3(0, 0, a + 0.57))
		_box(hub + radial * 2.08 + Vector3(0, 0, 0.12), Vector3(0.32, 0.18, 0.08), LAMP, Vector3(0, 0, a), true)


## Wind-stretched strips of canvas hang between unequal spars. Each strip sags in the middle.
func _shade_loft() -> void:
	for x in [-2.18, 2.18]:
		_tube(Vector3(x, 0.3, 0), Vector3(x, 8.0 if x < 0 else 6.35, 0), 0.12, 0.08, BONE)
	for s in 4:
		var z := -0.85 + s * 0.55
		var corners := [
			Vector3(-2.18, 7.7 - 0.3 * s, z),
			Vector3(-0.7, 6.65 - 0.38 * s, z),
			Vector3(0.8, 6.19 - 0.5 * s, z),
			Vector3(2.18, 6.05 - 0.52 * s, z)
		]
		for k in 3:
			var a: Vector3 = corners[k]
			var b: Vector3 = corners[k + 1]
			_box(
				(a + b) / 2,
				Vector3(a.distance_to(b) + 0.04, 0.16, 0.65),
				SAFFRON if s % 2 == 0 else OXIDE,
				Vector3(0, 0, atan2(b.y - a.y, b.x - a.x))
			)
	_tube(Vector3(-2.17, 7.74, 0), Vector3(-2.17, 8.38, 0), 0.14, 0.06, SAFFRON)


func _optics() -> void:
	_tripod(4.9, 1.9, BONE)
	_tube(Vector3(0, 4.5, 0), Vector3(0, 5.87, 0), 0.65, 0.48, IRON)
	var a := Vector3(-1.75, 5.4, -0.62)
	var b := Vector3(1.62, 7.25, 0.63)
	var v := (b - a).normalized()
	_tube(a, b, 0.43, 0.84, BONE, 16)
	_tube(b - v * 0.55, b + v * 0.13, 0.94, 0.97, INK, 18)
	_tube(b + v * 0.14, b + v * 0.17, 0.78, 0.78, ICE, 18, true)
	_tube(a - v * 0.42, a, 0.24, 0.38, MARINE)
	_tube(a + Vector3(0.25, 0.76, 0), b + Vector3(-0.65, 0.58, 0), 0.14, 0.17, ICE)


func _foundry() -> void:
	for k in 2:
		var x := -1.25 + 2.4 * k
		var h := 7.9 - k * 2.1
		_tube(Vector3(x, 0.3, 0), Vector3(x, h, 0), 1.04, 0.68, INK, 8)
		for j in 5:
			var y := 2.8 + (h - 3.1) * j / 4.0
			_tube(Vector3(x, y, 0), Vector3(x, y + 0.2, 0), 1.0, 1.0, IRON, 8)
		_box(Vector3(x, h * 0.60, 0.84), Vector3(0.23, h * 0.58, 0.12), SAFFRON, Vector3.ZERO, true)
		_tube(Vector3(x, h, 0), Vector3(x, h + 0.23, 0), 0.78, 0.87, OXIDE, 8)
		_tube(Vector3(x, h + 0.23, 0), Vector3(x, h + 0.26, 0), 0.55, 0.55, SAFFRON, 8, true)


func _relay_dish() -> void:
	_tripod(4.2, 1.8, OXIDE)
	var hub := Vector3(0, 5.85, 0)
	var axis := Vector3(-0.55, 0.55, 0.63).normalized()
	_tube(hub - axis * 0.6, hub + axis * 0.32, 0.51, 2.4, BONE, 20)
	_tube(hub + axis * 0.33, hub + axis * 0.36, 2.22, 2.22, MARINE, 20)
	var across := axis.cross(Vector3.UP).normalized()
	var upwards := across.cross(axis)
	var pickup := hub + axis * 2.05
	for k in 3:
		var a := TAU * k / 3
		var rim := hub + axis * 0.4 + (across * cos(a) + upwards * sin(a)) * 2.15
		_tube(rim, pickup, 0.07, 0.07, BONE)
	_tube(pickup - axis * 0.20, pickup + axis * 0.23, 0.25, 0.31, SAFFRON)
	_tube(Vector3(0, 3.8, 0), hub - axis * 0.55, 0.45, 0.55, IRON)


func _lighthouse() -> void:
	for k in 5:
		var y := 0.35 + k * 1.08
		_tube(Vector3(0, y, 0), Vector3(0, y + 1.08, 0), 1.22 - 0.1 * k, 1.12 - 0.1 * k, BONE if k % 2 == 0 else OXIDE, 14)
	_tube(Vector3(0, 5.75, 0), Vector3(0, 5.99, 0), 1.5, 1.5, INK, 14)
	_hoop(Vector3(0, 6.5, 0), 1.36, 0.06, BONE, Vector3.ZERO)
	for k in 8:
		var xz := Vector3(cos(k * TAU / 8), 0, sin(k * TAU / 8))
		_tube(Vector3.UP * 5.97 + xz * 1.36, Vector3.UP * 6.51 + xz * 1.36, 0.04, 0.04, BONE, 6)
		_tube(Vector3.UP * 5.99 + xz * 0.88, Vector3.UP * 7.45 + xz * 0.88, 0.07, 0.07, INK, 6)
	_tube(Vector3(0, 6.42, 0), Vector3(0, 7.04, 0), 0.48, 0.48, LAMP, 12, true)
	_tube(Vector3(0, 7.43, 0), Vector3(0, 8.38, 0), 1.36, 0.08, OXIDE, 14)


func _plumb_bob() -> void:
	_tube(Vector3(-1.75, 0.4, 0), Vector3(-1.75, 8.35, 0), 0.23, 0.18, SAFFRON, 8)
	_box(Vector3(-0.23, 8.12, 0), Vector3(3.45, 0.33, 0.34), SAFFRON)
	_tube(Vector3(-1.75, 6.45, 0), Vector3(0.62, 8.08, 0), 0.095, 0.095, IRON)
	_tube(Vector3(1.14, 8.04, 0), Vector3(1.14, 6.14, 0), 0.06, 0.06, BONE)
	_tube(Vector3(1.14, 5.57, 0), Vector3(1.14, 6.25, 0), 0.88, 0.19, BRASS, 8)
	_tube(Vector3(1.14, 4.1, 0), Vector3(1.14, 5.57, 0), 0.04, 0.88, SAFFRON, 8)
	_hoop(Vector3(1.14, 3.98, 0), 0.73, 0.07, IRON, Vector3.ZERO)
	for k in 6:
		_box(Vector3(-1.72, 3.1 + k * 0.63, 0.2), Vector3(0.37, 0.13, 0.05), BONE, Vector3.ZERO, true)


func _windsock() -> void:
	var mast := Vector3(-1.85, 7.5, 0)
	_tube(Vector3(mast.x, 0.3, 0), mast + Vector3.UP * 0.52, 0.17, 0.085, IRON)
	var throat := mast + Vector3(0.30, -0.32, 0)
	var tail := Vector3(2.4, 5.78, 0.48)
	for k in 5:
		var t := k / 5.0
		_tube(
			throat.lerp(tail, t),
			throat.lerp(tail, t + 0.2),
			lerpf(0.76, 0.24, t),
			lerpf(0.76, 0.24, t + 0.2),
			OXIDE if k % 2 == 0 else BONE,
			12
		)
	_tube(mast + Vector3.UP * 0.44, throat + Vector3.UP * 0.49, 0.06, 0.06, IRON)
	_tube(mast + Vector3.UP * 0.44, throat - Vector3.UP * 0.52, 0.06, 0.06, IRON)


func _snow_staff() -> void:
	for k in 10:
		_box(Vector3(-1.33, 0.75 + k * 0.75, 0), Vector3(0.46, 0.75, 0.40), ICE if k % 2 else INK)
		_box(Vector3(-1.02, 0.76 + k * 0.75, 0), Vector3(0.46 if k % 2 else 0.76, 0.12, 0.35), BONE)
	_tube(Vector3(0.92, 0.36, 0), Vector3(0.92, 4.93, 0), 0.18, 0.14, BRASS)
	for k in 7:
		var y := 4.84 + k * 0.22
		_tube(Vector3(0.92, y, 0), Vector3(0.92, y + 0.14, 0), 1.06, 0.81, BONE, 6)
	_tube(Vector3(0.92, 6.36, 0), Vector3(0.92, 6.85, 0), 1.16, 0.3, ICE, 6)


func _pump() -> void:
	for k in 2:
		var x := -1.62 + k * 2.15
		var h := 6.4 + k * 1.1
		_tube(Vector3(x, 0.35, 0), Vector3(x, h - 0.42, 0), 0.38, 0.38, MARINE)
		_tube(Vector3(x, h - 0.46, 0), Vector3(x + 0.45, h, 0), 0.40, 0.40, MARINE)
		_tube(Vector3(x + 0.40, h, 0), Vector3(x + 1.08, h, 0), 0.4, 0.4, MARINE)
		_tube(Vector3(x + 1.04, h, 0), Vector3(x + 1.40, h - 0.48, 0), 0.4, 0.48, BRASS)
		for y in [3.6, 5.25]:
			_tube(Vector3(x, y, 0), Vector3(x, y + 0.16, 0), 0.51, 0.51, BONE)
	_hoop(Vector3(-0.52, 4.0, 0.53), 0.72, 0.10, SAFFRON)
	for k in 3:
		var a := k * TAU / 3
		_tube(Vector3(-0.52, 4, 0.53), Vector3(-0.52 + cos(a) * 0.70, 4 + sin(a) * 0.70, 0.53), 0.065, 0.065, SAFFRON)


func _core_rack() -> void:
	_box(Vector3(0, 3.72, -0.2), Vector3(4.55, 0.39, 1.16), IRON)
	var layers := [OXIDE, BRASS, Color("#734e49"), BONE, Color("#b46742")]
	for k in 5:
		var x := -1.65 + k * 0.83
		var height: float = [2.18, 3.12, 3.82, 2.84, 1.66][k]
		_tube(Vector3(x, 0.36, -0.2), Vector3(x, 3.72, -0.2), 0.25, 0.24, IRON)
		for j in 5:
			var y := 3.90 + height * j / 5.0
			_tube(Vector3(x, y, -0.2), Vector3(x, y + height / 5, -0.2), 0.36, 0.36, layers[(j + k) % 5], 7)
		_tube(Vector3(x, 3.91, -0.2), Vector3(x, 4.12, -0.2), 0.41, 0.41, BONE, 8)


func _gyro() -> void:
	_tripod(4.25, 1.85, IRON)
	var hub := Vector3(0, 6.18, 0)
	_hoop(hub, 2.10, 0.15, SAFFRON)
	_hoop(hub, 1.82, 0.12, BONE, Vector3(1.05, 0.42, -0.45))
	_hoop(hub, 1.32, 0.14, MARINE, Vector3(0.65, -0.5, 0.93))
	_tube(hub + Vector3(-0.36, -0.5, -0.4), hub + Vector3(0.36, 0.5, 0.4), 0.49, 0.49, BRASS)
	for side in [-1, 1]:
		_box(hub + Vector3(side * 2.12, 0, 0), Vector3(0.38, 0.42, 0.46), INK)


func _drop_tester() -> void:
	for x in [-1.75, 1.75]:
		_tube(Vector3(x, 0.35, 0), Vector3(x * 0.82, 8.04, 0), 0.24, 0.18, OXIDE, 6)
	_box(Vector3(0, 7.95, 0), Vector3(3.42, 0.45, 0.74), INK)
	_tube(Vector3(0, 6.26, 0), Vector3(0, 7.82, 0), 0.19, 0.19, BONE)
	_box(Vector3(0, 5.87, 0), Vector3(2.13, 0.91, 1.05), SAFFRON)
	for k in 3:
		_box(Vector3(-0.72 + 0.69 * k, 5.88, 0.54), Vector3(0.22, 0.88, 0.04), INK, Vector3(0, 0, -0.29))
	_box(Vector3(0, 3.50, 0), Vector3(2.64, 0.36, 1.16), BONE)
	_box(Vector3(0, 1.85, 0), Vector3(1.7, 3.22, 1.03), IRON)


func _timing_clock() -> void:
	_tube(Vector3(0, 0.36, 0), Vector3(0, 4.95, 0), 0.44, 0.27, IRON, 8)
	var dial := Vector3(0, 6.08, 0)
	_tube(dial - Vector3.BACK * 0.38, dial, 2.07, 2.07, INK, 32)
	_tube(dial, dial + Vector3.BACK * 0.06, 1.86, 1.86, BONE, 32)
	for k in 12:
		var a := TAU * k / 12
		_box(dial + Vector3(sin(a) * 1.53, cos(a) * 1.53, 0.10), Vector3(0.12, 0.35, 0.055), INK, Vector3(0, 0, -a))
	_tube(dial + Vector3(0, 0, 0.18), dial + Vector3(1.03, 0.91, 0.18), 0.12, 0.065, OXIDE)
	for side in [-1, 1]:
		_box(Vector3(side * 1.42, 7.87, 0), Vector3(0.81, 0.46, 0.67), SAFFRON, Vector3(0, 0, -side * 0.5))


func _route_relief() -> void:
	# A trailhead cairn with the climbing road painted across the three rock faces.
	for k in 3:
		var x := -1.40 + k * 1.34
		var h: float = [5.8, 8.15, 6.64][k]
		_tube(Vector3(x, 0.40, 0), Vector3(x, h, 0), 1.18, 0.08, [OXIDE, IRON, BRASS][k], 5)
	var route := [
		Vector3(-1.58, 3.45, 0.72),
		Vector3(0.45, 4.18, 0.83),
		Vector3(-0.53, 4.66, 0.71),
		Vector3(0.39, 5.28, 0.64),
		Vector3(-0.30, 5.70, 0.53),
		Vector3(0.04, 6.15, 0.43)
	]
	for k in route.size() - 1:
		_tube(route[k], route[k + 1], 0.091, 0.091, LAMP, 6, true)
	_tube(Vector3(-0.06, 7.92, 0), Vector3(-0.06, 8.89, 0), 0.045, 0.045, BONE)
	_box(Vector3(0.38, 8.66, 0), Vector3(0.88, 0.40, 0.05), SAFFRON)


func _radome() -> void:
	_tripod(4.92, 1.89, BRASS)
	_tube(Vector3(0, 4.49, 0), Vector3(0, 4.89, 0), 1.56, 1.85, INK, 12)
	var rings := [[4.89, 1.90], [5.90, 2.18], [6.96, 1.73], [7.63, 0.90], [7.86, 0.03]]
	for k in rings.size() - 1:
		var lower: Array = rings[k]
		var upper: Array = rings[k + 1]
		_tube(Vector3(0, lower[0], 0), Vector3(0, upper[0], 0), lower[1], upper[1], BONE if k % 2 else ICE, 10)
		for j in 10:
			var a := j * TAU / 10.0
			var b := (j + 1) * TAU / 10.0
			var p := Vector3(cos(a) * lower[1], lower[0], sin(a) * lower[1])
			var q := Vector3(cos(b) * upper[1], upper[0], sin(b) * upper[1])
			_tube(p, q, 0.045, 0.045, IRON, 5)
	_tube(Vector3(0, 7.84, 0), Vector3(0, 9.01, 0), 0.07, 0.03, BRASS)
