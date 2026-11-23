## The racing pilots of the Eridanus track (view/race_pilots.gd; Luke: "Add AI racing pilots to
## Eridanus to battle, target is 140 - 150 seconds").
##   the course    read out of the sim: its length, a reference lap, each pilot's pace solved to its lap
##   clean laps    the field alone for four laps: every flying lap in 140 to 150 s and on its own
##                 target, nobody off the usable road, nobody stalled, no two craft through each
##                 other, and places traded
##   round him     a slow craft on the loop, a stopped one on the line in a town bend, one that
##                 squeezes a pilot toward the wall: they go round with room or drop back, and are
##                 never one of his sim's obstacles at a smash's closing speed
##   his own lap   the recorded lap of the course (tests/replay/eridanus_inputs.json) flown through a
##                 real sim, collisions on, with the field racing round him: nobody touches him,
##                 and his lap is the same lap flown alone, to the last digit
##   in the view   gridded round him at the start line, standing until green; his place and the
##                 gaps on the HUD; a restart is a new grid; no pilots on the emergency run or a GP;
##                 the VR quick menu's RACING PILOTS line, on Eridanus only
## --headless --xr-mode off --audio-driver Dummy -s res://tests/test_race_pilots.gd -- --mute
## Prints RACE PILOTS PASS.
extends SceneTree

const View := preload("res://view/craft_view.gd")
const Cockpit := preload("res://vr/vr_cockpit.gd")
const Race := preload("res://view/race_pilots.gd")
const Sim := preload("res://sim/craft_sim.gd")
const DT := 1.0 / 60.0
var failures := 0
var checks := 0
var off_road := 0.0        # the furthest any pilot has been past the usable road (m)
var slowest := INF         # the slowest any has gone once under way
var near_him := INF        # the nearest a pilot's middle has come to the stand-in's while level with it
var held := 0.0            # s any pilot has spent held up
var swaps := 0
var _order := ""
var profile := preload("res://tests/race_review_settings.gd").new()


func _finalize() -> void:
	profile.restore()


func _initialize() -> void:
	profile.pin(Cockpit.PREFS)
	View.track_override = "eridanus"
	View.job_override = "none"
	View.best_dir = OS.get_user_data_dir().path_join("test_race_pilots_")
	Race.forced = "on"
	Cockpit.camera = "cockpit"
	Cockpit._camera_loaded = true      # the pilot's saved choices stay out of this
	Cockpit._nose_loaded = true
	Cockpit._slide_loaded = true
	Cockpit._startup_loaded = true
	Cockpit._map_loaded = true
	Cockpit._school_loaded = true
	Cockpit.cold_start = false
	Cockpit.school = false
	_run.call_deferred()


func _check(label: String, passed: bool) -> void:
	checks += 1
	print(("PASS " if passed else "FAIL ") + label)
	failures += int(not passed)


func _reset_watch() -> void:
	off_road = 0.0
	slowest = INF
	near_him = INF
	held = 0.0
	swaps = 0
	_order = ""


## A stretch of the race, a step at a time; `each` moves the stand-in before each step.
func _race(r, seconds: float, each := Callable()) -> void:
	for k in int(seconds / DT):
		if each.is_valid():
			each.call(DT)
		r.step(DT)
		var order := ""
		var ranked: Array = r.pilots.duplicate()
		ranked.sort_custom(func(a, b): return a.prog > b.prog)
		for p in ranked:
			order += p.name[0] + p.name[1]
			off_road = maxf(off_road, absf(p.lat) - r.room[p.i])
			if r.clock > 30.0:
				slowest = minf(slowest, p.v)
			if p.blocked:
				held += DT
			if not r.player.is_empty() and absf(r._gap(p.s, float(r.player.s))) < Race.LEN:
				near_him = minf(near_him, absf(p.lat - float(r.player.lat)))
		if _order != "" and order != _order:
			swaps += 1
		_order = order


