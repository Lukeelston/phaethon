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
## The flyers (the stage 2 plan, task 4: view/raid_flyers.gd's drones and gunship). The stage 1 checks above are of a
## raid of raiders alone (this test's raids bring no flyers); these put flyers up by hand:
##   dash flyers    check_dash_counts_flyers: on, the raiders, then the drones, then GUNSHIP, a kind at none left out, then
##                  the clock, two spaces between them as between stage 1's parts: "RAID  5 RAIDERS  8 DRONES  GUNSHIP
##                  0:47", "RAID  5 RAIDERS  GUNSHIP  0:47"; every raider gone "RAID  3 DRONES  0:12", the gunship alone
##                  "RAID  GUNSHIP  0:12"; the dash shows each
##   map flyers     check_maps_mark_flyers: flyers.marks(x, y, r) marks by traffic.marks's own rule (|dx| and |dy| under
##                  r), each with the hostile mark; through the view's frame a drone 600 m ahead joins traffic's marks and
##                  is in both maps' dots with the hostile mark, drawn in the hostile red on the headset's map; the
##                  gunship's shots are not on the maps; raids off, the maps' marks are traffic's alone, as ever
##   tactical flyers check_tactical_lists_flyers: a drone 2 km on over her road, opening (going away faster than she
##                  closes), is picked as a raider is (hostile, seconds INF); none off her road, behind her or past the
##                  reach; through the display's frame its mark is brackets in the hostile red, standing at its x, y on
##                  the road (its height not drawn)
##   full raid      check_tactical_full_raid (fix round 1, Ruling Q): six raiders, ten drones and the gunship in reach and
##                  a commuter in her way: every raider marked, the commuter keeps its line, the flyers hold FLYER_LINES
##                  (4) lines, the gunship and the nearest drones; a drone not 500 m nearer (FLYER_KEEP) than one holding a
##                  line does not take it, one that is does (the farthest held drone's goes); every line taken, a late
##                  raider takes a commuter's off her way first, then the farthest drone's, never the gunship's nor the
##                  commuter's in her way; and a commuter coming into her way then takes the farthest drone's line
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
const Flyers := preload("res://view/raid_flyers.gd")
const MPH := 2.236936
var failures := 0
var checks := 0
var _flyer_ids := 0


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


## How many arguments a script's method takes (-1: no such method).
func _arity(script: Script, method: String) -> int:
	for m in script.get_script_method_list():
		if String(m.name) == method:
			return (m.args as Array).size()
	return -1


## A flyer of the raid's (view/raid_flyers.gd) put up by hand, not flown (nothing steps it here): `kind` at (x, y), z m
## up, going (vx, vy) m/s. The gunship is the module's own (its gunship()).
func _flyer(F, kind: String, x := 0.0, y := 0.0, z := 0.0, vx := 0.0, vy := 0.0):
	var f = Flyers.Gunship.new() if kind == "gunship" else Flyers.Flyer.new()
	f.id = Flyers.ID_BASE + 5000 + _flyer_ids
	_flyer_ids += 1
	f.kind = kind
	f.x = x
	f.y = y
	f.z = z
	f.vx = vx
	f.vy = vy
	f.v = Vector2(vx, vy).length()
	if f.v > 0.0:
		f.hx = vx / f.v
		f.hy = vy / f.v
	F._list.append(f)
	if kind == "gunship":
		F._gunship = f
	return f


## A road's place `lat` m left of its middle at sample f (the sims' frame), and its deck's height there.
func _road_at(sim, road: int, f: float, lat := 0.0) -> Vector3:
	var R = sim.roads[road]
	var i := clampi(int(f), 0, int(R.N) - 1)
	return Vector3(R.px[i] + R.nx[i] * lat, R.py[i] + R.ny[i] * lat, sim.net_height(road, float(i)))


