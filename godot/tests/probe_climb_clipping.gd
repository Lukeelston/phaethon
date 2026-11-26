## Where the pilot passes through the craft during each climb (Luke, 2026-11-25: "the pilot still clips through the mesh a
## lot"). Every visible mesh of the occupied cab (hull, seat, consoles, dash, levers, the canopy and its arms or rams) and
## of the display pod's lent parts is copied into a trimesh body, kept on the mesh as it moves; each part of the suit
## (convex hulls of its own meshes) is tested against them at every step of the climb. Touching is allowed: a part
## counts only past DEPTH beyond how deep it already sits in the stock seated pose (_baseline: the seat pose's own boots
## in the footwell, the climb's first and last moments). Prints CLIP lines (each step that clips: when, which part, how deep, into what) and a
## CLIPSUM line per climb (frames clipping, worst depth, per part).
## With --profile, instead: the cab's shape on the gate side by rays (canonical, the bay's frame: +X the gate side),
## PROFILE lines: the rim's top along the cockpit, the hull's outside by height, the cockpit's floor; and how far the
## stock seated pose itself sits in the cab (CLIPBASE).
##   --headless --xr-mode off -s res://tests/probe_climb_clipping.gd -- --mute [--craft=kiln] [--talon] [--leg=in] [--quiet] [--profile]
extends SceneTree

const Pilot := preload("res://sim/pilot_craft.gd")
const Settings := preload("res://release/game_settings.gd")
const Route := preload("res://release/garage_route.gd")
const GARAGE := "res://garage/garage.tscn"
const CanopyRig := preload("res://garage/canopy_rig.gd")
const LAYER := 1 << 19
const DEPTH := 0.025          # m: deeper than this is through the skin, not resting on it
# How deep a part is: the deepest of these that the part, shrunk inward by it, still meets the cab at (the physics
# solver's own contact depth read a boot resting on the detailed floor as 30 cm through it).
const INSETS := [0.025, 0.05, 0.10, 0.20]
const STEP := 1.0 / 30.0
var only := ""
var leg_only := ""
var quiet := false
var total_frames := 0
var total_clipped := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var talon := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--craft="):
			only = arg.trim_prefix("--craft=")
		elif arg.begins_with("--leg="):
			leg_only = arg.trim_prefix("--leg=")
		elif arg == "--talon":
			talon = true
		elif arg == "--quiet":
			quiet = true
	var prefs_before := Settings.prefs_path
	Settings.prefs_path = "user://probe-clipping-%d.cfg" % OS.get_process_id()
	Settings.set_phaethon_body("talon" if talon else "phaethon")
	Route.enter(self, false, "network")
	var until := Time.get_ticks_msec() + 30000
	while (current_scene == null or current_scene.scene_file_path != GARAGE) and Time.get_ticks_msec() < until:
		await process_frame
	var garage = current_scene
	for tick in 5:
		await process_frame
	var parts := _suit(garage.pilot)
	if OS.get_cmdline_user_args().has("--sizes"):
		for entry: Array in parts:
			var part: MeshInstance3D = entry[0]
			var box := part.mesh.get_aabb()
			var shape: ConvexPolygonShape3D = entry[1]
			var low := INF
			for point in shape.points:
				low = minf(low, point.y)
			print("SIZE %s parent=%s aabb %s..%s hull-low %.3f" % [part.name, part.get_parent().name, box.position, box.end, low])
		quit(0)
		return
	var profile := OS.get_cmdline_user_args().has("--profile")
	for id: String in Pilot.GARAGE_BAYS:
		var craft: String = garage.environment.bay_craft(id)
		if not only.is_empty() and craft != only:
			continue
		if profile:
			await _profile(garage, id, craft, parts)
		else:
			await _measure(garage, id, craft, parts)
	if FileAccess.file_exists(Settings.prefs_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.prefs_path))
	Settings.prefs_path = prefs_before
	print("CLIPTOTAL %d of %d frames clip" % [total_clipped, total_frames])
	quit(0)


