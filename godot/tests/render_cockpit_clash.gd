## Close-ups of the places in the cockpit where one mesh met another (Luke, after the flight of 22
## November: "The map is good but is sticking through the drift switch mesh", "the mach gauge mesh
## collides with those on the sides of it"), from the pilot's eye and from outside, in the production
## seat in daylight outside the Eridanus terminal. tests/probe_cockpit_clash.gd finds the places.
## Run windowed, as render_cockpit_spike.gd:
## --xr-mode off --resolution 1600x900 --fixed-fps 120 --audio-driver Dummy
## -s res://tests/render_cockpit_clash.gd -- --mute --out=DIR [--views=m,g2] [--pose=N] [--vehicle=shrike]
## --views keeps the views whose names begin with one of these (m: the map and the slide switch,
## g: the gauges, s: the sweep of the rest, k: the Shrike RS's own seat and levers; without it, all
## but k). --vehicle sits in another craft's cockpit.
extends "res://tests/render_terminal_art.gd"

const EYE: Vector3 = Seat.EYE
# Name; the frame its two points are in ("rig": floor origin, forward -Z; "dash", "map", "slide", "mode":
# that fitting's own); where the camera is; what it looks at; its field of view (degrees); a lamp at the
# camera (0: none); the nodes left out of the picture.
const VIEWS := [
	# the map's pod and the SLIDE / GRIP switch under its outboard corner
	["m1-seat", "rig", EYE, Vector3(-0.53, 0.50, 0.03), 34.0, 0.0, []],
	["m2-seat-near", "rig", EYE + (Vector3(-0.56, 0.45, 0.05) - EYE) * 0.55, Vector3(-0.56, 0.45, 0.05), 44.0, 0.0, []],
	["m3-lean-left", "rig", EYE + Vector3(-0.25, -0.05, -0.2), Vector3(-0.56, 0.45, 0.05), 44.0, 0.0, []],
	["m4-outboard", "rig", Vector3(-0.93, 0.56, 0.22), Vector3(-0.56, 0.45, 0.05), 40.0, 0.5, ["PodHull", "canopy"]],
	["m5-above", "rig", Vector3(-0.565, 0.86, 0.10), Vector3(-0.56, 0.45, 0.05), 40.0, 0.5, ["canopy"]],
	["m6-ahead", "rig", Vector3(-0.66, 0.50, -0.30), Vector3(-0.56, 0.45, 0.05), 44.0, 0.5, ["PodHull", "canopy", "Dashboard", "SegmentedCoaming"]],
	["m7-switch-face", "slide", Vector3(0.0, 0.02, 0.30), Vector3(0.0, 0.02, 0.0), 44.0, 0.4, []],
	["m8-strip", "map", Vector3(0.0, 0.40, 0.42), Vector3(0.0, 0.17, 0.0), 40.0, 0.4, []],
	["m9-strip-side", "rig", Vector3(-0.80, 0.74, -0.02), Vector3(-0.50, 0.69, -0.05), 44.0, 0.5, ["PodHull"]],
	# the gauge cluster: the centre tube and the one either side
	["g1-seat", "rig", EYE, Vector3(0.0, 0.40, -0.30), 40.0, 0.0, []],
	["g2-seat-near", "rig", EYE + (Vector3(0.0, 0.40, -0.30) - EYE) * 0.45, Vector3(0.0, 0.40, -0.30), 46.0, 0.0, []],
	["g3-port-joint", "dash", Vector3(-0.07, 0.10, 0.42), Vector3(-0.115, 0.03, 0.07), 26.0, 0.4, []],
	["g4-starboard-joint", "dash", Vector3(0.07, 0.10, 0.42), Vector3(0.115, 0.03, 0.07), 26.0, 0.4, []],
	["g5-into-centre-port", "dash", Vector3(0.10, 0.06, 0.34), Vector3(-0.105, 0.035, 0.075), 30.0, 0.4, []],
	["g6-into-port-dial", "dash", Vector3(-0.36, 0.06, 0.32), Vector3(-0.14, 0.025, 0.06), 30.0, 0.4, []],
	["g7-across-port", "dash", Vector3(-0.50, 0.10, 0.22), Vector3(-0.12, 0.03, 0.07), 34.0, 0.4, []],
	["g8-outer-joint-port", "dash", Vector3(-0.27, 0.08, 0.36), Vector3(-0.30, 0.015, 0.05), 26.0, 0.4, []],
	["g9-from-below", "dash", Vector3(-0.115, -0.28, 0.30), Vector3(-0.115, 0.0, 0.06), 34.0, 0.4, []],
	["g10-outer-joint-starboard", "dash", Vector3(0.27, 0.08, 0.36), Vector3(0.30, 0.015, 0.05), 26.0, 0.4, []],
	# the rest of the cockpit
	["s1-seat-ahead", "rig", EYE, EYE + Vector3(0.0, -0.25, -1.0), 70.0, 0.0, []],
	["s2-seat-port", "rig", EYE, Vector3(-0.60, 0.38, 0.35), 60.0, 0.0, []],
	["s3-seat-starboard", "rig", EYE, Vector3(0.60, 0.38, 0.35), 60.0, 0.0, []],
	["s4-seat-header", "rig", EYE, Vector3(0.0, 1.03, 0.33), 60.0, 0.0, []],
	["s5-mode-switch", "rig", EYE + (Vector3(0.585, 0.45, 0.08) - EYE) * 0.5, Vector3(0.585, 0.45, 0.08), 44.0, 0.0, []],
	["s6-mode-switch-outboard", "rig", Vector3(0.93, 0.56, 0.22), Vector3(0.585, 0.45, 0.06), 40.0, 0.5, ["PodHull", "canopy"]],
	["s7-start-pod-starboard", "rig", Vector3(0.20, 0.80, 0.52), Vector3(0.22, 1.0, 0.34), 44.0, 0.4, []],
	["s8-start-pod-port", "rig", Vector3(-0.20, 0.80, 0.52), Vector3(-0.23, 1.0, 0.34), 44.0, 0.4, []],
	["s9-dash-end-port", "rig", Vector3(-0.40, 0.55, 0.25), Vector3(-0.655, 0.25, -0.03), 40.0, 0.4, []],
	["s10-dash-end-starboard", "rig", Vector3(0.40, 0.55, 0.25), Vector3(0.655, 0.25, -0.03), 40.0, 0.4, []],
	["s11-lever-port", "rig", Vector3(-0.22, 0.62, 0.48), Vector3(-0.47, 0.32, 0.20), 44.0, 0.4, []],
	["s12-lever-starboard", "rig", Vector3(0.22, 0.62, 0.48), Vector3(0.47, 0.32, 0.20), 44.0, 0.4, []],
	["s13-seat-lap", "rig", EYE + Vector3(0.0, 0.0, -0.1), Vector3(0.0, 0.15, 0.55), 70.0, 0.0, []],
	["s14-tub-port", "rig", Vector3(-0.20, 0.60, 0.95), Vector3(-0.60, 0.26, 0.67), 50.0, 0.4, []],
	["s15-header-near", "rig", Vector3(0.0, 0.86, 0.50), Vector3(0.0, 1.04, 0.30), 60.0, 0.4, []],
	["s16-map-roof", "rig", EYE + Vector3(-0.1, -0.02, -0.25), Vector3(-0.50, 0.70, -0.07), 30.0, 0.4, []],
	["s17-arm-foot", "rig", Vector3(-0.42, 0.56, 0.18), Vector3(-0.60, 0.38, -0.03), 40.0, 0.4, []],
	["s18-mode-corner-outside", "rig", Vector3(0.86, 0.58, 0.16), Vector3(0.66, 0.485, 0.03), 30.0, 0.5, ["PodHull", "canopy"]],
	["s19-slide-corner-outside", "rig", Vector3(-0.86, 0.58, 0.20), Vector3(-0.66, 0.485, 0.08), 30.0, 0.5, ["PodHull", "canopy"]],
	["s20-port-console-nose", "rig", EYE + Vector3(-0.2, -0.05, -0.15), Vector3(-0.59, 0.40, 0.10), 34.0, 0.4, []],
	["s21-mode-corner-outside-hull-on", "rig", Vector3(0.86, 0.58, 0.16), Vector3(0.66, 0.485, 0.03), 30.0, 0.5, []],
	["s22-mode-corner-from-seat", "rig", EYE + Vector3(0.25, -0.1, -0.2), Vector3(0.645, 0.48, 0.03), 20.0, 0.4, []],
	# the Shrike RS's own fittings (--vehicle=shrike)
	["k1-lever-foot-port", "rig", Vector3(-0.22, 0.42, 0.46), Vector3(-0.46, 0.13, 0.20), 40.0, 0.5, []],
	["k2-lever-foot-starboard", "rig", Vector3(0.22, 0.42, 0.46), Vector3(0.46, 0.13, 0.20), 40.0, 0.5, []],
	["k3-lever-foot-above", "rig", Vector3(-0.46, 0.50, 0.24), Vector3(-0.46, 0.13, 0.20), 44.0, 0.5, []],
	["k4-seat-back-behind", "rig", Vector3(0.45, 1.25, 1.95), Vector3(0.0, 0.73, 1.07), 44.0, 0.6, ["canopy"]],
	["k5-seat-back-side", "rig", Vector3(1.1, 0.95, 1.25), Vector3(0.0, 0.73, 1.07), 44.0, 0.6, ["canopy"]],
	["k6-over-shoulder", "rig", EYE + Vector3(0.0, 0.05, -0.25), Vector3(0.12, 0.73, 1.10), 60.0, 0.5, []],
	["k7-seat-ahead", "rig", EYE, EYE + Vector3(0.0, -0.25, -1.0), 70.0, 0.0, []],
]
# What the instruments show for the stills: at speed on the burner (render_cockpit_spike.gd's).
const DEMO := {"mph": 3487.0, "kmh": 5611.8, "mach": 4.54, "mach_line": "MACH 4.5   MILE / 1.03 s", "progress": "GLACIER  178.3 mi   AT ERIDANUS",
	"footer": "SPEEDCRAFT   /   SQUEEZE RIGHT TO GO RIGHT  GRIPS BRAKE  L STICK UP: BURNER", "thr": [0.93, 0.81], "brk": [0.0, 0.22],
	"heat": [0.52, 0.74], "health": [1.0, 0.55], "flameout": [false, false], "battery": 0.72, "burner": true, "armed": true, "ramjet": false, "turbines": true,
	"gear": 3, "overdrive": false, "blink": true}


