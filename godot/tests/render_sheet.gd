## Render sheet (windowed: it renders): the emergency run's sights, one frame each, for a look
## without the headset. On the job (the twilight), MSAA 4x as in the headset, the craft hidden
## except in the pilot's shot on the shade line:
##   pad_far       the pad's red columns from 3.6 km out
##   pad_sign      the sign half a mile before it
##   pad_close     the pad itself from above
##   hall          inside a covered ramp: the roof's bars, the ribs, the strips down the walls
##   stars         the night still overhead, looking away from the dawn
##   dawn          the dawn's wall with its front 10 km out
##   shade_out     the shade line's canopy from outside, over its first corkscrew
##   shade_under   under the canopy, its road rolled over overhead
## Writes each as DIR/<name>.png and the lot as DIR/sheet.jpg (two across, 800 x 450 each).
## Run: Godot_v4.7.1-stable_win64_console.exe --path godot --resolution 1600x900 -s res://tests/render_sheet.gd -- --mute --out=DIR
extends SceneTree

const ViewScript := preload("res://view/craft_view.gd")
const SETTLE := 40
var v
var sim
var out_dir := ""
var frames := 0
var shot := 0
var names := ["pad_far", "pad_sign", "pad_close", "hall", "stars", "dawn", "shade_out", "shade_under"]
var imgs := []


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.get_slice("=", 1)
	if out_dir == "":
		out_dir = OS.get_user_data_dir()
	root.msaa_3d = Viewport.MSAA_4X
	ViewScript.track_override = "eridanus"
	ViewScript.job_override = "emergency"
	ViewScript.best_dir = OS.get_user_data_dir().path_join("render_sheet_")
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
	print("SHOT %s" % names[shot])
	shot += 1
	if shot >= names.size():
		_sheet()
		return true
	frames = 2
	return false


## Sample k's point on the main road, `back` samples before it.
func _at(k: int) -> Vector2:
	k = posmod(k, sim.N)
	return Vector2(sim.tpx[k], sim.tpy[k])


func _place(s: int) -> void:
	var name: String = names[s]
	var u := Vector2(cos(sim.P.dawnDir), sin(sim.P.dawnDir))
	var at := 0
	var e := Vector3.INF
	var l := Vector3.ZERO
	var clock := 20.0   # the front far off
	match name:
		"pad_far":   # 3.6 km out, or just out of the hall before it
			at = sim.pad - 300
			for k in range(sim.pad - 300, sim.pad - 60):
				if sim.tcover[posmod(k, sim.N)] == 1:
					at = k + 12
			var p := _at(at)
			var q := _at(sim.pad)
			e = Vector3(p.x, p.y, 4.0)
			l = Vector3(q.x, q.y, 160.0)
		"pad_sign":
			at = sim.pad - 112
			var p := _at(at)
			var q := _at(sim.pad - 80)
			e = Vector3(p.x, p.y, 5.0)
			l = Vector3(q.x, q.y, 45.0)
		"pad_close":
			at = sim.pad - 22
			var p := _at(at)
			var q := _at(sim.pad)
			var nrm := Vector2(sim.tnx[sim.pad], sim.tny[sim.pad])
			e = Vector3(p.x + nrm.x * 60.0, p.y + nrm.y * 60.0, 70.0)
			l = Vector3(q.x, q.y, 20.0)
		"hall":
			var r: Array = sim.covered_ramps[0]
			at = int(r[0]) + 150
			var p := _at(at)
			var q := _at(at + 22)
			e = Vector3(p.x, p.y, 9.0)
			l = Vector3(q.x, q.y, 16.0)
		"stars", "dawn":
			at = _open_facing(u if name == "stars" else -u)
			var p := _at(at)
			var dir := u if name == "stars" else -u
			e = Vector3(p.x, p.y, 4.0)
			l = Vector3(p.x + dir.x * 100.0, p.y + dir.y * 100.0, 4.0 + (75.0 if name == "stars" else 6.0))
			if name == "dawn":
				clock = sim.t_lit(p.x, p.y) - 10000.0 / sim.P.dawnSpeed
		"shade_out":
			var B = sim.branches[0]
			var k: int = B.covered.x - 30
			at = int(B.from_i) + k
			var nrm := Vector2(B.nx[k], B.ny[k])
			e = Vector3(B.px[k] + nrm.x * 420.0, B.py[k] + nrm.y * 420.0, 70.0)
			var k2: int = k + 60
			l = Vector3(B.px[k2], B.py[k2], 30.0)
		"shade_under":
			var B = sim.branches[0]
			var k: int = B.covered.x + 300
			at = int(B.from_i) + k
			e = Vector3(B.px[k], B.py[k], 40.0)
			l = Vector3(B.px[k + 25], B.py[k + 25], 52.0)
	v.craft.visible = false
	sim.respawn(-1, posmod(at, sim.N))
	v.eye = e
	v.look = l
	v.cam_offset = Vector3.ZERO
	sim.job.t0 = 0.0
	sim.time = clock


## The open loop's sample (every 4th) whose heading is most along `dir`, with open road around it.
func _open_facing(dir: Vector2) -> int:
	var best := 0
	var bd := -INF
	for i in range(0, sim.N, 4):
		if sim.tmode[i] != 1 or sim.tmode[posmod(i - 40, sim.N)] != 1 or sim.tmode[(i + 400) % sim.N] != 1:
			continue
		if sim.tcover[i] == 1:
			continue
		var d := Vector2(sim.ttx[i], sim.tty[i]).dot(dir)
		if d > bd:
			bd = d
			best = i
	return best


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
	sheet.save_jpg(out_dir.path_join("sheet.jpg"), 0.9)
	print("SHEET %s (%d shots)" % [out_dir.path_join("sheet.jpg"), imgs.size()])
