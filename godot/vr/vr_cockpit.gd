## M2 VR seat: seated OpenXR cockpit riding the pod. The pod is your frame of reference;
## the engines, binder and cables run out ahead of you, and the cockpit lists with the pod.
## Touch controllers stand in for the printed levers, in four schemes (QuestControls; a tap on
## the left menu button cycles them, the choice is saved): trigger throttles, throttle + steer,
## grab the levers, stick levers. Buttons, every scheme:
##   A reignite · B arm ramjet · X repair · thumbstick click recenter (view and seat height)
##   the MODE switch on the right console: push it up for SPEEDCRAFT, down for STARFIGHTER (live,
##   mid-lap; STARFIGHTER takes below 1,250 mph). Y hold 1 s flips it too. Y tap: restart
##   menu tap: next control scheme · menu hold 1.5 s: next track (range, grand prix, Eridanus)
## Haptics: a kick on the sonic boom; a tick in that hand when a lever crosses the burner gate.
## The printed levers / a gamepad win whenever they're moving; the keyboard still works.
## Logs OpenXR session events and a frame-timing summary every 10 s; writes a CSV on exit.
extends "res://view/craft_view.gd"

const SEAT := Vector3(0.0, 0.72, 0.6)  # eye point in pod space (pod forward = -Z): a little above the
                                        # cockpit rim (Luke: "sit a bit lower", then "view higher by default")
const FLOOR_H := 0.7                    # pod floor above the ground
const QuestControlsScript := preload("res://input/quest_controls.gd")
const PREFS := "user://vr_prefs.json"
const Y_HOLD := 1.0
const MENU_HOLD := 1.5   # hold the left menu button this long to switch track
const DashboardScript := preload("res://vr/dashboard.gd")
const CockpitInteriorScript := preload("res://vr/cockpit_interior.gd")
const ModeSwitchScript := preload("res://vr/mode_switch.gd")
const CanopyScript := preload("res://view/canopy.gd")
const MinimapPanelScript := preload("res://vr/minimap_panel.gd")
const Kit := preload("res://view/mesh_kit.gd")

var xr: XRInterface
var rig: Node3D
var shell: Node3D   # the cockpit's fittings (hull, seat, levers, panel): shudders, your head doesn't
var interior   # vr/cockpit_interior.gd
var mode_switch   # vr/mode_switch.gd: the SPEEDCRAFT / STARFIGHTER toggle on the right console
var canopy: Node3D   # view/canopy.gd: the windscreen ahead and the forcefield round the nose
var minimap_panel: Node3D   # vr/minimap_panel.gd
var _ride := {}   # CraftModel.ride's smoothing state
var _buzz_hold := {}   # controller -> seconds an event buzz still owns it (the shudder waits)
const SHAKE_M := 0.004   # cockpit shake per unit of air-brake shudder, metres
var origin: XROrigin3D
var hands := {}
var lever_pivots: Array[Node3D] = []
var lever_tips: Array[StandardMaterial3D] = []
var dashboard   # the instrument panel (vr/dashboard.gd)
var fade_mat: StandardMaterial3D
var fade_v := 0.0
var edges := {}
var frame_ms := PackedFloat32Array()
var report_t := 0.0
var quest
var _y_held := 0.0
var _menu_held := 0.0
var _menu_fired := false
var _switch_at := -1     # --switch-track-at=FRAMES: switch track by itself (tests the reload path)
var _frames := 0
var _y_fired := false
var _scheme_flash := 0.0


