## The raid's sounds (audio/raid_sounds.gd; the stage 2 plan, task 9) and where they play (view/raid_flyers.gd: the drones'
## whine, the gunship's drone, its shot's report; view/gunnery.gd's play_own and own_loop: the weapons'). In the VR seat on
## the Network (XR off), the Kiln (its lance's hum), Raids pinned on but for the first check. Run it twice:
##   --mute (the muted half)
##     check_off_makes_none   Raids off, the GUN never armed, 60 frames: raid_sounds.gd's cache is empty, no director and no
##                            fire control (so none of the raid's players); then the GUN armed and the lance burned 1 s
##                            (Ruling AF): still nothing made, no loop on the fire control, none of the raid's sounds on
##                            it, and the lance's stand-in (the turret's servo, higher) plays
##     check_muted            Raids on, a full raid (drones and the gunship), the GUN armed and the lance burning 2 s: no
##                            stream made (the cache still empty), no player of the flyers', no loop on the fire control,
##                            none of the raid's sounds on it; the lance's stand-in plays as it did
##   without it (the sound half; headless: the dummy audio driver, nothing heard anywhere)
##     check_off_makes_none   as above
##     check_made_at_load     Raids on: the director's build has made the flyers' three and the Kiln's hum (no other)
##                            before the first frame, in at most LOAD_MS (told); the flyers' players (the whine, the
##                            gunship's drone, two reports) and the lance's loop on the fire control, none playing
##     check_streams          each of the seven: made, 0.1 to 4 s long, a loop's points round it (a one-shot's none), its
##                            peak under -1 dBFS and no sample at full scale, the RMS of its loudest 100 ms within 6 dB of
##                            LEVELS; the time to make all seven told. And every layer of every recipe filled all it was
##                            to fill from its recording (RaidSounds.fills: none ran out of its source part way). And each
##                            stand-in played through the gun pool no louder than the jolt's thump: its source's loudest
##                            100 ms at THUMP_DB + 1.5 dBFS at the most (the whole-branch review's finding 2)
##     check_whine            a raid's drones: the whine plays, heard from no farther than the nearest drone and no nearer
##                            than that over the root of their number; destroyed one by one it plays on to the last, and
##                            stops in that very call (the fire control's damage); a frame on, still stopped
##     check_gunship          the gunship alone: its drone plays at it; a shot fired (its _shoot) is reported at the
##                            muzzle; shot down, its drone stops in that very call
##     check_raid_end         drones and the gunship up, both loops playing: the raid run out of time on the director's own
##                            frame: both stopped that frame; another set aside by reset: both stopped at once
##     check_hum              the lance armed: the hum plays the frames the beam burns and no other (every frame read):
##                            held, let go, held to overheating, cooled, held, SAFE thrown, stowed; on the mount's node
##     check_respawn          a raid on and the lance burning, the view's respawn (_respawn): the whine and the drone
##                            stopped at once; the hum the beam's own frame by frame (the trigger still held), stopped
##                            the frame it is let go
##     check_pause            the cockpit's menu (FLIGHT HOLD) open: the Master bus every raid player plays on is muted,
##                            as it mutes the engines'; the tree paused (the desktop pause): every loop playing is paused,
##                            as an engine's loop is; resumed, they play again
##     check_cost             a full raid (6 raiders, 10 drones, the gunship) and the lance burning, 600 frames: the work
##                            the sounds add a frame (the flyers' sound step and the lance's loop), mean and worst; the
##                            mean under COST_MS
##     check_weapons          the Vesper, the Shrike and the Orrery: each's own made at load and on its fire control; the
##                            Vesper's release plays the pulse's boom, the Shrike's volley of two plays one launch, an
##                            Orrery orb's strike its strike: each on a gun player at the mount's node
##     check_missing          a source missing (the arc's path pointed nowhere) and one unreadable (the fan's pointed at
##                            the turret's QOA shot): the lance's hum, the whine, the gunship's drone and the orb's strike
##                            not made (null, kept so: asked again, not tried again, so said once), no error; a Kiln flight
##                            with a raid up and the lance burning: no whine or drone player made (they had none), the
##                            gunship's report still made, the lance's stand-in plays as it did; the Vesper's boom taken
##                            away, its release plays the stand-in it replaced (the turret's impact at 0.45). Put back after
##     check_orb_window       the Orrery under the gunship: its three orbs set at it, two to strike this frame and the third
##                            the next (three strikes in two frames): one orb_strike starts, none more inside OWN_GAP of
##                            the fire control's own clock; a strike after it plays again
## Run with --fixed-fps 120. Prints RAID SOUNDS PASS. Puts user://vr_prefs.json back as it found it.
##   muted:  --headless --xr-mode off --fixed-fps 120 --audio-driver Dummy -s res://tests/test_raid_sounds.gd -- --mute
##   sound:  --headless --xr-mode off --fixed-fps 120 --audio-driver Dummy -s res://tests/test_raid_sounds.gd
extends SceneTree

