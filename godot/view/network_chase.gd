## Chase mode on the Network (Luke: "we need a police variant of the vehicle and a chase mode").
## Which way round depends on what the pilot flies (the menus' Craft row):
##   in the patrol craft   PURSUIT: a runner appears ahead and flees along the roads, taking exits as
##                         it likes; hold within CATCH_R of it for CATCH_T seconds and it is caught;
##                         let it get LOSE_R away for LOSE_T and it is lost
##   in a racer            GETAWAY: a patrol comes up behind, lights and siren going, and follows
##                         wherever you turn; if it holds within BUST_R of you for BUST_T you are
##                         busted; get LOSE_R clear of it for LOSE_T and you have escaped
## The other craft is one of traffic's own: a Car driven by network_traffic.gd's driver (its speed
## limits for curves and towns, its junctions), in the racer's slot so it is kept and driven every
## frame. This sets its speed and reads the gap; and draws it as a pod and two engines in its own
## livery (the driving partner's renderer), with a light bar and a siren when it is the patrol.
##   var chase := Chase.new(); view.add_child(chase); chase.build(view, view.traffic_net)
##   chase.update(delta)                  every frame, after traffic's own update
##   chase.text()                         the dash's line while one is on ("" otherwise)
##   chase.result                         "caught" | "lost" | "busted" | "escaped", once, for the view to take
extends "res://view/driving_partner.gd"

const Livery := preload("res://view/livery.gd")
const LightBar := preload("res://view/light_bar.gd")
const Settings := preload("res://release/game_settings.gd")
const Synth := preload("res://audio/course_audio.gd")
const Finishes := preload("res://view/craft_materials.gd")
const Traffic := preload("res://view/network_traffic.gd")
const MPH := 2.236936
const CRAFTS := [["racer", "Racer"], ["patrol", "Patrol"]]       # the menus' rows: [id, name]
const MODES := [["off", "Off"], ["on", "On"]]
const START_AFTER := 10.0        # s on a public road at speed before the first begins
const NEXT_AFTER := 25.0         # ... and between one and the next
const RUN_AHEAD := 1400.0        # m: a runner appears this far ahead
const COME_BEHIND := 1800.0      # ... a patrol this far behind
const LINGER := 6.0              # s it stays by you once it is over (caught, or with you pulled over)
const CATCH_R := 90.0
const CATCH_T := 4.0
const BUST_R := 80.0
const BUST_T := 5.0
const LOSE_R := 7000.0
const LOSE_T := 15.0
const RUNNER_TOP := 4300.0       # mph flat out, when you are on it
const RUNNER_EASE := 2900.0      # ... and when you are far back (it does not vanish over the horizon at once)
const RUNNER_GRIP := 8.0         # g in the bends
const RUNNER_TURNS := 0.45       # how often it takes an exit
const RUNNER_LIVERY := "crimson"
const PATROL_TOP := 6200.0       # (the craft's own best is past 6,000 on the ramjet: it is lost in the bends and at the exits, or flat out)
const PATROL_GRIP := 9.5

static var craft := "racer"      # what the pilot flies: "racer" or "patrol"
static var enabled := false      # chase mode
static var pinned := false       # a test or a render chose them: the saved choices do not replace them

var traffic
var car = null                   # traffic's Car, while one is on
var role := ""                   # "pursuit": you are the patrol, it runs; "getaway": it is the patrol, you run
var state := ""                  # "" waiting for the next | "on" | "over" (it lingers a few seconds)
var result := ""
var tally := {"caught": 0, "lost": 0, "busted": 0, "escaped": 0}
var gap := 0.0                   # m between the two, straight line
var bar: Node3D                  # its light bar (the patrol's)
var siren: AudioStreamPlayer3D
var _clock := 0.0
var _near := 0.0
var _far := 0.0
var _count := 0
var _linger := 0.0


static func ids(rows: Array) -> Array:
	return rows.map(func(entry): return entry[0])


static func load_saved() -> void:
	if not pinned:
		craft = Settings.choice("craft", ids(CRAFTS))
		enabled = Settings.choice("chase", ids(MODES)) == "on"