func _run() -> void:
	# ---- the course, and the paces ----
	var sim = Sim.new({"track": "eridanus"})
	var r = Race.new()
	r.build(null, sim)
	var paces := []
	var solved := true
	for p in r.pilots:
		var t: float = r.lone_lap(p.f_town, p.f_loop, p.lane)
		paces.append("%s %.2f/%.2f" % [p.name, p.f_town, p.f_loop])
		solved = solved and absf(t - p.lap_target) < 0.1 and p.lap_target >= 140.0 and p.lap_target <= 150.0
	_check("the course is read: %.1f km round, a reference lap of %.1f s (%.1f s of it in the towns), top %.0f mph on the loop and %.0f in a town" % [
		r.length / 1000.0, r.reference_lap, r.town_time, Race.V_LOOP * 2.236936, Race.V_TOWN * 2.236936],
		absf(r.length - sim.track_length) < 1.0 and r.length > 190000.0 and absf(r.reference_lap - 141.8) < 0.5)
	_check("five pilots, each a share of that lap in town and on the loop, solved to its own lap time (%s)" % ", ".join(paces), r.pilots.size() == 5 and solved)
	# ---- the field alone ----
	r.ghost = true
	r.lap_limit = 5
	_reset_watch()
	var t0 := Time.get_ticks_usec()
	_race(r, 4.0 * 150.0 + 20.0)
	var per_step := float(Time.get_ticks_usec() - t0) / (int((4.0 * 150.0 + 20.0) / DT))
	var told := []
	var in_window := true
	var on_target := true
	var counted := 0
	var varied := true
	for p in r.pilots:
		var flying: Array = p.laps.slice(1)  # every first lap includes the launch
		var lo := INF
		var hi := -INF
		for lap in flying:
			lo = minf(lo, lap)
			hi = maxf(hi, lap)
			in_window = in_window and lap >= 140.0 and lap <= 150.0
			on_target = on_target and absf(lap - p.lap_target) < 1.0
		varied = varied and hi - lo > 0.08
		counted += flying.size()
		told.append("%s %.1f-%.1f of %.1f (%d)" % [p.name, lo, hi, p.lap_target, flying.size()])
	_check("the field alone for four laps: every flying lap in 140 to 150 s (%s)" % ", ".join(told), in_window and counted >= 12)
	_check("... each within a second of its target and every pilot varies by lap", on_target and varied)
	_check("nobody left the usable road (the furthest past it %.1f m) and nobody stalled (the slowest any went under way, %.0f mph)" % [maxf(0.0, off_road), slowest * 2.236936],
		off_road < 2.0 and slowest > 150.0)
	_check("no two went through each other: level, their middles were never nearer than %.1f m (a craft is 8.4 m across)" % r.closest, r.closest > 15.0)
	_check("they race each other: the order changed %d times in four laps, and one was held up for %.1f s in all" % [swaps, held], swaps >= 2 and held < 60.0)
	print("COST the race alone: %.0f us a frame for five pilots (this machine, loaded or not; the budget for the field is 1,000)" % per_step)
	_check("a frame of the race costs under a millisecond (%.0f us)" % per_step, per_step < 1000.0)
	# ---- round him: a slow craft on the loop ----
	r.ghost = false
	_heat_checks(r)
	r.grid()
	r.go()
	r.player = {"s": 30000.0, "lat": 40.0, "v": 600.0}
	_reset_watch()
	r.closest = INF
	_race(r, 200.0, func(dt): r.player.s = fposmod(float(r.player.s) + float(r.player.v) * dt, r.length))
	var past := 0
	for p in r.pilots:
		past += int(p.prog > 30000.0 + 600.0 * 200.0)
	_check("a craft at 1,340 mph on the loop, 40 m left of the middle: all %d went by it, the nearest of them %.1f m off its middle as they passed, held up %.1f s" % [past, near_him, held],
		past == 5 and near_him >= 20.0 and held < 5.0)
	# ---- a stopped craft on the line in a town bend ----
	r.grid()
	var at := 5200.0
	var i_at: int = r._sample(at, 0)
	r.player = {"s": at, "lat": r.nominal(i_at, 0.0), "v": 0.0}
	_reset_watch()
	r.go()
	_race(r, 60.0)
	past = 0
	for p in r.pilots:
		past += int(p.prog > at + 500.0)
	_check("a craft stopped on the racing line in the first town's second bend (%.0f m from the wall's side): all %d went round it, none nearer than %.1f m, held up %.1f s" % [r.room[i_at] - absf(float(r.player.lat)), past, near_him, held],
		past == 5 and near_him >= 20.0 and held < 8.0)
	# ---- squeezed toward the wall on the start straight ----
	r.grid()
	r.player = {}
	r.ghost = true
	r.go()
	_race(r, 2.0)
	r.ghost = false
	var victim = r.pilots[0]
	r.player = {"s": victim.s, "lat": victim.lat - 30.0, "v": victim.v}
	_reset_watch()
	var gave := [victim.lat, victim.lat]
	# (the stand-in pushes on as the pilot would, left alone: level with it until it gives way)
	var squeeze := func(dt: float) -> void:
		var j: int = r._sample(float(r.player.s), victim.i)
		var free: float = victim.f_town * r.env[j]
		r.player.v = minf(free, float(r.player.v) + Race.push_at(float(r.player.v), r.power[j]) * victim.f_town * dt)
		r.player.s = fposmod(float(r.player.s) + float(r.player.v) * dt, r.length)
		r.player.lat = minf(float(r.player.lat) + 8.0 * dt, r.room[j] + 4.0)
		gave[1] = maxf(gave[1], victim.lat)
	_race(r, 6.5, squeeze)
	var dropped: float = -r._gap(float(r.player.s), victim.s)
	_check("a craft level with %s and moving across at it on the start straight: it gave %.0f m of road, then dropped %.0f m back; never nearer than %.1f m while level" % [victim.name, gave[1] - gave[0], dropped, near_him],
		gave[1] - gave[0] > 10.0 and near_him > 12.0 and dropped > Race.LEN)
	# ---- one of his sim's obstacles, never at a smash ----
	r.player = {}
	var p0 = r.pilots[2]
	sim.pod.x = p0.x - sin(p0.th) * 40.0
	sim.pod.y = p0.y + cos(p0.th) * 40.0
	sim.pod.vx = cos(p0.th) * p0.v
	sim.pod.vy = sin(p0.th) * p0.v
	r._feed_obstacles()
	var beside: int = sim.obstacles.size()
	var ids := []
	for o in sim.obstacles:
		ids.append(o.id)
	sim.pod.vx = 0.0
	sim.pod.vy = 0.0
	r._feed_obstacles()
	_check("flying beside %s at its speed it is two forcefields in his sim (%s); standing in its road as it comes at %.0f mph it is none (a smash is 1,500)" % [p0.name, ids, p0.v * 2.236936],
		beside >= 2 and ids.has("race:%s:pod" % p0.name) and sim.obstacles.is_empty() and p0.v > Race.TANGIBLE_V)
	_check("no pilots on the emergency run or a grand prix", not Race.available(Sim.new({"track": "eridanus", "job": "emergency"})) and not Race.available(Sim.new({"track": "gp"})) and Race.available(sim))
	r.free()
	# ---- his own recorded lap, among them ----
	var inputs: Array = JSON.parse_string(FileAccess.get_file_as_string("res://tests/replay/eridanus_inputs.json"))
	var flown = Sim.new({"track": "eridanus"})
	var alone = Sim.new({"track": "eridanus"})
	var alone_lap := -1.0
	var field = Race.new()
	field.build(null, flown)
	field.lap_limit = 1
	for tick in 180:
		field.step(DT)
	var touches := 0
	var his_lap := -1.0
	var identical := true
	var tangible := 0
	var level := INF
	var where := ""
	var his_lat := 0.0
	for u in inputs:
		var inp := {"thrL": u[0], "thrR": u[1], "brkL": u[2], "brkR": u[3], "repair": false, "reignite": true}
		if int(u[4]) > 0:
			inp["handling"] = ["", "speed", "starfighter"][int(u[4])]
		for k in 8:
			flown.step(inp, 1.0 / 480.0)
			alone.step(inp, 1.0 / 480.0)
		for body in flown.bodies.size():
			var a: Sim.Body = alone.bodies[body]
			var b: Sim.Body = flown.bodies[body]
			identical = identical and a.x == b.x and a.y == b.y and a.z == b.z and a.vx == b.vx and a.vy == b.vy and a.th == b.th
		for e in alone.events:
			if e.type == "lap":
				alone_lap = e.t
		alone.events.clear()
		for e in flown.events:
			if e.type == "bump" or e.type == "smash":
				touches += 1
			elif e.type == "lap":
				his_lap = e.t
		flown.events.clear()
		field.step(DT)
		field._feed_obstacles()
		tangible += int(not flown.obstacles.is_empty())
		for p in field.pilots:
			if absf(field._gap(p.s, float(field.me.s))) < Race.LEN and absf(p.lat - float(field.me.lat)) < level:
				level = absf(p.lat - float(field.me.lat))
				where = "%s at %.1f s, %.1f km round: it %.0f m left of the middle at %.0f mph making for %.0f, the craft %.0f m left at %.0f mph and crossing at %.1f m/s, %.0f m ahead of it" % [
					p.name, field.clock, float(field.me.s) / 1000.0, p.lat, p.v * 2.236936, p.target, float(field.me.lat), float(field.me.v) * 2.236936, (float(field.me.lat) - his_lat) / DT, field._gap(p.s, float(field.me.s))]
		his_lat = float(field.me.lat)
	_check("a recorded lap of the course (%.2f s, %d frames of a pilot's hands) flown with collisions on and the field racing round it: nobody touched it (%d touches; the nearest level with it %.1f m; they were its sim's obstacles for %d frames), and the lap is the same lap flown alone (%.2f s) to the last digit, every frame matching all three bodies in position, planar velocity and heading" % [
		his_lap, inputs.size(), touches, level, tangible, alone_lap],
		bool(flown.P.obstacleCollisions) and touches == 0 and tangible > 60 and level > 20.0 and his_lap > 0.0 and his_lap == alone_lap
		and identical)
	print("NEAREST " + where)
	_check("... and the race round him was a race: green released the field, the two gridded behind went by him, and he ended it sixth (\"%s\")" % field.line(), field.started and field.place == 6)
	_check("the replay crosses the sim-validated finish, is classified sixth and has a best lap", field.you.laps.size() == 1 and is_finite(field.you.finish) and field.you.best == field.you.finish and field.page().begins_with("FINISH  P6"))
	field.free()
	# ---- in the view ----
	var v = View.new()
	root.add_child(v)
	await process_frame
	v.set_process(false)
	var race = v.race
	var slots := []
	var grid_ok: bool = race != null and race.pilots.size() == 5
	if grid_ok:
		for p in race.pilots:
			# (along the road and across it: behind the line the road is the last bend's end, so a slot 100 m
			# back is 5 m off the straight through his craft)
			var along: float = race._gap(0.0, p.s)
			var straight: float = (p.x - v.sim.pod.x) * cos(v.sim.pod.th) + (p.y - v.sim.pod.y) * sin(v.sim.pod.th)
			slots.append("%s %+.0f/%+.0f" % [p.name, along, p.lat])
			grid_ok = grid_ok and absf(along - p.slot.x) < 0.5 and absf(p.lat - p.slot.y) < 0.5 and absf(straight - p.slot.x) < 6.0 and p.node != null and p.node.get_parent() == race
		for k in 30:
			race.update(1.0 / 90.0)
		for p in race.pilots:
			grid_ok = grid_ok and p.v == 0.0
	_check("in the view: five craft gridded round him at the start line, m ahead / m left of him (%s), standing while he stands" % ", ".join(slots), grid_ok and not race.started)
	_check("one red start lamp, two dark; no race sound nodes in a muted flight", race._bridge.lamps[0].material_override == race._bridge.red and race._bridge.lamps[1].material_override == race._bridge.dark and race._sound == null)
	var whole_then := 0
	for p in race.pilots:
		whole_then += int(p.whole and p.pod.visible and not p.far.visible)
	# left standing on his own place while they go: the two behind him go round him
	v.sim.lap_start = 0.0
	race.go()
	for k in 450:
		race.update(1.0 / 90.0)
		race.page()
	var gone := 0
	for p in race.pilots:
		gone += int(p.prog > 300.0)
	var page_then: String = race.page()
	_check("left standing on the line as they go, the two gridded behind him go round him: 5 s on all %d are past (\"%s\")" % [gone, race.line()], gone == 5 and race.place == 6)
	for k in 1800:
		race.update(1.0 / 90.0)
		race.page()
	_check("the glass carries the race while there is one to read (5 s on: \"%s\") and is clear once they have gone (25 s on, the nearest %.0f s ahead: \"%s\"); the HUD's line still has his place (\"%s\")" % [
		page_then.replace("\n", " / "), float(race.ahead.s), race.page(), race.line()],
		page_then.begins_with("PLACE  6 / 6") and race.page() == "" and float(race.ahead.s) > 4.0 and race.line().begins_with("P6 OF 6"))
	var blocks_now := 0
	var nearest_m := INF
	for p in race.pilots:
		blocks_now += int(not p.whole and p.far.visible and not p.pod.visible and not p.engines[0].visible and p.node.visible)
		nearest_m = minf(nearest_m, Vector2(p.x - v.sim.pod.x, p.y - v.sim.pod.y).length())
	_check("near him a pilot is drawn whole (%d of 5 on the grid), far off as three plain blocks in its colour (%d of 5 at 25 s, the nearest %.1f km away)" % [whole_then, blocks_now, nearest_m / 1000.0],
		whole_then == 5 and blocks_now == 5 and nearest_m > Race.WHOLE_R)
	v.sim.lap_start = -1.0
	race.grid()
	race.update(1.0 / 90.0)
	_check("his place on the grid: \"%s\"; and on the glass \"%s\"" % [race.line(), race.page().replace("\n", " / ")],
		race.place == 4 and race.line().begins_with("GRID 4 OF 6") and race.page().begins_with("GRID  4 / 6") and v._progress_text().contains("\nGRID 4 OF 6"))
	for tick in 270:
		race.update(1.0 / 90.0)
	_check("all three lights turn green together", race._bridge.lamps.all(func(lamp): return lamp.material_override == race._bridge.green))
	v.sim.pod.vx = 12.0 * cos(v.sim.pod.th)
	v.sim.pod.vy = 12.0 * sin(v.sim.pod.th)
	v.sim.lap_start = 0.0                # (his first move: the sim's own lap clock has started)
	for k in 270:
		race.update(1.0 / 90.0)
	var moving := 0
	for p in race.pilots:
		moving += int(p.v > 50.0)
	_check("green releases them, each on its own reaction: 3 s on all %d are away; the HUD's line is \"%s\"" % [moving, race.line()],
		race.started and moving == 5 and race.line().begins_with("P") and race.line().contains("AHEAD") and race.page().begins_with("PLACE  "))
	for k in 200:
		race.update(1.0 / 90.0)
	v.sim.obstacles = [{"id": "race:old"}]
	v._respawn()
	_check("regrid clears the previous heat's obstacles before the next sim step", v.sim.obstacles.is_empty())
	race.update(1.0 / 90.0)
	var back := true
	for p in race.pilots:
		back = back and p.v == 0.0 and absf(p.prog - p.slot.x) < 0.01
	_check("a restart is a new grid: everyone back in place and standing, the clock at nothing", back and not race.started)
	v.set_racers(false)
	_check("switched off they are gone, and his sim's obstacles with them", v.race == null and v.sim.obstacles.is_empty() and not v._progress_text().contains("\n"))
	v.queue_free()
	await process_frame
	# ---- the VR cockpit's quick menu ----
	var c = Cockpit.new()
	root.add_child(c)
	await process_frame
	c.set_process(false)
	var first := []
	for item in c._menu_items():
		first.append(item.key)
	c._menu_page = "options"       # (the pilots' line is on the OPTIONS page: the first page is full at ten lines)
	var keys := []
	for item in c._menu_items():
		keys.append(item.key)
	var at_racers := keys.find("racers")
	c.menu.items = c._menu_items()
	c.menu.open = true
	c.menu.at = at_racers
	var was_on: bool = c.race != null
	c.menu_choose()
	var off_now: bool = c.race == null
	Race.forced = ""
	var saved_off: bool = not Race.wanted(PackedStringArray())
	c.menu_choose()
	var on_again: bool = c.race != null and Race.wanted(PackedStringArray())
	Race.forced = "on"
	_check("the VR quick menu's OPTIONS page on Eridanus has RACING PILOTS (%s; the first page has OPTIONS and not the pilots: %s): it switches them off and on, and the choice is saved" % [keys, first],
		at_racers >= 0 and first.has("options") and not first.has("racers") and keys.has("back") and was_on and off_now and saved_off and on_again)
	for key in ["race_pace", "race_laps"]:
		c.menu.at = keys.find(key)
		c.menu_choose()
	var next: Array = c.race.menu_rows()
	_check("choices are saved for the next grid; this race keeps its starting rules", next[0].value == "EXPERT" and next[1].value == "5" and c.race.pace == "club" and c.race.lap_limit == 3)
	c._respawn()
	_check("Y regrids everyone with the chosen length and pace", c.race.pace == "expert" and c.race.lap_limit == 5 and c.race.pilots[4].lap_target == 135.5 and c.race.you.laps.is_empty())
	c.startup.cold()
	for k in 300:
		c.race.step(DT)
	_check("a cold cockpit holds the lights and all five grid slots", not c.race.started and c.race.lights == Race.COUNTDOWN)
	await _sound_check(c)
	c.queue_free()
	await process_frame
	print("RACE PILOTS %s (%d checks, %d failures)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)

func _heat_checks(r) -> void:
	r.lap_limit = 1
	r.grid()
	r.player = {"s": 0.0, "lat": 0.0, "v": 0.0}
	for tick in 119:
		r.step(DT)
	_check("red countdown holds the grid, including the two pilots behind the stripe", not r.started and r.page().contains("START IN   2") and r.pilots[4].prog == -90.0)
	r.player.s = 12.0
	r.step(DT)
	_check("jumping the start calls for a regrid without moving the craft", r.false_start and r.page().contains("REGRID") and r.player.s == 12.0)
	r.player.s = 0.0
	r.grid()
	for tick in 180:
		r.step(DT)
	_check("green at three seconds, a common clock and no phantom lap for a rear row", r.started and r.clock == 0.0 and r.page().contains("GREEN") and r.pilots[4].laps.is_empty())
	# A legal overlap makes the rival stay alongside. Coming into its space still gives
	# the avoidance search authority to open up clearance.
	var rival = r.pilots[2]
	rival.s = 30000.0
	rival.i = r._sample(rival.s, 0)
	rival.lat = -33.0
	rival.v = 1300.0
	r.player = {"s": rival.s, "lat": 0.0, "v": 1310.0}
	r._read_player()
	r._plan(rival, DT)
	r.clock = 10.0
	rival.prog = r.me.prog
	r._rank()
	_check("spotter identifies the rival and the side it actually occupies", r.page().contains(rival.name + " ALONGSIDE RIGHT"))
	_check("a matched-speed overlap holds the occupied lane, with a full passing lane left", rival.target == -33.0 and rival.alongside == -33.0)
	var mouths := 0
	for i in r.n:
		if r.sim.tmode[i] == 0 and r.sim.tmode[i-1] == 1:
			var far: int = r._sample(fposmod(r.cum[i]-9600.0,r.length), 0)
			var near: int = r._sample(fposmod(r.cum[i]-4000.0,r.length), far)
			mouths += int(r.env[far] > r.env[near] + 270.0 and r.env[near] < 1150.0)
	_check("both town entries are already braking at the recorded pilot's six-mile mark and below 1,150 m/s with 4 km left", mouths == 2)
	r.grid()
	r.player = {"s": 0.0, "lat": 0.0, "v": 0.0}
	r.go()
	# Complete a race without rendering. Read every post-finish page, including pilots
	# whose finishes arrive later than the player's, then ensure a second lap cannot rewrite it.
	var pages := ""
	for tick in int(185.0 / DT):
		r.player.v = r.length / 150.0
		r.player.s = fposmod(float(r.player.s) + r.player.v * DT, r.length)
		r.step(DT)
		if is_finite(r.you.finish) and tick % 60 == 0:
			pages += r.page() + "\n"
	var all_six := true
	for entry in r.entrants:
		all_six = all_six and pages.contains(entry.name) and entry.laps.size() == 1 and entry.best == entry.finish
	_check("all six classified with actual gaps and best laps (P%d, %.3f)" % [r.place, r.you.finish], all_six and pages.contains("+") and pages.contains("BEST") and absf(r.you.finish - 150.0) < 0.01 and r.place > 1 and r.place < 6)
	var classified: Array = r.entrants.duplicate()
	classified.sort_custom(r._classified)
	var exact := true
	for row in classified.size():
		var entry = classified[row]
		var gap := Race._time(entry.finish) if row == 0 else "+%.2f S" % (entry.finish - classified[0].finish)
		exact = exact and pages.contains("%d  %s   %s" % [row + 1, entry.name, gap])
	_check("each displayed place and hundredth-second gap agrees with the recorded stripe times", exact)
	var locked: float = r.you.finish
	var position: int = r.place
	r.player.s += 12000.0
	r.step(DT)
	_check("post-finish flying cannot change time or place", r.you.finish == locked and r.place == position)
	r.player = {}
	r.pace = "ace"
	r.grid()
	_check("Ace targets bracket a 134.94 s PB; regrid clears classification", r.pilots[4].lap_target == 130.5 and r.pilots[0].lap_target == 139.5 and not is_finite(r.you.finish))
	r.lap_limit = 3
	r.player = {"s": 0.0, "lat": 0.0, "v": 0.0}
	r.grid()
	r.go()
	var split := false
	for tick in int(445.0 / DT):
		var target: float = [139.0, 135.0, 137.0][mini(r.you.laps.size(), 2)]
		r.player.v = r.length / target
		r.player.s = fposmod(float(r.player.s) + r.player.v * DT, r.length)
		r.step(DT)
		if tick % 60 == 0:
			split = split or r.page().begins_with("FINAL LAP  3 / 3")
	var ace_quick: float = r.pilots[4].best
	var ace_trailing: float = r.pilots[0].best
	_check("three-lap Ace race from lights to flag; personal best is the middle lap and the glass called the final lap", split and r.you.laps.size() == 3 and absf(r.you.best - 135.0) < 0.02 and absf(r.you.finish - 411.0) < 0.02)
	_check("actual Ace flying pace brackets Luke's 134.94 s: %.2f to %.2f" % [ace_quick, ace_trailing], ace_quick < 134.94 and ace_trailing > 134.94 and ace_trailing < 142.0)
	r.pace = "club"
	r.player = {}

func _sound_check(c) -> void:
	# Give this muted cockpit just the race voices. Capture the actual mix at the seat.
	var r = c.race
	r._sound = preload("res://audio/race_audio.gd").new()
	r._sound.build(r, r.pilots.size())
	root.audio_listener_enable_3d = true
	var capture := AudioEffectCapture.new()
	capture.buffer_length = 1.0
	var idx := AudioServer.get_bus_effect_count(0)
	AudioServer.add_bus_effect(0, capture)
	r.go()
	await create_timer(0.45).timeout
	var green := _mixed_peak(capture)
	r._sound.green.stop()
	var p = r.pilots[0]
	p.x = c.sim.pod.x + 14.0
	p.y = c.sim.pod.y
	p.v = 620.0
	p.th = PI
	r._sound.sync(r)
	var voice: AudioStreamPlayer3D = r._sound.voices[0]
	var approach_pitch := voice.pitch_scale
	p.th = 0.0
	r._sound.sync(r)
	await create_timer(0.30).timeout
	var engine := _mixed_peak(capture)
	_check("recorded green and positional engine reach the stereo bus (peaks %.4f, %.4f); pitch drops as the rival recedes" % [green, engine], green > 0.001 and engine > 0.001 and maxf(green, engine) < 1.0 and approach_pitch > voice.pitch_scale)
	p.x += 1500.0
	r._sound.sync(r)
	_check("out of earshot the voice stops, regrid silences all cues", not voice.playing)
	r.grid()
	_check("the start and all five loops are silent on the new grid", not r._sound.green.playing and r._sound.voices.all(func(v): return not v.playing))
	AudioServer.remove_bus_effect(0, idx)


func _mixed_peak(capture: AudioEffectCapture) -> float:
	var peak := 0.0
	for frame in capture.get_buffer(capture.get_frames_available()):
		peak = maxf(peak, maxf(absf(frame.x), absf(frame.y)))
	return peak
