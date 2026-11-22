## The speed rush (vr/speed_rush.gd, vr/vr_cockpit.gd; Luke, 2026-11-22: "can you also add a little
## parallax/zoom effect with speed?"): the cockpit eased fore and aft by the craft's load and its speed,
## and the streaks in the air alongside.
##   the run      a scripted run at the headset's 90 frames a second: from a standstill through a launch's
##                loads to 10,000 mph, a light squeeze of the air brakes, a firm one, and full brakes to a
##                stop. The cockpit goes away under the pull, stays out with the speed, comes back under
##                the brakes and home at rest: inside its travel, its speed and its push all the way, with
##                no bounce. Switched off, the same run never moves it.
##   the cockpit  the real seat (XR off): only the shell moves, along its own nose, never turned; the rig,
##                the headset's origin and the camera are where they were, to the last bit; the tow links'
##                hooks go with the nose; it adds to the shudder; an outside camera has none of it; switched
##                off on the OPTIONS page it eases home and then stands exactly where the shudder alone puts
##                it, through another launch.
##   in sight     from the seated eye with the cockpit at each end of its travel, every point of the dials
##                and the strips that is in sight at rest still is.
##   the streaks  none at rest; out at speed, in the air's frame (through the seated eye, along the craft's
##                way); longer, more and brighter as the speed builds; none with the switch off.
##   the page     OPTIONS has SPEED RUSH: on with nothing saved, saved when switched.
## Run windowed (run-tests.ps1 -Windowed) it reads pixels back too: the streaks draw, and none of them
## within CLEAR degrees of dead ahead. Headless that part is skipped, and says so.
## Prints SPEED RUSH PASS.
extends SceneTree

const View := preload("res://view/craft_view.gd")
const Cockpit := preload("res://vr/vr_cockpit.gd")
const Rush := preload("res://vr/speed_rush.gd")
const Layout := preload("res://vr/gauge_layout.gd")
const Kit := preload("res://view/mesh_kit.gd")
const MPH := 2.236936
const FRAME := 1.0 / 90.0
# seconds, and the craft's load along its nose, g: a launch through the gears as tests/probe_rush.gd has it,
# on to 10,000 mph as the Aurora line or a boost takes her, the air brakes as the fourteenth flight's log has
# them (a light squeeze at speed is 20 g; a firm one 60), full brakes to a stop, and at rest
const RUN := [[0.5, 0.0], [3.0, 30.0], [2.0, 22.0], [3.0, 15.0], [3.0, 10.0], [4.0, 4.0], [11.6, 20.0], [4.0, 0.0],
	[3.0, -20.0], [2.0, 12.0], [2.0, -60.0], [1.0, 0.0], [12.0, -90.0], [4.0, 0.0]]
var failures := 0
var checks := 0
var v


func _initialize() -> void:
	View.track_override = "range"
	View.job_override = "none"
	View.best_dir = OS.get_user_data_dir().path_join("test_speed_rush_")
	Cockpit.camera = "cockpit"
	Cockpit._camera_loaded = true      # the pilot's saved choices stay out of this (the rush's own is read: there is none)
	Cockpit._nose_loaded = true
	Cockpit._slide_loaded = true
	Cockpit._startup_loaded = true
	Cockpit._map_loaded = true
	Cockpit._school_loaded = true
	Cockpit.cold_start = false
	Cockpit.school = false
	_run.call_deferred()


func _check(label: String, passed: bool) -> void:
	checks += 1
	print(("PASS " if passed else "FAIL ") + label)
	failures += int(not passed)


func _saved() -> Dictionary:
	var d = JSON.parse_string(FileAccess.get_file_as_string(Cockpit.PREFS)) if FileAccess.file_exists(Cockpit.PREFS) else {}
	return d if d is Dictionary else {}


func _go(key: String) -> bool:
	for k in v.menu.items.size():
		if String(v.menu.items[k].key) == key:
			v.menu.at = k
			v.menu_choose()
			return true
	return false


# --- the run, scripted (no scene: the easing by itself, at the headset's frame) ---

