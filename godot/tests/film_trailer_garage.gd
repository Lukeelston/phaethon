## The trailer's garage scenes (tools/trailer/README.md): the pilot garage filmed from a free camera, the hall's own
## sound recorded with it. The garage runs itself on the engine's clock; this script moves a camera of its own, presses
## the garage's own controls (the board button, the paint control, the one-touch start) and counts frames.
## Run windowed, under the engine's movie writer, a frame a step:
##   --xr-mode off --resolution 1280x720 --fixed-fps 30 --write-movie DIR/f.png
##   -s res://tests/film_trailer_garage.gd -- --out=DIR [--only=hall,fleet,...] [--preview=N]
## --preview=N draws only every Nth frame and saves it as DIR/<shot>-NNNN.jpg (no movie writer needed): a contact sheet.
## Each shot prints SHOT <name> <first frame> <last frame> (the engine's process frames: the movie's own numbering).
## It runs under a scratch profile of its own (game_settings.gd prefs_path): the paints it sets are not the pilot's.
extends SceneTree

const Settings := preload("res://release/game_settings.gd")
const Livery := preload("res://view/livery.gd")
const Route := preload("res://release/garage_route.gd")
const Fleet := preload("res://sim/pilot_craft.gd")
const GARAGE := "res://garage/garage.tscn"
const FPS := 30.0
const PAINTS := {"vesper": "star_command", "kiln": "cobalt", "shrike": "crimson", "orrery": "factory", "basilisk": "factory", "phaethon": "factory"}

var out_dir := ""
var only: PackedStringArray = []
var preview := 0
var cam: Camera3D
var garage
var hall
var _shot := ""
var _shot_frame := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
		elif arg.begins_with("--only="):
			only = arg.trim_prefix("--only=").split(",")
		elif arg.begins_with("--preview="):
			preview = int(arg.trim_prefix("--preview="))
	if out_dir.is_empty() or DirAccess.make_dir_recursive_absolute(out_dir) != OK:
		push_error("Pass --out= and a writable directory.")
		quit(1)
		return
	root.msaa_3d = Viewport.MSAA_4X
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var prefs_before := Settings.prefs_path
	Settings.prefs_path = "user://film-trailer-garage-%d.cfg" % OS.get_process_id()
	Settings.set_phaethon_body("phaethon")
	for id: String in PAINTS:
		Settings.set_choice(Livery.key_for(id), PAINTS[id])
	Route.enter(self, false, "network")
	for i in 600:
		await process_frame
		if current_scene != null and current_scene.scene_file_path == GARAGE:
			break
	garage = current_scene
	var ok: bool = garage != null and garage.scene_file_path == GARAGE
	if ok:
		hall = garage.environment
		for i in 20:
			await process_frame
		_hide_prompts()
		garage.walker.set_process_unhandled_input(false)
		cam = Camera3D.new()
		cam.near = 0.05
		cam.far = 2000.0
		cam.fov = 50.0
		root.add_child(cam)
		cam.make_current()
		for name: String in ["scout", "hall", "fleet", "paint", "talon", "board", "start"]:
			if (only.is_empty() and name != "scout") or only.has(name):
				await call("_scene_" + name)
	if FileAccess.file_exists(Settings.prefs_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.prefs_path))
	Settings.prefs_path = prefs_before
	print("TRAILER GARAGE %s" % ("done" if ok else "FAILED: no garage"))
	quit(0 if ok else 1)


## The flat view's control prompt (a panel on a canvas layer) is the player's, not the film's.
func _hide_prompts() -> void:
	for node: Node in garage.find_children("*", "CanvasLayer", true, false):
		(node as CanvasLayer).hide()


# --- frames -------------------------------------------------------------------------------------------------------

func _frame() -> void:
	_hide_prompts()
	if preview > 0:
		_shot_frame += 1
		var draw := _shot_frame % preview == 0
		RenderingServer.render_loop_enabled = draw
		await process_frame
		if draw:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_jpg(out_dir.path_join("%s-%04d.jpg" % [_shot, _shot_frame]), 0.9)
	else:
		await process_frame


func _begin(name: String) -> void:
	_shot = name
	_shot_frame = 0
	cam.make_current()
	_hide_prompts()
	print("SHOT %s begin %d" % [name, Engine.get_process_frames()])


func _end() -> void:
	print("SHOT %s end %d" % [_shot, Engine.get_process_frames()])


## `seconds` of film, the camera put by `move` each frame: move(k, t), k from 0 to 1 over the shot, t in seconds.
func _take(seconds: float, move: Callable) -> void:
	var n := roundi(seconds * FPS)
	for f in n:
		move.call(float(f) / maxf(1.0, n - 1.0), f / FPS)
		await _frame()


func _wait(seconds: float) -> void:
	for f in roundi(seconds * FPS):
		await _frame()


func _aim(from: Vector3, at: Vector3, fov := 50.0, roll := 0.0) -> void:
	cam.global_transform = Transform3D(Basis.looking_at(at - from, Vector3.UP), from)
	if roll != 0.0:
		cam.rotate_object_local(Vector3.FORWARD, deg_to_rad(roll))
	cam.fov = fov


