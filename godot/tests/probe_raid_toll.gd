## Raids' toll on commuters (the stage 2 plan; task 3's ruling L): commuters lost a minute for a chosen make-up, as a raid
## runs it. The game's VR cockpit on the Network (XR off, Raids pinned on), the raid on the first ground city that is not
## the start's, put down by the director's own arrival (an alarm, its city set, a frame), the craft held still on the
## city's road --far m short of where the raid's threats are (with the gunship, its first station; else the zone's
## middle; --far=0: in the zone's middle, as task 2 measured its drones). The craft is put there and traffic left --settle
## s to fill in round it (the fleet refills after a move), and only then the raid put down, and --seconds flown: the
## commuters lost (raids.lost: every one run down or shot), the gunship's share of them (a commuter gone from traffic as a
## shot of its at it went), and its shots at commuters.
##   --pack=N     raiders (0)        --drones=N     drones (0)        --gunship=yes|no   (yes)
##   --seconds=S  flown (60)         --far=M        (5000)            --settle=S         (40)
## Headless, at the raid tests' pace: --headless --xr-mode off --fixed-fps 120 --audio-driver Dummy
##   -s res://tests/probe_raid_toll.gd -- --mute [--pack=N ...]
## Prints a "TOLL ..." line, then "TOLL DONE". A measure: it asserts nothing. Puts user://vr_prefs.json back as it found it.
extends SceneTree

const Cockpit := preload("res://vr/vr_cockpit.gd")
const Pilot := preload("res://sim/pilot_craft.gd")
const Raids := preload("res://view/network_raids.gd")
const Chase := preload("res://view/network_chase.gd")
const Livery := preload("res://view/livery.gd")
const Outlook := preload("res://view/outlook.gd")
const PREFS := "user://vr_prefs.json"
const STEP := 1.0 / 120.0


func _initialize() -> void:
	Cockpit.track_override = "network"
	Cockpit.job_override = "none"
	Cockpit.spot_override = "E3@9000"
	Cockpit.vehicle_override = Pilot.STANDARD
	Cockpit.best_dir = OS.get_user_data_dir().path_join("probe_raid_toll_")
	Cockpit.camera = "cockpit"
	Cockpit._camera_loaded = true
	Cockpit._nose_loaded = true
	Cockpit._slide_loaded = true
	Cockpit._startup_loaded = true
	Cockpit.cold_start = false
	Cockpit._map_loaded = true
	Cockpit._school_loaded = true
	Outlook.pinned = true
	Outlook.time = "afternoon"
	Outlook.weather = "fair"
	Livery.pinned = true
	Livery.current = Livery.FACTORY
	Chase.pinned = true
	Chase.enabled = false
	Raids.pinned = true
	Raids.enabled = true
	_run.call_deferred()


