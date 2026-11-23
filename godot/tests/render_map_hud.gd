## The map's HUD switch and its wider LOCAL, from the pilot's eye (Luke, 2026-11-22: "Will you please add
## a switch to the map that projects it via the hud? Also I think the 'local' switch should zoom out a
## bit"): the pod's strip with its three controls, the windscreen with the map in it (whole country and
## local, looking ahead and looking at the map), the local map as it was and as it is. The production
## seat on the Eridanus road, as tests/render_cockpit_clash.gd. Run windowed:
## --xr-mode off --resolution 1600x900 --fixed-fps 120 --audio-driver Dummy
## -s res://tests/render_map_hud.gd -- --mute --out=DIR [--time=night] [--views=a,b] [--pose=N] [--depth=M]
## [--cost [--headset]]
## --views keeps the views whose names begin with one of these (a: looking ahead, b: looking at the map,
## c: the strip, d: LOCAL before and after, e: the rest: the head moved, a page up, another scheme).
## --depth: the windscreen's map as a flat image that many metres from the eye (MapGlass.depth), to compare.
## --cost: no pictures; the view ahead timed with the switch off, up on the whole map and up on the local,
## turn about (cost.json): the GPU's time for the frame, the draw calls, the main thread's time in the cockpit's
## frame. --headset: with a Quest 3's two eyes' worth of pixels (give --resolution 2064x1104).
extends "res://tests/render_terminal_art.gd"

const MiniMap := preload("res://view/minimap.gd")
const MapGlass := preload("res://view/minimap_glass.gd")
const EYE: Vector3 = Seat.EYE
const MPH := 2.236936
# Name; what the camera does ("ahead": from the eye, a little under level; "map": from the eye at the
# windscreen's map; "strip": square on to the pod's strip; "pod": from the eye at the pod; "screen": close
# on the pod's screen); field of view (degrees); the HUD switch; the map's (true: GLOBAL); how wide LOCAL
# reaches (1.0 as it was); the speed the local map is zoomed for (mph); extras.
const VIEWS := [
	["a0-ahead-off", "ahead", 70.0, false, true, 1.5, 2000.0, {}],
	["a1-ahead-global", "ahead", 70.0, true, true, 1.5, 2000.0, {}],
	["a2-ahead-local", "ahead", 70.0, true, false, 1.5, 2000.0, {}],
	["b1-map-global", "map", 36.0, true, true, 1.5, 2000.0, {}],
	["b2-map-local", "map", 36.0, true, false, 1.5, 2000.0, {}],
	["c1-strip", "strip", 40.0, true, true, 1.5, 2000.0, {}],
	["c2-strip-from-seat", "pod", 34.0, true, true, 1.5, 2000.0, {}],
	["c3-strip-off-from-seat", "pod", 34.0, false, false, 1.5, 2000.0, {}],
	["d1-local-before-0mph", "screen", 30.0, false, false, 1.0, 0.0, {}],
	["d2-local-after-0mph", "screen", 30.0, false, false, 1.5, 0.0, {}],
	["d3-local-before-2000mph", "screen", 30.0, false, false, 1.0, 2000.0, {}],
	["d4-local-after-2000mph", "screen", 30.0, false, false, 1.5, 2000.0, {}],
	["d5-local-before-5000mph", "screen", 30.0, false, false, 1.0, 5000.0, {}],
	["d6-local-after-5000mph", "screen", 30.0, false, false, 1.5, 5000.0, {}],
	["e1-ahead-global-page", "ahead", 70.0, true, true, 1.5, 2000.0, {"page": true}],
	["e2-ahead-local-head-right", "ahead", 70.0, true, false, 1.5, 2000.0, {"head": Vector3(0.09, 0.03, -0.04)}],
	["e3-ahead-local-head-left-low", "ahead", 70.0, true, false, 1.5, 2000.0, {"head": Vector3(-0.09, -0.05, 0.0)}],
	["e4-map-local-paper", "map", 36.0, true, false, 1.5, 2000.0, {"scheme": 4}],
	["e5-map-global-amber", "map", 36.0, true, true, 1.5, 2000.0, {"scheme": 1}],
	["e6-ahead-wide", "ahead", 96.0, true, false, 1.5, 2000.0, {}],
]
const PAGE := "RIGHT EXIT  2 MI / 4.0 S\nE2 EAST > GLACIER\nKEEP RIGHT | READY"
const DEMO := {"mph": 2000.0, "kmh": 3218.7, "mach": 2.61, "mach_line": "MACH 2.6   MILE / 1.80 s", "progress": "GLACIER  178.3 mi   AT ERIDANUS",
	"footer": "SPEEDCRAFT   /   SQUEEZE RIGHT TO GO RIGHT  GRIPS BRAKE  L STICK UP: BURNER", "thr": [0.93, 0.81], "brk": [0.0, 0.0],
	"heat": [0.52, 0.6], "health": [1.0, 1.0], "flameout": [false, false], "battery": 0.72, "burner": false, "armed": true, "ramjet": false, "turbines": true,
	"gear": 3, "overdrive": false, "blink": true}


