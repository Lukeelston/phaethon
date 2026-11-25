## The garage's paint control (Luke, 2026-11-25: "Will you fix her garage and talon paint then merge?"; the contract in
## docs/superpowers/specs/2026-11-25-garage-paint-talon-brief-codex.md): on foot at a bay, the walker's "power" button
## (I here, X on a pad, left X in the headset) takes the next paint on that craft's row.
##   a press   moves to the next choice (view/livery.gd choices_for), saves it under the craft's own key at once, and the
##             parked hull wears it, rebuilt in place (the same bay node: its stands, gate and the boards' connections
##             kept, the old airframe and its colliders gone); the prompt names the control and the paint
##   the cab   built after the press wears it; a warm cab in the old paint is thrown away, and the next one wears the new
##   the row   wraps at its end; the Vesper's includes Star Command, after Factory
##   run up    a bay whose engines are running refuses, and the prompt says why; shut down, it takes the press again
##   cold      a cold bay's switches moved in this visit survive the rebuild, and so does a start-up worked in it (PARK)
##   seated    the same button is still the battery (BATT, the assisted start)
##   prompt    the paint it names is the garage's own record, read when the bay is worked: a refresh reads no file
##   cost      the rebuild's main-thread time for each of the six bays' first press (printed: PAINT REBUILD)
##   headset   the headset's sign at a bay (garage_prompts.gd's placard) carries a third line, the paint control (a fourth
##             at the Phaethon's bay, the body), and every line of it fits the card, clear of the line above, as drawn,
##             with the longest paint name, with the body line and with the refusal; while a cab builds it is two lines
## Its own settings file for the run: the default one is left as it was.
## Run headless with --xr-mode off -s res://tests/test_garage_paint.gd -- --mute
extends SceneTree

const Pilot := preload("res://sim/pilot_craft.gd")
const Settings := preload("res://release/game_settings.gd")
const Livery := preload("res://view/livery.gd")
const Route := preload("res://release/garage_route.gd")
const Prompts := preload("res://garage/garage_prompts.gd")
const GARAGE := "res://garage/garage.tscn"
var checks := 0
var failures := 0
var _settings_before := ""
var _default_existed := false
var _default_settings := PackedByteArray()


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
	return ok


## Its own settings file for the run, as tests/test_fly_last_used.gd has; the default file is the player's.
func _own_settings(file_name: String) -> void:
	_settings_before = Settings.prefs_path
	_default_existed = FileAccess.file_exists(_settings_before)
	_default_settings = FileAccess.get_file_as_bytes(_settings_before) if _default_existed else PackedByteArray()
	Settings.prefs_path = "user://%s-%d.cfg" % [file_name, OS.get_process_id()]
	if FileAccess.file_exists(Settings.prefs_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.prefs_path))


func _settings_back() -> bool:
	if Settings.prefs_path != _settings_before and FileAccess.file_exists(Settings.prefs_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.prefs_path))
	Settings.prefs_path = _settings_before
	return FileAccess.file_exists(_settings_before) == _default_existed \
		and (not _default_existed or FileAccess.get_file_as_bytes(_settings_before) == _default_settings)


func _frames(count: int) -> void:
	for tick in count:
		await process_frame


func _key(code: Key) -> void:
	for down in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = down
		Input.parse_input_event(event)
		Input.flush_buffered_events()


## On foot at a bay's gate, the prompt caught up.
func _stand_at(garage, bay: String) -> void:
	garage.walker.set_seated(false, garage.environment.boarding_transform(bay))
	await _frames(2)


func _board(garage, bay: String) -> Node3D:
	await _stand_at(garage, bay)
	garage.interact()
	check(garage.walker.seated and garage.seated_craft == bay, "Board the parked " + bay)
	return garage.environment.bay_node(bay).get_node_or_null("OccupiedCockpit")


func _atlas(mesh: Mesh) -> ShaderMaterial:
	if mesh == null or mesh.get_surface_count() == 0:
		return null
	return mesh.surface_get_material(0) as ShaderMaterial


