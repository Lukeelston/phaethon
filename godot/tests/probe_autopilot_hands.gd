## The autopilot's hands, measured (Luke: "Autopilot works, but definitely runs like a computer running
## it - very jumpy."): the same drives test_autopilot.gd flies, with what it gives the sim logged every
## frame and summed up by tests/hand_meter.gd.
##   --mode=sim       the bare sim, the pilot asked --hz times a second (60, as the test; 90, a headset's)
##   --mode=cockpit   the VR cockpit with nobody's hands on her, whole frames (run it with
##                    --fixed-fps 90): the gearbox, the MODE switch's cooldown, the Network's own traffic
##   --drives=hold2400,hold1200,route,pass,wall,fast    which (all but fast by default)
##        hold2400, hold1200   N3 from sample 400, for Glacier, three minutes
##        route                standing in Eridanus, for Basalt, nudged up to 4,250 mph, seven minutes
##        route2               the same for Glacier, five minutes (the other way out of Eridanus, by N3)
##        pass, wall           (sim) a 300 mph vehicle on its line at 2,400; a wall of them at 2,000
##        fast                 taken at 3,100 mph on N3 with 3,200 asked, a minute (flight 18's way in)
##   --out=DIR --label=before  a CSV a drive (DIR/<label>-<mode><hz>-<drive>.csv) and the summary
##   --every=N                 a CSV row every N frames (1)
## --headless --xr-mode off --audio-driver Dummy [--fixed-fps 90] -s res://tests/probe_autopilot_hands.gd -- --mute --mode=sim --out=...
extends SceneTree

const CraftSimScript := preload("res://sim/craft_sim.gd")
const Autopilot := preload("res://view/autopilot.gd")
const View := preload("res://view/craft_view.gd")
const Cockpit := preload("res://vr/vr_cockpit.gd")
const HandMeter := preload("res://tests/hand_meter.gd")
const DT := 1.0 / 480.0
const MPH := 2.236936
const G := 9.81

var out_dir := ""
var label := "run"
var mode := "sim"
var hz := 60
var every := 1
var summary: Array[String] = []


