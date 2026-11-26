## Sprint and jump on foot in the garage (Luke, 2026-11-26: "add sprint with left click, jump with A"), and where the
## game's sound goes before a flight (the same message: "put the audio back in the headset").
##   walk        the stick alone walks at WALK_SPEED
##   sprint      a stick click with the stick pushed sprints (SPRINT_SPEED), until the stick is let go
##   body        a click with the stick near its centre is still the bay's body control, and starts no sprint
##   jump        off the floor and back onto it; a second press in the air does nothing; seated, none
##   the button  away from any bay the board button jumps; at a bay it boards and does not jump
##   sound       the device picker (audio/audio_out.gd) and the cockpit's own names for it agree; with no headset
##               device (the Dummy driver) nothing is changed
## Its own settings file for the run. Prints GARAGE MOVES PASS.
## Run headless with --xr-mode off --audio-driver Dummy -s res://tests/test_garage_moves.gd -- --mute
extends SceneTree

const Pilot := preload("res://sim/pilot_craft.gd")
const Settings := preload("res://release/game_settings.gd")
const Route := preload("res://release/garage_route.gd")
const AudioOut := preload("res://audio/audio_out.gd")
const Cockpit := preload("res://vr/vr_cockpit.gd")
const GARAGE := "res://garage/garage.tscn"
var STEP := 1.0 / 60.0      # the engine's own physics step (set in _run): move_and_slide moves by that, whatever it is told
const FORWARD := Vector2(0, -1)
var checks := 0
var failures := 0
var _settings_before := ""
var _asked: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, label: String) -> bool:
	checks += 1
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		failures += 1
	return ok


