## The patrol craft and chase mode (Luke: "we need a police variant of the vehicle and a chase mode";
## view/network_chase.gd, view/light_bar.gd):
##   off       by default there is no chase, the craft is a racer in its own paint
##   getaway   in a racer with chase on: after a while at speed on a highway a patrol comes up behind
##             (one of traffic's cars, in the racer's slot, drawn as a pod and engines in black and
##             white with a light bar); the dash says how far back; held on your tail it busts you,
##             and stays by you a few seconds before it goes; got clear of, you have escaped
##   pursuit   in the patrol craft: the craft is black and white with a light bar on each model of
##             its roof; a runner appears ahead and picks its own exits; while you are after it the
##             bar flashes and the cabin's rim light with it; held close it is caught, which scores;
##             afterwards the rim light is its own colour again
##   chosen    the menus' rows save the craft and the mode
## Run with --fixed-fps 120 (see _fly). Prints CHASE PASS.
extends SceneTree

const View := preload("res://view/craft_view.gd")
const Cockpit := preload("res://vr/vr_cockpit.gd")
const Chase := preload("res://view/network_chase.gd")
const Livery := preload("res://view/livery.gd")
const Outlook := preload("res://view/outlook.gd")
const CM := preload("res://view/craft_model.gd")
const UI := preload("res://release/release_config.gd")
const Settings := preload("res://release/game_settings.gd")
const STEP := 1.0 / 120.0
const MPH := 2.236936
var failures := 0


func _initialize() -> void:
	View.track_override = "network"
	View.job_override = "none"
	View.spot_override = "E3@9000"       # open highway, well clear of a crossing
	View.best_dir = OS.get_user_data_dir().path_join("test_chase_")
	Outlook.pinned = true
	Outlook.time = "afternoon"
	Outlook.weather = "fair"
	Livery.pinned = true
	Livery.current = "ember"
	Chase.pinned = true
	_run.call_deferred()


func _check(label: String, passed: bool) -> void:
	print(("PASS " if passed else "FAIL ") + label)
	failures += int(not passed)


