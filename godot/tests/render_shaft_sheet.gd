## Render sheet of the Network's new pieces (windowed: it renders), for a look without the headset: the
## pod parked at each place with the flight paused (the main menu's pause), the driving partner on.
##   board      coming up to a jump's board on E2
##   fork       on the exit ramp, the board over the fork, the spur's chevrons
##   far        a shaft from 12 km down its dead-straight highway
##   foot       the pull-up, going in
##   up         straight up the shaft
##   apex       upside down over the top
##   twist      coming down, rolling over
##   out        the pull-out, the highway ahead the other way
##   side       the whole shaft from the side
##   corner     a side road: the corner's board, its speed and gear
## Writes DIR/shaft_sheet.jpg (two across) and DIR/<name>.png.
## Run: Godot_v4.7.1-stable_win64_console.exe --path godot --resolution 1600x900 -s res://tests/render_shaft_sheet.gd -- --mute --out=DIR
extends SceneTree

const ViewScript := preload("res://view/craft_view.gd")
const SETTLE := 70
var v
var sim
var out_dir := ""
var frames := 0
var shot := 0
var names := ["board", "fork", "far", "foot", "up", "apex", "twist", "out", "side", "corner"]
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
	ViewScript.best_dir = OS.get_user_data_dir().path_join("render_shaft_")
	v = ViewScript.new()
	root.add_child(v)


func _process(_d: float) -> bool:
	frames += 1
	if frames < 3:
		return false
	if frames == 3:
		sim = v.sim
		v.set_partner(true)
		_place(names[shot])
		return false
	if frames < 3 + SETTLE:
		return false
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join("%s.png" % names[shot]))
	imgs.append(img)
	print("SHOT %s (%d chunks, pod at %.0f m, cam %s)" % [names[shot], v.network_world.chunks.size(), sim.pod.z, v.cam.position])
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


## On shaft road r, d m past its pull-up.
func _on_shaft(r: int, d: float) -> void:
	for sh in sim.shafts:
		if int(sh[0]) == r:
			sim.respawn_on(r, int(sh[1]) + roundi(d / 24.0), 1)


func _place(name: String) -> void:
	v.menu.open = false
	v.eye = Vector3.INF
	var t := _road("TE2+")
	var sh: Array = []
	for q in sim.shafts:
		if int(q[0]) == t:
			sh = q
	var R_s: float = sh[3]
	var V: float = sh[4]
	var q := PI * R_s / 2.0
	match name:
		"board":
			var found := false
			for key in v.network_world._signs:
				for spec in v.network_world._signs[key]:
					if spec[2] == "jump" and sim.roads[key.x].name == "E2" and not found and int(spec[1]) < 0:
						found = true
						sim.respawn_on(key.x, int(spec[0]) + 24, -1)
		"fork":
			var J = sim.jumps[0]
			var L = sim.roads[int(J[0])]
			for j in sim.junctions:
				if int(j[3]) == int(J[0]):
					var P = sim.roads[int(j[0])]
					var at := 0
					var bd := INF
					for i in range(0, P.N):
						var d := Vector2(P.px[i] - L.px[0], P.py[i] - L.py[0]).length()
						if d < bd:
							bd = d
							at = i
					sim.respawn_on(int(j[0]), maxi(1, at - 34), 1)
		"far":
			var e2 := _road("E2")
			sim.respawn_on(e2, sim.roads[e2].N - 1 - 500, 1)
		"foot":
			_on_shaft(t, q * 0.35)
		"up":
			_on_shaft(t, q + V * 0.5)
		"apex":
			_on_shaft(t, 2.0 * q + V)
		"twist":
			_on_shaft(t, 3.0 * q + V * 1.5)
		"out":
			_on_shaft(t, 4.0 * q + 2.0 * V - 600.0)
		"side":
			var e2 := _road("E2")
			var R = sim.roads[e2]
			var i: int = R.N - 1 - 60
			sim.respawn_on(e2, i, 1)
			v.eye = Vector3(R.px[i] + 6000.0, R.py[i] - 16000.0, 3000.0)
			v.look = Vector3(R.px[i] + 6000.0, R.py[i], 6000.0)
		"corner":
			for key in v.network_world._signs:
				for spec in v.network_world._signs[key]:
					if spec[2] == "corner" and sim.roads[key.x].name == "S1" and name == "corner":
						sim.respawn_on(key.x, int(spec[0]) - 40 * int(spec[1]), int(spec[1]))
						name = "done"
	v._sim_step()
	v._follow_origin()
	v.partner.placed = false   # (on its station for the shot; in flight it flies there)
	v.partner.update(0.0)
	v.menu.open = true   # the flight waits (a parked craft would slide back down a shaft)
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
	sheet.save_jpg(out_dir.path_join("shaft_sheet.jpg"), 0.9)
	print("SHEET %s (%d shots)" % [out_dir.path_join("shaft_sheet.jpg"), imgs.size()])