func _ready() -> void:
	quest = QuestControlsScript.new()
	super()
	var prefs := _load_prefs()
	if QuestControlsScript.SCHEMES.has(prefs.get("scheme", "")):
		quest.scheme = prefs.scheme
	var forced := false
	for a in OS.get_cmdline_user_args():
		forced = forced or a.begins_with("--handling=")
	# the saved handling applies to the range; the grand prix is a STARFIGHTER course
	if not forced and not sim.course and prefs.get("handling", "speed") != sim.P.handling:
		set_handling(prefs.handling)
	handling_ask = sim.P.handling
	_scheme_flash = 6.0
	if wind_audio:
		wind_audio.boomed.connect(_on_boom)
	print("CONTROLS: %s, %s handling" % [quest.scheme, sim.P.handling])
	print("TRACK: %s" % _track())
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--switch-track-at="):
			_switch_at = int(a.get_slice("=", 1))


func _load_prefs() -> Dictionary:
	if FileAccess.file_exists(PREFS):
		var d = JSON.parse_string(FileAccess.get_file_as_string(PREFS))
		if d is Dictionary:
			return d
	return {}


func _save_prefs() -> void:
	var f := FileAccess.open(PREFS, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"scheme": quest.scheme, "handling": handling_ask if handling_ask != "" else sim.P.handling}))


## Thumbstick click (either stick): sit where you are. Recentres the view AND the height, so
## your eyes land on the seat's eye point (Luke: "can I get a vertical height reset somewhere").
## The automatic recentre when the headset goes on keeps your height; this one resets it.
func recenter() -> void:
	XRServer.center_on_hmd(XRServer.RESET_BUT_KEEP_TILT, false)
	print("RECENTER: view and seat height")
	if hands.has("left"):
		_buzz(hands.left, 0.3, 0.05)
		_buzz(hands.right, 0.3, 0.05)


func _buzz(c: XRController3D, amp: float, dur: float, delay := 0.0) -> void:
	c.trigger_haptic_pulse("haptic", 0.0, amp, dur, delay)
	_buzz_hold[c] = dur + delay


## The air brakes shudder (Luke: "should have a shudder to them too"): each side's shudder from
## the wind audio (the same bursts you hear) trembles the hand on that brake (the left brake is
## the left hand in every scheme) and shakes the cockpit around you by a few millimetres. Never
## the view itself: your head stays put. Event buzzes (hits, the gate) win while they last.
func _apply_shudder(delta: float) -> void:
	for c in _buzz_hold.keys():
		_buzz_hold[c] = maxf(0.0, _buzz_hold[c] - delta)
	if not wind_audio:
		return
	var s: Array = wind_audio.shudder
	var w: Array = wind_audio.shake
	for k in 2:
		var hand: XRController3D = hands.left if k == 0 else hands.right
		if s[k] > 0.06 and _buzz_hold.get(hand, 0.0) <= 0.0:
			hand.trigger_haptic_pulse("haptic", 0.0, 0.2 + 0.6 * s[k], 0.05, 0.0)
	var up: float = s[0] * w[0] + s[1] * w[1]
	var side: float = s[0] * w[0] - s[1] * w[1]
	shell.position = Vector3(0.6 * side, up, 0.0) * SHAKE_M


## Wall contact buzzes the hand that drives the engine that touched (with crossed trigger
## throttles the right engine is the left hand's), both hands for the pod; a scrape is light.
func _on_hit(who: String, strength: float) -> void:
	var hand_for := {"L": "left", "R": "right"}
	if quest.scheme == "triggers":
		hand_for = {"L": "right", "R": "left"}
	var amp := 0.85 * strength
	var dur := 0.14 if strength >= 1.0 else 0.06
	if who == "pod":
		_buzz(hands.left, amp, dur)
		_buzz(hands.right, amp, dur)
	elif hand_for.has(who):
		_buzz(hands[hand_for[who]], amp, dur)


func _on_boom() -> void:
	for side in ["left", "right"]:
		_buzz(hands[side], 1.0, 0.3)
		_buzz(hands[side], 0.55, 1.2, 0.3)


