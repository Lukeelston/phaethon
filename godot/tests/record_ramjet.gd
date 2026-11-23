## The ramjet, heard: the cockpit flown on the range in real time through the burner, the ramjet, the held
## boost and back, so the engine's movie writer records what the game itself plays (engines, wind and field,
## mixed as a pilot gets them). The picture is the seat's, small; the sound is the point. Run windowed:
## --xr-mode off --resolution 320x180 --fixed-fps 120 --write-movie FILE.avi
## -s res://tests/record_ramjet.gd -- --out=DIR [--plan=run|hold] [--from=MPH] [--mph=MPH] [--solo=ramjet]
## and take the sound out of the film (ffmpeg -i FILE.avi -vn FILE.wav). No --mute.
## The craft is flown as the headset's trigger scheme flies it (input/quest_controls.gd's own gearbox, fourth
## gear, both triggers fully in, the burner lit from the left stick, the levers under the gate), because that
## is what the engines' voices hear in a flight: the gear's revs, not the levers.
##   --plan=run   one flight: held at --from (3,000 mph) in fourth gear dry and then on the burner; from the
##                moment the ramjet is armed the speed is the sim's own (fourth has no top speed: it climbs for as
##                long as it is held); the boost held three seconds, disarmed, the burner out.
##   --plan=hold  the same stages with the craft's speed pinned at --mph each frame, for measuring the mix's
##                loudness at one speed (the sim still steps: mode, boost and the gearbox are its own).
## REC lines give the time of each stage from the start of the film's sound; RECT lines the speed, the mode
## and the ramjet voice's state four times a second.
extends SceneTree

const Seat := preload("res://vr/vr_cockpit.gd")
const Quest := preload("res://input/quest_controls.gd")
const STEP := 1.0 / 120.0
const METERS := ["Master", "Engines", "EngineL", "EngineR", "EngineL_pops", "Wind", "Field"]

var _peaks := {}
var seat
var quest
var out_dir := ""
var plan := "run"
var from_mph := 3000.0
var pin_mph := -1.0
var clock := 0.0          # seconds of film
var frames := 0
var burner_want := false
var boosting := false
var _flick := 0.0


func _initialize() -> void:
	_run.call_deferred()


func _mph() -> float:
	var b = seat.sim.pod
	return sqrt(b.vx * b.vx + b.vy * b.vy) * 2.23694


func _set_speed(mph: float) -> void:
	for body in seat.sim.bodies:
		body.vx = mph * 0.44704
		body.vy = 0.0


## One frame, flown as the trigger scheme flies it (vr/vr_cockpit.gd _read_input's own mapping).
func _tick() -> void:
	var sim = seat.sim
	var v: float = sqrt(sim.pod.vx * sim.pod.vx + sim.pod.vy * sim.pod.vy)
	var c := {"lt": 1.0, "rt": 1.0, "lg": 0.0, "rg": 0.0, "ls": Vector2.ZERO, "rs": Vector2.ZERO,
		"speed": v, "airspeed": v / sim.line_speed(), "yaw": (sim.eL.w + sim.eR.w) / 2.0, "sf": sim.hblend}
	_flick = maxf(0.0, _flick - STEP)
	if quest.burner != burner_want and _flick <= 0.0:      # the left stick flicked: up lights the burner, down puts it out
		c.ls = Vector2(0.0, 1.0 if burner_want else -1.0)
		_flick = 0.3
	var q: Dictionary = quest.update(c, STEP)
	var inp := {"thrL": q.thrL, "thrR": q.thrR, "brkL": q.brkL, "brkR": q.brkR, "repair": false, "reignite": false,
		"burner": bool(q.get("burner", false)), "thrMul": q.get("mul", 1.0), "gearRpm": q.get("rpm", 0.0),
		"gearIndex": quest.gear, "gearOverdrive": bool(q.get("overdrive", false))}
	if boosting:
		inp["boost"] = true
	seat.inp = inp
	seat._process(STEP)
	if pin_mph > 0.0:
		_set_speed(pin_mph)
	for name: String in METERS:      # each bus's tallest peak since the last line (dB; a bus's meter is read after its effects)
		var bus := AudioServer.get_bus_index(name)
		if bus >= 0:
			_peaks[name] = maxf(float(_peaks.get(name, -99.0)), maxf(AudioServer.get_bus_peak_volume_left_db(bus, 0), AudioServer.get_bus_peak_volume_right_db(bus, 0)))
	if frames % 30 == 0:
		var ea = seat.engine_audio
		var voice := ""
		if ea != null and ea.has_method("ram_state"):
			voice = "  voice %s" % [ea.ram_state()]
		var meters := PackedStringArray()
		for name: String in METERS:
			meters.append("%s %.1f" % [name, float(_peaks.get(name, -99.0))])
		_peaks.clear()
		print("RECT %.2f s: %.0f mph, %s%s, gear %d revs %.2f, %.1f km%s" % [clock, _mph(), sim.mode, " +boost x%d" % sim.boost if sim.boost > 0 else "",
			quest.gear, float(q.get("rpm", 0.0)), sim.pod.x / 1000.0, voice])
		print("RECB %.2f s: %s" % [clock, ", ".join(meters)])
	frames += 1
	clock += STEP
	await process_frame


