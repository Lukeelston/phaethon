## Render the production guide include and its real material uniforms, then read the result.
## Run with an actual renderer, not --headless. The test window is moved offscreen and never focused.
extends SceneTree
const Sim := preload("res://sim/craft_sim.gd")
const Guide := preload("res://view/speed_guide.gd")
const MPH := 2.2369362920544

func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("SPEED GUIDE SHADER requires a real renderer; run without --headless")
		quit(2)
		return
	root.position = Vector2i(-10000, -10000)
	root.size = Vector2i(64, 64)
	root.unfocusable = true
	_run.call_deferred()

func _run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(32, 32)
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var shader := Shader.new()
	shader.code = "shader_type canvas_item;\n#include \"res://view/guide.gdshaderinc\"\nuniform float target_speed = 0.0;\nvoid fragment() { COLOR = vec4(guide_stop(v_now, target_speed) / 8192.0, 0.0, 0.0, 1.0); }\n"
	var material := ShaderMaterial.new()
	material.shader = shader
	var rect := ColorRect.new()
	rect.size = Vector2(32, 32)
	rect.material = material
	viewport.add_child(rect)
	var fails := 0
	for c in [["speed", 2000.0, 1250.0], ["speed", 4000.0, 1250.0], ["speed", 6000.0, 1250.0], ["starfighter", 1200.0, 400.0],
		["speed", 4000.0, 1250.0, {"frontBrakeMaxG": 0.0}], ["speed", 4000.0, 1250.0, {"frontBrakeMaxG": 20.0}]]:
		var options := {"track": "range", "handling": c[0]}
		if c.size() > 3:
			options.merge(c[3], true)
		var sim = Sim.new(options)
		sim.pod.vx = c[1] / MPH
		var guide = Guide.new()
		guide.setup(sim)
		guide.apply(material)
		material.set_shader_parameter("target_speed", c[2] / MPH)
		await process_frame
		await RenderingServer.frame_post_draw
		var img := viewport.get_texture().get_image()
		var expected: float = guide.stop_distance(c[1] / MPH, c[2] / MPH, guide.brake_model(), guide.brake_model("starfighter"))
		var rendered := img.get_pixel(16, 16).r * 8192.0 if not img.is_empty() else -1.0
		# A red-channel unit represents 8192 / 255 = 32.13 m in this 8-bit render target.
		var ok: bool = absf(rendered - expected) < 33.0
		print("%s rendered %s %.0f->%.0f mph overrides=%s: GPU %.1f m, CPU %.1f m" % ["PASS" if ok else "FAIL", c[0], c[1], c[2], c[3] if c.size() > 3 else {}, rendered, expected])
		if not ok:
			fails += 1
	viewport.queue_free()
	await process_frame
	print("SPEED GUIDE SHADER ", "PASS" if fails == 0 else "FAIL")
	quit(0 if fails == 0 else 1)