## The dash's line with flyers up: the director's own text(), from a director set to these counts by hand (its pack's
## size, its flyers' kinds, its clock): the raiders, the drones, GUNSHIP, a kind at none left out, the clock.
func check_dash_counts_flyers(v) -> void:
	var R = v.raids
	var F = R.flyers
	var pack_was: Array = R.pack.duplicate()
	var t_was: float = R._t
	var lines := []
	var ok := true
	# [raiders, drones, the gunship, s left, the line wanted]
	for case in [[5, 8, true, 47.5, "RAID  5 RAIDERS  8 DRONES  GUNSHIP  0:47"], [5, 0, true, 47.5, "RAID  5 RAIDERS  GUNSHIP  0:47"],
			[0, 3, false, 12.5, "RAID  3 DRONES  0:12"], [0, 0, true, 12.5, "RAID  GUNSHIP  0:12"]]:
		R.pack.clear()
		for k in int(case[0]):
			R.pack.append(Traffic.Car.new())
		F.clear()
		for k in int(case[1]):
			_flyer(F, "drone")
		if case[2]:
			_flyer(F, "gunship")
		R._t = R.time_limit - float(case[3])
		v.flash_until = 0.0
		var line: String = R.text()
		var dash: String = v._net_text()
		lines.append(line)
		ok = ok and line == String(case[4]) and dash == line
	R.pack.clear()
	R.pack.append_array(pack_was)
	F.clear()
	R._t = t_was
	_check("on with flyers up: raiders, drones, the gunship, a kind at none left out, the clock: %s (want \"RAID  5 RAIDERS  8 DRONES  GUNSHIP  0:47\", \"RAID  5 RAIDERS  GUNSHIP  0:47\", \"RAID  3 DRONES  0:12\", \"RAID  GUNSHIP  0:12\"), each on the dash" % [lines],
		ok and R.state == "on")


