## Pin race settings for review and return even an empty or absent pilot profile exactly.
extends RefCounted

const Settings := preload("res://release/game_settings.gd")
var original := {}

func pin(cockpit_prefs: String) -> void:
	for path in [cockpit_prefs, Settings.PREFS]:
		original[path] = FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null
	Settings.set_choice("race_pace", "club")
	Settings.set_choice("race_laps", "3")

func restore() -> void:
	for path: String in original:
		if original[path] != null:
			var file := FileAccess.open(path, FileAccess.WRITE)
			file.store_buffer(original[path])
			file.close()
		elif FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