func _make_view() -> void:
	xr = XRServer.find_interface("OpenXR")
	var live := xr != null and xr.is_initialized()
	if live:
		get_viewport().use_xr = true
		# MSAA, not TAA/FSR2: temporal AA smears at these speeds and differs eye to eye. 4x costs
		# ~0.6 ms on the 5080 at Quest 3 resolution (1.66 -> 2.23 ms GPU, both eyes, Eridanus start).
		# Shaders must survive it: edge samples see UVs off the quad (view/pylon.gdshader).
		get_viewport().msaa_3d = Viewport.MSAA_4X
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
		print("OPENXR: initialized, MSAA 4x")
	else:
		print("OPENXR: NOT initialized, running flat (is the Quest on and in Link mode?)")

	rig = Node3D.new()
	add_child(rig)
	origin = XROrigin3D.new()
	origin.position = SEAT
	rig.add_child(origin)
	var xr_cam := XRCamera3D.new()
	xr_cam.far = 120000   # the backdrop peaks sit at 45-57 km; Eridanus' far ranges up to ~100 km away
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
	craft.pod_frame = rig      # so the cables hook to the cockpit's own nose


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
	print("DIAG craft: scheme=%s grip=%.2f/%.2f brk=%.2f/%.2f shudder=%.2f/%.2f shake=%.1fmm hp=%.2f/%.2f pod=%.2f heat=%.2f/%.2f flameout=%s/%s mode=%s bat=%.2f btn X=%s Y=%s A=%s B=%s" % [
		quest.scheme, l.get_float("grip"), r.get_float("grip"), inp.brkL, inp.brkR,
		wind_audio.shudder[0] if wind_audio else 0.0, wind_audio.shudder[1] if wind_audio else 0.0, shell.position.length() * 1000.0,
		sim.eL.health, sim.eR.health, sim.pod.health,
		sim.eL.heat, sim.eR.heat, sim.eL.flameout, sim.eR.flameout, sim.mode, sim.battery,
		l.is_button_pressed("ax_button"), l.is_button_pressed("by_button"), r.is_button_pressed("ax_button"), r.is_button_pressed("by_button")])


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


func _rbox(parent: Node3D, size: Vector3, pos: Vector3, c: Color, rot_x := 0.0, n := 6.0, rough := 0.7) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = Kit.rounded_box(size, n)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = c
	mat.roughness = rough
	m.material_override = mat
	m.position = pos
	m.rotation.x = rot_x
	parent.add_child(m)
	return m


