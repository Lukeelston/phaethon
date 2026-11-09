extends SceneTree
const View := preload("res://view/craft_view.gd")
var fails := 0
var view

func check(ok: bool, message: String) -> void:
	if not ok:
		fails += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if not ResourceLoader.exists("res://online/online_view.gd"):
		check(false, "Online rendered integration is missing")
		quit(1)
		return
	var session = root.get_node("RaceSession")
	check(session.host_game("Test", "network", 27842) == OK, "Host created")
	View.track_override = "range" # the online world must win over an old solo track
	View.best_dir = "user://test_online_view_"
	view = View.new()
	root.add_child(view)
	view.set_process(false)
	check(view.sim.kind == "network", "Host world overrides old local track")
	check(view.sim.net.from == 0, "Online session starts in shared city")
	check(view.traffic_net == null and view.traffic == null, "No independent online traffic")
	view._sync_craft(0.016)
	var online = view.online
	var captured: PackedFloat64Array = online.capture_pose()
	var visual_script = load("res://online/remote_craft.gd")
	var remote = visual_script.new()
	root.add_child(remote)
	remote.build("Friend")
	var ox: float = view.org_x + 10000.125
	var oy: float = view.org_y - 1000.25
	remote.apply_pose(captured, ox, oy)
	check(remote.bodies[0].position.distance_to(Vector3(captured[2]-ox, captured[3], captured[4]+oy)) < 0.005, "Receiver subtracts its own floating origin")
	var synthetic: PackedFloat64Array = captured.duplicate()
	synthetic[2] = 900000.123456
	remote.apply_pose(synthetic, 900000.12, -synthetic[4])
	check(absf(remote.bodies[0].position.x - 0.003456) < 0.000001, "No Vector3 precision loss before origin subtraction")
	# Arbitrary rotated/upward pose is applied directly, without consulting observer's road.
	var q := Quaternion(Vector3.RIGHT, PI / 2)
	for j in 3:
		var base := 2 + j * 7
		synthetic[base+3] = q.x
		synthetic[base+4] = q.y
		synthetic[base+5] = q.z
		synthetic[base+6] = q.w
	remote.apply_pose(synthetic, 900000.12, -synthetic[4])
	check(remote.bodies[0].basis.is_equal_approx(Basis(q)), "Shaft orientation independent of observer road")
	var epoch_before: float = session.epoch
	view._respawn()
	check(session.epoch == epoch_before + 1, "Respawn marks a new pose generation")
	epoch_before = session.epoch
	view.sim.crash_t = view.DT / 2.0
	view._sim_step()
	check(session.epoch == epoch_before + 1, "Automatic crash recovery also marks a new generation")
	remote.free()
	view.free()
	session.leave_game()
	View.track_override = "range"
	view = View.new()
	root.add_child(view)
	view.set_process(false)
	check(not view.online_mode and view.sim.kind == "range", "Leaving restores solo track selection")
	check(view.traffic != null, "Solo traffic still exists")
	view.free()
	View.track_override = ""
	print("ONLINE VIEW %s" % ("PASS" if fails == 0 else "FAIL"))
	quit(0 if fails == 0 else 1)
