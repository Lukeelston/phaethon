## Fixed pilot-eye evidence at a quadrant exit and an open-ground on-ramp merge.
## --out=DIR --label=before|after. No player settings or save files are used.
extends SceneTree
const View := preload("res://view/craft_view.gd")
var v
var frame := 0
var shot := 0
var output := ""
var label := "junction"
var places := ["R11WN", "OEridanus", "R11WN", "OEridanus"]
var names := ["R11WN", "OEridanus", "R11WN_exit", "OEridanus_merge"]
var world_script := ""

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			output = a.trim_prefix("--out=")
		if a.begins_with("--label="):
			label = a.trim_prefix("--label=")
		if a.begins_with("--world-script="):
			world_script = a.trim_prefix("--world-script=")
	DirAccess.make_dir_recursive_absolute(output)
	root.msaa_3d = Viewport.MSAA_4X
	View.track_override = "network"
	View.job_override = "none"
	View.best_dir = OS.get_user_data_dir().path_join("render_junction_")
	v = View.new()
	root.add_child(v)

func _process(_dt: float) -> bool:
	frame += 1
	if frame == 3:
		if shot == 0 and world_script != "":
			v.network_world.free()
			v.network_world = load(world_script).new()
			v.add_child(v.network_world)
			v.network_world.build(v.sim, v)
			v.traffic_net.world = v.network_world
		_place()
	if frame < 85:
		return false
	var path := output.path_join("%s_%s.png" % [label, names[shot]])
	root.get_texture().get_image().save_png(path)
	print("PILOT SHOT ", path)
	shot += 1
	if shot == places.size():
		quit(0)
		return true
	frame = 2
	return false

func _place() -> void:
	var sim = v.sim
	var j: Array = []
	for a in sim.junctions:
		if sim.roads[int(a[3])].name == places[shot] and sim.roads[int(a[0])].name == "E2":
			j = a
			break
	var q := int(j[0])
	var r := int(j[3])
	var R = sim.roads[r]
	var end: int = 0 if int(j[4]) == 0 else R.N - 1
	sim._nearest_on(q, R.px[end], R.py[end], (int(j[1]) + int(j[2])) / 2, 90)
	var direction := 1 if shot == 0 else -1
	var i: int = sim._n_i - direction * 2
	sim.respawn_on(q, i, direction)
	if shot >= 2:
		sim.respawn_on(r, 60 if end == 0 else end - 60, 1)
	v.cam_offset = Vector3(0.3, 0.0, 1.4)
	v.eye = Vector3.INF
	sim.time = 10.0
	print("VIEW %s road %s sample %d, entry %.1f %.1f" % [names[shot], sim.roads[sim.pod.path].name, sim.pod.hint, R.px[end], R.py[end]])
