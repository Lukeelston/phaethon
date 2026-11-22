## The first minute of flying, coached (vr/flight_coach.gd; Luke, of the flight school: "launch it
## then add it"): its lines on their own (which comes up when, what clears it, when it says goodbye),
## then in a real cockpit (a taught flight hands the glass to it when the brake comes off; where the
## craft is across the road).
## --headless --xr-mode off --audio-driver Dummy -s res://tests/test_flight_coach.gd -- --mute
## Prints FLIGHT COACH PASS.
extends SceneTree

const View := preload("res://view/craft_view.gd")
const Cockpit := preload("res://vr/vr_cockpit.gd")
const Coach := preload("res://vr/flight_coach.gd")
const Sequence := preload("res://vr/startup_sequence.gd")
var failures := 0
var checks := 0
var state := {"mph": 0.0, "thr": [0.0, 0.0], "grip": [0.0, 0.0], "gear": 1, "top": false, "gears": true, "rpm": 0.2, "edge": 0.0, "crashed": false}


func _initialize() -> void:
	View.track_override = "network"
	View.job_override = "none"
	View.best_dir = OS.get_user_data_dir().path_join("test_flight_coach_")
	Cockpit.camera = "cockpit"
	Cockpit._camera_loaded = true      # the pilot's saved choices stay out of this
	Cockpit._nose_loaded = true
	Cockpit._slide_loaded = true
	Cockpit._startup_loaded = true
	Cockpit._map_loaded = true
	Cockpit._school_loaded = true
	Cockpit.cold_start = true
	Cockpit.school = true
	_run.call_deferred()


func _check(label: String, passed: bool) -> void:
	checks += 1
	print(("PASS " if passed else "FAIL ") + label)
	failures += int(not passed)


## Time passing for a coach with the state as it stands, changed by `with`.
func _fly(c, seconds: float, with := {}) -> void:
	for key in with:
		state[key] = with[key]
	var left := seconds
	while left > 1e-6:
		var dt := minf(left, 1.0 / 90.0)
		c.step(dt, state)
		left -= dt


func _lines(c) -> PackedStringArray:
	return c.message().split("\n")