## Fly RUN with a rush of its own. -> what was seen: the cockpit's place at the end of each leg (m forward),
## the speed there (mph), the travel's ends reached, the fastest it moved and the hardest it was pushed.
func _scripted(on: bool) -> Dictionary:
	var rush = Rush.new()
	var speed := 0.0
	var g_meter := 0.0
	var seen := {"ends": [], "mph": [], "fwd": 0.0, "aft": 0.0, "rate": 0.0, "accel": 0.0, "moved": 0.0, "early": 0.0, "rebound": 0.0, "stopped_at": -1}
	var was := 0.0
	var was_rate := 0.0
	var frame := 0
	for leg in RUN:
		for k in int(round(float(leg[0]) / FRAME)):
			var next := maxf(0.0, speed + float(leg[1]) * 9.81 * FRAME)
			var g := (next - speed) / FRAME / 9.81      # (stopped, the brakes pull nothing)
			speed = next
			g_meter += (g - g_meter) * (1.0 - exp(-FRAME / Cockpit.G_TAU))      # as the cockpit's g-meter reads it
			var at: float = rush.ease_surge(FRAME, g_meter, speed * MPH, on)
			var rate := (at - was) / FRAME
			seen.fwd = maxf(seen.fwd, at)
			seen.aft = maxf(seen.aft, -at)
			seen.rate = maxf(seen.rate, absf(rate))
			seen.accel = maxf(seen.accel, absf(rate - was_rate) / FRAME)
			seen.moved = maxf(seen.moved, absf(at))
			was = at
			was_rate = rate
			frame += 1
			if frame == int(round(1.5 / FRAME)):      # a second into the launch
				seen.early = at
			if speed == 0.0 and frame > 90 and seen.stopped_at < 0:
				seen.stopped_at = frame
			if seen.stopped_at >= 0:
				seen.rebound = maxf(seen.rebound, at)      # (she stops with the cockpit aft of its rest: past it, coming home, is a bounce)
		seen.ends.append(rush.surge)
		seen.mph.append(speed * MPH)
	rush.free()
	return seen


