## The run-up, taught (Luke, flying the fifteenth: "build a sort of 'tutorial' into the startup
## sequence. This is going to be a hard game for people to play first time, and i want to bring down
## the barrier to fun"): vr/startup_sequence.gd's lessons on their own (each passed only by doing
## it, in order; what the glass says; the plain run-up untouched), then in a real cockpit (a cold
## start is taught for a pilot who has not passed, the brake needles and the engines' air brakes
## follow the hands in the grip lessons, passing is remembered).
## --headless --xr-mode off --audio-driver Dummy -s res://tests/test_flight_school.gd -- --mute
## Prints FLIGHT SCHOOL PASS.
extends SceneTree

const View := preload("res://view/craft_view.gd")
const Cockpit := preload("res://vr/vr_cockpit.gd")
const Sequence := preload("res://vr/startup_sequence.gd")
var failures := 0
var checks := 0


func _initialize() -> void:
	View.track_override = "network"
	View.job_override = "none"
	View.best_dir = OS.get_user_data_dir().path_join("test_flight_school_")
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


## Time passing in a sequence with these triggers, grips and gear held.
func _hold(s, seconds: float, thr := [0.0, 0.0], grip := [0.0, 0.0], gear := 1) -> void:
	var left := seconds
	while left > 1e-6:
		var dt := minf(left, 1.0 / 90.0)
		s.step(dt, thr, gear, grip)
		left -= dt


## From cold and dark to both engines running on the brake: the run-up.
func _to_run_up(s) -> void:
	s.cold()
	s.flick("batt", 1)
	_hold(s, Sequence.SELFTEST_S + 0.3)
	s.flick("engine", 1)      # the guard
	s.flick("engine", 1)      # the switch under it
	_hold(s, Sequence.CHARGE_S + 0.3)
	s.press_start()
	_hold(s, Sequence.STAGGER_S + Sequence.CRANK_S + Sequence.CATCH_S + 0.5)
	s.events.clear()


func _lines(s) -> PackedStringArray:
	return s.message().split("\n")


