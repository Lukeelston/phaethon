## The Aurora line's takeoff and landing areas (view/aurora_stations.gd; Luke, after the twelfth
## flight: "animated 'takeoff and landing' areas for aurora, that will tell the pilot where to stop"):
##   pad       one at each lock, on the road's own surface outside the seal, on its flat, with a
##             gate of light over its bar (posts outside the flat, a beam high over the deck) and
##             a pylon at each corner
##   takeoff   a craft stopped on it heading in cycles the lock (latch, seal, equalise, clear) in
##             seven seconds; one that does not stop starts nothing
##   landing   a craft that came through the tube and stopped on the far pad is told where it is,
##             where from, how long it took and how fast it went
##   guidance  the distance rings and their words stand where they say; a craft coming is shown
##             green, amber or red by what its brakes can do, and that is measured here again
##   clear     nothing built is inside the bore, or low over the road's flat
## Prints AURORA STATIONS PASS.
extends SceneTree

const View := preload("res://view/craft_view.gd")
const Sim := preload("res://sim/craft_sim.gd")
const Tube := preload("res://sim/pressure_surface.gd")
const Stations := preload("res://view/aurora_stations.gd")
var failures := 0
var checks := 0
var v
var sim
var st
var road_i := 0
var R
var i0 := 0
var i1 := 0
var _bores := {}


func _initialize() -> void:
	View.track_override = "network"
	View.job_override = "none"
	View.best_dir = OS.get_user_data_dir().path_join("test_aurora_stations_")
	preload("res://view/outlook.gd").pinned = true
	_run.call_deferred()


func _check(label: String, passed: bool) -> void:
	checks += 1
	print(("PASS " if passed else "FAIL ") + label)
	failures += int(not passed)


## The craft set down on the tube's road at a sample, pointing the way given, at a speed (m/s).
func _put(sample: int, way: int, speed := 0.0) -> void:
	sim.respawn_on(road_i, sample, way)
	for b in sim.bodies:
		b.vx = R.tx[sample] * way * speed
		b.vy = R.ty[sample] * way * speed


func _steps(seconds: float, dt := 0.1) -> void:
	for k in roundi(seconds / dt):
		st.step(dt)