func _run() -> void:
	var only := PackedStringArray(["m", "g", "s"])
	var pose := 98
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--vehicle="):
			Seat.vehicle_override = arg.trim_prefix("--vehicle=")
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
		if arg.begins_with("--views="):
			only = arg.trim_prefix("--views=").split(",")
		if arg.begins_with("--pose="):
			pose = int(arg.trim_prefix("--pose="))
	if out_dir.is_empty() or DirAccess.make_dir_recursive_absolute(out_dir) != OK:
		push_error("Pass --out= and a writable directory.")
		quit(1)
		return
	var outlook := preload("res://view/outlook.gd")
	outlook.pinned = true
	outlook.time = "afternoon"
	outlook.weather = "fair"
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
	Seat.cold_start = false
	root.msaa_3d = Viewport.MSAA_4X
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Seat.track_override = "network"
	Seat.job_override = "none"
	Seat.best_dir = out_dir.path_join("review_")
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
	look.name = "clash_camera"
	look.near = 0.02
	look.far = 120000.0
	rig.add_child(look)
	var lamp := OmniLight3D.new()
	lamp.omni_range = 1.2
	lamp.shadow_enabled = false
	look.add_child(lamp)
	var frames := {"rig": null, "dash": seat.dashboard, "map": seat.minimap_panel, "slide": seat.slide_switch, "mode": seat.mode_switch}
	for view in VIEWS:
		var wanted := only.is_empty()
		for prefix in only:
			wanted = wanted or String(view[0]).begins_with(prefix)
		if not wanted:
			continue
		_set_pose(pose)
		var hidden := []
		for name in view[6]:
			for node in rig.find_children(name, "", true, false):
				if node is Node3D and (node as Node3D).visible:
					(node as Node3D).visible = false
					hidden.append(node)
		lamp.light_energy = float(view[5])
		lamp.visible = float(view[5]) > 0.0
		look.fov = float(view[4])
		look.make_current()
		for frame in 60:
			seat._process(STEP)
			seat.dashboard.show_state(DEMO)
			# (the fittings' frames move with the craft: the camera is put where they are, each frame)
			var to_rig := Transform3D.IDENTITY
			if frames[view[1]] != null:
				to_rig = rig.global_transform.affine_inverse() * (frames[view[1]] as Node3D).global_transform
			var from: Vector3 = to_rig * (view[2] as Vector3)
			var at: Vector3 = to_rig * (view[3] as Vector3)
			var up := Vector3.UP if absf((at - from).normalized().dot(Vector3.UP)) < 0.98 else Vector3.FORWARD
			look.transform = Transform3D(Basis.looking_at(at - from, up), from)
			look.make_current()
			await process_frame
		await RenderingServer.frame_post_draw
		var path := out_dir.path_join(str(view[0]) + ".png")
		if root.get_texture().get_image().save_png(path) != OK:
			push_error("Couldn't save " + path)
			quit(1)
			return
		for node in hidden:
			(node as Node3D).visible = true
		print("CLASH_SHOT ", view[0])
	seat.free()
	quit()
