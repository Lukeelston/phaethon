## Standalone Flight Hold graphics controls. The inherited flight and its controls stay intact.
extends "res://vr/vr_cockpit.gd"

const SCALES := [1.0, 0.8, 0.7]
const SAMPLES := [Viewport.MSAA_4X, Viewport.MSAA_2X, Viewport.MSAA_DISABLED]
const MSAA_LABELS := ["4x", "2x", "off"]
const WINDOW_US := 5000000
const SETTLE_US := 1000000
static var foveate := false
static var scale_index := 0
static var sample_index := 0
var graphics_open := false
var actual: Dictionary
var _start_us := 0
var _after_us := 0
var _frame_count := 0
var _gpu_samples := 0
var _gpu_sum := 0.0
var _api := OpenXRAPIExtension.new()
var _probe: Object
var _full_eye := Vector2i.ZERO
var _next_probe_us := 0
var _generation := 0

func _ready() -> void:
	super()
	if OS.has_feature("android"):
		_probe = Engine.get_singleton("JavaClassWrapper").wrap("com.godot.game.QuestProjection")
	_apply_graphics()

static func eye_region(full: Vector2i, scale: float) -> Rect2i:
	var size := Vector2i((Vector2(full) * scale).round())
	return Rect2i(Vector2i((Vector2(full - size) * 0.5).floor()), size)

func _apply_graphics() -> void:
	var viewport := get_viewport()
	viewport.msaa_3d = SAMPLES[sample_index]
	var openxr := xr as OpenXRInterface
	var live := openxr != null and openxr.is_initialized()
	var supported := live and openxr.is_foveation_supported()
	_generation += 1
	_next_probe_us = 0
	if live:
		_full_eye = Vector2i(openxr.get_render_target_size())
		if _full_eye.x > 0 and _full_eye.y > 0:
			# OpenXR's projection subimage is the eye image sent to the compositor.
			# The allocation stays large enough to restore full resolution without restarting XR.
			_api.set_render_region(eye_region(_full_eye, SCALES[scale_index]) if scale_index else Rect2i())
	viewport.vrs_mode = Viewport.VRS_XR if supported and foveate else Viewport.VRS_DISABLED
	var level := 0
	if supported:
		openxr.foveation_dynamic = false
		openxr.foveation_level = 2 if foveate else 0
		level = openxr.foveation_level if viewport.vrs_mode == Viewport.VRS_XR else 0
	var msaa_index := SAMPLES.find(viewport.msaa_3d)
	actual = {
		"foveation": (["off", "low", "medium", "high"][clampi(level, 0, 3)] if supported else "unavailable"),
		"requested_scale": SCALES[scale_index], "scale": null,
		"eye_w": 0, "eye_h": 0, "allocation_w": _full_eye.x, "allocation_h": _full_eye.y,
		"msaa": MSAA_LABELS[msaa_index] if msaa_index >= 0 else "unknown"
	}
	_reset_window()
	print("QUEST_SETTINGS ", JSON.stringify(actual))

func _menu_items() -> Array:
	if graphics_open:
		return [
			{"key": "foveation", "label": "FOVEATION", "value": str(actual.get("foveation", "off")).to_upper()},
			{"key": "scale", "label": "EYE BUFFER", "value": "%.1f" % SCALES[scale_index]},
			{"key": "msaa", "label": "MSAA", "value": MSAA_LABELS[sample_index].to_upper()},
			{"key": "graphics_back", "label": "BACK"}
		]
	var entries := super()
	entries.push_front({"key": "graphics", "label": "QUEST GRAPHICS"})
	return entries

func menu_choose() -> bool:
	var choice: String = menu.key()
	match choice:
		"graphics", "graphics_back":
			graphics_open = choice == "graphics"
			menu.at = 0
		"foveation": foveate = not foveate
		"scale": scale_index = (scale_index + 1) % SCALES.size()
		"msaa": sample_index = (sample_index + 1) % SAMPLES.size()
		_: return super()
	if choice in ["foveation", "scale", "msaa"]:
		_apply_graphics()
	menu.items = _menu_items()
	_menu_show()
	return true

func menu_open(on: bool) -> void:
	if not on:
		graphics_open = false
	_reset_window()
	super(on)

func _reset_window() -> void:
	_start_us = 0
	_after_us = Time.get_ticks_usec() + SETTLE_US
	_frame_count = 0
	_gpu_samples = 0
	_gpu_sum = 0.0

func _process(delta: float) -> void:
	super(delta)
	var now := Time.get_ticks_usec()
	if _probe != null and get_viewport().use_xr and now >= _next_probe_us:
		_next_probe_us = now + 1000000
		RenderingServer.call_on_render_thread(_read_projection.bind(_generation))
	if menu.open or not hands_live or not get_viewport().use_xr or actual.get("scale") == null:
		_reset_window()
		return
	if now < _after_us:
		return
	if _start_us == 0:
		_start_us = now
		return
	var gpu_ms := RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())
	_sample_frame(now, gpu_ms)

func _read_projection(generation: int) -> void:
	# The native OpenXR layer and its view array belong to the rendering thread.
	var packed: int = _probe.readEyeSize(_api.get_projection_layer())
	_observe_eye.call_deferred(generation, Vector2i(packed >> 32, packed & 0xffffffff))

func _observe_eye(generation: int, size: Vector2i) -> void:
	if generation != _generation or _full_eye.x <= 0 or _full_eye.y <= 0:
		return
	if size == Vector2i(actual.eye_w, actual.eye_h):
		return
	actual.eye_w = size.x
	actual.eye_h = size.y
	actual.scale = null
	if size.x > 0 and size.y > 0:
		actual.scale = snappedf(float(size.x) / _full_eye.x, 0.001)
	_reset_window()
	print("QUEST_SETTINGS ", JSON.stringify(actual))

func _exit_tree() -> void:
	if xr != null and xr.is_initialized():
		_api.set_render_region(Rect2i())
	super()

func _sample_frame(now: int, gpu_ms: float) -> void:
	_frame_count += 1
	if is_finite(gpu_ms) and gpu_ms > 0:
		_gpu_sum += gpu_ms
		_gpu_samples += 1
	var elapsed := now - _start_us
	if elapsed < WINDOW_US:
		return
	var row := actual.duplicate()
	row.merge({"frames": _frame_count, "seconds": elapsed / 1000000.0,
		"fps": _frame_count * 1000000.0 / elapsed, "gpu_samples": _gpu_samples,
		"gpu_ms": _gpu_sum / _gpu_samples if _gpu_samples else null, "course": _track()})
	print("QUEST_PERF ", JSON.stringify(row))
	_start_us = now
	_frame_count = 0
	_gpu_samples = 0
	_gpu_sum = 0.0