func _build_cockpit() -> void:
	var leather := Color(0.13, 0.12, 0.12)
	# You sit in the pod itself: the same polished hull the flat view shows, open cockpit,
	# rubber lip, matte trim inside, the nose and its cable hardpoints out ahead.
	shell = Node3D.new()
	shell.name = "shell"
	rig.add_child(shell)
	var hull := MeshInstance3D.new()
	hull.mesh = CraftModelScript.pod_hull()
	hull.position = Vector3(0, CraftModelScript.POD_FRAME_UP, 0)
	shell.add_child(hull)
	for s in [-1.0, 1.0]:   # where the cables hook (the hull carries the eyes themselves)
		var mark := Marker3D.new()
		mark.name = "hardpoint_%s" % ("l" if s < 0.0 else "r")
		mark.position = Vector3(0.18 * s, CraftModelScript.POD_FRAME_UP + CraftModelScript.POD_EYE_H, -2.1)
		rig.add_child(mark)   # anchors, not fittings: on the rig, steady through the shudder
	_rbox(shell, Vector3(0.62, 0.78, 0.13), Vector3(0, 0.54, 1.1), leather, -0.12, 5.0).name = "seat_back"   # its top is the headrest
	_rbox(shell, Vector3(0.6, 0.12, 0.52), Vector3(0, 0.145, 0.86), leather, 0.0, 5.0).name = "seat_cushion"   # both clear the hull floor (test_cables)
	for s in [-1.0, 1.0]:
		var pivot := Node3D.new()
		pivot.position = Vector3(0.46 * s, 0.1, 0.2)   # beside the seat, clear of the instrument panel
		shell.add_child(pivot)
		var shaft := MeshInstance3D.new()
		shaft.mesh = Kit.cyl(0.016, 0.016, 0.32, 12)
		var steel := StandardMaterial3D.new()
		steel.albedo_color = Color(0.75, 0.77, 0.8)
		steel.metallic = 0.9
		steel.roughness = 0.25
		shaft.material_override = steel
		shaft.position = Vector3(0, 0.16, 0)
		pivot.add_child(shaft)
		var knob := MeshInstance3D.new()
		knob.mesh = Kit.ball(0.04, 16)
		knob.scale = Vector3(1.0, 1.35, 1.0)
		var km := StandardMaterial3D.new()
		km.albedo_color = Color(0.16, 0.17, 0.19)
		km.roughness = 0.4
		knob.material_override = km
		knob.position = Vector3(0, 0.36, 0)
		pivot.add_child(knob)
		lever_pivots.append(pivot)
		lever_tips.append(km)
	# instrument panel: curved round the eye, inside the cockpit opening (clear of the hull),
	# low enough that the nose and its cable hardpoints still show over the top
	interior = CockpitInteriorScript.new()   # floor, frames, consoles, harness, rim light
	shell.add_child(interior)
	interior.build()
	mode_switch = ModeSwitchScript.new()   # SPEEDCRAFT / STARFIGHTER, on the front of the right console
	shell.add_child(mode_switch)
	mode_switch.transform = ModeSwitchScript.mount()
	mode_switch.build()
	canopy = CanopyScript.build()
	canopy.position = Vector3(0, CraftModelScript.POD_FRAME_UP, 0)
	shell.add_child(canopy)
	dashboard = DashboardScript.new()
	shell.add_child(dashboard)
	dashboard.transform = DashboardScript.mount()
	dashboard.build()
	minimap_panel = MinimapPanelScript.new()   # the path ahead, up and left of the instrument panel
	shell.add_child(minimap_panel)
	minimap_panel.transform = MinimapPanelScript.mount(SEAT)
	minimap_panel.build()
	minimap_panel.visible = sim.kind == "circuit"


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


func _read_input(delta: float) -> void:
	var p: Dictionary = levers.poll(delta)
	var l: XRController3D = hands.left
	var r: XRController3D = hands.right
	var c := {"lt": l.get_float("trigger"), "rt": r.get_float("trigger"), "lg": l.get_float("grip"), "rg": r.get_float("grip"),
		"ls": l.get_vector2("primary"), "rs": r.get_vector2("primary"), "lz": l.position.z, "rz": r.position.z,
		"speed": sqrt(sim.pod.vx * sim.pod.vx + sim.pod.vy * sim.pod.vy), "yaw": (sim.eL.w + sim.eR.w) / 2.0}
	var q: Dictionary = quest.update(c, delta)
	if q.tickL:
		_buzz(l, 0.35, 0.04)
	if q.tickR:
		_buzz(r, 0.35, 0.04)
	if levers.source.begins_with("Gamepad"):   # printed levers or a gamepad in use: they win
		inp = {"thrL": p.thrL, "thrR": p.thrR, "brkL": maxf(p.brkL, q.brkL), "brkR": maxf(p.brkR, q.brkR)}
	else:
		inp = {"thrL": maxf(p.thrL, q.thrL), "thrR": maxf(p.thrR, q.thrR), "brkL": maxf(p.brkL, q.brkL), "brkR": maxf(p.brkR, q.brkR)}
	inp.repair = p.repair or l.is_button_pressed("ax_button")
	inp.reignite = p.reignite or r.is_button_pressed("ax_button")
	if p.arm or _pressed_once("arm", r.is_button_pressed("by_button")):
		sim.armed = not sim.armed
	# Y: tap restarts, hold flips the handling (live, as the MODE switch)
	if p.respawn:
		_respawn()
	if l.is_button_pressed("by_button"):
		_y_held += delta
		if _y_held >= Y_HOLD and not _y_fired:
			_y_fired = true
			toggle_handling()
			_save_prefs()
			_buzz(l, 0.8, 0.15)
	else:
		if _y_held > 0.0 and not _y_fired:
			_respawn()
		_y_held = 0.0
		_y_fired = false
	match _menu(l.is_button_pressed("menu_button"), delta):
		"scheme":
			quest.next_scheme()
			_save_prefs()
			_scheme_flash = 4.0
			_buzz(l, 0.5, 0.08)
			print("CONTROLS: ", quest.scheme)
		"track":
			_buzz(l, 0.9, 0.2)
			_buzz(r, 0.9, 0.2)
			switch_track()
	_frames += 1
	if _switch_at > 0 and _frames == _switch_at and track_override == "":   # once
		switch_track()
	# the MODE switch: either hand can throw it
	if mode_switch:
		for hand in [l, r]:
			var flip: String = mode_switch.poke(hand, delta)
			if flip != "" and ask_handling(flip):   # (refused inside the cooldown: the lever springs back)
				_save_prefs()
				_buzz(hand, 0.9, 0.06)
				print("HANDLING: switch to ", flip)
	if _pressed_once("recenter", l.is_button_pressed("primary_click") or r.is_button_pressed("primary_click")):
		recenter()
	_diag(delta, l, r, p)


