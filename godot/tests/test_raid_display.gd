## Raids on the dash, the maps and the tactical display, and the alarm (the stage 1 plan, task 12): view/network_raids.gd
## text(), its alarm and the lost commuter's burst (view/raid_burst.gd); network_traffic.gd race_text(); craft_view.gd
## _raid_target(); view/minimap_2d.gd and vr/minimap_panel.gd dot_style(); view/tactical_display.gd pick(). Raids pinned
## on, the Network, the headset's cockpit (the Phaethon, its gun never armed):
##   text called    "RAID  <CITY>  <its distance as the dash reads it>  <n> LOST"
##   text on        "RAID  <n> RAIDERS  <m:ss left>", the raiders left as they go; "" waiting and over
##   dash           the dash's line is the raid's while one is called or on; its end flashed ("RAID LOST"); then the
##                  dash's own line again
##   target         both maps point to the raid's city while it is called or on (the map's own frame, and through the
##                  view's frame), and back to the dash's target after
##   hostile dots   both maps' dot_style(HOSTILE_MARK): the hostile red, bigger than a commuter's and the racer's; theirs
##                  as they were, in every colour scheme; the headset's map draws a raider in it. That screen takes its
##                  vertex colours as linear: its red is HOSTILE_COL in linear, which it shows as HOSTILE_COL itself, and
##                  in every scheme (AMBER's orange roads too) it stands well off the roads, the target and the traffic
##   tactical       a raider in the display's reach is picked though she is not gaining on it, or would reach it only in
##                  a minute; its line is in the hostile red whatever its seconds; a commuter beside it as before. Beside
##                  a commuter she would reach in the same second (a red as near as makes no odds) a raider is a shape
##                  of its own: brackets round it (shape 2, the shader's INSTANCE_CUSTOM.y), not a line (shape 1)
##   alarm          a muted flight makes none; with sound, a synthesised tone (no loop, 1.3 to 2.2 s) played once at
##                  each call (counted on its player)
##   burst          a commuter lost (commuter_lost) is a bright burst there for a Phaethon that never armed its gun,
##                  standing on the city road's deck, aged by the director's frame and gone within a second
##   off            raids off: no director, no alarm, no burst; the dash and the target as ever
##   build          the director makes the alarm's tone and the bursts' batch (hidden, its shader set) at build, not
##                  at their first use mid-flight
##   target pulse   while a raid is called or on, its city's diamond swells and shrinks on both maps (RAID_HZ, calm:
##                  1 to 2 a second), rimmed in the hostile red: the headset's drawn diamond over eight frames, the
##                  flat map's by the same rule (MiniMap.target_swell); after the raid and with raids off it is the
##                  plain diamond, static, as it ever was
##   never left out every line taken by commuters in her way, a raider still gets its mark (the furthest-off
##                  commuter's line gives way); three raiders among six commuters off her way do not thin them away
## --headless --xr-mode off --audio-driver Dummy -s res://tests/test_raid_display.gd -- --mute
## Prints RAID DISPLAY PASS.
extends SceneTree

const View := preload("res://view/craft_view.gd")
const Cockpit := preload("res://vr/vr_cockpit.gd")
const Raids := preload("res://view/network_raids.gd")
const Traffic := preload("res://view/network_traffic.gd")
const Tactical := preload("res://view/tactical_display.gd")
const Map2D := preload("res://view/minimap_2d.gd")
const MapPanel := preload("res://vr/minimap_panel.gd")
const Chase := preload("res://view/network_chase.gd")
const Livery := preload("res://view/livery.gd")
const Outlook := preload("res://view/outlook.gd")
const Pilot := preload("res://sim/pilot_craft.gd")
const MiniMap := preload("res://view/minimap.gd")
const MPH := 2.236936
var failures := 0
var checks := 0


func _initialize() -> void:
	View.track_override = "network"
	View.job_override = "none"
	View.spot_override = "E3@9000"       # open highway, 170 km and more from every city
	View.vehicle_override = Pilot.STANDARD
	View.best_dir = OS.get_user_data_dir().path_join("test_raid_display_")
	DirAccess.remove_absolute(View.best_dir + "network.json")
	Cockpit.camera = "cockpit"
	Cockpit._camera_loaded = true      # the pilot's saved choices stay out of this
	Cockpit._nose_loaded = true
	Cockpit._slide_loaded = true
	Cockpit._startup_loaded = true
	Cockpit._map_loaded = true
	Cockpit._school_loaded = true
	Cockpit._rush_loaded = true
	Cockpit.cold_start = false
	Cockpit.school = false
	Outlook.pinned = true
	Outlook.time = "afternoon"
	Outlook.weather = "fair"
	Livery.pinned = true
	Livery.current = "ember"
	Chase.pinned = true
	Chase.enabled = false
	Raids.pinned = true
	Raids.enabled = true
	_run.call_deferred()


