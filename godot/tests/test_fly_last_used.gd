## The per-craft switch set-up store (release/game_settings.gd's craft_setup) and Garage.fly, the menus' Fly button:
## it starts at once in the craft last used, with that craft's saved switches and paint. Nothing saved is the Phaethon
## in its Factory paint; a hand-edited value is dropped; the engine state is never saved; a launch in one craft leaves
## another's set-up as it was.
## Run headless with --xr-mode off -s res://tests/test_fly_last_used.gd -- --mute
extends SceneTree

const UI := preload("res://release/release_config.gd")
const Pilot := preload("res://sim/pilot_craft.gd")
const Settings := preload("res://release/game_settings.gd")
const Livery := preload("res://view/livery.gd")
const View := preload("res://view/craft_view.gd")
const Garage := preload("res://release/garage_route.gd")
var checks := 0
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
	return ok


## A launch changes the scene on the next idle frame; let it settle (the flight is not under test) before the next.
func _settle() -> void:
	for tick in 5:
		await process_frame


func _run() -> void:
	var settings_before := Settings.prefs_path
	var vehicle_before: String = View.vehicle_override
	var track_before: String = View.track_override
	var job_before: String = View.job_override
	var spot_before: String = View.spot_override
	var entry_before: Dictionary = View.garage_on_entry
	var pad_before: bool = View.pad_start
	Settings.prefs_path = "user://test-fly-last-used-%d.cfg" % OS.get_process_id()
	if FileAccess.file_exists(Settings.prefs_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.prefs_path))

	check(Settings.selected_craft() == Pilot.STANDARD, "Nothing saved: the Phaethon is the craft")
	check(Settings.craft_setup(Pilot.STANDARD).is_empty(), "Nothing saved: no switch set-up")
	check(Livery.is_factory(Livery.saved_for(Pilot.STANDARD)) and Livery.built(Pilot.STANDARD) == "ember",
		"Nothing saved: the Phaethon is built in its Factory paint")

	Settings.set_craft_setup("kiln", {"handling": "starfighter", "slide": false, "startup": 1, "paint": "x"})
	check(Settings.craft_setup("kiln") == {"handling": "starfighter", "slide": false},
		"Only handling and slide are kept (the engine state and the rest are dropped): %s" % Settings.craft_setup("kiln"))
	Settings.set_craft_setup("kiln", {"slide": true})
	check(Settings.craft_setup("kiln") == {"handling": "starfighter", "slide": true}, "A later save merges over the saved set-up")
	check(Settings.craft_setup(Pilot.STANDARD).is_empty(), "One craft's set-up is not another's")

	var config := ConfigFile.new()
	config.load(Settings.prefs_path)
	config.set_value("garage", "kiln", {"handling": "banana", "slide": "yes"})
	config.save(Settings.prefs_path)
	check(Settings.craft_setup("kiln").is_empty(), "A hand-edited value is dropped")
	Settings.set_craft_setup("kiln", {"handling": "banana"})
	check(Settings.craft_setup("kiln").is_empty(), "An invalid handling saves nothing")
	config.load(Settings.prefs_path)
	check(config.get_value("garage", "kiln") == {"handling": "banana", "slide": "yes"}, "... and leaves the stored value alone")
	Settings.set_craft_setup("kiln", {"handling": "starfighter", "slide": true})

	Garage.launch_flight(self, "vesper", {"vesper": {"handling": "starfighter"}, "kiln": {"slide": false}})
	check(Settings.selected_craft() == "vesper", "A launch saves the selected craft")
	check(Settings.craft_setup("vesper") == {"handling": "starfighter"}, "A launch saves the launched craft's switches")
	check(Settings.craft_setup("kiln") == {"handling": "starfighter", "slide": true}, "A launch in the Vesper leaves the Kiln's set-up as it was")
	await _settle()

	Settings.set_selected_craft("kiln")
	Garage.fly(self, false, "range")
	check(View.vehicle_override == "kiln", "Fly flies the selected craft")
	check(View.garage_on_entry == {"handling": "starfighter", "slide": true}, "Fly carries the saved set-up onto the pad: %s" % View.garage_on_entry)
	check(View.track_override == UI.course_overrides("range")[0], "Fly starts at the chosen course")
	await _settle()

	Settings.set_selected_craft("talon")
	var coat := ""
	for entry: Array in Livery.choices_for("talon"):
		if not Livery.is_factory(entry[0]):
			coat = entry[0]
			break
	Settings.set_choice(Livery.key_for("talon"), coat)
	View.vehicle_override = ""
	Garage.fly(self, false, "range")
	check(View.vehicle_override == "talon" and not coat.is_empty() and Livery.built("talon") == coat,
		"Fly flies the Talon (it has no garage bay) in its saved paint (%s)" % coat)
	await _settle()

	View.vehicle_override = "marker"
	View.garage_on_entry = {"marker": true}
	var setup_before := Settings.craft_setup("kiln")
	Settings.set_selected_craft("kiln")
	Garage.fly(self, false, "no-such-course")
	check(View.vehicle_override == "marker" and View.garage_on_entry == {"marker": true} and Settings.selected_craft() == "kiln"
		and Settings.craft_setup("kiln") == setup_before, "An unknown course changes nothing")
	await _settle()

	View.vehicle_override = vehicle_before
	View.track_override = track_before
	View.job_override = job_before
	View.spot_override = spot_before
	View.garage_on_entry = entry_before
	View.pad_start = pad_before
	if FileAccess.file_exists(Settings.prefs_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.prefs_path))
	Settings.prefs_path = settings_before
	print("FLY LAST USED %s (%d checks, %d failures)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(int(failures > 0))
