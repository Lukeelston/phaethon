extends RefCounted

# Packaged PCVR opens the menu first. Direct cockpit launches skip that boot scene.
static var _last_display := ""


static func log_headset(xr: OpenXRInterface) -> void:
	var size := Vector2i.ZERO
	var hz := 0.0
	if xr != null and xr.is_initialized():
		size = Vector2i(xr.get_render_target_size())
		hz = xr.display_refresh_rate
	var line := headset_line(size, hz)
	if line != _last_display:
		print(line)
		_last_display = line


static func headset_line(size: Vector2i, hz: float) -> String:
	var target := "%dx%d" % [size.x, size.y] if size.x > 0 and size.y > 0 else "unavailable"
	var refresh := "%.2f Hz" % hz if hz > 0.0 else "unavailable"
	return "DIAG headset: render_target=%s refresh=%s" % [target, refresh]


static func log_memory() -> void:
	var ram := OS.get_memory_info()
	var used := int(ram.physical) - int(ram.free) if ram.physical >= 0 and ram.free >= 0 else -1
	# The engine's allocator counter is debug-only. System RAM is also available in exports.
	var engine := OS.get_static_memory_usage() if OS.is_debug_build() else -1
	var video := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED)
	print("DIAG memory: system_used=%s engine_static=%s video_used=%s" % [
		_mib(used), _mib(engine), _mib(video if video > 0 else -1)])


static func _mib(bytes: int) -> String:
	return "%.1f MiB" % (bytes / 1048576.0) if bytes >= 0 else "unavailable"
