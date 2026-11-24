## Things moving at ordinary speeds, so you can watch yourself lap them: trucks on a highway
## at 70 mph, a freight train at 90 mph, airliners at their 575 mph cruise, 450 m up, and cars
## crossing the overpasses at 60 mph (up the ramps, over your head, down the other side).
## Every position is a pure function of sim time (nothing to simulate, replays match), and
## only the ones near the pod are drawn: a near and a distant MultiMesh per model, refilled each frame.
##   add_child(traffic); traffic.build(view)    once (range only)
##   traffic.sync(sim.time)                     every frame, after the floating origin moves
extends Node3D

const Sim := preload("res://sim/craft_sim.gd")
const Batch := preload("res://view/traffic_batch.gd")
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
var trucks: Batch
var tankers: Batch
var locos: Batch
var cars: Batch
var hoppers: Batch
var planes: Batch
var road_cars: Batch   # over the overpasses


func build(v) -> void:
	view = v
	trucks = _pool(preload("res://art/traffic/truck.glb"), 140, 1400.0)
	tankers = _pool(preload("res://art/traffic/tanker.glb"), 40, 1400.0)
	locos = _pool(preload("res://art/traffic/locomotive.glb"), 8, 1400.0)
	cars = _pool(preload("res://art/traffic/boxcar.glb"), 2 * (TRAIN_CARS + 1), 1400.0, true)
	hoppers = _pool(preload("res://art/traffic/hopper.glb"), TRAIN_CARS, 1400.0, true)
	road_cars = _pool(preload("res://art/traffic/sedan.glb"), 32, 300.0, true)
	planes = _pool(preload("res://art/traffic/airliner.glb"), 4, 2400.0)

func _pool(model: PackedScene, capacity: int, radius: float, colors := false) -> Batch:
	var batch := Batch.new()
	batch.configure(model, capacity, radius, AABB(Vector3(-1e6, -1e4, -1e6), Vector3(2e6, 2e4, 2e6)), colors)
	add_child(batch)
	return batch

## A stable pseudo-random 0..1 per integer (spacing jitter, paint).
static func _hash01(k: int) -> float:
	var h := (k * 374761393 + 668265263) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return float(h % 10007) / 10007.0


func sync(t: float) -> void:
	var camera := get_viewport().get_camera_3d()
	var eye := camera.global_position if camera else Vector3.ZERO
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
			if x < lo or x > hi or x < 0.0 or x > X_MAX or n >= trucks.capacity:
				continue
			var body := tankers if posmod(k + int(dir > 0.0), 4) == 0 else trucks
			body.put(Transform3D(Basis(Vector3.UP, 0.0 if dir > 0.0 else PI), view.w3(x, lane)), eye)
			n += 1
	trucks.finish_frame()
	tankers.finish_frame()

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
			if j == 0 and nl < locos.capacity:
				locos.put(Transform3D(Basis(), view.w3(x, RangeWorld.RAIL_Y)), eye)
				nl += 1
			elif j > 0 and nc < cars.capacity:
				var paint := _hash01(k * 64 + j)
				var col := Color(0.55, 0.24, 0.14) if paint < 0.45 else (Color(0.2, 0.36, 0.55) if paint < 0.7 else
					(Color(0.85, 0.85, 0.82) if paint < 0.85 else Color(0.25, 0.45, 0.28)))
				# Aggregate wagons travel in short groups; their consist follows the train across origin shifts.
				var wagon := hoppers if posmod(j + 3 * k, 8) < 3 else cars
				wagon.put(Transform3D(Basis(), view.w3(x, RangeWorld.RAIL_Y)), eye, col)
				nc += 1
	locos.finish_frame()
	cars.finish_frame()
	hoppers.finish_frame()

	# airliners cruising down the range, 450 m up (seen further: they rise out of the haze)
	var np := 0
	var p0 := PLANE_V * t
	for k in range(int(floor((lo - p0) / PLANE_GAP)), int(ceil((ox + 30000.0 - p0) / PLANE_GAP)) + 1):
		var x := k * PLANE_GAP + p0
		if x < lo or x > ox + 30000.0 or np >= planes.capacity:
			continue
		var y := PLANE_Y + (_hash01(k) - 0.5) * 300.0
		planes.put(Transform3D(Basis(), view.w3(x, y, PLANE_ALT + _hash01(k + 7) * 150.0)), eye)
		np += 1
	planes.finish_frame()

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
					if nc2 >= road_cars.capacity:
						break
					var yy := fposmod(k * CAR_GAP + dir * CAR_V * t + o * 0.37 + lane * 61.0, path) - path / 2.0
					var hgt := Route.road_height(yy)
					var slope := 0.0
					if absf(yy) > Route.DECK_HALF_Y:   # on a ramp: nose down going away from the deck
						slope = atan(Route.DECK_TOP / (Route.RAMP_END_Y - Route.DECK_HALF_Y)) * signf(yy) * dir
					var basis := Basis(Vector3.UP, 0.0 if dir > 0.0 else PI) * Basis(Vector3.RIGHT, slope)
					var paint := _hash01(int(o) + k * 7 + lane * 131)
					var hue := Color.from_hsv(paint, 0.55, 0.85) if paint < 0.7 else Color(0.9, 0.9, 0.88)
					road_cars.put(Transform3D(basis, view.w3(o + (dir * 3.5), yy, hgt)), eye, hue)
					nc2 += 1
	road_cars.finish_frame()
