extends SceneTree
const Lobby := preload("res://online/lobby.gd")
var fails := 0

func check(ok: bool, text: String) -> void:
	if not ok:
		fails += 1
		push_error(text)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var session = root.get_node("RaceSession")
	var lobby := Lobby.new()
	root.add_child(lobby)
	check(lobby.actions.size() == 4, "Host/join/solo/cancel controls are present")
	check(session.join_game("", "Friend") == ERR_INVALID_PARAMETER, "Empty host address rejected")
	check(session.host_game("Host", "network", 5) == ERR_INVALID_PARAMETER, "Invalid port rejected")
	check(session.clean_name("  [Pilot]\n  ") == "Pilot", "Pilot names sanitized")
	# Normal desktop launches require relaunch for Vulkan OpenXR, never late init.
	lobby.vr.button_pressed = true
	lobby._launch()
	check(not session.active and session.status.contains("Play-VR.cmd"), "VR startup failure gives actionable relaunch instructions")
	# Timeout is a state transition and leaves the controls usable for retry.
	check(session.join_game("127.0.0.1", "Friend", 27999) == OK, "Connection begins")
	session.connect_started = Time.get_ticks_msec() - session.TIMEOUT_MS - 1
	session._process(0.1)
	check(not session.connecting and session.status.contains("timed out"), "Timeout clears pending connection")
	check(not lobby.actions[0].disabled and not lobby.actions[1].disabled, "Host and join enabled after failure")
	lobby.free()
	session.leave_game()
	print("ONLINE LOBBY %s" % ("PASS" if fails == 0 else "FAIL"))
	quit(0 if fails == 0 else 1)