## The maps: flyers.marks's rule is traffic.marks's; a drone joins traffic's marks through the view's frame and is on
## both maps in the hostile style; the gunship's shots are not.
func check_maps_mark_flyers(v) -> void:
	var R = v.raids
	var F = R.flyers
	var T = v.traffic_net
	var sim = v.sim
	var P = v.minimap_panel
	# the rule, against traffic's: the same places about a point, a hostile car and a drone at each
	var c0 := Vector2(sim.pod.x, sim.pod.y)
	var r := 1000.0
	var probes := [Vector2(0.9, 0.9), Vector2(0.999, 0.0), Vector2(0.0, -0.999), Vector2(1.001, 0.0), Vector2(-0.7, 0.7), Vector2(0.5, -1.2), Vector2(-1.3, -1.3)]
	var cars_were: Array = T.cars.duplicate()
	T.cars.clear()
	F.clear()
	var inside := 0
	for k in probes.size():
		var at: Vector2 = c0 + (probes[k] as Vector2) * r
		var c := Traffic.Car.new()
		c.id = 990200 + k
		c.x = at.x
		c.y = at.y
		c.hostile = true
		T.cars.append(c)
		_flyer(F, "drone", at.x, at.y, 90.0)
		inside += int(absf((probes[k] as Vector2).x) < 1.0 and absf((probes[k] as Vector2).y) < 1.0)
	var by_traffic: Array = T.marks(c0.x, c0.y, r)
	var by_flyers: Array = F.marks(c0.x, c0.y, r)
	T.cars.clear()
	T.cars.append_array(cars_were)
	F.clear()
	var all_hostile := true
	for m in by_flyers:
		all_hostile = all_hostile and int(m[2]) == Traffic.HOSTILE_MARK
	_check("flyers.marks(x, y, r) marks by traffic.marks's own rule: of %d places about a point, %d within r on each axis; traffic's marks %d, the flyers' %d, the same places (%s), each the hostile mark (%s)" % [probes.size(), inside, by_traffic.size(), by_flyers.size(), by_flyers == by_traffic, all_hostile],
		by_flyers == by_traffic and by_flyers.size() == inside and inside == 4 and all_hostile)
	# through the view's frame: a drone 600 m ahead, and a gunship's shot in flight beside it
	var fwd := Vector2(cos(sim.pod.th), sin(sim.pod.th))
	var at := c0 + fwd * 600.0
	var drone = _flyer(F, "drone", at.x, at.y, float(sim.pod.z) + 90.0)
	F.shots.append({"p": Vector3(at.x + 80.0, at.y, float(sim.pod.z) + 40.0), "v": Vector3.ZERO, "t": 0.0})
	var whole_was: bool = v.minimap.whole
	v.minimap.whole = false
	v._sync_world()      # (the view's own frame: the maps' marks)
	var mk: Array = v.minimap.marks
	var its := mk.filter(func(m): return is_equal_approx(float(m[0]), drone.x) and is_equal_approx(float(m[1]), drone.y))
	var hostiles := mk.filter(func(m): return int(m[2]) == Traffic.HOSTILE_MARK).size()
	var f: Dictionary = v.minimap.update(sim.pod.th, 1.0 / 60.0)
	var flat: Dictionary = MiniMap.layout(f, Map2D.SIDE, Map2D.SIDE, Map2D.MARGIN, Map2D.TOP)
	var head: Dictionary = MiniMap.layout(f, MapPanel.W, MapPanel.H, MapPanel.MARGIN, MapPanel.TOP)
	var flat_h := (flat.dots as Array).filter(func(d): return int(d[1]) == Traffic.HOSTILE_MARK and (d[0] as Vector2).y > (flat.craft as Vector2).y)
	var head_h := (head.dots as Array).filter(func(d): return int(d[1]) == Traffic.HOSTILE_MARK and (d[0] as Vector2).y > (head.craft as Vector2).y)
	P.show_frame(f)
	var red: int = _painted(P, Traffic.HOSTILE_COL.srgb_to_linear())
	F.clear()
	v.minimap.whole = whole_was
	v.minimap.marks = []
	_check("a drone 600 m ahead (and a gunship's shot in flight beside it): through the view's frame it joins traffic's marks (%d marks, %d hostile; the drone's %s), the shot is none of them; in both maps' dots with the hostile mark, ahead of the craft (the flat map's %d, the headset's %d), drawn in the hostile red on the headset's map (%d vertices: one mark)" % [mk.size(), hostiles, its, flat_h.size(), head_h.size(), red],
		its.size() == 1 and int(its[0][2]) == Traffic.HOSTILE_MARK and hostiles == 1 and flat_h.size() == 1 and head_h.size() == 1 and red == 3)


