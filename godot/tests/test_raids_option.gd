## Raids: the Off/On option and the director's hookup (view/network_raids.gd; the stage 1 plan, task 1):
##   default   with no saved choice raids are off
##   saved     the menus' row saves "on" and a flight reads it
##   rows      release_config has the button; the desktop menu and the headset menu both build a "Raids" row
##   off       on the Network with raids off, nothing is built (no director, no node)
##   on        on the Network with raids on, the director exists and holds traffic
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
	var v = await _cockpit()
	_check("on the Network with raids off there is no director and no node (raids %s, nodes %d)" % [v.raids, v.find_children("network_raids", "", true, false).size()],
		v.raids == null and v.find_children("network_raids", "", true, false).is_empty() and v.traffic_net != null and v.traffic_net.raids == null)
	v.queue_free()
	await process_frame

	# on: the director
	Raids.enabled = true
	v = await _cockpit()
	_check("with raids on the director exists and holds traffic", v.raids != null and v.raids.traffic == v.traffic_net and v.traffic_net.raids == v.raids and v.raids.name == "network_raids")
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
	_restore_prefs()
	print("RAIDS OPTION %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)
