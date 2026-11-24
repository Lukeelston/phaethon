## Where the tow links run under the Talon's nose: the highest point of any link part (swivel, barrel, boot, rod,
## yoke) in hull space, over a grid of stations (z, 0.1 m) and |x| (0.05 m), through test_talon_prow.gd's flight.
## --headless --xr-mode off --audio-driver Dummy -s res://tests/probe_talon_links.gd -- --mute
extends SceneTree

const View := preload("res://view/craft_view.gd")
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
	var grid := {}      # Vector2i(z bin, |x| bin) -> highest y
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
					var local := hull.global_transform.affine_inverse() * part.global_transform
					for p in part.mesh.get_faces():
						var q := local * p
						if q.z < -4.0 or q.z > -1.8 or absf(q.x) > 0.8:
							continue
						var key := Vector2i(floori(q.z / 0.1), floori(absf(q.x) / 0.05))
						grid[key] = maxf(grid.get(key, -INF), q.y)
	var line := "z \\ |x|:"
	for xi in 16:
		line += " %5.2f" % (xi * 0.05)
	print(line)
	for zi in range(-40, -18):
		line = "%5.1f  :" % (zi * 0.1)
		for xi in 16:
			var v = grid.get(Vector2i(zi, xi))
			line += "     ." if v == null else " %+.2f" % v
		print(line)
	View.vehicle_override = ""
	game.free()
	quit(0)