func _the_run() -> void:
	_check("the speed's share is by the logarithm: none at 300 mph (%.2f), a third at 1,000 (%.2f), two thirds at 3,000 (%.2f), all at 10,000 (%.2f) and no more past it (%.2f)" % [
			Rush.speed_share(300.0), Rush.speed_share(1000.0), Rush.speed_share(3000.0), Rush.speed_share(10000.0), Rush.speed_share(14000.0)],
		Rush.speed_share(0.0) == 0.0 and Rush.speed_share(300.0) == 0.0 and absf(Rush.speed_share(1000.0) - 0.343) < 0.01 and absf(Rush.speed_share(3000.0) - 0.657) < 0.01
		and absf(Rush.speed_share(10000.0) - 1.0) < 1e-6 and Rush.speed_share(14000.0) == 1.0)
	var rising := true
	var inside := true
	for mph in [0.0, 300.0, 1000.0, 3000.0, 6000.0, 10000.0, 14000.0]:
		var last := -INF
		for g in range(-300, 301, 5):
			var want: float = Rush.target(float(g), mph)
			rising = rising and want >= last
			inside = inside and want <= Rush.FWD_MAX and want >= -Rush.AFT_MAX
			last = want
	_check("what is asked of the cockpit rises with the load at every speed, and is inside the travel whatever the load (%.0f mm forward, %.0f mm back): at 30 g off the line %.1f mm, at 3,000 mph and 15 g %.1f mm, at 10,000 mph and no load %.1f mm, in a light squeeze there %.1f mm" % [
			Rush.FWD_MAX * 1000.0, Rush.AFT_MAX * 1000.0, Rush.target(30.0, 200.0) * 1000.0, Rush.target(15.0, 3000.0) * 1000.0, Rush.target(0.0, 10000.0) * 1000.0, Rush.target(-20.0, 10000.0) * 1000.0],
		rising and inside and Rush.FWD_MAX <= 0.04 and Rush.AFT_MAX <= 0.03 and Rush.target(0.0, 0.0) == 0.0)
	var run := _scripted(true)
	var e: Array = run.ends
	var top: float = run.mph[7]
	_check("off the line (30 g) the cockpit eases away: %.1f mm a second into the launch, %.1f mm by 3 s (%.0f mph)" % [float(run.early) * 1000.0, float(e[1]) * 1000.0, float(run.mph[1])],
		float(run.early) > 0.004 and float(e[1]) > 0.014 and float(e[1]) < 0.028)
	_check("it stays out as the pull fades and the speed builds: %.1f mm at %.0f mph (22 g), %.1f at %.0f (15 g), %.1f at %.0f (10 g), %.1f at %.0f (4 g)" % [
			float(e[2]) * 1000.0, float(run.mph[2]), float(e[3]) * 1000.0, float(run.mph[3]), float(e[4]) * 1000.0, float(run.mph[4]), float(e[5]) * 1000.0, float(run.mph[5])],
		float(e[2]) > 0.014 and float(e[3]) > 0.014 and float(e[4]) > 0.012 and float(e[5]) > 0.010)
	_check("holding %.0f mph with no load it stands at the speed's own part: %.1f mm (%.1f asked)" % [top, float(e[7]) * 1000.0, Rush.speed_part(top) * 1000.0],
		top > 9900.0 and absf(float(e[7]) - Rush.speed_part(top)) < 0.0005 and float(e[7]) > 0.012)
	_check("a light squeeze of the air brakes (20 g) brings it %.1f mm back toward the pilot (to %.1f mm); on the throttle again it goes out (%.1f mm); a firm squeeze (60 g) brings it %.1f mm back (to %.1f mm)" % [
			(float(e[7]) - float(e[8])) * 1000.0, float(e[8]) * 1000.0, float(e[9]) * 1000.0, (float(e[9]) - float(e[10])) * 1000.0, float(e[10]) * 1000.0],
		float(e[7]) - float(e[8]) > 0.005 and float(e[7]) - float(e[8]) < 0.016 and float(e[9]) > float(e[7]) and float(e[10]) < float(e[8]) - 0.003)
	_check("full brakes to a stop, and at rest it is home: %.2f mm, having come no further than %.2f mm past its rest on the way" % [float(e[13]) * 1000.0, float(run.rebound) * 1000.0],
		float(run.mph[12]) == 0.0 and absf(float(e[13])) < 0.0003 and float(run.rebound) < 0.0003)
	_check("all the way it is inside its travel (%.1f mm forward at most of %.0f, %.1f mm back of %.0f), never faster than %.0f mm/s (%.1f) and never pushed harder than %.2f m/s2 (%.3f)" % [
			float(run.fwd) * 1000.0, Rush.FWD_MAX * 1000.0, float(run.aft) * 1000.0, Rush.AFT_MAX * 1000.0, Rush.RATE_MAX * 1000.0, float(run.rate) * 1000.0, Rush.ACCEL_MAX, float(run.accel)],
		float(run.fwd) <= Rush.FWD_MAX and float(run.aft) <= Rush.AFT_MAX and float(run.fwd) > 0.015 and float(run.aft) > 0.002
		and float(run.rate) <= Rush.RATE_MAX * 1.001 and float(run.accel) <= Rush.ACCEL_MAX * 1.02 and Rush.RATE_MAX <= 0.1 and Rush.ACCEL_MAX <= 0.6)
	var off := _scripted(false)
	_check("switched off, the same run never moves it (%.6f mm at most)" % (float(off.moved) * 1000.0), float(off.moved) == 0.0)


# --- the cockpit ---

var mps := 0.0
var clock := 0.0


## A frame of the real cockpit with the craft's speed scripted: `g` is the load along her nose for this frame.
## (The sim is not stepped: she stands where she was and her speed is told, so nothing but the rush has a
## reason to move.) -> the frame's time.
func _frame(g: float) -> float:
	await process_frame
	var delta: float = v.get_process_delta_time()
	if delta <= 0.0:
		return 0.0
	var sim = v.sim
	mps = maxf(0.0, mps + g * 9.81 * delta)
	sim.time += delta
	for b in sim.bodies:
		b.vx = mps * cos(sim.pod.th)
		b.vy = mps * sin(sim.pod.th)
	v._read_g()
	v._place_camera(1.0)
	v._apply_shudder(delta)
	v._sync_rush(delta)
	clock += delta
	return delta


