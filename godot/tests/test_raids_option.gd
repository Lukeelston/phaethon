## Raids: the Off/On option and the director's hookup (view/network_raids.gd; the stage 1 plan, task 1):
##   default   with no saved choice raids are off
##   saved     the menus' row saves "on" and a flight reads it
##   rows      release_config has the button; the desktop menu and the headset menu both build a "Raids" row
##   off       on the Network with raids off, nothing is built (no director, no node); the Phaethon's fire control is
##             not made either (it is made at the first arming), but its sounds are read at the cockpit's build
##   on        on the Network with raids on, the director exists and holds traffic; the Phaethon's fire control is made
##             at load, dormant: flight frames do not step it (its guns stay stowed) until the GUN is first armed, and
##             then the same one steps (none is made then)
##   range     raids on the Range build nothing (raids are the Network's)
## Run headless. Prints RAIDS OPTION PASS.
extends SceneTree

const View := preload("res://view/craft_view.gd")
const Cockpit := preload("res://vr/vr_cockpit.gd")
const Raids := preload("res://view/network_raids.gd")
const Livery := preload("res://view/livery.gd")
const Outlook := preload("res://view/outlook.gd")
const Chase := preload("res://view/network_chase.gd")
const UI := preload("res://release/release_config.gd")
const Settings := preload("res://release/game_settings.gd")
const Gunnery := preload("res://view/gunnery.gd")
const Pilot := preload("res://sim/pilot_craft.gd")
var failures := 0
var _prefs_before := PackedByteArray()
var _had_prefs := false


func _initialize() -> void:
	View.track_override = "network"
	View.job_override = "none"
	View.spot_override = "E3@9000"
	View.best_dir = OS.get_user_data_dir().path_join("test_raids_option_")
	Outlook.pinned = true
	Outlook.time = "afternoon"
	Outlook.weather = "fair"
	Livery.pinned = true
	Livery.current = "ember"
	Chase.pinned = true
	Chase.enabled = false
	Chase.craft = "racer"
	_had_prefs = FileAccess.file_exists(Settings.prefs_path)
	if _had_prefs:
		_prefs_before = FileAccess.get_file_as_bytes(Settings.prefs_path)
	_run.call_deferred()


func _check(label: String, passed: bool) -> void:
	print(("PASS " if passed else "FAIL ") + label)
	failures += int(not passed)


func _restore_prefs() -> void:
	if _had_prefs:
		var f := FileAccess.open(Settings.prefs_path, FileAccess.WRITE)
		f.store_buffer(_prefs_before)
		f.close()
	elif FileAccess.file_exists(Settings.prefs_path):
		DirAccess.remove_absolute(Settings.prefs_path)


func _cockpit() -> Node:
	var v = Cockpit.new()
	root.add_child(v)
	await process_frame
	v.set_process(false)
	return v


func _find_row(node: Node, title: String) -> Button:
	for b in node.find_children("*", "Button", true, false):
		if (b as Button).text.begins_with(title):
			return b
	return null


func _run() -> void:
	# default and saved choice
	if FileAccess.file_exists(Settings.prefs_path):
		DirAccess.remove_absolute(Settings.prefs_path)
	Raids.pinned = false
	Raids.enabled = true
	Raids.load_saved()
	_check("with no saved choice raids are off (%s)" % Raids.enabled, not Raids.enabled)
	Settings.set_choice("raids", "on")
	Raids.load_saved()
	_check("a saved \"on\" is read by a flight (%s)" % Raids.enabled, Raids.enabled)
	Settings.set_choice("raids", "off")
	Raids.load_saved()
	_check("and a saved \"off\" turns it off again (%s)" % Raids.enabled, not Raids.enabled)

	# rows
	var row := UI.raids_button(18)
	root.add_child(row)
	var first := row.text
	row.pressed.emit()
	_check("release_config's Raids button steps Off then On (\"%s\" then \"%s\"; saved %s)" % [first, row.text, Settings.choice("raids", ["off", "on"])],
		first.begins_with("Raids") and first.ends_with("Off") and row.text.ends_with("On") and Settings.choice("raids", ["off", "on"]) == "on")
	row.queue_free()
	Settings.set_choice("raids", "off")
	change_scene_to_file("res://release/menu.tscn")
	await scene_changed
	await process_frame
	_check("the desktop menu has a Raids row", _find_row(current_scene, "Raids") != null)
	change_scene_to_file("res://release/vr_menu.tscn")
	await scene_changed
	await process_frame
	_check("the headset menu has a Raids row", _find_row(current_scene, "Raids") != null)
	current_scene.queue_free()
	await process_frame

	# off: nothing built
	Raids.pinned = true
	Raids.enabled = false
	Cockpit.vehicle_override = Pilot.STANDARD
	var wavs := 0
	for n in ["fire", "deploy", "stow", "impact", "burst"]:
		wavs += int(ResourceLoader.exists("res://audio/turret/%s.wav" % n))
	var cached_before: int = Gunnery._sound_cache.size()
	var v = await _cockpit()
	_check("on the Network with raids off there is no director and no node (raids %s, nodes %d)" % [v.raids, v.find_children("network_raids", "", true, false).size()],
		v.raids == null and v.find_children("network_raids", "", true, false).is_empty() and v.traffic_net != null and v.traffic_net.raids == null)
	for i in 3:
		v._process(1.0 / 120.0)
	var cached: int = Gunnery._sound_cache.size()
	_check("raids off, the Phaethon's fire control is not made (%s), its %d sounds read at the cockpit's build (%d cached, %d before it)" % [v.gunnery, wavs, cached, cached_before],
		v.gunnery == null and wavs > 0 and cached_before == 0 and cached == wavs)
	v.queue_free()
	await process_frame

	# on: the director
	Raids.enabled = true
	v = await _cockpit()
	_check("with raids on the director exists and holds traffic", v.raids != null and v.raids.traffic == v.traffic_net and v.traffic_net.raids == v.raids and v.raids.name == "network_raids")
	var made = v.gunnery
	var asleep: bool = made != null and bool(made.get("dormant"))
	for i in 6:
		v._process(1.0 / 120.0)
	var unstepped: bool = made != null and float(made.get("_now")) == 0.0 and v.craft.weapon.deploy_t() == 0.0
	v.gun_wanted = true
	for i in 6:
		v._process(1.0 / 120.0)
	var woke: bool = made != null and v.gunnery == made and not bool(made.get("dormant")) and float(made.get("_now")) > 0.0
	_check("raids on, the Phaethon's fire control is made at load (%s), dormant (%s), not stepped by 6 flight frames (%s); armed, the same one steps (%s)" % [made, asleep, unstepped, woke],
		made != null and asleep and unstepped and woke)
	v.gun_wanted = false
	v.raids.update(0.016)
	v._respawn()
	_check("it updates and a restart resets it without error (text \"%s\")" % v.raids.text(), v.raids.text() == "" and v.raids.result == "")
	v.queue_free()
	await process_frame

	# range: nothing
	View.track_override = "range"
	v = await _cockpit()
	_check("on the Range, raids on builds nothing (%s)" % v.raids, v.raids == null)
	v.queue_free()
	await process_frame

	Raids.pinned = false
	Cockpit.vehicle_override = ""
	_restore_prefs()
	print("RAIDS OPTION %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)
