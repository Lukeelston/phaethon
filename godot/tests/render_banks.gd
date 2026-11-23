## The Network's banked bends from the pilot's seat (Luke, 2026-11-22: "I think most roads would benefit from
## being at least slightly banked on curves, just so that the pilot can see what's coming"): pictures before
## (CraftSim.net_banks off) and after, and how tall each bend's surface stands in them. Run windowed:
## --xr-mode off --resolution 1600x900 --fixed-fps 120 --audio-driver Dummy
## -s res://tests/render_banks.gd -- --mute --out=DIR [--only=before|after] [--no-pictures]
## The production cockpit is stood, at rest, where a craft doing 3,000 mph would be 8, 4 and 2 seconds short of
## three bends (E1's 45 km sweeper, Frostline Pass's 14 km bend, S2's 6 km one), at each one's start (0) and a
## third of the way round it (in), and a third of the way round a ring (12 km), looking ahead. For each:
##   DIR/<before|after>-<bend>-<n>s.png        the seat's own view
##   DIR/<before|after>-<bend>-<n>s-zoom.png   the same through a 12 degree lens (the bend, large enough to see)
##   a line "SIGHT ...": the bend's surface ahead of the craft (its deck, edge to edge, to where it ends or 20 km
##   on) laid onto the picture by the camera's own projection: how many of the picture's 900 rows it stands over
##   (and that in degrees), and how tall it is on average across the columns it spans (its area in the picture over
##   its width). (Laid on, not looked for in the picture: what stands in front of it, a wall's cap or the craft's
##   own engines, is not taken off.)
## And the seat's view on a ring coming up to its junction, on E1 at an exit, on E1's sweeper with the traffic
## on it, and a view from above of that sweeper with its walls.
extends "res://tests/render_terminal_art.gd"

const Sim := preload("res://sim/craft_sim.gd")
const MPH := 2.236936
const HZ := 120.0
const FAR := 3000.0 / MPH      # m: a second's flying at 3,000 mph. What of a bend lies further off than this is what the pilot reads it by
const BENDS := [["e1-45km", "E1", 1, 1, [8, 4, 2, 0, -1]], ["frost-14km", "SFrost", 5, 6, [8, 4, 2, 0, -1]], ["s2-6km", "S2", 4, 4, [8, 4, 2, 0, -1]],
	["ring-12km", "R00WN", 0, 0, [-1]]]      # [name, road, the first and the last of its segments that are the bend, the places: seconds short of it at 3,000 mph (-1: a third of the way round it)]


## Where segments `seg` to `last` of road `road_name` begin and end: [road, first sample, the sample after the last].
func _segment(_sim, road_name: String, seg: int, last := -1) -> Array:
	for r in Sim.NET_ROADS.size():
		if String(Sim.NET_ROADS[r][0]) != road_name:
			continue
		var at := 0
		var first := 0
		var segs: Array = Sim.NET_ROADS[r][5]
		for k in segs.size():
			var sg: Array = segs[k]
			var n := maxi(1, int(ceil((float(sg[1]) if sg[0] == "S" else float(sg[1]) * deg_to_rad(float(sg[2]))) / Sim.NET_STEP)))
			if k == seg:
				first = at
			if k == maxi(seg, last):
				return [r, first, at + n]
			at += n
	return []


## The roads and the land built round the craft where it stands.
func _settle() -> void:
	var sim = seat.sim
	var world = seat.network_world
	seat._ride.clear()
	for i in 6000:
		world.sync(sim.pod.x, sim.pod.y)
		seat.landscape.sync(sim.pod.x, sim.pod.y)
		if i % 40 == 0:
			await process_frame
		var roads_done: bool = world.wanted == 0 and world._job.is_empty() and world._bank_queue.is_empty() and world._bank_job.is_empty()
		if i > 400 and roads_done and seat.landscape.pending.is_empty() and seat.landscape._job.is_empty():
			break


## The craft at rest on `road` at `sample`, `right` m right of its middle, and the seat's view settled there.
func _stand(road: int, sample: int, dir: int, right: float, frames := 40) -> void:
	seat.sim.respawn_on(road, sample, dir, right)
	await _settle()
	seat.cam.position = Vector3.ZERO
	seat.cam.rotation_degrees = Vector3(-1.0, 0.0, 0.0)
	for k in frames:
		seat._process(1.0 / HZ)
		seat.cam.rotation_degrees = Vector3(-1.0, 0.0, 0.0)
		await process_frame


