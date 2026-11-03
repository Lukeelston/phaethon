## The Network's frame-time gate (windowed: it renders): 4,000 mph along E2 through the centre
## crossing (N2's flyover overhead, its ramps peeling off), the world streaming in ahead and dropping
## behind, MSAA 4x as in the headset, vsync off, the sim at the headset's pace: each frame 1/120 s of
## sim time whatever the frame took (the time scale set every frame), so the sim and the streaming do
## a headset frame's work in each. (The Quest 3 runs at 120 Hz over Link; at 72 Hz the gate passed
## builds that dropped to 60 fps in the headset, 2026-10-20.)
##   frame time   p95 at most 8.7 ms (120 Hz, the headset report's line), and no frame over 16.7 ms
##                (two headset frames: no streaming hitch)
##   streaming    chunks built and dropped on the way (it's really streaming)
##   horizon      no white band along it: no row of the horizon band (35-60% down the frame) more
##                than 30% near-white (the masts' beacons every 240 m made one 81% white)
##   no whitewash the dust off the engines is road spray, not sand: on the highway at speed it
##                brightens the road under the pilot (the lower half) by at most 8% (Luke: "everything
##                looks like it's whitewashed when at speed"; the sand plumes added 30%). Measured
##                after 20 frames at real time, three frames on, three off (read straight after the
##                timed run, whose pacing goes up to 8x on a loaded machine, it once read +22% where
##                it reads +5% unloaded)
## Prints RENDER NETWORK PASS. --out=DIR saves the view half way.
## Run: Godot_v4.7.1-stable_win64_console.exe --path godot --resolution 1600x900 -s res://tests/render_network.gd -- --mute [--out=DIR]
extends SceneTree

const ViewScript := preload("res://view/craft_view.gd")
const MPH := 2.236936
const SETTLE := 60
const HZ := 120.0
const TIMED := 1500               # 12.5 s: through the crossing and on (~25 km)
var fails := 0
var passed := 0
var v
var frames := 0
var ms := PackedFloat64Array()
var last_us := 0
var out_dir := ""
var built0 := 0
var notes := []
var lum_dust := -1.0
var band_white := -1.0
var lum_clear := -1.0
var _b := 0
var _bd := 0
var p0 := Vector2.ZERO
var held := 0
var img0: Image
var on := []
var off := []


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.get_slice("=", 1)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	root.msaa_3d = Viewport.MSAA_4X
	ViewScript.track_override = "network"
	ViewScript.job_override = "none"
	ViewScript.best_dir = OS.get_user_data_dir().path_join("render_network_")
	v = ViewScript.new()
	root.add_child(v)