func _run() -> void:
	var only := PackedStringArray()
	var pose := 98
	var cost := false
	var outlook := preload("res://view/outlook.gd")
	outlook.pinned = true
	outlook.time = "afternoon"
	outlook.weather = "fair"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
		if arg.begins_with("--views="):
			only = arg.trim_prefix("--views=").split(",")
		if arg.begins_with("--pose="):
			pose = int(arg.trim_prefix("--pose="))
		if arg.begins_with("--time="):
			outlook.time = arg.trim_prefix("--time=")
		if arg.begins_with("--depth="):
			MapGlass.depth = float(arg.trim_prefix("--depth="))
		if arg == "--cost":
			cost = true
		if arg == "--headset":
			root.scaling_3d_scale = 2.0
	if out_dir.is_empty() or DirAccess.make_dir_recursive_absolute(out_dir) != OK:
		push_error("Pass --out= and a writable directory.")
		quit(1)
		return
	preload("res://view/livery.gd").pinned = true
	preload("res://view/network_chase.gd").pinned = true
	Seat._nose_loaded = true
	Seat._camera_loaded = true
	Seat._slide_loaded = true
	Seat._startup_loaded = true
	Seat._school_loaded = true
	Seat._map_loaded = true
	Seat.map_whole = true
	Seat.map_scheme = 0
	Seat.map_hud = false
	Seat.cold_start = false
	root.msaa_3d = Viewport.MSAA_4X
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Seat.track_override = "network"
	Seat.job_override = "none"
	Seat.best_dir = out_dir.path_join("review_")
	var prefs_before := FileAccess.get_file_as_string(Seat.PREFS) if FileAccess.file_exists(Seat.PREFS) else ""
	seat = Seat.new()
	root.add_child(seat)
	seat.set_process(false)
	seat.cruise = 0.0
	for c in seat.sim.cities:
		if c.name == "ERIDANUS":
			city = c
	if city.is_empty() or root.use_xr:
		push_error("This review requires the Eridanus Network road and a monoscopic viewport.")
		quit(1)
		return
	_set_pose(pose)
	for i in 2400:
		seat.network_world.sync(seat.sim.pod.x, seat.sim.pod.y)
		seat.landscape.sync(seat.sim.pod.x, seat.sim.pod.y)
		if i % 40 == 0:
			await process_frame
	var rig: Node3D = seat.rig
	var look := Camera3D.new()
	look.name = "map_hud_camera"
	look.near = 0.02
	look.far = 120000.0
	rig.add_child(look)
	if cost:
		await _cost(look, pose)
	else:
		for view in VIEWS:
			var wanted := only.is_empty()
			for prefix in only:
				wanted = wanted or String(view[0]).begins_with(prefix)
			if not wanted:
				continue
			var extra: Dictionary = view[7]
			Seat.map_hud = view[3]
			Seat.map_whole = view[4]
			Seat.map_scheme = int(extra.get("scheme", 0))
			seat.minimap.local_wider = float(view[5])
			look.fov = float(view[2])
			look.make_current()
			for frame in 70:
				_frame(look, pose, String(view[1]), float(view[6]), extra)
				await process_frame
			await RenderingServer.frame_post_draw
			var path := out_dir.path_join(str(view[0]) + ".png")
			if root.get_texture().get_image().save_png(path) != OK:
				push_error("Couldn't save " + path)
				quit(1)
				return
			print("MAP_HUD_SHOT %s (reach %.0f m)" % [view[0], seat.minimap.ahead * (1.0 if Seat.map_whole else seat.minimap.local_wider)])
	# the profile's own choices as they were found (nothing here saves them, but a hand might)
	if prefs_before != "":
		var out := FileAccess.open(Seat.PREFS, FileAccess.WRITE)
		out.store_string(prefs_before)
		out.close()
	Seat.map_hud = false
	Seat.map_whole = true
	Seat.map_scheme = 0
	seat.free()
	quit()