## Frames for `seconds` under load g, watching what must not move. -> how many frames it did.
var rig_at: Transform3D
var cam_at: Transform3D
var moved_frames := 0          # frames in which the rig, the origin or the camera were not exactly where they began
var skewed_frames := 0         # frames in which the shell was turned, or off its own nose's line, or not where the rush has it
var worst_rate := 0.0
func _fly(seconds: float, g: float) -> void:
	var until := clock + seconds
	while clock < until:
		var before: float = v.shell.position.z
		var delta: float = await _frame(g)
		if delta <= 0.0:
			continue
		if v.rig.transform != rig_at or v.origin.transform != Transform3D(Basis.IDENTITY, Cockpit.EYE) or v.cam.global_transform != cam_at:
			moved_frames += 1
		var place: Vector3 = v.shell.position - v._shake
		if v.shell.transform.basis != Basis.IDENTITY or place.x != 0.0 or place.y != 0.0 or v.shell.position != v._shake + Vector3(0.0, 0.0, -v.rush.surge):
			skewed_frames += 1
		if v._shake == Vector3.ZERO:
			worst_rate = maxf(worst_rate, absf(v.shell.position.z - before) / delta)


func _the_cockpit() -> void:
	v = Cockpit.new()
	root.add_child(v)
	await process_frame
	v.set_process(false)
	for hand in v.hands.values():
		hand.get_child(0).visible = false
	_check("with nothing saved the speed rush is on, and the cockpit has its streaks, hidden at rest", Cockpit.speed_rush and v.rush != null and v.rush.streaks != null and not v.rush.streaks.visible)
	for i in 30:
		await _frame(0.0)
	rig_at = v.rig.transform
	cam_at = v.cam.global_transform
	var anchors := [v.craft._pod_anchor(v.sim, 0), v.craft._pod_anchor(v.sim, 1)]
	var hooks := [v._hardpoints[0].position, v._hardpoints[1].position]
	await _fly(0.6, 0.0)
	_check("at rest the shell stands exactly at its place (%s), the origin on the eye point" % v.shell.position, v.shell.position == Vector3.ZERO and v.origin.transform == Transform3D(Basis.IDENTITY, Cockpit.EYE))
	# a launch: 30 g for 3 s
	await _fly(3.0, 30.0)
	var launched: float = -v.shell.position.z
	var launch_mph := mps * MPH
	_check("a launch (30 g for 3 s, to %.0f mph) eases the shell %.1f mm forward along its own nose" % [launch_mph, launched * 1000.0], launched > 0.012 and launched < 0.028)
	var hook_ok := true
	var hook_worst := 0.0
	for k in 2:
		var shift: Vector3 = v._rush_shift
		hook_ok = hook_ok and v._hardpoints[k].position == (hooks[k] as Vector3) + shift
		hook_worst = maxf(hook_worst, (v.craft._pod_anchor(v.sim, k) - ((anchors[k] as Vector3) + v.rig.transform.basis * shift)).length())
	_check("the tow links' hooks have gone with the nose (the links' ends %.4f mm off it at worst)" % (hook_worst * 1000.0), hook_ok and hook_worst < 1e-5 and v._rush_shift.z < -0.012)
	# the streaks at speed
	var rush = v.rush
	var streak_at: Vector3 = rush.transform.origin
	var way: Vector3 = -rush.transform.basis.z
	var flown := Vector3(v.sim.pod.vx, 0.0, -v.sim.pod.vy).normalized()
	_check("at %.0f mph the streaks are out: %.0f%% of them, %.1f m long, in the air's frame (its origin %.4f m from the seated eye, its way %.3f degrees off the craft's)" % [
			launch_mph, float(rush.mat.get_shader_parameter("amount")) * 100.0, float(rush.mat.get_shader_parameter("streak_length")), streak_at.distance_to(v.rig.transform * Cockpit.EYE), rad_to_deg(way.angle_to(flown))],
		rush.streaks.visible and float(rush.mat.get_shader_parameter("strength")) > 0.05 and float(rush.mat.get_shader_parameter("amount")) > 0.3 and float(rush.mat.get_shader_parameter("amount")) < 1.0
		and streak_at.distance_to(v.rig.transform * Cockpit.EYE) < 1e-5 and way.angle_to(flown) < deg_to_rad(0.6) and rush.streaks.material_override == rush.mat)
	# held: the speed's part alone
	await _fly(2.5, 0.0)
	var held: float = -v.shell.position.z
	_check("holding %.0f mph it settles at the speed's part: %.1f mm (%.1f asked)" % [mps * MPH, held * 1000.0, Rush.speed_part(mps * MPH) * 1000.0], absf(held - Rush.speed_part(mps * MPH)) < 0.001 and held > 0.005)
	# the air brakes
	await _fly(2.0, -25.0)
	var braked: float = -v.shell.position.z
	_check("the air brakes (25 g for 2 s, down to %.0f mph) bring it %.1f mm back toward the pilot (to %.1f mm)" % [mps * MPH, (held - braked) * 1000.0, braked * 1000.0], held - braked > 0.005)
	# with the shudder: the gear's grab jolts the shell while the rush has it out
	await _fly(1.0, 12.0)
	v._grab = 1.0
	v._grab_t = 0.0
	var jolted := 0.0
	var summed := true
	for i in 12:
		await _frame(12.0)
		jolted = maxf(jolted, v._shake.length())
		summed = summed and v.shell.position == v._shake + v._rush_shift and v._rush_shift.z < -0.004
	_check("it adds to the shudder: a gear's grab jolts the shell %.1f mm about where the rush has it (%.1f mm forward)" % [jolted * 1000.0, -v._rush_shift.z * 1000.0], jolted > 0.001 and summed)
	while v._grab > 0.0:      # (the jolt dies away)
		await _frame(0.0)
	# an outside camera
	Cockpit.camera = "chase"
	for i in 4:
		await _frame(0.0)
	var chase_origin: bool = v.origin.transform != Transform3D(Basis.IDENTITY, Cockpit.EYE)
	var until := clock + 2.5
	while clock < until:
		await _frame(0.0)
	_check("an outside camera has none of it: the shell is home (%s) and the streaks are in" % v.shell.position, chase_origin and v.shell.position == Vector3.ZERO and not rush.streaks.visible)
	Cockpit.camera = "cockpit"
	await _fly(2.0, 0.0)
	_check("back in the seat it is out again (%.1f mm) and so are they" % (-v.shell.position.z * 1000.0), -v.shell.position.z > 0.004 and rush.streaks.visible)
	_check("through all of that the rig, the headset's origin and the camera were exactly where they began (%d frames in which one was not), and the shell was never turned nor off its nose's line (%d frames); it never moved faster than %.0f mm/s (%.1f)" % [
			moved_frames, skewed_frames, Rush.RATE_MAX * 1000.0, worst_rate * 1000.0],
		moved_frames == 0 and skewed_frames == 0 and worst_rate <= Rush.RATE_MAX * 1.05 and worst_rate > 0.005)
	# the page
	v.menu_open(true)
	_go("options")
	var line_on: bool = v.menu.text().contains("SPEED RUSH   ON")
	_go("rush")
	var line_off: bool = v.menu.text().contains("SPEED RUSH   OFF") and v.menu.key() == "rush"
	_check("the OPTIONS page has SPEED RUSH, on (%s); chosen, it reads OFF and is saved (\"%s\")" % [line_on, _saved().get("rush", "")], line_on and line_off and not Cockpit.speed_rush and _saved().get("rush", "") == "off")
	v.menu_open(false)
	# switched off at speed: home, and then exactly where the shudder alone puts it
	var out_before: float = -v.shell.position.z
	until = clock + 2.5
	var home_at := -1.0
	while clock < until:
		await _frame(0.0)
		if home_at < 0.0 and v.shell.position == Vector3.ZERO:
			home_at = clock - (until - 2.5)
	_check("switched off at %.0f mph the shell eases home from %.1f mm (there in %.1f s) and the streaks go" % [mps * MPH, out_before * 1000.0, home_at], out_before > 0.004 and home_at > 0.2 and v.shell.position == Vector3.ZERO and not rush.streaks.visible)
	var strayed := 0
	v._grab = 1.0
	v._grab_t = 0.0
	var shaken := 0.0
	until = clock + 2.0
	while clock < until:      # another launch's worth of load, and a gear's grab, switched off
		await _frame(30.0)
		shaken = maxf(shaken, v._shake.length())
		if v.shell.position != v._shake or v._rush_shift != Vector3.ZERO or rush.streaks.visible or v._hardpoints[0].position != hooks[0] or v.craft._pod_anchor(v.sim, 0) != anchors[0]:
			strayed += 1
	_check("off, a 30 g pull to %.0f mph leaves the shell exactly where the shudder alone puts it (%d frames in which it was not; the grab still jolts it %.1f mm), the hooks where they were and no streak drawn" % [mps * MPH, strayed, shaken * 1000.0],
		strayed == 0 and shaken > 0.001 and mps * MPH > 1000.0)
	v.menu_open(true)
	_go("options")
	_go("rush")
	_check("switched on again it is saved so (\"%s\")" % _saved().get("rush", ""), Cockpit.speed_rush and _saved().get("rush", "") == "on" and v.menu.text().contains("SPEED RUSH   ON"))
	v.menu_open(false)
	while v._grab > 0.0:
		await _frame(0.0)


