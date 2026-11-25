## The tactical display (view/tactical_display.gd; Luke, 2026-11-22: "a switch that adds a 'tactical speed
## display' hud over the whole windscreen ... a physical overlay onto the world") and the quick menu's panels
## (view/main_menu.gd lay()) that its switch is on:
##   the menu      the OPTIONS page's first panel is as it was; stepping on past BACK is the next panel, where
##                 TACTICAL DISPLAY is; it is off with nothing saved, and saved when switched; a page of any
##                 length is laid out in panels of ten lines at most
##   off           no node, nothing drawn; the cockpit's one call costs next to nothing
##   the rails     stand on the road's own samples, at its edges, on its surface (the views' accessor), out to
##                 twelve seconds' flying; their colour is the bend's ask against the sim's own grip at the
##                 speed she is doing, on the scale set from Luke's flights (calm under 1.8, red from 2.7), which
##                 `pace` moves live; a banked circuit's bank is in it; at no severity are they a vehicle's colour
##                 (nor an exit's); `dim` dims it all
##   the vehicles  one ahead in her lane that she is closing on has a line; one she is not gaining on, one on
##                 a road crossing overhead and one on that deck heading her way have none; a busy road keeps
##                 only those in her way
##   the exits     an exit's chevrons begin seven seconds before its mouth at any speed to 8,000 mph (never
##                 less than 8 km), stand on its lane, point the way it leaves, and none is laid nearer than
##                 two and a half seconds; a gate stands across the lane at the mouth; the row is laid in
##                 seconds at the speed it was laid for, big at the whole seconds, a quarter apart over the last
##                 two and a half before that; seen from the seat a chevron keeps one size far off and grows as
##                 she nears from two and a half seconds off, as a thing of its own size does
##   the log       a TAC line a second while it is shown, none while it is off or nothing of it is shown
##   where         nothing standing still, in the Aurora tube, from an outside camera; the number alone off
##                 the roads
## --headless --xr-mode off --audio-driver Dummy -s res://tests/test_tactical_display.gd -- --mute
## Prints TACTICAL DISPLAY PASS.
extends SceneTree

const View := preload("res://view/craft_view.gd")
const Cockpit := preload("res://vr/vr_cockpit.gd")
const Tactical := preload("res://view/tactical_display.gd")
const Traffic := preload("res://view/network_traffic.gd")
const Menu := preload("res://view/main_menu.gd")
const MPH := 2.236936
const G := 9.81
var failures := 0
var checks := 0


func _initialize() -> void:
	View.track_override = "network"
	View.job_override = "none"
	View.best_dir = OS.get_user_data_dir().path_join("test_tactical_")
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
	preload("res://view/outlook.gd").pinned = true
	_run.call_deferred()


func _check(label: String, passed: bool) -> void:
	checks += 1
	print(("PASS " if passed else "FAIL ") + label)
	failures += int(not passed)


func _keys(v) -> Array:
	var keys := []
	for item in v.menu.items:
		keys.append(String(item.key))
	return keys


func _go(v, key: String) -> bool:
	for k in v.menu.items.size():
		if String(v.menu.items[k].key) == key:
			v.menu.at = k
			v.menu_choose()
			return true
	return false


func _saved() -> Dictionary:
	var d = JSON.parse_string(FileAccess.get_file_as_string(Cockpit.PREFS)) if FileAccess.file_exists(Cockpit.PREFS) else {}
	return d if d is Dictionary else {}


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


## Frames of the display until its rails reach as far as they are to (or the road runs out).
## Stations whose rail sides are marked right for the way she flies (Vector2i(right, all)): a rail's vertices lie to
## her left of the station's middle (tx * dy - ty * dx > 0 along her heading) when they carry 0, to her right with 1.
func _sides(t) -> Vector2i:
	var good := 0
	var n: int = t.st_s.size()
	for k in n:
		var a: Vector3 = t._verts[4 * k]
		var b: Vector3 = t._verts[4 * k + 2]
		var mid := (a + b) * 0.5
		var ok := true
		for side in 2:
			for top in 2:
				var at: Vector3 = t._verts[4 * k + 2 * side + top] - mid
				var leftward: float = t.st_tx[k] * -at.z - t.st_ty[k] * at.x      # (the views' z is -y)
				var marked: float = t._side[4 * k + 2 * side + top].r
				ok = ok and ((leftward > 0.0 and marked == 0.0) or (leftward < 0.0 and marked == 1.0))
		good += 1 if ok else 0
	return Vector2i(good, n)