func _check(label: String, passed: bool) -> void:
	checks += 1
	print(("PASS " if passed else "FAIL ") + label)
	failures += int(not passed)


## Has this script a method of this name (a static one too)?
func _has(script: Script, method: String) -> bool:
	for m in script.get_script_method_list():
		if String(m.name) == method:
			return true
	return false


func _road(sim, named: String) -> int:
	for r in sim.roads.size():
		if String(sim.roads[r].name) == named:
			return r
	return -1


## The craft stood on sample i of a road, going `dir` along it at `mph`, `left` m left of its middle that way.
func _place(v, road: int, i: int, dir: int, mph: float, left := 0.0) -> void:
	var sim = v.sim
	sim.respawn_on(road, i, dir, -left)
	var R = sim.roads[road]
	for body in sim.bodies:
		body.vx = R.tx[i] * dir * mph / MPH
		body.vy = R.ty[i] * dir * mph / MPH
	v._follow_origin()
	v._ride.clear()


func _settle(v, t, frames := 600) -> void:
	var sim = v.sim
	var speed: float = Vector2(sim.pod.vx, sim.pod.vy).length()
	for k in frames:
		t.sync(1.0 / 120.0, v._rush_flow, true)
		if t.st_s.size() >= 2 and (t.route_done or t.st_s[t.st_s.size() - 1] >= t.pod_s + Tactical.reach_at(speed)):
			return


func _car(sim, id: int, road: int, f: float, dir: int, lat: float, mph: float, hostile := false) -> Traffic.Car:
	var c := Traffic.Car.new()
	var R = sim.roads[road]
	var i := clampi(int(f), 0, int(R.N) - 1)
	c.id = id
	c.road = road
	c.f = f
	c.dir = dir
	c.lat = lat
	c.v = mph / MPH
	c.x = R.px[i] + R.nx[i] * lat
	c.y = R.py[i] + R.ny[i] * lat
	c.hx = R.tx[i] * dir
	c.hy = R.ty[i] * dir
	c.hostile = hostile
	return c


