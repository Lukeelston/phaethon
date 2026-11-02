## Ride gate (Luke: "going over hills makes the camera very shaky, and there are quick elevation
## changes that are just too intense for the sport"): the autopilot's Eridanus lap
## (tests/replay/eridanus_*.json) replayed through the sim, the cockpit's ride (CraftModel.ride,
## what the headset's camera rides) read every 1/60 s frame and set against the old one (the
## surface's slope over a fixed 4 m: the 12 m polyline's joints twitched it at speed).
##   jitter      the pitch's frame-to-frame wobble (its second difference) at speed: a fraction of
##               the old, and tiny
##   on the road the cockpit never sinks below the surface
##   gentle      the steepest the nose ever points up or down, and the fastest it climbs or drops
## Then the emergency run home by the shade line (tests/replay/job_shade_*.json), upside down under
## its canopy (CraftModel.onto_road carries the VR cockpit onto the twisted road):
##   jitter      the nose's wobble at speed, as above
##   on the road the cockpit's eye never comes nearer the road than 2 m along the road's normal,
##               turned over too
##   corkscrews  it rolls right over (180 deg) and back, never faster than 90 deg/s
## Prints RIDE PASS.
## Run: Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_ride.gd
extends SceneTree

const Sim := preload("res://sim/craft_sim.gd")
const CM := preload("res://view/craft_model.gd")
const DT := 1.0 / 480.0
const SUB := 8
const ASK := ["", "speed", "starfighter"]
const CHECKS := 8
const EYE := Vector3(0.0, 1.1, 0.0)   # the head over the cockpit's floor, seated
var fails := 0
var passed := 0


class View:
	var sim
	func surface(x: float, y: float) -> Vector2:
		return sim.surface_at(x, y, sim.pod.hint, sim.pod.path)


func _initialize() -> void:
	var inputs: Array = JSON.parse_string(FileAccess.get_file_as_string("res://tests/replay/eridanus_inputs.json"))
	var sim = Sim.new({"track": "eridanus"})
	var v := View.new()
	v.sim = sim
	var st := {}
	var fd := 1.0 / 60.0
	var old := PackedFloat64Array()
	var new := PackedFloat64Array()
	var fast := PackedByteArray()
	var sank := 0.0
	var worst_pitch := 0.0
	var worst_climb := 0.0
	var last_h := 0.0
	var frames := 0
	for u in inputs:
		var inp := {"thrL": u[0], "thrR": u[1], "brkL": u[2], "brkR": u[3], "repair": false, "reignite": true}
		if int(u[4]) > 0:
			inp["handling"] = ASK[int(u[4])]
		for k in SUB:
			sim.step(inp, DT)
		sim.events.clear()
		var spd: float = sqrt(sim.pod.vx * sim.pod.vx + sim.pod.vy * sim.pod.vy)
		old.append(CM.slope_pitch(v, sim.pod.x, sim.pod.y, sim.pod.th, 2.0))
		var r := CM.ride(v, sim, st, fd)
		new.append(r.y)
		fast.append(1 if spd > 1000.0 / 2.236936 else 0)
		sank = maxf(sank, v.surface(sim.pod.x, sim.pod.y).x - r.x)
		worst_pitch = maxf(worst_pitch, absf(r.y))
		if frames > 0:
			worst_climb = maxf(worst_climb, absf(r.x - last_h) / fd)
		last_h = r.x
		frames += 1
	var jo := _jitter(old, fast)
	var jn := _jitter(new, fast)
	print("  (%d frames, %d over 1,000 mph)" % [frames, Array(fast).count(1)])
	_check("jitter at speed: the nose wobbles %.4f deg rms frame to frame (the old fixed 4 m read: %.4f), worst %.3f deg (old %.3f)" % [jn[0], jo[0], jn[1], jo[1]],
		jn[0] < 0.01 and jn[0] < jo[0] / 5.0 and jn[1] < 0.1)
	_check("on the road: the cockpit never sinks below the surface (worst %.4f m)" % sank, sank < 0.001)
	_check("gentle: the nose never points more than %.2f deg up or down over the banking" % rad_to_deg(worst_pitch), rad_to_deg(worst_pitch) < 4.0)
	_check("gentle: the cockpit never climbs or drops faster than %.1f ft/s" % (worst_climb * 3.28084), worst_climb * 3.28084 < 120.0)
	_shade_lap()
	var good: bool = fails == 0 and passed == CHECKS
	print("RIDE ", "PASS" if good else "FAIL (%d failed, %d of %d passed)" % [fails, passed, CHECKS])
	quit(0 if good else 1)


