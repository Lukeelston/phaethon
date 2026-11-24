## The Talon's forward fairing projects past both tow posts (Codex's prow test, e2675a1, brought to the Talon and
## to today's tow links: they were ropes, now jointed drawbars, view/tow_link.gd). Check every part of each link
## (its swivel, barrel, boot, rod and yoke) against the plating's actual triangles under slack, acceleration and
## split-lever turns, with the nose open and closed.
## --headless --xr-mode off --audio-driver Dummy -s res://tests/test_talon_prow.gd -- --mute
## Prints TALON PROW PASS.
extends SceneTree

const View := preload("res://view/craft_view.gd")
const Talon := preload("res://view/talon_airframe.gd")
const LEVERS := [Vector2.ZERO, Vector2(0.8, 0.8), Vector2(0.45, 0.88), Vector2(0.9, 0.37)]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	View.track_override = "range"
	View.vehicle_override = "talon"
	View.job_override = "none"
	var game := View.new()
	root.add_child(game)
	game.set_process(false)
	var hull: MeshInstance3D = game.craft.pod
	var hits := 0
	var samples := 0
	var by := {}      # "part, nose, levers" -> [contacts, least z, most z, most y, least |x|, most |x|] (printed when it fails)
	var nose_was: bool = game.craft.nose_closed
	for closed in [false, true]:
		game.craft.set_nose_closed(closed, game)
		var mesh := hull.mesh as ArrayMesh
		var surface := mesh.surface_find_by_name(Talon.SURFACE)
		if surface < 0:
			push_error("The Talon's hull has no plating.")
			quit(1)
			return
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var faces := PackedVector3Array()
		for index in arrays[Mesh.ARRAY_INDEX]:
			faces.append(vertices[index])
		var plating := TriangleMesh.new()
		plating.create_from_faces(faces)
		var bounds := AABB(vertices[0], Vector3.ZERO)
		for p in vertices:
			bounds = bounds.expand(p)
		game.sim.restart()
		for lever: Vector2 in LEVERS:
			var input := {"thrL": lever.x, "thrR": lever.y, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": true}
			for frame in 70:
				for step in 8:
					game.sim.step(input, 1.0 / 480.0)
				game._follow_origin()
				game.craft.sync(game.sim, input, 1.0 / 60.0)
				game.craft.sync_cables(game.sim, 1.0 / 60.0)
				if frame % 5 != 0:
					continue
				for k in 2:
					var parts: Array = game.craft.link_parts[k].duplicate()
					parts.append(game.craft.link_boots[k])
					for part: MeshInstance3D in parts:
						if not part.is_visible_in_tree():
							continue
						var local := hull.global_transform.affine_inverse() * part.global_transform
						if not bounds.grow(0.05).intersects(local * part.mesh.get_aabb()):
							continue
						var skin := part.mesh.get_faces()
						for t in range(0, skin.size(), 3):
							var a := local * skin[t]
							var b := local * skin[t + 1]
							var c := local * skin[t + 2]
							for edge: Array in [[a, b], [b, c], [c, a]]:
								if not bounds.has_point(edge[0]) and bounds.intersects_segment(edge[0], edge[1]) == null:
									continue      # (a rod's long edges run the length of it: through the plating's box with both ends outside)
								samples += 1
								var met := plating.intersect_segment(edge[0], edge[1])
								if not met.is_empty():
									hits += 1
									var at: Vector3 = met.position
									var key := "%s, nose %s, levers %s" % [part.name, "closed" if closed else "open", lever]
									var was: Array = by.get(key, [0, INF, -INF, -INF, INF, -INF])
									by[key] = [was[0] + 1, minf(was[1], at.z), maxf(was[2], at.z), maxf(was[3], at.y), minf(was[4], absf(at.x)), maxf(was[5], absf(at.x))]
	game.craft.set_nose_closed(nose_was, game)
	for name in by:
		print("  %s: %d contacts at z %.3f .. %.3f, |x| %.3f .. %.3f, up to y %.3f" % [name, by[name][0], by[name][1], by[name][2], by[name][4], by[name][5], by[name][3]])
	var passed := hits == 0 and samples > 1000
	print("TALON PROW %s (%d link/plating contacts in %d edge checks)" % ["PASS" if passed else "FAIL", hits, samples])
	View.vehicle_override = ""
	game.free()
	quit(0 if passed else 1)
