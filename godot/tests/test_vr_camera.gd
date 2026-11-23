## The quick menu's camera change (Luke: "Will you also add a camera change to the pause menu?"):
## the seat, a chase view and a far one. Outside, the view is level and turns with the pod's
## heading only; back in the seat the origin is the eye point again.
## Optional screenshots use a window and -- --shots=DIR to save a picture of each camera.
extends SceneTree

const View := preload("res://view/craft_view.gd")
const Cockpit := preload("res://vr/vr_cockpit.gd")
var v
var failures := 0
var shots := ""


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			shots = arg.trim_prefix("--shots=")
	View.track_override = "network"
	View.job_override = "none"
	View.best_dir = OS.get_user_data_dir().path_join("test_vr_camera_")
	Cockpit.camera = "cockpit"
	Cockpit._camera_loaded = true      # the pilot's saved choice stays out of this
	_run.call_deferred()


func _check(label: String, passed: bool) -> void:
	print(("PASS " if passed else "FAIL ") + label)
	failures += int(not passed)


func _run() -> void:
	v = Cockpit.new()
	root.add_child(v)
	await process_frame
	v.set_process(false)
	var sim = v.sim
	sim.respawn_on(2, 9000, 1)       # E3, open country
	var L = sim.roads[2]
	for b in sim.bodies:
		b.vx = 1400.0 * L.tx[9000]
		b.vy = 1400.0 * L.ty[9000]
	await _settle()
	v.menu_open(true)
	var keys := []
	for item in v.menu.items:
		keys.append(item.key)
	_check("the quick menu has a CAMERA line, on COCKPIT: %s" % [keys], keys.has("camera") and v.menu.items[keys.find("camera")].value == "COCKPIT")
	var seat_eye: Vector3 = v.cam.global_position
	var seat_origin: Transform3D = v.origin.transform
	_check("in the seat the origin is the eye point (%.0f mm over the point the cockpit is laid out round)" % (Cockpit.SEAT_RISE * 1000.0),
		seat_origin.is_equal_approx(Transform3D(Basis.IDENTITY, Cockpit.EYE)) and Cockpit.SEAT_RISE > 0.0 and Cockpit.EYE.y > Cockpit.SEAT.y)
	var mirror_eye: Vector3 = preload("res://view/screen_reflection.gd").EYE + Vector3(0.0, preload("res://view/craft_model.gd").POD_FRAME_UP, 0.0)
	_check("the windscreen's reflection is taken for that same eye (%.3f m up; the cockpit's %.3f)" % [mirror_eye.y, Cockpit.EYE.y], mirror_eye.is_equal_approx(Cockpit.EYE))
	await _shot("c1-cockpit.png")
	v.menu.at = keys.find("camera")
	var names := []
	var report := []
	var outside := true
	var level := true
	var panel := true
	var readout := true
	for expect in ["chase", "far"]:
		_check("choosing CAMERA keeps the menu open", v.menu_choose() and v.menu.open)
		names.append(v.menu.items[v.menu.at].value)
		outside = outside and Cockpit.camera == expect
		# lean the cockpit hard: the view outside must not lean with it
		v.craft.bank[2] = 0.5
		v._comfort_roll = deg_to_rad(25.0)
		v._comfort_roll_rate = 0.0
		v._place_camera(1.0)
		var yaw: float = sim.pod.th - PI / 2.0
		var want: Vector3 = seat_eye + Basis(Vector3.UP, yaw) * Cockpit.CAMERA_OFFSETS[expect]
		var eye: Vector3 = v.cam.global_position
		report.append("%s %.2f m off, up %.3f, rig rolled %.0f deg" % [expect, eye.distance_to(want), v.origin.global_basis.y.y, rad_to_deg(v.rig.rotation.z)])
		outside = outside and eye.distance_to(want) < 0.35      # (the seat eye itself swings a little as the rig rolls about the head)
		level = level and v.origin.global_basis.y.dot(Vector3.UP) > 0.9999 and absf(v.rig.rotation.z) > 0.2
		var ahead: Vector3 = v.origin.global_transform * Vector3(0.0, 0.02, -1.1)
		panel = panel and v.menu_panel.visible and v.menu_panel.global_position.distance_to(ahead) < 0.01
		v._update_hud()
		readout = readout and v.chase_hud.visible and v.chase_hud.text.contains("MPH")
		v.craft.bank[2] = 0.0
		v._comfort_roll = 0.0
		v._place_camera(1.0)
		v.menu_open(false)
		await _settle()
		await _shot("c%d-%s.png" % [names.size() + 1, expect])
		v.menu_open(true)
		v.menu.at = keys.find("camera")
	_check("CAMERA steps to CHASE then FAR CHASE, behind and above the seat: %s" % [", ".join(report)], names == ["CHASE", "FAR CHASE"] and outside)
	_check("outside, the view stays level while the cockpit leans", level)
	_check("the menu stays a metre in front of the camera", panel)
	_check("outside, the speed is on a readout by the view: %s" % v.chase_hud.text.get_slice("
", 0), readout)
	v.menu_choose()
	v._place_camera(1.0)
	_check("and round to the seat again: the origin is the eye point, the readout gone", Cockpit.camera == "cockpit"
		and v.origin.transform.is_equal_approx(seat_origin) and not v.chase_hud.visible and v.menu.items[v.menu.at].value == "COCKPIT")
	var saved = JSON.parse_string(FileAccess.get_file_as_string(Cockpit.PREFS))
	_check("the choice is saved with the controls", saved is Dictionary and saved.get("camera", "") == "cockpit")
	v.menu_open(false)
	v.queue_free()
	await process_frame
	print("VR CAMERA %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)


func _settle() -> void:
	v._ride.clear()
	for i in 60:
		v._follow_origin()
		v._sync_craft(1.0 / 60.0)
		v._place_camera(1.0)
		v._sync_world()
		v._update_hud()
		for hand in v.hands.values():
			hand.get_child(0).visible = false
		await process_frame


func _shot(name: String) -> void:
	if shots.is_empty() or DisplayServer.get_name() == "headless":
		return
	DirAccess.make_dir_recursive_absolute(shots)
	await RenderingServer.frame_post_draw
	_check("saved " + name, root.get_texture().get_image().save_png(shots.path_join(name)) == OK)
