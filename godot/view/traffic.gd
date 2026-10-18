## Things moving at ordinary speeds, so you can watch yourself lap them: trucks on a highway
## at 70 mph, a freight train at 90 mph, airliners at their 575 mph cruise, 450 m up, and cars
## crossing the overpasses at 60 mph (up the ramps, over your head, down the other side).
## Every position is a pure function of sim time (nothing to simulate, replays match), and
## only the ones near the pod are drawn: one MultiMesh per model, refilled each frame.
##   add_child(traffic); traffic.build(view)    once (range only)
##   traffic.sync(sim.time)                     every frame, after the floating origin moves
extends Node3D

const Sim := preload("res://sim/craft_sim.gd")
const Kit := preload("res://view/mesh_kit.gd")
const RangeWorld := preload("res://view/range_world.gd")

const MPH := 0.44704
const BEHIND := 3000.0
const AHEAD := 14000.0
const X_MAX := Sim.RANGE_LEN + Sim.OVERRUN   # the road and rail end here (and at 0)

const TRUCK_V := 70.0 * MPH
const TRUCK_GAP := 330.0
const TRAIN_V := 90.0 * MPH
const TRAIN_GAP := 24000.0
const TRAIN_CARS := 40
const CAR_LEN := 19.0
const PLANE_V := 575.0 * MPH
const PLANE_GAP := 36000.0
const PLANE_ALT := 450.0
const PLANE_Y := 320.0
const CAR_V := 60.0 * MPH
const CAR_GAP := 145.0
const Route := preload("res://view/route_features.gd")

var view
var trucks: MultiMesh
var locos: MultiMesh
var cars: MultiMesh
var planes: MultiMesh
var road_cars: MultiMesh   # over the overpasses