const Cockpit := preload("res://vr/vr_cockpit.gd")
const Pilot := preload("res://sim/pilot_craft.gd")
const Raids := preload("res://view/network_raids.gd")
const Chase := preload("res://view/network_chase.gd")
const Livery := preload("res://view/livery.gd")
const Outlook := preload("res://view/outlook.gd")
const RaidSounds := preload("res://audio/raid_sounds.gd")
const PREFS := "user://vr_prefs.json"
const STEP := 1.0 / 120.0
const COST_MS := 0.05            # ms a frame the sounds may add, mean (the plan's 0.5 is the director, flyers and weapons together)
const LOAD_MS := 150.0           # ms the load's making may take (the flyers' three and a weapon's), at the most
const AT_LOAD := ["drone_whine", "gunship_drone", "gunship_shot", "lance_hum"]
const TURRET_DIR := "res://audio/turret/"      # the stand-ins' sources (view/gunnery.gd AUDIO_DIR)
const THUMP_DB := -15.0          # dBFS: the jolt's thump in the game's mix (audio/raid_sounds.gd LEVELS' note)
var failures := 0
var sections := 0                # (a section that dies on a script error never counts itself: the verdict then fails)
var muted := false


func _initialize() -> void:
	muted = "--mute" in OS.get_cmdline_user_args()
	Cockpit.track_override = "network"
	Cockpit.job_override = "none"
	Cockpit.spot_override = "E3@9000"
	Cockpit.best_dir = OS.get_user_data_dir().path_join("test_raid_sounds_")
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
	_run.call_deferred()


func _check(label: String, passed: bool) -> void:
	print(("PASS " if passed else "FAIL ") + label)
	failures += int(not passed)


