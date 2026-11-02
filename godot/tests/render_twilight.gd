## Twilight render gate (windowed: it renders): the emergency run's pre-dawn twilight must not cost
## the speed cues (Luke: the ground grain, the asphalt joints, the dust and the lights "now feel
## great"). The pilot's view at 4,000 mph on Eridanus' loop, facing the dawn (its front 10 km out),
## rendered in the afternoon (free Eridanus) and in the twilight (the job):
##   twilight    the job's light is the twilight preset, darker than the afternoon, and the dawn's
##               wall is up
##   cues        the lower half's mean gradient (Sobel) keeps at least half the afternoon's
##   no NaNs     with MSAA on (as in the headset) and the craft hidden, no black (NaN) pixels in the
##               upper half, where the dawn's wall and the sky are
##   frame time  p95 at most 13.9 ms (72 Hz), vsync off, with --print-fps
## Prints RENDER TWILIGHT PASS.
## Run: Godot_v4.7.1-stable_win64_console.exe --path godot --resolution 1600x900 -s res://tests/render_twilight.gd -- --mute --print-fps [--out=DIR]
extends SceneTree

const ViewScript := preload("res://view/craft_view.gd")
const MPH := 2.236936
const SETTLE := 45
const TIMED := 240
var fails := 0
var passed := 0
var checks := 3
var v
var frames := 0
var stage := 0
var shots := []
var lum := []
var ms := PackedFloat64Array()
var last_us := 0
var print_fps := false
var out_dir := ""


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--print-fps":
			print_fps = true
			checks = 4
		elif a.begins_with("--out="):
			out_dir = a.get_slice("=", 1)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	root.msaa_3d = Viewport.MSAA_4X   # the headset's: MSAA extrapolates edge pixels' UVs (NaNs if unclamped)
	_view("")


func _view(job: String) -> void:
	ViewScript.track_override = "eridanus"
	ViewScript.job_override = job
	v = ViewScript.new()
	root.add_child(v)
	frames = 0


## On the loop, facing the dawn (the sample whose heading is most against the front's travel), at
## 4,000 mph on the lever; on the job, the clock set so the front is 10 km out.
func _place() -> void:
	var sim = v.sim
	var u := Vector2(cos(sim.P.dawnDir), sin(sim.P.dawnDir))
	var best := -1
	var bd := INF
	for i in range(0, sim.N, 4):
		if sim.tmode[i] != 1 or sim.tmode[posmod(i - 40, sim.N)] != 1 or sim.tmode[(i + 400) % sim.N] != 1:
			continue
		var d := Vector2(sim.ttx[i], sim.tty[i]).dot(u)
		if d < bd:
			bd = d
			best = i
	sim.set_handling("speed")
	sim.respawn(-1, best)
	var vel: float = 4000.0 / MPH
	for b in sim.bodies:
		b.vx = vel * sim.ttx[best]
		b.vy = vel * sim.tty[best]
	v.cruise = 0.87
	v.cam_offset = Vector3(0.3, 0.0, 1.4)   # the pilot's eye
	if not sim.job.is_empty():
		sim.job.t0 = 0.0
		sim.time = sim.t_lit(sim.pod.x, sim.pod.y) - 10000.0 / sim.P.dawnSpeed


func _process(_d: float) -> bool:
	frames += 1
	if frames == 3:
		_place()
		return false
	if frames < SETTLE:
		return false
	if frames == SETTLE:
		var img := root.get_viewport().get_texture().get_image()
		shots.append(img)
		if out_dir != "":
			img.save_png(out_dir.path_join("twilight_%d.png" % stage))
		if stage == 0:
			lum.append(_mean_lum(img))
			v.queue_free()
			ViewScript.track_override = ""
			ViewScript.job_override = ""
			stage = 1
			_view("emergency")
			return false
		lum.append(_mean_lum(img))
		v.craft.visible = false   # the next shot: the sky and the wall alone
		return false
	if frames == SETTLE + 3:
		var bare := root.get_viewport().get_texture().get_image()
		shots.append(bare)
		if out_dir != "":
			bare.save_png(out_dir.path_join("twilight_2_bare.png"))
		v.craft.visible = true
		last_us = Time.get_ticks_usec()
		return false
	if frames < SETTLE + 3:
		return false
	if frames <= SETTLE + 3 + TIMED:
		var now := Time.get_ticks_usec()
		ms.append((now - last_us) / 1000.0)
		last_us = now
		return false
	_judge()
	return true


