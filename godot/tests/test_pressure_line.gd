## Exercise the actual vehicle, developed surface, desktop/VR menu and cockpit.
extends SceneTree

const View := preload("res://vr/vr_cockpit.gd")
const Flat := preload("res://view/craft_view.gd")
const Menu := preload("res://release/release_config.gd")
const Sim := preload("res://sim/craft_sim.gd")
const DT := 1.0 / 480.0
var failed := 0
var v
var s
var r: int = Sim.NET_PRESSURE[0]
var lo: int = Sim.NET_PRESSURE[1]
var hi: int = Sim.NET_PRESSURE[2]
var input := {"thrL": 0.78, "thrR": 0.78, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": true}

func check(label: String, condition: bool) -> void:
	print(("PASS " if condition else "FAIL ") + label)
	failed += int(not condition)

func _initialize() -> void:
	Flat.track_override = "network"
	Flat.job_override = "none"
	Flat.spot_override = "SAurora"
	Flat.best_dir = OS.get_user_data_dir().path_join("test_pressure_")
	v = View.new()
	root.add_child(v)
	_run.call_deferred()

func _run() -> void:
	v.set_process(false)
	s = v.sim
	var road = s.roads[r]
	var line = v.network_world.pressure_line
	check("menu launches on the approach", Menu.course_overrides("aurora") == ["network", "none", "SAurora"]
		and s.pod.path == r and s.pod.hint < lo and Menu.course_for("network", "SAurora") == "aurora")
	check("sealed span reaches both opposite map corners", road.px[lo] < 30000 and road.py[lo] < 30000
		and road.px[hi] > 570000 and road.py[hi] > 570000 and line.span > 766000)
	var glass := {}
	var collars := {}
	for node in line.get_children():
		if not node is MeshInstance3D:
			continue
		if node.mesh.surface_get_material(0) == line.glazing:
			glass[node.mesh.get_rid()] = true
		elif node.mesh.surface_get_material(0) == line.metal:
			collars[node.mesh.get_rid()] = true
	check("hundreds of sections share three glass meshes and a bounded pool",
		line.blocks >= 200 and line._glass_shapes.size() == 3 and glass.size() <= 3
		and collars.size() <= 4 and line.get_child_count() < 150)
	_seed(lo - 2, 1, 0)
	var outside: float = s.pressure_fill()
	_seed(lo + 19, 1, 0)
	var vestibule: float = s.pressure_fill()
	_seed((lo + hi) / 2, 1, 750)
	check("pressure builds across the entrance gallery", outside == 0.0 and vestibule > 0.45 and vestibule < 0.55 and s.pressure_fill() == 1.0)
	s.pressure_arc = PI * s.Pressure.RADIUS
	for k in 1440:
		s.step(input, DT)
	var upright: Vector3 = v.shaft_carry_at(s.pod.x, s.pod.y) * Vector3.UP
	check("three seconds of matched thrust hold the ceiling", upright.dot(Vector3.DOWN) > 0.999)
	for dir in [1, -1]:
		_roll(dir)
		_exit(dir)
	s.respawn_on(r, lo - 2)
	check("reset clears angular position", s.pressure_arc == 0.0)
	v.free()
	print("AURORA PRESSURE LINE ", "PASS" if failed == 0 else "FAIL")
	quit(0 if failed == 0 else 1)

func _seed(i: int, dir: int, speed: float) -> void:
	s.respawn_on(r, i, dir)
	var road = s.roads[r]
	for b in s.bodies:
		b.vx = dir * speed * road.tx[i]
		b.vy = dir * speed * road.ty[i]

func _roll(dir: int) -> void:
	_seed((lo + hi) / 2, 1, 650.0)
	var last := 0.0
	var sweep := 0.0
	var seen := {}
	var min_eye := INF
	var min_up := 1.0
	var jumps := 0.0
	var preceding := Vector3.ZERO
	var hits := 0
	for frame in 660:
		# Pulse one lever, then match thrust. The pilot chooses the helix.
		input.thrL = (0.70 if dir > 0 else 0.83) if frame < 75 else 0.78
		input.thrR = (0.83 if dir > 0 else 0.70) if frame < 75 else 0.78
		for sub in 8:
			s.step(input, DT)
			for event in s.events:
				hits += int(event.type in ["scrape", "hit", "wreck", "binder"])
			s.events.clear()
		var angle: float = s.pressure_arc / s.Pressure.RADIUS
		sweep += wrapf(angle - last, -PI, PI)
		last = angle
		seen[posmod(roundi(angle / (PI * 0.5)), 4)] = true
		v._follow_origin()
		v.craft.sync(s, input, 1.0 / 60.0)
		v._place_camera(1.0)
		var up: Vector3 = v.shaft_carry_at(s.pod.x, s.pod.y) * Vector3.UP
		var base: Vector3 = v.wz(s.pod.x, s.pod.y, s.net_height(r, s.pod.hint))
		var eye: Vector3 = v.rig.transform * (v.origin.position + v.cam.position)
		min_eye = minf(min_eye, (eye - base).dot(up))
		min_up = minf(min_up, up.dot(v.rig.basis.y))
		if frame > 0:
			jumps = maxf(jumps, up.angle_to(preceding))
		preceding = up
	check("lever input drives %.1f turns, all four quadrants, %d contacts" % [sweep / TAU, hits],
		dir * sweep > TAU * 1.5 and seen.size() == 4 and hits == 0 and not s.binder_broken)
	check("headset rig follows the wall, eye clearance %.2f m, largest rotation %.2f degrees" %
		[min_eye, rad_to_deg(jumps)], min_eye > 0.4 and min_up > 0.96 and jumps < 0.1)

func _exit(dir: int) -> void:
	_seed(hi - 380 if dir > 0 else lo + 380, dir, 1250.0)
	input.thrL = 0.78
	input.thrR = 0.78
	s.step(input, DT)
	s.pressure_arc = PI * s.Pressure.RADIUS - 0.01
	var initial: float = s.pressure_arc
	var worst_step := 0.0
	var prev := initial
	for k in 12000:
		s.step(input, DT)
		worst_step = maxf(worst_step, absf(wrapf((s.pressure_arc - prev) / s.Pressure.RADIUS, -PI, PI)))
		prev = s.pressure_arc
		if (dir > 0 and s.pod.hint > hi + 2) or (dir < 0 and s.pod.hint < lo - 2):
			break
	check("%s lock receives an inverted pilot and releases upright" % ("NE" if dir > 0 else "SW"),
		not Sim.in_pressure(r, s.pod.hint) and absf(prev) < 0.01 and worst_step < 0.01 and not s.pod.off_road)