## Each suit part with a mesh: [the part, its convex hull, that hull shrunk by each of INSETS].
func _suit(pilot: Node3D) -> Array:
	var parts := []
	for node: Node in pilot.find_children("*", "MeshInstance3D", true, false):
		var part := node as MeshInstance3D
		if part.mesh == null:
			continue
		var hull := part.mesh.create_convex_shape(true, false)
		var centre := Vector3.ZERO
		for point in hull.points:
			centre += point
		centre /= maxf(1.0, hull.points.size())
		var shrunk := []
		for inset: float in INSETS:
			var points := PackedVector3Array()
			for point in hull.points:
				var out := point - centre
				points.append(centre + out * maxf(0.0, 1.0 - inset / maxf(out.length(), 0.0001)))
			var shape := ConvexPolygonShape3D.new()
			shape.points = points
			shrunk.append(shape)
		parts.append([part, hull, shrunk])
	return parts


## How deep `part` is in the cab: the deepest inset its shrunk hull still meets anything at (0: not past the first).
func _depth(space: PhysicsDirectSpaceState3D, entry: Array) -> float:
	var part: MeshInstance3D = entry[0]
	var query := PhysicsShapeQueryParameters3D.new()
	query.transform = Transform3D(part.global_transform.basis.orthonormalized(), part.global_transform.origin)
	query.collision_mask = LAYER
	var depth := 0.0
	for k in INSETS.size():
		query.shape = entry[2][k]
		if space.intersect_shape(query, 1).is_empty():
			break
		depth = INSETS[k]
	return depth


## How deep each suit part sits in the cab in the stock seated pose (garage.gd interact(), instant): the climb is
## measured past this (its first and last moments are that pose, and it is not the climb's doing).
func _baseline(garage, id: String, parts: Array) -> Dictionary:
	var hall = garage.environment
	garage.walker.set_seated(false, hall.boarding_transform(id))
	await process_frame
	garage.interact()
	await process_frame
	var obstacles := _obstacles(garage, id)
	await physics_frame
	await physics_frame
	var space := root.get_world_3d().direct_space_state
	var base := {}
	for entry: Array in parts:
		base[(entry[0] as Node).name] = _depth(space, entry)
	for pair: Array in obstacles:
		(pair[0] as Node).queue_free()
	garage.leave_seat()
	await process_frame
	return base


func _measure(garage, id: String, craft: String, parts: Array) -> void:
	var hall = garage.environment
	var base: Dictionary = await _baseline(garage, id, parts)
	var gate: Transform3D = hall.boarding_transform(id)
	garage.walker.set_seated(false, Transform3D(gate.basis, gate.origin + gate.basis.z * 0.9))
	for tick in 3:
		await process_frame
	for leg in ["in", "out"]:
		garage._board_button()
		var climb = garage._climb
		climb.set_process(false)
		if not leg_only.is_empty() and leg != leg_only:
			climb.finish_now()
			continue
		var obstacles := _obstacles(garage, id)
		var space := root.get_world_3d().direct_space_state
		var bay: Node3D = hall.bay_node(id)
		var side := signf((bay.global_transform.affine_inverse() * gate.origin).x)
		var frames := 0
		var clipped := 0
		var worst := {}
		var t := 0.0
		while not climb.pilot_done:
			climb.advance(STEP)
			t += STEP
			if climb.pilot_done:
				break
			for pair: Array in obstacles:
				(pair[0] as StaticBody3D).global_transform = (pair[1] as Node3D).global_transform
			await physics_frame
			frames += 1
			var said := []
			for entry: Array in parts:
				var part: MeshInstance3D = entry[0]
				if not part.is_visible_in_tree():
					continue
				var depth := _depth(space, entry)
				if depth < DEPTH or depth <= float(base.get(part.name, 0.0)):
					continue
				var query := PhysicsShapeQueryParameters3D.new()
				query.shape = entry[2][0]
				query.transform = Transform3D(part.global_transform.basis.orthonormalized(), part.global_transform.origin)
				query.collision_mask = LAYER
				var local: Vector3 = bay.global_transform.affine_inverse() * part.global_transform * part.mesh.get_aabb().get_center()
				local.x *= side
				var into := []
				for hit: Dictionary in space.intersect_shape(query, 8):
					var name := String((hit.collider as Node).name)
					if name not in into:
						into.append(name)
				var lowest := INF
				var box: AABB = part.mesh.get_aabb()
				for c in 8:
					lowest = minf(lowest, (bay.global_transform.affine_inverse() * part.global_transform * box.get_endpoint(c)).y)
				said.append("%s %.3f @(%.2f %.2f %.2f) low %.3f [%s]" % [part.name, depth, local.x, local.y, local.z, lowest, ",".join(into)])
				if depth > float(worst.get(part.name, 0.0)):
					worst[part.name] = depth
			if not said.is_empty():
				clipped += 1
				if not quiet:
					print("CLIP %s %s t=%.2f %s" % [craft, leg, t, "  ".join(said)])
		climb.finish_now()
		for pair: Array in obstacles:
			(pair[0] as Node).queue_free()
		total_frames += frames
		total_clipped += clipped
		var parts_said := []
		for name in worst:
			parts_said.append("%s %.3f" % [name, worst[name]])
		print("CLIPSUM %s %s: %d of %d frames clip; %s" % [craft, leg, clipped, frames, ", ".join(parts_said)])
		await process_frame


