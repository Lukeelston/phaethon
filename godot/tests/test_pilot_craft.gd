## Menu selection, native handling, and the two assemblies that actually get flown.
extends SceneTree

const View := preload("res://view/craft_view.gd")
const Settings := preload("res://release/game_settings.gd")
const Sim := preload("res://sim/craft_sim.gd")
const DT := 1.0 / 480.0
const LEVERS := {"thrL": 0.82, "thrR": 0.82, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": true}
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func check(label: String, ok: bool) -> void:
	if not ok:
		failures += 1
	print(("PASS " if ok else "FAIL ") + label)


func trial(id: String) -> Vector2:
	var sim := Sim.new({"vehicle": id, "track": "range", "startY": -3000.0})
	var steps := 0
	while sqrt(sim.pod.vx**2 + sim.pod.vy**2) < 447.04 and steps < 4800:
		sim.step(LEVERS, DT)
		steps += 1
	sim.restart()
	for body in sim.bodies:
		body.vx = 350.0 * 0.44704
		body.vy = 0.0
	var split := LEVERS.duplicate()
	split.thrL = 0.30
	for i in 240:
		sim.step(split, DT)
	var yaw := rad_to_deg(sim.pod.th)
	check(id + " remains intact in the split-lever turn", sim.mode == "normal" and not sim.binder_broken)
	sim.set_handling("starfighter")
	sim.respawn()
	var idle := {"thrL":0.0, "thrR":0.0, "brkL":0.0, "brkR":0.0, "repair":false, "reignite":true}
	var gp_preset := Sim.new({"vehicle":id, "track":"gp"})
	check(id + " restores its GP yaw damping on respawn", is_equal_approx(sim.P.yawDamp, gp_preset.P.yawDamp))
	for mode in ["speed", "starfighter"]:
		idle.handling = mode
		for i in 500:
			sim.step(idle, DT)
		var expected: float = gp_preset.P.yawDamp if mode == "starfighter" else Sim.DEFAULTS.yawDamp
		check(id + " blends into its " + mode + " yaw damping", is_equal_approx(sim.P.yawDamp, expected))
	check(id + " survives a handling change and respawn", sim.P.vehicle == id and sim.P.engineMass == sim.eL.m)
	return Vector2(steps * DT, yaw)


func check_airframe(craft) -> void:
	# (Geometry pass, 2026-11-23: the baked bodywork's finish is view/fleet_finish.gdshader, which adds
	# the occlusion baked into the vertex colours and specular anti-aliasing to the same three maps.)
	var material: ShaderMaterial = craft.engines[0].get_node("ShrikeFairing").get_active_material(0)
	var atlas := load("res://art/shrike/enamel.tres") as StandardMaterial3D
	check("paint, surface finish and relief use the imported maps", material.shader == preload("res://view/fleet_finish.gdshader")
		and material.get_shader_parameter("albedo_map") == atlas.albedo_texture
		and material.get_shader_parameter("orm_map") == atlas.roughness_texture and atlas.roughness_texture == atlas.metallic_texture
		and material.get_shader_parameter("normal_map") == atlas.normal_texture and atlas.normal_texture != null)
	var colours = (craft.engines[0].get_node("ShrikeFairing").mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	var shaded := 0
	if colours != null:
		for c: Color in colours:
			shaded += int(c.a < 0.6)
	check("the engine carries baked occlusion in its vertex colours (%d vertices in shadow)" % shaded, colours != null and shaded > 50)
	for k in 2:
		var body: ArrayMesh = craft.engines[k].get_node("ShrikeFairing").mesh
		check("engine %d batches its fixed surfaces into one paint material" % k, body.get_surface_count() == 1 and body.surface_get_material(0) == material and not craft.engines[k].has_node("NacelleShell"))
		var fan_a: MeshInstance3D = craft.rotors[k][0].get_child(0)
		var fan_b: MeshInstance3D = craft.rotors[k][1].get_child(0)
		check("engine %d has a mirrored compressor pair on independent shafts" % k, fan_a.mesh == fan_b.mesh and fan_a.transform.basis.determinant() * fan_b.transform.basis.determinant() < 0)
		var brake: Mesh = craft.front_flaps[k][0].get_child(0).mesh
		var aft: Mesh = craft.flaps[k][0].get_child(0).mesh
		check("engine %d has separate textured front and aft leaves" % k, brake != aft and brake.surface_get_material(0) == material and aft.surface_get_material(0) == material)


func check_pod_controls(game, vr: bool) -> void:
	var model = game.craft
	var hull: MeshInstance3D = model.tail_lights.get_parent()
	check("brakes and lamps ride on the pilot's visible hull", hull.is_visible_in_tree() and model.pod_flaps.all(func(f): return f.get_parent() == hull))
	var previous_mesh: Mesh = hull.mesh
	var closed: bool = model.nose_closed
	model.set_nose_closed(not closed, game)
	check("nose switch preserves the Shrike hardware", hull.mesh != previous_mesh and bool(hull.mesh.get_meta(&"shrike_hull", false)) and hull.has_node("ShrikeStrakes"))
	model.set_nose_closed(closed, game)
	check("nose switch restores the previous hull", hull.mesh == previous_mesh)
	if vr:
		check("the pilot sits in the same bucket shown from chase", game.shell.get_node("seat_back").mesh == model.pod.get_node("seat_back").mesh)
	var previous: Dictionary = game.inp.duplicate()
	for demand: Vector2 in [Vector2(.85, .0), Vector2(.0, .85), Vector2(.85, .85), Vector2.ZERO]:
		game.inp.brkL = demand.x
		game.inp.brkR = demand.y
		game._sync_craft(1.0)
		var lights: Vector2 = model.tail_lights.material_override.get_shader_parameter("brakes")
		check("rear lamps follow each lever at " + str(demand), lights.is_equal_approx(demand))
		check("pod brake doors follow the common brake demand", is_equal_approx(model.pod_flap_open, minf(demand.x, demand.y)))
		if vr:
			game._place_camera(1.0)
			var angle := Vector2(game.brake_paddles[0].rotation.x, game.brake_paddles[1].rotation.x)
			check("brake paddles show the correct independent travel", angle.is_equal_approx(demand * deg_to_rad(-18.0)))
	game.inp = previous


func check_fleet(game, id: String, vr: bool) -> void:
	var model = game.craft
	var art = model.fleet
	check(id + " has the selected airframe", art != null and art.id == id)
	if not art:
		return
	var hull: MeshInstance3D = game.shell.get_node("PodHull") if vr else model.pod
	check(id + " shows its own cab, seat and roof", hull.is_visible_in_tree() and hull.mesh == art.part(&"Cab")
			and hull.get_node("FleetSeat").mesh == art.part(&"Seat")
			and (game.canopy if vr else model.canopy).get_node("roof").mesh == art.part(&"Roof"))
	var closed: bool = model.nose_closed
	model.set_nose_closed(not closed, game)
	check(id + " service bonnet follows the nose switch", hull.get_node("ServiceBonnet").visible != closed)
	model.set_nose_closed(closed, game)
	var previous: Dictionary = game.inp.duplicate()
	var started := float(game.sim.pod.x)
	game.inp = LEVERS.duplicate()
	for frame in 180:
		game.sim.step(game.inp, 1.0 / 120.0)
		game._sync_craft(1.0 / 120.0)
	game._place_camera(1.0)
	model.sync_cables(game.sim)
	check(id + " tows the cab under its own power", absf(game.sim.pod.x - started) > 1.0 and not game.sim.binder_broken)
	for k in 2:
		var engine: Node3D = model.engines[k]
		var fairing: MeshInstance3D = engine.get_node_or_null("FleetFairing")
		check(id + " carries the correct engine " + str(k), fairing != null and fairing.mesh == art.part(&"Port" if k == 0 else &"Starboard"))
		var bore := fairing.mesh.generate_triangle_mesh()
		var open := true
		for x in [-0.70, -0.35, 0.0, 0.35, 0.70]:
			var hit := bore.intersect_ray(Vector3(x, 0, 4.71), Vector3.FORWARD)
			open = open and (hit.is_empty() or hit.position.z <= model.Jets.PIPE_Z)
		check(id + " nozzle has an open exhaust path " + str(k), open and model.flames[k].visible)
		var ends: Array = model.cable_ends[k]
		check(id + " drawbar meets both hardpoints " + str(k), ends.size() == 2
				and ends[0].distance_to(engine.transform * model.ENGINE_EYE) < 0.002
				and ends[1].distance_to(model._pod_anchor(game.sim, k)) < 0.002 and model.link_span[k] > 2.0)
	game.inp.brkL = 0.84
	game.inp.brkR = 0.30
	game._sync_craft(1.0)
	var loads: Vector2 = model.tail_lights.material_override.get_shader_parameter("brakes")
	check(id + " left and right brakes work independently", loads.is_equal_approx(Vector2(0.84, 0.30)) and model.flap_open[0] > model.flap_open[1])
	check(id + " cab brake doors and lamps travel with the visible cab", model.tail_lights.get_parent() == hull and model.pod_flaps[0].get_parent() == hull)
	var hinge: Vector3 = model.pod_flaps[1].position
	var skin := hull.mesh.generate_triangle_mesh().intersect_ray(hinge + Vector3.RIGHT, Vector3.LEFT)
	check(id + " cab brake hinge sits on the outside of its armour", not skin.is_empty()
			and hinge.x > skin.position.x and hinge.x - skin.position.x < 0.012)
	game.inp = previous


## Measure the cast lip on the installed binnacle, relative to each LCD's glass.
func check_lcd_trays(cluster, id: String) -> void:
	var frame_mesh: Mesh = cluster.get_node("binnacle").mesh
	var surface := frame_mesh.generate_triangle_mesh()
	var seated := true
	for w in cluster.Layout.WINDOWS:
		var frame: Transform3D = cluster.Kit.on_arc(w[1], w[2], 0, cluster.R)
		var glass_z: float = w[5] + .0006
		for side in [-1.0, 1.0]:
			var ray := Vector3(side * (w[3] + .004), 0, glass_z + .015)
			var hit := surface.intersect_ray(frame * ray, -frame.basis.z)
			if hit.is_empty():
				seated = false
				continue
			var height: float = (frame.affine_inverse() * Vector3(hit.position)).z - glass_z
			seated = seated and height > .002 and height < .003
	check(id + " both LCDs sit inside their rolled metal edges", seated)


## The covers may be hollow. Trace under the middle of each skirt edge, where
## the lens seats, and check that its illuminated crown stands clear of the grip.
func check_grip_lenses(game, id: String) -> void:
	var fitted := true
	for lever: Node3D in game.lever_pivots:
		var grip: MeshInstance3D = lever.get_node("PilotGrip")
		var lens: MeshInstance3D = grip.get_node("GateIndicator")
		# Probe in lens-space millimetres so the ray epsilon cannot skip its seat.
		var faces := grip.mesh.get_faces()
		var into_lens := lens.transform.affine_inverse()
		for i in faces.size():
			faces[i] = (into_lens * faces[i]) * 1000
		var support := TriangleMesh.new()
		support.create_from_faces(faces)
		var bounds := lens.mesh.get_aabb()
		for offset in [Vector2(.475, 0), Vector2(-.475, 0), Vector2(0, .475), Vector2(0, -.475)]:
			var ray := bounds.get_center() + Vector3(offset.x * bounds.size.x, .045, offset.y * bounds.size.z)
			var hit := support.intersect_ray(ray * 1000, Vector3.DOWN)
			if hit.is_empty():
				fitted = false
				continue
			var contact_y: float = hit.position.y
			fitted = fitted and contact_y >= bounds.position.y * 1000 - .3 \
					and contact_y < bounds.end.y * 1000 - .5
	check(id + " both illuminated grip caps are seated and exposed", fitted)


func check_throttle_boots(game, id: String) -> void:
	var previous: Dictionary = game.inp.duplicate()
	var seated: bool = game.throttle_gaiters.size() == 2
	for demand in [Vector2(0, 1), Vector2(.5, .5), Vector2(1, 0)]:
		game.inp.thrL = demand.x
		game.inp.thrR = demand.y
		game._place_camera(1.0)
		for k in game.throttle_gaiters.size():
			var boot: Skeleton3D = game.throttle_gaiters[k]
			var fixed_joint := boot.find_bone("Gate")
			var shaft_joint := boot.find_bone("Shaft")
			seated = seated and fixed_joint >= 0 and shaft_joint >= 0
			if fixed_joint < 0 or shaft_joint < 0:
				continue
			var lever: Node3D = game.lever_pivots[k]
			var expected := Quaternion(Vector3.RIGHT, deg_to_rad(lerpf(30, -30, demand[k])))
			seated = seated and boot.position.is_equal_approx(lever.position) \
					and boot.get_bone_pose(fixed_joint).is_equal_approx(Transform3D.IDENTITY) \
					and boot.get_bone_pose_rotation(shaft_joint).is_equal_approx(expected)
			var cover := boot.get_node("Bellows") as MeshInstance3D
			seated = seated and cover.skin != null and cover.get_node(cover.skeleton) == boot
	game.inp = previous
	game._place_camera(1.0)
	check(id + " boot skirts stay on the gate and both necks follow independent lever travel", seated)


func check_flight_deck(game, id: String) -> void:
	var cluster = game.dashboard
	var meter = game.aux_meter
	if Sim.PilotCraft.phaethon_based(id):      # (the Talon sits in the Phaethon's own cockpit)
		check(id + " cockpit uses the original gauge body and layout", meter == null and cluster.flight_deck == null and game.throttle_gaiters.is_empty()
				and cluster.gauges == cluster.Layout.GAUGES and not game.interior.has_node("SillFittings")
				and cluster.get_node("binnacle").mesh == cluster.Interior._hd_mesh(cluster.BODY, "Binnacle"))
		return
	var layout := Sim.PilotCraft.deck_of(id)   # (the Basilisk builds the Kiln's deck)
	check(id + " has its own dial layout, side fittings and auxiliary instrument",
			cluster.flight_deck.id == layout and cluster.gauges != cluster.Layout.GAUGES
			and game.interior.has_node("SillFittings") and meter.id == layout)
	check_lcd_trays(cluster, layout)
	check_throttle_boots(game, layout)
	check_grip_lenses(game, layout)
	if layout != Sim.PilotCraft.ORRERY:
		var housing: MeshInstance3D = meter.get_node("Case")
		var surface := housing.mesh.generate_triangle_mesh()
		var supported := true
		for side in [-1, 1]:
			for end in [-1, 1]:
				var corner := Vector3(side * meter.card_size.x * .5, end * meter.card_size.y * .5, .01)
				var hit := surface.intersect_ray(housing.transform.affine_inverse() * corner, Vector3.DOWN)
				supported = supported and not hit.is_empty() and hit.normal.y > .99
		check(id + " supports all four corners of the meter card on its flat face", supported)
	var welt := game.interior.get_node_or_null("SegmentedCoaming/StitchedWelt") as MeshInstance3D
	var left := 0
	var right := 0
	if welt and welt.mesh.get_surface_count() == 2:
		var thread_vertices := welt.mesh.surface_get_arrays(1)[Mesh.ARRAY_VERTEX] as PackedVector3Array
		for point in thread_vertices:
			if point.x < -.28:
				left += 1
			if point.x > .28:
				right += 1
	check(id + " has raised thread along both padded cheeks", left > 100 and right > 100)
	# Probe the assembled screw, since a high backing plate can hide a perfectly good socket.
	var radial := .0022 if layout == Sim.PilotCraft.ORRERY else .003
	var screw_centre := Vector3(0,.073,.003) if layout == Sim.PilotCraft.ORRERY else Vector3(.086,.0543,-.0015)
	var hardware: MeshInstance3D = meter.get_node("RimHardware")
	# TriangleMesh's intersection tolerance can skip sub-millimetre facets at game scale.
	var millimetres := hardware.mesh.get_faces()
	for i in millimetres.size():
		millimetres[i] *= 1000
	var surface := TriangleMesh.new()
	surface.create_from_faces(millimetres)
	var origin := (screw_centre + Vector3.BACK * .01 + Vector3.UP * .00011) * 1000
	var bottom := surface.intersect_ray(origin,Vector3.FORWARD)
	var crown := surface.intersect_ray(origin + Vector3.RIGHT * radial * 1000 * .57,Vector3.FORWARD)
	check(id + " meter screws have a recessed drive below the crown", not bottom.is_empty() and not crown.is_empty()
			and crown.position.z - bottom.position.z > radial * 1000 * .25)
	var before: Array = []
	meter.sync(0, [0,1], [0,1], -20, 0)
	for cursor in meter.cursors:
		before.append(cursor.transform)
	check(id + " instrument lighting follows the battery", is_zero_approx(meter.card_material.emission_energy_multiplier))
	# Drive the opposite readings through the same HUD update used in flight.
	game._read_g()
	game.sim.pod.th = PI / 2
	game.inp.brkL = 1.0
	game.inp.brkR = 0.0
	game.craft.cable_strain.assign([1.0, 0.0])
	game.g_turn = 20.0
	game.startup.park = false
	game.startup.power = 1.0
	game._update_hud()
	for i in meter.cursors.size():
		check(id + " live indicator responds " + str(i), not meter.cursors[i].transform.is_equal_approx(before[i]))
	check(id + " restores its instrument lighting", meter.card_material.emission_energy_multiplier > .1)
	var previous_light: String = game.light_preset
	for preset in ["afternoon", "twilight"]:
		game.light_preset = preset
		game._update_hud()
		check("%s auxiliary illumination matches the main panel at %s" % [id, preset],
				is_equal_approx(meter.card_material.emission_energy_multiplier, cluster.lamps.backlight.a))
	game.light_preset = previous_light
	game._update_hud()
	check(id + " lights the printed graduations separately from the card stock",
			meter.card_material.emission_texture != null and meter.card_material.emission_texture != meter.card_material.albedo_texture)
	if layout == Sim.PilotCraft.KILN:
		meter.sync(0,[0,0],[1,1],0,1)
		check("load pointers can respond independently", meter.cursors[0].position.x > .05
				and meter.cursors[1].position.x > .05 and is_equal_approx(meter.cursors[1].position.x,before[1].origin.x))
	if layout == Sim.PilotCraft.ORRERY:
		check("compass reads north with the north-up map", is_zero_approx(meter.cursors[0].rotation.z))
	check_sight_lines(game)
	# A long status and a two-line checklist share the strip with the repair hint or step rail.
	for key in ["progress", "mach", "footer", "feat"]:
		var label: Label3D = cluster.labels[key]
		var saved := label.text
		for message in ["CHECK THE STARBOARD TURBINE AND RESET THE IGNITION BEFORE RESTARTING", "ENGINE START CHECKLIST\nSTARBOARD TURBINE READY", "READY"]:
			cluster._strip_text(label, message)
			var font := label.font if label.font else ThemeDB.fallback_font
			var bounds := font.get_multiline_string_size(message, HORIZONTAL_ALIGNMENT_CENTER, -1, label.font_size) * label.pixel_size
			check("%s %s fits its LCD row" % [id, key], bounds.x <= .3661 and bounds.y <= (.0311 if key == "progress" else .0251))
		check("%s %s restores full type size" % [id, key], is_equal_approx(label.pixel_size, cluster.PX))
		cluster._strip_text(label, saved)


func check_sight_lines(game) -> void:
	var cluster = game.dashboard
	var hull: MeshInstance3D = game.shell.get_node("PodHull")
	var obstacles := [hull, game.canopy.get_node("roof"), game.interior.get_node("SegmentedCoaming"),
			game.interior.get_node("Dashboard"), game.interior.get_node("SillFittings"), game.interior.get_node("SegmentedCoaming/StitchedWelt"), cluster.get_node("binnacle")]
	for name in ["FleetSeat","ServiceBonnet"]:
		if hull.has_node(name):
			obstacles.append(hull.get_node(name))
	obstacles.append_array(game.aux_meter.find_children("*","MeshInstance3D",true,false))
	var targets: Array[Vector3] = []
	var card_targets: Array[Vector3] = []
	var meter = game.aux_meter
	for x in [-.46, -.25, 0.0, .25, .46]:
		for y in [-.45, -.25, 0.0, .25, .45]:
			if meter.id == Sim.PilotCraft.ORRERY and Vector2(x,y).length() > .47:
				continue
			card_targets.append(meter.to_global(Vector3(x * meter.card_size.x, y * meter.card_size.y, .001)))
	for window in cluster.Layout.WINDOWS:
		var xf: Transform3D = cluster.Kit.on_arc(window[1],window[2],0,cluster.R)
		for x in [-.96, 0.0, .96]:
			for y in [-.82, 0.0, .82]:
				targets.append(cluster.to_global(xf * Vector3(x * window[3],y * window[4],window[5] + .0014)))
	for g: Dictionary in cluster.gauges:
		var frame: Transform3D = cluster.Kit.on_arc(g.x,g.y,0,cluster.R)
		for offset: Vector2 in [Vector2(-.55,.20),Vector2(.55,.20),Vector2(0,.65),Vector2(0,-.55)]:
			targets.append(cluster.to_global(frame * Vector3(offset.x*g.rf,offset.y*g.rf,g.face+.003)))
	# Also trace to the lower status strips, points counter and two heel trays.
	# A high undertray can hide these even when every gauge above it is visible.
	for x in [-.32,-.17,0.0,.17,.32]:
		var at: Transform3D = cluster.Kit.on_arc(x,-.125,.02,cluster.R)
		targets.append(cluster.to_global(at.origin))
	for x in [-.20,.20]:
		targets.append(game.shell.to_global(Vector3(x,.16,-.16)))
	for group in [game.interior,game.slide_switch,game.mode_switch]:
		for label: Label3D in group.find_children("*","Label3D",true,false):
			if label.is_visible_in_tree() and not label.text.is_empty():
				targets.append(label.global_position)
	var seen := true
	for fitting: MeshInstance3D in obstacles:
		var surface := fitting.mesh.generate_triangle_mesh()
		for eye_x in [-.033,.033]:
			for drop in [0.0,.04]:
				var eye := fitting.to_local(game.shell.to_global(game.EYE+Vector3(eye_x,-drop,0)))
				var samples := targets.duplicate()
				if not meter.cursors.has(fitting.get_parent()):
					samples.append_array(card_targets)
				for target in samples:
					var dial := fitting.to_local(target)
					var hit := surface.intersect_ray(eye,eye.direction_to(dial))
					if hit and eye.distance_to(hit.position) < eye.distance_to(dial)-.002:
						seen = false
						print("Sight line blocked ",game.sim.P.vehicle," ",fitting.name," to ",cluster.to_local(target))
	check(game.sim.P.vehicle + " both eyes see the meters, displays, console legends and footwells at both heights",seen)


func _run() -> void:
	var prefs_existed := FileAccess.file_exists(Settings.PREFS)
	var previous := FileAccess.get_file_as_bytes(Settings.PREFS) if prefs_existed else PackedByteArray()
	var config := ConfigFile.new()
	config.set_value("flight", "vehicle", 27)
	config.set_value("flight", "unrelated", "keep")
	config.save(Settings.PREFS)
	check("malformed preference recovers to original", Settings.selected_craft() == "phaethon")
	check("direct launch accepts the explicit vehicle", Sim.PilotCraft.resolve(["--vehicle=shrike"], "phaethon") == "shrike")
	for id in ["orrery", "kiln", "vesper", "basilisk"]:
		var result := trial(id)
		check(id + " reaches 1,000 mph and turns under differential thrust", result.x < 10.0 and result.y > 0)
		print(id, " 1000 mph seconds / split-lever yaw degrees ", result)
	var stock := trial("phaethon")
	check("the Talon flies as the Phaethon does (the same tuning)", trial("talon") == stock)
	var shrike := trial("shrike")
	print("1000 mph, then degrees after 0.5 s at 350 mph: Phaethon ", stock, ", Shrike ", shrike)
	check("Shrike launches faster at equal throttle", shrike.x < stock.x * 0.9 and stock.x < 10)
	check("Shrike turns in harder at equal entry speed", shrike.y > stock.y * 1.1 and stock.y > 0)
	# (A flight chosen from the VR board now begins cold, parked with both air brakes held out: these checks are of a
	# craft that is running, as the packaged build's own verifier asks for.)
	preload("res://vr/vr_cockpit.gd").cold_start = false
	preload("res://vr/vr_cockpit.gd")._startup_loaded = true      # (... whatever the saved choice says)
	for vr in [false, true]:
		var scene := "res://release/vr_menu.tscn" if vr else "res://release/menu.tscn"
		for id in ["talon", "shrike", "orrery", "kiln", "vesper", "basilisk", "phaethon"]:
			change_scene_to_file(scene)
			await scene_changed
			var menu = current_scene
			check("menu recalls the persisted craft", menu.craft_selector.selected == Settings.selected_craft())
			if vr:
				menu.focus_row(menu.buttons.find(menu.craft_selector.button))
				menu.activate()
				menu.choose_course("range")
				menu.focus_row(menu.start_index)
				menu.activate()
			else:
				menu.craft_selector.button.pressed.emit()
				menu.start_course("range")
			await scene_changed
			var game = current_scene
			await process_frame
			await process_frame
			var is_shrike: bool = id == "shrike"
			check("selected and saved " + id, game.sim.P.vehicle == id and Settings.selected_craft() == id)
			check("both engine fairings match the selection", game.craft.engines.all(func(e): return e.has_node("ShrikeFairing") == is_shrike))
			check("visible pod trim matches the selection", game.craft.pod.has_node("ShrikeStrakes") == is_shrike)
			if is_shrike:
				check_airframe(game.craft)
				check_pod_controls(game, vr)
			if game.craft.Fleet.supports(id):
				check_fleet(game, id, vr)
			if vr:
				check_flight_deck(game, id)
				check("the pilot sees the selected cabin", (game.shell.find_child("ShrikePlate", true, false) != null) == is_shrike)
				check("tow instrument matches the selection", (game.tow_meter != null) == is_shrike)
				if is_shrike:
					game.craft.cable_strain.assign([0.23, 0.97])
					game._update_hud()
					var loads: Vector2 = game.tow_meter.get_shader_parameter("loads")
					check("port and starboard load indications respond independently", loads.is_equal_approx(Vector2(0.23, 0.97)))
			var gap: float = game.craft.engines[0].position.distance_to(game.craft.engines[1].position)
			check("rendered engine separation matches the chassis", absf(gap - game.sim.P.engineGap) < 0.1)
	config.load(Settings.PREFS)
	check("cycling craft preserves other settings", config.get_value("flight", "unrelated", "") == "keep")
	if prefs_existed:
		var file := FileAccess.open(Settings.PREFS, FileAccess.WRITE)
		file.store_buffer(previous)
		file.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.PREFS))
	print("PILOT CRAFT ", "PASS" if failures == 0 else "FAIL")
	quit(int(failures > 0))
