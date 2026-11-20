## Realism spike: pilot-seat views of the cockpit's own fittings in the production seat, in
## daylight just outside the Eridanus terminal. Run windowed, as render_terminal_art.gd:
## --xr-mode off --resolution 1600x900 --fixed-fps 120 --audio-driver Dummy
## -s res://tests/render_cockpit_spike.gd -- --mute --out=DIR [--classic] [--flat-panel] [--demo] [--pose=N] [--views=a,b] [--open]
## --classic renders v0.3.2's original fittings, materials and traffic for comparison;
## --flat-panel only its flat instrument panel and heads-up map. --demo feeds the instruments
## a flight at speed; --pose is the road sample to sit at (0: inside the terminal; 98: daylight).
extends "res://tests/render_terminal_art.gd"

# Name, head offset from the seated eye (m), and where the head is turned (degrees).
const VIEWS := [
	["c1-dashboard", Vector3(0.0, -0.02, -0.12), Vector3(-24, 0, 0)],
	["c2-mode-switch", Vector3(0.2, -0.1, -0.2), Vector3(-42, -40, 0)],
	["c3-lap", Vector3(0.0, 0.06, -0.12), Vector3(-80, 0, 0)],
	["c4-port-lever", Vector3(-0.12, -0.04, -0.08), Vector3(-42, 42, 0)],
	["c5-seat", Vector3(0.0, 0.1, -0.5), Vector3(-22, 180, 0)],
	["c6-cluster", Vector3(0.0, -0.06, -0.62), Vector3(-19, 0, 0)],
	["c7-cluster-port", Vector3(-0.34, -0.02, -0.72), Vector3(-17, -27, 0)],
	["c8-centre-dial", Vector3(0.02, -0.25, -0.8), Vector3(-17, 0, 0)],
	["c9-map", Vector3(0.0, 0.0, -0.05), Vector3(-15, 30, 0)],
	["c10-map-near", Vector3(-0.2, -0.05, -0.35), Vector3(-16, 36, 0)],
	# the roof: straight ahead, up at the header, out of each side, over the shoulder
	["c11-ahead", Vector3(0.0, 0.0, 0.0), Vector3(0, 0, 0)],
	["c12-header", Vector3(0.0, 0.0, 0.0), Vector3(24, 0, 0)],
	["c13-port", Vector3(0.0, 0.0, 0.0), Vector3(6, 62, 0)],
	["c14-starboard-up", Vector3(0.0, 0.0, 0.0), Vector3(30, -48, 0)],
	["c15-overhead", Vector3(0.0, 0.0, 0.0), Vector3(72, 0, 0)],
	["c16-over-shoulder", Vector3(0.0, 0.0, 0.0), Vector3(8, 132, 0)],
]
# What the instruments show for the stills: at speed on the burner, the starboard engine hurt.
const DEMO := {"mph": 3487.0, "kmh": 5611.8, "mach": 4.54, "mach_line": "MACH 4.5   MILE / 1.03 s", "progress": "GLACIER  178.3 mi   AT ERIDANUS",
	"footer": "SPEEDCRAFT   /   SQUEEZE RIGHT TO GO RIGHT  GRIPS BRAKE  L STICK UP: BURNER", "thr": [0.93, 0.81], "brk": [0.0, 0.22],
	"heat": [0.52, 0.74], "health": [1.0, 0.55], "flameout": [false, false], "battery": 0.72, "burner": true, "armed": true, "ramjet": false, "turbines": true,
	"gear": 3, "overdrive": false, "blink": true}


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
	if out_dir.is_empty() or DirAccess.make_dir_recursive_absolute(out_dir) != OK:
		push_error("Pass --out= and a writable directory.")
		quit(1)
		return
	var only := PackedStringArray()
	var pose := 98
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--views="):
			only = arg.trim_prefix("--views=").split(",")
		if arg.begins_with("--pose="):
			pose = int(arg.trim_prefix("--pose="))
	if "--open" in OS.get_cmdline_user_args():   # the open cockpit, before the roof
		preload("res://view/canopy.gd").roofed = false
	if "--flat-panel" in OS.get_cmdline_user_args():   # v0.3.2's flat instrument panel and heads-up map
		preload("res://vr/gauge_cluster.gd").enabled = false
		preload("res://vr/minimap_panel.gd").enclosure = false
	if "--classic" in OS.get_cmdline_user_args():
		preload("res://vr/cockpit_interior.gd").hd_parts = false
		preload("res://view/craft_materials.gd").hd = false
		preload("res://view/traffic_models.gd").hd = false
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
	for view in VIEWS:
		if not only.is_empty() and not only.has(view[0]):
			continue
		_set_pose(pose)
		seat.cam.position = view[1]
		seat.cam.rotation_degrees = view[2]
		for frame in 60:
			seat._process(STEP)
			if "--demo" in OS.get_cmdline_user_args():
				var state := DEMO.duplicate()
				if "--twilight" in OS.get_cmdline_user_args():
					state["backlight"] = 0.5
				if "--pistons" in OS.get_cmdline_user_args():   # under 2,000 mph: the turbines are not lit yet
					state.merge({"mph": 1452.0, "kmh": 2336.8, "mach": 1.89, "mach_line": "MACH 1.9   MILE / 2.48 s", "burner": false,
						"turbines": false}, true)
				seat.dashboard.show_state(state)
			await process_frame
		await RenderingServer.frame_post_draw
		var path := out_dir.path_join(str(view[0]) + ".png")
		if root.get_texture().get_image().save_png(path) != OK:
			push_error("Couldn't save " + path)
			quit(1)
			return
		print("COCKPIT_SHOT ", view[0])
	seat.free()
	quit()
