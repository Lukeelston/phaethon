## Every pilot craft in its paints (view/livery.gd): outside three-quarters on, the cab close, and the seat's
## view ahead (from Cockpit.EYE), one picture each: <vehicle>-<livery>-<shot>.png.
## Needs a window: --xr-mode off --fixed-fps 120 -s res://tests/render_paint.gd -- --mute --out=ABSOLUTE_DIRECTORY
##   [--vehicles=phaethon,shrike,...] [--liveries=factory,cobalt,...] [--shots=exterior,cab,seat] [--arcs]
## The binder's arcs are hidden unless --arcs: they restrike by the wall clock, and two runs are compared.
## A livery may be given as paint:name, built in `paint` and its pictures named `name` (on a build from before
## the Factory entry, --liveries=ember:factory takes the pictures Factory is compared against).
extends SceneTree

const Seat := preload("res://vr/vr_cockpit.gd")
const Livery := preload("res://view/livery.gd")
const Outlook := preload("res://view/outlook.gd")
const Pilot := preload("res://sim/pilot_craft.gd")
const BinderArc := preload("res://view/binder_arc.gd")
const DT := 1.0 / 120.0
var output := ""


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Paint screenshots need a rendering display.")
		quit(1)
		return
	var vehicles: Array = Pilot.ORDER.duplicate()
	var liveries := ["factory"]
	var shots := ["exterior", "cab", "seat"]
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			output = arg.trim_prefix("--out=")
		elif arg.begins_with("--vehicles="):
			vehicles = Array(arg.trim_prefix("--vehicles=").split(","))
		elif arg.begins_with("--liveries="):
			liveries = Array(arg.trim_prefix("--liveries=").split(","))
		elif arg.begins_with("--shots="):
			shots = Array(arg.trim_prefix("--shots=").split(","))
	if output.is_empty() or DirAccess.make_dir_recursive_absolute(output) != OK:
		push_error("Pass a writable --out directory")
		quit(1)
		return
	Livery.pinned = true
	Outlook.pinned = true
	Outlook.time = "afternoon"
	Outlook.weather = "fair"
	Seat.track_override = "range"
	Seat.job_override = "none"
	Seat._camera_loaded = true
	Seat.camera = "cockpit"
	Seat._startup_loaded = true
	Seat.cold_start = false
	Seat._nose_loaded = true
	Seat._slide_loaded = true
	Seat._map_loaded = true
	Seat._school_loaded = true
	root.msaa_3d = Viewport.MSAA_4X
	for id: String in vehicles:
		for entry: String in liveries:
			var paint := entry.get_slice(":", 0)
			var label := entry.get_slice(":", 1) if entry.contains(":") else paint
			Livery.current = paint
			Seat.vehicle_override = id
			var game := Seat.new()
			root.add_child(game)
			game.set_process(false)
			for i in 12:
				game._process(DT)
			for child in game.get_children():
				if child is CanvasLayer:
					child.hide()
			if "--arcs" not in OS.get_cmdline_user_args():
				for arc in game.find_children("*", "MeshInstance3D", true, false):
					if arc.get_script() == BinderArc:
						arc.hide()      # (its restrikes follow the wall clock: two runs would differ there and only there)
				for k in 2:      # ... and so do the binder emitters' pulse and the fin strobes' flash: held still
					game.craft.binder_mats[k].albedo_color = game.craft.BINDER_COL
					game.craft.strobes[k].visible = false
			var cab: Transform3D = game.canopy.global_transform
			var engine: Transform3D = game.craft.engines[1].global_transform
			var middle: Vector3 = (cab.origin + engine.origin - cab.basis.x * game.sim.P.engineGap * 0.5) * 0.5
			var cam := game.cam as Camera3D
			for shot: String in shots:
				match shot:
					"exterior":
						cam.global_position = middle + cab.basis * Vector3(26, 14, -19)
						cam.look_at(middle + cab.basis * Vector3(0, 0, -1.75), cab.basis.y)
						cam.fov = 33
					"cab":
						var hull: Transform3D = game.shell.get_node("PodHull").global_transform
						cam.global_position = hull * Vector3(5.5, 2.4, -6.5)
						cam.look_at(hull * Vector3(0.6, 0.15, -0.6), hull.basis.y)
						cam.fov = 40
					"seat":
						var rig: Transform3D = game.rig.global_transform
						cam.global_position = rig * Seat.EYE
						cam.look_at(cam.global_position + rig.basis * Vector3(0, -0.18, -1).normalized(), rig.basis.y)
						cam.fov = 90
				for i in 3:
					await process_frame
				await RenderingServer.frame_post_draw
				var path := output.path_join("%s-%s-%s.png" % [id, label, shot])
				if root.get_texture().get_image().save_png(path) != OK:
					push_error("Could not write " + path)
					quit(1)
					return
				print("PAINT VIEW ", path)
			game.free()
			await process_frame
	quit()