func _process(_d: float) -> bool:
	frames += 1
	if frames == 3:
		var sim = v.sim
		var r := -1
		for k in sim.roads.size():
			if sim.roads[k].name == "E2":
				r = k
		var R = sim.roads[r]
		var i := 0
		var bd := INF
		for k in range(0, R.N, 2):
			var d := Vector2(R.px[k] - 275000.0, R.py[k] - 300000.0).length()
			if d < bd:
				bd = d
				i = k
		sim.set_handling("speed")
		sim.respawn_on(r, i, 1)
		for b in sim.bodies:
			b.vx = 4000.0 / MPH * R.tx[i]
			b.vy = 4000.0 / MPH * R.ty[i]
		v.cruise = 0.87
		v.inp = {"thrL": 0.87, "thrR": 0.87, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": true}
		v.cam_offset = Vector3(0.3, 0.0, 1.4)   # the pilot's eye
		return false
	if frames < SETTLE:
		return false
	if frames == SETTLE:
		built0 = v.network_world.built
		p0 = Vector2(v.sim.pod.x, v.sim.pod.y)
		last_us = Time.get_ticks_usec()
		return false
	if frames <= SETTLE + TIMED:
		var now := Time.get_ticks_usec()
		ms.append((now - last_us) / 1000.0)
		last_us = now
		Engine.time_scale = clampf((1.0 / HZ) / maxf(ms[-1] / 1000.0, 1e-4), 0.25, 8.0)
		var W0 = v.network_world
		notes.append([ms[-1], W0.built - _b, W0.boards - _bd, frames, v.traffic_net.update_ms if v.traffic_net else 0.0, v.traffic_net.cars.size() if v.traffic_net else 0])
		_b = W0.built
		_bd = W0.boards
		return false
	Engine.time_scale = 1.0
	held += 1
	if held <= 20:   # settle at real time (see the header)
		if held == 20:
			img0 = root.get_viewport().get_texture().get_image()
			band_white = _band_white(img0)
		return false
	if held <= 23:   # the same view with the dust on, then off (a frame between: the texture is the last frame's)
		on.append(_lum(root.get_viewport().get_texture().get_image()))
		if held == 23:
			v.dust.visible = false
		return false
	if held == 24:
		return false
	if held <= 27:
		off.append(_lum(root.get_viewport().get_texture().get_image()))
		return false
	v.dust.visible = true
	lum_dust = (on[0] + on[1] + on[2]) / 3.0
	lum_clear = (off[0] + off[1] + off[2]) / 3.0
	if out_dir != "":   # (after the timed frames: saving a PNG takes ~200 ms)
		img0.save_png(out_dir.path_join("network_run.png"))
	notes.sort_custom(func(a, b): return a[0] > b[0])
	for n in notes.slice(0, 14):
		print("    slow frame %d: %.1f ms, %d chunks, %d boards; traffic %.2f ms (%d)" % [n[3], n[0], n[1], n[2], n[4], n[5]])
	var s := Array(ms)
	s.sort()
	var p95: float = s[int(s.size() * 0.95)]
	var worst: float = s[-1]
	var W = v.network_world
	print("  frame p95 %.2f ms, median %.2f ms, worst %.2f ms over %d frames; %.0f mph, %.1f km travelled" % [p95, s[s.size() / 2], worst, s.size(),
		Vector2(v.sim.pod.vx, v.sim.pod.vy).length() * MPH, (Vector2(v.sim.pod.x, v.sim.pod.y) - p0).length() / 1000.0])
	var budget := 1044.0 / HZ
	_check("frame time: p95 %.2f ms (want <= %.1f), worst %.2f ms (want <= %.1f)" % [p95, budget, worst, 2000.0 / HZ], p95 <= budget and worst <= 2000.0 / HZ)
	_check("streaming: %d chunks built and %d dropped on the way, the slowest %.1f ms" % [W.built - built0, W.dropped, W.build_ms_max], W.built - built0 > 10 and W.dropped > 0)
	_check("no whitewash: the road under the pilot %.3f with the dust, %.3f without (%+.0f%%, want <= +8%%)" % [lum_dust, lum_clear, (lum_dust / maxf(lum_clear, 1e-6) - 1.0) * 100.0],
		lum_dust <= lum_clear * 1.08)
	_check("horizon: the whitest row of the horizon band %.0f%% near-white (want <= 30%%)" % (band_white * 100.0), band_white <= 0.30)
	var good: bool = fails == 0 and passed == 4
	print("RENDER NETWORK ", "PASS" if good else "FAIL (%d failed)" % fails)
	quit(0 if good else 1)
	return true


## The horizon band's whitest strip: across the frame's 1600 px, each 5-row strip's share of
## near-white (luminance > 0.85) pixels (a band of light, not a 1-px line), the worst of them.
func _band_white(img: Image) -> float:
	var im := img.duplicate() as Image
	im.resize(1600, 900, Image.INTERPOLATE_BILINEAR)
	var worst := 0.0
	var y := int(900 * 0.35)
	while y < int(900 * 0.60):
		var n := 0
		for x in range(0, 1600, 2):
			var l := 0.0
			for k in 5:
				l += im.get_pixel(x, y + k).get_luminance()
			if l / 5.0 > 0.85:
				n += 1
		worst = maxf(worst, n / 800.0)
		y += 5
	return worst


## Mean luminance of the lower half (the road ahead of and under the pilot).
func _lum(img: Image) -> float:
	var im := img.duplicate() as Image
	im.resize(160, 90)
	var acc := 0.0
	for y in range(45, 90):
		for x in 160:
			acc += im.get_pixel(x, y).get_luminance()
	return acc / (45.0 * 160.0)


func _check(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if ok:
		passed += 1
	else:
		fails += 1