## The emergency run by the shade line, the VR cockpit's rig worked out as vr_cockpit.gd does it.
func _shade_lap() -> void:
	var inputs: Array = JSON.parse_string(FileAccess.get_file_as_string("res://tests/replay/job_shade_inputs.json"))
	var sim = Sim.new({"track": "eridanus", "job": "emergency"})
	var v := View.new()
	v.sim = sim
	var st := {}
	var fd := 1.0 / 60.0
	var pitch := PackedFloat64Array()
	var fast := PackedByteArray()
	var clear := INF
	var roll_max := 0.0
	var rate := 0.0
	var last_roll := 0.0
	var branch_frames := 0
	for f in inputs.size():
		var u: Array = inputs[f]
		var inp := {"thrL": u[0], "thrR": u[1], "brkL": u[2], "brkR": u[3], "repair": false, "reignite": true}
		if int(u[4]) > 0:
			inp["handling"] = ASK[int(u[4])]
		for k in SUB:
			sim.step(inp, DT)
		sim.events.clear()
		var spd: float = sqrt(sim.pod.vx * sim.pod.vx + sim.pod.vy * sim.pod.vy)
		var r := CM.ride(v, sim, st, fd)
		pitch.append(r.y)
		fast.append(1 if spd > 1000.0 / 2.236936 or sim.pod.path > 0 else 0)   # at speed, and all the way along the shade line
		if f > 0:
			rate = maxf(rate, absf(st.roll - last_roll) / fd)
		last_roll = st.roll
		if sim.pod.path > 0:
			branch_frames += 1
			roll_max = maxf(roll_max, st.roll)
			var yaw: float = sim.pod.th - PI / 2.0
			var floor_flat := Vector3(sim.pod.x, sim.pod.z - 0.8 + CM.POD_LIFT, -sim.pod.y)
			var flat := Transform3D(Basis.from_euler(Vector3(0.0, yaw, 0.0)), floor_flat)
			var rig := CM.onto_road(sim, flat, floor_flat, st.roll, r.y, 0.0, 0.0)
			var road := CM.road_xf(sim, sim.pod.x, sim.pod.y, 0.0, 0.0)
			var nrm: Vector3 = road.basis * Vector3.UP
			clear = minf(clear, (rig * EYE - road * Vector3(sim.pod.x, 0.0, -sim.pod.y)).dot(nrm))
	var jn := _jitter(pitch, fast)
	print("  (the shade line: %d frames, %d on it)" % [inputs.size(), branch_frames])
	_check("shade line: the nose wobbles %.4f deg rms frame to frame at speed and along the line, worst %.3f deg" % [jn[0], jn[1]], jn[0] < 0.01 and jn[1] < 0.1)
	_check("shade line: the cockpit's eye never nearer the road than %.2f m along its normal, turned over too" % clear, branch_frames > 1000 and clear >= 2.0)
	_check("shade line: the corkscrews roll the cockpit right over (%.1f deg)" % rad_to_deg(roll_max), rad_to_deg(roll_max) > 179.5)
	_check("shade line: the roll never faster than %.1f deg/s (want <= 90)" % rad_to_deg(rate), rad_to_deg(rate) <= 90.0)


## The pitch's second difference (deg): rms and worst, over the frames flown fast.
func _jitter(a: PackedFloat64Array, fast: PackedByteArray) -> Array:
	var sq := 0.0
	var n := 0
	var worst := 0.0
	for i in range(1, a.size() - 1):
		if fast[i] == 0:
			continue
		var d := rad_to_deg(a[i + 1] - 2.0 * a[i] + a[i - 1])
		sq += d * d
		n += 1
		worst = maxf(worst, absf(d))
	return [sqrt(sq / maxf(n, 1)), worst]


func _check(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if ok:
		passed += 1
	else:
		fails += 1