# --- in sight ---

## What stands in the way from `from` to `to` (shell metres): the name of the first of the cockpit's solid
## parts found there, "" if the way is clear.
func _blocked_by(solids: Array, from: Vector3, to: Vector3) -> String:
	var short := from + (to - from) * 0.995
	for solid in solids:
		var into: Transform3D = solid[1]
		if not (solid[0] as TriangleMesh).intersect_segment(into * from, into * short).is_empty():
			return String(solid[2])
	return ""


func _in_sight() -> void:
	var solids := []      # [the part's triangles, shell metres -> its own]
	var shell: Node3D = v.shell
	for node in shell.find_children("*", "MeshInstance3D", true, false):
		var part := node as MeshInstance3D
		if part.mesh == null or not part.is_visible_in_tree():
			continue
		if v.dashboard.is_ancestor_of(part) and part.name != "binnacle":      # (the dials, needles, lamps and glass are what is looked at)
			continue
		if v.canopy.is_ancestor_of(part) and part.name != "roof":             # (glass, the field, the reflection: looked through)
			continue
		var tris := part.mesh.generate_triangle_mesh()
		if tris != null:
			solids.append([tris, part.global_transform.affine_inverse() * shell.global_transform, part.name])
	var mount: Transform3D = v.dashboard.transform
	var points := []
	for g in Layout.GAUGES:      # two rings on each dial's face, a little proud of it (not its middle: the needles' hub stands there)
		var on_face: Transform3D = mount * Kit.on_arc(g.x, g.y, 0.0, Layout.R)
		for k in 8:
			for r in [0.5, 0.85]:
				var a := TAU * (k + 0.5) / 8.0
				points.append(on_face * Vector3(r * float(g.rf) * cos(a), r * float(g.rf) * sin(a), float(g.face) + 0.004))
	for w in Layout.WINDOWS:      # the LCD strips
		var on_strip: Transform3D = mount * Kit.on_arc(w[1], w[2], 0.0, Layout.R)
		for x in [-0.85, 0.0, 0.85]:
			points.append(on_strip * Vector3(x * float(w[3]), 0.0, float(w[5]) + 0.003))
	# the cockpit moved forward is the eye moved back in it, and the other way about
	var eyes := {"at rest": Cockpit.EYE, "fully forward": Cockpit.EYE + Vector3(0.0, 0.0, Rush.FWD_MAX), "fully back": Cockpit.EYE - Vector3(0.0, 0.0, Rush.AFT_MAX)}
	var seen := {}
	var down := {}
	var hidden := []
	var mach: Vector3 = mount * Kit.on_arc(Layout.GAUGES[0].x, Layout.GAUGES[0].y, 0.0, Layout.R) * Vector3(0.0, 0.0, float(Layout.GAUGES[0].face))
	for name in eyes:
		var eye: Vector3 = eyes[name]
		var can := []
		for i in points.size():
			var by := _blocked_by(solids, eye, points[i])
			can.append(by == "")
			if by != "":
				hidden.append("point %d %s behind %s %s" % [i, points[i], by, name])
		seen[name] = can
		down[name] = rad_to_deg(atan2(eye.y - mach.y, Vector2(mach.x - eye.x, mach.z - eye.z).length()))
	var at_rest: int = (seen["at rest"] as Array).count(true)
	var lost := {"fully forward": 0, "fully back": 0}
	for name in lost:
		for i in points.size():
			lost[name] += int(seen["at rest"][i] and not seen[name][i])
	_check("the instruments stay in sight: of %d points on the dials and strips %d are in sight from the seat (through %d solid parts), and with the cockpit %.0f mm forward %d of those are lost, %.0f mm back %d (the Mach dial's centre %.1f degrees under level at rest, %.1f and %.1f at the ends; %.2f, %.2f and %.2f m off)" % [
			points.size(), at_rest, solids.size(), Rush.FWD_MAX * 1000.0, lost["fully forward"], Rush.AFT_MAX * 1000.0, lost["fully back"], down["at rest"], down["fully forward"], down["fully back"],
			(eyes["at rest"] as Vector3).distance_to(mach), (eyes["fully forward"] as Vector3).distance_to(mach), (eyes["fully back"] as Vector3).distance_to(mach)] + ("" if hidden.is_empty() else " [" + "; ".join(hidden) + "]"),
		at_rest >= points.size() * 9 / 10 and solids.size() > 5 and lost["fully forward"] == 0 and lost["fully back"] == 0)