func build(v) -> void:
	view = v
	var mat := Kit.vertex_colors()
	var cab := Color(0.85, 0.86, 0.88)
	var box := Color(0.93, 0.93, 0.9)
	var dark := Color(0.12, 0.12, 0.13)
	trucks = _pool(Kit.compound([
		[Kit.box(Vector3(2.6, 3.3, 2.5)), Kit.at(Vector3(8.0, 1.95, 0)), cab],
		[Kit.box(Vector3(0.1, 1.2, 2.2)), Kit.at(Vector3(9.3, 2.7, 0)), dark],       # windscreen
		[Kit.box(Vector3(13.6, 3.8, 2.6)), Kit.at(Vector3(-0.6, 2.4, 0)), box],
		[Kit.box(Vector3(16.0, 0.5, 2.4)), Kit.at(Vector3(0.5, 0.55, 0)), dark],     # chassis + wheels
	]), 140, mat)
	locos = _pool(Kit.compound([
		[Kit.box(Vector3(21.0, 3.6, 3.0)), Kit.at(Vector3(0, 2.6, 0)), Color(0.95, 0.68, 0.12)],
		[Kit.box(Vector3(4.0, 1.0, 3.1)), Kit.at(Vector3(7.5, 3.0, 0)), Color(0.12, 0.12, 0.13)],
		[Kit.box(Vector3(21.0, 0.8, 2.8)), Kit.at(Vector3(0, 0.6, 0)), Color(0.12, 0.12, 0.13)],
	]), 8, mat)
	cars = _pool(Kit.compound([
		[Kit.box(Vector3(CAR_LEN - 1.6, 3.9, 3.0)), Kit.at(Vector3(0, 2.75, 0)), Color.WHITE],
		[Kit.box(Vector3(CAR_LEN - 1.0, 0.8, 2.8)), Kit.at(Vector3(0, 0.6, 0)), Color(0.14, 0.14, 0.15)],
	]), 2 * (TRAIN_CARS + 1), mat, true)
	var white := Color(0.94, 0.95, 0.97)
	var belly := Color(0.7, 0.72, 0.75)
	var blue := Color(0.12, 0.25, 0.55)
	road_cars = _pool(Kit.compound([   # length along z: they cross the range
		[Kit.rounded_box(Vector3(1.9, 1.0, 4.4), 6.0), Kit.at(Vector3(0, 0.7, 0)), Color.WHITE],
		[Kit.rounded_box(Vector3(1.7, 0.75, 2.2), 5.0), Kit.at(Vector3(0, 1.45, 0.2)), Color(0.15, 0.2, 0.26)],
		[Kit.box(Vector3(1.95, 0.5, 3.6)), Kit.at(Vector3(0, 0.3, 0)), Color(0.1, 0.1, 0.1)],
	]), 32, mat, true)
	planes = _pool(Kit.compound([
		[Kit.cyl(2.0, 2.0, 52.0, 16), Kit.at(Vector3.ZERO, Vector3(0, 0, PI / 2)), white],
		[Kit.cyl(0.4, 2.0, 7.0, 16), Kit.at(Vector3(29.5, 0, 0), Vector3(0, 0, -PI / 2)), white],    # nose
		[Kit.cyl(2.0, 0.6, 9.0, 16), Kit.at(Vector3(-30.5, 0.6, 0), Vector3(0, 0, -PI / 2)), white],  # tail cone
		[Kit.box(Vector3(9.0, 0.5, 60.0)), Kit.at(Vector3(-2.0, -0.9, 0), Vector3(0, 0.0, 0)), belly], # wing
		[Kit.box(Vector3(5.0, 0.4, 20.0)), Kit.at(Vector3(-30.0, 1.2, 0)), belly],                      # stabiliser
		[Kit.box(Vector3(7.0, 10.0, 0.5)), Kit.at(Vector3(-30.0, 6.5, 0), Vector3(0, 0, -0.35)), blue], # fin
		[Kit.cyl(1.4, 1.4, 5.0, 12), Kit.at(Vector3(1.0, -2.6, 9.5), Vector3(0, 0, PI / 2)), belly],    # engines
		[Kit.cyl(1.4, 1.4, 5.0, 12), Kit.at(Vector3(1.0, -2.6, -9.5), Vector3(0, 0, PI / 2)), belly],
		[Kit.box(Vector3(40.0, 0.6, 0.1)), Kit.at(Vector3(2.0, 0.6, 2.02)), blue],                     # cheat line
		[Kit.box(Vector3(40.0, 0.6, 0.1)), Kit.at(Vector3(2.0, 0.6, -2.02)), blue],
	]), 4, mat)


func _pool(mesh: Mesh, n: int, mat: Material, colors := false) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = colors
	mm.mesh = mesh
	mm.instance_count = n
	mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-1e6, -1e4, -1e6), Vector3(2e6, 2e4, 2e6))   # never culled as a whole
	add_child(mmi)
	return mm


## A stable pseudo-random 0..1 per integer (spacing jitter, paint).
static func _hash01(k: int) -> float:
	var h := (k * 374761393 + 668265263) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return float(h % 10007) / 10007.0