## One frame of the seat, parked at the pose, the local map zoomed as at `mph`, the camera put where `what` says.
func _frame(look: Camera3D, pose: int, what: String, mph: float, extra: Dictionary) -> float:
	_set_pose(pose)
	seat.minimap.ahead = MiniMap.target_ahead(mph / MPH)
	var begin := Time.get_ticks_usec()
	seat._process(STEP)
	var took := (Time.get_ticks_usec() - begin) / 1000.0
	seat.dashboard.show_state(DEMO)
	if extra.get("page", false) and seat.approach_display:
		seat.approach_display.set_message(PAGE)
		seat.approach_display._process(1.0)
	var rig: Node3D = seat.rig
	var to_rig := Transform3D.IDENTITY
	var from := EYE + (extra.get("head", Vector3.ZERO) as Vector3)
	var at := EYE + Vector3(0.0, -0.05, -1.0)
	match what:
		"map":
			at = from + MapGlass.sight(0.0, 0.0)
		"pod":
			at = Vector3(-0.53, 0.56, 0.0)
		"strip":
			to_rig = rig.global_transform.affine_inverse() * (seat.minimap_panel as Node3D).global_transform
			from = Vector3(-0.012, 0.40, 0.42)
			at = Vector3(-0.012, 0.17, 0.0)
		"screen":
			to_rig = rig.global_transform.affine_inverse() * (seat.minimap_panel as Node3D).global_transform
			from = Vector3(0.0, 0.0, 0.46)
			at = Vector3.ZERO
	from = to_rig * from
	at = to_rig * at
	look.transform = Transform3D(Basis.looking_at(at - from, Vector3.UP), from)
	look.make_current()
	return took


## The switch's cost: the view ahead with it off, up on the whole map, up on the local, turn about.
func _cost(look: Camera3D, pose: int) -> void:
	var vp := root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	look.fov = 96.0 if root.scaling_3d_scale > 1.0 else 70.0      # (a headset's eye sees about 96 degrees)
	var kinds := [["off-global", false, true], ["hud-global", true, true], ["off-local", false, false], ["hud-local", true, false]]
	var kept := {}
	const ROUNDS := 5
	for turn in ROUNDS + 1:
		for kind in kinds:
			Seat.map_hud = kind[1]
			Seat.map_whole = kind[2]
			var got := {"gpu": [], "cpu": [], "draws": [], "wall": []}
			var last := Time.get_ticks_usec()
			for frame in 150:
				var took := _frame(look, pose, "ahead", 2000.0, {})
				await process_frame
				var now := Time.get_ticks_usec()
				if frame >= 60:
					(got.gpu as Array).append(RenderingServer.viewport_get_measured_render_time_gpu(vp))
					(got.cpu as Array).append(took)
					(got.draws as Array).append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
					(got.wall as Array).append((now - last) / 1000.0)
				last = now
			if turn == 0:
				continue      # (the first round is thrown away: a shader new to the view is compiled in it)
			if not kept.has(kind[0]):
				kept[kind[0]] = {"gpu": [], "cpu": [], "draws": [], "wall": []}
			for key in got:
				var values: Array = got[key]
				values.sort()
				(kept[kind[0]][key] as Array).append(values[values.size() / 2])
	var result := {"viewport": str(root.size), "scale": root.scaling_3d_scale, "fov": look.fov, "rounds": ROUNDS}
	for kind in kinds:
		var line := {}
		for key in kept[kind[0]]:
			var values: Array = kept[kind[0]][key]
			values.sort()
			line[key] = snappedf(values[values.size() / 2], 0.001)
			line[key + "_rounds"] = values
		result[kind[0]] = line
	for pair in [["off-global", "hud-global"], ["off-local", "hud-local"]]:
		var off: Dictionary = result[pair[0]]
		var on: Dictionary = result[pair[1]]
		print("MAP_HUD_COST %s: gpu %.3f -> %.3f ms (%+.3f) | draw calls %.0f -> %.0f | the cockpit's frame on the main thread %.3f -> %.3f ms (%+.3f) | wall %.2f -> %.2f ms" % [
			pair[1], off.gpu, on.gpu, float(on.gpu) - float(off.gpu), off.draws, on.draws, off.cpu, on.cpu, float(on.cpu) - float(off.cpu), off.wall, on.wall])
	var output := FileAccess.open(out_dir.path_join("cost.json"), FileAccess.WRITE)
	if output:
		output.store_line(JSON.stringify(result, "\t"))