# --- the streaks ---

func _the_streaks() -> void:
	var longer := true
	var more := true
	var brighter := true
	var last := [0.0, 0.0, 0.0]
	var told := []
	for mph in [300.0, 1000.0, 3000.0, 5000.0, 8000.0, 10000.0]:
		var share: float = Rush.speed_share(mph)
		var now := [Rush.streak_length(share), Rush.streak_amount(share), Rush.streak_strength(share)]
		if mph > 300.0:
			longer = longer and now[0] > last[0]
			more = more and now[1] > last[1]
			brighter = brighter and now[2] > last[2]
		told.append("%.0f: %.1f m, %.0f%%, %.2f" % [mph, now[0], now[1] * 100.0, now[2]])
		last = now
	_check("the streaks are longer, more and brighter as the speed builds (mph: length, how many, how bright: %s), none at or under 300 mph, and a fresh set is %d quads with nothing in the middle %.0f degrees" % [
			"; ".join(told), Rush.COUNT, Rush.CLEAR.x],
		longer and more and brighter and Rush.streak_strength(Rush.speed_share(300.0)) == 0.0 and Rush.streak_amount(0.0) == 0.0 and Rush.CLEAR.x >= 20.0 and Rush.CLEAR.y > Rush.CLEAR.x
		and Rush.RADIUS.x >= 1.5 and Rush.streak_mesh().get_faces().size() == Rush.COUNT * 6)
	# a frame's travel: as far as the craft has gone, but never further than a streak can go by and still be seen to stream
	var rush = Rush.new()
	rush.build(v)
	var stepped := []
	for mph in [400.0, 3000.0, 10000.0]:
		var before: float = rush.travel
		rush.shown = 1.0
		rush.sync(FRAME, mph, true, Transform3D.IDENTITY)
		stepped.append((rush.travel - before) / Rush.streak_length(Rush.speed_share(mph)))
	_check("in a frame a streak goes by no more than %.2f of its own length (at 400, 3,000 and 10,000 mph: %.2f, %.2f, %.2f)" % [Rush.STEP_MAX, stepped[0], stepped[1], stepped[2]],
		stepped[0] > 0.05 and stepped[0] <= Rush.STEP_MAX + 1e-4 and stepped[1] <= Rush.STEP_MAX + 1e-4 and stepped[2] <= Rush.STEP_MAX + 1e-4)
	rush.free()
	await _pixels()