func sync(t: float) -> void:
	var ox: float = view.org_x
	var lo := ox - BEHIND
	var hi := ox + AHEAD
	# trucks: one lane each way, a truck every ~330 m with jitter
	var n := 0
	for dir in [1.0, -1.0]:
		var lane: float = RangeWorld.HWY_Y + (-3.5 if dir > 0.0 else 3.5)
		var shift: float = dir * TRUCK_V * t + (0.0 if dir > 0.0 else 170.0)
		for k in range(int(floor((lo - shift) / TRUCK_GAP)) - 1, int(ceil((hi - shift) / TRUCK_GAP)) + 1):
			var x: float = k * TRUCK_GAP + shift + (_hash01(k * 2 + int(dir > 0.0)) - 0.5) * 200.0
			if x < lo or x > hi or x < 0.0 or x > X_MAX or n >= trucks.instance_count:
				continue
			trucks.set_instance_transform(n, Transform3D(Basis(Vector3.UP, 0.0 if dir > 0.0 else PI), view.w3(x, lane)))
			n += 1
	trucks.visible_instance_count = n

	# freight trains heading down the range, a long one every 24 km
	var nl := 0
	var nc := 0
	var head0 := TRAIN_V * t
	for k in range(int(floor((lo - head0) / TRAIN_GAP)), int(ceil((hi + TRAIN_CARS * CAR_LEN - head0) / TRAIN_GAP)) + 1):
		var head := k * TRAIN_GAP + head0
		for j in TRAIN_CARS + 1:
			var x := head - j * CAR_LEN - (2.0 if j > 0 else 0.0)
			if x < lo or x > hi or x < 0.0 or x > X_MAX:
				continue
			if j == 0 and nl < locos.instance_count:
				locos.set_instance_transform(nl, Transform3D(Basis(), view.w3(x, RangeWorld.RAIL_Y)))
				nl += 1
			elif j > 0 and nc < cars.instance_count:
				cars.set_instance_transform(nc, Transform3D(Basis(), view.w3(x, RangeWorld.RAIL_Y)))
				var paint := _hash01(k * 64 + j)
				var col := Color(0.55, 0.24, 0.14) if paint < 0.45 else (Color(0.2, 0.36, 0.55) if paint < 0.7 else
					(Color(0.85, 0.85, 0.82) if paint < 0.85 else Color(0.25, 0.45, 0.28)))
				cars.set_instance_color(nc, col)
				nc += 1
	locos.visible_instance_count = nl
	cars.visible_instance_count = nc

	# airliners cruising down the range, 450 m up (seen further: they rise out of the haze)
	var np := 0
	var p0 := PLANE_V * t
	for k in range(int(floor((lo - p0) / PLANE_GAP)), int(ceil((ox + 30000.0 - p0) / PLANE_GAP)) + 1):
		var x := k * PLANE_GAP + p0
		if x < lo or x > ox + 30000.0 or np >= planes.instance_count:
			continue
		var y := PLANE_Y + (_hash01(k) - 0.5) * 300.0
		planes.set_instance_transform(np, Transform3D(Basis(), view.w3(x, y, PLANE_ALT + _hash01(k + 7) * 150.0)))
		np += 1
	planes.visible_instance_count = np

	# cars over the overpasses: two lanes, opposite ways, following the deck and the ramps
	var nc2 := 0
	var route = view.range_world.route if view.range_world else null
	if route:
		var path := Route.RAMP_END_Y * 2.0
		for o in route.overpass_x:
			if o < lo - 300.0 or o > hi:
				continue
			for lane in 2:
				var dir := 1.0 if lane == 0 else -1.0
				for k in int(path / CAR_GAP):
					if nc2 >= road_cars.instance_count:
						break
					var yy := fposmod(k * CAR_GAP + dir * CAR_V * t + o * 0.37 + lane * 61.0, path) - path / 2.0
					var hgt := Route.road_height(yy)
					var slope := 0.0
					if absf(yy) > Route.DECK_HALF_Y:   # on a ramp: nose down going away from the deck
						slope = atan(Route.DECK_TOP / (Route.RAMP_END_Y - Route.DECK_HALF_Y)) * signf(yy) * dir
					var basis := Basis(Vector3.UP, 0.0 if dir > 0.0 else PI) * Basis(Vector3.RIGHT, slope)
					road_cars.set_instance_transform(nc2, Transform3D(basis, view.w3(o + (dir * 3.5), yy, hgt)))
					var paint := _hash01(int(o) + k * 7 + lane * 131)
					road_cars.set_instance_color(nc2, Color.from_hsv(paint, 0.55, 0.85) if paint < 0.7 else Color(0.9, 0.9, 0.88))
					nc2 += 1
	road_cars.visible_instance_count = nc2