func build(v) -> void:           # (set `traffic` first: view.traffic_net)
	view = v
	sim = v.sim
	name = "network_chase"
	role = "pursuit" if craft == "patrol" else "getaway"
	var wears := RUNNER_LIVERY if role == "pursuit" else "police"
	var own := Livery.current
	Livery.current = wears          # (a craft's colours are in its meshes: build these in its livery, then back)
	var lit := Kit.vertex_colors(true)
	_flame_mat = StandardMaterial3D.new()
	_flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flame_mat.albedo_color = Color(1.0, 0.6, 0.25)
	var cable_mat := StandardMaterial3D.new()
	cable_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cable_mat.albedo_color = Color(0.45, 0.85, 1.0)
	for k in 2:
		var out := -1.0 if k == 0 else 1.0
		var eng := Node3D.new()
		add_child(eng)
		_engines.append(eng)
		var body := MeshInstance3D.new()
		body.mesh = CraftModelScript._engine_body(out)
		body.material_override = Finishes.painted_metal()
		body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		eng.add_child(body)
		var lights := MeshInstance3D.new()
		lights.mesh = CraftModelScript._engine_lights(out)
		lights.material_override = lit
		lights.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		eng.add_child(lights)
		var fl := MeshInstance3D.new()
		fl.mesh = Kit.box(Vector3(CraftModelScript.ENG_W - 0.6, 0.4, 1.0))
		fl.material_override = _flame_mat
		fl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		eng.add_child(fl)
		_flames.append(fl)
		var c := MeshInstance3D.new()
		c.mesh = Kit.box(Vector3(0.12, 0.12, 1.0))
		c.material_override = cable_mat
		c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(c)
		_cables.append(c)
	_pod = MeshInstance3D.new()
	_pod.mesh = CraftModelScript.pod_hull()
	_pod.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_pod)
	Livery.current = own
	if role == "getaway":           # it is the patrol: its lights, and its siren where it is
		bar = LightBar.new()
		_pod.add_child(bar)
		bar.build(LightBar.ON_FIN, 0.5)
		if view.get("engine_audio") != null:      # (a muted flight has no sound of any kind)
			siren = AudioStreamPlayer3D.new()
			siren.stream = wail()
			siren.volume_db = -4.0
			siren.unit_size = 60.0
			siren.max_distance = 4000.0
			_pod.add_child(siren)
	visible = false
	_clock = 0.0


## A siren's wail: a tone swept up and down between 620 and 1,380 Hz, as a seamless loop.
static func wail(seconds := 1.6, rate := 22050) -> AudioStreamWAV:
	var n := int(seconds * rate)
	var tail := rate / 20
	var l := PackedFloat32Array()
	l.resize(n + tail)
	var phase := 0.0
	for i in n + tail:
		var t := fposmod(float(i) / rate, seconds) / seconds
		var up := 0.5 - 0.5 * cos(TAU * t)
		var hz := lerpf(620.0, 1380.0, up)
		phase += TAU * hz / rate
		l[i] = 0.62 * sin(phase) + 0.26 * sin(2.0 * phase) + 0.12 * sin(3.0 * phase)
	return Synth._wav(l, l.duplicate(), rate, 0.5, n)


## Is the pilot where one can begin: on an open public road, at speed, with no racer about?
func _ready_for_one() -> bool:
	var P = sim.pod
	if P.off_road or traffic.race_state != "":
		return false
	var R = sim.roads[P.path]
	return traffic._public_road(R) and not R.shaft and R.w[0] >= 180.0 and Vector2(P.vx, P.vy).length() > 900.0 / MPH


func _begin() -> bool:
	var pc = traffic._pod_as_car()
	if pc == null:
		return false
	var c := Traffic.Car.new()
	c.id = 950000 + _count
	c.kind = Traffic.RACER          # the racer's slot: kept, driven every frame, never turned round
	c.chase = "fugitive" if role == "pursuit" else "pursuer"
	c.craft = true                  # drawn here, as a pod and its engines: not as one of traffic's models
	c.name = "RUNNER" if role == "pursuit" else "PATROL"
	c.road = pc.road
	c.dir = pc.dir
	c.f = pc.f + pc.dir * (RUN_AHEAD if role == "pursuit" else -COME_BEHIND) / 24.0
	var R = sim.roads[c.road]
	if c.f < 4.0 or c.f > R.N - 5.0:
		return false
	c.nsp_road = -1
	c.v = pc.v if role == "pursuit" else pc.v + 250.0 / MPH
	c.vdes = c.v
	c.a_up = 3.0 * 9.81
	c.a_lat = (RUNNER_GRIP if role == "pursuit" else PATROL_GRIP) * 9.81
	c.headway = 0.3
	c.turn_p = RUNNER_TURNS if role == "pursuit" else 0.0
	c.col = Color(0.9, 0.1, 0.1) if role == "pursuit" else Color(0.3, 0.5, 1.0)
	c.lane = clampi(pc.lane, 0, traffic._lanes[c.road].size() - 1)
	c.lat = traffic._lane_lat(c, c.lane)
	traffic._place(c)
	traffic.cars.append(c)
	traffic.racer = c
	traffic.race_state = "chase"    # (not one of the racer's own states: its machine stands by while this runs)
	traffic.race_t = 0.0
	car = c
	state = "on"
	_near = 0.0
	_far = 0.0
	_count += 1
	return true