## A trimesh body for every visible mesh the climb can meet: [body, the mesh it follows].
func _obstacles(garage, id: String) -> Array:
	var bay: Node3D = garage.environment.bay_node(id)
	var sources: Array[Node] = garage._cockpit.find_children("*", "MeshInstance3D", true, false)
	sources.append_array(bay.model.pod.find_children("*", "MeshInstance3D", true, false))
	var pairs := []
	for node in sources:
		var mesh := node as MeshInstance3D
		if mesh.mesh == null or not mesh.is_visible_in_tree() or mesh.mesh.get_aabb().size.length() < 0.06:
			continue
		var body := StaticBody3D.new()
		body.name = String(mesh.name) if mesh.get_parent() == null else "%s/%s" % [mesh.get_parent().name, mesh.name]
		body.collision_layer = LAYER
		body.collision_mask = 0
		var shape := CollisionShape3D.new()
		var tri := mesh.mesh.create_trimesh_shape()
		tri.backface_collision = false      # (two-sided, a boot resting on a thin floor plate read as through it: the solver pushed it out the far side)
		shape.shape = tri
		body.add_child(shape)
		root.add_child(body)
		body.global_transform = mesh.global_transform
		pairs.append([body, mesh])
	return pairs


func _profile(garage, id: String, craft: String, parts: Array) -> void:
	var hall = garage.environment
	var bay: Node3D = hall.bay_node(id)
	var gate: Transform3D = hall.boarding_transform(id)
	var side := signf((bay.global_transform.affine_inverse() * gate.origin).x)
	garage.walker.set_seated(false, gate)
	await process_frame
	garage.interact()      # (instant: the stock seated pose, the cab shown)
	await process_frame
	var pilot: Node3D = garage.pilot
	var shot: Dictionary = pilot.snapshot()
	var seated := []
	for key in ["ankles", "knees", "grips"]:
		for i in 2:
			var p: Vector3 = shot[key][i] if key != "knees" else shot.hips[i] + (shot.ankles[i] - shot.hips[i]) * 0.5 + shot.knees[i]
			var b: Vector3 = bay.global_transform.affine_inverse() * (pilot.global_transform * p)
			seated.append("%s%d(%.2f %.2f %.2f)" % [key.left(4), i, b.x * side, b.y, b.z])
	print("SEATED %s %s" % [craft, " ".join(seated)])
	var rig := CanopyRig.new(craft, garage._cockpit.shell.get_node("canopy"), side)
	rig.apply(1.0)      # (open: the rims and the floor as the climb meets them)
	await process_frame
	var obstacles := _obstacles(garage, id)
	await physics_frame
	await physics_frame
	var space := root.get_world_3d().direct_space_state
	var said := []
	for entry: Array in parts:
		var part: MeshInstance3D = entry[0]
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = entry[1]
		query.transform = Transform3D(part.global_transform.basis.orthonormalized(), part.global_transform.origin)
		query.collision_mask = LAYER
		var points := space.collide_shape(query, 32)
		var depth := 0.0
		for k in range(0, points.size(), 2):
			depth = maxf(depth, points[k].distance_to(points[k + 1]))
		if depth > 0.0:
			said.append("%s %.3f" % [part.name, depth])
	print("CLIPBASE %s seated: %s" % [craft, ", ".join(said)])
	var to_world := func(p: Vector3) -> Vector3: return bay.global_transform * Vector3(p.x * side, p.y, p.z)
	var ray := func(a: Vector3, b: Vector3) -> Vector3:
		var q := PhysicsRayQueryParameters3D.create(to_world.call(a), to_world.call(b), LAYER)
		q.hit_back_faces = true
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return Vector3.INF
		var at: Vector3 = bay.global_transform.affine_inverse() * hit.position
		return Vector3(at.x * side, at.y, at.z)
	# the rim's top: straight down at each x out from the centreline, at three stations along the cockpit
	for z in [0.30, 0.60, 0.90]:
		var row := []
		for i in 34:
			var x := 0.30 + i * 0.07
			var hit: Vector3 = ray.call(Vector3(x, 2.5, z), Vector3(x, -0.7, z))
			row.append("%.2f:%s" % [x, "-" if hit == Vector3.INF else "%.2f" % hit.y])
		print("PROFILE %s top z=%.2f  %s" % [craft, z, " ".join(row)])
	# the hull's outside: in from the gate side at each height
	for z in [0.40, 0.65]:
		var row := []
		for i in 13:
			var y := -0.65 + i * 0.12
			var hit: Vector3 = ray.call(Vector3(3.2, y, z), Vector3(0.0, y, z))
			row.append("%.2f:%s" % [y, "-" if hit == Vector3.INF else "%.2f" % hit.x])
		print("PROFILE %s outside z=%.2f  %s" % [craft, z, " ".join(row)])
	# the cockpit's floor and the seat: straight down at the centreline and at 0.2 out, along the cockpit
	for x in [0.0, 0.2]:
		var row := []
		for i in 14:
			var z := -0.60 + i * 0.12
			var hit: Vector3 = ray.call(Vector3(x, 1.2, z), Vector3(x, -0.7, z))
			row.append("%.2f:%s" % [z, "-" if hit == Vector3.INF else "%.2f" % hit.y])
		print("PROFILE %s floor x=%.1f  %s" % [craft, x, " ".join(row)])
	# the footwell: a grid straight down, and the interior parts' bounds
	for zi in 12:
		var z := -0.40 + zi * 0.08
		var row := []
		for xi in 9:
			var x := -0.40 + xi * 0.10
			var hit: Vector3 = ray.call(Vector3(x, 0.70, z), Vector3(x, -0.7, z))
			row.append("-" if hit == Vector3.INF else "%.2f" % hit.y)
		print("WELL %s z=%.2f  x-0.4..0.4: %s" % [craft, z, " ".join(row)])
	for node in garage._cockpit.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.name in ["InstrumentBezel", "PowderCoatedPanels", "SeatTub", "ConsoleL", "ConsoleR", "RecessedConduits", "GuardAndGatePaint"]:
			var box: AABB = bay.global_transform.affine_inverse() * mesh.global_transform * mesh.mesh.get_aabb()
			print("PART %s %s %s..%s tris %d" % [craft, mesh.name, box.position, box.end, mesh.mesh.get_faces().size() / 3])
	for pair: Array in obstacles:
		(pair[0] as Node).queue_free()
	rig.apply(0.0)
	rig.free_links()
	garage.leave_seat()
	await process_frame