func _ease(k: float) -> float:
	return smoothstep(0.0, 1.0, k)


## A point in a bay's own frame (x to the craft's right, y up from its pod's centre line, z aft: the engines are ahead
## at about -16), in the world.
func _bay(id: String, p: Vector3) -> Vector3:
	return (hall.bay_node(id) as Node3D).global_transform * p


func _put_pilot(at: Transform3D) -> void:
	garage.walker.set_seated(false, at)


# --- scenes -------------------------------------------------------------------------------------------------------

## Stills from a ring of places round each bay, to choose the shots from (not in the film).
func _scene_scout() -> void:
	_put_pilot(hall.spawn_transform())
	var views := {
		"aisle": [Vector3(2.5, 0.3, 9.0), Vector3(0.0, 0.2, -6.0), 46.0],
		"rear34": [Vector3(6.5, 1.2, 5.5), Vector3(0.0, 0.0, -7.0), 50.0],
		"side": [Vector3(7.5, 0.6, -8.0), Vector3(0.0, 0.0, -8.0), 60.0],
		"front34": [Vector3(6.0, 0.9, -24.0), Vector3(0.0, 0.0, -8.0), 46.0],
		"nose": [Vector3(0.0, 0.2, -27.0), Vector3(0.0, 0.3, -8.0), 40.0],
		"high": [Vector3(4.0, 5.2, -22.0), Vector3(0.0, -0.5, -7.0), 50.0],
		"low": [Vector3(3.2, -0.9, -21.0), Vector3(0.0, 0.6, -10.0), 55.0],
		"cab": [Vector3(3.0, 0.9, 1.6), Vector3(0.0, 0.2, -1.0), 50.0],
	}
	for id: String in Fleet.GARAGE_BAYS:
		for view: String in views:
			var v: Array = views[view]
			_begin("scout-%s-%s" % [id, view])
			_aim(_bay(id, v[0]), _bay(id, v[1]), v[2])
			preview = 1
			await _frame()
	_begin("scout-entrance")
	var spawn: Transform3D = hall.spawn_transform()
	_aim(spawn.origin + Vector3(0, 1.7, 0), spawn.origin + Vector3(0, 1.5, -20.0), 62.0)
	await _frame()
	_begin("scout-top")
	_aim(Vector3(0.0, 7.0, 22.0), Vector3(0.0, 0.0, -6.0), 70.0)
	await _frame()


## The right-hand engine's centre in a bay's frame (parked_airframe.gd engine_centers), `side` -1 the left one.
func _engine(id: String, side := 1.0) -> Vector3:
	var best := Vector3(3.6 * side, 0.0, -20.0)
	for c: Vector3 in hall.bay_node(id).engine_centers:
		if signf(c.x) == side:
			best = c
	return best


## The hall from its entrance, the camera coming down off the roof beams into the aisle; the pilot at the first bay.
func _scene_hall() -> void:
	_put_pilot(hall.boarding_transform("phaethon"))
	_begin("hall")
	await _take(5.0, func(k: float, _t: float) -> void:
		_aim(Vector3(0.6, 4.0, 22.5).lerp(Vector3(0.0, 1.8, 12.0), _ease(k)), Vector3(0.0, 1.2, -4.0).lerp(Vector3(0.0, 1.1, -16.0), k), 58.0))
	_end()


## Each craft in its bay: a slow move past it.
func _scene_fleet() -> void:
	_put_pilot(hall.spawn_transform())
	for id: String in Fleet.GARAGE_BAYS:
		var gate_side := signf((hall.bay_node(id).global_transform.affine_inverse() * hall.boarding_transform(id).origin).x)
		var s := -gate_side      # the side away from the bay's sign and gate
		var e := _engine(id, s)
		_begin("fleet-%s-pod" % id)
		await _take(2.6, func(k: float, _t: float) -> void:
			_aim(_bay(id, Vector3(3.6 * s, 0.9, 3.4).lerp(Vector3(4.6 * s, 0.6, 0.4), k)), _bay(id, Vector3(0.0, 0.15, -1.0).lerp(Vector3(0.0, 0.2, -2.2), k)), 44.0))
		_end()
		_begin("fleet-%s-engine" % id)
		await _take(2.6, func(k: float, _t: float) -> void:
			_aim(_bay(id, e + Vector3(4.4 * s, 0.7, -7.5).lerp(Vector3(5.6 * s, 1.0, -4.0), k)), _bay(id, e + Vector3(-1.2 * s, 0.0, -0.5)), 42.0))
		_end()


