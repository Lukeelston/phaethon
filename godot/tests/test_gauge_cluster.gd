## Gauge cluster gate (vr/gauge_cluster.gd): the analogue instruments show what they are fed, and
## the whole binnacle stays inside the cockpit. Prints GAUGE CLUSTER PASS when every check passes.
## (The flat panel it replaces keeps its own gate: tests/test_dashboard.gd.)
## Run: Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_gauge_cluster.gd
extends SceneTree

const Cluster := preload("res://vr/gauge_cluster.gd")
const Layout := preload("res://vr/gauge_layout.gd")
const CraftModel := preload("res://view/craft_model.gd")
const CHECKS := 35
var fails := 0
var passed := 0
var d
var frames := 0


func _near(a: float, b: float) -> bool:
	return absf(a - b) < 0.01


## Roll the points counter for some seconds, a twentieth at a time.
func _roll(seconds: float) -> void:
	for i in roundi(seconds / 0.05):
		d.roll(0.05)


## The g-meter's clockwork for some seconds, a twentieth at a time.
func _settle(seconds: float) -> void:
	for i in roundi(seconds / 0.05):
		d.settle(0.05)


func _initialize() -> void:
	_check("the cluster's art is in the project", Cluster.available())
	d = Cluster.new()
	root.add_child(d)
	d.transform = Cluster.mount()
	d.build()
	d.show_state({"mph": 4452.4, "kmh": 7165.2, "mach": 5.8, "mach_line": "MACH 5.8   MILE / 0.81 s", "progress": "TO BOX 12.00 km",
		"footer": "SPEED   /   TRIGGER THROTTLES", "thr": [1.0, 0.5], "brk": [0.0, 0.75], "heat": [0.3, 1.1], "health": [1.0, 0.4],
		"flameout": [false, true], "battery": 0.4, "burner": true, "armed": false, "ramjet": false, "turbines": true, "gear": 3, "overdrive": true,
		"blink": true})
	_check("the digital speed reads 4,452 (%s; the display is sent %d)" % [d.labels.speed.text, d._digit_mat.get_shader_parameter("speed")],
		d.labels.speed.text == "4,452" and d._digit_mat.get_shader_parameter("speed") == 4452)
	_check("mph only, imperial (%s)" % d.labels.units.text, d.labels.units.text == "MPH")
	_check("the Mach line and the run line reach the LCD strips", d.labels.mach.text == "MACH 5.8   MILE / 0.81 s" and d.labels.progress.text == "TO BOX 12.00 km")
	_check("the Mach needle shows 5.8 of 8 (%.1f deg)" % d.needle_angle("mach"), _near(d.needle_angle("mach"), 200.0 - 220.0 * 5.8 / 8.0))
	_check("thrust needles at full and at half (%.0f, %.0f deg)" % [d.needle_angle("thrL"), d.needle_angle("thrR")],
		_near(d.needle_angle("thrL"), -45.0) and _near(d.needle_angle("thrR"), 90.0))
	_check("the right air brake at three quarters (%.0f deg), the left at rest (%.0f)" % [d.needle_angle("brkR"), d.needle_angle("brkL")],
		_near(d.needle_angle("brkR"), 300.0) and _near(d.needle_angle("brkL"), 210.0))
	_check("BURNER is lit orange, ARMED and RAMJET are dark",
		Color(d.lamps.burner, 1.0) == d.ORANGE and d.lamps.burner.a == 1.0 and d.lamps.armed.a == 0.0 and d.lamps.ramjet.a == 0.0)
	_check("TURBINES is lit green while the second stage runs", d.lamps.turbines.a == 1.0 and Color(d.lamps.turbines, 1.0) == d.GREEN)
	_check("the right engine's FLAMEOUT is lit red, the left dark (%s)" % d.labels.headR.text,
		d.lamps.flameoutR.a == 1.0 and Color(d.lamps.flameoutR, 1.0) == d.RED and d.lamps.flameoutL.a == 0.0 and d.labels.headR.text == "R FLAMEOUT")
	_check("over-limit heat pegs the needle at the top of its scale (%.0f deg) and lights HOT; the cool engine's stays dark" % d.needle_angle("heatR"),
		_near(d.needle_angle("heatR"), 30.0) and d.lamps.hotR.a == 1.0 and d.lamps.hotL.a == 0.0)
	_check("engine health: %d of 8 segments on the right, %d on the left; the repair hint is up (%s)" % [d.arc_lit("hpR", 8), d.arc_lit("hpL", 8), d.labels.warn.text],
		d.arc_lit("hpR", 8) == 4 and d.arc_lit("hpL", 8) == 8 and d.labels.warn.text == "HOLD X: REPAIR R" and Color(d.lamps.hpR0, 1.0) == d.AMBER)
	_check("the battery arc shows %d of 12" % d.arc_lit("bat", 12), d.arc_lit("bat", 12) == 5 and Color(d.lamps.bat0, 1.0) == d.CYAN)
	_check("the gear digit shows third, orange in overdrive (%s)" % d.labels.gear.text,
		d.labels.gear.text == "3" and d.labels.gear.modulate == d.ORANGE and d._digit_mat.get_shader_parameter("gear") == 3)
	d.show_state({"mph": 300.0, "kmh": 483.0, "mach_line": "", "progress": "", "footer": "", "thr": [0.5, 0.5], "brk": [0.0, 0.0],
		"heat": [0.3, 0.3], "health": [1.0, 0.2], "flameout": [false, false], "battery": 0.1, "burner": false, "armed": false, "ramjet": false, "blink": false})
	_check("a damaged engine is labelled (%s), and a badly hurt one's arc blinks red" % d.labels.headR.text,
		d.labels.headR.text == "R DAMAGED" and d.labels.headL.text == "L" and Color(d.lamps.hpR0, 1.0) == d.RED and d.lamps.hpR0.a < 0.5)
	_check("equal throttles point the same way (%.0f, %.0f deg); without a Mach figure the needle follows the speed (%.1f deg)" % [
		d.needle_angle("thrL"), d.needle_angle("thrR"), d.needle_angle("mach")],
		_near(d.needle_angle("thrL"), d.needle_angle("thrR")) and absf(d.needle_angle("mach") - (200.0 - 220.0 * (300.0 / 767.27) / 8.0)) < 0.1)
	_check("TURBINES is dark on pistons alone (no turbines key: the flat panel's callers)", d.lamps.turbines.a == 0.0)
	_check("the turbines light at %.0f mph and stay lit down to %.0f" % [EngineAudio.TUNE.turbine_mph[0], EngineAudio.TUNE.turbine_off_mph],
		not EngineAudio.turbines_at(EngineAudio.TUNE.turbine_mph[0] - 1.0, false) and EngineAudio.turbines_at(EngineAudio.TUNE.turbine_mph[0], false)
		and EngineAudio.turbines_at(EngineAudio.TUNE.turbine_off_mph, true) and not EngineAudio.turbines_at(EngineAudio.TUNE.turbine_off_mph - 1.0, true)
		and EngineAudio.TUNE.turbine_off_mph < EngineAudio.TUNE.turbine_mph[0] and EngineAudio.TUNE.turbine_mph[0] < EngineAudio.TUNE.turbine_mph[1])
	_check("a low battery turns its arc red, and no gear blanks the digit", Color(d.lamps.bat0, 1.0) == d.RED and d.labels.gear.text == "" and not d.labels.gear_lbl.visible)
	# the points counter between the strips, and the feat on the strip beside it
	var run := {"mph": 2000.0, "kmh": 3218.0, "mach_line": "MACH 2.6", "progress": "", "footer": "SPEED   /   TRIGGER THROTTLES", "thr": [1.0, 1.0], "brk": [0.0, 0.0],
		"heat": [0.2, 0.2], "health": [1.0, 1.0], "flameout": [false, false], "battery": 1.0, "burner": false, "armed": false, "ramjet": false, "blink": true}
	d.show_state(run)
	_check("with no score the counter stands at zero and the strip shows the handling", d.points == 0 and d.rolled == 0.0 and d.labels.footer.visible and not d.labels.feat.visible)
	run.merge({"points": 1225, "feat": "HIGH-SPEED PRECISION  +1225", "feat_age": 0.4})
	d.show_state(run)
	_roll(0.35)
	var half_way: float = d.rolled
	_roll(0.4)
	_check("an award rolls in evenly over 0.7 s (%.0f of 1,225 after 0.35 s, then %.0f), and the drums are sent it" % [half_way, d.rolled],
		absf(half_way - 612.5) < 1.0 and d.rolled == 1225.0 and float(d._drum_mat.get_shader_parameter("value")) == 1225.0 and d.labels.points.text == "1225")
	_check("the feat is read on the strip beside it, in the handling's place (%s)" % d.labels.feat.text,
		d.labels.feat.visible and d.labels.feat.text == "HIGH-SPEED PRECISION  +1225" and not d.labels.footer.visible and d.labels.feat.modulate.a == 1.0)
	run.merge({"points": 1240, "feat": "VELOCITY  +15", "feat_age": 3.5}, true)
	d.show_state(run)
	_roll(0.35)
	var small: float = d.rolled
	_roll(0.4)
	_check("a small award still takes its time (%.1f after 0.35 s, then %.0f), and an older feat is dimmer (%.2f)" % [small, d.rolled, d.labels.feat.modulate.a],
		small > 1231.0 and small < 1234.0 and d.rolled == 1240.0 and d.labels.feat.visible and d.labels.feat.modulate.a < 0.6)
	run.merge({"feat_age": 7.0}, true)
	d.show_state(run)
	_check("after six seconds the strip goes back to the handling", d.labels.footer.visible and not d.labels.feat.visible)
	run.merge({"points": 0, "feat": "", "feat_age": 1e9}, true)
	d.show_state(run)
	_roll(0.2)
	var back: float = d.rolled
	_roll(0.2)
	_check("a new run spins it back to zero in half the time (%.0f after 0.2 s, then %.0f)" % [back, d.rolled], back > 400.0 and back < 660.0 and d.rolled == 0.0)
	# the g-meter: the sub-dial's needle and its tell-tale, and on the status strip the figure, the slip bar and the peak
	var up := func(pull: float) -> float: return log(1.0 + pull) / log(101.0)      # how far up its scale of decades a load reads
	var flown := run.duplicate()
	flown.merge({"progress": "GLACIER  178.9 mi   FROM ERIDANUS  0:02"}, true)
	d.show_state(flown)
	_settle(0.25)
	_check("at rest the g-meter stands at 1 g, a seventh of the way up its scale (%.3f, %.1f deg), the tell-tale with it and the ball in the middle of its tube; the strip reads \"%s\" and \"%s\"" % [d.values.g, d.needle_angle("g"), d.labels.g.text, d.labels.g_peak.text],
		_near(d.values.g, up.call(1.0)) and _near(d.needle_angle("g"), 225.0 - 270.0 * up.call(1.0)) and _near(d.needle_angle("g_peak"), d.needle_angle("g"))
		and d.labels.g.text == "1.0 G" and d.labels.g_peak.text == "PEAK 1.0" and d.labels.g.visible and d._slip.visible and float(d._slip_mat.get_shader_parameter("ball")) == 0.0)
	flown.merge({"g": 4.2, "g_side": 4.07}, true)
	d.show_state(flown)
	var stale: String = d.labels.g.text
	_settle(0.25)
	_check("a 4.2 g left turn: the needle follows the load at once (%.1f deg), the figure is read a fifth of a second later (\"%s\", then \"%s\"), and the ball runs right, where the pilot is thrown (%.2f of its travel)" % [d.needle_angle("g"), stale, d.labels.g.text, float(d._slip_mat.get_shader_parameter("ball"))],
		_near(d.needle_angle("g"), 225.0 - 270.0 * up.call(4.2)) and stale == "1.0 G" and d.labels.g.text == "4.2 G"
		and _near(float(d._slip_mat.get_shader_parameter("ball")), up.call(4.07)) and float(d._slip_mat.get_shader_parameter("hard")) == 0.0)
	flown.merge({"g": 24.0, "g_side": -23.9}, true)
	d.show_state(flown)
	_settle(0.25)
	_check("a hard right turn, 24 g: the needle is in the last third of its scale (%.2f), the tell-tale has gone up with it, and the ball is out to the left and orange (%.2f)" % [d.values.g, float(d._slip_mat.get_shader_parameter("ball"))],
		d.values.g > 2.0 / 3.0 and _near(d.values.g, up.call(24.0)) and _near(d.values.g_peak, d.values.g) and d.labels.g.text == "24.0 G"
		and float(d._slip_mat.get_shader_parameter("ball")) < -0.6 and float(d._slip_mat.get_shader_parameter("hard")) == 1.0)
	flown.merge({"g": 1.0, "g_side": 0.0}, true)
	d.show_state(flown)
	_settle(Cluster.PEAK_HOLD - 0.3)
	d.show_state(flown)
	_check("the turn let go: the needle is back at 1 g (%.1f deg), and the tell-tale stays at the 24 g it was pushed to for %.0f s (%.1f deg, \"%s\")" % [d.needle_angle("g"), Cluster.PEAK_HOLD, d.needle_angle("g_peak"), d.labels.g_peak.text],
		_near(d.needle_angle("g"), 225.0 - 270.0 * up.call(1.0)) and d.g_peak == 24.0 and _near(d.needle_angle("g_peak"), 225.0 - 270.0 * up.call(24.0)) and d.labels.g_peak.text == "PEAK 24.0" and d.labels.g.text == "1.0 G")
	_settle(0.35)
	d.show_state(flown)
	var falling: float = d.g_peak
	_settle(2.0)
	d.show_state(flown)
	_check("then it falls back down the scale to the needle (%.1f g a third of a second into the fall, then %.1f; \"%s\")" % [falling, d.g_peak, d.labels.g_peak.text],
		falling < 20.0 and falling > 8.0 and d.g_peak == 1.0 and _near(d.needle_angle("g_peak"), d.needle_angle("g")) and d.labels.g_peak.text == "PEAK 1.0")
	flown.merge({"g": 122.0, "g_side": 0.0}, true)
	d.show_state(flown)
	_settle(0.25)
	var pegged: float = d.values.g
	flown.merge({"g": 0.0}, true)
	d.show_state(flown)
	_settle(0.25)
	_check("full air brakes at Mach 7, 122 g: the needle is on its top stop (%.3f of the scale) and the strip still has the figure (\"122 G\"); weightless over a jump it lies at zero (%.0f deg, \"%s\"), the tell-tale left at the top" % [pegged, d.needle_angle("g"), d.labels.g.text],
		pegged > 1.0 and pegged < 1.04 and d.labels.g_peak.text == "PEAK 122" and _near(d.needle_angle("g"), 225.0) and d.labels.g.text == "0.0 G" and d.g_peak == 122.0)
	flown.merge({"g": 1.0, "health": [1.0, 0.4]}, true)
	d.show_state(flown)
	var hint: bool = not d.labels.g.visible and not d._slip.visible and not d.labels.g_peak.visible and d.labels.warn.text == "HOLD X: REPAIR R"
	flown.merge({"health": [1.0, 1.0], "progress": "ENGINE POWER   2 / 5\nLIFT THE RED GUARD"}, true)
	d.show_state(flown)
	var two_lines: bool = not d.labels.g.visible and not d._slip.visible
	flown.merge({"progress": "OFF THE ROAD   ERIDANUS ON-RAMP  12.4 mi   (OR RESTART)"}, true)
	d.show_state(flown)
	var wrapped: bool = not d.labels.g.visible and not d._slip.visible
	flown.merge({"progress": "GLACIER  178.9 mi   FROM ERIDANUS  0:02"}, true)
	d.show_state(flown)
	_check("its line on the strip gives way to the repair hint (%s), to the start-up's two lines (%s) and to a run line too long for one (%s), and comes back after" % [hint, two_lines, wrapped],
		hint and two_lines and wrapped and d.labels.g.visible and d._slip.visible and d.labels.g_peak.visible)
	# through the start-up that line is the checklist's rail of five steps (what StartupSequence.display() gives the glass)
	flown.merge({"progress": "ENGINE POWER   2 / 5
LIFT THE RED GUARD", "steps": {"done": 1, "mark": 17, "bars": [1.0, 0.4], "pair": false, "alert": false}}, true)
	d.show_state(flown)
	var railed: bool = d._steps.visible and not d.labels.g.visible and not d._slip.visible and int(d.steps.done) == 1 and float(d._steps_mat.get_shader_parameter("done")) == 1.0 		and (d._steps_mat.get_shader_parameter("bars") as Vector2).is_equal_approx(Vector2(1.0, 0.4)) and float(d._steps_mat.get_shader_parameter("pair")) == 0.0
	flown.merge({"steps": {"done": 2, "bars": [0.3, 0.0], "pair": true, "alert": true}, "health": [1.0, 0.4]}, true)
	d.show_state(flown)
	var hint_first: bool = not d._steps.visible and d.steps.is_empty() and d.labels.warn.text == "HOLD X: REPAIR R"
	flown.merge({"health": [1.0, 1.0]}, true)
	d.show_state(flown)
	var engines: bool = d._steps.visible and float(d._steps_mat.get_shader_parameter("done")) == 2.0 and float(d._steps_mat.get_shader_parameter("pair")) == 1.0 and float(d._steps_mat.get_shader_parameter("alert")) == 1.0
	flown.merge({"power": 0.0}, true)
	d.show_state(flown)
	var dead: bool = not d._steps.visible
	flown.merge({"power": 1.0, "steps": {}, "progress": "GLACIER  178.9 mi   FROM ERIDANUS  0:02"}, true)
	d.show_state(flown)
	_check("through the start-up that line is the checklist's rail of steps: one behind and the next filling (%s), the repair hint before it (%s), an engine in each half and a refusal (%s), dark with the battery off (%s); with the checklist gone so is the rail, and the g-meter is back" % [railed, hint_first, engines, dead],
		railed and hint_first and engines and dead and not d._steps.visible and d.steps.is_empty() and d.labels.g.visible and d._slip.visible)
	flown.merge({"g": 9.0, "power": 1.0, "sweep": 0.25}, true)
	d.show_state(flown)
	var swept: float = d.values.g
	flown.merge({"power": 0.0, "sweep": -1.0}, true)
	d.show_state(flown)
	_check("in the self-test its needle and tell-tale sweep with the rest (%.2f of the scale, the Mach needle's own); with the battery off they lie on the stop and the strip is blank" % swept,
		_near(swept, 0.5) and d.values.g == 0.0 and d.values.g_peak == 0.0 and _near(d.needle_angle("g"), 225.0) and not d.labels.g.visible and not d._slip.visible)
	flown.merge({"power": 1.0, "g": 1.0}, true)
	d.show_state(flown)
	# the longest things the strips show, for the clearance pass (labels size to their text)
	d.show_state({"mph": 5387.0, "kmh": 8669.0, "mach_line": "MACH 7.0   MILE / 0.67 s",
		"progress": "STOPPED IN BOX  95.46s   6.9 ft off   braked 4.47 mi out\nBEST 95.46s   (Y: go again)",
		"footer": "STARFIGHTER   /   L STICK THROTTLE  R STICK STEER  TRIGGERS BRAKE", "thr": [1.0, 1.0], "brk": [1.0, 1.0],
		"heat": [1.0, 1.0], "health": [0.1, 0.1], "flameout": [true, true], "battery": 1.0, "burner": true, "armed": true, "ramjet": true, "blink": true})


func _process(_delta: float) -> bool:
	frames += 1
	if frames < 3:   # Label3D builds its mesh on the next frame
		return false
	# every vertex of every part, in the pod's frame, must clear the hull
	var bad := {}
	var worst := ""
	var n := 0
	for node in d.find_children("*", "VisualInstance3D", true, false):
		var vi := node as VisualInstance3D
		var pts := PackedVector3Array()
		if vi is MeshInstance3D:
			pts = (vi as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		else:
			var box := vi.get_aabb()
			if box.size == Vector3.ZERO:
				continue
			for c in 8:
				pts.append(box.get_endpoint(c))
		for corner in pts:
			var rig: Vector3 = vi.global_transform * corner
			var pod := rig - Vector3(0, CraftModel.POD_FRAME_UP, 0)
			var why: String = CraftModel.hull_clearance(pod)
			n += 1
			if why != "":
				bad[vi.name] = bad.get(vi.name, 0) + 1
				worst = "%s %s at pod (%.2f, %.2f, %.2f)" % [vi.name, why, pod.x, pod.y, pod.z]
	_check("the cluster clears the hull: %d points checked, clipping %s%s" % [n, bad, "" if bad.is_empty() else " (e.g. " + worst + ")"],
		bad.is_empty() and n > 10000)
	var good: bool = fails == 0 and passed == CHECKS
	print("GAUGE CLUSTER ", "PASS" if good else "FAIL (%d failed, %d of %d passed)" % [fails, passed, CHECKS])
	quit(0 if good else 1)
	return true


func _check(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if ok:
		passed += 1
	else:
		fails += 1
