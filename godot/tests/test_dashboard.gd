## Dashboard gate: the instrument panel shows what it's fed. Prints DASHBOARD PASS when every
## check passes.
## Run: Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_dashboard.gd
extends SceneTree

const DashScript := preload("res://vr/dashboard.gd")
const CraftModel := preload("res://view/craft_model.gd")
var fails := 0
var passed := 0


var d
var frames := 0


func _initialize() -> void:
	d = DashScript.new()
	root.add_child(d)
	d.transform = DashScript.mount()
	d.build()
	d.show_state({"mph": 4452.4, "kmh": 7165.2, "mach_line": "MACH 5.8   MILE / 0.81 s", "progress": "TO BOX 12.00 km",
		"footer": "SPEED   /   TRIGGER THROTTLES", "thr": [1.0, 0.5], "brk": [0.0, 0.75], "heat": [0.3, 1.1], "health": [1.0, 0.4],
		"flameout": [false, true], "battery": 0.4, "burner": true, "armed": false, "ramjet": false, "blink": true})
	_check("speed reads 4,452 (%s)" % d.labels.speed.text, d.labels.speed.text == "4,452")
	_check("units line: mph only, imperial (%s)" % d.labels.units.text, d.labels.units.text == "MPH")
	_check("Mach line passes through", d.labels.mach.text == "MACH 5.8   MILE / 0.81 s")
	var thr_l: MeshInstance3D = d.bars.thrL[0]
	var thr_r: MeshInstance3D = d.bars.thrR[0]
	var brk_r: MeshInstance3D = d.bars.brkR[0]
	_check("throttle bars at 1.0 and 0.5 (%.2f, %.2f)" % [thr_l.scale.y, thr_r.scale.y], is_equal_approx(thr_l.scale.y, 1.0) and is_equal_approx(thr_r.scale.y, 0.5))
	_check("bars grow up from a common floor", is_equal_approx(thr_l.position.y - thr_l.scale.y * d.BAR_H / 2.0, thr_r.position.y - thr_r.scale.y * d.BAR_H / 2.0))
	_check("left throttle past the gate is orange, right is green",
		(d.bars.thrL[1] as StandardMaterial3D).albedo_color == d.ORANGE and (d.bars.thrR[1] as StandardMaterial3D).albedo_color == d.GREEN)
	_check("right brake bar at 0.75 (%.2f)" % brk_r.scale.y, is_equal_approx(brk_r.scale.y, 0.75))
	_check("BURNER lamp lit, RAMJET dark", d.lamps.burner[0].modulate == d.ORANGE and d.lamps.ramjet[0].modulate == d.DIM)
	_check("right flameout warning (%s)" % d.labels.headR.text, d.labels.headR.text == "R FLAMEOUT" and d.labels.headR.modulate == d.RED)
	_check("over-limit heat is red and the bar stops at the top", (d.bars.heatR[1] as StandardMaterial3D).albedo_color.is_equal_approx(d.RED) and is_equal_approx(d.bars.heatR[0].scale.y, 1.0))
	_check("right engine health shown (HP bar %.2f) and the repair hint is up (%s)" % [d.bars.hpR[0].scale.y, d.labels.warn.text],
		is_equal_approx(d.bars.hpR[0].scale.y, 0.4) and d.labels.warn.text == "HOLD X: REPAIR R" and is_equal_approx(d.bars.hpL[0].scale.y, 1.0))
	d.show_state({"mph": 300.0, "kmh": 483.0, "mach_line": "", "progress": "", "footer": "", "thr": [0.5, 0.5], "brk": [0.0, 0.0],
		"heat": [0.3, 0.3], "health": [1.0, 0.4], "flameout": [false, false], "battery": 1.0, "burner": false, "armed": false, "ramjet": false, "blink": true})
	_check("a damaged engine is labelled (%s)" % d.labels.headR.text, d.labels.headR.text == "R DAMAGED" and d.labels.headL.text == "L")
	# the longest things the panel shows, for the clearance pass (labels size to their text)
	d.show_state({"mph": 5387.0, "kmh": 8669.0, "mach_line": "MACH 7.0   MILE / 0.67 s",
		"progress": "STOPPED IN BOX  95.46s   6.9 ft off   braked 4.47 mi out\nBEST 95.46s   (Y: go again)",
		"footer": "STARFIGHTER   /   L STICK THROTTLE  R STICK STEER  TRIGGERS BRAKE", "thr": [1.0, 1.0], "brk": [1.0, 1.0],
		"heat": [1.0, 1.0], "health": [0.1, 0.1], "flameout": [true, true], "battery": 1.0, "burner": true, "armed": true, "ramjet": true, "blink": true})


func _process(_delta: float) -> bool:
	frames += 1
	if frames < 3:   # Label3D builds its mesh on the next frame
		return false
	# every corner of every part of the panel, in the pod's frame, must clear the hull
	var bad := []
	var worst := ""
	var n := 0
	for node in d.find_children("*", "VisualInstance3D", true, false):
		var vi := node as VisualInstance3D
		# meshes: their real vertices (a curved part's bounding-box corners float in empty
		# space); labels: their quad's corners
		var pts := PackedVector3Array()
		if vi is MeshInstance3D:
			var mesh: Mesh = (vi as MeshInstance3D).mesh
			pts = (mesh as PrimitiveMesh).get_mesh_arrays()[Mesh.ARRAY_VERTEX] if mesh is PrimitiveMesh else mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
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
				bad.append(vi.name)
				worst = "%s %s at pod (%.2f, %.2f, %.2f)" % [vi.name, why, pod.x, pod.y, pod.z]
	var parts := {}
	for nm in bad:
		parts[nm] = parts.get(nm, 0) + 1
	_check("panel clears the hull: %d points checked, %d clipping %s%s" % [n, bad.size(), parts, "" if bad.is_empty() else " (e.g. " + worst + ")"],
		bad.is_empty() and n > 100)
	var good: bool = fails == 0 and passed == 13
	print("DASHBOARD ", "PASS" if good else "FAIL (%d failed, %d passed)" % [fails, passed])
	quit(0 if good else 1)
	return true


func _check(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if ok:
		passed += 1
	else:
		fails += 1