func _for(seconds: float, what: String) -> void:
	print("REC %.2f s: %s (%.0f mph)" % [clock, what, _mph()])
	for f in roundi(seconds / STEP):
		await _tick()


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
		if arg.begins_with("--plan="):
			plan = arg.trim_prefix("--plan=")
		if arg.begins_with("--from="):
			from_mph = float(arg.trim_prefix("--from="))
		if arg.begins_with("--mph="):
			pin_mph = float(arg.trim_prefix("--mph="))
	if out_dir.is_empty() or DirAccess.make_dir_recursive_absolute(out_dir) != OK:
		push_error("Pass --out= and a writable directory.")
		quit(1)
		return
	if plan == "hold" and pin_mph <= 0.0:
		push_error("--plan=hold wants --mph=.")
		quit(1)
		return
	if plan != "hold":
		pin_mph = from_mph        # (let go when the ramjet is armed)
	Seat._nose_loaded = true        # (the pilot's saved choices stay out of it)
	Seat._camera_loaded = true
	Seat._startup_loaded = true
	Seat.camera = "cockpit"
	Seat.track_override = "range"
	Seat.job_override = "none"
	Seat.cold_on_entry = false
	Seat.best_dir = out_dir.path_join("review_")
	seat = Seat.new()
	root.add_child(seat)
	seat.set_process(false)
	seat.cruise = 0.0
	if root.use_xr or seat.engine_audio == null or seat.wind_audio == null:
		push_error("This needs a monoscopic viewport and sound (no --mute).")
		quit(1)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--solo="):      # one of the engines' layers alone ("ramjet": its voice), the wind and the field muted
			seat.engine_audio.solo = arg.trim_prefix("--solo=")
			for bus: String in ["Wind", "Field", "Boom"]:
				if AudioServer.get_bus_index(bus) >= 0:
					AudioServer.set_bus_mute(AudioServer.get_bus_index(bus), true)
	quest = Quest.new()
	quest.set_gear(Quest.GEARS.size() - 1)
	_set_speed(pin_mph if pin_mph > 0.0 else from_mph)
	# the lead-in: the engines spool, the second engine catches, the field seals, the turbines come in (not part of
	# the recording's count). A hold is on the burner before it begins, so its first stretch is a settled one.
	burner_want = plan == "hold"
	for f in roundi((8.0 if plan == "hold" else 4.0) / STEP):
		await _tick()
	print("REC_BEGIN %.3f" % clock)
	var zero := clock
	clock = 0.0
	frames = 0
	if plan == "hold":
		# (stages long enough to measure through the engines' own slow beat: twin engines a third of a percent
		# apart swing the mix's low end 2 dB every three seconds or so)
		await _for(7.0, "the burner, speed pinned at %.0f mph" % pin_mph)
		seat.sim.armed = true
		await _for(9.0, "the ramjet armed")
		boosting = true
		await _for(5.0, "the boost held")
		boosting = false
		await _for(2.0, "the boost let go")
		seat.sim.armed = false
		await _for(7.0, "disarmed: the burner again")
	else:
		await _for(2.0, "fourth gear, both triggers in, no burner, held at %.0f mph" % from_mph)
		burner_want = true
		await _for(5.0, "the burner lit, still held at %.0f mph" % from_mph)
		seat.sim.armed = true
		pin_mph = -1.0
		await _for(18.0, "the ramjet armed, and held: the speed is the sim's own from here")
		boosting = true
		await _for(3.0, "the boost held")
		boosting = false
		await _for(3.0, "the boost let go")
		seat.sim.armed = false
		await _for(4.0, "disarmed: the burner again")
		burner_want = false
		await _for(2.0, "the burner out")
	print("REC %.2f s: end (%.0f mph, %.1f km run)" % [clock, _mph(), seat.sim.pod.x / 1000.0])
	print("REC_END %.3f" % (zero + clock))
	seat.free()
	quit()