## How far apart two colours are (straight-line distance in RGB, 0 .. 1.73).
func _apart(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()


## How wide the headset map's last drawing of colour `col` is, panel units across (0 if none).
func _extent(panel, col: Color) -> float:
	var lo := INF
	var hi := -INF
	for i in panel._c.size():
		if (panel._c[i] as Color).is_equal_approx(col):
			lo = minf(lo, panel._v[i].x)
			hi = maxf(hi, panel._v[i].x)
	return hi - lo if hi >= lo else 0.0


## The headset map's last drawing: how many vertices are in `col`'s red, green and blue, whatever their strength.
func _rgb_count(panel, col: Color) -> int:
	var n := 0
	for c: Color in panel._c:
		n += int(absf(c.r - col.r) < 0.002 and absf(c.g - col.g) < 0.002 and absf(c.b - col.b) < 0.002)
	return n


func _spread(a: Array) -> float:
	return float(a.max()) - float(a.min())


## Eight frames of the map 0.1 s apart: the headset's target diamond across, its rim's vertices (in the hostile red at
## any strength), the flat map's diamond by its rule (half size, rim strength, from 9 px), and each frame's raid pulse.
func _pulse_frames(v, pnl) -> Dictionary:
	var mini: Script = MiniMap
	var out := {"sizes": [], "rims": [], "flat": [], "flat_rim": [], "raid": []}
	for k in 8:
		var f: Dictionary = v.minimap.update(v.sim.pod.th, 0.1)
		pnl.show_frame(f)
		out.sizes.append(snappedf(_extent(pnl, Color(pnl.tone("target"), 1.0)), 0.0001))
		out.rims.append(_rgb_count(pnl, MapPanel.hostile_tone()))
		var sw: Vector2 = mini.call("target_swell", 9.0, f) if _has(mini, "target_swell") else Vector2(9.0, 0.0)
		out.flat.append(snappedf(sw.x, 0.01))
		out.flat_rim.append(snappedf(sw.y, 0.01))
		out.raid.append(float((f.get("target", {}) as Dictionary).get("raid", -1.0)))
	return out


## Is a plain diamond's width on the headset's map (0.011 on the map, 0.008 on its rim: across, twice that)?
func _plain(across: float) -> bool:
	return absf(across - 0.022) < 0.0002 or absf(across - 0.016) < 0.0002


## The colours in the headset map's last drawing equal to `col`: how many vertices.
func _painted(panel, col: Color) -> int:
	var n := 0
	for c: Color in panel._c:
		n += int(c.is_equal_approx(col))
	return n


func _target(v) -> void:
	if v.has_method("_raid_target"):
		v._raid_target()


func _run() -> void:
	var prefs_before := FileAccess.get_file_as_string(Cockpit.PREFS) if FileAccess.file_exists(Cockpit.PREFS) else ""
	Tactical.wanted = false
	var v = Cockpit.new()
	root.add_child(v)
	await process_frame
	v.set_process(false)
	v.cruise = 0.0
	var sim = v.sim
	var R = v.raids
	var T = v.traffic_net
	if R == null or T == null:
		_check("raids pinned on: the cockpit has a director and traffic", false)
		await _finish(v, prefs_before)
		return
	R.tick_every = 1.0e9        # (no commuters lost off-screen while this looks: the counts are this test's)
	R.arrive_r = 0.0            # (nor an arrival but the one it makes)
	v.flash_until = 0.0

	# ---- made at build (raids on only), not at first use mid-flight ----
	var made = R.get("burst")
	var made_mat = made.material_override if made is MultiMeshInstance3D else null
	_check("made at the director's build: the alarm's tone (%s) and the bursts' batch (%s), hidden, none drawn, its shader set (%s)" % [Raids._alarm_wav, made, made_mat],
		Raids._alarm_wav is AudioStreamWAV and made is MultiMeshInstance3D and not made.visible and int(made.shown) == 0
		and made_mat is ShaderMaterial and (made_mat as ShaderMaterial).shader != null and (made_mat as ShaderMaterial).shader.code.contains("INSTANCE_CUSTOM"))

	# ---- the alarm ----
	R.reset()
	var muted_view: bool = v.muted
	var called_muted: bool = R._alarm()
	var players: int = R.find_children("*", "AudioStreamPlayer", true, false).size()
	_check("a muted flight (the runner's --mute: %s): a raid called (%s) makes no alarm (player %s, %d players under the director)" % [muted_view, called_muted, R.get("alarm"), players],
		muted_view and called_muted and R.get("alarm") == null and players == 0)
	R.reset()
	v.muted = false             # (now a flight with sound)
	R._alarm()
	var a = R.get("alarm")
	var w = a.stream if a is AudioStreamPlayer else null
	var plays_one = a.get("plays") if a != null else null
	var playing: bool = a.playing if a is AudioStreamPlayer else false
	var secs: float = w.get_length() if w is AudioStreamWAV else 0.0
	_check("with sound: the call has its alarm, a synthesised tone (%s, %.2f s, loop %s, not chase's wail), played once (%s; playing %s)" % [w, secs, w.loop_mode if w is AudioStreamWAV else -1, plays_one, playing],
		a is AudioStreamPlayer and w is AudioStreamWAV and w.loop_mode == AudioStreamWAV.LOOP_DISABLED and secs > 1.3 and secs < 2.2
		and (w as AudioStreamWAV).data.size() > 1000 and plays_one == 1 and playing and a.get_parent() == R)
	R.reset()
	R._alarm()
	var plays_two = a.get("plays") if a != null else null
	_check("the next call plays the same player again, once (%s), and makes no other" % plays_two,
		plays_two == 2 and R.get("alarm") == a and R.find_children("*", "AudioStreamPlayer", true, false).size() == 1)
	if a is AudioStreamPlayer:
		a.stop()
	v.muted = true

	# ---- called: the dash's line and the target ----
	R.reset()
	R._alarm()
	R.lost = 7
	var c: Dictionary = sim.cities[R.city]
	var d := Vector2(float(c.cx) - sim.pod.x, float(c.cy) - sim.pod.y).length()
	var want := "RAID  %s  %s  %d LOST" % [c.name, View._far(d), 7]
	_check("called: \"%s\" (want \"%s\")" % [R.text(), want], R.state == "called" and R.text() == want)
	R.lost = 8
	_check("... its losses as they go: \"%s\"" % R.text(), R.text().ends_with("  8 LOST"))
	v.flash_until = 0.0
	_check("the dash shows it: \"%s\"; traffic's race line \"%s\"" % [v._net_text(), T.race_text()], v._net_text() == R.text() and T.race_text() == R.text() and R.text() != "")
	var other: int = (R.city + 1) % sim.cities.size()
	v.net_target = other
	v.minimap.target = other
	_target(v)
	var f: Dictionary = v.minimap.update(sim.pod.th, 1.0 / 60.0)
	var named: String = String(f.target.name) if f.has("target") else ""
	_check("the maps point to the raid's city %s (target %d, want %d; the frame's target \"%s\"), not the dash's own %s" % [c.name, v.minimap.target, R.city, named, sim.cities[other].name],
		v.minimap.target == R.city and named == String(c.name) and other != R.city)
	v.minimap.target = other
	v._sync_world()      # (the view's own frame: the director's update, then the target)
	_check("... and so it is through the view's frame (target %d, want %d; still %s)" % [v.minimap.target, R.city, R.state], v.minimap.target == R.city and R.state == "called")
	# check_target_pulse: the raid's city swells on the maps while called
	var pnl = v.minimap_panel
	var whole_was: bool = v.minimap.whole
	v.minimap.whole = false
	v.minimap.marks = []
	var hz: float = float((MiniMap as Script).get_script_constant_map().get("RAID_HZ", 0.0))
	var pc := _pulse_frames(v, pnl)
	_check("called: its city swells at %.1f a second (calm: 1 to 2): the headset's diamond across %s (plain 0.016 or 0.022), rimmed in the hostile red every frame (%s vertices); the flat map's %s px, rim %s" % [hz, pc.sizes, pc.rims, pc.flat, pc.flat_rim],
		hz >= 1.0 and hz <= 2.0 and _spread(pc.sizes) > 0.003 and int(pc.rims.min()) == 6 and _spread(pc.flat) > 2.0 and float(pc.flat_rim.min()) >= 0.5 and float(pc.raid.min()) >= 0.0)

	# ---- on: the raiders left and the time ----
	R._arrive()
	R._t = 33.4
	var n: int = R.pack.size()
	var want_on := "RAID  %d RAIDERS  1:26" % n
	_check("on: \"%s\" (want \"%s\": %d raiders, 86.6 s of %.0f left)" % [R.text(), want_on, n, R.time_limit], R.state == "on" and n >= 4 and R.text() == want_on)
	v.flash_until = 0.0
	_target(v)
	_check("the dash shows it (\"%s\"), the maps still the city (%d)" % [v._net_text(), v.minimap.target], v._net_text() == want_on and v.minimap.target == R.city)
	var po := _pulse_frames(v, pnl)
	_check("on: still swelling (%s across, %s rim vertices)" % [po.sizes, po.rims], _spread(po.sizes) > 0.003 and int(po.rims.min()) == 6)
	var shot = R.pack[0]
	R.on_kill(shot)
	T.knock_out(shot)
	R.update(0.0)
	_check("a raider shot: \"%s\"" % R.text(), R.text() == "RAID  %d RAIDERS  1:26" % (n - 1))

	# ---- a commuter lost: its burst, for a Phaethon that never armed its gun ----
	# (raids on, its fire control is made at load, dormant until the GUN is first armed: view/gunnery.gd)
	var gunless: bool = String(sim.P.get("vehicle", "")) == Pilot.STANDARD and (v.gunnery == null or v.gunnery.dormant) and v.craft.weapon != null and not v.gun_wanted
	var zone: Dictionary = R._zone(R.city)
	var road: int = zone.road
	var Rd = sim.roads[road]
	var zi: int = (zone.z.x + zone.z.y) / 2
	var bx: float = Rd.px[zi]
	var by: float = Rd.py[zi]
	var deck: float = sim.net_height(road, float(zi))
	R.commuter_lost.emit(bx, by)
	var b = R.get("burst")
	var mm: MultiMesh = b.multimesh if b is MultiMeshInstance3D else null
	R.update(0.1)       # (the director's frame: the burst's own)
	var drawn: int = mm.visible_instance_count if mm else -1
	var xf: Transform3D = b.laid[0][0] if b is MultiMeshInstance3D and b.laid.size() == 1 else Transform3D()
	var at := Vector3(bx - v.org_x, deck, -(by - v.org_y))
	var side := xf.basis.x.length()
	var eye: Vector3 = v.get_viewport().get_camera_3d().global_position if v.get_viewport().get_camera_3d() else Vector3.ZERO
	var ang := side / maxf(1.0, eye.distance_to(xf.origin))
	var age: float = b.laid[0][1] if b is MultiMeshInstance3D and b.laid.size() == 1 else -1.0
	_check("the Phaethon (%s), its gun never armed (gunnery %s): a commuter lost at the city road's sample %d makes a burst (%s), drawn %d, a child of the director" % [sim.P.get("vehicle", "?"), v.gunnery, zi, b, drawn],
		gunless and b is MultiMeshInstance3D and b.get_parent() == R and b.visible and drawn == 1)
	_check("... where the commuter was (%.1f, %.1f against %.1f, %.1f), standing on the deck (its middle %.0f m over it, side %.0f m, %.2f degrees to the eye), %.0f%% through its life after 0.1 s" % [xf.origin.x, xf.origin.z, at.x, at.z, xf.origin.y - deck, side, rad_to_deg(ang), age * 100.0],
		drawn == 1 and absf(xf.origin.x - at.x) < 1.0 and absf(xf.origin.z - at.z) < 1.0 and xf.origin.y > deck and xf.origin.y - deck < side * 0.5
		and side >= 20.0 and ang > deg_to_rad(1.0) and age > 0.0 and age < 0.3)
	for k in 10:
		R.update(0.1)
	_check("... and gone within a second (drawn %d, shown %s); no gun woken by it (%s, dormant %s)" % [mm.visible_instance_count if mm else -1, b.visible if b else null, v.gunnery,
			v.gunnery.dormant if v.gunnery else null],
		mm != null and mm.visible_instance_count == 0 and not b.visible and (v.gunnery == null or v.gunnery.dormant))

	# ---- over: the flash, then the dash's own line and target ----
	R._end("lost", "time")
	_check("over: no line (\"%s\"), traffic's race line none (\"%s\")" % [R.text(), T.race_text()], R.text() == "" and T.race_text() == "" and R.state == "over")
	v._raid_result()
	_check("the end flashed on the dash: \"%s\"" % v._net_text(), v._net_text().begins_with("RAID LOST"))
	v.flash_until = 0.0
	_target(v)
	var own: String = v._net_text()
	_check("then the dash's own line (\"%s\") and the maps back to its target (%d, want %d)" % [own, v.minimap.target, other],
		not own.begins_with("RAID") and own.begins_with(String(sim.cities[other].name)) and v.minimap.target == other)
	var pa := _pulse_frames(v, pnl)
	_check("after the raid the target is the plain diamond again, static, as it ever was: across %s, rim vertices %s, the frames' pulse %s; the flat map's %s px, rim %s" % [pa.sizes, pa.rims, pa.raid, pa.flat, pa.flat_rim],
		_spread(pa.sizes) == 0.0 and _plain(float(pa.sizes[0])) and int(pa.rims.max()) == 0 and float(pa.raid.max()) == -1.0
		and float(pa.flat.min()) == 9.0 and float(pa.flat.max()) == 9.0 and float(pa.flat_rim.max()) == 0.0)
	v.minimap.whole = whole_was
	R.reset()
	_check("waiting: no line (\"%s\")" % R.text(), R.text() == "" and R.state == "")

	# ---- the maps' dots ----
	var map2d: Script = Map2D      # (held as a Script: its static functions called by name, so this parses before they exist)
	var map_panel: Script = MapPanel
	var has2 := _has(Map2D, "dot_style")
	var hasp := _has(MapPanel, "dot_style")
	if has2:
		var h2: Array = map2d.call("dot_style", Traffic.HOSTILE_MARK)
		var c2: Array = map2d.call("dot_style", Traffic.CAR)
		var r2: Array = map2d.call("dot_style", 4)
		var ordinary := true
		for k in 9:
			if k != 4:
				ordinary = ordinary and map2d.call("dot_style", k) == c2
		_check("the flat map: a raider's dot %s at %.1f px, a commuter's %s at %.1f (every kind but the racer's), the racer's %s at %.1f" % [(h2[1] as Color).to_html(), float(h2[0]), (c2[1] as Color).to_html(), float(c2[0]), (r2[1] as Color).to_html(), float(r2[0])],
			(h2[1] as Color).is_equal_approx(Traffic.HOSTILE_COL) and float(h2[0]) > float(c2[0]) and float(h2[0]) > float(r2[0]) and ordinary
			and is_equal_approx(float(c2[0]), 2.0) and (c2[1] as Color).is_equal_approx(Color(0.9, 0.9, 0.95, 0.75))
			and is_equal_approx(float(r2[0]), 4.5) and (r2[1] as Color).is_equal_approx(Color(1.0, 0.3, 0.9)))
	else:
		_check("the flat map has dot_style()", false)
	if hasp:
		var panel_ok := true
		var bad := []
		var nearest_gap := INF
		var nearest_to := ""
		for k in MapPanel.SCHEMES.size():
			var sc: Dictionary = MapPanel.SCHEMES[k]
			var hp: Array = map_panel.call("dot_style", Traffic.HOSTILE_MARK, k)
			var cp: Array = map_panel.call("dot_style", Traffic.CAR, k)
			var rp: Array = map_panel.call("dot_style", 4, k)
			var ok: bool = ((hp[1] as Color).is_equal_approx(Traffic.HOSTILE_COL.srgb_to_linear()) and float(hp[0]) > float(cp[0]) and float(hp[0]) > float(rp[0])
				and is_equal_approx(float(cp[0]), 0.0028) and (cp[1] as Color).is_equal_approx(Color(sc.craft, 0.8))
				and is_equal_approx(float(rp[0]), 0.006) and (rp[1] as Color).is_equal_approx(sc.star))
			if not ok:
				bad.append(sc.name)
			panel_ok = panel_ok and ok
			# as the screen shows them (its vertex colours linear): the raider's red against the scheme's own colours
			var seen: Color = (hp[1] as Color).linear_to_srgb()
			for key in ["star", "speed", "target", "craft"]:
				var gap := _apart(seen, (sc[key] as Color).linear_to_srgb())
				if gap < nearest_gap:
					nearest_gap = gap
					nearest_to = "%s %s" % [sc.name, key]
		var h0: Array = map_panel.call("dot_style", Traffic.HOSTILE_MARK)
		var shown: Color = (h0[1] as Color).linear_to_srgb()
		_check("the headset's map, in every scheme: a raider's dot the hostile red and bigger than a commuter's and the racer's; theirs as they were (wrong in %s); dot_style(HOSTILE_MARK) %s, HOSTILE_COL in linear, which the screen shows as %s (HOSTILE_COL %s)" % [bad, h0, shown.to_html(false), Traffic.HOSTILE_COL.to_html(false)],
			panel_ok and (h0[1] as Color).is_equal_approx(Traffic.HOSTILE_COL.srgb_to_linear()) and _apart(shown, Traffic.HOSTILE_COL) < 0.01)
		_check("... and as shown it stands well off every scheme's roads, target and traffic: nearest %s, %.2f apart (over 0.45)" % [nearest_to, nearest_gap], nearest_gap > 0.45)
	else:
		_check("the headset's map has dot_style()", false)
	var P = v.minimap_panel
	var was_whole: bool = v.minimap.whole
	v.minimap.whole = false
	var fwd := Vector2(cos(sim.pod.th), sin(sim.pod.th))
	var left_of := Vector2(-fwd.y, fwd.x)
	var p1 := Vector2(sim.pod.x, sim.pod.y) + fwd * 600.0
	var p2 := p1 + left_of * 300.0
	v.minimap.marks = [[p1.x, p1.y, Traffic.HOSTILE_MARK], [p2.x, p2.y, Traffic.CAR]]
	P.show_frame(v.minimap.update(sim.pod.th, 1.0 / 60.0))
	var red: int = _painted(P, Traffic.HOSTILE_COL.srgb_to_linear())
	var grey: int = _painted(P, Color(P.tone("craft"), 0.8))
	_check("the headset's map draws a raider 600 m ahead in the hostile red (%d vertices) and a commuter beside it as ever (%d)" % [red, grey], red == 3 and grey == 3)
	v.minimap.marks = []
	v.minimap.whole = was_whole

	# ---- the tactical display ----
	var e1 := _road(sim, "E1")
	_place(v, e1, 4000, 1, 5000.0, 22.5)
	Tactical.wanted = true
	var t = Tactical.frame(v, null, 1.0 / 120.0, v._rush_flow, true)
	_settle(v, t)
	var speed := 5000.0 / MPH
	var here: float = sim._road_f(sim.pod)
	var even := _car(sim, 901, e1, here + 6000.0 / 24.0, 1, 22.5, 5000.0, true)          # 6 km on at her speed: not gaining
	var slow_far := _car(sim, 902, e1, here + 20000.0 / 24.0, 1, -67.5, 4400.0, true)    # 20 km on, gained on at 600 mph: 75 s
	var close := _car(sim, 903, e1, here + 1500.0 / 24.0, 1, 22.5, 2500.0, true)         # 1.5 km on, closing at 2,500 mph: 1.3 s
	var beyond := _car(sim, 904, e1, here + 30000.0 / 24.0, 1, 22.5, 2500.0, true)       # past the display's reach
	var behind := _car(sim, 905, e1, here - 40.0, 1, 22.5, 2500.0, true)
	var commuter_even := _car(sim, 906, e1, here + 6000.0 / 24.0, 1, -22.5, 5000.0)
	var commuter := _car(sim, 907, e1, here + 4000.0 / 24.0, 1, -22.5, 2500.0)
	var got: Array = t.pick([even, slow_far, close, beyond, behind, commuter_even, commuter], speed)
	var ids := []
	for g in got:
		ids.append(int(g.car.id))
	ids.sort()
	_check("the display picks the raiders in its reach (%.1f km at 5,000 mph), gaining or not, near or a minute off: %s (want 901 902 903 and the commuter 907; not one past its reach, behind her, or a commuter she is not gaining on)" % [Tactical.reach_at(speed) / 1000.0, ids],
		ids == [901, 902, 903, 907])
	T.cars.clear()
	T.cars.append_array([even, slow_far, close, commuter])
	for k in 80:
		t.sync(1.0 / 120.0, v._rush_flow, true)
	var tints := {}
	for id in [901, 902, 903, 907]:
		tints[id] = t.marks[id].tint if t.marks.has(id) else null
	var reds := 0
	for k in t.line_count:
		reds += int(t.line_tints[k].is_equal_approx(Color(Traffic.HOSTILE_COL, 1.0)))
	var soon: Color = Tactical.soon_tint(float(t.marks[907].seconds)) if t.marks.has(907) else Color.BLACK
	_check("their lines: the three raiders' in the hostile red, full height and strength, whatever their seconds (%d of %d drawn so); the commuter's by its seconds as ever (%s against %s)" % [reds, t.line_count, tints.get(907), soon],
		t.line_count == 4 and reds == 3 and tints[901] != null and (tints[901] as Color).is_equal_approx(Traffic.HOSTILE_COL) and (tints[903] as Color).is_equal_approx(Traffic.HOSTILE_COL)
		and (tints[902] as Color).is_equal_approx(Traffic.HOSTILE_COL) and t.marks[903].way and t.marks[902].way and tints[907] != null and (tints[907] as Color).is_equal_approx(soon))
	# a raider and a commuter she would reach in the same second: both red, so the raider's is a shape of its own
	T.cars.clear()
	for k in 80:
		t.sync(1.0 / 120.0, v._rush_flow, true)
	var at_1s := 2500.0 / MPH * 1.0      # m: closing at 2,500 mph, one second off
	var raider_1s := _car(sim, 911, e1, here + at_1s / 24.0, 1, 22.5, 2500.0, true)
	var commuter_1s := _car(sim, 912, e1, here + at_1s / 24.0, 1, -22.5, 2500.0)
	T.cars.append_array([raider_1s, commuter_1s])
	for k in 80:
		t.sync(1.0 / 120.0, v._rush_flow, true)
	var shape := {}
	var tint := {}
	var kk := 0
	for m in t.marks.values():      # (the lines are laid in the marks' order; all eased in by now)
		shape[m.id] = t.line_shape[kk]
		tint[m.id] = t.line_tints[kk]
		kk += 1
	var both := shape.has(911) and shape.has(912)
	var secs_1s: Array = [t.marks[911].seconds if t.marks.has(911) else -1.0, t.marks[912].seconds if t.marks.has(912) else -1.0]
	var red_gap: float = _apart(tint[911], tint[912]) if both else -1.0
	var code: String = RegEx.create_from_string("//[^\\n]*").sub(t.line_mat.shader.code, "", true)      # (its code, not its comments)
	_check("a raider and a commuter in her way, each %.2f s / %.2f s off: both red (%.2f apart, the commuter's %s), but the raider's mark is brackets (shape %s) and the commuter's a line (shape %s); the shader lays out a raider's by its INSTANCE_CUSTOM.y, %s m / %s px" % [secs_1s[0], secs_1s[1], red_gap,
			(tint.get(912, Color.BLACK) as Color).to_html(false), shape.get(911, -1), shape.get(912, -1), t.line_mat.get_shader_parameter("box").x, t.line_mat.get_shader_parameter("box").y],
		both and absf(float(secs_1s[0]) - 1.0) < 0.05 and absf(float(secs_1s[1]) - 1.0) < 0.05 and red_gap < 0.1
		and int(shape[911]) == 2 and int(shape[912]) == 1 and code.contains("raider = INSTANCE_CUSTOM.y;") and code.contains("if (raider > 0.5)") and code.contains("uniform vec2 box")
		and (t.line_mat.get_shader_parameter("box") as Vector2).is_equal_approx((Tactical as Script).get_script_constant_map().get("HOSTILE_BOX", Vector2.ZERO)))
	# raiders are not the crowd thinning is for: six commuters off her way keep their lines beside three raiders
	T.cars.clear()
	for k in 80:
		t.sync(1.0 / 120.0, v._rush_flow, true)
	for k in 6:
		T.cars.append(_car(sim, 920 + k, e1, here + (3000.0 + 500.0 * k) / 24.0, 1, -112.5 if k % 2 == 0 else 157.5, 2500.0))
	for k in 3:
		T.cars.append(_car(sim, 930 + k, e1, here + (2500.0 + 700.0 * k) / 24.0, 1, 22.5, 2500.0, true))
	for k in 80:
		t.sync(1.0 / 120.0, v._rush_flow, true)
	var off_way := 0
	var raider_marks := 0
	for m in t.marks.values():
		off_way += int(not m.hostile and not m.way)
		raider_marks += int(m.hostile)
	_check("three raiders among six commuters off her way: not thinned (%s), every commuter's line kept (%d of 6), every raider marked (%d of 3)" % [t.thinned, off_way, raider_marks],
		not t.thinned and off_way == 6 and raider_marks == 3)
	# every line taken: a raider is never the one left out
	T.cars.clear()
	for k in 80:
		t.sync(1.0 / 120.0, v._rush_flow, true)
	for k in 12:
		T.cars.append(_car(sim, 940 + k, e1, here + (1500.0 + 450.0 * k) / 24.0, 1, 22.5 if k % 2 == 0 else -22.5, 2500.0))
	for k in 80:
		t.sync(1.0 / 120.0, v._rush_flow, true)
	var full_before: int = t.marks.size()
	T.cars.append(_car(sim, 960, e1, here + 3200.0 / 24.0, 1, 22.5, 2500.0, true))
	for k in 80:
		t.sync(1.0 / 120.0, v._rush_flow, true)
	var late_shape := -1
	var kl := 0
	for m in t.marks.values():
		if m.id == 960:
			late_shape = t.line_shape[kl]
		kl += 1
	_check("every line taken by twelve commuters in her way (%d marks of %d): a raider coming up still gets its mark (%s, shape %d), the furthest-off commuter's giving way (it is %s; %d marks, %d drawn)" % [full_before, Tactical.MAX_LINES, t.marks.has(960), late_shape,
			"gone" if not t.marks.has(951) else "still there", t.marks.size(), t.line_count],
		full_before == Tactical.MAX_LINES and t.marks.has(960) and late_shape == 2 and not t.marks.has(951) and t.marks.size() == Tactical.MAX_LINES and t.line_count == Tactical.MAX_LINES)
	T.cars.clear()
	Tactical.wanted = false
	t = Tactical.frame(v, t, 1.0 / 120.0, v._rush_flow, true)
	await _finish(v, prefs_before)


func _finish(v, prefs_before: String) -> void:
	v.queue_free()
	await process_frame
	# ---- raids off ----
	Raids.enabled = false
	var o = View.new()
	root.add_child(o)
	await process_frame
	o.set_process(false)
	o.flash_until = 0.0
	var line: String = o._net_text()
	_check("raids off: no director (%s), nothing of it in the tree, traffic's race line none, the dash its own (\"%s\"), the maps the dash's target (%d, %d)" % [o.raids, line, o.minimap.target, o.net_target],
		o.raids == null and o.traffic_net != null and o.traffic_net.raids == null and o.find_children("network_raids", "", true, false).is_empty()
		and o.find_children("*", "MultiMeshInstance3D", true, false).filter(func(n): return n.name == "RaidBurst").is_empty()
		and o.traffic_net.race_text() == "" and not line.begins_with("RAID") and o.minimap.target == o.net_target)
	var of: Dictionary = o.minimap.update(o.sim.pod.th, 0.1)
	var mini: Script = MiniMap
	var osw: Vector2 = mini.call("target_swell", 9.0, of) if _has(mini, "target_swell") else Vector2(-1.0, -1.0)
	_check("raids off: the target never pulses (flag %s, the frame's pulse %s, the flat map's diamond %s: 9 px and no rim, as ever)" % [o.minimap.get("target_raid"), (of.get("target", {}) as Dictionary).get("raid", "none"), osw],
		o.minimap.get("target_raid") != true and not (of.get("target", {}) as Dictionary).has("raid") and osw == Vector2(9.0, 0.0))
	o.queue_free()
	await process_frame
	Raids.enabled = true
	if prefs_before == "":
		if FileAccess.file_exists(Cockpit.PREFS):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(Cockpit.PREFS))
	else:
		var out := FileAccess.open(Cockpit.PREFS, FileAccess.WRITE)
		out.store_string(prefs_before)
		out.close()
	View.track_override = ""
	print("RAID DISPLAY %s (%d checks, %d failures)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)