## Is a fleet craft's atlas material painted in a livery (as tests/test_garage_fleet_paint.gd asks it)?
func _wears(material: ShaderMaterial, livery: String) -> bool:
	if material == null:
		return false
	var repainted: bool = material.get_shader_parameter("repaint") == true
	if livery == Livery.STAR_COMMAND:
		var map := material.get_shader_parameter("albedo_map") as Texture2D
		return map != null and map.resource_path.ends_with("vesper_star_command.webp") and not repainted
	if Livery.is_factory(livery):
		var map := material.get_shader_parameter("albedo_map") as Texture2D
		return not repainted and map != null and not map.resource_path.ends_with("vesper_star_command.webp")
	var enamel = material.get_shader_parameter("to_r")
	return repainted and enamel is Color and (enamel as Color).is_equal_approx(Livery.coat("paint", livery))


func _saved_in_file(key: String) -> String:
	var config := ConfigFile.new()
	config.load(Settings.prefs_path)
	return str(config.get_value("flight", key, ""))


func _run() -> void:
	_own_settings("test-garage-paint")
	Route.enter(self, false, "range")
	var until := Time.get_ticks_msec() + 20000
	while (current_scene == null or current_scene.scene_file_path != GARAGE) and Time.get_ticks_msec() < until:
		await process_frame
	if check(current_scene != null and current_scene.scene_file_path == GARAGE, "The garage opens"):
		await _frames(3)
		await _cost(current_scene)
		await _paint(current_scene)
	await _placard()
	check(_settings_back(), "the default settings file is as it was (the run had its own)")
	print("GARAGE PAINT %s (%d checks, %d failures)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(int(failures > 0))


## The headset's sign on foot at a bay: its third line names the paint control (at the Phaethon's bay a fourth, the
## body), and each line fits the card, inside its face and clear of the line above it, with the longest name on any
## row, with the body line, and with the refusal in its place. Measured from the text as drawn (each Label3D's own
## mesh, so its vertical alignment counts), in the card's frame.
func _placard() -> void:
	var card = Prompts.new()
	root.add_child(card)
	card.setup(true)
	var longest := ""
	for entry: Array in Livery.CHOICES + Livery.OWN[Pilot.VESPER]:
		if str(entry[1]).length() > longest.length():
			longest = str(entry[1])
	var talon := str(Pilot.NAMES[Pilot.TALON])
	var cut := []
	for case: Array in [["", ""], ["", talon], ["Shut the engines down first", talon]]:
		card.show_controls(talon, false, "The Network", false, Transform3D.IDENTITY, longest, case[0], case[1])
		await process_frame
		var half: float = card._face.size.x * 0.5
		var top: float = card._backing.position.y + card._face.size.y * 0.5
		var bottom: float = card._backing.position.y - card._face.size.y * 0.5
		var above := top
		for line: Label3D in [card._vr_title, card._vr_hint, card._vr_bay]:
			var ink: AABB = line.transform * line.get_aabb()      # (the text as drawn, in the card's frame)
			var said := line.text.replace("\n", " / ")
			print("PLACARD \"%s\": x %.3f..%.3f, y %.3f..%.3f m; the card x %.3f..%.3f, y %.3f..%.3f" % [said,
				ink.position.x, ink.end.x, ink.position.y, ink.end.y, -half, half, bottom, top])
			if ink.size.x <= 0.0 or ink.position.x < -half + 0.01 or ink.end.x > half - 0.01 or ink.position.y < bottom + 0.005:
				cut.append("\"%s\" outside the card" % said)
			if ink.end.y > above:
				cut.append("\"%s\" over the line above it (%.3f > %.3f)" % [said, ink.end.y, above])
			above = ink.position.y
		if case[1] != "" and case[0] == "" and not card._vr_bay.text.contains("\nL STICK CLICK   BODY  " + talon.to_upper()):
			cut.append("no body line")
	check(card._vr_bay.visible and card._vr_bay.text.contains("SHUT THE ENGINES DOWN FIRST") and cut.is_empty(),
		"The headset's sign at a bay has the paint line, \"X   PAINT  %s\" (and the body line), and every line fits the card as drawn (cut: %s)" % [longest.to_upper(), cut])
	card.show_controls(talon, false, "The Network", false, Transform3D.IDENTITY, longest, "", talon)
	card.boarding(talon)
	check(not card._vr_bay.visible and card._backing.position.y == 0.0 and is_equal_approx(card._face.size.y, 0.19),
		"While a cab builds (an XR boarding) the sign is its two lines: the bay's controls are not offered")
	card.show_controls("", false, "The Network", false, Transform3D.IDENTITY)
	check(not card._vr_bay.visible and card._backing.position.y == 0.0, "Away from a bay the sign is as it was: two lines")
	card.free()


## Each bay's first press, timed on the main thread (the setting saved, the bay rebuilt, the prompt redrawn).
func _cost(garage) -> void:
	var worst := ["", 0.0]
	var said := []
	for bay: String in Pilot.GARAGE_BAYS:
		await _stand_at(garage, bay)
		var t0 := Time.get_ticks_usec()
		garage._work_bay("paint")
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		said.append("%s %.1f ms" % [bay, ms])
		if ms > float(worst[1]):
			worst = [bay, ms]
	print("PAINT REBUILD %s; heaviest %s %.1f ms" % [", ".join(said), worst[0], worst[1]])
	check(Livery.saved_for("phaethon") == "cobalt" and Livery.saved_for("vesper") == Livery.STAR_COMMAND and Livery.saved_for("kiln") == "ember",
		"Each bay's first press took its row's second paint (the Phaethon's Cobalt: its Factory is Ember; the Vesper's Star Command)")


func _paint(garage) -> void:
	var hall = garage.environment
	# ---- a press at the Kiln's bay
	await _stand_at(garage, "kiln")
	var bay: Node3D = hall.bay_node("kiln")
	var was: String = Livery.saved_for("kiln")
	var ids := Livery.ids_for("kiln")
	var want: String = ids[(ids.find(was) + 1) % ids.size()]
	var old_model: Node3D = bay.model
	var old_colliders: Array = bay._colliders.duplicate()
	var centers: Array = bay.engine_centers.duplicate()
	var wired: int = bay.engine_stage_changed.get_connections().size()
	_key(KEY_I)
	await _frames(1)
	check(Livery.saved_for("kiln") == want and _saved_in_file(Livery.key_for("kiln")) == want,
		"A press at the Kiln's bay takes the next paint (%s after %s), saved at once under its own key" % [Livery.saved_for("kiln"), was])
	check(hall.bay_node("kiln") == bay and bay.paint == Livery.built("kiln") and _wears(_atlas(bay.model.fleet.part(&"Cab")), want),
		"... and its parked hull wears it (%s), the same bay node rebuilt" % bay.paint)
	check(not is_instance_valid(old_model) and old_colliders.all(func(b): return not is_instance_valid(b))
		and bay._colliders.size() == old_colliders.size() and bay.engine_centers == centers
		and bay.engine_stage_changed.get_connections().size() == wired and bay.get_node_or_null("ParkedModel") == bay.model,
		"... the old airframe and its colliders gone, as many new, the engines where they stood, the boards still wired (%d)" % wired)
	var hint: String = garage._prompts._hint.text
	check(hint.begins_with("I  Paint: " + str(Livery.choices_for("kiln")[ids.find(want)][1])),
		"The prompt names the control and the paint: \"%s\"" % hint.get_slice("\n", 0))
	# ---- the cab built after the press wears it
	var cab := await _board(garage, "kiln")
	var hull := cab.get_node_or_null("ParkedShell/PodHull") as MeshInstance3D if cab else null
	check(hull != null and _wears(_atlas(hull.mesh), want), "Boarded after the press, the Kiln's cab wears %s" % want)
	# ---- seated, the same button is still the battery
	var runup: Node = bay.get_node_or_null("Runup")
	_key(KEY_I)
	await _frames(2)
	runup = bay.get_node_or_null("Runup")
	check(runup != null and runup.startup.batt and Livery.saved_for("kiln") == want, "Seated, I is still the battery (BATT on), and the paint stays")
	garage.leave_seat()
	await _frames(2)
	# ---- a run-up bay refuses
	_key(KEY_I)
	await _frames(1)
	check(Livery.saved_for("kiln") == want and hall.bay_node("kiln").model == bay.model and garage._prompts._status.visible
		and garage._prompts._status.text == garage.REFUSED_RUNNING,
		"With its battery on, the Kiln's bay refuses the paint and says why (\"%s\")" % garage._prompts._status.text)
	# ---- shut down, it takes the press again
	await _board(garage, "kiln")
	_key(KEY_I)      # (seated: the battery's shortcut, which shuts it down)
	await _frames(2)
	garage.leave_seat()
	await _frames(2)
	var shut: Node = bay.get_node_or_null("Runup")
	var was_cold: bool = shut != null and not shut.startup.batt and shut.startup.stage == ["off", "off"]
	_key(KEY_I)
	await _frames(1)
	check(was_cold and Livery.saved_for("kiln") != want and bay.paint == Livery.built("kiln") and not garage._prompts._status.visible,
		"Shut down with one seated I, the Kiln's bay that refused takes the next paint (%s)" % Livery.saved_for("kiln"))
	# ---- the row wraps
	await _stand_at(garage, "shrike")
	var start: String = Livery.saved_for("shrike")
	var row := Livery.ids_for("shrike")
	var seen := []
	for k in row.size():
		_key(KEY_I)
		await _frames(1)
		seen.append(Livery.saved_for("shrike"))
	var expected := []
	for k in row.size():
		expected.append(row[(row.find(start) + 1 + k) % row.size()])
	check(seen == expected and seen.back() == start, "At the Shrike's bay the row goes round in order and wraps to where it began (%s)" % [seen])
	check(not garage._prompts._status.visible, "The refusal is the Kiln's: at the Shrike's bay none is shown")
	# ---- the prompt's paint is the garage's record, read when the bay is worked: a refresh reads no file
	var shown: String = garage._prompts._hint.text.get_slice("\n", 0)
	Settings.set_choice(Livery.key_for("shrike"), row[(row.find(start) + 1) % row.size()])      # (written behind the garage's back)
	garage._update_prompt()
	var refreshed: String = garage._prompts._hint.text.get_slice("\n", 0)
	Settings.set_choice(Livery.key_for("shrike"), start)
	check(refreshed == shown and shown.begins_with("I  Paint: " + str(Livery.choices_for("shrike")[row.find(start)][1])),
		"A prompt refresh names the paint from the garage's own record, not the settings file (\"%s\")" % refreshed)
	# ---- the Vesper's row has Star Command, after Factory
	check(Livery.ids_for("vesper").slice(0, 2) == [Livery.FACTORY, Livery.STAR_COMMAND], "The Vesper's row: Factory, then Star Command")
	var vesper: Node3D = hall.bay_node("vesper")
	check(Livery.saved_for("vesper") == Livery.STAR_COMMAND and _wears(_atlas(vesper.model.fleet.part(&"Cab")), Livery.STAR_COMMAND),
		"The Vesper's first press put it in Star Command, and its hull wears the Star Command atlas")
	# ---- a cold bay's moved switches survive, and its worked start-up; its warm cab goes
	await _board(garage, "orrery")
	var orrery: Node3D = hall.bay_node("orrery")
	var worked: Node = orrery.get_node("Runup")
	worked.work("handling", 1)
	worked.work("slide", -1)
	worked.work("park", -1)      # (the brake released, BATT still off: a start-up the pilot worked)
	var sequence = worked.startup
	garage.leave_seat()
	await _frames(2)
	var warm := orrery.get_node_or_null("OccupiedCockpit") != null
	var before_paint: String = Livery.saved_for("orrery")
	_key(KEY_I)
	await _frames(1)
	var again: Node = orrery.get_node_or_null("Runup")
	check(Livery.saved_for("orrery") != before_paint and again != null and again.switch_settings == {"handling": "starfighter", "slide": false}
		and again.telemetry.handling == "starfighter" and not again.telemetry.slide and not again.startup.batt,
		"At the cold Orrery's bay the paint changes and the switches moved in this visit survive the rebuild (%s)" % [again.switch_settings if again else "no run-up"])
	check(again != null and not is_instance_valid(worked) and again.operated and again.startup == sequence
		and not again.startup.park and not again.startup.batt,
		"... and so does the start-up worked there (its PARK released), on the new run-up, for the launch to hand on")
	check(warm and orrery.get_node_or_null("OccupiedCockpit") == null and garage._cockpit == null,
		"The warm cab left in the old paint is thrown away with the old airframe")
	var cab_after := await _board(garage, "orrery")
	var hull_after := cab_after.get_node_or_null("ParkedShell/PodHull") as MeshInstance3D if cab_after else null
	check(hull_after != null and _wears(_atlas(hull_after.mesh), Livery.saved_for("orrery")) and garage.seated_craft == "orrery",
		"Boarded again, the Orrery's new cab wears the new paint (%s)" % Livery.saved_for("orrery"))
	garage.leave_seat()
	await _frames(1)
