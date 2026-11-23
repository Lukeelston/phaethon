## A film of one of Mount Hyperion's leaps from the seat (after film_unflown.gd, whose camera, captions and world
## set-up it uses): the last 12 km of the lane, the lip, the flight, the landing and the first of the run-out.
## Run windowed:
## --xr-mode off --resolution 1280x720 --fixed-fps 60 --write-movie FILE.avi
## -s res://tests/film_hyperion_leap.gd -- --out=DIR [--leap=cliff|ramp] [--mph=10000]
## The craft is put down on the lane at the speed asked for and held to it as far as the lip, flat out as a pilot
## would be (top gear, the ramjet lit); from the lip on it is the sim's own flight, the levers still on the stop;
## two seconds after the field has it the levers are shut and the air brakes go on. FILM_BEGIN and FILM_END give
## the seconds of the film to keep, FILMT lines where the craft was twice a second and what the road builder was
## doing (its longest frame, the chunks it had waiting). A flat picture from the seat is not the headset.
extends "res://tests/film_unflown.gd"


func _run() -> void:
	var which := "cliff"
	var mph := 10000.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
		if arg.begins_with("--leap="):
			which = arg.trim_prefix("--leap=")
		if arg.begins_with("--mph="):
			mph = float(arg.trim_prefix("--mph="))
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
	root.msaa_3d = Viewport.MSAA_4X
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var layer := CanvasLayer.new()
	root.add_child(layer)
	caption = Label.new()
	caption.add_theme_font_size_override("font_size", 24)
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0, 0, 0, 0.6)
	box.set_content_margin_all(9)
	caption.add_theme_stylebox_override("normal", box)
	caption.position = Vector2(28, root.size.y - 62)
	caption.visible = false
	layer.add_child(caption)
	if await _leap(which, mph):
		print("FILM_END %.3f" % (frames * DT))
	if seat:
		seat.free()
	quit()


## One frame, flown on `inp` as given (the sim's own inputs: the levers, the burner, top gear's drag).
func _fly(inp: Dictionary) -> void:
	seat.inp = inp
	seat.startup.gears = true
	seat.startup.step(DT, [float(inp.thrL), float(inp.thrR)], 1)
	seat._apply_startup(DT)
	seat._process(DT)
	seat.approach_display._process(DT)
	_busiest = maxf(_busiest, float(seat.network_world.sync_ms))
	_waiting = maxi(_waiting, int(seat.network_world.wanted))
	if frames % 30 == 0:
		var b = seat.sim.pod
		print("FILMT %.2f s: %s sample %d, %.0f m up%s, %.0f mph; roads %.1f ms a frame at most, %d chunks waiting; the dash: %s" % [frames * DT, seat.sim.roads[b.path].name, b.hint, b.z,
			" (in the air)" if b.off_road else "", _mph(), _busiest, _waiting, seat._progress_text().replace("\n", " / ")])
		_busiest = 0.0
		_waiting = 0
	await _frame()


func _leap(which: String, mph: float) -> bool:
	var sim_script = load("res://sim/craft_sim.gd")
	var lp: Array = sim_script.NET_LEAPS[0 if which == "cliff" else 1]
	var lane_name: String = sim_script.NET_ROADS[int(lp[0])][0]
	var probe = sim_script.new({"track": "network"})
	var lane := int(lp[0])
	var from: int = int(probe.roads[lane].N) - 501
	probe = null
	if not await _begin("%s@%d" % [lane_name, from], false, false):
		return false
	var sim = seat.sim
	var R = sim.roads[lane]
	var v := mph * 0.44704
	sim.armed = true
	var flat := {"thrL": 0.87, "thrR": 0.87, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": true, "burner": true, "gearOverdrive": true, "thrMul": 1.0, "gearIndex": 4}
	await _roll(0.5)
	print("FILM_BEGIN %.3f" % (frames * DT))
	_say("The %s leap at %s mph, 12 km short of the lip: 200 m up to a lip of half a degree." % ["cliff's" if which == "cliff" else "ramp's", String.num_int64(int(mph))])
	for b in sim.bodies:
		b.vx = v * R.tx[from]
		b.vy = v * R.ty[from]
	var air := -1.0
	var caught := -1.0
	var lip := Vector2.ZERO
	var peak := 0.0
	var t := 0.0
	var said := 0
	var miles := 0.0
	while t < 40.0:
		var inp := flat.duplicate()
		if caught >= 0.0 and t - caught > 2.0:      # the run-out: levers shut, air brakes on
			inp.thrL = 0.0
			inp.thrR = 0.0
			inp.burner = false
			inp.brkL = 0.7
			inp.brkR = 0.7
		await _fly(inp)
		t += DT
		var pod = sim.pod
		if air < 0.0 and not pod.off_road and int(pod.path) == lane:      # held to the figure as far as the lip
			var k := v / maxf(1.0, Vector2(pod.vx, pod.vy).length())
			for b in sim.bodies:
				b.vx *= k
				b.vy *= k
		if air < 0.0 and pod.off_road:
			air = t
			lip = Vector2(pod.x, pod.y)
			_say("Off the lip. The landing field is under the whole flight; nothing is steered.")
		if air >= 0.0 and caught < 0.0:
			peak = maxf(peak, pod.z)
			if said == 0 and t - air > 4.5:
				said = 1
				_say("%.0f m up, %.1f miles out, %s mph and still gaining: the engines push all the way." % [pod.z, Vector2(pod.x, pod.y).distance_to(lip) / 1609.344, String.num_int64(int(_mph()))])
			if not pod.off_road:
				caught = t
				miles = Vector2(pod.x, pod.y).distance_to(lip) / 1609.344
				_say("Caught by the field after %.1f s and %.1f miles in the air (peak %.0f m), at %s mph." % [t - air, Vector2(pod.x, pod.y).distance_to(lip) / 1609.344, peak, String.num_int64(int(_mph()))])
		if caught >= 0.0 and t - caught > 2.0 and said < 2:
			said = 2
			_say("Levers shut, air brakes on: the run-out.")
		if caught >= 0.0 and t - caught > 6.0:
			break
		if sim.crash_t > 0.0:
			_say("WRECKED")
			await _roll(1.0)
			break
	print("FILM_LEAP %s at %.0f mph: in the air %.2f s to %.2f s (%.1f s), peak %.0f m, %.1f miles; ended on %s at %.0f mph%s" % [which, mph, air, caught, caught - air, peak, miles,
		sim.roads[sim.pod.path].name, _mph(), " WRECKED" if sim.crash_t > 0.0 else ""])
	return caught >= 0.0
