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
	Cockpit.camera = "cockpit"
	Cockpit._camera_loaded = true      # the saved choices stay out of this: with a chase camera left saved by
	Cockpit._nose_loaded = true        # another run, the readout was measured from outside the pod and failed
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
	var display = v.approach_display
	_check("projector is mounted on the windscreen", display.get_parent() == v.canopy and v.shell.is_ancestor_of(display))
	_check("cockpit warns below speed and names the lip minimum", display.panel.is_visible_in_tree() and (display.image == null or display.image.is_visible_in_tree()) and display.status.text == "TOO SLOW" and display.advice.text.contains("3,000 MPH AT LIP"))
	if display.image:
		# (with the roof) the readout is thrown onto the windscreen: it lies in the glass, wraps round
		# with it and lies back with it, and from the seat it is where it was and as wide.
		var eye: Vector3 = display.EYE
		var off := 0.0
		var inside := true
		var widths := PackedFloat32Array()
		for j in 5:
			for i in 9:
				var on: Vector2 = display.image_uv(i / 8.0, j / 4.0)
				var glass := ScreenReflection.screen(on.x, on.y)
				var at: Vector3 = display.image_point(i / 8.0, j / 4.0)
				off = maxf(off, at.distance_to(glass))
				inside = inside and at.distance_to(eye) < glass.distance_to(eye)
			var left: Vector3 = display.image_point(0.0, j / 4.0) - eye
			var right: Vector3 = display.image_point(1.0, j / 4.0) - eye
			widths.append(rad_to_deg(atan2(right.x, -right.z) - atan2(left.x, -left.z)))
		var middle: Vector3 = display.image_point(0.5, 0.5)
		var wraps: float = display.image_point(0.0, 0.5).z - middle.z
		var lies_back: float = display.image_point(0.5, 1.0).z - display.image_point(0.5, 0.0).z
		_check("the image lies in the windscreen (%.1f mm inside it), wraps %.0f mm round at its ends and lies back %.0f mm from foot to top" % [off * 1000.0, wraps * 1000.0, lies_back * 1000.0],
			inside and off < 0.006 and wraps > 0.02 and absf(wraps - (display.image_point(1.0, 0.5).z - middle.z)) < 0.001 and lies_back > 0.08)
		var to_middle := middle - eye
		var to_foot: Vector3 = display.image_point(0.5, 0.0) - eye
		var to_top: Vector3 = display.image_point(0.5, 1.0) - eye
		var foot := rad_to_deg(atan2(to_foot.y, -to_foot.z))
		var top := rad_to_deg(atan2(to_top.y, -to_top.z))
		_check("from the seat it stands from %.1f to %.1f degrees up, %.2f m away, and is as wide at its foot as at its top (%.1f, %.1f, %.1f degrees): its sides stand upright" % [foot, top, to_middle.length(), widths[0], widths[2], widths[4]],
			absf((foot + top) * 0.5 - 19.5) < 0.3 and absf(top - foot - 38.0 * 0.228 / 0.94) < 0.3 and absf(widths[0] - 38.0) < 0.4 and absf(widths[2] - 38.0) < 0.4 and absf(widths[4] - 38.0) < 0.4)
		# its lines bow with the glass: across the middle row, how far the ends stand above the middle from the seat
		var end: Vector3 = display.image_point(0.0, 0.5) - eye
		var bow := rad_to_deg(atan2(end.y, Vector2(end.x, end.z).length()) - atan2(to_middle.y, Vector2(to_middle.x, to_middle.z).length()))
		_check("its lines bow with the screen, gently: the ends %.2f degrees off the middle's height" % bow, absf(bow) > 0.05 and absf(bow) < 2.5)
	_check("the small dashboard does not duplicate the three-line approach", v.dashboard.labels.progress.text.is_empty())
	_check("next action leads the readout with distance and ETA", display.action.text == "JUMP LIP" and display.countdown.text.ends_with(" S"))
	# Test against the actual canopy mesh, not a guessed bounding box: a rail through the words
	# was visible in the first screenshot even though the label existed and contained correct text.
	var frame: MeshInstance3D = v.canopy.get_node("frame")
	var frame_top := INF
	for point in frame.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		frame_top = minf(frame_top, v.cam.unproject_position(frame.to_global(point)).y)
	_check_type(display)
	# (where the pilot sees it: on the curved screen its edges are not straight, so all along them)
	var lower_left := Vector2(INF, -INF)
	var upper_right := Vector2(-INF, INF)
	for i in 9:
		for edge: Vector3 in [display.seen_at(i / 8.0, 0.0), display.seen_at(i / 8.0, 1.0)]:
			var px: Vector2 = v.cam.unproject_position(edge)
			lower_left = Vector2(minf(lower_left.x, px.x), maxf(lower_left.y, px.y))
			upper_right = Vector2(maxf(upper_right.x, px.x), minf(upper_right.y, px.y))
	var viewport_size: Vector2 = v.cam.get_viewport().get_visible_rect().size
	_check("complete readout clears canopy rail and stays inside seated view: panel %s to %s, rail %.1f, viewport %s" % [lower_left, upper_right, frame_top, viewport_size], lower_left.y + 4.0 < frame_top and upper_right.y > 0.0 and lower_left.x > 0.0 and upper_right.x < viewport_size.x)
	await _shot("ascent-cockpit.png")
	v.skill_score._award("turn", "HIGH-SPEED PRECISION", 1225)
	v._update_hud()
	for label: Label3D in [v._skill_readout, v._skill_award]:
		var left: Vector2 = v.cam.unproject_position(label.to_global(label.get_aabb().position))
		_check("active %s clears approach readout" % label.name, left.x > upper_right.x)
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
	_check("twelve-thousand-mph guidance is visible before the exit with preparation time", display.panel.visible and display.route.text.contains("KEEP RIGHT"))
	_check_type(display)
	await _shot("ascent-early-guidance.png")
	# Closer to the entrance board for a legibility inspection at flight-eye height.
	at = mouth - highway_way * 84
	sim.respawn_on(parent, at, highway_way)
	for b in sim.bodies:
		b.vx = 4000.0 / 2.236936 * H.tx[at] * highway_way
		b.vy = 4000.0 / 2.236936 * H.ty[at] * highway_way
	await _settle()
	_check("highway approach names the right exit and readiness", display.action.text == "RIGHT EXIT" and display.status.text == "READY")
	await _shot("ascent-entry.png")
	display.panel.hide()
	await _shot("ascent-entry-sign.png")
	display.panel.show()
	# A corner interchange has ordinary exits and no jump; use the same display with a clear option.
	sim.respawn_on(0, 2400, 1)
	for b in sim.bodies:
		b.vx = 4000.0 / 2.236936
		b.vy = 0.0
	await _settle()
	_check("ordinary exit offers destination without a jump-speed requirement", display.advice.text.contains("OPTIONAL") and display.route.text.contains("N1 UPPER") and display.status.text.is_empty())
	_check_type(display)
	await _shot("ordinary-exit-guidance.png")
	sim.respawn(0)
	v._update_hud()
	_check("leaving the approach starts retraction", display.message.is_empty() and display.panel.visible)
	display._process(display.CLOSE_TIME)
	_check("guidance stows after leaving the approach", not display.panel.visible and not display.is_processing())
	# The projector's beam (with the roof): from the lens under the header to the image's top edge,
	# lit with the image and gone with it.
	if display.beam:
		var fan: PackedVector3Array = display.beam.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		# the image's top edge on the glass, from the projector: its middle, and a corner
		var top_middle: float = (display.image_point(0.5, 1.0) - display.position).length()
		var top_corner: float = (display.image_point(0.0, 1.0) - display.position).length()
		var nearest := INF
		var furthest := 0.0
		for point in fan:
			nearest = minf(nearest, point.length())
			furthest = maxf(furthest, point.length())
		_check("the beam runs from the housing (%.2f m) down the glass to the image's top edge (%.2f m, of %.2f at its middle and %.2f at its corners) and is dark while stowed" % [nearest, furthest, top_middle, top_corner],
			nearest < 0.03 and absf(furthest - maxf(top_middle, top_corner)) < 0.01 and not display.beam.visible)
	display.set_message("WRONG WAY\nASCENT J0 | TURN BACK\nJUMP LIP IS BEHIND")
	display._process(display.OPEN_TIME*0.5)
	_check("projection sweeps down from the header", is_equal_approx(display.deployment,0.5) and display.action.modulate.a > 0.95 and display.advice.modulate.a < 0.05)
	if display.beam:
		_check("the beam comes up with the image", display.beam.visible and float(display.beam_mat.get_shader_parameter("lit")) > 0.3)
	display.set_message("RIGHT EXIT  2 MI / 4.7 S\nTO N1 UPPER\nOPTIONAL / KEEP RIGHT")
	_check("live updates preserve animation position", is_equal_approx(display.deployment,0.5) and display.countdown.text.ends_with("4.7 S"))
	display.set_message("")
	display._process(display.CLOSE_TIME*0.2)
	var partial: float = display.deployment
	display.set_message("JUMP LIP  2 MI / 4.0 S\nASCENT J0 > N2 UPPER\nMIN 3,000 MPH AT LIP | READY")
	display._process(display.OPEN_TIME*0.15)
	_check("interrupted retraction opens smoothly on the new guidance", display.deployment > partial and display.deployment < 1.0 and display.status.text == "READY")
	v.queue_free()
	await process_frame
	print("NETWORK GUIDANCE %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)

func _check_type(display) -> void:
	var half: Vector2 = display.panel.mesh.size*0.5
	for label: Label3D in display.panel.get_children():
		if label.text.is_empty(): continue
		var box := label.get_aabb()
		var lo := label.position + box.position
		var hi := lo + box.size
		_check("projected %s fits glass" % label.name, lo.x > -half.x and hi.x < half.x and lo.y > -half.y and hi.y < half.y)
	_check("action and countdown have separate space", display.action.position.x+display.action.get_aabb().end.x < display.countdown.position.x+display.countdown.get_aabb().position.x)

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