func _logic() -> void:
	# the plain run-up is what it was
	var plain = Sequence.new()
	plain.gears = true
	_to_run_up(plain)
	_check("not taught, the run-up is the plain one: no lesson, its page as it was (\"%s\"), the lessons' checks not asked for" % _lines(plain)[0],
		plain.held() and plain.lesson() == "" and _lines(plain)[0].begins_with("RUN-UP") and plain.checks.steerR and plain.checks.steerL and plain.checks.brake and not plain.checks.thrL)
	_hold(plain, 0.3, [1.0, 0.0])
	_hold(plain, 0.3, [0.0, 1.0])
	_hold(plain, 0.2, [0.0, 0.0], [0.0, 0.0], 2)
	_hold(plain, Sequence.TURBINE_UP_S + 0.3, [1.0, 1.0], [0.0, 0.0], 2)
	_check("... and is passed as it always was: each lever, a shift, both held", plain.checks_done() and _lines(plain)[0].begins_with("RELEASE PARK BRAKE") and _lines(plain)[2].begins_with("ALL CHECKS GOOD"))

	# taught: a lesson at a time
	var s = Sequence.new()
	s.gears = true
	s.school = true
	_to_run_up(s)
	var marks := [int(s.display().mark)]
	_check("taught, the run-up opens on the throttle: lesson 1 of %d, \"%s\" / \"%s\" / \"%s\"" % [s.lesson_count(), _lines(s)[0], _lines(s)[1], _lines(s)[2]],
		s.held() and s.lesson() == "throttle" and s.lesson_number() == 1 and s.lesson_count() == 6 and _lines(s)[0].begins_with("THROTTLE  4 / 5") and _lines(s)[1].begins_with("BOTH TRIGGERS > ")
		and _lines(s)[2].ends_with("| 1 OF 6") and not s.checks_done())
	_hold(s, 2.0, [0.87, 0.0])
	_check("one trigger alone does not pass it, and the glass says so: \"%s\"; its bars are the two triggers (%.2f / %.2f)" % [_lines(s)[2], s.display().bars[0], s.display().bars[1]],
		s.lesson() == "throttle" and _lines(s)[2].begins_with("ONE TRIGGER") and s.display().pair and float(s.display().bars[0]) > 0.99 and float(s.display().bars[1]) == 0.0)
	_hold(s, 2.0, [0.5, 0.5])
	_check("... nor both part way (this is a game of full or nothing)", s.lesson() == "throttle" and not s.checks.thrL)
	_hold(s, 2.0, [0.0, 0.0], [0.0, 0.4])
	_check("... and a grip squeezed now does not pass a lesson that has not come up yet", s.lesson() == "throttle" and not s.checks.steerR)
	_hold(s, Sequence.THROTTLE_HOLD_S - 0.2, [0.87, 0.87])
	var before: bool = s.checks.thrL
	_hold(s, 0.3, [0.87, 0.87])
	_check("both triggers all the way in for a second pass it (not before: %s), with one tick: %s" % [before, s.events], not before and s.checks.thrL and s.checks.thrR and s.events.count("check") == 1 and s.lesson() == "turbines")
	marks.append(int(s.display().mark))
	_check("held on, the turbines spool to their test speed: \"%s\"" % _lines(s)[1], _lines(s)[0].begins_with("TURBINES") and _lines(s)[1].contains("KEEP HOLDING") and s.turbine > 0.05 and s.turbine < 0.5)
	_hold(s, Sequence.TURBINE_UP_S, [0.87, 0.87])
	_check("... and that is the second lesson passed; the third is a right turn: \"%s\" / \"%s\"" % [_lines(s)[0], _lines(s)[1]],
		s.checks.turbines and s.events.has("turbines_ok") and s.lesson() == "right" and _lines(s)[0].begins_with("TURN RIGHT") and _lines(s)[1].begins_with("RIGHT GRIP > SQUEEZE GENTLY") and s.lesson_number() == 3)
	marks.append(int(s.display().mark))
	_hold(s, 1.5, [0.0, 0.0], [0.0, 1.0])
	_check("the right grip crushed is not a turn: \"%s\" (the bars are the two grips: %.2f / %.2f)" % [_lines(s)[2], s.display().bars[0], s.display().bars[1]],
		s.lesson() == "right" and _lines(s)[2].begins_with("TOO HARD") and s.display().pair and float(s.display().bars[1]) == 1.0 and float(s.display().bars[0]) == 0.0)
	_hold(s, 1.5, [0.0, 0.0], [0.4, 0.0])
	_check("the left grip is the wrong hand: \"%s\"" % _lines(s)[2], s.lesson() == "right" and _lines(s)[2].begins_with("THE OTHER HAND"))
	_hold(s, 1.5, [0.0, 0.0], [0.4, 0.4])
	_check("both grips is not a turn either: \"%s\"" % _lines(s)[2], s.lesson() == "right" and _lines(s)[2].begins_with("ONE GRIP ONLY"))
	_hold(s, 0.5, [0.0, 0.0], [0.0, 0.4])
	_hold(s, 0.1)
	_hold(s, 0.5, [0.0, 0.0], [0.0, 0.4])
	_check("a gentle squeeze let go before it has been held is not passed", s.lesson() == "right" and not s.checks.steerR)
	_hold(s, Sequence.GENTLE_HOLD_S + 0.1, [0.0, 0.0], [0.0, 0.4])
	_check("the right grip at 0.4 (his own median squeeze) held: passed, and the left turn is next: \"%s\"" % _lines(s)[0], s.checks.steerR and s.lesson() == "left" and _lines(s)[1].begins_with("LEFT GRIP"))
	marks.append(int(s.display().mark))
	_hold(s, Sequence.GENTLE_HOLD_S + 0.1, [0.87, 0.87], [0.3, 0.0])
	_check("the left grip gently, the triggers held in or not: passed; the brakes are next: \"%s\" / \"%s\"" % [_lines(s)[0], _lines(s)[1]], s.checks.steerL and s.lesson() == "brake" and _lines(s)[1].begins_with("BOTH GRIPS > SQUEEZE HARD"))
	marks.append(int(s.display().mark))
	_hold(s, 1.5, [0.0, 0.0], [0.5, 0.5])
	_check("both grips half in is not the brakes hard", s.lesson() == "brake" and not s.checks.brake)
	_hold(s, Sequence.HARD_HOLD_S + 0.1, [0.0, 0.0], [1.0, 1.0])
	_check("both grips all the way: passed; the last lesson is the gearbox: \"%s\" / \"%s\" / \"%s\"" % [_lines(s)[0], _lines(s)[1], _lines(s)[2]],
		s.checks.brake and s.lesson() == "gear" and s.lesson_number() == 6 and _lines(s)[0].begins_with("SHIFT") and _lines(s)[1].begins_with("RIGHT STICK") and _lines(s)[2].ends_with("| 6 OF 6") and not s.checks_done())
	marks.append(int(s.display().mark))
	_hold(s, 0.2, [0.0, 0.0], [0.0, 0.0], 2)
	_check("a shift passes it: every lesson done, and the glass sends him off with the two things to remember: \"%s\" / \"%s\"" % [_lines(s)[0], _lines(s)[2]],
		s.checks.gear and s.lesson() == "" and s.checks_done() and _lines(s)[0].begins_with("RELEASE PARK BRAKE") and _lines(s)[2].begins_with("TRIGGERS IN, STEER WITH GENTLE SQUEEZES"))
	marks.append(int(s.display().mark))
	var rising := true
	for k in range(1, marks.size()):
		rising = rising and int(marks[k]) > int(marks[k - 1])
	_check("the glass's tally went up at every lesson passed (%s)" % [marks], rising)
	s.events.clear()
	s.flick("park", -1)
	_hold(s, 0.1, [0.87, 0.87], [0.0, 0.0], 2)
	_check("the brake let go with every lesson passed: cleared, and the school is behind him (%s)" % [s.events], s.cleared and s.is_hot() and s.taught and not s.school and s.events.has("schooled"))
	s.flick("park", 1)
	_hold(s, 0.1)
	_check("... so setting the brake again is the plain run-up", s.held() and s.lesson() == "" and _lines(s)[0].begins_with("RUN-UP"))

	# without a gearbox there are five lessons; and a school walked out of is not passed
	var short = Sequence.new()
	short.school = true
	_to_run_up(short)
	_hold(short, Sequence.THROTTLE_HOLD_S + Sequence.TURBINE_UP_S + 0.5, [0.87, 0.87])
	_check("with no gearbox there are five lessons (the third now up: \"%s\")" % _lines(short)[2], short.lesson_count() == 5 and short.lesson() == "right" and _lines(short)[2].ends_with("| 3 OF 5"))
	short.events.clear()
	short.flick("park", -1)
	_hold(short, 0.1)
	_check("the brake let go half way through: she flies, but the school is not passed and will be there next time", short.cleared and not short.taught and short.school and not short.events.has("schooled"))
	# the asks are the measured ones
	_check("what is asked is how the game is flown: a trigger's stop (0.87) is past FULL_LEVER (%.2f), and the gentle squeeze (%.2f to %.2f) holds the measured median of 0.40 and stops short of a hard one (%.2f)" % [
		Sequence.FULL_LEVER, Sequence.GENTLE.x, Sequence.GENTLE.y, Sequence.HARD_GRIP],
		Sequence.FULL_LEVER < 0.87 and Sequence.FULL_LEVER > 0.75 and Sequence.GENTLE.x < 0.4 and Sequence.GENTLE.y > 0.4 and Sequence.GENTLE.y < Sequence.TOO_HARD and Sequence.TOO_HARD <= Sequence.HARD_GRIP)