func _track() -> String:   # "range", "gp", "eridanus" (or "circuit")
	return sim.track_name if sim.course else ("range" if sim.kind == "range" else "circuit")


## The left menu button: a tap (released before MENU_HOLD) cycles the control scheme; holding it
## MENU_HOLD switches track. Returns "scheme", "track" or "".
func _menu(down: bool, delta: float) -> String:
	if down:
		_menu_held += delta
		if _menu_held >= MENU_HOLD and not _menu_fired:
			_menu_fired = true
			return "track"
		return ""
	var tapped := _menu_held > 0.0 and not _menu_fired
	_menu_held = 0.0
	_menu_fired = false
	return "scheme" if tapped else ""


## Range -> grand prix -> Eridanus -> range, in the headset: reload the scene on the next track (the OpenXR session
## carries on; CraftView.track_override survives the reload and wins over --track).
func switch_track() -> void:
	var to := next_track(_track())
	print("TRACK: switching %s -> %s" % [_track(), to])
	track_override = to
	get_tree().call_deferred("reload_current_scene")


## The menu hold's cycle: range -> grand prix -> Eridanus -> range (a plain circuit goes to the range).
static func next_track(cur: String) -> String:
	var order := ["range", "gp", "eridanus"]
	return order[(order.find(cur) + 1) % order.size()]


func _place_camera(_k: float) -> void:
	# The cockpit lists with the pod, rolled about your head rather than the floor: the view
	# tilts but your eyes don't swing sideways (a floor pivot moves them ~0.9 m at 60 deg).
	var yaw: float = sim.pod.th - PI / 2.0
	var b_yaw := Basis(Vector3.UP, yaw)
	# the ride over the banking, smoothed (CraftModel.ride: Luke, "going over hills makes the camera very shaky")
	var r := CraftModelScript.ride(self, sim, _ride, get_process_delta_time())
	var roll := clampf(craft.bank[2] + r.z, -CraftModelScript.ROLL_MAX, CraftModelScript.ROLL_MAX)
	var pitch := r.y   # up and down the banking
	var b_full := Basis.from_euler(Vector3(pitch, yaw, roll))   # lean + the track's banking (capped), and its slope
	var base := w3(sim.pod.x, sim.pod.y, sim.pod.z - 0.8 + CraftModelScript.POD_LIFT) + Vector3.UP * (r.x - surface(sim.pod.x, sim.pod.y).x)   # floor 0.8 m below the pod body centre, lifted with the pod
	var head := origin.position + cam.position
	rig.basis = b_full
	rig.position = base + b_yaw * head - b_full * head
	var thr := [inp.thrL, inp.thrR]
	for k in 2:
		lever_pivots[k].rotation.x = deg_to_rad(lerpf(30.0, -30.0, thr[k]))
		lever_tips[k].albedo_color = Color(1.0, 0.55, 0.15) if thr[k] >= sim.P.gate else Color(0.16, 0.17, 0.19)


