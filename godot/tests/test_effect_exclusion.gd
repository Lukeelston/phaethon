## GPU regression: exterior dust/vapor must not draw inside the real pod frame or near the
## current eye, even when the VR rig replaces the hidden exterior pod. Keep external cues.
## Mutations caught: absent mask, stale/flat-only frame, missing VR floor offset, missing eye mask,
## and disabling the whole effect. Runs the production effect materials on small witness faces.
## Run windowed with --xr-mode off -- --track=range --mute.
extends SceneTree

const Flat := preload("res://view/craft_view.gd")
const MPH := 2.236936
var fails := 0
var passed := 0
var v
var viewport: SubViewport
var camera: Camera3D
var witness: MeshInstance3D


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("EFFECT EXCLUSION requires a real renderer")
		quit(2)
		return
	root.position = Vector2i(-10000, -10000)
	root.size = Vector2i(64, 64)
	root.unfocusable = true
	_run.call_deferred()


func _run() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(64, 64)
	viewport.world_3d = World3D.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	Flat.track_override = "range"
	Flat.job_override = "none"
	v = Flat.new()
	viewport.add_child(v)
	v.set_process(false)
	v.visible = false
	v.cam.current = false
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	viewport.world_3d.environment = env
	camera = Camera3D.new()
	camera.near = 0.01
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 0.12
	viewport.add_child(camera)
	camera.current = true
	witness = MeshInstance3D.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for p in [Vector3(-0.1, -0.1, 0), Vector3(0.1, -0.1, 0), Vector3(0.1, 0.1, 0),
		Vector3(-0.1, -0.1, 0), Vector3(0.1, 0.1, 0), Vector3(-0.1, 0.1, 0)]:
		st.set_normal(Vector3.RIGHT)   # a glancing condensation face, visible without a mask
		st.set_uv(Vector2(0.5, 0.5))
		st.add_vertex(p)
	witness.mesh = st.commit()
	viewport.add_child(witness)
	var white := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	white.fill(Color.WHITE)
	var texture := ImageTexture.create_from_image(white)
	for mat in v.dust.plume_mats + [v.dust.arm_mat]:
		mat.set_shader_parameter("noise_tex", texture)
		mat.set_shader_parameter("density", 1.0)
		mat.set_shader_parameter("color", Vector3.ONE)
	v.cues.cone_mat.set_shader_parameter("strength", 1.0)
	var rig := Node3D.new()
	var shell := Node3D.new()
	shell.name = "shell"
	viewport.add_child(rig)
	rig.add_child(shell)
	for mph in [5000.0, 6000.0, 10000.0]:
		v.sim.pod.vx = mph / MPH
		for vr in [false, true]:
			v.craft.pod_frame = rig if vr else null
			# A translated/elevated render frame after an origin shift, yawed, pitched and banked.
			# In VR the unrelated exterior pod deliberately remains elsewhere.
			var b := Basis.from_euler(Vector3(0.4, -1.1, 1.2))
			var frame := Transform3D(b, Vector3(18.0 + mph / 100.0, 430.0, -27.0 + (40.0 if vr else 0.0)))
			v.craft.pod.transform = Transform3D(Basis.IDENTITY, Vector3(-75, 10, 85)) if vr else frame
			rig.transform = frame * Transform3D(Basis.IDENTITY, Vector3(0, -0.6, 0))
			shell.position = Vector3(0.008, -0.006, 0)
			if vr:
				frame = shell.global_transform * Transform3D(Basis.IDENTITY, Vector3(0, 0.6, 0))
			for effect in [["engine dust", v.dust.plume_mats[0]], ["shock dust", v.dust.arm_mat], ["vapor", v.cues.cone_mat]]:
				witness.material_override = effect[1]
				var prefix := "%s %.0f mph %s" % ["VR" if vr else "flat", mph, effect[0]]
				# Literal cabin witnesses: seat, footwell and upper side of the headroom.
				for local in [Vector3(0, 0.12, 0.6), Vector3(0.4, -0.3, -1.4), Vector3(0.65, 0.9, 0.4)]:
					var inside := await _pixel(frame * local, 4.0)
					_check("%s cabin %s rejects pixels (%.4f)" % [prefix, local, inside], inside < 0.005)
				var outside := await _pixel(frame * Vector3(3.0, 0.3, 0), 4.0)
				_check("%s exterior stays visible (%.4f)" % [prefix, outside], outside > 0.05)
				# The headset can move away from the nominal seat; its live camera still needs clearance.
				var leaned := await _pixel(frame * Vector3(3.0, 1.4, 0.6), 0.2)
				_check("%s off-centre eye rejects nearby pixels (%.4f)" % [prefix, leaned], leaned < 0.005)
	v.craft.pod_frame = null
	rig.queue_free()
	viewport.queue_free()
	await process_frame
	print("EFFECT EXCLUSION %s (%d passed, %d failed)" % ["PASS" if fails == 0 else "FAIL", passed, fails])
	quit(0 if fails == 0 else 1)


func _pixel(at: Vector3, distance: float) -> float:
	witness.position = at
	camera.position = at + Vector3(0, 0, distance)
	camera.look_at(at, Vector3.UP)
	# Effect _process updates after the owner's camera/rig placement. Waiting only one process
	# frame intentionally catches stale uniforms when the rig moves in this frame.
	await process_frame
	await RenderingServer.frame_post_draw
	var c := viewport.get_texture().get_image().get_pixel(32, 32)
	return maxf(c.r, maxf(c.g, c.b))


func _check(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if ok:
		passed += 1
	else:
		fails += 1