## How far apart two colours are (straight-line distance in RGB, 0 .. 1.73).
func _apart(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()


func _settle(v, t, frames := 600) -> int:
	var sim = v.sim
	var speed: float = Vector2(sim.pod.vx, sim.pod.vy).length()
	for k in frames:
		t.sync(1.0 / 120.0, v._rush_flow, true)
		if t.st_s.size() >= 2 and (t.route_done or t.st_s[t.st_s.size() - 1] >= t.pod_s + Tactical.reach_at(speed)):
			return k + 1
	return frames


func _car(sim, id: int, road: int, f: float, dir: int, lat: float, mph: float) -> Traffic.Car:
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
	return c


func _run() -> void:
	var prefs_before := FileAccess.get_file_as_string(Cockpit.PREFS) if FileAccess.file_exists(Cockpit.PREFS) else ""
	if prefs_before != "":      # a pilot with nothing saved: what he gets
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Cockpit.PREFS))
	Tactical.wanted = false
	var v = Cockpit.new()
	root.add_child(v)
	await process_frame
	v.set_process(false)
	var sim = v.sim
	v.traffic_net.cars.clear()      # (the road's own traffic stays out of what is counted here)

	# ---- the menu ----
	_check("with nothing saved the tactical display is off, and there is no node of it", not Tactical.wanted and v.tactical == null and v.find_child("TacticalDisplay", true, false) == null)
	v.menu_open(true)
	var first: Array = _keys(v)
	_go(v, "options")
	var one: Array = _keys(v)
	var head: String = v.menu.text().get_slice("\n", 0)
	# (parked at its launch site, it begins with Codex's PILOT GARAGE: vr_cockpit.gd _menu_items, craft_view.gd can_visit_garage)
	_check("the OPTIONS page's first panel is as it was, with the garage first (%s), headed \"%s\"" % [one, head],
		v.can_visit_garage() and one == ["garage", "consumables", "powerups", "field", "autopilot", "rush", "nose", "back"] and head == "OPTIONS   1 / 2" and v.menu.at == 0 and v.menu.paged())
	_check("... and its BACK says where stepping on goes: \"%s\"" % v.menu.text().get_slice("\n", one.size() + 1).strip_edges(), v.menu.text().get_slice("\n", one.size() + 1).contains("BACK   (DOWN: PAGE 2)"))
	for k in one.size() - 1:
		v.menu.move(1)
	var on_back: String = v.menu.key()
	v.menu.move(1)
	var two: Array = _keys(v)
	_check("stepping down its lines reaches BACK (%s), and once more the next panel: %s, the cursor on \"%s\", headed \"%s\"" % [on_back, two, v.menu.key(), v.menu.text().get_slice("\n", 0)],
		on_back == "back" and two == ["tactical", "back"] and v.menu.key() == "tactical" and v.menu.text().begins_with("OPTIONS   2 / 2") and v.menu.text().contains("TACTICAL DISPLAY   OFF"))
	v.menu_choose()
	_check("TACTICAL DISPLAY switched on: wanted, the line reads ON, the cursor still on it, the panel still up, saved (%s)" % _saved().get("tactical", ""),
		Tactical.wanted and v.menu.text().contains("TACTICAL DISPLAY   ON") and v.menu.key() == "tactical" and v.menu.page == 1 and _saved().get("tactical", "") == "on")
	v.menu.move(-1)
	_check("up from a panel's first line is the panel before's last (%s, panel %d)" % [v.menu.key(), v.menu.page + 1], v.menu.key() == "back" and v.menu.page == 0 and _keys(v) == one)
	v.menu.move(1)
	v.menu.move(1)
	v.menu.move(1)
	_check("down past the last panel's BACK is the first panel's first line (%s, panel %d)" % [v.menu.key(), v.menu.page + 1], v.menu.key() == one[0] and v.menu.page == 0)
	v.menu.move(-1)
	_check("... and up from there the last panel's BACK", v.menu.key() == "back" and v.menu.page == 1)
	_go(v, "back")
	_check("BACK from any panel returns to the first page with the cursor on OPTIONS", _keys(v) == first and v.menu.key() == "options" and not v.menu.paged() and v.menu.text().begins_with("FLIGHT HOLD\n"))
	v.menu.move(-1)
	v.menu.move(1)
	for k in first.size():
		v.menu.move(1)
	_check("the first page still wraps round itself (%s)" % v.menu.key(), v.menu.key() == "options" and _keys(v) == first)
	_go(v, "options")
	_check("OPTIONS opened again begins at its first panel", v.menu.page == 0 and _keys(v) == one)
	v.menu.move(-1)
	v.menu_open(false)
	v.menu_open(true)
	_check("closed on the second panel, the menu opens on the first page", _keys(v) == first and not v.menu.paged())
	v.menu_open(false)
	v._await_neutral_controls = false
	# a page of any length
	var m := Menu.new()
	var long := []
	for k in 25:
		long.append({"key": "k%d" % k, "label": "LINE %d" % k})
	m.items = m.lay([long, [{"key": "more", "label": "MORE"}]], {"key": "back", "label": "BACK"})
	var sizes := []
	var seen := []
	for p in m.pages:
		sizes.append((p as Array).size())
		for item in p:
			if String(item.key) != "back":
				seen.append(String(item.key))
	_check("twenty-five lines and one more are laid out as panels of %s: none over ten, every line once, each ending in BACK" % [sizes],
		sizes == [10, 10, 8, 2] and seen.size() == 26 and seen[0] == "k0" and seen[25] == "more" and String(m.pages[2][7].key) == "back")
	var walked := []
	for k in 30:
		walked.append(m.key())
		m.move(1)
	_check("... and stepping down walks them all in order, through each BACK, and round to the start", walked[9] == "back" and walked[10] == "k9" and walked[19] == "back" and walked[27] == "back" and walked[28] == "more" and walked[29] == "back" and m.key() == "k0")
	m.items = [{"key": "a", "label": "A"}, {"key": "b", "label": "B"}]
	m.at = 1
	m.move(1)
	_check("a menu given plain items afterwards has no panels: it wraps, and its heading is its own", m.key() == "a" and not m.paged() and m.text().begins_with("FLIGHT HOLD\n"))
	# the Eridanus track's own page (nine lines and BACK): still one panel, and the next
	var eri := Menu.new()
	var nine := []
	for k in 9:
		nine.append({"key": "k%d" % k, "label": "L"})
	eri.lay([nine, [{"key": "tactical", "label": "T"}]], {"key": "back", "label": "BACK"})
	_check("nine lines and BACK (the Eridanus track's) stay one panel of ten", eri.pages.size() == 2 and (eri.pages[0] as Array).size() == 10)

	# ---- off ----
	Tactical.wanted = false
	Tactical.tac_lines = 0
	var t0 := Time.get_ticks_usec()
	var gave = null
	for k in 20000:
		gave = Tactical.frame(v, gave, 1.0 / 120.0, v._rush_flow, true)
	var off_us := float(Time.get_ticks_usec() - t0) / 20000.0
	_check("off: the cockpit's call gives nothing back, builds nothing, writes nothing to the log (%d lines in 167 s of frames), and takes %.2f microseconds" % [Tactical.tac_lines, off_us],
		gave == null and v.find_child("TacticalDisplay", true, false) == null and off_us < 3.0 and Tactical.tac_lines == 0)

	# ---- the rails ----
	var e1 := _road(sim, "E1")
	var n1 := _road(sim, "N1")
	var E = sim.roads[e1]
	_place(v, e1, 4000, 1, 3000.0)
	Tactical.wanted = true
	var t = Tactical.frame(v, null, 1.0 / 120.0, v._rush_flow, true)
	_check("on: the call builds it (a child of the view), with its rails, lines, chevrons and number", t != null and t.get_parent() == v and t.rails != null and t.lines != null and t.chevrons != null and t.number != null)
	var frames := _settle(v, t)
	var speed := 3000.0 / MPH
	var n: int = t.st_s.size()
	var on_samples := true
	var on_surface := true
	var worst_gap := 0.0
	for k in n:
		var r: int = t.st_road[k]
		var i: int = t.st_i[k]
		var R = sim.roads[r]
		on_samples = on_samples and is_equal_approx(t.st_x[k], R.px[i]) and is_equal_approx(t.st_y[k], R.py[i])
		for side in 2:
			var lat: float = (R.w[i] / 2.0 - Tactical.RAIL_INSET) * (1.0 if side == 0 else -1.0)
			var x: float = R.px[i] + R.nx[i] * lat
			var y: float = R.py[i] + R.ny[i] * lat
			var want := Vector3(x - t._ax, float(sim.surface_at(x, y, i, r).x) + 0.3, -(y - t._ay))
			for top in 2:
				var got: Vector3 = t._verts[4 * k + 2 * side + top]
				worst_gap = maxf(worst_gap, got.distance_to(want))
				on_surface = on_surface and t._uv[4 * k + 2 * side + top].x == float(top)
	_check("at 3,000 mph on E1 the rails are %d stations, every one on a sample of the road (%s), 96 m apart, its four vertices at the road's two edges on the views' own surface (the worst %.3f m off)" % [n, on_samples, worst_gap],
		n > 100 and on_samples and on_surface and worst_gap < 0.05 and absf((t.st_s[n - 1] - t.st_s[0]) / float(n - 1) - 96.0) < 0.5)
	_check("... from her own place (%.0f m along them) out to twelve seconds' flying (%.0f m; the last station %.0f m ahead), laid in %d frames" % [t.pod_s, Tactical.reach_at(speed), t.st_s[n - 1] - t.pod_s, frames],
		t.pod_s >= 0.0 and t.pod_s < 100.0 and t.st_s[n - 1] - t.pod_s >= Tactical.reach_at(speed) and is_equal_approx(Tactical.reach_at(speed), speed * 12.0) and t.st_road[0] == e1 and t.st_i[0] == 4000)
	_check("... and drawn: the rails shown, where the view has the road (the mesh %d vertices, its place %s)" % [t.rail_mesh.surface_get_array_len(0), t.rails.position],
		t.rails.visible and t.rail_mesh.get_surface_count() == 1 and t.rail_mesh.surface_get_array_len(0) == 4 * n and t.rails.position.is_equal_approx(Vector3(t._ax - v.org_x, 0.0, -(t._ay - v.org_y))))
	# the colour: the sim's own grip
	var grip: float = Tactical.grip(sim)
	_check("what she holds is the sim's own: %.2f g as a SPEEDCRAFT (her engines' cap %.0f g, her pod's %.0f g, by their masses)" % [grip / G, sim.P.gripCapG, sim.P.podCapG],
		is_equal_approx(grip, G * (2.0 * sim.eL.m * sim.P.gripCapG + sim.pod.m * sim.P.podCapG) / (2.0 * sim.eL.m + sim.pod.m)) and absf(grip / G - 13.79) < 0.01
		and is_equal_approx(float(t.rail_mat.get_shader_parameter("grip")), grip))
	# the hardest bend of a highway, from 6 km short of it
	var bend_road := -1
	var bend_i := 0
	var hardest := 0.0
	for r in sim.roads.size():
		var R = sim.roads[r]
		if R.shaft or R.deck or String(R.role) != "" or int(R.N) < 4000 or not (String(R.name).begins_with("E") or String(R.name).begins_with("N")):
			continue
		for i in range(400, int(R.N) - 400, 4):
			var turn: float = absf(angle_difference(atan2(R.ty[i], R.tx[i]), atan2(R.ty[i + 4], R.tx[i + 4]))) / 96.0
			if turn > hardest:
				hardest = turn
				bend_road = r
				bend_i = i
	_place(v, bend_road, bend_i - 250, 1, 3000.0)
	_settle(v, t)
	n = t.st_s.size()
	var bend := 0.0
	var bend_at := 0
	for k in n:
		if absf(t.st_k[k]) > bend:
			bend = absf(t.st_k[k])
			bend_at = k
	var v_hold := sqrt(grip / maxf(bend, 1e-12))
	_check("the hardest bend of the highways (%s, sample %d: a radius of %.1f km) is in the rails 6 km short of it (station %d), and is held to %.0f mph" % [sim.roads[bend_road].name, bend_i, 0.001 / maxf(bend, 1e-12), bend_at, v_hold * MPH],
		bend > 1e-6 and absf(bend - hardest) < hardest * 0.02 and absi(int(t.st_i[bend_at]) - bend_i) <= 8)
	var held: Color = Tactical.tint(Tactical.load_of(sim, bend, v_hold))
	var calm: Color = Tactical.tint(Tactical.load_of(sim, bend, 1.3 * v_hold))
	var warm: Color = Tactical.tint(Tactical.load_of(sim, bend, sqrt(Tactical.WARM_AT) * v_hold))
	var hot: Color = Tactical.tint(Tactical.load_of(sim, bend, 1.75 * v_hold))
	_check("its colour answers the speed, on the scale set from his flights: calm on that speed (%s; red on the old scale) and three tenths over it (%s), amber at %.2f of it (%s), red at 1.75 (%s)" % [held.to_html(false), calm.to_html(false), sqrt(Tactical.WARM_AT), warm.to_html(false), hot.to_html(false)],
		held.is_equal_approx(Tactical.RAIL_CALM) and calm.is_equal_approx(Tactical.RAIL_CALM) and warm.is_equal_approx(Tactical.RAIL_WARM) and hot.is_equal_approx(Tactical.RAIL_HOT)
		and Tactical.tint(0.5 * (Tactical.CALM_AT + Tactical.WARM_AT)).is_equal_approx(Tactical.RAIL_CALM.lerp(Tactical.RAIL_WARM, 0.5)))
	_check("... by what the mesh carries for the shader: each vertex its place along the route and the bend there (station %d: %.0f m, 1 / %.0f m), and the frame's speed squared" % [bend_at, t._uv2[4 * bend_at].x, 1.0 / t._uv2[4 * bend_at].y],
		is_equal_approx(t._uv2[4 * bend_at].x, float(t.st_s[bend_at])) and absf(t._uv2[4 * bend_at + 3].y - bend) < bend * 1e-4 and is_equal_approx(float(t.rail_mat.get_shader_parameter("speed2")), speed * speed)
		and is_equal_approx(float(t.rail_mat.get_shader_parameter("pod_s")), t.pod_s))
	# ---- the scale, its two knobs, and the rails against the vehicles ----
	t.sync(1.0 / 120.0, v._rush_flow, true)
	var sent: Vector4 = t.rail_mat.get_shader_parameter("at_load")
	_check("at pace 1 the scale is the one from his flights (calm under %.1f, amber by %.1f, red from %.1f, wholly by %.1f), and the rails' shader has it" % [sent.x, sent.y, sent.z, sent.w],
		Tactical.pace == 1.0 and Tactical.thresholds().is_equal_approx(Vector4(1.8, 2.2, 2.7, 3.0)) and sent.is_equal_approx(Vector4(1.8, 2.2, 2.7, 3.0))
		and Tactical.tint(1.79).is_equal_approx(Tactical.RAIL_CALM) and Tactical.tint(2.2).is_equal_approx(Tactical.RAIL_WARM) and Tactical.tint(3.0).is_equal_approx(Tactical.RAIL_HOT)
		and Tactical.heat(1.79) == "calm" and Tactical.heat(1.8) == "warm" and Tactical.heat(2.7) == "hot")
	Tactical.pace = 0.345
	t.sync(1.0 / 120.0, v._rush_flow, true)
	sent = t.rail_mat.get_shader_parameter("at_load")
	var sooner := Tactical.tint(0.7)
	Tactical.pace = 1.0
	t.sync(1.0 / 120.0, v._rush_flow, true)
	var back_again: Vector4 = t.rail_mat.get_shader_parameter("at_load")
	_check("pace 0.345 moves it at the next frame (calm now ends at %.3f, the old 0.62) and an ask of 0.7 is no longer calm (%s); pace 1 again, the shader has the first scale back" % [sent.x, sooner.to_html(false)],
		absf(sent.x - 0.621) < 0.001 and sent.is_equal_approx(Vector4(1.8, 2.2, 2.7, 3.0) * 0.345) and not sooner.is_equal_approx(Tactical.RAIL_CALM) and Tactical.tint(0.7).is_equal_approx(Tactical.RAIL_CALM)
		and back_again.is_equal_approx(Vector4(1.8, 2.2, 2.7, 3.0)))
	var full: float = t.rail_mat.get_shader_parameter("gain")
	Tactical.dim = 0.5
	t.sync(1.0 / 120.0, v._rush_flow, true)
	var dimmed: float = t.rail_mat.get_shader_parameter("gain")
	var dimmed_chev: float = t.chev_mat.get_shader_parameter("gain")
	var dimmed_words: float = t.number.modulate.a
	Tactical.dim = 1.0
	t.sync(1.0 / 120.0, v._rush_flow, true)
	_check("dim 0.5 halves its strength at the next frame (the rails %.2f of %.2f, the chevrons %.2f, the number %.2f); dim 1, all of it again" % [dimmed, full, dimmed_chev, dimmed_words],
		full > 0.5 and absf(dimmed - 0.5 * full) < 0.01 and absf(dimmed_chev - 0.5 * full) < 0.01 and absf(dimmed_words - 0.5 * full) < 0.01
		and absf(float(t.rail_mat.get_shader_parameter("gain")) - full) < 0.01)
	# every severity of the rails against every one of the vehicles' (and the exits' green): by hue, and by colour
	var rail_hues := Vector2(INF, -INF)
	var car_hues := Vector2(INF, -INF)
	var nearest_colour := INF
	var nearest_green := INF
	for a in 81:
		var rail: Color = Tactical.tint(float(a) * 0.05)
		rail_hues = Vector2(minf(rail_hues.x, rail.h * 360.0), maxf(rail_hues.y, rail.h * 360.0))
		nearest_green = minf(nearest_green, Vector3(rail.r - Tactical.EXIT_GREEN.r, rail.g - Tactical.EXIT_GREEN.g, rail.b - Tactical.EXIT_GREEN.b).length())
		for s in 201:
			var car: Color = Tactical.soon_tint(float(s) * 0.05)
			if a == 0:
				car_hues = Vector2(minf(car_hues.x, car.h * 360.0), maxf(car_hues.y, car.h * 360.0))
			nearest_colour = minf(nearest_colour, Vector3(rail.r - car.r, rail.g - car.g, rail.b - car.b).length())
	_check("the rails at every severity (hues %.0f to %.0f degrees) are never a vehicle's colour at any seconds (hues %.0f to %.0f): the nearest pair %.2f apart in RGB, the exits' green %.2f off" % [rail_hues.x, rail_hues.y, car_hues.x, car_hues.y, nearest_colour, nearest_green],
		rail_hues.x > car_hues.y + 40.0 and rail_hues.y < 360.0 + car_hues.x - 40.0 and nearest_colour > 0.45 and nearest_green > 0.7
		and Tactical.soon_tint(9.0).is_equal_approx(Tactical.CALM) and not Tactical.tint(0.0).is_equal_approx(Tactical.CALM))
	# the log
	Tactical.tac_lines = 0
	t._tac_t = 0.0
	for k in 300:      # two and a half seconds
		t.sync(1.0 / 120.0, v._rush_flow, true)
	var tac_pattern := RegEx.create_from_string("^TAC: rails \\d+\\.\\d\\d (calm|warm|hot) \\| vehicles \\d+ nearest (-|\\d+\\.\\d) \\| exit (-|\\d+\\.\\d)$")
	_check("while it is shown, a line a second to the log: %d in two and a half seconds, \"%s\"" % [Tactical.tac_lines, t.last_tac],
		Tactical.tac_lines == 2 and tac_pattern.search(t.last_tac) != null)
	_place(v, e1, 4000, 1, 5000.0)
	_settle(v, t)
	_check("at 5,000 mph on E1: the speed squared the shader has is that speed's, and the rails run to %.1f km" % [(t.st_s[t.st_s.size() - 1] - t.pod_s) / 1000.0],
		is_equal_approx(float(t.rail_mat.get_shader_parameter("speed2")), pow(5000.0 / MPH, 2.0)) and t.st_s[t.st_s.size() - 1] - t.pod_s >= 5000.0 / MPH * 12.0)
	sim.set_handling("starfighter")
	_check("as a STARFIGHTER she holds %.2f g (the sim's caps for that handling)" % (Tactical.grip(sim) / G), absf(Tactical.grip(sim) / G - (2.0 * sim.eL.m * 50.0 + sim.pod.m * 30.0) / (2.0 * sim.eL.m + sim.pod.m)) < 0.01)
	sim.set_handling("speed")
	_check("a bank into the bend adds its own share, as the sims add it: 10 degrees at 1,000 mph holds %.1f g against %.1f flat; out of it, %.1f" % [Tactical.hold(sim, 447.0, deg_to_rad(10.0)) / G, grip / G, Tactical.hold(sim, 447.0, deg_to_rad(-10.0)) / G],
		is_equal_approx(Tactical.hold(sim, 447.0, deg_to_rad(10.0)), grip + float(sim.P.bank) * (G * tan(deg_to_rad(10.0)) + float(sim.P.bankDown) * 447.0 * 447.0 * sin(deg_to_rad(10.0))))
		and Tactical.hold(sim, 447.0, deg_to_rad(-10.0)) < grip)
	# she flies on: the stations behind are passed, the ones ahead stay where they were
	var keep_x: float = t.st_x[40]
	var keep_i: int = t.st_i[40]
	_place(v, e1, 4000 + 30 * 4, 1, 5000.0)
	_settle(v, t, 3)
	_check("flown on 30 stations, the rails are the same ones (station 40 is now the one she has %d behind her, where it was) and she is %.0f m along them" % [40 - t.at, t.pod_s],
		t.st_i[40] == keep_i and t.st_x[40] == keep_x and t.at == 30 and absf(t.pod_s - 30.0 * 96.0) < 1.0)
	_place(v, e1, 4000, -1, 5000.0)
	_settle(v, t)
	_check("turned round, they are laid again the other way (the first station sample %d, the next %d)" % [t.st_i[0], t.st_i[1]], t.route_dir == -1 and t.st_i[0] == 4000 and t.st_i[1] == 3996 and t.st_tx[0] == -E.tx[4000])
	# the two rails in their own colours (Luke: "different colors on each side"): her left the violets, her right the
	# rose and pink, by where each rail lies from the way she flies, both ways along the road; red the same on both
	var against := _sides(t)
	_place(v, e1, 4000, 1, 5000.0)
	_settle(v, t)
	var along := _sides(t)
	_check("each rail carries its side for the shader, hers, not the road's: flown against its samples %d of %d stations right, with them %d of %d" % [against.x, against.y, along.x, along.y],
		against.y > 100 and against.x == against.y and along.y > 100 and along.x == along.y)
	_check("... and the sides differ in colour where the bend is calm and amber (left %s, right %s; amber %s, %s), not where it is red (both %s), and the shader has the right's" % [
			Tactical.RAIL_CALM.to_html(false), Tactical.RAIL_CALM_RIGHT.to_html(false), Tactical.RAIL_WARM.to_html(false), Tactical.RAIL_WARM_RIGHT.to_html(false), Tactical.RAIL_HOT.to_html(false)],
		_apart(Tactical.RAIL_CALM, Tactical.RAIL_CALM_RIGHT) > 0.3 and _apart(Tactical.RAIL_WARM, Tactical.RAIL_WARM_RIGHT) > 0.15
		and _apart(Tactical.RAIL_CALM_RIGHT, Tactical.CALM) > 0.3 and _apart(Tactical.RAIL_CALM_RIGHT, Tactical.WARM) > 0.3 and _apart(Tactical.RAIL_CALM_RIGHT, Tactical.HOT) > 0.3
		and _apart(Tactical.RAIL_WARM_RIGHT, Tactical.HOT) > 0.3 and _apart(Tactical.RAIL_CALM_RIGHT, Tactical.EXIT_GREEN) > 0.3
		and (t.rail_mat.get_shader_parameter("calm_right") as Color).is_equal_approx(Tactical.RAIL_CALM_RIGHT)
		and (t.rail_mat.get_shader_parameter("warm_right") as Color).is_equal_approx(Tactical.RAIL_WARM_RIGHT)
		and t.rail_mesh.surface_get_format(0) & Mesh.ARRAY_FORMAT_COLOR != 0)

	# ---- the vehicles ----
	_place(v, e1, 4000, 1, 5000.0, 22.5)
	_settle(v, t)
	speed = 5000.0 / MPH
	var here: float = sim._road_f(sim.pod)
	var ahead_f := here + 4000.0 / 24.0
	var in_lane := _car(sim, 1, e1, ahead_f, 1, 22.5, 2500.0)
	var faster := _car(sim, 2, e1, ahead_f, 1, 22.5, 5600.0)
	var far_lane := _car(sim, 3, e1, ahead_f, 1, -157.5, 2500.0)
	var behind := _car(sim, 4, e1, here - 20.0, 1, 22.5, 2500.0)
	var beyond := _car(sim, 5, e1, here + 25000.0 / 24.0, 1, 22.5, 4800.0)      # 25 km on and barely gained on: over two minutes off
	var got: Array = t.pick([in_lane, faster, far_lane, behind, beyond], speed)
	var by_id := {}
	for g in got:
		by_id[int(g.car.id)] = g
	_check("a vehicle 4 km ahead in her lane doing 2,500 mph is marked, in her way, %.1f s off (4,000 m at a closing 2,500 mph is 3.6 s)" % float(by_id.get(1, {}).get("seconds", -1.0)),
		by_id.has(1) and bool(by_id[1].way) and absf(float(by_id[1].seconds) - 4000.0 / (2500.0 / MPH)) < 0.1 and absf(float(by_id[1].along) - 4000.0) < 30.0 and absf(float(by_id[1].left)) < 1.0)
	_check("one she is not gaining on, one behind her and one over two minutes off are not (%s marked)" % [by_id.keys()], not by_id.has(2) and not by_id.has(4) and not by_id.has(5))
	_check("one four lanes over is marked, not in her way (%.0f m to her right)" % -float(by_id.get(3, {}).get("left", 0.0)), by_id.has(3) and not bool(by_id[3].way) and absf(float(by_id[3].left) + 180.0) < 1.0)
	# a road crossing overhead: N1 over E1
	var cross_i := -1
	var cross_n := -1
	for i in range(200, int(E.N) - 200, 2):
		for near in sim.net_near(E.px[i], E.py[i]):
			if int(near[0]) == n1 and absf(float(near[2])) < 30.0 and cross_i < 0:
				cross_i = i
				cross_n = int(near[1])
		if cross_i >= 0:
			break
	var N = sim.roads[n1]
	var deck: float = sim.net_height(n1, float(cross_n)) - sim.net_height(e1, float(cross_i))
	var across: float = absf(N.tx[cross_n] * E.tx[cross_i] + N.ty[cross_n] * E.ty[cross_i])
	_place(v, e1, cross_i - 60, 1, 5000.0, 22.5)      # 1.4 km short of where N1 crosses
	_settle(v, t)
	var over := _car(sim, 6, n1, float(cross_n), 1, 0.0, 300.0)
	var over_along := _car(sim, 7, n1, float(cross_n), 1, 0.0, 300.0)      # the same deck, heading as E1 does
	over_along.hx = E.tx[cross_i]
	over_along.hy = E.ty[cross_i]
	var under := _car(sim, 8, e1, float(cross_i), 1, 22.5, 300.0)
	got = t.pick([over, over_along, under], speed)
	_check("N1 crosses over E1 at its sample %d, %.0f m up (the two roads' ways %.2f of one another): a vehicle on it there has no line, nor one on that deck heading as E1 does; one on E1 under it has (%d marked)" % [cross_i, deck, across, got.size()],
		cross_i > 0 and deck > 50.0 and got.size() == 1 and int(got[0].car.id) == 8)
	# a ramp running into her road, at her level, going her way: its vehicle counts though it is on another road
	var merging := _car(sim, 9, n1, float(cross_n), 1, 0.0, 300.0)
	merging.x = E.px[cross_i - 20] + E.nx[cross_i - 20] * 60.0
	merging.y = E.py[cross_i - 20] + E.ny[cross_i - 20] * 60.0
	merging.hx = E.tx[cross_i - 20]
	merging.hy = E.ty[cross_i - 20]
	merging.f = 0.0
	for r in sim.roads.size():      # (some road that is not hers, whose own height there is her road's here)
		if r != e1 and r != n1 and absf(sim.net_height(r, 0.0) - sim.net_height(e1, float(cross_i - 20))) < 1.0:
			merging.road = r
			break
	var level: bool = absf(sim.net_height(merging.road, 0.0) - sim.net_height(e1, float(cross_i - 20))) < Tactical.SAME_DECK
	got = t.pick([merging], speed)
	_check("a vehicle on another road that runs along hers at her level, 60 m to her left a kilometre on, has one (level with her: %s)" % level, level and got.size() == 1 and absf(float(got[0].left) - 37.5) < 2.0 and absf(float(got[0].along) - 960.0) < 60.0)
	# drawn, and thinned when the road is busy
	_place(v, e1, 4000, 1, 5000.0, 22.5)
	_settle(v, t)
	here = sim._road_f(sim.pod)
	v.traffic_net.cars.clear()
	v.traffic_net.cars.append(_car(sim, 11, e1, here + 6000.0 / 24.0, 1, 22.5, 2500.0))
	v.traffic_net.cars.append(_car(sim, 12, e1, here + 7000.0 / 24.0, 1, -157.5, 2500.0))
	for k in 80:
		t.sync(1.0 / 120.0, v._rush_flow, true)
	_check("two vehicles ahead, one in her way and one four lanes over: two lines drawn (%d), each eased in; the one in her way coloured by its %.1f s, the other calm and at %.0f%% strength" % [t.line_count, float(t.marks[11].seconds), t.line_tints[1].a * 100.0],
		t.lines.visible and t.line_count == 2 and t.lines.multimesh.visible_instance_count == 2 and t.marks.size() == 2 and float(t.marks[11].a) == 1.0 and not t.thinned
		and t.line_tints[0].is_equal_approx(Color(Tactical.soon_tint(float(t.marks[11].seconds)), 1.0)) and t.line_tints[1].is_equal_approx(Color(Tactical.CALM, Tactical.SIDE_LINE.y)))
	for k in 7:      # the road gets busy: seven more out of her way
		v.traffic_net.cars.append(_car(sim, 20 + k, e1, here + (2500.0 + 400.0 * k) / 24.0, 1, -112.5 if k % 2 == 0 else 112.5, 2500.0))
	for k in 80:
		t.sync(1.0 / 120.0, v._rush_flow, true)
	_check("nine ahead, one in her way: it thins to that one line (%d drawn)" % t.line_count, t.thinned and t.line_count == 1 and t.marks.has(11) and t.marks.size() == 1)
	v.traffic_net.cars.clear()
	for k in 80:
		t.sync(1.0 / 120.0, v._rush_flow, true)
	_check("the road clear again: no lines", not t.lines.visible and t.marks.is_empty() and not t.thinned)
	_check("seconds to a vehicle give its colour: calm at %.0f s and more, amber at %.1f, red by %.1f" % [Tactical.SOON.x, Tactical.SOON.y, Tactical.SOON.z],
		Tactical.soon_tint(9.0).is_equal_approx(Tactical.CALM) and Tactical.soon_tint(Tactical.SOON.y).is_equal_approx(Tactical.WARM) and Tactical.soon_tint(0.5).is_equal_approx(Tactical.HOT))

	# ---- the exits ----
	var lanes: Array = v.network_world.exit_lanes.get(e1, [])
	var lane: Array = []
	for row in lanes:      # the first exit going up E1's samples, well along it
		if int(row[2]) == 1 and int(row[5]) >= 0 and int(row[4]) > 3000 and lane.is_empty():
			lane = row
	var mouth := int(lane[4])
	var lead := Tactical.exit_lead(speed)
	_check("an exit's chevrons begin %.1f km before its mouth at 5,000 mph: seven seconds; at 8,000 mph %.1f s, at 1,000 mph %.0f s (never under 8 km)" % [lead / 1000.0, Tactical.exit_lead(8000.0 / MPH) / (8000.0 / MPH), Tactical.exit_lead(1000.0 / MPH) / (1000.0 / MPH)],
		is_equal_approx(lead, speed * 7.0) and Tactical.exit_lead(8000.0 / MPH) / (8000.0 / MPH) > 6.5 and is_equal_approx(Tactical.exit_lead(1000.0 / MPH), 8000.0))
	_place(v, e1, mouth - int((lead + 2000.0) / 24.0), 1, 5000.0)
	_settle(v, t)
	for k in 16:
		t.sync(1.0 / 120.0, v._rush_flow, true)
	var early: int = t.chevron_count
	var none_yet := true
	for e in t.exits_ahead(speed):
		none_yet = none_yet and (bool(e.join) or int(e.mouth) != mouth)
	_place(v, e1, mouth - int((lead - 500.0) / 24.0), 1, 5000.0)
	_settle(v, t)
	for k in 16:
		t.sync(1.0 / 120.0, v._rush_flow, true)
	var ex := {}
	for e in t.exits:
		if int(e.mouth) == mouth and int(e.to) == int(lane[5]) and not bool(e.join):
			ex = e
	_check("2 km before that there are none for it (%s; %d laid); half a kilometre inside it they are laid (%d), for the exit to %s on her %s" % [none_yet, early, t.chevron_count, sim.roads[int(lane[5])].name, "left" if float(ex.get("side", 0.0)) > 0.0 else "right"],
		none_yet and not ex.is_empty() and t.chevron_count > 20 and t.chevrons.visible and float(ex.side) == (1.0 if float(lane[3]) >= 0.0 else -1.0))
	# where they stand: on the lane's own line along E1, none nearer her than two and a half seconds, and on along the exit
	var here_f: float = sim._road_f(sim.pod)
	var nearest := INF
	var on_lane := 0
	var on_exit := 0
	var gates := 0
	var gate_at := Vector2.ZERO
	var gate_k := -1
	var points_out := true
	var out_way := Vector3(E.nx[mouth], 0.0, -E.ny[mouth]) * (1.0 if float(lane[3]) >= 0.0 else -1.0)
	var mine := 0
	var row: Array = []      # [m to the mouth, tier, its index in the MultiMesh]
	var laid_v: float = ex.v
	for idx in t.chev_laid.size():
		var laid: Array = t.chev_laid[idx]
		if String(laid[0]) != String(ex.key):
			continue
		mine += 1
		var xf: Transform3D = laid[1]
		var to_mouth: float = laid[2]
		var x: float = xf.origin.x + t._chev_ax
		var y: float = -xf.origin.z + t._chev_ay
		points_out = points_out and xf.basis.x.normalized().is_equal_approx(out_way) and is_equal_approx(xf.basis.x.length(), float(laid[4]))
		if String(laid[3]) == "gate":
			gates += 1
			gate_at = Vector2(x, y)
			gate_k = idx
		elif to_mouth > 0.0:
			var i := mouth - roundi(to_mouth / 24.0)
			var want := Vector2(E.px[i] + E.nx[i] * float(lane[3]), E.py[i] + E.ny[i] * float(lane[3]))
			on_lane += int(Vector2(x, y).distance_to(want) < 0.05)
			nearest = minf(nearest, (float(i) - here_f) * 24.0)
			row.append([to_mouth, float(laid[4]), idx])
		else:
			on_exit += 1
	# the row, in seconds at the speed it was laid for: the whole seconds big, halves between, quarters over the last two
	row.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	var expect := 0
	var expect_wholes := 0
	for q in range(1, 200):
		var back := roundi(q * 0.25 * laid_v / 24.0)
		if back > int(ex.from):
			break
		expect += int(q % 2 == 0 or q * 0.25 <= Tactical.CHEV_TIGHT + 0.001)
		expect_wholes += int(q % 4 == 0)
	var wholes_ok := true
	var gaps_ok := true
	var wholes := 0
	var tiers_ok := true
	for idx in row.size():
		var seconds: float = float(row[idx][0]) / laid_v
		var tier: float = row[idx][1]
		var is_whole := absf(seconds - roundf(seconds)) < 0.02
		var is_half := not is_whole and absf(seconds * 2.0 - roundf(seconds * 2.0)) < 0.04
		wholes += int(is_whole)
		wholes_ok = wholes_ok and (tier == Tactical.CHEV_TIER.x) == is_whole
		tiers_ok = tiers_ok and (tier == (Tactical.CHEV_TIER.x if is_whole else (Tactical.CHEV_TIER.y if is_half else Tactical.CHEV_TIER.z))) and (is_whole or is_half or seconds <= Tactical.CHEV_TIGHT + 0.02)
		var gap: float = (float(row[idx][0]) - (float(row[idx - 1][0]) if idx > 0 else 0.0)) / laid_v
		gaps_ok = gaps_ok and absf(gap - (0.25 if seconds <= Tactical.CHEV_TIGHT + 0.02 else 0.5)) < 0.03
	_check("%d stand on the lane's own line along E1 (%.0f m left of its middle), the nearest %.1f km ahead of her (2.5 s is %.1f km), %d more on along the exit; every one points the way the lane leaves, scaled by its tier" % [on_lane, float(lane[3]), nearest / 1000.0, speed * 2.5 / 1000.0, on_exit],
		on_lane == expect and on_lane + on_exit + gates == mine and t.chevrons.multimesh.visible_instance_count == t.chevron_count and nearest >= speed * Tactical.EXIT_CLEAR_S - 300.0 and on_exit == Tactical.CHEV_ON and points_out)
	_check("... laid in seconds at %.0f mph: %d at whole seconds before the mouth (the big ones), a quarter second apart over the last two and a half before that (%s), each sized by its place (%s)" % [laid_v * MPH, wholes, gaps_ok, tiers_ok],
		on_lane > 8 and wholes == expect_wholes and wholes_ok and gaps_ok and tiers_ok)
	var gate_want := Vector2(E.px[mouth] + E.nx[mouth] * float(lane[3]), E.py[mouth] + E.ny[mouth] * float(lane[3]))
	var gate_data: Color = t.chev_laid[gate_k][6] if gate_k >= 0 else Color()
	var gate_from_start: float = rad_to_deg(atan(Tactical.chev_half(speed * Tactical.EXIT_LEAD_S, absf(gate_data.a), 1.0, true) * Tactical.GATE_TALL / (speed * Tactical.EXIT_LEAD_S)))
	_check("one gate stands across the lane at the mouth (%.2f m off the lane's line there), its own half width %.0f m (the lane's rails stand 26 m out), %.1f degrees tall from where it begins" % [gate_at.distance_to(gate_want), -gate_data.a, gate_from_start],
		gates == 1 and gate_at.distance_to(gate_want) < 0.05 and gate_data.a <= -30.0 and gate_data.r == 0.0 and gate_from_start > 1.0)
	# as she nears: a whole second's chevron one second before the mouth, its half size as the eye sees it, by the
	# shaders' own rule (whose numbers are the ones the instance and the material carry)
	var one_s: Array = []
	for r in row:
		if absf(float(r[0]) / laid_v - 1.0) < 0.02:
			one_s = r
	var data: Color = t.chev_laid[int(one_s[2])][6] if not one_s.is_empty() else Color()
	var looks := []
	for s in [4.0, 3.0, 2.5, 2.0, 1.5, 1.0, 0.5]:
		var d: float = s * laid_v
		looks.append(rad_to_deg(atan(Tactical.chev_half(d, data.a, Tactical.CHEV_TIER.x) / d)))
	_check("seen from the seat, its half size %s degrees at 4, 3, 2.5, 2, 1.5, 1 and half a second from it: one size far off, then growing as she nears (own half size %.0f m, the shader's %.5f the material's)" % [str(looks.map(func(a): return snappedf(a, 0.01))), data.a, float(t.chev_mat.get_shader_parameter("chev_tan"))],
		not one_s.is_empty() and is_equal_approx(data.a, Tactical.chev_own(laid_v)) and absf(float(looks[0]) - float(looks[1])) < 0.01 and float(looks[3]) > float(looks[2]) * 1.05
		and float(looks[6]) > 3.5 * float(looks[0]) and float(looks[5]) > float(looks[4]) and is_equal_approx(float(t.chev_mat.get_shader_parameter("chev_tan")), tan(deg_to_rad(Tactical.CHEV_ANGLE))))
	var born: float = float(ex.born)
	_place(v, e1, mouth - int(4000.0 / 24.0), 1, 5000.0)
	_settle(v, t)
	for k in 16:
		t.sync(1.0 / 120.0, v._rush_flow, true)
	var still := {}
	for e in t.exits:
		if int(e.mouth) == mouth and int(e.to) == int(lane[5]) and not bool(e.join):
			still = e
	_check("flown on to 4 km short of it, its chevrons are the ones first laid (when, from where, and for what speed)", not still.is_empty() and float(still.born) == born and int(still.from) == int(ex.from) and float(still.v) == float(ex.v))
	_place(v, e1, mouth + 30, 1, 5000.0)
	_settle(v, t)
	for k in 16:
		t.sync(1.0 / 120.0, v._rush_flow, true)
	var gone := true
	for e in t.exits:
		gone = gone and not (int(e.mouth) == mouth and int(e.to) == int(lane[5]) and not bool(e.join))
	_check("past its mouth they are gone", gone)

	# ---- where ----
	_place(v, e1, 4000, 1, 0.0)
	for k in 120:
		t.sync(1.0 / 120.0, v._rush_flow, true)
	Tactical.tac_lines = 0
	for k in 360:
		t.sync(1.0 / 120.0, v._rush_flow, true)
	_check("standing still: nothing of it is shown, and nothing written to the log (%d lines in 3 s)" % Tactical.tac_lines, not t.rails.visible and not t.lines.visible and not t.chevrons.visible and not t.number.visible and t.amount == 0.0 and Tactical.tac_lines == 0)
	_place(v, e1, 4000, 1, 3000.0)
	for k in 120:
		t.sync(1.0 / 120.0, v._rush_flow, true)
	var words: String = t.number.text
	_check("at 3,000 mph: all of it, and the number reads \"%s\", %.0f m ahead of the seated eye and %.1f degrees over level" % [words, t.number.position.distance_to(v._rush_flow.origin), rad_to_deg(asin((v._rush_flow.affine_inverse() * t.number.position).y / Tactical.NUMBER_AHEAD))],
		t.rails.visible and t.number.visible and t.amount == 1.0 and words == "3,000" and absf((v._rush_flow.affine_inverse() * t.number.position).z + Tactical.NUMBER_AHEAD) < 0.01
		and absf((v._rush_flow.affine_inverse() * t.number.position).y - Tactical.NUMBER_AHEAD * tan(deg_to_rad(Tactical.NUMBER_ELEVATION))) < 0.01)
	for k in 120:
		t.sync(1.0 / 120.0, v._rush_flow, false)
	_check("from an outside camera, or while she is still being started: nothing", not t.rails.visible and not t.number.visible and t.amount == 0.0)
	sim.pod.off_road = true
	for k in 120:
		t.sync(1.0 / 120.0, v._rush_flow, true)
	_check("off the roads: the number alone", not t.rails.visible and not t.chevrons.visible and not t.lines.visible and t.number.visible)
	sim.pod.off_road = false
	var tube: int = sim.NET_PRESSURE[0]
	_place(v, tube, int(sim.NET_PRESSURE[1]) + 400, 1, 3000.0)
	for k in 120:
		t.sync(1.0 / 120.0, v._rush_flow, true)
	_check("in the Aurora tube: nothing", not t.rails.visible and not t.number.visible and t.amount == 0.0)
	# the cockpit's own frame, switched off again: the node goes
	_place(v, e1, 4000, 1, 3000.0)
	v.tactical = t
	Tactical.wanted = false
	v.tactical = Tactical.frame(v, v.tactical, 1.0 / 120.0, v._rush_flow, true)
	await process_frame
	_check("switched off: the node is freed, and nothing of it is left in the view", v.tactical == null and not is_instance_valid(t) and v.find_child("TacticalDisplay", true, false) == null)
	v.queue_free()
	await process_frame

	# ---- a closed course: the road ahead and the speed ----
	View.track_override = "gp"
	var c = Cockpit.new()
	root.add_child(c)
	await process_frame
	c.set_process(false)
	var cs = c.sim
	cs.respawn(-1, 150)      # 1.8 km down the first straight: its first two corners are inside twelve seconds
	for body in cs.bodies:
		body.vx = cs.ttx[150] * 268.0
		body.vy = cs.tty[150] * 268.0
	c._follow_origin()
	Tactical.wanted = true
	var ct = Tactical.frame(c, null, 1.0 / 120.0, c._rush_flow, true)
	for k in 600:
		ct.sync(1.0 / 120.0, c._rush_flow, true)
	var banked := 0
	var leans_in := 0
	var on_track := true
	for k in ct.st_s.size():
		var i: int = ct.st_i[k]
		on_track = on_track and is_equal_approx(ct.st_x[k], cs.tpx[i]) and ct.st_road[k] == 0
		if absf(cs.tb[i]) > deg_to_rad(5.0) and absf(ct.st_k[k]) > 1e-4:
			banked += 1
			leans_in += int(ct.lean_at(k) > deg_to_rad(4.0))
	_check("on the grand prix circuit at 600 mph: rails on its own samples (%d stations, %.1f km of them, twelve seconds), no chevrons, no lines; %d stations in its banked corners, the bank leaning into the bend at %d of them" % [ct.st_s.size(), (ct.st_s[ct.st_s.size() - 1] - ct.pod_s) / 1000.0, banked, leans_in],
		ct.rails.visible and on_track and ct.st_s.size() > 100 and not ct.chevrons.visible and not ct.lines.visible and banked > 5 and leans_in == banked and ct.number.visible and ct.number.text == "600")
	Tactical.wanted = false
	c.queue_free()
	await process_frame
	if prefs_before == "":
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Cockpit.PREFS))
	else:
		var out := FileAccess.open(Cockpit.PREFS, FileAccess.WRITE)
		out.store_string(prefs_before)
		out.close()
	View.track_override = ""
	print("TACTICAL DISPLAY %s (%d checks, %d failures)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)
