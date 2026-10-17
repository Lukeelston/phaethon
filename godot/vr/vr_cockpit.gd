## M2 VR seat: seated OpenXR cockpit riding the pod. The pod is your frame of reference;
## the engines, binder and cables run out ahead of you.
## Touch controllers stand in for the printed levers:
##   thumbstick up/down  moves that side's lever (it holds where you leave it)
##   trigger             that side's air brake
##   A reignite · B arm ramjet · X repair · Y respawn · thumbstick click recenter
## The printed levers / a gamepad / the keyboard still work through LeverInput.
## Logs OpenXR session events and a frame-timing summary every 10 s; writes a CSV on exit.
extends "res://view/craft_view.gd"

const SEAT := Vector3(0.0, 0.75, 0.6)   # eye point in pod space (pod forward = -Z)
const FLOOR_H := 0.7                    # pod floor above the ground
const STICK_DZ := 0.15

var xr: XRInterface
var rig: Node3D
var origin: XROrigin3D
var hands := {}
var lever_pivots: Array[Node3D] = []
var lever_tips: Array[StandardMaterial3D] = []
var dash: Label3D
var fade_mat: StandardMaterial3D
var fade_v := 0.0
var edges := {}
var frame_ms := PackedFloat32Array()
var report_t := 0.0


func _make_view() -> void:
	xr = XRServer.find_interface("OpenXR")
	var live := xr != null and xr.is_initialized()
	if live:
		get_viewport().use_xr = true
		# OpenXR paces frames; desktop vsync caps at 60 Hz and judders (Firefly Catcher, 2026-07-27).
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		for sig in ["session_begun", "session_visible", "session_focussed", "session_stopping", "pose_recentered"]:
			if xr.has_signal(sig):
				xr.connect(sig, _on_xr_event.bind(sig))
		if "display_refresh_rate" in xr:
			xr.set("display_refresh_rate", 90.0)
		# Sound in the headset, not on the desk: Windows' default output may be the PC speakers.
		for dev in AudioServer.get_output_device_list():
			if dev.contains("Oculus Virtual Audio"):
				AudioServer.output_device = dev
				print("AUDIO: output -> ", dev)
				break
		print("OPENXR: initialized")
	else:
		print("OPENXR: NOT initialized, running flat (is the Quest on and in Link mode?)")

	rig = Node3D.new()
	add_child(rig)
	origin = XROrigin3D.new()
	origin.position = SEAT
	rig.add_child(origin)
	var xr_cam := XRCamera3D.new()
	xr_cam.far = 30000
	origin.add_child(xr_cam)
	cam = xr_cam
	for side in ["left", "right"]:
		var c := XRController3D.new()
		c.tracker = "%s_hand" % side
		origin.add_child(c)
		hands[side] = c
		var m := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(0.04, 0.03, 0.1)
		m.mesh = b
		m.material_override = _mat(Color(0.2, 0.22, 0.25))
		c.add_child(m)
	_build_cockpit()
	_build_fade(xr_cam)
	pod_mesh.visible = false   # you are sitting inside it


func _on_xr_event(sig: String) -> void:
	print("OPENXR: ", sig)
	if sig == "session_focussed":
		XRServer.center_on_hmd(XRServer.RESET_BUT_KEEP_TILT, true)
		var trackers := XRServer.get_trackers(XRServer.TRACKER_CONTROLLER)
		for name in trackers:
			var t: XRPositionalTracker = trackers[name]
			print("DIAG tracker: %s profile=%s" % [name, t.profile])


var _diag_t := 0.0