func _logic() -> void:
	var c = Coach.new()
	_fly(c, 1.0)
	_check("a coach nobody began says nothing", not c.on and c.tip == "" and c.message() == "")
	c.begin()
	_fly(c, 1.0)
	_check("begun as the brake comes off, its first line is to go: \"%s\" / \"%s\" / \"%s\"" % [_lines(c)[0], _lines(c)[1], _lines(c)[2]],
		c.tip == "go" and _lines(c)[0].begins_with("GO  ") and _lines(c)[1].begins_with("BOTH TRIGGERS > ") and c.events.count("tip") == 1)
	_fly(c, 3.0, {"thr": [0.87, 0.3], "mph": 200.0})
	_check("one trigger in is not going", c.tip == "go" and not c.went)
	c.events.clear()
	_fly(c, Coach.GO_HOLD_S + 0.1, {"thr": [0.87, 0.87], "mph": 900.0})
	_check("both held in for two seconds: he has gone, the line clears with a tick (%s)" % [c.events], c.went and c.tip == "" and c.message() == "" and c.events.has("tip_ok"))
	# the gear runs out
	_fly(c, 0.3, {"mph": 1750.0, "rpm": 0.98})
	_check("on the limiter for a moment it says nothing yet", c.tip == "")
	_fly(c, Coach.REDLINE_S, {})
	_check("sat on it, it asks for a shift: \"%s\" / \"%s\" / \"%s\"" % [_lines(c)[0], _lines(c)[1], _lines(c)[2]], c.tip == "shift" and _lines(c)[0].begins_with("SHIFT UP  GEAR 1") and _lines(c)[1].begins_with("RIGHT STICK"))
	_fly(c, 0.5, {"rpm": 0.93})
	_check("... and keeps asking while the revs hunt under the limiter", c.tip == "shift")
	c.events.clear()
	_fly(c, 0.2, {"gear": 2, "rpm": 0.6})
	_check("the shift made, the line clears with a tick, and it is counted (%d)" % c.shifts, c.tip == "" and c.shifts == 1 and c.events.has("tip_ok"))
	_fly(c, 1.0, {"gear": 4, "top": true, "rpm": 1.2, "mph": 4000.0})
	_check("in top gear the revs past the mark ask for nothing", c.tip == "")
	# the wall coming
	_fly(c, 0.2, {"edge": 0.7})
	_check("drifting to the right wall, it says to steer left with the left grip: \"%s\" / \"%s\" / \"%s\"" % [_lines(c)[0], _lines(c)[1], _lines(c)[2]],
		c.tip == "left" and _lines(c)[0].begins_with("STEER LEFT") and _lines(c)[1].begins_with("LEFT GRIP > SQUEEZE GENTLY") and _lines(c)[2].begins_with("THE WALL IS ON YOUR RIGHT"))
	_fly(c, 0.3, {"grip": [1.0, 0.0]})
	_check("the grip crushed: \"%s\"" % _lines(c)[2], _lines(c)[2].begins_with("TOO HARD"))
	_fly(c, 0.3, {"grip": [0.0, 0.4]})
	_check("the wrong grip: \"%s\"" % _lines(c)[2], _lines(c)[2].begins_with("THE OTHER HAND: THE LEFT GRIP"))
	_fly(c, 0.3, {"grip": [0.4, 0.0], "edge": 0.5})
	_check("coming off the wall the line stays until he is well clear (no flicker at the mark)", c.tip == "left")
	c.events.clear()
	_fly(c, 0.2, {"edge": 0.2, "grip": [0.0, 0.0]})
	_check("clear of it: the line goes with a tick, one wall steered off", c.tip == "" and c.steers == 1 and c.events.has("tip_ok"))
	_fly(c, 0.2, {"edge": -0.7})
	_check("the left wall asks for the right grip: \"%s\"" % _lines(c)[1], c.tip == "right" and _lines(c)[1].begins_with("RIGHT GRIP") and _lines(c)[2].begins_with("THE WALL IS ON YOUR LEFT"))
	_fly(c, 0.2, {"edge": 0.0})
	# the power let go
	_fly(c, Coach.LIFT_S - 0.3, {"thr": [0.0, 0.0]})
	_check("a short lift is left alone", c.tip == "")
	_fly(c, 0.5, {})
	_check("the triggers out for a second and a half at speed: \"%s\" / \"%s\"" % [_lines(c)[0], _lines(c)[2]], c.tip == "power" and _lines(c)[2].begins_with("SLOW WITH THE GRIPS"))
	_fly(c, 0.2, {"thr": [0.87, 0.87]})
	_check("back in, it clears", c.tip == "")
	# a crash, and the end
	_fly(c, 0.2, {"edge": 0.9, "crashed": true})
	_check("in a crash it says nothing", c.tip == "" and c.message() == "")
	_fly(c, 0.2, {"crashed": false, "edge": 0.7})
	_fly(c, 0.2, {"edge": 0.1})
	_check("three walls steered off, the shifts made: it says goodbye (\"%s\")" % _lines(c)[0], c.steers == 3 and c.tip == "farewell" and _lines(c)[0].begins_with("SHE IS YOURS"))
	c.events.clear()
	_fly(c, Coach.FAREWELL_S + 0.2, {})
	_check("... and is done: nothing more on the glass (%s)" % [c.events], c.done and c.message() == "" and c.events.has("coached"))
	# a pilot who never touches a grip, and one who simply flies on
	var quiet = Coach.new()
	quiet.begin()
	state = {"mph": 2000.0, "thr": [0.87, 0.87], "grip": [0.0, 0.0], "gear": 4, "top": true, "gears": true, "rpm": 0.5, "edge": 0.0, "crashed": false}
	_fly(quiet, Coach.GO_HOLD_S + Coach.UNSTEERED_S + 0.5, {})
	_check("twelve seconds flying with no grip touched: \"%s\" / \"%s\"" % [_lines(quiet)[0], _lines(quiet)[2]], quiet.tip == "steer" and _lines(quiet)[1].begins_with("EITHER GRIP"))
	_fly(quiet, 0.3, {"grip": [0.0, 0.3]})
	_check("a squeeze, and it clears", quiet.tip == "" and quiet.squeezed)
	_fly(quiet, Coach.ENOUGH_S, {"grip": [0.0, 0.0]})
	_check("after %d s in the air it says goodbye whatever has been done" % int(Coach.ENOUGH_S), quiet.tip == "farewell" or quiet.done)
	_check("what it asks is what the school asked: a trigger past %.2f, a squeeze under %.2f" % [Coach.FULL_LEVER, Coach.TOO_HARD], Coach.FULL_LEVER == Sequence.FULL_LEVER and Coach.TOO_HARD == Sequence.TOO_HARD)


