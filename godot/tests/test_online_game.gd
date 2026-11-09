## Runs the visible lobby path, then drives real CraftViews in separate processes.
extends Node
var session
var started := 0
var seen := 0
var frames := 0
var first_x := INF
var last_x := INF
var first_remote_x := INF
var last_remote_x := INF
var respawned := false
var saw_respawn := false
var shot := ""
var shot_requested := false
var mode := "host"
var deadline := 0

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--join="): mode = "guest"
		if arg.begins_with("--capture="): shot = arg.trim_prefix("--capture=")
	call_deferred("start")

func start() -> void:
	session = get_tree().root.get_node("RaceSession")
	deadline = Time.get_ticks_msec() + 45000

func _process(_delta: float) -> void:
	if session == null: return
	if Time.get_ticks_msec() > deadline:
		push_error("Game client timed out: " + session.status)
		get_tree().quit(1)
		return
	var view = get_tree().current_scene
	if view == null or not "online_mode" in view or view.online == null: return
	frames += 1
	if started == 0:
		started = Time.get_ticks_msec()
		view.cruise = 0.0
		view.inp = {"thrL": view.cruise, "thrR": view.cruise, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": true}
		print("GAME READY ", mode)
	if first_x == INF: first_x = view.sim.pod.x
	last_x = view.sim.pod.x
	for id in view.online.remotes:
		var remote = view.online.remotes[id]
		if remote.visible:
			seen += 1
			var p: PackedFloat64Array = session.pose_for(id)
			if not p.is_empty():
				if first_remote_x == INF: first_remote_x = p[2]
				last_remote_x = p[2]
				if p[1] >= 1: saw_respawn = true
	var elapsed := Time.get_ticks_msec() - started
	if elapsed > 6000:
		view.cruise = 0.35 if mode == "host" else 0.30
		view.inp.thrL = view.cruise
		view.inp.thrR = view.cruise
	if mode == "guest" and elapsed > 8000 and not respawned:
		view._respawn()
		respawned = true
	if seen > 50 and elapsed > 3500 and not shot_requested and shot != "" and DisplayServer.get_name() != "headless":
		shot_requested = true
		capture.call_deferred()
	if elapsed > (16000 if mode == "host" else 11000):
		var ok: bool = seen > 40 and absf(last_x-first_x) > 5.0 and absf(last_remote_x-first_remote_x) > 5.0
		if mode == "host": ok = ok and saw_respawn and session.players.size() == 1 and view.online.remotes.is_empty()
		print("GAME %s %s rendered_remote_frames=%d local_movement=%.2f remote_movement=%.2f respawn_seen=%s" % [mode, "PASS" if ok else "FAIL", seen, last_x-first_x, last_remote_x-first_remote_x, saw_respawn])
		session.leave_game()
		get_tree().quit(0 if ok else 1)

func capture() -> void:
	await RenderingServer.frame_post_draw
	var err := get_tree().root.get_texture().get_image().save_png(shot)
	print("CAPTURE ", err, " ", shot)