func _run() -> void:
	var prefs_existed := FileAccess.file_exists(PREFS)
	var prefs := FileAccess.get_file_as_bytes(PREFS) if prefs_existed else PackedByteArray()
	var want := 2 if muted else 13
	await check_off_makes_none()
	Raids.pinned = true
	Raids.enabled = true
	if muted:
		await check_muted()
	else:
		var v = await _cockpit(Pilot.KILN)
		if v.raids == null or v.gunnery == null:
			_check("raids pinned on: the Kiln's seat has a director (%s) and a fire control made at load (%s)" % [v.raids, v.gunnery], false)
		else:
			check_made_at_load(v)
			check_streams()
			await check_whine(v)
			await check_gunship(v)
			await check_raid_end(v)
			await check_hum(v)
			await check_respawn(v)
			await check_pause(v)
			await check_cost(v)
		v.queue_free()
		await process_frame
		await check_weapons()
		await check_missing()
		await check_orb_window()
	_check("every section ran to its end (%d of %d)" % [sections, want], sections == want)
	Raids.pinned = false
	Raids.enabled = false
	Cockpit.vehicle_override = ""
	if prefs_existed:
		var file := FileAccess.open(PREFS, FileAccess.WRITE)
		file.store_buffer(prefs)
		file.close()
	elif FileAccess.file_exists(PREFS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	print("RAID SOUNDS %s (%s half, %d failures)" % ["PASS" if failures == 0 else "FAIL", "muted" if muted else "sound", failures])
	quit(0 if failures == 0 else 1)


# --- the stage ---------------------------------------------------------------------------------------------------

func _cockpit(id: String):
	Cockpit.vehicle_override = id
	var v = Cockpit.new()
	root.add_child(v)
	await process_frame
	v.set_process(false)
	v.cruise = 0.0
	if v.traffic_net != null:
		v.traffic_net._hw_time = -1.0e9      # (no street racer drops in: it would hold traffic's floor)
	return v


## One frame: the craft held still, the view stepped, a frame let pass.
func _frame(v) -> void:
	for b in v.sim.bodies:
		b.vx = 0.0
		b.vy = 0.0
		b.vz = 0.0
	v.inp = {"thrL": 0.0, "thrR": 0.0, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": true, "burner": false}
	v._process(STEP)
	await process_frame


func _fly(v, seconds: float) -> void:
	for i in maxi(1, roundi(seconds / STEP)):
		await _frame(v)


## The raid's city: the first ground city that is not the start's.
func _city(v) -> int:
	var sim = v.sim
	for k in sim.cities.size():
		if String(sim.cities[k].get("kind", "")) != "orbit" and k != int(sim.net.from):
			return k
	return -1


## A raid on city k with `pack` raiders, `drones` drones and the gunship or not, arrived (the director's own arrival
## puts them down) with the craft still in the middle of its town zone: the arrival's frame, and one more.
func _raid_on(v, k: int, pack: int, drones: int, gunship: bool) -> void:
	var R = v.raids
	R.reset()
	var zone: Dictionary = R._zone(k)
	v.sim.respawn_on(int(zone.road), (int(zone.z.x) + int(zone.z.y)) / 2, 1)
	R.time_limit = 1.0e9
	R.away_t = 1.0e9
	R.pack_size = Vector2i(pack, pack)
	R.drones = Vector2i(drones, drones)
	R.gunship_from = 1 if gunship else 1 << 30
	R.gunship_every = 1
	R._alarm()
	R.city = k                   # (whichever it picked: this one)
	await _frame(v)
	await _frame(v)


## The craft put down still at the drones' first group's point (its drones circle within a few hundred metres).
static func _near_group(v) -> void:
	var G = v.raids.flyers._groups[0]
	v.sim.respawn_on(int(G.road), clampi(int(G.f), 2, v.sim.roads[int(G.road)].N - 3), 1)


## Arm the GUN and fly till the mount is out (at most 2 s).
func _arm(v) -> void:
	v.gun_wanted = true
	for i in int(2.0 / STEP):
		await _frame(v)
		if v.gunnery != null and v.gunnery.mount.is_out():
			return


# --- what the sounds' players are (each null where it was not made; read so, a build without them fails, not stops) -----

static func _whine(v):
	return v.raids.flyers.get("whine")


static func _drone(v):
	return v.raids.flyers.get("hull_drone")


static func _reports(v) -> Array:
	var r = v.raids.flyers.get("reports")
	return r if r is Array else []


static func _hum(v):
	return v.gunnery.get("_own_loop") if v.gunnery != null else null


static func _on(p) -> bool:
	return p != null and p.playing


## The raid's players (the flyers'), and the fire control's own loop: those made.
static func _players(v) -> Array:
	var out := []
	for p in [_whine(v), _drone(v), _hum(v)] + _reports(v):
		if p != null:
			out.append(p)
	return out


## RaidSounds.fills (name -> [[samples filled, samples wanted], ...] a layer), read as the script's own at run time: null
## where it keeps none.
static func _fills():
	var s: Script = load("res://audio/raid_sounds.gd")
	return s.get("fills")


## The gun pool's players playing `stream`: [how many, all on the mount's node].
static func _gun_playing(g, stream) -> Array:
	var n := 0
	var on_node := true
	for p: AudioStreamPlayer3D in g._gun_audio:
		if stream != null and p.playing and p.stream == stream:
			n += 1
			on_node = on_node and p.get_parent() == g.mount.node()
	return [n, on_node]


# --- the checks ---------------------------------------------------------------------------------------------------

func check_off_makes_none() -> void:
	Raids.pinned = true
	Raids.enabled = false
	var v = await _cockpit(Pilot.KILN)
	await _fly(v, 0.5)
	var made := RaidSounds._cache.keys()
	var bare: bool = v.raids == null and v.gunnery == null
	await _arm(v)      # (Ruling AF: armed, with Raids off, the weapon's own is still not made)
	var g = v.gunnery
	var burned := 0
	var stand_in := 0
	if g != null:
		g.hold_fire = true
		for i in 120:
			await _frame(v)
			burned += int(g.mount.burning)
			for p: AudioStreamPlayer3D in g._gun_audio:
				stand_in += int(p.playing and p.stream == g._sounds.get("deploy"))
		g.hold_fire = false
	var own := []
	if g != null:
		for n: String in RaidSounds.NAMES:
			if g._sounds.has(n):
				own.append(n)
	sections += 1
	_check("Raids off, the GUN never armed, 60 frames: raid_sounds.gd's cache empty (%s), no director and no fire control (%s); then armed and the lance burned (%d of 120 frames): the cache still empty (%s), no loop on the fire control (%s), none of the raid's sounds on it (%s), the lance's stand-in playing (%d player-frames)" % [
			made, bare, burned, RaidSounds._cache.keys(), _hum(v), own, stand_in],
		made.is_empty() and bare and g != null and burned > 100 and RaidSounds._cache.is_empty() and _hum(v) == null and own.is_empty()
			and stand_in > 0)
	v.queue_free()
	await process_frame


func check_muted() -> void:
	var v = await _cockpit(Pilot.KILN)
	var k := _city(v)
	await _raid_on(v, k, 6, 10, true)
	var F = v.raids.flyers
	var up := [F.count("drone"), F.count("gunship")]
	await _arm(v)
	var g = v.gunnery
	g.hold_fire = true
	var burned := 0
	var stand_in := 0
	for i in int(2.0 / STEP):
		await _frame(v)
		burned += int(g.mount.burning)
		for p: AudioStreamPlayer3D in g._gun_audio:
			stand_in += int(p.playing and p.stream == g._sounds.get("deploy"))
	g.hold_fire = false
	var own := []
	for n: String in RaidSounds.NAMES:
		if g._sounds.has(n):
			own.append(n)
	sections += 1
	_check("--mute, a full raid up (%s drones and gunships) and the lance burning (%d frames of 240): no stream made (the cache %s), no player of the flyers' or loop on the fire control (%s), none of the raid's sounds on it (%s); the lance's stand-in played as it did (%d player-frames)" % [
			up, burned, RaidSounds._cache.keys(), _players(v), own, stand_in],
		up == [10, 1] and burned > 200 and RaidSounds._cache.is_empty() and _players(v).is_empty() and own.is_empty() and stand_in > 0)
	v.queue_free()
	await process_frame


func check_made_at_load(v) -> void:
	var made := RaidSounds._cache.keys()
	made.sort()
	var ms := 0.0
	for n in made:
		ms += float(RaidSounds.make_ms.get(n, 0.0))
	var g = v.gunnery
	var playing := 0
	for p in _players(v):
		playing += int(p.playing)
	var want := AT_LOAD.duplicate()
	want.sort()
	var hum = _hum(v)
	sections += 1
	_check("Raids on, the Kiln: the load made %s (want %s) in %.1f ms (at most %.0f), before the first frame; the flyers' players (the whine %s, the drone %s, %d reports) and the lance's loop on the fire control (%s, its hum %s), none playing (%d)" % [
			made, want, ms, LOAD_MS, _whine(v) != null, _drone(v) != null, _reports(v).size(), hum != null,
			hum != null and hum.stream == RaidSounds._cache.get("lance_hum"), playing],
		made == want and ms <= LOAD_MS and _whine(v) != null and _drone(v) != null and _reports(v).size() == 2 and hum != null
			and hum.stream == RaidSounds._cache.get("lance_hum") and g._sounds.get("lance_hum") == RaidSounds._cache.get("lance_hum")
			and playing == 0)


func check_streams() -> void:
	var report := []
	var ok := true
	var total := 0.0
	for n: String in RaidSounds.NAMES:
		var w = RaidSounds.make(n)
		total += float(RaidSounds.make_ms.get(n, 0.0))
		if not (w is AudioStreamWAV):
			report.append("%s NOT MADE" % n)
			ok = false
			continue
		var x := RaidSounds.samples(w)
		var seconds := x.size() / float(w.mix_rate)
		var peak := 0.0
		var full := 0
		for i in x.size():
			var a := absf(x[i])
			peak = maxf(peak, a)
			full += int(a * 32768.0 >= 32767.0)
		var level := linear_to_db(RaidSounds.loudest(x, w.mix_rate))
		var loops := n in RaidSounds.LOOPS
		var points: bool = w.loop_mode == AudioStreamWAV.LOOP_FORWARD and w.loop_begin == 0 and w.loop_end == x.size() if loops \
			else w.loop_mode == AudioStreamWAV.LOOP_DISABLED
		var good: bool = seconds >= 0.1 and seconds <= 4.0 and points and peak < db_to_linear(-1.0) and full == 0 \
			and absf(level - float(RaidSounds.LEVELS[n])) <= 6.0
		ok = ok and good
		report.append("%s %.2f s%s peak %.1f dBFS, loudest 100 ms %.1f (LEVELS %.1f)%s" % [n, seconds, " loop" if loops else "",
			linear_to_db(peak), level, float(RaidSounds.LEVELS[n]), "" if good else " (!)"])
	sections += 1
	_check("each of the seven made, 0.1 to 4 s, the loops' points round them, peaks under -1 dBFS, none at full scale, its level within 6 dB of LEVELS: %s; all seven made in %.1f ms" % [
		"; ".join(report), total], ok)
	# (The whole-branch review's finding 2) every stand-in played through the gun pool, which gives a sound its own level
	# to within about 1 dB, is no louder than the jolt's thump: its source's loudest 100 ms (read from the file itself:
	# the game's import is QOA) at THUMP_DB + 1.5 at the most.
	var stand_ins := []
	var quiet := true
	for n: String in RaidSounds.STAND_IN:
		var s: Array = RaidSounds.STAND_IN[n]
		if s.is_empty() or s[0] != "gun":
			continue
		var w := AudioStreamWAV.load_from_file(TURRET_DIR + String(s[1]) + ".wav", {"compress/mode": 0})
		var x := RaidSounds.samples(w)
		var level := linear_to_db(RaidSounds.loudest(x, w.mix_rate)) if not x.is_empty() else 0.0
		var good := not x.is_empty() and level <= THUMP_DB + 1.5
		quiet = quiet and good
		stand_ins.append("%s's %s at %.2f: %.1f dBFS%s" % [n, s[1], float(s[2]), level, "" if good else " (!)"])
	_check("each stand-in through the gun pool no louder than the jolt's thump (%.1f) + 1.5 dB on disk: %s" % [THUMP_DB,
		"; ".join(stand_ins)], quiet and stand_ins.size() == 3)
	var fills = _fills()      # (name -> [[samples filled, samples wanted], ...] a layer, as made)
	var short := []
	var layers := 0
	var want_layers := 0
	for n: String in RaidSounds.NAMES:
		want_layers += (RaidSounds._recipe(n).layers as Array).size()
	if fills is Dictionary:
		for n: String in RaidSounds.NAMES:
			var each: Array = fills.get(n, [])
			if each.size() != (RaidSounds._recipe(n).layers as Array).size():
				short.append("%s: %d of %d layers told" % [n, each.size(), (RaidSounds._recipe(n).layers as Array).size()])
			for k in each.size():
				layers += 1
				if int(each[k][0]) != int(each[k][1]):
					short.append("%s layer %d: %d of %d samples" % [n, k + 1, int(each[k][0]), int(each[k][1])])
	_check("every layer of every recipe filled all it was to fill from its recording (%d of %d layers told; short: %s)" % [layers, want_layers,
			short if fills is Dictionary else "NO FILLS KEPT"],
		fills is Dictionary and short.is_empty() and layers == want_layers)


func check_whine(v) -> void:
	var R = v.raids
	var F = R.flyers
	var k := _city(v)
	await _raid_on(v, k, 4, 8, false)
	var n: int = F.count("drone")
	var eye: Vector3 = root.get_viewport().get_camera_3d().global_position
	var nearest := INF
	var drones := []
	for f in F.all():
		if f.kind == "drone":
			drones.append(f)
			nearest = minf(nearest, Vector3(f.x - v.org_x, f.z, -(f.y - v.org_y)).distance_to(eye))
	var w = _whine(v)
	var heard_at: float = w.global_position.distance_to(eye) if w != null else -1.0
	var started := _on(w)
	var on_till_last := true
	for i in drones.size() - 1:
		F.hit(drones[i], 99)
		on_till_last = on_till_last and _on(w)
	var last = drones.back()
	var killed: bool = v.gunnery.damage(last, last.hp, Vector3(last.x, last.y, last.z))
	var stopped_at_once := not _on(w)
	await _frame(v)
	sections += 1
	_check("%d drones up: the whine playing (%s), heard %.0f m off (the nearest drone %.0f m; no nearer than %.0f); destroyed one by one it played on to the last (%s); the last shot down (%s): stopped in that very call (%s), a frame on still (%s)" % [
			n, started, heard_at, nearest, nearest / sqrt(maxf(n, 1)), on_till_last, killed, stopped_at_once, not _on(w)],
		n == 8 and started and heard_at <= nearest * 1.001 and heard_at >= nearest / sqrt(float(n)) * 0.999 and on_till_last and killed
			and stopped_at_once and w != null and not _on(w))
	R.reset()


func check_gunship(v) -> void:
	var R = v.raids
	var F = R.flyers
	var k := _city(v)
	await _raid_on(v, k, 4, 0, true)
	var gs = F.gunship()
	var d = _drone(v)
	var playing := _on(d)
	var at_it: float = d.global_position.distance_to(F.ship.global_position) if d != null else INF
	var whine := _on(_whine(v))
	F._shoot(gs)      # (a shot of the test's own, laid where its gun was laid)
	var reported := false
	var at_muzzle := INF
	for p: AudioStreamPlayer3D in _reports(v):
		if p.playing:
			reported = true
			at_muzzle = minf(at_muzzle, p.global_position.distance_to(F._muzzle.global_position))
	var killed: bool = v.gunnery.damage(gs, gs.hp, Vector3(gs.x, gs.y, gs.z))
	var stopped := not _on(d)
	await _frame(v)
	sections += 1
	_check("the gunship up: its drone playing (%s) at it (%.2f m), no whine with no drones (%s); a shot fired: reported (%s) at the muzzle (%.2f m); shot down (%s): its drone stopped in that very call (%s), a frame on still (%s)" % [
			playing, at_it, whine, reported, at_muzzle, killed, stopped, not _on(d)],
		playing and at_it < 0.01 and not whine and reported and at_muzzle < 0.01 and killed and stopped and d != null and not _on(d))
	R.reset()


func check_raid_end(v) -> void:
	var R = v.raids
	var k := _city(v)
	await _raid_on(v, k, 4, 6, true)
	var both := _on(_whine(v)) and _on(_drone(v))
	R.time_limit = R._t + 3.5 * STEP      # (it runs out on the director's own frame, a few on)
	var frames := 0
	var same_frame := false
	while R.state == "on" and frames < 20:
		await _frame(v)
		frames += 1
		same_frame = R.state != "on" and _whine(v) != null and not _on(_whine(v)) and not _on(_drone(v))
	var ended: String = "%s (%s)" % [R.result, R._why]
	await _raid_on(v, k, 4, 6, true)
	var again := _on(_whine(v)) and _on(_drone(v))
	R.reset()
	var reset_at_once := not _on(_whine(v)) and not _on(_drone(v))
	await _frame(v)
	sections += 1
	_check("drones and the gunship up, both loops playing (%s); the raid run out of time (%s, %d frames on): both stopped that frame (%s); another up (%s), set aside by reset: both stopped at once (%s), a frame on still (%s)" % [
			both, ended, frames, same_frame, again, reset_at_once, not _on(_whine(v)) and not _on(_drone(v))],
		both and ended.begins_with("lost") and same_frame and again and reset_at_once and not _on(_whine(v)) and not _on(_drone(v)))


func check_hum(v) -> void:
	var g0 = v.gunnery
	await _arm(v)
	var g = v.gunnery
	var m = g.mount
	var hum = _hum(v)
	var on_node: bool = hum != null and hum.get_parent() == m.node()
	var wrong := 0          # frames the hum's playing was not the beam's burning
	var steps := []
	g.hold_fire = true
	for i in 30:
		await _frame(v)
		wrong += int(_on(hum) != m.burning)
	steps.append(["held: burning and humming", m.burning and _on(hum)])
	g.hold_fire = false
	await _frame(v)
	steps.append(["let go: stopped that frame", not m.burning and not _on(hum)])
	g.hold_fire = true
	var hot_frame := -1
	for i in int(3.0 / STEP):
		await _frame(v)
		wrong += int(_on(hum) != m.burning)
		if m.hot > 0.0 and hot_frame < 0:
			hot_frame = i
		if hot_frame >= 0 and i == hot_frame + 1:
			steps.append(["overheated: stopped the frame the beam was off", not m.burning and not _on(hum)])
	g.hold_fire = false
	for i in int(3.5 / STEP):      # (cooled)
		await _frame(v)
		wrong += int(_on(hum) != m.burning)
	g.hold_fire = true
	for i in 12:
		await _frame(v)
		wrong += int(_on(hum) != m.burning)
	steps.append(["cooled and held again: humming", m.burning and _on(hum)])
	v.gun_wanted = false      # (SAFE, the trigger still held)
	await _frame(v)
	steps.append(["SAFE: stopped that frame", not m.burning and not _on(hum)])
	for i in int(1.5 / STEP):      # (stowing, the trigger still held)
		await _frame(v)
		wrong += int(_on(hum) != m.burning)
	steps.append(["stowed: still quiet", m.deploy_t() == 0.0 and not _on(hum)])
	g.hold_fire = false
	var told := []
	var all_ok := true
	for s: Array in steps:
		told.append("%s %s" % [s[0], "yes" if s[1] else "NO"])
		all_ok = all_ok and bool(s[1])
	sections += 1
	_check("the lance (its fire control the load's: %s): the hum on the mount's node (%s); %s; frames the hum was not the beam's: %d" % [
			g == g0, on_node, "; ".join(told), wrong],
		g == g0 and on_node and hot_frame >= 0 and steps.size() == 6 and wrong == 0 and all_ok)


func check_respawn(v) -> void:
	var R = v.raids
	var k := _city(v)
	await _raid_on(v, k, 4, 6, true)
	await _arm(v)
	var g = v.gunnery
	var hum = _hum(v)
	g.hold_fire = true
	await _frame(v)
	await _frame(v)
	var before := _on(_whine(v)) and _on(_drone(v)) and _on(hum)
	v._respawn()
	var flyers_stopped := not _on(_whine(v)) and not _on(_drone(v))
	var wrong := 0
	var burned := 0
	for i in 20:
		await _frame(v)
		wrong += int(_on(hum) != g.mount.burning)
		burned += int(g.mount.burning)
	g.hold_fire = false
	await _frame(v)
	var let_go: bool = not g.mount.burning and not _on(hum)
	await _frame(v)
	sections += 1
	_check("a raid on and the lance burning, every loop playing (%s); the view's respawn (the raid now \"%s\"): the whine and the drone stopped at once (%s); the hum the beam's own 20 frames on (%d wrong; the beam burned %d of them, the trigger still held); let go: stopped that frame (%s)" % [
			before, R.state, flyers_stopped, wrong, burned, let_go],
		before and flyers_stopped and wrong == 0 and let_go and not _on(_whine(v)) and not _on(_drone(v)))


func check_pause(v) -> void:
	var R = v.raids
	var k := _city(v)
	await _raid_on(v, k, 4, 6, true)
	var g = v.gunnery
	g.hold_fire = true
	await _frame(v)
	var loops: Array = [_whine(v), _drone(v), _hum(v)]
	var all_on := loops.all(func(p) -> bool: return _on(p))
	var buses := []
	for p in _players(v):
		if not buses.has(String(p.bus)):
			buses.append(String(p.bus))
	var was_muted := AudioServer.is_bus_mute(0)
	v.menu_open(true)
	await _frame(v)
	var menu_muted := AudioServer.is_bus_mute(0)
	v.menu_open(false)
	var unmuted := not AudioServer.is_bus_mute(0)
	var engine_loop: AudioStreamPlayer = null
	if v.engine_audio != null:
		for p in v.engine_audio.find_children("*", "AudioStreamPlayer", true, false):
			if (p as AudioStreamPlayer).playing:
				engine_loop = p
				break
	paused = true      # (the desktop pause: release/pause_overlay.gd set_paused, which mutes the Master bus as well)
	await process_frame
	await process_frame
	var held := all_on and loops.all(func(p) -> bool: return p.stream_paused)
	var engine_held: bool = engine_loop != null and engine_loop.stream_paused
	paused = false
	await process_frame
	var resumed := all_on and loops.all(func(p) -> bool: return not p.stream_paused and p.playing)
	g.hold_fire = false
	await _frame(v)
	R.reset()
	sections += 1
	_check("every loop playing (%s), on the bus %s; the cockpit's menu open: the Master bus muted (%s, as it mutes the engines'), closed: not (%s); the tree paused: every loop paused (%s), as an engine's loop is (%s); resumed: playing again (%s)" % [
			all_on, buses, menu_muted, unmuted, held, engine_held, resumed],
		all_on and buses == ["Master"] and not was_muted and menu_muted and unmuted and held and engine_held and resumed)


func check_cost(v) -> void:
	var R = v.raids
	var F = R.flyers
	var k := _city(v)
	await _raid_on(v, k, 6, 10, true)
	var g = v.gunnery
	g.hold_fire = true
	var up := [R.pack.size(), F.count("drone"), F.count("gunship")]
	var sum := 0.0
	var worst := 0.0
	var burned := 0
	var can: bool = F.has_method("_sounds_step") and g.has_method("own_loop")
	for i in 600:
		if g.mount.hot > 0.0 or g.mount.fire_s > 2.0:      # (kept burning: no cooling in the count)
			g.mount.hot = 0.0
			g.mount.fire_s = 0.0
		await _frame(v)
		burned += int(g.mount.burning)
		if not can:
			continue
		var t0 := Time.get_ticks_usec()
		F._sounds_step()
		g.own_loop("lance_hum", g.mount.burning)
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		sum += ms
		worst = maxf(worst, ms)
	g.hold_fire = false
	await _frame(v)
	R.reset()
	sections += 1
	_check("a full raid (%s raiders, drones, gunships) and the lance burning (%d of 600 frames): the sounds' own work a frame (the flyers' sound step and the lance's loop; there: %s) %.4f ms mean (under %.2f), %.4f ms worst" % [
			up, burned, can, sum / 600.0, COST_MS, worst],
		up == [6, 10, 1] and burned > 590 and can and sum / 600.0 < COST_MS)


func check_weapons() -> void:
	var report := []
	var ok := true
	# the Vesper: a release
	var v = await _cockpit(Pilot.VESPER)
	var g = v.gunnery
	var boom = RaidSounds._cache.get("pulse_boom")
	var on_g: bool = g != null and boom != null and g._sounds.get("pulse_boom") == boom
	await _arm(v)
	g.hold_fire = true
	await _frame(v)
	g.hold_fire = false
	var heard: Array = _gun_playing(g, boom)
	report.append("the Vesper's boom on its fire control %s, a release plays it on %d gun player(s) at the mount %s" % [on_g, heard[0], heard[1]])
	ok = ok and on_g and heard[0] == 1 and heard[1]
	v.queue_free()
	await process_frame
	# the Shrike: a volley of two
	v = await _cockpit(Pilot.SHRIKE)
	g = v.gunnery
	var launch = RaidSounds._cache.get("missile_launch")
	on_g = g != null and launch != null and g._sounds.get("missile_launch") == launch
	var k := _city(v)
	await _raid_on(v, k, 0, 4, false)
	_near_group(v)
	await _arm(v)
	var two := []
	for f in v.raids.flyers.all():
		if two.size() < 2 and not g.mount._beyond(f, v.sim.pod):      # (within the rack's reach)
			two.append(f)
	g.mount.locks = two.duplicate()
	g.hold_fire = true
	await _frame(v)
	g.hold_fire = false
	heard = _gun_playing(g, launch)
	report.append("the Shrike's launch on its fire control %s, a volley of %d plays it on %d gun player(s) at the mount %s" % [on_g, g.mount.missiles.size(), heard[0], heard[1]])
	ok = ok and on_g and g.mount.missiles.size() == 2 and heard[0] == 1 and heard[1]
	v.raids.reset()
	v.queue_free()
	await process_frame
	# the Orrery: an orb's strike on its own
	v = await _cockpit(Pilot.ORRERY)
	g = v.gunnery
	var strike = RaidSounds._cache.get("orb_strike")
	on_g = g != null and strike != null and g._sounds.get("orb_strike") == strike
	k = _city(v)
	await _raid_on(v, k, 0, 2, false)
	_near_group(v)      # (its drones within an orb's reach on its own)
	await _arm(v)
	var most := 0
	var on_node := true
	var struck := 0
	for i in int(4.0 / STEP):
		await _frame(v)
		heard = _gun_playing(g, strike)
		most = maxi(most, heard[0])
		on_node = on_node and heard[1]
		struck = g.mount.strikes
		if struck > 0 and most > 0:
			break
	report.append("the Orrery's strike on its fire control %s, %d strike(s) played it on up to %d gun player(s) at the mount %s" % [on_g, struck, most, on_node])
	ok = ok and on_g and struck > 0 and most >= 1 and on_node
	v.raids.reset()
	v.queue_free()
	await process_frame
	sections += 1
	_check("each weapon's own, made at load and played at its mount: %s" % "; ".join(report), ok)


func check_orb_window() -> void:
	var v = await _cockpit(Pilot.ORRERY)
	var k := _city(v)
	await _raid_on(v, k, 0, 0, true)
	var F = v.raids.flyers
	var gs = F.gunship()
	if gs != null:      # (1.5 km down the road from it: inside a send's reach, 2.2 km, beyond an orb's own, 900 m, so none goes on its own)
		var Rd = v.sim.roads[int(gs.road)]
		var f: float = gs.f + 1500.0 / float(Rd.len[clampi(int(gs.f), 0, Rd.N - 1)])
		v.sim.respawn_on(int(gs.road), clampi(int(f), 2, Rd.N - 3), 1)
	await _arm(v)
	await _fly(v, 0.5)      # (the orbs up out of their cradles into orbit)
	var g = v.gunnery
	var m = g.mount
	var strike = RaidSounds._cache.get("orb_strike")
	var gap = g.get_script().get("OWN_GAP")
	var starts := []        # orb_strike's starts, a frame
	var struck := []        # strikes landed, a frame
	var was: int = m.strikes
	if gs != null and m.orbs.size() == 3:
		var at := Vector3(gs.x, gs.y, gs.z)
		for o in m.orbs:      # (all three at it: two there now, the third 18 m off, a frame behind them)
			o.state = "out"
			o.target = gs
			o.v = Vector3.ZERO
			o.flown = 0.0
		m.orbs[0].p = at
		m.orbs[1].p = at + Vector3(0.0, 0.0, 1.0)
		m.orbs[2].p = at + Vector3(18.0, 0.0, 0.0)
		for i in 2:
			for p: AudioStreamPlayer3D in g._gun_audio:
				p.stop()
			await _frame(v)
			starts.append(_gun_playing(g, strike)[0])
			struck.append(m.strikes - was)
			was = m.strikes
		for i in 8:      # (past the gap: 67 ms of the fire control's frames)
			for p: AudioStreamPlayer3D in g._gun_audio:
				p.stop()
			await _frame(v)
		var o = m.orbs[0]
		o.state = "out"
		o.target = gs
		o.v = Vector3.ZERO
		o.p = Vector3(gs.x, gs.y, gs.z)
		for p: AudioStreamPlayer3D in g._gun_audio:
			p.stop()
		await _frame(v)
		starts.append(_gun_playing(g, strike)[0])
		struck.append(m.strikes - was)
	v.raids.reset()
	v.queue_free()
	await process_frame
	sections += 1
	_check("the Orrery's three orbs at the gunship: strikes a frame %s (three in the first two), orb_strike's starts a frame %s: one, none more inside the gap (%s s of the fire control's own clock); %d frames on, a strike plays again" % [
			struck.slice(0, 2), starts.slice(0, 2), gap, 10],
		gs != null and struck.size() == 3 and int(struck[0]) + int(struck[1]) == 3 and int(struck[0]) >= 1 and starts[0] + starts[1] == 1
			and starts[0] == 1 and int(struck[2]) == 1 and starts[2] == 1)


func check_missing() -> void:
	var sources_were: Dictionary = RaidSounds.sources.duplicate()
	var cache_was: Dictionary = RaidSounds._cache.duplicate()
	RaidSounds.sources["arc"] = "res://audio/raid_sounds_missing.wav"      # (nowhere)
	RaidSounds.sources["fan"] = "res://audio/turret/fire.wav"              # (imported QOA: not samples)
	var gone := ["lance_hum", "drone_whine", "gunship_drone", "orb_strike"]
	for n: String in gone:
		RaidSounds._cache.erase(n)
	var made := []
	for n: String in gone:
		made.append(RaidSounds.make(n))
	var kept := true      # (asked again: the null kept, not tried again)
	for n: String in gone:
		kept = kept and RaidSounds._cache.has(n) and RaidSounds._cache[n] == null and RaidSounds.make(n) == null
	var v = await _cockpit(Pilot.KILN)
	var k := _city(v)
	await _raid_on(v, k, 4, 6, true)
	var F = v.raids.flyers
	var flyers_ok: bool = _whine(v) == null and _drone(v) == null and _reports(v).size() == 2 and F.count("drone") == 6
	await _arm(v)
	var g = v.gunnery
	g.hold_fire = true
	var stand_in := 0
	for i in 120:
		await _frame(v)
		for p: AudioStreamPlayer3D in g._gun_audio:
			stand_in += int(p.playing and p.stream == g._sounds.get("deploy"))
	g.hold_fire = false
	var no_hum: bool = _hum(v) == null and not g.own_loop("lance_hum", true)
	await _frame(v)
	v.raids.reset()
	v.queue_free()
	await process_frame
	v = await _cockpit(Pilot.VESPER)
	g = v.gunnery
	g._sounds.erase("pulse_boom")      # (as if it could not be made)
	await _arm(v)
	g.hold_fire = true
	await _frame(v)
	g.hold_fire = false
	var burst: Array = _gun_playing(g, g._sounds.get("impact"))
	var pitch := 0.0
	for p: AudioStreamPlayer3D in g._gun_audio:
		if p.playing and p.stream == g._sounds.get("impact"):
			pitch = p.pitch_scale
	v.queue_free()
	await process_frame
	RaidSounds.sources = sources_were
	RaidSounds._cache = cache_was
	if _fills() is Dictionary:      # (the remade ones' fills taken out: those made with their sources are not in the cache now)
		for n: String in gone:
			(_fills() as Dictionary).erase(n)
	sections += 1
	_check("a source missing and one unreadable: %s not made (%s), kept so (%s); a Kiln flight with a raid up: no whine or drone player, two reports, six drones (%s), the lance burning with no hum of its own (%s) and its stand-in playing (%d player-frames); the Vesper's boom taken away, a release plays the turret's impact on a gun player (%d, at %.2f; the stand-in's 0.45)" % [
			gone, made, kept, flyers_ok, no_hum, stand_in, burst[0], pitch],
		made.all(func(w) -> bool: return w == null) and kept and flyers_ok and no_hum and stand_in > 0 and burst[0] == 1
			and is_equal_approx(pitch, 0.45))