func _process(delta: float) -> void:
	super(delta)
	_apply_shudder(delta)
	interior.set_mode(sim.mode, sim.hblend)
	# An untracked hand (flat runs, before the first pose) sits at the origin, i.e. on the eye: its
	# box's far face, 5 cm out on the near plane, z-fought into a dark rectangle mid-view.
	for side in hands:
		hands[side].get_child(0).visible = hands[side].get_has_tracking_data()
	CanopyScript.update(canopy, sqrt(sim.pod.vx * sim.pod.vx + sim.pod.vy * sim.pod.vy), sim.hblend, sim.mode, delta)
	if mode_switch:
		mode_switch.show_state(handling_ask == "starfighter", sim.hblend, handling_ask == "starfighter" and sim.hblend == 0.0)
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
	# The budget is the rate the headset really runs at: Link refuses the 90 Hz ask above and paces
	# at the Link app's setting (72 Hz on 2026-10-19), and a fixed 90 Hz line counted every paced
	# frame as a miss. 4% over the frame time is a miss, as 11.6 ms was at 90 Hz.
	var hz := 0.0
	if xr != null and xr.is_initialized() and "display_refresh_rate" in xr:
		hz = float(xr.get("display_refresh_rate"))
	var hz_src := "headset"
	if hz <= 0.0:
		hz = 90.0
		hz_src = "assumed"
	var budget := 1044.0 / hz
	var total := 0.0
	var slow := 0
	for v in recent:
		total += v
		if v > budget:
			slow += 1
	print("FRAMES: %.1f fps avg, p95 %.2f ms, %.1f%% over %.1f ms (%.0f Hz budget, %s), %d frames total" % [
		1000.0 * recent.size() / total, sorted[int(sorted.size() * 0.95)], 100.0 * slow / recent.size(),
		budget, hz, hz_src, n])


func _update_hud() -> void:
	var kmh := _kmh()
	_scheme_flash = maxf(0.0, _scheme_flash - get_process_delta_time())
	var ctl: String = QuestControlsScript.HINTS[quest.scheme] if _scheme_flash > 0.0 else QuestControlsScript.NAMES[quest.scheme]
	if minimap_panel.visible:
		minimap_panel.show_frame(minimap.update(sim.pod.th, get_process_delta_time()))
	dashboard.show_state({
		"mph": kmh / 1.609344, "kmh": kmh, "mach_line": cues.readout(), "progress": _progress_text(),
		"footer": "%s   /   %s" % [handling_text(), ctl],
		"thr": [inp.thrL, inp.thrR], "brk": [inp.brkL, inp.brkR], "heat": [sim.eL.heat, sim.eR.heat],
		"health": [sim.eL.health, sim.eR.health],
		"flameout": [sim.eL.flameout, sim.eR.flameout], "battery": sim.battery,
		"burner": sim.mode == "burner", "armed": sim.armed, "ramjet": sim.mode == "ramjet",
		"blink": (Time.get_ticks_msec() / 250) % 2 == 0,
	})


func _exit_tree() -> void:
	_report()
	var path := "user://frames_%s.csv" % Time.get_datetime_string_from_system().replace(":", "-")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_line("frame,ms")
		for i in frame_ms.size():
			f.store_line("%d,%.3f" % [i, frame_ms[i]])
		print("FRAMES: csv ", ProjectSettings.globalize_path(path))