func _save(name: String) -> void:
	if "--no-pictures" in OS.get_cmdline_user_args():
		return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out_dir.path_join(name + ".png"))


## The bend's deck (road r, samples a to b) laid onto the picture: [the rows it stands over (px), its mean height across
## the columns it spans (px: its area over its width), px a degree at the picture's middle, and, of what lies more than
## FAR ahead, the degrees from its lowest point to its highest as the eye sees them and how far its highest is over the
## eye's own level (degrees: under 0 it is all below the horizon)].
func _sight(r: int, a: int, b: int) -> Array:
	var sim = seat.sim
	var R = sim.roads[r]
	var cam: Camera3D = seat.cam
	var size := Vector2(root.size)
	var box := Rect2()
	var any := false
	var area := 0.0
	var before := PackedVector2Array()
	var eye: Vector3 = seat.global_transform.affine_inverse() * cam.global_position      # (in the view's own frame, whose up is the world's)
	var low := INF
	var high := -INF
	for i in range(a, mini(b, a + 834) + 1):      # (20 km of it at most)
		var hw: float = R.w[i] / 2.0
		var row := PackedVector2Array()
		for c in 17:
			var across: float = lerpf(-hw, hw, float(c) / 16.0)
			var local: Vector3 = seat.wz(R.px[i] + R.nx[i] * across, R.py[i] + R.ny[i] * across,
				sim.net_height(r, float(i)) + Sim.net_edge(R.w[i], across).x + Sim.net_bank_lift(R, i, 0.0, across))
			var at: Vector3 = seat.global_transform * local
			var p := Vector2(NAN, NAN) if cam.is_position_behind(at) else cam.unproject_position(at)
			if p.x < 0.0 or p.x >= size.x or p.y < 0.0 or p.y >= size.y:
				p = Vector2(NAN, NAN)
			row.append(p)
			if not is_nan(p.x):
				box = box.expand(p) if any else Rect2(p, Vector2.ZERO)
				any = true
				var range_m := Vector2(local.x - eye.x, local.z - eye.z).length()
				if range_m > FAR:      # (how high over the level of the eye it stands, whichever way the cockpit is rolled)
					var up := rad_to_deg(atan2(local.y - eye.y, range_m))
					low = minf(low, up)
					high = maxf(high, up)
		for c in (16 if not before.is_empty() else 0):
			var q := [before[c], before[c + 1], row[c + 1], row[c]]
			if is_nan(q[0].x) or is_nan(q[1].x) or is_nan(q[2].x) or is_nan(q[3].x):
				continue
			var twice := 0.0
			for k in 4:
				twice += (q[k] as Vector2).cross(q[(k + 1) % 4] as Vector2)
			area += absf(twice) / 2.0
		before = row
	return [box.size.y, area / maxf(box.size.x, 1.0), size.y / 2.0 / tan(deg_to_rad(cam.fov) / 2.0) * PI / 180.0, maxf(0.0, high - low), high]


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
	if out_dir.is_empty() or DirAccess.make_dir_recursive_absolute(out_dir) != OK:
		push_error("Pass --out= and a writable directory.")
		quit(1)
		return
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			only = arg.trim_prefix("--only=")
	var outlook := preload("res://view/outlook.gd")
	outlook.pinned = true
	outlook.time = "afternoon"
	outlook.weather = "fair"
	preload("res://view/livery.gd").pinned = true
	preload("res://view/network_chase.gd").pinned = true
	Seat._nose_loaded = true
	root.msaa_3d = Viewport.MSAA_4X
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Seat.track_override = "network"
	Seat.job_override = "none"
	Seat.best_dir = out_dir.path_join("review_")
	for mode: String in ["before", "after"]:
		if only != "" and only != mode:
			continue
		Sim.net_banks = mode == "after"
		seat = Seat.new()
		root.add_child(seat)
		seat.set_process(false)
		seat.cruise = 0.0
		var sim = seat.sim
		var fov: float = seat.cam.fov
		# the three bends, 8, 4 and 2 seconds out at 3,000 mph
		for bend in BENDS:
			var seg := _segment(sim, String(bend[1]), int(bend[2]), int(bend[3]))
			var r: int = seg[0]
			var R = sim.roads[r]
			var mid: int = (int(seg[1]) + int(seg[2])) / 2
			for secs: int in bend[4]:
				var from: int = int(seg[1]) - roundi(3000.0 / MPH * secs / Sim.NET_STEP)
				var tag := "%ds" % secs
				if secs < 0:
					from = int(seg[1]) + (int(seg[2]) - int(seg[1])) / 3
					tag = "in"
				await _stand(r, from, 1, 0.0)
				var seen := _sight(r, maxi(int(seg[1]), from + 6), int(seg[2]))
				print("SIGHT %s %s %s (sample %d of %s; the bend %d-%d, radius %.0f m, %.0f m wide, banked %.2f degrees at its middle, %.2f where the craft stands): its surface ahead stands over %.1f rows of the picture's %d (%.3f degrees), %.2f px tall on average; the lens %.0f degrees; what is more than %.0f m off stands %.3f degrees tall whichever way the cockpit is rolled (%.1f px here, %.1f in the headset at 25 a degree), its top %+.3f degrees from the eye's level" % [
					mode, bend[0], tag, from, R.name, seg[1], seg[2], 1.0 / absf(R.kap[mid]), R.w[mid], rad_to_deg(R.bank[mid]), rad_to_deg(R.bank[from]),
					seen[0], root.size.y, float(seen[0]) / float(seen[2]), seen[1], fov, FAR, seen[3], float(seen[3]) * float(seen[2]), float(seen[3]) * 25.0, seen[4]])
				await _save("%s-%s-%s" % [mode, bend[0], tag])
				seat.cam.fov = 12.0
				for k in 3:
					await process_frame
				await _save("%s-%s-%s-zoom" % [mode, bend[0], tag])
				seat.cam.fov = fov
		# a ring coming up to its junction with the highway it climbs to; E1 at an exit; E1's sweeper with its traffic
		var ring := _segment(sim, "R00WN", 0)
		await _stand(ring[0], int(ring[2]) - 170, 1, 0.0)      # (4 km short of its end: the bank easing out, the highway's deck ahead)
		await _save("%s-junction-ring" % mode)
		await _stand(ring[0], (int(ring[1]) + int(ring[2])) / 2, 1, 0.0)
		await _save("%s-ring-middle" % mode)
		var e1 := _segment(sim, "E1", 1)
		await _stand(e1[0], 2540, 1, 100.0)
		await _save("%s-exit" % mode)
		var sweep := (int(e1[1]) + int(e1[2])) / 2
		await _stand(e1[0], sweep, 1, 60.0)
		seat.set_process(true)      # (the traffic spawns round a craft that is there a while)
		var until := Time.get_ticks_msec() + 9000
		while Time.get_ticks_msec() < until:
			await process_frame
		seat.set_process(false)
		seat.cam.position = Vector3.ZERO
		seat.cam.rotation_degrees = Vector3(-1.0, 0.0, 0.0)
		seat._process(1.0 / HZ)
		await process_frame
		await _save("%s-traffic" % mode)
		seat.cam.fov = 12.0
		for k in 3:
			await process_frame
		await _save("%s-traffic-zoom" % mode)
		seat.cam.fov = fov
		# from above: the sweeper's outside edge, its walls and what is beside it
		var R1 = sim.roads[e1[0]]
		var above := Camera3D.new()
		above.far = 60000.0
		above.fov = 50.0
		seat.add_child(above)
		# (each well clear of the land brought up beside the road, whose crest stands up to 64 m over the wall's foot)
		for view in [["above", sweep - 40, -470.0, 190.0, sweep + 25, -150.0], ["above-inside", sweep - 40, 470.0, 170.0, sweep + 25, 150.0], ["above-end", int(e1[2]) + 60, -470.0, 190.0, int(e1[2]) - 20, -150.0],
				["above-low", sweep - 12, -150.0, 60.0, sweep + 30, -200.0]]:
			var ci: int = view[1]
			var ti: int = view[4]
			above.position = seat.wz(R1.px[ci] + R1.nx[ci] * float(view[2]), R1.py[ci] + R1.ny[ci] * float(view[2]), float(view[3]))
			above.basis = Basis.looking_at(seat.wz(R1.px[ti] + R1.nx[ti] * float(view[5]), R1.py[ti] + R1.ny[ti] * float(view[5]), 4.0) - above.position, Vector3.UP)
			above.make_current()
			for k in 4:
				await process_frame
			await _save("%s-%s" % [mode, view[0]])
		seat.cam.make_current()
		seat.free()
		await process_frame
	Sim.net_banks = true
	print("RENDER BANKS DONE")
	quit()