# Once a second: every boundary of the input chain, so a dead control shows where it dies.
func _diag(delta: float, l: XRController3D, r: XRController3D, p: Dictionary) -> void:
	_diag_t += delta
	if _diag_t < 1.0:
		return
	_diag_t = 0.0
	var pads := []
	for d in Input.get_connected_joypads():
		pads.append("%d:%s known=%s ax0=%.2f ax1=%.2f" % [d, Input.get_joy_name(d), Input.is_joy_known(d),
			Input.get_joy_axis(d, 0), Input.get_joy_axis(d, 1)])
	print("DIAG input: pads=%s src=%s | L track=%s stick=%s trig=%.2f | R track=%s stick=%s trig=%.2f | poll thr=%.2f/%.2f | inp thr=%.2f/%.2f | v=%d km/h" % [
		pads, levers.source,
		l.get_has_tracking_data(), l.get_vector2("primary"), l.get_float("trigger"),
		r.get_has_tracking_data(), r.get_vector2("primary"), r.get_float("trigger"),
		p.thrL, p.thrR, inp.thrL, inp.thrR,
		int(sqrt(sim.pod.vx * sim.pod.vx + sim.pod.vy * sim.pod.vy) * 3.6)])


func _box(parent: Node3D, size: Vector3, pos: Vector3, c: Color, rot_x := 0.0) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	m.mesh = b
	m.material_override = _mat(c)
	m.position = pos
	m.rotation.x = rot_x
	parent.add_child(m)
	return m


func _build_cockpit() -> void:
	var hull := Color(0.55, 0.58, 0.62)
	var dark := Color(0.16, 0.17, 0.19)
	_box(rig, Vector3(1.8, 0.05, 2.6), Vector3(0, 0.0, 0.3), dark)               # floor
	for s in [-1.0, 1.0]:
		_box(rig, Vector3(0.08, 0.45, 2.6), Vector3(0.9 * s, 0.22, 0.3), hull)   # side cowls
	_box(rig, Vector3(1.8, 0.35, 0.3), Vector3(0, 0.3, -0.95), hull)             # front cowl, below eye line
	_box(rig, Vector3(1.2, 0.02, 0.35), Vector3(0, 0.48, -0.75), dark, 0.6)      # dash
	_box(rig, Vector3(0.7, 0.8, 0.1), Vector3(0, 0.5, 1.05), dark)               # seat back
	for s in [-1.0, 1.0]:
		var pivot := Node3D.new()
		pivot.position = Vector3(0.24 * s, 0.15, 0.05)
		rig.add_child(pivot)
		_box(pivot, Vector3(0.03, 0.32, 0.03), Vector3(0, 0.16, 0), Color(0.75, 0.77, 0.8))
		var tip := _box(pivot, Vector3(0.05, 0.11, 0.05), Vector3(0, 0.36, 0), dark)
		lever_pivots.append(pivot)
		lever_tips.append(tip.material_override)
	dash = Label3D.new()
	dash.position = Vector3(0, 0.56, -0.7)
	dash.rotation.x = -0.6
	dash.pixel_size = 0.0011
	dash.font_size = 40
	dash.modulate = Color(1.0, 0.75, 0.45)
	dash.outline_size = 0
	rig.add_child(dash)


func _build_fade(xr_cam: XRCamera3D) -> void:
	var m := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.25
	s.height = 0.5
	m.mesh = s
	fade_mat = StandardMaterial3D.new()
	fade_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fade_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fade_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	fade_mat.no_depth_test = true
	fade_mat.render_priority = 127
	fade_mat.albedo_color = Color(0, 0, 0, 0)
	m.material_override = fade_mat
	xr_cam.add_child(m)


func _pressed_once(key: String, down: bool) -> bool:
	var fired: bool = down and not edges.get(key, false)
	edges[key] = down
	return fired


static func _dz(v: float) -> float:
	return 0.0 if absf(v) < STICK_DZ else (v - signf(v) * STICK_DZ) / (1.0 - STICK_DZ)