func _run() -> void:
	var prefs_existed := FileAccess.file_exists(PREFS)
	var prefs := FileAccess.get_file_as_bytes(PREFS) if prefs_existed else PackedByteArray()
	var pack := 0
	var drones := 0
	var gunship := true
	var seconds := 60.0
	var far := 5000.0
	var settle := 40.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--pack="):
			pack = int(arg.trim_prefix("--pack="))
		elif arg.begins_with("--drones="):
			drones = int(arg.trim_prefix("--drones="))
		elif arg.begins_with("--gunship="):
			gunship = arg.trim_prefix("--gunship=") != "no"
		elif arg.begins_with("--seconds="):
			seconds = float(arg.trim_prefix("--seconds="))
		elif arg.begins_with("--far="):
			far = float(arg.trim_prefix("--far="))
		elif arg.begins_with("--settle="):
			settle = float(arg.trim_prefix("--settle="))
	var v = Cockpit.new()
	root.add_child(v)
	await process_frame
	v.set_process(false)
	v.cruise = 0.0
	var R = v.raids
	var sim = v.sim
	var T = v.traffic_net
	T._hw_time = -1.0e9      # (no street racer drops in: it would hold traffic's floor)
	var k := -1
	for c in sim.cities.size():
		if String(sim.cities[c].get("kind", "")) != "orbit" and c != int(sim.net.from):
			k = c
			break
	var zone: Dictionary = R._zone(k)
	var road: int = zone.road
	var Rd = sim.roads[road]
	var mid := (int(zone.z.x) + int(zone.z.y)) / 2
	R.time_limit = 1.0e9
	R.away_t = 1.0e9
	R.pack_size = Vector2i(pack, pack)
	R.drones = Vector2i(drones, drones)
	R.gunship_from = 1 if gunship else 1 << 30
	R.gunship_every = 1
	# where the threats will be: the gunship's first station (a raid put down and set aside to read it), else the middle
	var at_f := float(mid)
	var way := 1
	sim.respawn_on(road, mid, 1)
	await _frame(v)
	if gunship and far > 0.0:
		R._alarm()
		R.city = k
		await _frame(v)
		if R.flyers.gunship() != null:
			at_f = R.flyers.gunship().f0
			way = R.flyers.gunship().way
		R.reset()
	var i := mid if far <= 0.0 else clampi(roundi(at_f - way * far / float(Rd.len[clampi(int(at_f), 0, Rd.N - 1)])), 2, Rd.N - 3)
	sim.respawn_on(road, i, 1)
	for n in roundi(settle / STEP):
		await _frame(v)
	R._alarm()
	R.city = k
	await _frame(v)
	var F = R.flyers
	var lost0: int = R.lost
	var made0: int = F.shots_made
	var by_shot := 0
	var at_commuters := 0
	var gap_sum := 0.0
	var gap_n := 0
	var states := {}          # s the gunship spent in each state ...
	var idle := {}            # ... and of them, off its cool with nothing it could fire on
	var glows := 0            # its muzzle's glows begun (each ends in a shot, or held)
	var glowing := false
	var made: int = made0
	for n in roundi(seconds / STEP):
		var aimed := {}           # a shot's n -> its commuter, before the frame
		for s in F.shots:
			if s.car != null:
				aimed[s.n] = s.car
		await _frame(v)
		var left := {}
		for s in F.shots:
			left[s.n] = true
			if s.n > made and s.car != null:
				at_commuters += 1
		made = F.shots_made
		for sn in aimed:
			if not left.has(sn) and not T.cars.has(aimed[sn]):
				by_shot += 1
		var g = F.gunship()
		if g != null:
			gap_sum += Vector2(g.x - sim.pod.x, g.y - sim.pod.y).length()
			gap_n += 1
			states[g.state] = float(states.get(g.state, 0.0)) + STEP
			if g.cool <= 0.0 and g.warn < 0.0:
				idle[g.state] = float(idle.get(g.state, 0.0)) + STEP
			if g.warn >= 0.0 and not glowing:
				glows += 1
			glowing = g.warn >= 0.0
	var lost: int = R.lost - lost0
	var spent := []
	for s in states:
		spent.append("%s %.0f s (%.0f of them with nothing to fire on)" % [s, states[s], float(idle.get(s, 0.0))])
	print("TOLL pack %d, drones %d, gunship %s; the craft held %s on %s (traffic settled %.0f s): %d commuters lost in %.0f s, %.1f a minute; the gunship's shots took %d of them, from %d shots at commuters (%d shots in all, from %d glows: %d held), the gunship %.1f km from the craft on average; its time: %s" % [
		pack, drones, "yes" if gunship else "no", "in the zone's middle" if far <= 0.0 else "%.1f km short of %s" % [far / 1000.0, "its first station" if gunship else "the zone's middle"],
		Rd.name, settle, lost, seconds, lost * 60.0 / seconds, by_shot, at_commuters, F.shots_made - made0, glows, glows - (F.shots_made - made0),
		gap_sum / maxf(1.0, gap_n) / 1000.0, ", ".join(spent) if not spent.is_empty() else "none"])
	R.reset()
	v.queue_free()
	await process_frame
	Raids.pinned = false
	Raids.enabled = false
	Cockpit.vehicle_override = ""
	if prefs_existed:
		var file := FileAccess.open(PREFS, FileAccess.WRITE)
		file.store_buffer(prefs)
		file.close()
	elif FileAccess.file_exists(PREFS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	print("TOLL DONE")
	quit(0)


## One frame: the craft held still, the view stepped, a frame let pass.
func _frame(v) -> void:
	for b in v.sim.bodies:
		b.vx = 0.0
		b.vy = 0.0
		b.vz = 0.0
	v.inp = {"thrL": 0.0, "thrR": 0.0, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": true, "burner": false}
	v._process(STEP)
	await process_frame
