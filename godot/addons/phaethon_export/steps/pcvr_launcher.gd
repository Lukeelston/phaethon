@tool
extends EditorExportPlugin

var executable := ""

func _get_name() -> String:
	return "PhaethonPcvrBoot"

func _export_begin(features: PackedStringArray, _debug: bool, path: String, _flags: int) -> void:
	executable = path if "pcvr" in features and path.get_extension().to_lower() == "exe" else ""

func _export_end() -> void:
	if executable.is_empty():
		return
	var target := ProjectSettings.globalize_path(executable)
	executable = ""
	if not target.is_absolute_path():
		target = ProjectSettings.globalize_path("res://").path_join(target).simplify_path()
	if not FileAccess.file_exists(target):
		return # The platform export itself failed.
	var launcher := target.get_basename() + ".launcher.tmp.exe"
	var worker := target.get_basename() + ".engine"
	var compiler := OS.get_environment("WINDIR").path_join("Microsoft.NET/Framework64/v4.0.30319/csc.exe")
	var source := ProjectSettings.globalize_path("res://").path_join("../tools/PcvrBoot.cs").simplify_path().replace("/", "\\")
	launcher = launcher.simplify_path().replace("/", "\\")
	var output: Array = []
	var result := OS.execute(compiler, ["/nologo", "/target:winexe", "/optimize+", "/reference:System.Windows.Forms.dll", "/out:" + launcher, source], output, true)
	if result != 0:
		_export_error("Compile failed (%d): %s" % [result, output])
		return
	if DirAccess.rename_absolute(target, worker) != OK:
		_export_error("Could not install engine at " + worker)
		return
	if DirAccess.rename_absolute(launcher, target) != OK:
		DirAccess.rename_absolute(worker, target)
		_export_error("Could not install watchdog at " + target)
		return
	var receipt := FileAccess.open(target + ".sha256", FileAccess.WRITE)
	if receipt == null:
		_export_error("Cannot record launcher digest for " + target)
		return
	receipt.store_line(FileAccess.get_sha256(target))

func _export_error(message: String) -> void:
	get_export_platform().add_message(EditorExportPlatform.EXPORT_MESSAGE_ERROR, "PCVR startup", message)
	push_error("PCVR startup: " + message)