func _read_input(delta: float) -> void:
	var p: Dictionary = levers.poll(delta)
	var l: XRController3D = hands.left
	var r: XRController3D = hands.right
	# Squeeze both grips: level both levers to the lower one.
	if _pressed_once("level", l.get_float("grip") > 0.7 and r.get_float("grip") > 0.7):
		levers.level_to_lower()
	for pair in [[l, "thr_l"], [r, "thr_r"]]:
		var stick := _dz((pair[0] as XRController3D).get_vector2("primary").y)
		var rate := 0.9 if stick > 0.0 else 1.4
		levers.set(pair[1], clampf(levers.get(pair[1]) + stick * rate * delta, 0.0, 1.0))
	inp = {"thrL": levers.thr_l, "thrR": levers.thr_r,
		"brkL": maxf(p.brkL, l.get_float("trigger")), "brkR": maxf(p.brkR, r.get_float("trigger")),
		"repair": p.repair or l.is_button_pressed("ax_button"),
		"reignite": p.reignite or r.is_button_pressed("ax_button")}
	if p.arm or _pressed_once("arm", r.is_button_pressed("by_button")):
		sim.armed = not sim.armed
	if p.respawn or _pressed_once("respawn", l.is_button_pressed("by_button")):
		_respawn()
	if _pressed_once("recenter", l.is_button_pressed("primary_click") or r.is_button_pressed("primary_click")):
		XRServer.center_on_hmd(XRServer.RESET_BUT_KEEP_TILT, true)
	_diag(delta, l, r, p)


func _place_camera(_k: float) -> void:
	rig.position = w3(sim.pod.x, sim.pod.y, sim.pod.z - 0.8)   # floor 0.8 m below the pod body centre
	rig.rotation = Vector3(0, sim.pod.th - PI / 2.0, 0)
	var thr := [inp.thrL, inp.thrR]
	for k in 2:
		lever_pivots[k].rotation.x = deg_to_rad(lerpf(30.0, -30.0, thr[k]))
		lever_tips[k].albedo_color = Color(1.0, 0.55, 0.15) if thr[k] >= sim.P.gate else Color(0.16, 0.17, 0.19)


func _process(delta: float) -> void:
	super(delta)
	# Crash: fade to black, respawn happens in the dark, fade back up.
	var target := 1.0 if sim.crash_t > 0.0 else 0.0
	fade_v = move_toward(fade_v, target, delta * 4.0)
	fade_mat.albedo_color = Color(0, 0, 0, fade_v)
	frame_ms.append(delta * 1000.0)
	report_t += delta
	if report_t >= 10.0:
		_report()
		report_t = 0.0


func _report() -> void:
	var n := frame_ms.size()
	if n == 0:
		return
	var recent := frame_ms.slice(maxi(0, n - 900))
	var sorted := recent.duplicate()
	sorted.sort()
	var total := 0.0
	var slow := 0
	for v in recent:
		total += v
		if v > 11.6:
			slow += 1
	print("FRAMES: %.1f fps avg, p95 %.2f ms, %.1f%% over 11.6 ms (90 Hz budget), %d frames total" % [
		1000.0 * recent.size() / total, sorted[int(sorted.size() * 0.95)], 100.0 * slow / recent.size(), n])


func _update_hud() -> void:
	var v := _kmh()
	var mode_txt: String = {"ramjet": "RAMJET", "burner": "AFTERBURNER"}.get(sim.mode, "RAMJET ARMED" if sim.armed else "")
	dash.text = "%d km/h  %d mph\n%s\nHEAT %d | %d   BAT %d\n%s" % [
		v, v / 1.609344, _progress_text(),
		sim.eL.heat * 100, sim.eR.heat * 100, sim.battery * 100, mode_txt]


func _exit_tree() -> void:
	_report()
	var path := "user://frames_%s.csv" % Time.get_datetime_string_from_system().replace(":", "-")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_line("frame,ms")
		for i in frame_ms.size():
			f.store_line("%d,%.3f" % [i, frame_ms[i]])
		print("FRAMES: csv ", ProjectSettings.globalize_path(path))
