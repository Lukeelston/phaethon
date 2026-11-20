## A fingerprint of the Network's terrain and its props, to prove a faster way of building them
## builds the same thing: for a handful of tiles (open country, a highway's corridor, the coast road,
## the drop), a hash of the tile's mesh arrays as the streamer builds them (two rows a slice) and of
## its prop records. Prints TERRAIN HASH lines; compare two runs.
## Run: --headless --xr-mode off --audio-driver Dummy -s res://tests/probe_terrain_hash.gd -- --mute
extends SceneTree

const View := preload("res://view/craft_view.gd")
const TILES := [Vector2i(36, 36), Vector2i(12, 26), Vector2i(1, 20), Vector2i(1, 35), Vector2i(71, 52), Vector2i(71, 47), Vector2i(3, 12), Vector2i(50, 61)]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	View.track_override = "network"
	View.job_override = "none"
	View.best_dir = OS.get_user_data_dir().path_join("terrain_hash_")
	var v = View.new()
	root.add_child(v)
	v.set_process(false)
	var land = v.get("landscape")
	var all := []
	for key in TILES:
		var job: Dictionary = land._new_job(key)
		while int(job.row) < land.GRID + 1:
			land._rows(job, 2)
		var mesh: ArrayMesh = land._mesh(job)
		var arrays := mesh.surface_get_arrays(0)
		var mesh_hash := hash([arrays[Mesh.ARRAY_VERTEX], arrays[Mesh.ARRAY_NORMAL], arrays[Mesh.ARRAY_COLOR], arrays[Mesh.ARRAY_TEX_UV]])
		var props: Array = land.prop_records(key)
		var flat := []
		for p in props:
			flat.append([p.kind, p.p, snappedf(p.height, 0.0001), snappedf(p.scale, 0.0001), snappedf(p.yaw, 0.0001)])
		print("TERRAIN HASH tile %s: mesh %d, %d props %d" % [key, mesh_hash, props.size(), hash(flat)])
		all.append([mesh_hash, hash(flat)])
	print("TERRAIN HASH all: %d" % hash(all))
	v.free()
	quit()