## Fly on with the levers up (no burner: about 2,500 mph). Traffic, and the chase with it, run on the
## engine's own frame time, so this test is run at a fixed 120 frames a second and a frame is let
## pass for every step of the flight: the two clocks agree.
func _fly(v, seconds: float) -> void:
	for i in int(seconds / STEP):
		v.inp = {"thrL": 1.0, "thrR": 1.0, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": true, "burner": false}
		v._process(STEP)
		await process_frame


## Put the other craft `along` metres up the pilot's road from the pilot (negative: behind), in its lane.
func _put(v, along: float) -> void:
	var pc = v.traffic_net._pod_as_car()
	var c = v.chase.car
	if c == null:
		return
	c.road = pc.road
	c.dir = pc.dir
	c.f = pc.f + pc.dir * along / 24.0
	c.lat = pc.lat
	c.v = pc.v
	c.nsp_road = -1
	c.vcap_road = -1
	v.traffic_net._place(c)


func _cockpit():
	var v = Cockpit.new()
	root.add_child(v)
	await process_frame
	v.set_process(false)
	v.cruise = 0.0           # (the levers are this test's: with cruise below zero the cockpit reads its own controllers each frame)
	return v


func _run() -> void:
	var saved_craft := Settings.choice("craft", Chase.ids(Chase.CRAFTS))
	var saved_chase := Settings.choice("chase", Chase.ids(Chase.MODES))
	# off
	Chase.craft = "racer"
	Chase.enabled = false
	var v = await _cockpit()
	_check("by default there is no chase and the craft is a racer in its own paint (%s, %d light bars)" % [Livery.current, v.light_bars.size()],
		v.chase == null and Livery.current == "ember" and v.light_bars.is_empty() and v.traffic_net.chase == null and not v.pursuing())
	v.queue_free()
	await process_frame

	# getaway
	Chase.enabled = true
	v = await _cockpit()
	var chase = v.chase
	_check("chase on, in a racer: the getaway, waiting for a highway at speed (role %s, state \"%s\")" % [chase.role if chase else "?", chase.state if chase else "?"],
		chase != null and chase.role == "getaway" and chase.state == "" and not chase.visible and chase.bar != null and v.light_bars.is_empty())
	await _fly(v, 16.0)
	var T = v.traffic_net
	var mph: float = Vector2(v.sim.pod.vx, v.sim.pod.vy).length() * MPH
	var behind: float = T._gap_to_pod(chase.car) if chase.car else 0.0
	_check("at %.0f mph a patrol is on the road behind: one of traffic's cars in the racer's slot (%s), %.0f m back, drawn here (%s) with its bar lit or between flashes; the dash: \"%s\"" % [
			mph, T.racer == chase.car and T.race_state == "chase", behind, chase.visible, v._net_text()],
		chase.state == "on" and chase.car != null and T.cars.has(chase.car) and T.racer == chase.car and T.race_state == "chase" and chase.car.chase == "pursuer" and chase.car.craft
			and behind > 0.0 and behind < Chase.COME_BEHIND + 400.0 and chase.visible and v._net_text().begins_with("PATROL"))
	# it follows the pilot's turns (the racer's rule), and does not pick its own
	_check("it follows where the pilot turns, taking no exits of its own (turn chance %.1f)" % chase.car.turn_p, chase.car.turn_p == 0.0 and chase.car.kind == T.RACER)
	var rim_own: Color = v.interior.rim_mat.albedo_color
	_put(v, -40.0)
	var washed := {}
	for i in 150:
		v.inp = {"thrL": 1.0, "thrR": 1.0, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": true, "burner": false}
		v._process(STEP)
		await process_frame
		var wc: Color = v.interior.rim_mat.albedo_color
		washed["red" if wc.r > 0.8 and wc.b < 0.3 else ("blue" if wc.b > 0.8 and wc.r < 0.3 else "dark")] = true
		OS.delay_msec(8)      # (the flash runs on the clock)
	_check("close behind, its lamps wash over the cabin's rim light (%s, strength %.2f)" % [washed.keys(), v.patrol_wash()],
		washed.has("red") and washed.has("blue") and v.patrol_wash() > 0.9)
	await _fly(v, Chase.BUST_T + 1.0)
	var busted: String = chase.result if chase.result != "" else str(chase.tally)
	_check("held on your tail for %.0f s it busts you (tally %s), and stays by you (state \"%s\", still drawn %s)" % [Chase.BUST_T, chase.tally, chase.state, chase.visible],
		int(chase.tally.busted) == 1 and chase.state == "over" and chase.visible)
	await _fly(v, Chase.LINGER + 1.0)
	_check("then it goes: off the road (%s), the racer's slot free (%s), hidden (%s), the rim light its own colour (%s)" % [chase.car == null, T.racer == null and T.race_state == "", not chase.visible,
			v.interior.rim_mat.albedo_color.is_equal_approx(rim_own)],
		chase.car == null and T.racer == null and T.race_state == "" and not chase.visible and chase.state == "" and v.interior.rim_mat.albedo_color.is_equal_approx(rim_own))
	await _fly(v, Chase.NEXT_AFTER + 2.0)
	var again: bool = chase.state == "on" and chase.car != null
	if again:
		for k in int((Chase.LOSE_T + 1.0) / 0.5):
			if chase.car == null:
				break
			_put(v, -(Chase.LOSE_R + 1500.0))
			await _fly(v, 0.5)
	_check("another comes (%s); kept %.1f km clear for %.0f s, you have escaped it (tally %s)" % [again, (Chase.LOSE_R + 1500.0) / 1000.0, Chase.LOSE_T, chase.tally],
		again and int(chase.tally.escaped) == 1 and chase.car == null)
	v.queue_free()
	await process_frame

	# pursuit
	Chase.craft = "patrol"
	v = await _cockpit()
	chase = v.chase
	T = v.traffic_net
	var hull_is_patrols := false
	for part: MeshInstance3D in v.find_children("*", "MeshInstance3D", true, false):
		hull_is_patrols = hull_is_patrols or part.mesh == CM.pod_hull_in("police")
	var rim_before: Color = v.interior.rim_mat.albedo_color
	_check("in the patrol craft: black and white (%s, hull %s), a light bar on each model of its roof (%d), dark until a pursuit; the pursuit's role" % [Livery.current, hull_is_patrols, v.light_bars.size()],
		Livery.current == "police" and hull_is_patrols and v.light_bars.size() == 2 and chase.role == "pursuit" and chase.bar == null and not v.pursuing()
			and not (v.light_bars[0].lamps[0] as MeshInstance3D).visible)
	await _fly(v, 16.0)
	var ahead: float = -T._gap_to_pod(chase.car) if chase.car else 0.0
	_check("a runner is on the road ahead (%.0f m), picking its own exits (turn chance %.2f, \"%s\"); the dash: \"%s\"" % [ahead, chase.car.turn_p if chase.car else -1.0, chase.car.chase if chase.car else "", v._net_text()],
		chase.state == "on" and chase.car != null and chase.car.chase == "fugitive" and chase.car.turn_p > 0.3 and ahead > 0.0 and v._net_text().begins_with("PURSUIT") and v.pursuing())
	# the lights: over a second of frames each lamp shows, and the rim light takes its colour
	var seen := {}
	var rim_seen := {}
	for i in 150:
		v._process(STEP)
		await process_frame
		for bar in v.light_bars:
			seen[int((bar.lamps[0] as MeshInstance3D).visible) + 2 * int((bar.lamps[1] as MeshInstance3D).visible)] = true
		var rc: Color = v.interior.rim_mat.albedo_color
		rim_seen["red" if rc.r > 0.8 and rc.b < 0.3 else ("blue" if rc.b > 0.8 and rc.r < 0.3 else "dark")] = true
		OS.delay_msec(8)      # (the flash runs on the clock)
	_check("after it, the bar flashes red and blue in turn (lamp states seen %s) and the cabin's rim light with it (%s)" % [seen.keys(), rim_seen.keys()],
		seen.has(1) and seen.has(2) and seen.has(0) and not seen.has(3) and rim_seen.has("red") and rim_seen.has("blue"))
	var points_before: int = v.skill_score.total if v.skill_score else 0
	for k in int((Chase.CATCH_T + 1.0) / 0.25):
		if chase.state != "on":
			break
		_put(v, 45.0)
		await _fly(v, 0.25)
	var scored: int = (v.skill_score.total if v.skill_score else 0) - points_before
	await _fly(v, 0.2)
	var rim_after: Color = v.interior.rim_mat.albedo_color
	_check("held within %.0f m for %.0f s it is caught (tally %s), which scores (%d points); the lights go out and the rim light is its own colour again (%s)" % [Chase.CATCH_R, Chase.CATCH_T, chase.tally, scored, rim_after.is_equal_approx(rim_before)],
		int(chase.tally.caught) == 1 and scored >= 2500 and not v.pursuing() and rim_after.is_equal_approx(rim_before) and not (v.light_bars[0].lamps[0] as MeshInstance3D).visible
			and not (v.light_bars[0].lamps[1] as MeshInstance3D).visible)
	v.queue_free()
	await process_frame

	# chosen
	Settings.set_choice("craft", "racer")
	Settings.set_choice("chase", "off")
	var craft_row := UI.craft_button()
	var chase_row := UI.chase_button()
	root.add_child(craft_row)
	root.add_child(chase_row)
	var first := [craft_row.text, chase_row.text]
	craft_row.pressed.emit()
	chase_row.pressed.emit()
	Chase.pinned = false
	Chase.load_saved()
	_check("the menus' rows: %s then \"%s\", \"%s\"; and a flight reads them: %s, chase %s" % [first, craft_row.text, chase_row.text, Chase.craft, Chase.enabled],
		String(first[0]).ends_with("Racer") and String(first[1]).ends_with("Off") and craft_row.text.ends_with("Patrol") and chase_row.text.ends_with("On") and Chase.craft == "patrol" and Chase.enabled)
	craft_row.queue_free()
	chase_row.queue_free()
	Settings.set_choice("craft", saved_craft)
	Settings.set_choice("chase", saved_chase)
	print("CHASE %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)
