## Render sheet of the Network (windowed: it renders), for a look without the headset: the pod
## parked at each place (the world streams in round it), the camera where the shot says. MSAA 4x as
## in the headset; the craft hidden but in the pilot's shots.
##   start        the pilot at Eridanus' terminal
##   stack        over the centre crossing, 2 km up: the flyover and its four ramps
##   flyover      on E2 coming up to the crossing, N2's deck crossing over
##   board        the board before a ramp
##   glacier      Glacier's skyline from 30 km down E3, the ice under it
##   basalt       the black rock and its ember cracks, Basalt's towers
##   mesa         the red strata, Mesa's towers
##   turnaround   the end of E1: its board and the loop
## Writes DIR/<name>.png and DIR/network_sheet.jpg (two across).
## Run: Godot_v4.7.1-stable_win64_console.exe --path godot --resolution 1600x900 -s res://tests/render_network_sheet.gd -- --mute --out=DIR
extends SceneTree

const ViewScript := preload("res://view/craft_view.gd")
const SETTLE := 70
var v
var sim
var out_dir := ""
var frames := 0
var shot := 0
var names := ["start", "stack", "flyover", "board", "glacier", "basalt", "mesa", "turnaround"]
var imgs := []


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.get_slice("=", 1)
	if out_dir == "":
		out_dir = OS.get_user_data_dir()
	root.msaa_3d = Viewport.MSAA_4X
	ViewScript.track_override = "network"
	ViewScript.job_override = "none"
	ViewScript.best_dir = OS.get_user_data_dir().path_join("render_network_")
	v = ViewScript.new()
	root.add_child(v)


func _process(_d: float) -> bool:
	frames += 1
	if frames < 3:
		return false
	if frames == 3:
		sim = v.sim
		_place(shot)
		return false
	if frames < 3 + SETTLE:
		return false
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join("%s.png" % names[shot]))
	imgs.append(img)
	print("SHOT %s (%d chunks built, %d boards)" % [names[shot], v.network_world.chunks.size(), v.network_world.boards])
	shot += 1
	if shot >= names.size():
		_sheet()
		return true
	frames = 2
	return false


func _road(name: String) -> int:
	for r in sim.roads.size():
		if sim.roads[r].name == name:
			return r
	return -1


func _near(r: int, x: float, y: float) -> int:
	var R = sim.roads[r]
	var best := 0
	var bd := INF
	for i in range(0, R.N, 2):
		var d := Vector2(R.px[i] - x, R.py[i] - y).length()
		if d < bd:
			bd = d
			best = i
	return best


func _place(s: int) -> void:
	var name: String = names[s]
	v.craft.visible = name == "start"
	v.eye = Vector3.INF
	v.cam_offset = Vector3.ZERO
	match name:
		"start":
			sim.respawn(0)
			v.cam_offset = Vector3(0.3, 0.0, 1.4)
		"stack":
			var r := _road("E2")
			sim.respawn_on(r, _near(r, 288000.0, 300000.0), 1)
			v.eye = Vector3(286000.0, 286000.0, 2600.0)
			v.look = Vector3(300000.0, 300000.0, 0.0)
		"flyover":
			var r := _road("E2")
			var i := _near(r, 296500.0, 300000.0)
			sim.respawn_on(r, i, 1)
			v.eye = Vector3(sim.roads[r].px[i], sim.roads[r].py[i] + 60.0, 6.0)
			v.look = Vector3(300000.0, 300000.0, 70.0)
		"board":
			var r := _road("E2")
			var J: Array = []
			for j in sim.junctions:
				if int(j[0]) == r and sim.roads[int(j[3])].name.begins_with("R11"):
					J = j
					break
			var i: int = maxi(0, int(J[1]) - 300)
			sim.respawn_on(r, i, 1)
			var R = sim.roads[r]
			v.eye = Vector3(R.px[i], R.py[i], 8.0)
			v.look = Vector3(R.px[i + 40], R.py[i + 40], 40.0)
		"glacier":
			var r := _road("E3")
			var i := _near(r, 498000.0, 500000.0)
			sim.respawn_on(r, i, 1)
			var R = sim.roads[r]
			v.eye = Vector3(R.px[i], R.py[i], 30.0)
			v.look = Vector3(529000.0, 513000.0, 400.0)
		"basalt":
			var r := _road("E1")
			var i := _near(r, 95000.0, 100000.0)
			sim.respawn_on(r, i, -1)
			var R = sim.roads[r]
			v.eye = Vector3(R.px[i], R.py[i] - 300.0, 40.0)
			v.look = Vector3(71000.0, 87000.0, 150.0)
		"mesa":
			var r := _road("E1")
			var i := _near(r, 548000.0, 100000.0)
			sim.respawn_on(r, i, -1)
			var R = sim.roads[r]
			v.eye = Vector3(R.px[i], R.py[i] - 300.0, 40.0)
			v.look = Vector3(529000.0, 87000.0, 150.0)
		"turnaround":
			var r := _road("E1")
			var R = sim.roads[r]
			var i: int = R.N - 1 - 330
			sim.respawn_on(r, i, 1)
			v.eye = Vector3(R.px[i], R.py[i], 120.0)
			v.look = Vector3(R.px[R.N - 1] + 9000.0, R.py[R.N - 1], 0.0)
	sim.time = 10.0


func _sheet() -> void:
	var w := 800
	var h := 450
	var rows := int(ceil(imgs.size() / 2.0))
	var sheet := Image.create(w * 2, h * rows, false, Image.FORMAT_RGB8)
	for i in imgs.size():
		var im := (imgs[i] as Image).duplicate() as Image
		im.convert(Image.FORMAT_RGB8)
		im.resize(w, h, Image.INTERPOLATE_LANCZOS)
		sheet.blit_rect(im, Rect2i(0, 0, w, h), Vector2i((i % 2) * w, (i / 2) * h))
	sheet.save_jpg(out_dir.path_join("network_sheet.jpg"), 0.9)
	print("SHEET %s (%d shots)" % [out_dir.path_join("network_sheet.jpg"), imgs.size()])
