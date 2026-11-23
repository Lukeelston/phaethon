@tool
extends EditorPlugin

const STEPS := "res://addons/phaethon_export/steps"

var exporters: Array[EditorExportPlugin] = []

func _enter_tree() -> void:
	for filename in DirAccess.get_files_at(STEPS):
		if filename.get_extension() == "gd":
			var exporter: EditorExportPlugin = load(STEPS.path_join(filename)).new()
			exporters.append(exporter)
			add_export_plugin(exporter)

func _exit_tree() -> void:
	for exporter in exporters:
		remove_export_plugin(exporter)
	exporters.clear()