## The tactical display: a drone over her road in reach is listed as a raider is, whatever its closing time; placed by
## its x, y on the road, its height not drawn.
func check_tactical_lists_flyers(v, t, road: int, here: float, speed: float) -> void:
	var R = v.raids
	var F = R.flyers
	var T = v.traffic_net
	var sim = v.sim
	var Rd = sim.roads[road]
	var i_on := clampi(int(here + 2000.0 / 24.0), 0, int(Rd.N) - 1)
	var away := 5500.0 / MPH                         # (opening: going away at 5,500 mph against her 5,000)
	F.clear()
	var p := _road_at(sim, road, here + 2000.0 / 24.0, 22.5)
	var opening = _flyer(F, "drone", p.x, p.y, p.z + 100.0, Rd.tx[i_on] * away, Rd.ty[i_on] * away)
	var q := _road_at(sim, road, here + 2000.0 / 24.0, 1500.0)
	var aside = _flyer(F, "drone", q.x, q.y, q.z + 100.0)          # 1.5 km to her side: off her road
	q = _road_at(sim, road, here - 300.0 / 24.0, 22.5)
	var behind = _flyer(F, "drone", q.x, q.y, q.z + 100.0)
	q = _road_at(sim, road, here + 30000.0 / 24.0, 22.5)
	var beyond = _flyer(F, "drone", q.x, q.y, q.z + 100.0)         # past the display's reach
	var arity := _arity(Tactical, "pick")
	var got: Array = t.pick([], speed, [opening, aside, behind, beyond]) if arity >= 3 else []
	var its := got.filter(func(g): return g.car == opening)
	var said := "none"
	if its.size() == 1:
		said = "hostile %s, %.0f m on, seconds %s" % [its[0].get("hostile"), float(its[0].along), its[0].seconds]
	_check("a drone 2 km on over her road, going away at 5,500 mph against her 5,000, is picked as a raider is (%s); none 1.5 km to her side, behind her or past the reach (%d picked of 4; pick takes the flyers: %d arguments)" % [said, got.size(), arity],
		arity >= 3 and got.size() == 1 and its.size() == 1 and bool(its[0].get("hostile", false)) and float(its[0].seconds) == INF and absf(float(its[0].along) - 2000.0) < 60.0)
	# through the display's frame: the director's flyers, the drone alone, no traffic
	var cars_were: Array = T.cars.duplicate()
	T.cars.clear()
	F.clear()
	F._list.append(opening)
	for k in 80:
		t.sync(1.0 / 120.0, v._rush_flow, true)
	var mark = t.marks.get(opening.id)
	var shape := -1
	var tint := Color.BLACK
	var kk := 0
	for m in t.marks.values():
		if m.id == opening.id:
			shape = t.line_shape[kk]
			tint = t.line_tints[kk]
		kk += 1
	var deck: float = sim.net_height(road, here + 2000.0 / 24.0)
	if mark != null and mark.get("deck") != null:
		mark.deck = -999.0      # (each pass sets it again from the road under the flyer: here 0 m, as a mark's own start)
		for k in 2 * Tactical.SCAN_FRAMES:
			t.sync(1.0 / 120.0, v._rush_flow, true)
	var stands = mark.get("deck") if mark != null else null
	_check("... and through the display's frame, the director's flyer: its mark (%s), brackets (shape %d) in the hostile red (%s) though she is not gaining on it; the drone's own (%s), standing at %s m on the road under it (the road's %.0f m; the drone %.0f m up: its height not drawn)" % [mark != null, shape, tint.to_html(), mark.get("flyer") == opening if mark != null else null, stands, deck, opening.z],
		mark != null and shape == 2 and tint.is_equal_approx(Color(Traffic.HOSTILE_COL, 1.0)) and mark.get("flyer") == opening and stands != null and absf(float(stands) - deck) < 5.0)
	F.clear()
	T.cars.clear()
	T.cars.append_array(cars_were)


## The display's lines live now (marks drawn and not going): of `ids`, those with one.
func _held(t, ids: Array) -> Array:
	return ids.filter(func(id): return t.marks.has(id) and float(t.marks[id].to) > 0.0)


func _settle_lines(v, t) -> void:
	for k in 80:
		t.sync(1.0 / 120.0, v._rush_flow, true)