func _run() -> void:
	STEP = 1.0 / Engine.physics_ticks_per_second
	_settings_before = Settings.prefs_path
	Settings.prefs_path = "user://test-garage-moves-%d.cfg" % OS.get_process_id()
	Settings.set_phaethon_body("phaethon")
	Route.enter(self, false, "network")
	var garage = await _garage()
	if check(garage != null, "the garage opens"):
		await _on_foot(garage)
		await _button(garage)
	_sound()
	if FileAccess.file_exists(Settings.prefs_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.prefs_path))
	Settings.prefs_path = _settings_before
	print("GARAGE MOVES %s (%d checks, %d failures)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(int(failures > 0))


func _garage() -> Node:
	var until := Time.get_ticks_msec() + 30000
	while current_scene == null or current_scene.scene_file_path != GARAGE or not current_scene.is_node_ready():
		if Time.get_ticks_msec() > until:
			return null
		await process_frame
	for tick in 3:
		await process_frame
	return current_scene


## Stand the walker at the hall's spawn (clear of every bay), settled on the floor.
func _stand(garage) -> void:
	var walker = garage.walker
	walker.set_seated(false, garage.environment.spawn_transform())
	for n in 20:
		await physics_frame
		walker.step_locomotion(Vector2.ZERO, STEP)


## Step `frames` with the stick held at `intent`; the fastest the walker went over the floor, and the highest it stood.
func _go(walker, intent: Vector2, frames: int) -> Vector2:
	var fastest := 0.0
	var highest := -INF
	for n in frames:
		await physics_frame
		walker.step_locomotion(intent, STEP)
		fastest = maxf(fastest, Vector2(walker.velocity.x, walker.velocity.z).length())
		highest = maxf(highest, walker.global_position.y)
	return Vector2(fastest, highest)


func _on_foot(garage) -> void:
	var walker = garage.walker
	var hall = garage.environment
	walker.set_physics_process(false)      # (its own frames would step it too, the stick at rest)
	walker.bay_control_requested.connect(func(control: String): _asked.append(control))
	await _stand(garage)
	check(hall.nearest_bay(walker.global_position) == "" and walker.is_on_floor(),
		"the spawn is on the floor and clear of every bay (nearest \"%s\")" % hall.nearest_bay(walker.global_position))

	var walked: Vector2 = await _go(walker, FORWARD, 54)
	check(absf(walked.x - walker.WALK_SPEED) < .05 and not walker.sprinting,
		"the stick alone: %.2f m/s (WALK_SPEED %.2f), not sprinting" % [walked.x, walker.WALK_SPEED])

	await _stand(garage)
	walker._stick_click(FORWARD)
	var ran: Vector2 = await _go(walker, FORWARD, 54)
	check(walker.sprinting and absf(ran.x - walker.SPRINT_SPEED) < .05 and _asked.is_empty(),
		"a click with the stick pushed: %.2f m/s (SPRINT_SPEED %.2f), sprinting %s, nothing asked of the bay %s" % [ran.x,
		walker.SPRINT_SPEED, walker.sprinting, _asked])
	await _go(walker, Vector2.ZERO, 1)
	var let_go: bool = walker.sprinting
	await _stand(garage)
	var after: Vector2 = await _go(walker, FORWARD, 54)
	check(not let_go and absf(after.x - walker.WALK_SPEED) < .05,
		"the stick let go ends it (sprinting %s); pushed again it walks, %.2f m/s" % [let_go, after.x])

	await _stand(garage)
	walker._stick_click(Vector2(0, -.2))
	check(_asked == ["body"] and not walker.sprinting, "a click with the stick near its centre: the body control %s, no sprint" % [_asked])
	walker._stick_click(Vector2(.3, -.3))
	check(_asked == ["body", "body"], "a click tilting the stick 0.42: the body control still %s" % [_asked])
	_asked.clear()

	await _stand(garage)
	var floor_y: float = walker.global_position.y
	var want: float = walker.JUMP_SPEED * walker.JUMP_SPEED / (2.0 * 9.8)
	walker.jump()
	var up: Vector2 = await _go(walker, Vector2.ZERO, 12)
	var in_air: bool = not walker.is_on_floor()
	walker.jump()      # (a second press in the air)
	var over: Vector2 = await _go(walker, Vector2.ZERO, 90)
	var peak := maxf(up.y, over.y) - floor_y
	check(in_air and absf(peak - want) < .05 and walker.is_on_floor() and absf(walker.global_position.y - floor_y) < .01,
		"a jump: off the floor (%s), %.2f m up (want %.2f; a second press in the air added nothing), down on it again (%s, %.3f m from where he stood)" % [
		in_air, peak, want, walker.is_on_floor(), walker.global_position.y - floor_y])

	await _stand(garage)
	walker.seated = true
	walker.jump()
	var sat: Vector2 = await _go(walker, Vector2.ZERO, 12)
	walker.seated = false
	await _go(walker, Vector2.ZERO, 12)
	check(sat.y - floor_y < .005 and walker.global_position.y - floor_y < .005,
		"seated, no jump (%.3f m), and none saved up for when he stands (%.3f m)" % [sat.y - floor_y, walker.global_position.y - floor_y])


func _button(garage) -> void:
	var walker = garage.walker
	var hall = garage.environment
	await _stand(garage)
	var floor_y: float = walker.global_position.y
	garage._board_button()
	var hop: Vector2 = await _go(walker, Vector2.ZERO, 40)
	check(hop.y - floor_y > .3 and not garage._climbing() and garage.seated_craft.is_empty(),
		"the board button away from any bay: a jump (%.2f m up), no climb (%s), nobody seated (\"%s\")" % [hop.y - floor_y,
		garage._climbing(), garage.seated_craft])
	await _go(walker, Vector2.ZERO, 60)

	walker.set_seated(false, hall.boarding_transform(Pilot.KILN))
	await _go(walker, Vector2.ZERO, 20)
	var gate_y: float = walker.global_position.y
	garage._board_button()
	var rose: float = 0.0
	var climbing := false
	for n in 240:
		await process_frame
		if not walker.scripted:
			rose = maxf(rose, walker.global_position.y - gate_y)
		if garage._climbing():
			climbing = true
			break
	check(climbing and rose < .02, "the board button at the Kiln's bay: a climb (%s), no jump first (%.3f m)" % [climbing, rose])
	if climbing:
		garage._board_button()      # (pressed again: the climb finishes at once)
		for n in 120:
			await process_frame
			if not garage.seated_craft.is_empty():
				break
		check(garage.seated_craft == hall.bay_craft(Pilot.KILN), "and it ends seated in the craft there (\"%s\")" % garage.seated_craft)
		garage.leave_seat()


func _sound() -> void:
	var devices := PackedStringArray(["Default", "Headphones (Oculus Virtual Audio Device)", "Headphones (Realtek USB Audio)"])
	var same := true
	for asked in ["", "headphones+realtek", "sennheiser"]:
		same = same and AudioOut.pick(devices, asked) == Cockpit.audio_out_pick(devices, asked)
	check(same and AudioOut.pick(devices, "") == devices[1] and AudioOut.matches(devices[2], "REALTEK+headphones"),
		"the device picker and the cockpit's names for it agree; nothing asked is the headset's (%s)" % AudioOut.pick(devices, ""))
	var before := AudioServer.output_device
	var chosen := AudioOut.route()
	check(chosen == "" and AudioServer.output_device == before,
		"with no headset device (%s): none chosen (\"%s\"), the output left as it was (%s)" % [AudioServer.get_output_device_list(), chosen,
		AudioServer.output_device])