func _run() -> void:
	_logic()
	# in a cockpit: a cold start is taught for a pilot who has not passed
	var prefs_before := FileAccess.get_file_as_string(Cockpit.PREFS) if FileAccess.file_exists(Cockpit.PREFS) else ""
	Cockpit.cold_on_entry = true
	var v = Cockpit.new()
	root.add_child(v)
	await process_frame
	v.set_process(false)
	var s = v.startup
	_check("a flight chosen from the menu begins cold with the school on (trigger throttles: %s), and the quick menu has its line" % v.quest.scheme,
		s.school and not s.cleared and s.park and Cockpit.school and v._menu_items().any(func(item): return item.key == "school" and item.value == "ON"))
	if s.school:
		s.gears = true
		s.flick("batt", 1)
		_hold(s, Sequence.SELFTEST_S + 0.3)
		s.flick("engine", 1)
		s.flick("engine", 1)
		_hold(s, Sequence.CHARGE_S + 0.3)
		s.press_start()
		_hold(s, Sequence.STAGGER_S + Sequence.CRANK_S + Sequence.CATCH_S + 0.5)
		_hold(s, Sequence.THROTTLE_HOLD_S + Sequence.TURBINE_UP_S + 0.5, [0.87, 0.87])
		v.inp = {"thrL": 0.0, "thrR": 0.0, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": false}
		_hold(s, 0.3, [0.0, 0.0], [0.0, 0.4])
		for frame in 30:
			v._sync_craft(1.0 / 90.0)
		_check("in the right turn's lesson the brake needles and the engines' air brakes are the hands' own: needles %s, flaps %.2f / %.2f (on the brake alone they are all out)" % [v._shown_brakes(), v.craft.flap_open[0], v.craft.flap_open[1]],
			s.lesson() == "right" and is_equal_approx(float(v._shown_brakes()[1]), 0.4) and float(v._shown_brakes()[0]) == 0.0 and absf(v.craft.flap_open[1] - 0.4) < 0.02 and v.craft.flap_open[0] < 0.02)
		_hold(s, Sequence.GENTLE_HOLD_S + 0.1, [0.0, 0.0], [0.0, 0.4])
		_hold(s, Sequence.GENTLE_HOLD_S + 0.1, [0.0, 0.0], [0.4, 0.0])
		_hold(s, Sequence.HARD_HOLD_S + 0.1, [0.0, 0.0], [1.0, 1.0])
		_hold(s, 0.2, [0.0, 0.0], [0.0, 0.0], 2)
		for frame in 30:
			v._sync_craft(1.0 / 90.0)
		_check("with the lessons done the brake holds every air brake out again (needles %s, flaps %.2f / %.2f)" % [v._shown_brakes(), v.craft.flap_open[0], v.craft.flap_open[1]],
			s.checks_done() and float(v._shown_brakes()[0]) == 1.0 and v.craft.flap_open[0] > 0.99 and v.craft.flap_open[1] > 0.99)
		s.flick("park", -1)
		_hold(s, 0.1, [0.0, 0.0], [0.0, 0.0], 2)
		v._apply_startup(0.0)
		var saved: Dictionary = v._load_prefs()
		_check("flown away from, the school is passed and that is remembered (saved: %s): the next cold start is the plain one" % saved.get("school", "?"), not Cockpit.school and saved.get("school", "") == "done")
	v.queue_free()
	await process_frame
	Cockpit.cold_on_entry = true
	v = Cockpit.new()
	root.add_child(v)
	await process_frame
	_check("... and it is: cold, the school off", v.startup.park and not v.startup.cleared and not v.startup.school)
	v.queue_free()
	await process_frame
	# the pilot's own file as it was found
	if prefs_before == "":
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Cockpit.PREFS))
	else:
		var out := FileAccess.open(Cockpit.PREFS, FileAccess.WRITE)
		out.store_string(prefs_before)
		out.close()
	print("FLIGHT SCHOOL %s (%d checks, %d failures)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)