## The paint control worked at the Phaethon's bay (garage.gd _work_bay "paint": the bay's craft built again in each).
func _scene_paint() -> void:
	var id := "phaethon"
	_put_pilot(hall.boarding_transform(id))
	_begin("paint")
	var order := ["cobalt", "crimson", "viridian", "sunflower", "violet", "obsidian", "bone", "factory"]
	var n := 0
	for f in roundi(5.4 * FPS):
		var k := f / (5.4 * FPS)
		_aim(_bay(id, Vector3(4.4, 1.0, 3.0).lerp(Vector3(5.2, 1.3, 1.2), k)), _bay(id, Vector3(0.0, 0.1, -3.0)), 46.0)
		if f == roundi((0.7 + 0.6 * n) * FPS) and n < order.size():
			Settings.set_choice(Livery.key_for(id), order[n])
			garage._rebuild_bay(id, id)
			garage._name_bay(id)
			n += 1
		await _frame()
	_end()


## The other body stood at the Phaethon's bay (garage.gd _work_bay "body"): the Talon, and back.
func _scene_talon() -> void:
	var id := "phaethon"
	_put_pilot(hall.boarding_transform(id))
	_begin("talon")
	for f in roundi(5.0 * FPS):
		var k := f / (5.0 * FPS)
		_aim(_bay(id, Vector3(6.4, 1.6, 6.5).lerp(Vector3(5.0, 1.2, 3.0), k)), _bay(id, Vector3(0.0, 0.0, -7.0)), 50.0)
		if f == roundi(1.0 * FPS):
			garage._work_bay("body")
		await _frame()
	_end()
	garage._work_bay("body")
	await _wait(0.2)


## The climb into the Phaethon, played by the garage (garage/boarding.gd), from outside on the gate's side.
func _scene_board() -> void:
	var id := "phaethon"
	var gate: Transform3D = hall.boarding_transform(id)
	var side := signf((hall.bay_node(id).global_transform.affine_inverse() * gate.origin).x)
	_put_pilot(Transform3D(gate.basis, gate.origin + gate.basis.z * 0.9))
	await _wait(0.3)
	_begin("board")
	_aim(_bay(id, Vector3(4.3 * side, 1.0, 3.8)), _bay(id, Vector3(0.8 * side, 0.2, 0.5)), 50.0)
	await _wait(0.8)
	garage._board_button()
	var f := 0
	while f < roundi(14.0 * FPS):
		var k := f / (10.0 * FPS)
		_aim(_bay(id, Vector3(4.3 * side, 1.0, 3.8).lerp(Vector3(3.4 * side, 0.9, 2.6), clampf(k, 0.0, 1.0))), _bay(id, Vector3(0.8 * side, 0.2, 0.5)), 50.0)
		cam.make_current()
		await _frame()
		f += 1
		if garage.seated_craft == id and garage._climb == null:
			break
	await _wait(0.6)
	_end()
	print("TRAILER GARAGE board took %.1f s, seated in '%s'" % [f / FPS, garage.seated_craft])


## Seated in the Phaethon: the one-touch start, the bay door going up ahead, the engines lit.
func _scene_start() -> void:
	var id := "phaethon"
	if garage.seated_craft != id:
		_put_pilot(hall.boarding_transform(id))
		await _wait(0.2)
		garage.interact()
		for i in 300:
			await process_frame
			if garage.seated_craft == id:
				break
	var eye: Camera3D = garage.walker.camera
	var e := _engine(id, 1.0)
	var door: Transform3D = hall.door_transform(id)
	_shot = "start-seat"
	_shot_frame = 0
	eye.make_current()
	eye.rotation = Vector3(deg_to_rad(-6.0), 0.0, 0.0)
	_hide_prompts()
	print("SHOT start-seat begin %d" % Engine.get_process_frames())
	await _wait(1.6)
	garage.walker.cockpit_control_requested.emit("power")
	await _wait(5.4)
	_end()
	_begin("start-rear")
	await _take(5.0, func(k: float, _t: float) -> void:
		_aim(_bay(id, Vector3(2.8, 2.5, 7.0).lerp(Vector3(1.2, 1.9, 4.6), k)), _bay(id, Vector3(0.0, 0.6, -24.0)), 46.0))
	_end()
	_begin("start-engine")
	await _take(3.0, func(k: float, _t: float) -> void:
		_aim(_bay(id, e + Vector3(3.6, 0.9, 6.5).lerp(Vector3(2.2, 0.5, 4.6), k)), _bay(id, e + Vector3(-0.6, 0.0, 0.0)), 44.0))
	_end()
	_begin("start-door")
	await _take(5.0, func(k: float, _t: float) -> void:
		_aim(door * Vector3(1.5, 1.3, -9.0).lerp(Vector3(0.4, 1.0, -4.5), k), _bay(id, Vector3(0.0, 0.2, -10.0)), 40.0))
	_end()
	_begin("start-over")
	await _take(3.0, func(k: float, _t: float) -> void:
		_aim(_bay(id, Vector3(0.0, 5.2, 9.0).lerp(Vector3(0.0, 3.6, 3.0), k)), _bay(id, Vector3(0.0, 0.2, -26.0)), 52.0))
	_end()
	print("TRAILER GARAGE start: door %s, %s" % [hall.doors.phase(id), garage._runups[id].status_text()])
