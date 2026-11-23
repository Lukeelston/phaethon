@tool
extends EditorExportPlugin

func _get_name() -> String:
	return "FlightBenchmarkRecordings"

func _export_begin(_features: PackedStringArray, _debug: bool, _path: String, _flags: int) -> void:
	for track in ["eridanus", "network"]:
		var file := "%s_inputs.json" % track
		var bytes := FileAccess.get_file_as_bytes("res://tests/replay/" + file)
		if bytes.is_empty():
			get_export_platform().add_message(EditorExportPlatform.EXPORT_MESSAGE_ERROR, "Flight benchmark", "Missing recording: " + file)
		else:
			add_file("res://release/replays/" + file, bytes, false)