func _judge() -> void:
	var a: Image = shots[0]
	var b: Image = shots[1]
	var dawn_up: bool = v.dawn != null and v.dawn.wall.visible
	_check("twilight: the job's light is %s (free Eridanus' %s), %.0f%% of the afternoon's brightness; the dawn's wall up (%s)" % [
			v.light_preset, "afternoon", lum[1] / maxf(lum[0], 1e-6) * 100.0, dawn_up],
		v.light_preset == "twilight" and lum[1] < lum[0] * 0.8 and dawn_up)
	var ga := _sobel(a)
	var gb := _sobel(b)
	_check("cues: the lower half's mean gradient %.4f in the twilight, %.4f in the afternoon (%.0f%%, want >= 50%%)" % [gb, ga, gb / maxf(ga, 1e-6) * 100.0], gb >= 0.5 * ga)
	var bare: Image = shots[2]
	var black := 0
	for y in bare.get_height() / 2:
		for x in bare.get_width():
			var c := bare.get_pixel(x, y)
			if c.r + c.g + c.b == 0.0:
				black += 1
	_check("no NaNs: %d black pixels in the upper half (the sky and the dawn's wall)" % black, black == 0)
	if print_fps:
		var s := Array(ms)
		s.sort()
		var p95: float = s[int(s.size() * 0.95)]
		print("  frame p95 %.2f ms, median %.2f ms over %d frames" % [p95, s[s.size() / 2], s.size()])
		_check("frame time: p95 %.2f ms (want <= 13.9 ms, 72 Hz)" % p95, p95 <= 13.9)
	var good: bool = fails == 0 and passed == checks
	print("RENDER TWILIGHT ", "PASS" if good else "FAIL (%d failed, %d of %d passed)" % [fails, passed, checks])
	quit(0 if good else 1)


func _mean_lum(img: Image) -> float:
	var small := img.duplicate() as Image
	small.resize(200, 112)
	var acc := 0.0
	for y in small.get_height():
		for x in small.get_width():
			acc += small.get_pixel(x, y).get_luminance()
	return acc / (small.get_width() * small.get_height())


## The lower half's mean Sobel gradient magnitude (luminance, at 800 x 450).
func _sobel(img: Image) -> float:
	var im := img.duplicate() as Image
	im.resize(800, 450)
	var w := im.get_width()
	var h := im.get_height()
	var L := PackedFloat32Array()
	L.resize(w * h)
	for y in h:
		for x in w:
			L[y * w + x] = im.get_pixel(x, y).get_luminance()
	var acc := 0.0
	var n := 0
	for y in range(h / 2 + 1, h - 1):
		for x in range(1, w - 1):
			var gx := (L[(y - 1) * w + x + 1] + 2.0 * L[y * w + x + 1] + L[(y + 1) * w + x + 1]) - (L[(y - 1) * w + x - 1] + 2.0 * L[y * w + x - 1] + L[(y + 1) * w + x - 1])
			var gy := (L[(y + 1) * w + x - 1] + 2.0 * L[(y + 1) * w + x] + L[(y + 1) * w + x + 1]) - (L[(y - 1) * w + x - 1] + 2.0 * L[(y - 1) * w + x] + L[(y - 1) * w + x + 1])
			acc += sqrt(gx * gx + gy * gy)
			n += 1
	return acc / n


func _check(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if ok:
		passed += 1
	else:
		fails += 1
