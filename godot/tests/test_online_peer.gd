## Real ENet peer, driven by tools/test_online.py. No mocked transport.
extends SceneTree
var session
var role := ""
var address := "127.0.0.1"
var port := 27841
var end_ms := 0
var start_ms := 0
var frames_sent := 0
var received := 0
var first_x := INF
var last_x := INF
var tick := 0.0
var saw_peer := false

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--role="): role = arg.get_slice("=", 1)
		if arg.begins_with("--port="): port = int(arg.get_slice("=", 1))
		if arg.begins_with("--address="): address = arg.get_slice("=", 1)
	call_deferred("start")

func start() -> void:
	session = root.get_node("RaceSession")
	start_ms = Time.get_ticks_msec()
	end_ms = start_ms + (7000 if role == "host" else 4500)
	var err: int
	if role == "host":
		err = session.host_game("Host", "network", port)
	else:
		if role == "mismatch": session.fingerprint = "incompatible-test-build"
		err = session.join_game(address, "Guest", port)
	if err != OK:
		push_error("Session creation failed: %s" % session.status)
		quit(1)
	print("PEER READY ", role)

func _process(delta: float) -> bool:
	if session == null: return false
	var now := Time.get_ticks_msec()
	tick += delta
	if session.active and tick >= 0.05:
		tick = 0
		frames_sent += 1
		var p := PackedFloat64Array([float(frames_sent), 0])
		for i in 3:
			p.append_array(PackedFloat64Array([100000.125 + frames_sent * 2, 4, -50000.25, 0, 0, 0, 1]))
		p.append_array(PackedFloat64Array([0.7, 0.8, 0]))
		session.publish_pose(p)
		for id in session.buffers:
			var pose: PackedFloat64Array = session.pose_for(id)
			if not pose.is_empty():
				received += 1
				if first_x == INF: first_x = pose[2]
				last_x = pose[2]
		if session.players.size() == 2: saw_peer = true
	if role == "mismatch" and session.status.contains("Different game version"):
		print("MISMATCH PASS")
		quit(0)
	if now >= end_ms:
		var ok: bool = received > 20 and last_x > first_x + 20 and saw_peer
		if role == "host": ok = ok and session.players.size() == 1 and session.buffers.is_empty()
		print("PEER %s %s received=%d moved=%.3f players=%d" % [role, "PASS" if ok else "FAIL", received, last_x-first_x, session.players.size()])
		session.leave_game()
		quit(0 if ok else 1)
	return false