## A full raid on the tactical display (Ruling Q): raiders first, never left out; then the commuters in her way (no flyer
## takes such a line); then the flyers, the gunship and the nearest drones, FLYER_LINES in all; then the rest.
func check_tactical_full_raid(v, t, road: int, here: float) -> void:
	var F = v.raids.flyers
	var T = v.traffic_net
	var sim = v.sim
	var cars_were: Array = T.cars.duplicate()
	T.cars.clear()
	F.clear()
	_settle_lines(v, t)      # (the last check's lines gone)
	var cap := int((Tactical as Script).get_script_constant_map().get("FLYER_LINES", 4))
	var keep := float((Tactical as Script).get_script_constant_map().get("FLYER_KEEP", 500.0))
	# six raiders 2.5 to 15 km on (off her way), ten drones 3 to 21 km on over her road, the gunship 20 km on, and a
	# commuter in her way 4 km on, reached in 3.6 s
	var raiders := []
	for k in 6:
		raiders.append(_car(sim, 970100 + k, road, here + (2500.0 + 2500.0 * k) / 24.0, 1, -67.5, 4400.0, true))
	var drones := []
	for k in 10:
		var p := _road_at(sim, road, here + (3000.0 + 2000.0 * k) / 24.0, -150.0 + 30.0 * k)
		drones.append(_flyer(F, "drone", p.x, p.y, p.z + 100.0))
	var gp := _road_at(sim, road, here + 20000.0 / 24.0, 0.0)
	var gunship = _flyer(F, "gunship", gp.x, gp.y, gp.z + 200.0)
	var in_way := _car(sim, 970200, road, here + 4000.0 / 24.0, 1, 22.5, 2500.0)
	T.cars.append_array(raiders)
	T.cars.append(in_way)
	_settle_lines(v, t)
	var raider_ids: Array = raiders.map(func(c): return c.id)
	var drone_ids: Array = drones.map(func(f): return f.id)
	var flyer_ids: Array = drone_ids + [gunship.id]
	var r_held := _held(t, raider_ids)
	var f_held := _held(t, flyer_ids)
	var c_mark = t.marks.get(in_way.id)
	var c_ok: bool = c_mark != null and float(c_mark.to) > 0.0 and bool(c_mark.way) and not bool(c_mark.hostile) and (c_mark.tint as Color).is_equal_approx(Tactical.soon_tint(float(c_mark.seconds)))
	_check("a full raid, six raiders and eleven flyers in reach, a commuter in her way %.1f s off: every raider marked (%d of 6), the commuter keeps its line (%s); the flyers hold %d lines (want %d): the gunship (%s) and the nearest drones (%s, want %s); %d lines in all" % [
			float(c_mark.seconds) if c_mark != null else -1.0, r_held.size(), c_ok, f_held.size(), cap, f_held.has(gunship.id), f_held.filter(func(id): return id != gunship.id), drone_ids.slice(0, cap - 1), t.line_count],
		r_held.size() == 6 and c_ok and cap == 4 and f_held.size() == cap and f_held.has(gunship.id) and _held(t, drone_ids.slice(0, cap - 1)).size() == cap - 1
		and t.line_count == 6 + 1 + cap)
	# a drone coming nearer: a little (300 m nearer than the farthest held, under FLYER_KEEP) takes nothing; well nearer
	# (1.5 km) takes the farthest held drone's line
	var d2 = drones[2]
	var d3 = drones[3]
	var at3 := Vector2(d3.x, d3.y)
	var p := _road_at(sim, road, here + 6700.0 / 24.0, 0.0)
	d3.x = p.x
	d3.y = p.y
	_settle_lines(v, t)
	var steady: bool = _held(t, [d2.id]).size() == 1 and _held(t, [d3.id]).is_empty() and _held(t, flyer_ids).size() == cap
	p = _road_at(sim, road, here + 5500.0 / 24.0, 0.0)
	d3.x = p.x
	d3.y = p.y
	_settle_lines(v, t)
	var swapped: bool = _held(t, [d3.id]).size() == 1 and _held(t, [d2.id]).is_empty() and _held(t, flyer_ids).size() == cap and _held(t, [gunship.id]).size() == 1
	d3.x = at3.x
	d3.y = at3.y
	_settle_lines(v, t)
	var back: bool = _held(t, [d2.id]).size() == 1 and _held(t, [d3.id]).is_empty()
	_check("a drone 300 m nearer than the farthest held one (under FLYER_KEEP, %.0f m) takes no line (%s); 1.5 km nearer, it takes the farthest held drone's (%s); back where it was, that drone has its line again (%s)" % [keep, steady, swapped, back],
		steady and swapped and back)
	# every line taken (a commuter off her way 6 km on takes the last), and raiders come into reach late
	var off_way := _car(sim, 970201, road, here + 6000.0 / 24.0, 1, -112.5, 2500.0)
	T.cars.append(off_way)
	_settle_lines(v, t)
	var full: int = t.line_count
	var had_off: bool = _held(t, [off_way.id]).size() == 1
	var late := _car(sim, 970106, road, here + 17500.0 / 24.0, 1, -67.5, 4400.0, true)
	T.cars.append(late)
	_settle_lines(v, t)
	var late_marked: bool = _held(t, [late.id]).size() == 1
	var off_gone: bool = not t.marks.has(off_way.id)
	var flyers_after_one: int = _held(t, flyer_ids).size()
	var later := _car(sim, 970107, road, here + 18000.0 / 24.0, 1, -67.5, 4400.0, true)
	T.cars.append(later)
	_settle_lines(v, t)
	var later_marked: bool = _held(t, [later.id]).size() == 1
	var f_after := _held(t, flyer_ids)
	var in_way_kept: bool = _held(t, [in_way.id]).size() == 1
	_check("every line taken (%d, the commuter off her way's among them: %s): a raider coming into reach takes that commuter's line (marked %s, the commuter's gone %s, the flyers' %d kept); another takes the farthest held drone's (marked %s; the flyers' now %s: the gunship's kept %s, drone %d's gone %s); the commuter in her way keeps its line throughout (%s); every raider marked (%d of 8)" % [
			full, had_off, late_marked, off_gone, flyers_after_one, later_marked, f_after, f_after.has(gunship.id), d2.id, not f_after.has(d2.id), in_way_kept, _held(t, raider_ids + [late.id, later.id]).size()],
		full == Tactical.MAX_LINES and had_off and late_marked and off_gone and flyers_after_one == cap and later_marked and f_after.size() == cap - 1
		and f_after.has(gunship.id) and not f_after.has(d2.id) and in_way_kept and _held(t, raider_ids + [late.id, later.id]).size() == 8)
	# every line still taken, a second commuter comes into her way (the next lane, 3 km on): it takes the farthest held
	# drone's line, not a raider's nor the first commuter's
	var second := _car(sim, 970202, road, here + 3000.0 / 24.0, 1, -22.5, 2500.0)
	T.cars.append(second)
	_settle_lines(v, t)
	var f_last := _held(t, flyer_ids)
	_check("every line taken, a second commuter in her way (%s s off) takes the farthest held drone's line (marked %s; the flyers' now %s: the gunship's kept %s, drone %d's gone %s); the first keeps its line (%s), every raider its mark (%d of 8); %d lines" % [
			t.marks[second.id].seconds if t.marks.has(second.id) else "-", _held(t, [second.id]).size() == 1, f_last, f_last.has(gunship.id), drones[1].id, not f_last.has(drones[1].id),
			_held(t, [in_way.id]).size() == 1, _held(t, raider_ids + [late.id, later.id]).size(), t.line_count],
		_held(t, [second.id]).size() == 1 and bool(t.marks[second.id].way) and f_last.size() == cap - 2 and f_last.has(gunship.id) and not f_last.has(drones[1].id)
		and _held(t, [in_way.id]).size() == 1 and _held(t, raider_ids + [late.id, later.id]).size() == 8 and t.line_count == Tactical.MAX_LINES)
	T.cars.clear()
	F.clear()
	_settle_lines(v, t)
	T.cars.append_array(cars_were)


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
	R.drones = Vector2i(0, 0)   # (the stage 1 checks: a raid of raiders alone; the flyers' checks put up their own)
	R.gunship_from = 1000000
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
	check_dash_counts_flyers(v)

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
	check_maps_mark_flyers(v)

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
	check_tactical_lists_flyers(v, t, e1, here, speed)
	check_tactical_full_raid(v, t, e1, here)
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
	o._sync_world()      # (the view's own frame: the maps' marks)
	var off_marks: Array = o.minimap.marks
	var traffic_only: Array = o.traffic_net.marks(o.sim.pod.x, o.sim.pod.y, 40000.0)
	_check("raids off: the maps' marks are traffic's alone, as ever (%d marks, traffic's %d)" % [off_marks.size(), traffic_only.size()],
		off_marks == traffic_only and not traffic_only.is_empty())
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
