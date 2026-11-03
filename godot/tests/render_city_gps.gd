## Render sheet of the city GPs (windowed: it renders): each from 400 m up behind its start line,
## looking down the first straight, in its city's landscape with its towers round it.
## Writes DIR/<gp>.png and DIR/city_gps.jpg (two across).
## Run: Godot_v4.7.1-stable_win64_console.exe --path godot --resolution 1600x900 -s res://tests/render_city_gps.gd -- --mute --out=DIR
extends SceneTree

const ViewScript := preload("res://view/craft_view.gd")
const GPS := ["gp_dunes", "gp_glacier", "gp_basalt", "gp_mesa"]
var v
var frames := 0
var shot := 0
var out_dir := ""
var imgs := []


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.get_slice("=", 1)
	root.msaa_3d = Viewport.MSAA_4X
	_view()


func _view() -> void:
	ViewScript.track_override = GPS[shot]
	ViewScript.job_override = "none"
	v = ViewScript.new()
	root.add_child(v)
	frames = 0


func _process(_d: float) -> bool:
	frames += 1
	if frames == 3:
		var sim = v.sim
		v.craft.visible = false
		var i := 0
		v.eye = Vector3(sim.tpx[i] - sim.ttx[i] * 900.0 - sim.tnx[i] * 300.0, sim.tpy[i] - sim.tty[i] * 900.0 - sim.tny[i] * 300.0, 420.0)
		v.look = Vector3(sim.tpx[i] + sim.ttx[i] * 2500.0, sim.tpy[i] + sim.tty[i] * 2500.0, 0.0)
	if frames < 40:
		return false
	var img := root.get_viewport().get_texture().get_image()
	if out_dir != "":
		img.save_png(out_dir.path_join("%s.png" % GPS[shot]))
	imgs.append(img)
	print("SHOT %s" % GPS[shot])
	v.queue_free()
	shot += 1
	if shot >= GPS.size():
		var w := 800
		var h := 450
		var sheet := Image.create(w * 2, h * 2, false, Image.FORMAT_RGB8)
		for k in imgs.size():
			var im := (imgs[k] as Image).duplicate() as Image
			im.convert(Image.FORMAT_RGB8)
			im.resize(w, h, Image.INTERPOLATE_LANCZOS)
			sheet.blit_rect(im, Rect2i(0, 0, w, h), Vector2i((k % 2) * w, (k / 2) * h))
		sheet.save_jpg(out_dir.path_join("city_gps.jpg"), 0.9)
		print("SHEET city_gps.jpg")
		return true
	_view()
	return false