func _run() -> void:
	v = View.new()
	root.add_child(v)
	await process_frame
	v.set_process(false)
	sim = v.sim
	var line = v.network_world.pressure_line if v.network_world != null else null
	if line == null or line.get("stations") == null:
		print("FAIL the Aurora line has its stations")
		print("AURORA STATIONS FAIL (no stations)")
		quit(1)
		return
	st = line.stations
	st.set_process(false)
	st.sound = false
	road_i = int(Sim.NET_PRESSURE[0])
	R = sim.roads[road_i]
	i0 = int(Sim.NET_PRESSURE[1])
	i1 = int(Sim.NET_PRESSURE[2])
	var a := Vector2(R.px[i0], R.py[i0])
	var t := Vector2(R.tx[i0], R.ty[i0])
	var n := Vector2(R.nx[i0], R.ny[i0])
	var keel: float = sim.net_height(road_i, float(i0))
	var span: float = float(i1 - i0) * float(R.len[i0])

	# ---- the pads lie on the road
	_check("a lock at each end of the sealed span (%.0f km), each with the field across its bore" % (span / 1000.0),
		st.locks.size() == 2 and st.locks[0].home == 0.0 and absf(float(st.locks[1].home) - span) < 0.5 and st.locks[0].field != null and st.locks[1].field != null
		and st.locks[0].field != st.locks[1].field)
	var flat: float = float(R.w[i0]) / 2.0 - Sim.net_edge_span(R.w[i0])
	var worst_across := 0.0
	var worst_height := 0.0
	var reach := Stations.BAR + 110.0 + 60.0 * (Stations.ROAD_CHEVRONS - 1) + 36.0      # the furthest chevron's far end
	for lock in [[i0, -1], [i1, 1]]:
		for k in range(0, ceili(reach / float(R.len[i0])) + 1):
			var i: int = int(lock[0]) + int(lock[1]) * k
			var q := Vector2(R.px[i], R.py[i]) - a
			worst_across = maxf(worst_across, absf(q.dot(n)))
			worst_height = maxf(worst_height, absf(sim.net_height(road_i, float(i)) - keel))
	_check("the road outside each seal runs straight and level under the pad and its chevrons (%.0f m out: %.1f m off the line, %.2f m off the keel's height), and they keep to its flat (%.0f m either side)" % [reach, worst_across, worst_height, flat],
		worst_across + 34.0 < flat and worst_height < 0.25 and Stations.PAD_WIDE + worst_across < flat and Stations.DECK > 0.12 and Stations.DECK < 0.5)

	# ---- takeoff
	var pad_sample := roundi(Stations.BAR / float(R.len[i0]))
	_put(i0 - 40, 1)
	st.step(0.1)
	var lock: Dictionary = st.locks[0]
	var red: Vector3 = lock.pad.get_shader_parameter("state")
	var road_face: Label3D = lock.node.get_node("Sign")
	_check("at rest the bar is red, the field as it was, and the lock's board and the sign over the road (both its faces) say to stop at the red bar", lock.state == Stations.REST and red.x > 0.9 and red.y < 0.2 and float(lock.charge) == 0.0
		and String(lock.said).contains("STOP AT THE RED BAR") and String(lock.said).contains("SOUTHWEST LOCK") and String(lock.told).contains("STOP AT THE RED BAR")
		and road_face.text.contains("STOP AT THE RED BAR") and road_face.text.contains("SOUTHWEST LOCK")
		and absf(road_face.position.z + Stations.BAR + Stations.SIGN_AT) < 3.0 and road_face.position.z < lock.arrival.position.z)
	_put(i0 - pad_sample, 1)
	st.step(0.1)
	var green: Vector3 = lock.pad.get_shader_parameter("state")
	_check("a craft stopped on the pad heading in starts the cycle: the bar green, the latch heard", lock.state == Stations.CYCLE and green.y > 0.9 and green.x < 0.5 and st.played.has([0, "clamp"]))
	_steps(Stations.LATCH_S * 0.5)
	var early := [float(lock.charge), float(lock.iris), float(lock.spin[0])]
	_steps(Stations.LATCH_S * 0.5 + Stations.SEAL_S * 0.6)
	var sealing := [float(lock.charge), float(lock.iris)]
	_steps(Stations.SEAL_S * 0.4 + Stations.FILL_S * 0.5)
	var filling: float = lock.gauge.get_shader_parameter("progress")
	var words := String(lock.said)
	_check("its hoops turn (%.2f rad), an iris closes across the bore (%.2f shut), the ring fills as the pressure comes up (%.2f, \"%s\")" % [early[2], sealing[1], filling, words.replace("\n", " / ")],
		absf(early[2]) > 0.05 and early[1] == 0.0 and sealing[1] > 0.3 and sealing[0] > early[0] and filling > 0.2 and filling < 0.8 and words.contains("kPa") and float(lock.iris) == 1.0
		and st.played.has([0, "release"]) and st.played.has([0, "power"]))
	_steps(Stations.FILL_S * 0.5 + Stations.OPEN_S + 0.2)
	var away: float = lock.approach.get_shader_parameter("run")
	_check("after %.1f s it is clear: the iris open (%.2f), the ring full, the strips running away down the tube (%.0f m/s), a chime, \"%s\"" % [Stations.LATCH_S + Stations.SEAL_S + Stations.FILL_S + Stations.OPEN_S, float(lock.iris), away, String(lock.said).replace("\n", " / ")],
		lock.state == Stations.CLEAR and float(lock.iris) == 0.0 and float(lock.gauge.get_shader_parameter("progress")) == 1.0 and away < 0.0 and st.played.has([0, "chime"]) and String(lock.said).contains("CLEAR"))
	_put(i0 + 90, 1, 600.0)
	st.step(0.1)
	_check("once the craft is on its way the lock rests again", lock.state == Stations.REST and float(lock.charge) == 0.0)
	# one that leaves before it is clear
	_put(i0 - pad_sample, 1)
	st.step(0.1)
	_steps(2.0)
	_put(i0 - 1, 1, 300.0)
	st.step(0.1)
	_check("a craft that leaves the pad mid-cycle lets the lock go: it rests, nothing in the way", lock.state == Stations.REST and float(lock.iris) == 0.0)
	# one that never stops
	var heard: int = st.played.size()
	var started := false
	_put(i0 - 40, 1, 300.0)
	for k in 180:
		for sub in 4:
			sim.step({"thrL": 0.5, "thrR": 0.5, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": true}, 1.0 / 240.0)
		st.step(1.0 / 60.0)
		started = started or lock.state != Stations.REST or float(lock.charge) > 0.0
	_check("a craft that crosses the pad without stopping starts nothing (it is %d samples into the tube now, on its run: %s)" % [sim.pod.hint - i0, st.trip],
		not started and st.played.size() == heard and sim.pod.hint > i0 and not st.trip.is_empty() and int(st.trip.from) == 0)
	# the far lock, the same, the other way round
	_put(i1 + pad_sample, -1)
	st.step(0.1)
	_check("the northeast lock answers a craft stopped on its pad heading southwest", st.locks[1].state == Stations.CYCLE and st.locks[0].state == Stations.REST and String(st.locks[1].said).contains("NORTHEAST LOCK"))
	_put(i1 + 60, 1)               # (off the pad: the lock lets go)
	st.step(0.1)
	_put(i1 + pad_sample, 1)       # stopped on it pointing away, having come from nowhere: no cycle, no landing
	st.step(0.1)
	st.step(0.1)
	_check("... and not one pointing away from it that has not come through the tube", st.locks[1].state == Stations.REST)

	# ---- landing
	_put(i1 - 3, 1, 900.0)
	st.step(0.05)
	st.trip = {"from": 0, "t0": float(sim.time) - 172.0, "top": 9950.0}
	for k in 30:
		for sub in 2:
			sim.step({"thrL": 0.0, "thrR": 0.0, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": true}, 1.0 / 240.0)
		st.step(1.0 / 120.0)
	_check("a craft that comes out through the northeast seal has ended its run (%s)" % st.arrival, not st.arrival.is_empty() and int(st.arrival.lock) == 1 and int(st.arrival.from) == 0
		and absf(float(st.arrival.seconds) - 172.25) < 1.0 and st.trip.is_empty())
	_put(i1 + pad_sample, 1)
	st.step(0.1)
	st.step(0.1)
	var told := String(st.locks[1].told)
	var bar: Vector3 = st.locks[1].pad.get_shader_parameter("state")
	_check("stopped on the pad it has landed: the bar green, a chime, and the board beyond the pad says \"%s\"" % told.replace("\n", " / "),
		st.locks[1].state == Stations.LANDED and bar.y > 0.9 and told.contains("ARRIVED") and told.contains("NORTHEAST LOCK") and told.contains("SOUTHWEST LOCK") and told.contains("768 KM")
		and told.contains("2 MIN 52 S") and told.contains("9,950 MPH"))
	_put(i1 + 60, 1, 200.0)
	st.step(0.1)
	_check("... and when it moves off the lock rests and the run is forgotten", st.locks[1].state == Stations.REST and st.arrival.is_empty() and String(st.locks[1].told).contains("STOP AT THE RED BAR"))

	# ---- guidance from inside
	var places := []
	var wrong := []
	for k in 2:
		var node: Node3D = st.locks[k].node
		var seen := {}
		for child in node.get_children():
			if child is Label3D and String(child.name).begins_with("Distance"):
				var km := int(String(child.text).split(" ")[0])
				seen[km] = int(seen.get(km, 0)) + 1
				var from_axis := Vector2(child.position.x, child.position.y - Tube.RADIUS).length()
				var says_brake := String(child.text).contains("BRAKE")
				if absf(child.position.z - (km * 1000.0 - Stations.BAR)) > 0.5 or from_axis < Tube.RADIUS + 60.0 or says_brake != (km <= Stations.BRAKE_KM) or child.double_sided:
					wrong.append([k, km, child.position])
		for km: float in Stations.BOARDS_KM:
			if int(seen.get(int(km), 0)) != 4:
				wrong.append([k, km, "seen %d times" % int(seen.get(int(km), 0))])
		places.append(seen.size())
	_check("each lock's distances stand at %s km before its bar, four times round the hull outside the glass, the ones from %d km in saying BRAKE (wrong: %s)" % [Stations.BOARDS_KM, int(Stations.BRAKE_KM), wrong.slice(0, 3)],
		wrong.is_empty() and places == [Stations.BOARDS_KM.size(), Stations.BOARDS_KM.size()])
	_check("what the brakes can do: %.2f km to stop from 5,000 mph, %.2f from 10,000; at 10,000 mph a craft 30 km out need not brake yet, at 20 km it must, at 9 km it cannot stop at the bar" % [Stations.stop_km(5000.0), Stations.stop_km(10000.0)],
		absf(Stations.stop_km(5000.0) - 5.95) < 0.01 and Stations.brake_state(10000.0, 30000.0) == 0 and Stations.brake_state(10000.0, 20000.0) == 1 and Stations.brake_state(10000.0, 9000.0) == 2
		and Stations.brake_state(300.0, 800.0) == 0 and Stations.brake_state(3000.0, 3000.0) == 2)
	# measured again: full air brakes from 6,000 mph inside the tube
	_put((i0 + i1) / 2, 1, 6000.0 * 0.44704)
	var x0 := Vector2(sim.pod.x, sim.pod.y)
	var steps := 0
	while steps < 240 * 40 and Vector2(sim.pod.vx, sim.pod.vy).length() > 0.9:
		sim.step({"thrL": 0.0, "thrR": 0.0, "brkL": 1.0, "brkR": 1.0, "repair": false, "reignite": true}, 1.0 / 240.0)
		steps += 1
	var took := Vector2(sim.pod.x, sim.pod.y).distance_to(x0) / 1000.0
	_check("... and the sim agrees: full air brakes from 6,000 mph stop it in %.2f km (%.1f s), the table says %.2f" % [took, steps / 240.0, Stations.stop_km(6000.0)],
		absf(took - Stations.stop_km(6000.0)) < 0.15 * Stations.stop_km(6000.0))
	var shown := []
	for case in [[60000.0, 0], [15000.0, 1], [5000.0, 2]]:
		_put(i1 - roundi((float(case[0]) - Stations.BAR) / float(R.len[i0])), 1, 10000.0 * 0.44704)
		st.step(0.05)
		var colour: Vector3 = st.locks[1].rings.get_shader_parameter("state")
		var run: float = st.locks[1].approach.get_shader_parameter("run")
		shown.append([st.braking, colour, run])
	_check("a craft coming at 10,000 mph is shown green 60 km out, amber at 15, red at 5 (the rings' colour and the strips running to the bar): %s" % [shown],
		shown[0][0] == 0 and shown[1][0] == 1 and shown[2][0] == 2 and (shown[0][1] as Vector3).y > 0.9 and (shown[2][1] as Vector3).x > 0.9 and (shown[2][1] as Vector3).y < 0.2
		and float(shown[0][2]) > 0.0 and st.locks[0].state == Stations.REST)

	# ---- nothing inside the bore, nothing low over the road's flat (each triangle is tried at its
	# corners, the middles of its sides and its own middle: a post is two long triangles)
	var inside := []
	var low := []
	var meshes := 0
	var triangles := 0
	var labels := 0
	var gate := {"posts": 0, "beam_low": INF, "top": 0.0, "near": INF}
	var gauge := {"low": INF, "near": INF, "far": 0.0}
	for k in 2:
		for child in (st.locks[k].node as Node3D).get_children():
			if child is Label3D:
				labels += 1
				var at: Vector3 = child.position
				if at.z < 0.0 and absf(at.x) < 100.0 and at.y < 40.0:
					low.append([child.name, at])
				continue
			if not child is MeshInstance3D:
				continue
			meshes += 1
			var mesh: Mesh = child.mesh
			for s in mesh.get_surface_count():
				var verts: PackedVector3Array = mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
				var index = mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX]
				var count: int = index.size() if index != null and index.size() > 0 else verts.size()
				triangles += count / 3
				for tri in count / 3:
					var c := []
					for e in 3:
						c.append(child.transform * verts[index[tri * 3 + e] if index != null and index.size() > 0 else tri * 3 + e])
					for p: Vector3 in [c[0], c[1], c[2], (c[0] + c[1]) * 0.5, (c[1] + c[2]) * 0.5, (c[2] + c[0]) * 0.5, (c[0] + c[1] + c[2]) / 3.0]:
						if p.z >= 0.0:
							if _in_bore(p):
								inside.append([child.name, p])
						elif absf(p.x) < flat and p.y > 0.5 and p.y < 40.0:
							low.append([child.name, p])
						if child.name == "PadMarks" and p.y > 1.0:
							gate.near = minf(float(gate.near), absf(p.x)) if p.y < 40.0 else float(gate.near)
							gate.top = maxf(float(gate.top), p.y)
							if absf(p.x) < flat:
								gate.beam_low = minf(float(gate.beam_low), p.y)
							var from_bar := absf(p.z + Stations.BAR)
							if from_bar > 1.3 and (absf(from_bar - Stations.PAD_HALF) > 1.0 or p.y > Stations.PYLON_HIGH + 0.01):
								gate.posts = -1000      # (neither the gate over the bar nor a pylon at an end of the pad)
							elif from_bar > 1.3:
								gate.posts = int(gate.posts) + 1
						if child.name == "PressureRing":
							var from_axis := Vector2(p.x, p.y - Tube.RADIUS).length()
							gauge.low = minf(float(gauge.low), p.y)
							gauge.near = minf(float(gauge.near), from_axis)
							gauge.far = maxf(float(gauge.far), from_axis)
	_check("nothing built is inside the bore (%s) or between half a metre and 40 m over the road's flat outside (%s): %d meshes of %d triangles and %d labels for the two locks" % [inside.slice(0, 2), low.slice(0, 2), meshes, triangles, labels],
		inside.is_empty() and low.is_empty() and meshes > 10 and labels == 70 and absf(float(st.locks[0].board.position.y) - 66.0) < 0.1)
	_check("over each bar a gate of light and a pylon at each corner of the pad: posts and pylons %.0f m from the road's middle, outside the flat (%.0f m), the beam from %.1f to %.1f m over the deck" % [float(gate.near), flat, float(gate.beam_low), float(gate.top)],
		float(gate.near) > flat and float(gate.near) < float(R.w[i0]) / 2.0 and float(gate.beam_low) > 40.0 and float(gate.top) <= Stations.GATE_HIGH + 0.01 and int(gate.posts) > 0)
	_check("the pressure gauge is an arc clear of the accumulators (%.0f to %.0f m from the axis; they reach 227) and all above the deck (its ends %.0f m up)" % [float(gauge.near), float(gauge.far), float(gauge.low)],
		float(gauge.near) > 230.0 and float(gauge.low) > 10.0)

	# ---- away from the line it costs nothing
	sim.respawn(0)
	st.step(0.1)
	st.step(0.1)
	_check("with the craft on another road both locks rest and nothing is worked out", st.locks[0].resting and st.locks[1].resting and st.braking == -1)
	print("AURORA STATIONS %s (%d checks, %d failures)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	v.free()
	quit(int(failures > 0))


## Is a point (a lock's own frame, z metres inside the seal) inside the tube's bore there, by more than a centimetre?
func _in_bore(p: Vector3) -> bool:
	var key := roundi(p.z * 100.0)
	if not _bores.has(key):
		var fold := smoothstep(0.0, Tube.APRON, p.z)
		var outline := PackedVector2Array()
		for j in 256:
			var a := TAU * j / 256.0
			outline.append(Tube.section(a, fold) + Tube.normal(a, fold) * 0.01)
		_bores[key] = outline
	var poly: PackedVector2Array = _bores[key]
	return Geometry2D.is_point_in_polygon(Vector2(p.x, p.y), poly)