func _run() -> void:
	_logic()
	var prefs_before := FileAccess.get_file_as_string(Cockpit.PREFS) if FileAccess.file_exists(Cockpit.PREFS) else ""
	Cockpit.cold_on_entry = true
	var v = Cockpit.new()
	root.add_child(v)
	await process_frame
	v.set_process(false)
	var s = v.startup
	_check("a taught flight has the coach waiting, silent, while the school has the glass", s.school and v._coach_armed and not v.coach.on and v.coach.message() == "")
	s.flick("batt", 1)
	for k in 300:
		s.step(1.0 / 90.0, [0.0, 0.0], 1)
	s.flick("engine", 1)
	s.flick("engine", 1)
	for k in 150:
		s.step(1.0 / 90.0, [0.0, 0.0], 1)
	s.press_start()
	for k in 420:
		s.step(1.0 / 90.0, [0.0, 0.0], 1)
	s.flick("park", -1)
	s.step(1.0 / 90.0, [0.0, 0.0], 1)
	v._apply_startup(0.0)
	_check("the brake off (the lessons walked out of or not): the coach is on", v.coach.on and not v._coach_armed and s.cleared)
	v.inp = {"thrL": 0.0, "thrR": 0.0, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": false}
	for k in int((Sequence.CLEARED_S + 0.5) * 90.0):
		s.step(1.0 / 90.0, [0.0, 0.0], 1)
	v._coach_step(1.0 / 90.0, [0.0, 0.0])
	var strip: String = v._hud_progress(true)
	_check("once CLEARED has gone from the glass the coach's first line is on it and on the instrument strip: \"%s\" (strip: \"%s\")" % [v.approach_display.message.replace("\n", " / "), strip.replace("\n", " / ")],
		v.approach_display.message.begins_with("GO  ") and strip.begins_with("GO"))
	# where she is across the road
	var R = v.sim.roads[v.sim.pod.path]
	var i: int = v.sim.pod.hint
	var middle := Vector2(R.px[i], R.py[i])
	var left := Vector2(R.nx[i], R.ny[i])
	var along := Vector2(R.tx[i], R.ty[i])
	var seen := []
	for case in [[0.0, 1.0], [-0.35, 1.0], [0.35, 1.0], [0.35, -1.0]]:      # m left of the middle as a share of the width, and which way she points
		v.sim.pod.x = middle.x + left.x * float(case[0]) * float(R.w[i])
		v.sim.pod.y = middle.y + left.y * float(case[0]) * float(R.w[i])
		v.sim.pod.th = atan2(along.y * float(case[1]), along.x * float(case[1]))
		seen.append(snappedf(v._across_road(), 0.01))
	_check("across the road: in the middle 0, 35%% of the width right of it +0.7, left of it -0.7, and the same place flown the other way is on her right again (%s)" % [seen],
		absf(seen[0]) < 0.02 and absf(seen[1] - 0.7) < 0.02 and absf(seen[2] + 0.7) < 0.02 and absf(seen[3] - 0.7) < 0.02)
	v.queue_free()
	await process_frame
	if prefs_before == "":
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Cockpit.PREFS))
	else:
		var out := FileAccess.open(Cockpit.PREFS, FileAccess.WRITE)
		out.store_string(prefs_before)
		out.close()
	print("FLIGHT COACH %s (%d checks, %d failures)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)
