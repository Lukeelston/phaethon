## Gauge cluster gate (vr/gauge_cluster.gd): the analogue instruments show what they are fed, and
## the whole binnacle stays inside the cockpit. Prints GAUGE CLUSTER PASS when every check passes.
## (The flat panel it replaces keeps its own gate: tests/test_dashboard.gd.)
## Run: Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_gauge_cluster.gd
extends SceneTree

const Cluster := preload("res://vr/gauge_cluster.gd")
const Layout := preload("res://vr/gauge_layout.gd")
const CraftModel := preload("res://view/craft_model.gd")
const CHECKS := 20
var fails := 0
var passed := 0
var d
var frames := 0


func _near(a: float, b: float) -> bool:
	return absf(a - b) < 0.01


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
	_check("the turbines light at 2,000 mph and stay lit down to 1,700",
		not EngineAudio.turbines_at(1999.0, false) and EngineAudio.turbines_at(2000.0, false)
		and EngineAudio.turbines_at(1700.0, true) and not EngineAudio.turbines_at(1699.0, true))
	_check("a low battery turns its arc red, and no gear blanks the digit", Color(d.lamps.bat0, 1.0) == d.RED and d.labels.gear.text == "" and not d.labels.gear_lbl.visible)
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