func _end(how: String) -> void:
	if how != "":
		result = how
		tally[how] = int(tally[how]) + 1
	if car != null and how in ["caught", "busted"]:
		state = "over"                # it stays by you a few seconds, slowing, before it goes
		_linger = LINGER
		car.vdes = 0.0
		return
	_gone()


## It leaves the road: traffic has no more of it, and the racers may come again.
func _gone() -> void:
	if car != null:
		traffic.cars.erase(car)
		if traffic.racer == car:
			traffic.racer = null
			traffic.race_state = ""
	car = null
	state = ""
	_clock = 0.0
	visible = false
	if siren and siren.playing:
		siren.stop()


func _pose() -> void:
	x = car.x + car.hx * car.v * car.owed
	y = car.y + car.hy * car.v * car.owed
	z = sim.net_deck(car.road, car.f, car.lat) + float(sim.P.rideH)
	th = atan2(car.hy, car.hx)
	bank = 0.0
	visible = true
	_draw_it()
	if bar:
		bar.flash(true, Time.get_ticks_msec() / 1000.0)


func update(delta: float) -> void:
	if traffic == null:
		return
	var P = sim.pod
	var pv: float = Vector2(P.vx, P.vy).length()
	if state == "":
		_clock = _clock + delta if _ready_for_one() else maxf(_clock - delta, 0.0)
		if _clock >= (START_AFTER if _count == 0 else NEXT_AFTER):
			if not _begin():
				_clock *= 0.5
		return
	if car == null or not traffic.cars.has(car) or traffic.racer != car:
		_gone()                       # it ran off the end of the roads, or the pilot went back to a city
		return
	if state == "over":
		_linger -= delta
		car.vdes = minf(car.vdes, pv) if role == "getaway" else 0.0
		_pose()
		if _linger <= 0.0:
			_gone()
		return
	gap = Vector2(car.x - P.x, car.y - P.y).length()
	if role == "pursuit":
		# it runs: flat out with you on it, easing when you are far back so the chase can go on
		car.vdes = lerpf(RUNNER_TOP, RUNNER_EASE, smoothstep(1500.0, 4500.0, gap)) / MPH
		_near = _near + delta if gap < CATCH_R else maxf(_near - 2.0 * delta, 0.0)
		_far = _far + delta if gap > LOSE_R else 0.0
		if _near >= CATCH_T:
			_end("caught")
			return
		if _far >= LOSE_T:
			_end("lost")
			return
	else:
		# it hunts: onto your tail, and past nothing (it backs off if it has run by you)
		var ahead: float = traffic._gap_to_pod(car)     # m the pilot is ahead of it, along its way
		car.vdes = clampf(pv + (ahead - 30.0) * 0.5, 0.0, PATROL_TOP / MPH) if ahead > -40.0 else maxf(pv - 60.0, 0.0)
		if ahead < 900.0:
			_take_pilots_lane()
		_near = _near + delta if gap < BUST_R else maxf(_near - 2.0 * delta, 0.0)
		_far = _far + delta if gap > LOSE_R else 0.0
		if _near >= BUST_T:
			_end("busted")
			return
		if _far >= LOSE_T:
			_end("escaped")
			return
	_pose()                           # where it is, as a craft
	if siren and not siren.playing:
		siren.play()


## Close behind, the patrol takes the lane the pilot is in: it comes onto the tail, not past in another lane.
func _take_pilots_lane() -> void:
	var pc = traffic._pod_as_car()
	if pc == null or pc.road != car.road or pc.dir != car.dir:
		return
	var nearest := INF
	for lane in traffic._lanes[car.road].size():
		var off: float = absf(traffic._lane_lat(car, lane) - pc.lat)
		if off < nearest:
			nearest = off
			car.lane = lane


## The dash's line while one is on.
func text() -> String:
	if state != "on":
		return ""
	var far := "%.1f mi" % (gap / 1609.344) if gap > 800.0 else "%d ft" % int(gap / 0.3048)
	if role == "pursuit":
		if gap < CATCH_R:
			return "PURSUIT  ON IT  hold %.0f s" % maxf(CATCH_T - _near, 0.0)
		return "PURSUIT  RUNNER %s %s%s" % [far, "AHEAD" if traffic._gap_to_pod(car) < 0.0 else "BEHIND", "   LOSING IT" if gap > LOSE_R else ""]
	if gap < BUST_R:
		return "PATROL ON YOU  %.0f s to lose it" % maxf(BUST_T - _near, 0.0)
	return "PATROL  %s BACK%s" % [far, "   NEARLY CLEAR" if gap > LOSE_R else ""]