## Windowed: the picture with the streaks and without them, at 3,000 mph, the head turned LOOK degrees to the
## left with a headset's own sharpness (38 degrees up and down the window): the picture runs from inside the
## clear middle out to the side.
const LOOK := 46.0
func _pixels() -> void:
	if DisplayServer.get_name() == "headless":
		print("SKIP the streaks' pixels (headless: run windowed to read them back)")
		return
	root.msaa_3d = Viewport.MSAA_4X
	mps = 3000.0 / MPH
	v.cam.position = Vector3.ZERO
	v.cam.rotation_degrees = Vector3(0.0, LOOK, 0.0)
	v.cam.fov = 38.0
	for i in 90:
		await _frame(0.0)
	v.rush.shown = 1.0
	await _frame(0.0)
	v.rush.travel = 137.0      # (the same streaks every time the picture is taken)
	v._sync_rush(0.0)
	v.rush.mat.set_shader_parameter("strength", 1.0)      # (made bright for the reading: where they are drawn is what is read, not how bright)
	var shots := []
	for drawn_now in [false, true, false]:
		v.rush.streaks.visible = drawn_now
		for i in 3:
			await process_frame
		await RenderingServer.frame_post_draw
		shots.append(root.get_texture().get_image())
	var size: Vector2i = shots[0].get_size()
	var focal: float = size.y * 0.5 / tan(deg_to_rad(v.cam.fov) * 0.5)
	var ahead: Vector3 = v.cam.basis.inverse() * Vector3.FORWARD      # the craft's way, as the camera has it
	var lit := 0
	var inside := 0
	var nearest := INF
	var reach := Vector2(INF, -INF)
	for y in range(0, size.y, 2):
		for x in range(0, size.x, 2):
			var off := rad_to_deg(Vector3(x - size.x * 0.5, size.y * 0.5 - y, -focal).angle_to(ahead))
			reach = Vector2(minf(reach.x, off), maxf(reach.y, off))
			var a: Color = shots[0].get_pixel(x, y)
			var b: Color = shots[1].get_pixel(x, y)
			var c: Color = shots[2].get_pixel(x, y)
			if absf(a.r - c.r) + absf(a.g - c.g) + absf(a.b - c.b) > 0.01:      # (something of the scene's own changed here between the two plain pictures)
				continue
			if maxf(b.r - a.r, maxf(b.g - a.g, b.b - a.b)) < 0.02:
				continue
			lit += 1
			nearest = minf(nearest, off)
			inside += int(off < Rush.CLEAR.x - 1.0)
	_check("at 3,000 mph the streaks draw (made bright, %d of the picture's sampled pixels are lit by them), none within %.0f degrees of dead ahead (the nearest %.1f degrees off it; the picture runs from %.0f to %.0f)" % [
			lit, Rush.CLEAR.x, nearest, reach.x, reach.y], lit > 150 and inside == 0 and nearest < Rush.CLEAR.y and reach.x < Rush.CLEAR.x - 5.0)
	v.cam.rotation = Vector3.ZERO


func _run() -> void:
	var prefs_before := FileAccess.get_file_as_string(Cockpit.PREFS) if FileAccess.file_exists(Cockpit.PREFS) else ""
	if prefs_before != "":      # a pilot with nothing saved: what he gets
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Cockpit.PREFS))
	_the_run()
	await _the_cockpit()
	_in_sight()
	await _the_streaks()
	v.queue_free()
	await process_frame
	if prefs_before == "":
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Cockpit.PREFS))
	else:
		var out := FileAccess.open(Cockpit.PREFS, FileAccess.WRITE)
		out.store_string(prefs_before)
		out.close()
	Cockpit.speed_rush = true
	print("SPEED RUSH %s (%d checks, %d failures)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)