func _arg(name: String, fallback: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--" + name + "="):
			return a.trim_prefix("--" + name + "=")
	return fallback


func _initialize() -> void:
	View.track_override = "network"
	View.job_override = "none"
	View.best_dir = OS.get_user_data_dir().path_join("probe_autopilot_hands_")
	out_dir = _arg("out", "")
	label = _arg("label", "run")
	mode = _arg("mode", "sim")
	hz = int(_arg("hz", "60" if mode == "sim" else "90"))
	every = maxi(1, int(_arg("every", "1")))
	if out_dir != "":
		DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _city(sim, name: String) -> int:
	for k in sim.cities.size():
		if String(sim.cities[k].name) == name:
			return k
	return -1


func _road(sim, name: String) -> int:
	for r in sim.roads.size():
		if String(sim.roads[r].name) == name:
			return r
	return -1


func _next_city(sim, from: int) -> int:
	var best := -1
	var bd := INF
	for k in sim.cities.size():
		if k == from:
			continue
		var d := Vector2(sim.cities[k].cx - sim.pod.x, sim.cities[k].cy - sim.pod.y).length()
		if d < bd:
			bd = d
			best = k
	return best


## Where a drive starts and what is asked of it.
func _setup(drive: String, sim) -> Dictionary:
	match drive:
		"hold2400", "hold1200":
			sim.respawn_on(_road(sim, "N3"), 400, 1)
			return {"city": _city(sim, "GLACIER"), "mph": 2400.0 if drive == "hold2400" else 1200.0, "secs": 180.0, "nudges": 0}
		"route":
			var e: Dictionary = sim.cities[_city(sim, "ERIDANUS")]
			sim.respawn_on(int(e.road), int(e.i), 1)
			sim.net.from = _city(sim, "ERIDANUS")      # (she is there: crossing its terminal on the way out is no arrival)
			return {"city": _city(sim, "BASALT"), "mph": 0.0, "secs": 420.0, "nudges": 7}
		"route2":
			var e2: Dictionary = sim.cities[_city(sim, "ERIDANUS")]
			sim.respawn_on(int(e2.road), int(e2.i), 1)
			sim.net.from = _city(sim, "ERIDANUS")
			return {"city": _city(sim, "GLACIER"), "mph": 0.0, "secs": 300.0, "nudges": 7}
		"pass":
			sim.respawn_on(_road(sim, "N3"), 400, 1)
			return {"city": _city(sim, "GLACIER"), "mph": 2400.0, "secs": 80.0, "nudges": 0, "cars_at": 40.0, "cars_ahead": 220, "span": 0}
		"wall":
			sim.respawn_on(_road(sim, "N3"), 400, 1)
			return {"city": _city(sim, "GLACIER"), "mph": 2000.0, "secs": 130.0, "nudges": 0, "cars_at": 40.0, "cars_ahead": 600, "span": 8}
		"fast":
			var road := _road(sim, "N3")
			sim.respawn_on(road, 400, 1)
			var R = sim.roads[road]
			var v := 3100.0 / MPH
			for b in sim.bodies:
				b.vx = R.tx[400] * v
				b.vy = R.ty[400] * v
			return {"city": _city(sim, "GLACIER"), "mph": 3200.0, "secs": 60.0, "nudges": 0}
	return {}


func _header() -> String:
	return "t,mph,thrL,thrR,brkL,brkR,lat_g,lon_g,yaw_dps,off_m,lane_m,status,handling,gear,want_mph,near_m,near_mph,near_ahead_m,near_left_m,cap_mph\n"


## The nearest vehicle to the pod: [m off, its mph, m ahead of her along her travel, m to her left], or [-1, 0, 0, 0].
func _nearest_car(sim, cars: Array) -> Array:
	var best := INF
	var out := [-1.0, 0.0, 0.0, 0.0]
	var v := Vector2(sim.pod.vx, sim.pod.vy)
	var along := v.normalized() if v.length() > 1.0 else Vector2(cos(sim.pod.th), sin(sim.pod.th))
	for c in cars:
		var d := Vector2(c.x - sim.pod.x, c.y - sim.pod.y)
		if d.length_squared() < best:
			best = d.length_squared()
			out = [d.length(), float(c.v) * MPH, d.dot(along), along.x * d.y - along.y * d.x]
	return out


class Trace:
	var file: FileAccess
	var every := 1
	var n := 0
	var v := Vector2.ZERO
	var have := false

	func row(t: float, dt: float, thr_l: float, thr_r: float, brk_l: float, brk_r: float, sim, a, handling: String, gear: int, near: Array) -> void:
		var vel := Vector2(sim.pod.vx, sim.pod.vy)
		var lat := 0.0
		var lon := 0.0
		if have and v.length() > 1.0 and dt > 0.0:
			var along := v.normalized()
			var acc := (vel - v) / dt
			lat = (along.x * acc.y - along.y * acc.x) / 9.81
			lon = along.dot(acc) / 9.81
		v = vel
		have = true
		n += 1
		if file == null or n % every != 0:
			return
		var R = sim.roads[sim.pod.path]
		var i := clampi(int(sim.pod.hint), 0, int(R.N) - 1)
		var off: float = (sim.pod.x - R.px[i]) * R.nx[i] + (sim.pod.y - R.py[i]) * R.ny[i]
		var want: float = a.vplan[mini(a.vplan.size() - 1, a.at)] * 2.236936 if a.vplan.size() > 0 else 0.0
		file.store_string("%.4f,%.1f,%.4f,%.4f,%.4f,%.4f,%.3f,%.3f,%.3f,%.2f,%.1f,%s,%s,%d,%.0f,%.0f,%.0f,%.0f,%.0f,%.0f\n" % [
			t, vel.length() * 2.236936, thr_l, thr_r, brk_l, brk_r, lat, lon, rad_to_deg((sim.eL.w + sim.eR.w) / 2.0), off, a.lane, a.status, handling, gear, want,
			near[0], near[1], near[2], near[3], minf(a.lane_cap * 2.236936, 99999.0)])


func _open(drive: String) -> Trace:
	var tr := Trace.new()
	tr.every = every
	if out_dir != "":
		tr.file = FileAccess.open(out_dir.path_join("%s-%s%d-%s.csv" % [label, mode, hz, drive]), FileAccess.WRITE)
		if tr.file:
			tr.file.store_string(_header())
	return tr


func _report(drive: String, m, extra: String) -> void:
	var s: Dictionary = m.stats()
	var head := "HANDS %s %s%d %s: %s" % [label, mode, hz, drive, extra]
	print(head)
	print(m.text())
	summary.append(head)
	summary.append(m.text())
	var keys := ["lever_rate", "brake_rate", "lever_rev", "lever_quick", "brake_rev", "brake_quick", "steer_rev", "steer_quick", "steer_med", "steer_90", "full", "part", "braking", "brake_med",
		"lat_g", "lat_jerk", "lat_jerk95", "lat_jerk99", "lon_jerk95", "lon_jerk99", "lon_g_min", "wag10", "wag_rms", "lane_n", "handling_n", "gear_n"]
	var parts := []
	for k in keys:
		parts.append("%s=%.4f" % [k, float(s[k])])
	var line := "HANDSROW %s %s%d %s %s" % [label, mode, hz, drive, " ".join(parts)]
	print(line)
	summary.append(line)


# ---- the bare sim ----

func _sim_drive(drive: String) -> void:
	var sim = CraftSimScript.new({"track": "network", "handling": "speed"})
	var plan := _setup(drive, sim)
	var a = Autopilot.new()
	var city: int = plan.city
	var took: bool = a.engage(sim, city)
	if float(plan.mph) > 0.0:
		a.set_cruise(float(plan.mph) / MPH)
	for k in int(plan.nudges):
		a.nudge(1)
	var m = HandMeter.new()
	var tr := _open(drive)
	var frame := 1.0 / hz
	var acc := 0.0
	var t := 0.0
	var hits := 0
	var arrivals := []
	var cars := []
	var lane_was := 0.0
	var ask_was := ""
	var mph_lo := INF
	var mph_hi := 0.0
	var off_most := 0.0
	var nearest := INF
	var given_back := ""
	while t < float(plan.secs):
		if plan.has("cars_at") and t >= float(plan.cars_at) and cars.is_empty():
			var CR = sim.roads[sim.pod.path]
			var ci := clampi(int(sim.pod.hint) + int(plan.cars_ahead) * Autopilot.way(sim), 0, int(CR.N) - 1)
			var w := float(Autopilot.way(sim))
			for k in range(-int(plan.span), int(plan.span) + 1):
				cars.append({"x": CR.px[ci] + CR.nx[ci] * k * 22.0, "y": CR.py[ci] + CR.ny[ci] * k * 22.0, "v": 300.0 / MPH, "hx": CR.tx[ci] * w, "hy": CR.ty[ci] * w})
		var u: Dictionary = a.fly(sim, city, cars, frame)
		if u.is_empty():
			given_back = a.why_off
			break
		if absf(a.lane - lane_was) > 10.0:
			m.note("lane")
		lane_was = a.lane
		if ask_was != "" and String(u.handling) != ask_was:
			m.note("handling")
		ask_was = String(u.handling)
		var inp := {"thrL": u.thrL, "thrR": u.thrR, "brkL": u.brkL, "brkR": u.brkR, "repair": false, "reignite": true, "handling": u.handling}
		acc += frame
		var steps := int(floor(acc / DT + 1e-9))
		acc -= steps * DT
		for k in steps:
			sim.step(inp, DT)
			for e in sim.events:
				match String(e.type):
					"hit", "scrape", "smash":
						hits += 1
					"arrive":
						arrivals.append("%s at %.0f s" % [sim.cities[int(e.city)].name, float(e.t)])
						city = _next_city(sim, int(e.city))
			sim.events.clear()
		var dt := steps * DT
		t += dt
		for c in cars:
			c.x += c.v * c.hx * dt
			c.y += c.v * c.hy * dt
			nearest = minf(nearest, Vector2(c.x - sim.pod.x, c.y - sim.pod.y).length())
		m.add(dt, u.thrL, u.thrR, u.brkL, u.brkR, sim)
		tr.row(t, dt, u.thrL, u.thrR, u.brkL, u.brkR, sim, a, String(u.handling), 0, _nearest_car(sim, cars))
		if t >= 45.0:
			var mph := Vector2(sim.pod.vx, sim.pod.vy).length() * MPH
			mph_lo = minf(mph_lo, mph)
			mph_hi = maxf(mph_hi, mph)
			var R = sim.roads[sim.pod.path]
			var i := clampi(int(sim.pod.hint), 0, int(R.N) - 1)
			off_most = maxf(off_most, absf((sim.pod.x - R.px[i]) * R.nx[i] + (sim.pod.y - R.py[i]) * R.ny[i] - a.lane))
	_report(drive, m, "took %s, %.0f s, %d wall contacts, arrivals %s, %.0f to %.0f mph after 45 s, most %.1f m off its line, nearest vehicle %.0f m%s" % [
		took, t, hits, arrivals, mph_lo, mph_hi, off_most, nearest, (", GIVEN BACK: " + given_back) if given_back != "" else ""])


# ---- the cockpit ----

func _cockpit_drive(drive: String) -> void:
	Cockpit.camera = "cockpit"
	Cockpit._camera_loaded = true
	Cockpit._startup_loaded = true
	Cockpit.cold_start = false
	Cockpit.cold_on_entry = false
	Cockpit._school_loaded = true
	Cockpit.school = false
	Cockpit._options_loaded = true
	Cockpit.consumables = false
	Cockpit.power_ups_on = false
	# (a slate of its own: the view saves the city it last arrived at and what it has found, and starts the next
	# flight there with another target)
	var slate := "probe_hands_%s_%s_%d_" % [label, drive, Time.get_ticks_usec()]
	View.best_dir = OS.get_user_data_dir().path_join(slate)
	var c = Cockpit.new()
	root.add_child(c)
	await process_frame
	c.set_process(false)
	var sim = c.sim
	var plan := _setup(drive, sim)
	c.net_target = int(plan.city)
	if drive == "fast":      # as a pilot would have her: top gear, both levers in
		c.quest.set_gear(4)
		c.quest.rpm = 0.7
		c.inp.thrL = 0.87
		c.inp.thrR = 0.87
	var took: bool = c.set_autopilot(true)
	var a = c.autopilot
	if float(plan.mph) > 0.0:
		a.set_cruise(float(plan.mph) / MPH)
	for k in int(plan.nudges):
		a.nudge(1)
	var m = HandMeter.new()
	var tr := _open(drive)
	var t := 0.0
	var t_sim: float = sim.time
	var lane_was := 0.0
	var ask_was := String(c.handling_ask)
	var gear_was: int = c.quest.gear
	var mph_lo := INF
	var mph_hi := 0.0
	var off_most := 0.0
	var gears := {}
	var frames := 0
	var frame := 1.0 / hz
	var nearest := INF         # the least a vehicle came to the pod
	var close := 0             # frames with one within 12 m (a vehicle is some 9 m wide: inside one, were it solid)
	var walls := 0             # wall contacts: a body's contact flag going up (the view keeps the sim's events to itself)
	var touching := false
	c.set_process(true)        # the engine's own frames from here (--fixed-fps: each is 1/hz s)
	while t < float(plan.secs) and a.on:
		await process_frame
		var now: float = sim.time
		var dt := now - t_sim
		if dt < 0.0:           # (a restart: the sim's clock began again)
			dt = frame
		t_sim = now
		t += frame
		frames += 1
		if absf(a.lane - lane_was) > 10.0:
			m.note("lane")
		lane_was = a.lane
		if String(c.handling_ask) != ask_was:
			m.note("handling")
		ask_was = String(c.handling_ask)
		if c.quest.gear != gear_was:
			m.note("gear")
		gear_was = c.quest.gear
		gears[gear_was] = float(gears.get(gear_was, 0.0)) + frame
		var inp: Dictionary = c.inp
		if dt > 0.0:
			m.add(dt, inp.thrL, inp.thrR, inp.brkL, inp.brkR, sim)
		var near := _nearest_car(sim, c.traffic_net.cars if c.traffic_net else [])
		if float(near[0]) >= 0.0:
			nearest = minf(nearest, float(near[0]))
			close += int(float(near[0]) < 12.0)
		var touch := false
		for b in sim.bodies:
			touch = touch or b.contact[0] or b.contact[1]
		walls += int(touch and not touching)
		touching = touch
		tr.row(t, dt, inp.thrL, inp.thrR, inp.brkL, inp.brkR, sim, a, String(c.handling_ask), c.quest.gear, near)
		if t >= 45.0:
			var mph := Vector2(sim.pod.vx, sim.pod.vy).length() * MPH
			mph_lo = minf(mph_lo, mph)
			mph_hi = maxf(mph_hi, mph)
			var R = sim.roads[sim.pod.path]
			var i := clampi(int(sim.pod.hint), 0, int(R.N) - 1)
			off_most = maxf(off_most, absf((sim.pod.x - R.px[i]) * R.nx[i] + (sim.pod.y - R.py[i]) * R.ny[i] - a.lane))
	c.set_process(false)
	_report(drive, m, "took %s, %.0f s (%d frames), %.0f to %.0f mph after 45 s, most %.1f m off its line, %d wall contacts, s in each gear %s, the traffic %d vehicles (pass-through: OBSTACLE COLLISIONS off), the nearest one came %.0f m (%d frames with one within 12 m), still its own %s (%s)" % [
		took, t, frames, mph_lo, mph_hi, off_most, walls, gears, c.traffic_net.cars.size() if c.traffic_net else 0, nearest, close, a.on, a.why_off])
	c.set_autopilot(false)
	c.queue_free()
	await process_frame
	await process_frame
	for file in DirAccess.get_files_at(OS.get_user_data_dir()):
		if file.begins_with(slate):
			DirAccess.remove_absolute(OS.get_user_data_dir().path_join(file))


func _run() -> void:
	var prefs_before := FileAccess.get_file_as_string(Cockpit.PREFS) if FileAccess.file_exists(Cockpit.PREFS) else ""
	var drives := _arg("drives", "hold2400,hold1200,route,pass,wall" if mode == "sim" else "hold2400,hold1200,route").split(",")
	for drive in drives:
		if mode == "cockpit":
			await _cockpit_drive(drive)
		else:
			_sim_drive(drive)
	if mode == "cockpit":
		if prefs_before == "":
			DirAccess.remove_absolute(ProjectSettings.globalize_path(Cockpit.PREFS))
		else:
			var out := FileAccess.open(Cockpit.PREFS, FileAccess.WRITE)
			out.store_string(prefs_before)
			out.close()
	if out_dir != "":
		var f := FileAccess.open(out_dir.path_join("%s-%s%d-summary.txt" % [label, mode, hz]), FileAccess.WRITE)
		if f:
			f.store_string("\n".join(summary) + "\n")
	print("HANDS DONE")
	quit(0)
