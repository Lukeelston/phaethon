## Cockpit-mounted guidance and entrance signs, with optional real rendered screenshots.
## Run without --headless to save evidence/ascent-cockpit.png and ascent-entry.png.
extends SceneTree

const View := preload("res://view/craft_view.gd")
const Cockpit := preload("res://vr/vr_cockpit.gd")
var v
var failures := 0

func _initialize() -> void:
	View.track_override = "network"
	View.job_override = "none"
	View.best_dir = OS.get_user_data_dir().path_join("test_network_guidance_")
	_run.call_deferred()

func _check(label: String, passed: bool) -> void:
	print(("PASS " if passed else "FAIL ") + label)
	failures += int(not passed)

func _run() -> void:
	v = Cockpit.new()
	root.add_child(v)
	await process_frame
	v.set_process(false)
	var sim = v.sim
	var launch := int(sim.jumps[0][0])
	var L = sim.roads[launch]
	sim.respawn_on(launch, L.N - 301, 1)
	for b in sim.bodies:
		b.vx = 2500.0 / 2.236936 * L.tx[L.N - 301]
		b.vy = 2500.0 / 2.236936 * L.ty[L.N - 301]
	await _settle()
	_check("ascent warning is mounted on the craft, not on the tracked eye", v._jump_guidance.get_parent() == v.rig and v._jump_guidance.get_parent() != v.cam)
	_check("cockpit warns below speed and names the lip minimum", v._jump_guidance.visible and v._jump_guidance.text.contains("TOO SLOW") and v._jump_guidance.text.contains("3,000 MPH AT LIP"))
	_check("the small dashboard does not duplicate the three-line approach", v.dashboard.labels.progress.text.is_empty())
	_check("cockpit warning uses a readable font and three short lines", v._jump_guidance.font_size >= 36 and v._jump_guidance.text.split("\n").size() == 3)
	_check("next action leads the readout with distance and ETA", v._jump_guidance.text.begins_with("JUMP LIP") and v._jump_guidance.text.split("\n")[0].contains(" S"))
	# Test against the actual canopy mesh, not a guessed bounding box: a rail through the words
	# was visible in the first screenshot even though the label existed and contained correct text.
	var frame: MeshInstance3D = v.canopy.get_node("frame")
	var frame_top := INF
	for point in frame.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		frame_top = minf(frame_top, v.cam.unproject_position(frame.to_global(point)).y)
	var panel = v._jump_guidance_backing
	_check("readout lettering %s fits its backing %s" % [v._jump_guidance.get_aabb().size, panel.mesh.size], v._jump_guidance.get_aabb().size.x <= panel.mesh.size.x - 0.04 and v._jump_guidance.get_aabb().size.y <= panel.mesh.size.y - 0.02)
	var half: Vector2 = panel.mesh.size * 0.5
	var lower_left: Vector2 = v.cam.unproject_position(panel.to_global(Vector3(-half.x, -half.y, 0.0)))
	var upper_right: Vector2 = v.cam.unproject_position(panel.to_global(Vector3(half.x, half.y, 0.0)))
	var viewport_size: Vector2 = v.cam.get_viewport().get_visible_rect().size
	_check("complete readout clears canopy rail and stays inside seated view: panel %s to %s, rail %.1f, viewport %s" % [lower_left, upper_right, frame_top, viewport_size], lower_left.y + 4.0 < frame_top and upper_right.y > 0.0 and lower_left.x > 0.0 and upper_right.x < viewport_size.x)
	await _shot("ascent-cockpit.png")
	# Resolve the actual highway entrance through the exit ramp, including reverse-built ramps.
	var J: Array = sim.junctions[L.jx[0]]
	var ramp := int(J[0])
	var R = sim.roads[ramp]
	var ramp_way := int(J[6])
	var ramp_end: int = 0 if ramp_way > 0 else R.N - 1
	var HJ: Array = []
	for ji in R.jx:
		var candidate: Array = sim.junctions[ji]
		if int(candidate[3]) == ramp and int(candidate[4]) <= ramp_end and ramp_end <= int(candidate[5]): HJ = candidate
	var parent := int(HJ[0])
	var H = sim.roads[parent]
	var highway_way := ramp_way * int(HJ[6])
	var mouth: int = v._net_guidance_parent_sample(HJ, ramp_end)
	var at: int = mouth - highway_way * 2000
	sim.respawn_on(parent, at, highway_way)
	for b in sim.bodies:
		b.vx = 12000.0 / 2.236936 * H.tx[at] * highway_way
		b.vy = 12000.0 / 2.236936 * H.ty[at] * highway_way
	await _settle()
	_check("twelve-thousand-mph guidance is visible before the exit with preparation time", v._jump_guidance.visible and v._jump_guidance.text.contains("KEEP RIGHT"))
	_check("highway lettering fits its backing", v._jump_guidance.get_aabb().size.x <= panel.mesh.size.x - 0.04)
	await _shot("ascent-early-guidance.png")
	# Closer to the entrance board for a legibility inspection at flight-eye height.
	at = mouth - highway_way * 84
	sim.respawn_on(parent, at, highway_way)
	for b in sim.bodies:
		b.vx = 4000.0 / 2.236936 * H.tx[at] * highway_way
		b.vy = 4000.0 / 2.236936 * H.ty[at] * highway_way
	await _settle()
	_check("highway approach names the right exit and readiness", v._jump_guidance.text.contains("RIGHT EXIT") and v._jump_guidance.text.contains("READY"))
	await _shot("ascent-entry.png")
	v._jump_guidance.hide()
	v._jump_guidance_backing.hide()
	await _shot("ascent-entry-sign.png")
	# A corner interchange has ordinary exits and no jump; use the same display with a clear option.
	sim.respawn_on(0, 2400, 1)
	for b in sim.bodies:
		b.vx = 4000.0 / 2.236936
		b.vy = 0.0
	await _settle()
	_check("ordinary exit offers destination without a jump-speed requirement", v._jump_guidance.text.contains("OPTIONAL") and v._jump_guidance.text.contains("N1 UPPER") and not v._jump_guidance.text.contains("MIN "))
	await _shot("ordinary-exit-guidance.png")
	sim.respawn(0)
	v._update_hud()
	_check("guidance hides after leaving the approach", not v._jump_guidance.visible)
	v.queue_free()
	await process_frame
	print("NETWORK GUIDANCE %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)

func _settle() -> void:
	v._ride.clear()
	for i in 100:
		v._follow_origin()
		v._sync_craft(1.0 / 60.0)
		v._place_camera(1.0)
		v._sync_world()
		v._update_hud()
		for hand in v.hands.values():
			hand.get_child(0).visible = false
		await process_frame

func _shot(name: String) -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var path := "res://../evidence/" + name
		_check("saved " + name, root.get_texture().get_image().save_png(path) == OK)
