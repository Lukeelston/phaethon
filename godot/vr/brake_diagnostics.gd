## Opt-in, local brake investigation. No simulation writes; absent in ordinary runs.
## --brake-trace=ABSOLUTE_PATH records 10 Hz for five active minutes per flight.
extends RefCounted

var _file: FileAccess
var _elapsed := 0.0
var _sample_time := 0.0
var _flush_time := 0.0
var _steps := 0
var _contact_steps := [0, 0, 0]
var _min_grip := [1.0, 1.0, 1.0]


func open(path: String, track: String) -> void:
	if not path.is_absolute_path():
		push_warning("BRAKE TRACE: expected an absolute local path")
		return
	_file = FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	if _file == null:
		push_warning("BRAKE TRACE: could not open " + path)
		return
	_file.seek_end()
	_file.store_line(JSON.stringify({"event": "start", "schema": 1, "track": track,
		"utc": Time.get_datetime_string_from_system(true), "sample_hz": 10,
		"contact_source": "every physics step; body circle contact flags",
		"angles": "radians", "distances": "metres", "speed": "metres/second"}))
	_file.flush()
	print("BRAKE TRACE: ", path)


func observe_step(sim) -> void:
	if _file == null:
		return
	_steps += 1
	for i in sim.bodies.size():
		var b = sim.bodies[i]
		if b.contact[0] or b.contact[1]:
			_contact_steps[i] += 1
		_min_grip[i] = minf(_min_grip[i], b.grip)


func capture(view, delta: float) -> void:
	if _file == null:
		return
	_elapsed += delta
	_sample_time += delta
	_flush_time += delta
	if _sample_time < 0.1:
		return
	var sim = view.sim
	var bodies := []
	for b in sim.bodies:
		var road := {}
		if b.path >= 0 and b.path < sim.roads.size():
			var r = sim.roads[b.path]
			var i := clampi(b.hint, 0, r.N - 1)
			road = {"name": r.name, "sample": i, "width": r.w[i],
				"lateral": (b.x - r.px[i]) * r.nx[i] + (b.y - r.py[i]) * r.ny[i],
				"heading": atan2(r.ty[i], r.tx[i])}
		bodies.append({"position": [b.x, b.y, b.z], "velocity": [b.vx, b.vy, b.vz],
			"heading": b.th, "yaw_rate": b.w, "grip": b.grip, "contact": b.contact,
			"off_road": b.off_road, "deck_catch": b.lock, "road": road})
	var controllers := {}
	var partner := {}
	if view.partner:
		var p = view.partner
		partner = {"position": [p.x, p.y, p.z], "heading": p.th,
			"phase": p.maneuver, "ahead": p._ahead, "offset": p._offset}
	for side in view.hands:
		var hand: XRController3D = view.hands[side]
		controllers[side] = {"grip": hand.get_float("grip"), "trigger": hand.get_float("trigger"),
			"tracked": hand.get_has_tracking_data()}
	_file.store_line(JSON.stringify({"event": "sample", "elapsed": _elapsed, "sim_time": sim.time,
		"interval": _sample_time, "physics_steps": _steps, "contact_steps": _contact_steps,
		"min_grip": _min_grip, "controllers": controllers, "focused": view.hands_live,
		"awaiting_neutral": view._await_neutral_controls, "scheme": view.quest.scheme,
		"input": view.inp, "mode": sim.mode, "handling": sim.hblend,
		"gear": view.quest.gear, "pair_heading": sim.pair_th, "bodies_L_R_pod": bodies,
		"partner": partner}))
	_sample_time = 0.0
	_steps = 0
	_contact_steps = [0, 0, 0]
	_min_grip = [1.0, 1.0, 1.0]
	if _flush_time >= 1.0:
		_file.flush()
		_flush_time = 0.0
	if _elapsed >= 300.0:
		close("five minute limit")


func close(reason := "flight ended") -> void:
	if _file != null:
		_file.store_line(JSON.stringify({"event": "end", "elapsed": _elapsed, "reason": reason}))
		_file.close()
		_file = null
