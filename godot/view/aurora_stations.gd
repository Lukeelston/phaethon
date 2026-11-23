## The Aurora line's takeoff and landing areas (Luke, after the twelfth flight: "animated 'takeoff
## and landing' areas for aurora, that will tell the pilot where to stop. The takeoff could just be
## a fun animation of something to do with the airlock"). One at each pressure lock, the same both
## ends, built once in a lock's own frame: its origin on the keel at the seal, z into the tube, the
## road outside at negative z (straight and level there for 700 m).
##   the pad        a lit stop bar across the deck BAR outside the seal, in a box PAD_HALF long each
##                  way, with chevrons running to it from both sides, and over the bar a gate of
##                  light: a post either side of the road's flat and a beam between them, high over
##                  the deck (paint on a deck is a hair's breadth from a seat a metre over it; the
##                  gate is what says where the bar is from a kilometre off), and a pylon of light at
##                  each corner of the pad (a pilot stopped on the bar has the gate overhead: the far
##                  pair of pylons is what he sees change). Used both ways: a craft going in stops on
##                  it and takes off, a craft coming out stops on it and has landed. Bar, gate and
##                  pylons are red until a craft has stopped on the pad, then green.
##   from inside    a ring round the hull (outside the glass: the bore is flown all the way round)
##                  at each of BOARDS_KM before the bar, with its distance four times round it, the
##                  nearer ones saying BRAKE; the rings take the colour of how hard the craft coming
##                  must brake to stop at the bar (green, amber: brake now, red: too fast), worked
##                  out from what its air brakes do (STOP_KM, measured); and for the last APPROACH
##                  metres strips of light under the glass floor that run toward the bar.
##   takeoff        a craft heading in, stopped on the pad, cycles the lock: its rings turn and
##                  latch, an iris of light closes across the bore, an arc of two dozen lights over
##                  the lock fills as the pressure comes up to 101 kPa (the START button's ring, half
##                  a kilometre across), the iris opens green and the strips run away down the tube.
##                  Seven seconds. Nothing is in the way of a craft that does not stop: the lock rests.
##   landing        a craft that has come out of the tube and stopped on the pad is told so: the
##                  gate washes green, and the sign over the road beyond it says where it is, where
##                  it came from, how long the line took and how fast it went. (The sign is an open
##                  frame: from the road the lock is seen through it, and its other face says where
##                  to stop.)
## Nothing here is solid and nothing is inside the bore or low over the road's flat. The lock's sounds are
## the start-up's recordings (audio/startup_audio.gd): an air valve, a latch, a contactor, a chime.
##   var s := Stations.new(); line.add_child(s); s.build(sim, line)
##   s.place(z)              from the line's sync: its anchor along the line has moved
##   s.step(delta)           every frame (its own _process calls it)
extends Node3D

const Tube := preload("res://sim/pressure_surface.gd")
const Kit := preload("res://view/mesh_kit.gd")
const Marks := preload("res://view/aurora_marks.gdshader")
const Ring := preload("res://view/start_ring.gdshader")
const BAR := 400.0              # m outside the seal: the stop bar (from it the bore's middle is 22 degrees up and the whole lock is in a pilot's view)
const ROAD_CHEVRONS := 4        # chevrons to the bar from the road, 60 m apart ...
const SEAL_CHEVRONS := 5        # ... and from the seal, 55 m apart
const PAD_HALF := 80.0          # the pad runs this far along either side of the bar ...
const PAD_WIDE := 56.0          # ... and this far across either side of the road's middle (its flat is 70 m)
const DECK := 0.22              # m over the deck: the pad's marks (the road's own paint is at 0.12)
const GATE_X := 76.0            # the gate's posts: this far either side of the road's middle (its flat ends at 70 m) ...
const GATE_HIGH := 46.0         # ... and this tall; its beam is the top 2.4 m
const PYLON_HIGH := 26.0        # the pylons at the pad's four corners, in line with the gate's posts
const SIGN_AT := 180.0          # m beyond the bar: the sign over the road
const GAUGE_IN := 76.0          # the pressure gauge: an arc from this far outside the glass (the accumulators reach 67 m) ...
const GAUGE_OUT := 98.0         # ... to this ...
const GAUGE_SWEEP := 240.0      # ... of this many degrees over the top (its ends 31 m up, in sight over the road's walls)
const STOPPED := 0.9            # m/s: under 2 mph is stopped
const BOARDS_KM := [100.0, 50.0, 30.0, 20.0, 10.0, 5.0, 2.0, 1.0]
const BRAKE_KM := 30.0          # the boards from here in say BRAKE (flat out in the line, 10,800 mph, amber comes at 28 km)
const RING_IN := 6.0            # a distance ring: from this far outside the glass ...
const RING_OUT := 42.0          # ... to this
const NUMERAL_AT := 96.0        # the middle of a ring's numerals, outside the glass
const NUMERAL_FAR := 4500.0     # m: a ring's words are drawn from here in (40 m letters: they cannot be read from further)
const APPROACH := 3000.0        # m inside the seal: the strips of light under the floor
## Full air brakes, levers shut, inside the tube: [mph, km to a stop] (tests/test_aurora_stations.gd
## measures it again). Hundreds of g at speed, a few g under 1,500 mph: the last of it is the long part.
## (Measured with the line's air going along with the craft, its body's drag a quarter: craft_sim.gd line_speed.)
const STOP_KM := [[0.0, 0.0], [200.0, 0.08], [500.0, 0.47], [1000.0, 1.77], [2000.0, 3.66], [3000.0, 4.26], [4000.0, 5.03],
	[5000.0, 5.95], [6000.0, 6.96], [8000.0, 9.15], [10000.0, 11.42], [12000.0, 13.63], [15000.0, 16.75], [20000.0, 21.32],
	[25000.0, 25.19]]
const REACT_S := 2.0            # amber allows this long to get on the brakes ...
const MARGIN := 1.5             # ... and this much of the stopping distance
const LATCH_S := 1.2            # the cycle: the rings turn and latch,
const SEAL_S := 1.4             # the iris closes,
const FILL_S := 3.2             # the pressure comes up,
const OPEN_S := 1.2             # the iris opens: clear
const HOLD_S := 25.0            # the lock stays clear this long, or until the craft has gone
const LANDED_S := 60.0
const NAMES := ["SOUTHWEST LOCK", "NORTHEAST LOCK"]
const RED := Color(1.0, 0.1, 0.06)
const AMBER := Color(1.0, 0.62, 0.12)
const GREEN := Color(0.3, 1.0, 0.45)
const CYAN := Color(0.25, 0.9, 0.95)
const COPPER := Color(0.91, 0.48, 0.22)
const PALE := Color(0.9, 1.0, 0.95)
const STOP := Color(1.0, 0.05, 0.03)       # the pad's bar, gate and pylons: a signal's red and green, drawn near their own
const GO := Color(0.06, 1.0, 0.24)         # brightness (well over white they wash out to salmon and mint by day)
const INK := Color(0.0, 0.035, 0.045)      # round the boards' letters: they are read against a bright field and the sky
enum {REST, CYCLE, CLEAR, LANDED}

var sim
var locks: Array = []           # two: {node, state, t, pad, approach, rings, gauge, field, hoops, board, arrival, ...}
var played: Array = []          # [lock, sound] as asked for, in order (the tests read it)
var sound := true               # (false: nothing is played; --mute)
var braking := -1               # how the craft coming to a lock must brake: -1 none coming, 0 green, 1 amber, 2 red
var trip := {}                  # the craft's run through the tube: {from, t0, top}
var arrival := {}               # ... and its end: {lock, from, seconds, top, at}
var _road := 0
var _a := Vector2.ZERO          # the southwest seal, the line's way and its left, on the map
var _t := Vector2.ZERO
var _n := Vector2.ZERO
var _span := 0.0
var _along_was := INF
var _players := {}


## How far the craft takes to stop from a speed on full air brakes, km.
static func stop_km(mph: float) -> float:
	for k in range(1, STOP_KM.size()):
		if mph <= float(STOP_KM[k][0]):
			return lerpf(STOP_KM[k - 1][1], STOP_KM[k][1], inverse_lerp(STOP_KM[k - 1][0], STOP_KM[k][0], mph))
	var last: Array = STOP_KM[-1]
	var before: Array = STOP_KM[-2]
	return float(last[1]) + (mph - float(last[0])) * (float(last[1]) - float(before[1])) / (float(last[0]) - float(before[0]))


## How a craft at a speed, a distance short of the bar, must brake to stop on it: 0 it need not yet,
## 1 now, 2 it cannot on its brakes alone.
static func brake_state(mph: float, to_bar_m: float) -> int:
	var need := stop_km(mph) * 1000.0
	if to_bar_m < need * 1.05:
		return 2
	if to_bar_m < need * MARGIN + mph * 0.44704 * REACT_S:
		return 1
	return 0


## A point on the hull's outside at arc `s` metres left of the keel, `out` metres outside the glass,
## `z` metres inside the seal (the lower panels are flat at the threshold and take their curve
## across the apron).
static func hull(s: float, z: float, out: float) -> Vector3:
	var fold := smoothstep(0.0, Tube.APRON, z)
	var a := s / Tube.RADIUS
	var p := Tube.section(a, fold) - Tube.normal(a, fold) * out
	return Vector3(p.x, p.y, z)


func build(craft_sim, line: Node3D) -> void:
	name = "AuroraStations"
	sim = craft_sim
	var route: Array = sim.NET_PRESSURE
	_road = int(route[0])
	var road = sim.roads[_road]
	var i: int = route[1]
	_a = Vector2(road.px[i], road.py[i])
	_t = Vector2(road.tx[i], road.ty[i])
	_n = Vector2(road.nx[i], road.ny[i])
	_span = float(int(route[2]) - i) * float(road.len[i])
	sound = not ("--mute" in OS.get_cmdline_user_args())
	var deck := _deck_marks()
	var strips := _approach_strips()
	var rings := SurfaceTool.new()        # a lock's distance rings: one mesh, one draw
	rings.begin(Mesh.PRIMITIVE_TRIANGLES)
	for km: float in BOARDS_KM:
		_hull_ring(rings, km * 1000.0 - BAR, RING_IN, RING_OUT, 96, Color(1, 0, 0))
	var ring := rings.commit()
	var hoop := _annulus(Tube.RADIUS + 44.0, Tube.RADIUS + 52.0, 16, Color(1, 1, 1), 0.62)
	var gauge := _annulus(Tube.RADIUS + GAUGE_IN, Tube.RADIUS + GAUGE_OUT, 96, Color(1, 1, 1), 1.0, deg_to_rad(GAUGE_SWEEP))
	var gantry := _gantry()
	var fields: Array = line.get("seal_fields") if line.get("seal_fields") != null else []
	for k in 2:
		var node := Node3D.new()
		node.name = "LockSW" if k == 0 else "LockNE"
		if k == 1:
			node.rotation.y = PI          # its z runs into the tube too
		add_child(node)
		var lock := {"node": node, "state": REST, "t": 0.0, "name": NAMES[k], "home": 0.0 if k == 0 else _span,
			"field": fields[k] if fields.size() > k else null, "spin": [0.0, 0.0, 0.0], "said": "", "told": ""}
		lock.pad = _material(STOP, AMBER)
		lock.pad.set_shader_parameter("run", 60.0)
		lock.pad.set_shader_parameter("spacing", 180.0)
		_add(node, deck, lock.pad, Vector3.ZERO, 7000.0, "PadMarks")
		lock.approach = _material(CYAN, CYAN)
		lock.approach.set_shader_parameter("spacing", 600.0)
		_add(node, strips, lock.approach, Vector3.ZERO, 14000.0, "ApproachStrips")
		lock.rings = _material(CYAN, CYAN)
		_add(node, ring, lock.rings, Vector3.ZERO, 0.0, "DistanceRings")       # (a hundred kilometres long: the camera's far plane is what culls it)
		for km: float in BOARDS_KM:
			var z := km * 1000.0 - BAR
			for q in 4:
				var turn := q * PI / 2.0
				var words := Label3D.new()
				words.name = "Distance%d_%d" % [int(km), q]
				words.text = "%d KM\n%s" % [int(km), "BRAKE" if km <= BRAKE_KM else "TO THE LOCK"]
				words.font_size = 96
				words.pixel_size = 0.42
				words.outline_size = 0
				words.shaded = false
				words.double_sided = false
				words.alpha_cut = Label3D.ALPHA_CUT_DISCARD
				words.modulate = Color(0.86, 1.0, 0.93)
				words.rotation.z = turn       # its top away from the bore: the one over a pilot's head reads upright, wherever on the wall he rides
				words.position = Vector3(0, Tube.RADIUS, z) + Vector3(-sin(turn), cos(turn), 0) * (Tube.RADIUS + NUMERAL_AT)
				words.visibility_range_end = NUMERAL_FAR
				node.add_child(words)
		# the lock's own machinery: three hoops of light that turn, the pressure ring, its board
		lock.hoop_mat = StandardMaterial3D.new()
		lock.hoop_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		lock.hoop_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		lock.hoops = []
		for z: float in [-3.0, 24.0, 77.0]:
			lock.hoops.append(_add(node, hoop, lock.hoop_mat, Vector3(0, Tube.RADIUS, z), 30000.0, "Hoop"))
		lock.gauge = ShaderMaterial.new()
		lock.gauge.shader = Ring
		lock.gauge.set_shader_parameter("segments", 24.0)
		lock.gauge.set_shader_parameter("rest", 0.1)
		_add(node, gauge, lock.gauge, Vector3(0, Tube.RADIUS, -4.0), 20000.0, "PressureRing")
		lock.board = _board(node, "Board", Vector3(0, 66.0, -2.0), PI, 0.2)       # written on the field, low in the bore where a pilot on the pad is looking (its foot 41 m over the road)
		_add(node, gantry, _panel_material(), Vector3.ZERO, 9000.0, "ArrivalGantry")
		lock.arrival = _board(node, "Arrival", Vector3(0, 75.0, -BAR - SIGN_AT + 2.2), 0.0, 0.16)   # over the road beyond the pad, read coming out
		var road_face := _board(node, "Sign", Vector3(0, 75.0, -BAR - SIGN_AT - 2.2), PI, 0.16)     # ... and its other face, read coming to the lock by road
		road_face.text = "AURORA LINE   S20\n%s\nSTOP AT THE RED BAR" % lock.name
		road_face.modulate = PALE
		locks.append(lock)
		_rest(lock)
	set_process(true)


## The line's anchor along itself has moved: each lock takes its place from it.
func place(anchor_z: float) -> void:
	for lock: Dictionary in locks:
		(lock.node as Node3D).position.z = float(lock.home) - anchor_z


func _process(delta: float) -> void:
	step(delta)


## Both locks at rest and no run remembered (a harness between its views; a flight begun afresh).
func reset() -> void:
	for k in locks.size():
		_begin(k, REST)
	trip = {}
	arrival = {}
	_along_was = INF
	braking = -1


## Where the craft is to a lock: [metres inside its seal (negative: outside), metres left of the
## middle, its speed into the tube, its speed, whether it points into the tube].
func craft_at(k: int) -> Array:
	var b = sim.pod
	var along := (float(b.x) - _a.x) * _t.x + (float(b.y) - _a.y) * _t.y
	var across := (float(b.x) - _a.x) * _n.x + (float(b.y) - _a.y) * _n.y
	var v_along := float(b.vx) * _t.x + float(b.vy) * _t.y
	var nose := cos(float(b.th)) * _t.x + sin(float(b.th)) * _t.y
	var way := 1.0 if k == 0 else -1.0
	return [along if k == 0 else _span - along, across * way, v_along * way, sqrt(float(b.vx) * float(b.vx) + float(b.vy) * float(b.vy)), nose * way > 0.3]


func step(delta: float) -> void:
	if sim == null or locks.is_empty():
		return
	var b = sim.pod
	var on_line: bool = int(b.path) == _road and not bool(b.off_road)
	var along := (float(b.x) - _a.x) * _t.x + (float(b.y) - _a.y) * _t.y
	if on_line:
		_follow_trip(along)
	else:
		_along_was = INF
	braking = -1
	for k in 2:
		var lock: Dictionary = locks[k]
		var at := craft_at(k) if on_line else [-1e9, 0.0, 0.0, 0.0, false]
		var inside: float = at[0]
		var speed: float = at[3]
		var on_pad: bool = on_line and absf(inside + BAR) < PAD_HALF and absf(float(at[1])) < PAD_WIDE
		var stopped: bool = on_pad and speed < STOPPED
		var near: bool = on_line and inside > -2500.0 and inside < BOARDS_KM[0] * 1000.0 + 12000.0
		if not near and int(lock.state) == REST:
			if not bool(lock.get("resting", false)):
				_rest(lock)
			continue
		lock.resting = false
		lock.t = float(lock.t) + delta
		match int(lock.state):
			REST:
				if stopped and bool(at[4]):
					_begin(k, CYCLE)
				elif stopped and not arrival.is_empty() and int(arrival.lock) == k:
					_begin(k, LANDED)
			CYCLE:
				if not on_pad:
					_begin(k, REST)        # it went without waiting: the lock lets go
				elif float(lock.t) >= LATCH_S + SEAL_S + FILL_S + OPEN_S:
					_begin(k, CLEAR)
			CLEAR:
				if float(lock.t) > HOLD_S or inside > 1500.0 or inside < -BAR - 600.0:
					_begin(k, REST)
			LANDED:
				if float(lock.t) > LANDED_S or not on_pad or speed > 5.0:
					arrival = {}
					_begin(k, REST)
		# a craft coming to this lock from inside: how it must brake
		var coming: bool = on_line and inside > -BAR - PAD_HALF and float(at[2]) < -3.0 and not stopped
		if coming:
			braking = brake_state(speed * 2.23694, maxf(inside + BAR, 0.0))
		_show(lock, k, coming, stopped, delta)


## The craft's run through the tube: begun as it crosses a seal inward, ended as it crosses one out.
func _follow_trip(along: float) -> void:
	var b = sim.pod
	var was := _along_was
	_along_was = along
	if was == INF or absf(along - was) > 2000.0:      # set down afresh: no run to speak of
		if was != INF:
			trip = {}
		return
	var inside := along > 0.0 and along < _span
	var before := was > 0.0 and was < _span
	if inside and not before:
		trip = {"from": 0 if along < _span * 0.5 else 1, "t0": float(sim.time), "top": 0.0}
		arrival = {}
	elif before and not inside and not trip.is_empty():
		arrival = {"lock": 0 if along <= 0.0 else 1, "from": int(trip.from), "seconds": float(sim.time) - float(trip.t0), "top": float(trip.top), "at": float(sim.time)}
		trip = {}
	if inside and not trip.is_empty():
		trip.top = maxf(float(trip.top), sqrt(float(b.vx) * float(b.vx) + float(b.vy) * float(b.vy)) * 2.23694)


func _begin(k: int, state: int) -> void:
	var lock: Dictionary = locks[k]
	lock.state = state
	lock.t = 0.0
	lock.rang = {}
	match state:
		CYCLE:
			_play(k, "clamp")
		CLEAR:
			_play(k, "chime")
		LANDED:
			_play(k, "chime")
		REST:
			_rest(lock)


## A sound of the cycle once, when its moment comes.
func _once(k: int, lock: Dictionary, at: float, what: String) -> void:
	if float(lock.t) >= at and not (lock.rang as Dictionary).has(what):
		lock.rang[what] = true
		_play(k, what)


func _play(k: int, what: String) -> void:
	played.append([k, what])
	if not sound or not is_inside_tree():
		return
	var key := "%d %s" % [k, what]
	if not _players.has(key):
		var bank: Dictionary = StartupAudio.bank()
		if not bank.has(what):
			return
		var p := AudioStreamPlayer3D.new()
		p.stream = bank[what][0]
		p.volume_db = StartupAudio.level_db(what) - 3.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED     # a lock 260 m off, heard as a place and not as a distance
		p.attenuation_filter_cutoff_hz = 20500.0
		p.position = Vector3(0, Tube.RADIUS, 0)
		(locks[k].node as Node3D).add_child(p)
		_players[key] = p
	(_players[key] as AudioStreamPlayer3D).play()


## A lock as it stands with nothing to do.
func _rest(lock: Dictionary) -> void:
	lock.resting = true
	lock.state = REST
	lock.rang = {}
	_paint(lock.pad, STOP, 1.2, 60.0, 0.7)
	(lock.pad as ShaderMaterial).set_shader_parameter("runner", AMBER)
	_paint(lock.approach, CYAN, 0.0, 0.0, 0.5)
	(lock.approach as ShaderMaterial).set_shader_parameter("runner", CYAN)
	_paint(lock.rings, CYAN, 0.45, 0.0, 0.0)
	(lock.hoop_mat as StandardMaterial3D).albedo_color = COPPER * 0.5
	var gauge: ShaderMaterial = lock.gauge
	gauge.set_shader_parameter("lit", Vector3(CYAN.r, CYAN.g, CYAN.b))
	gauge.set_shader_parameter("level", 1.0)
	gauge.set_shader_parameter("rest", 0.22)        # (unlit it is a dim arc of two dozen lamps, not a black one)
	gauge.set_shader_parameter("progress", 0.0)
	_field(lock, 0.0, 0.0, CYAN)
	_say(lock, "AURORA LINE   S20\n%s\nSTOP AT THE RED BAR" % lock.name, PALE)
	_tell(lock, "AURORA LINE   S20\n%s\nSTOP AT THE RED BAR" % lock.name, PALE)


## Draw a lock as its state has it.
func _show(lock: Dictionary, k: int, coming: bool, stopped: bool, delta: float) -> void:
	var t: float = lock.t
	var state: int = lock.state
	var hoops: Array = lock.hoops
	var spin: Array = lock.spin
	var turning := 0.0
	# the bar and the pad: red until a craft has stopped on it
	var go := state != REST or stopped
	var wash := exp(-t / 1.2) if state == LANDED else 0.0
	_paint(lock.pad, GO if go else STOP, (1.1 if go else 1.2) + 3.0 * wash, 60.0, 0.7)
	# the strips and the rings: for a craft coming out, how it must brake; for one cleared in, the way
	if coming:
		var colour: Color = [GREEN, AMBER, RED][braking]
		_paint(lock.approach, colour, 0.0, 700.0, 1.6)
		(lock.approach as ShaderMaterial).set_shader_parameter("runner", colour)
		_paint(lock.rings, colour, 1.4 if braking == 0 else (1.8 + 0.6 * sin(Time.get_ticks_msec() * 0.012 * braking)), 0.0, 0.0)
	elif state == CLEAR or (state == CYCLE and t > LATCH_S + SEAL_S + FILL_S):
		_paint(lock.approach, GREEN, 0.0, -900.0, 1.8)
		(lock.approach as ShaderMaterial).set_shader_parameter("runner", GREEN)
		_paint(lock.rings, CYAN, 0.45, 0.0, 0.0)
	else:
		_paint(lock.approach, CYAN, 0.0, 0.0, 0.5)
		(lock.approach as ShaderMaterial).set_shader_parameter("runner", CYAN)
		_paint(lock.rings, CYAN, 0.45, 0.0, 0.0)
	var gauge: ShaderMaterial = lock.gauge
	match state:
		REST:
			(lock.hoop_mat as StandardMaterial3D).albedo_color = COPPER * 0.5
			_field(lock, 0.0, 0.0, CYAN)
		CYCLE:
			var seal_at := LATCH_S
			var fill_at := LATCH_S + SEAL_S
			var open_at := fill_at + FILL_S
			_once(k, lock, 0.25, "release")
			_once(k, lock, fill_at, "power")
			var kpa := 101.0 * smoothstep(0.0, 1.0, clampf((t - fill_at) / FILL_S, 0.0, 1.0))
			if t < seal_at:                 # the hoops wind up
				turning = smoothstep(0.0, LATCH_S, t)
				(lock.hoop_mat as StandardMaterial3D).albedo_color = COPPER.lerp(AMBER, turning) * (0.6 + 1.2 * turning)
				_field(lock, 0.25 * turning, 0.0, AMBER)
				_say(lock, "%s\nHOLD ON THE PAD\nLATCHING" % lock.name, AMBER)
			elif t < fill_at:               # the iris closes
				turning = 1.0
				var shut := smoothstep(0.0, 1.0, (t - seal_at) / SEAL_S)
				(lock.hoop_mat as StandardMaterial3D).albedo_color = AMBER * 1.8
				_field(lock, 0.25 + 0.75 * shut, shut, AMBER)
				_say(lock, "%s\nHOLD ON THE PAD\nSEALING THE BORE" % lock.name, AMBER)
			elif t < open_at:               # the pressure comes up: the ring fills, amber turns to cyan
				var k_fill := kpa / 101.0
				turning = 1.0 - 0.8 * k_fill
				var colour := AMBER.lerp(CYAN, k_fill)
				(lock.hoop_mat as StandardMaterial3D).albedo_color = colour * 1.8
				_field(lock, 1.0, 1.0, colour)
				gauge.set_shader_parameter("lit", Vector3(AMBER.r, AMBER.g, AMBER.b))      # (one strong colour while it fills: it is read against the sky)
				gauge.set_shader_parameter("level", 1.5)
				gauge.set_shader_parameter("rest", 0.16)
				gauge.set_shader_parameter("progress", k_fill)
				_say(lock, "%s\nEQUALISING\n%d kPa" % [lock.name, roundi(kpa)], colour)
			else:                           # the iris opens: clear
				var opened := smoothstep(0.0, 1.0, (t - open_at) / (OPEN_S * 0.7))
				turning = 0.0
				(lock.hoop_mat as StandardMaterial3D).albedo_color = GREEN * 2.0
				_field(lock, 1.0 - 0.6 * opened, 1.0 - opened, GREEN)
				gauge.set_shader_parameter("lit", Vector3(GREEN.r, GREEN.g, GREEN.b))
				gauge.set_shader_parameter("level", 1.7)
				gauge.set_shader_parameter("progress", 1.0)
				_say(lock, "%s\n101 kPa\nCLEAR" % lock.name, GREEN)
		CLEAR:
			var glow := 0.75 + 0.25 * sin(t * 5.0)
			(lock.hoop_mat as StandardMaterial3D).albedo_color = GREEN * (1.4 * glow)
			_field(lock, 0.4, 0.0, GREEN)
			gauge.set_shader_parameter("lit", Vector3(GREEN.r, GREEN.g, GREEN.b))
			gauge.set_shader_parameter("level", 1.6 * glow)
			gauge.set_shader_parameter("progress", 1.0)
			_say(lock, "%s\n101 kPa   CLEAR\nGO" % lock.name, GREEN)
		LANDED:
			(lock.hoop_mat as StandardMaterial3D).albedo_color = GREEN * (0.8 + 1.6 * wash)
			_field(lock, 0.7 * wash, 0.0, GREEN)
			var words := "ARRIVED   %s" % lock.name
			if not arrival.is_empty() and int(arrival.from) != k:
				var secs := roundi(float(arrival.seconds))
				words += "\n%d KM FROM THE %s\nIN %d MIN %02d S\nTOP SPEED %s MPH" % [roundi(_span / 1000.0), NAMES[int(arrival.from)], secs / 60, secs % 60, _thousands(roundi(float(arrival.top)))]
			_tell(lock, words, GREEN)
	# the hoops turn, each its own way, and come to rest squared up
	for h in hoops.size():
		var rate := (1.5 - 0.35 * h) * (1.0 if h % 2 == 0 else -1.0) * turning
		spin[h] = float(spin[h]) + rate * delta
		if turning == 0.0 and state != REST:
			spin[h] = lerp_angle(float(spin[h]), snappedf(float(spin[h]), TAU / 16.0), 1.0 - exp(-delta * 6.0))
		(hoops[h] as Node3D).rotation.z = float(spin[h])


func _thousands(n: int) -> String:
	var s := str(n)
	return s if s.length() <= 3 else s.left(s.length() - 3) + "," + s.right(3)


func _paint(material, state: Color, level: float, run: float, run_level: float) -> void:
	var m: ShaderMaterial = material
	m.set_shader_parameter("state", Vector3(state.r, state.g, state.b))
	m.set_shader_parameter("level", level)
	m.set_shader_parameter("run", run)
	m.set_shader_parameter("run_level", run_level)


func _field(lock: Dictionary, charge: float, iris: float, tint: Color) -> void:
	lock.charge = charge
	lock.iris = iris
	if lock.field == null:
		return
	var f: ShaderMaterial = lock.field
	f.set_shader_parameter("charge", charge)
	f.set_shader_parameter("iris", iris)
	f.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b) * 1.2)


## The words on the lock's board, and on the board beyond the pad.
func _say(lock: Dictionary, words: String, colour: Color) -> void:
	if String(lock.said) != words:
		lock.said = words
		(lock.board as Label3D).text = words
	(lock.board as Label3D).modulate = colour.lerp(Color.WHITE, 0.45)


func _tell(lock: Dictionary, words: String, colour: Color) -> void:
	if String(lock.told) != words:
		lock.told = words
		(lock.arrival as Label3D).text = words
	(lock.arrival as Label3D).modulate = colour.lerp(Color.WHITE, 0.45)


func _material(state: Color, runner: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = Marks
	m.set_shader_parameter("state", Vector3(state.r, state.g, state.b))
	m.set_shader_parameter("runner", Vector3(runner.r, runner.g, runner.b))
	return m


func _panel_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.metallic = 0.3
	m.roughness = 0.5
	return m


func _add(node: Node3D, mesh: Mesh, material: Material, at: Vector3, far: float, label: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = label
	mi.mesh = mesh
	mi.material_override = material
	mi.position = at
	mi.visibility_range_end = far
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(mi)
	return mi


func _board(node: Node3D, label: String, at: Vector3, turn: float, pixel: float) -> Label3D:
	var l := Label3D.new()
	l.name = label
	l.font_size = 64
	l.pixel_size = pixel
	l.outline_size = 14
	l.outline_modulate = INK
	l.shaded = false
	l.double_sided = false
	l.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	l.position = at
	l.rotation.y = turn
	l.visibility_range_end = 5000.0
	node.add_child(l)
	return l


## One flat quad of a mark: its corners, its kind (the shader's colour code), and the metres to the
## bar at each corner.
func _quad(st: SurfaceTool, corners: Array, kind: Color, to_bar: Array) -> void:
	for i in [0, 1, 2, 0, 2, 3]:
		st.set_color(kind)
		st.set_uv(Vector2(0.5, float(to_bar[i])))
		st.set_normal(Vector3.UP)
		st.add_vertex(corners[i])


## The pad: on the deck the bar, the box round it, and chevrons running to the bar from the road
## and from the seal; over the bar its gate of light, and a pylon at each corner.
func _deck_marks() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bar := Color(1, 0, 0)
	var box := Color(0.55, 0, 0)
	var run := Color(0, 1, 0)
	var y := DECK
	_quad(st, [Vector3(-PAD_WIDE, y, -BAR - 4.0), Vector3(PAD_WIDE, y, -BAR - 4.0), Vector3(PAD_WIDE, y, -BAR + 4.0), Vector3(-PAD_WIDE, y, -BAR + 4.0)], bar, [0, 0, 0, 0])
	# the gate over the bar, each part two blades crossed so it is seen from beside and beneath too
	for side: float in [-1.0, 1.0]:
		var x := side * GATE_X
		_quad(st, [Vector3(x - 1.2, 0, -BAR), Vector3(x + 1.2, 0, -BAR), Vector3(x + 1.2, GATE_HIGH, -BAR), Vector3(x - 1.2, GATE_HIGH, -BAR)], bar, [0, 0, 0, 0])
		_quad(st, [Vector3(x, 0, -BAR - 1.2), Vector3(x, 0, -BAR + 1.2), Vector3(x, GATE_HIGH, -BAR + 1.2), Vector3(x, GATE_HIGH, -BAR - 1.2)], bar, [0, 0, 0, 0])
	_quad(st, [Vector3(-GATE_X, GATE_HIGH - 2.4, -BAR), Vector3(GATE_X, GATE_HIGH - 2.4, -BAR), Vector3(GATE_X, GATE_HIGH, -BAR), Vector3(-GATE_X, GATE_HIGH, -BAR)], bar, [0, 0, 0, 0])
	_quad(st, [Vector3(-GATE_X, GATE_HIGH - 1.2, -BAR - 1.2), Vector3(GATE_X, GATE_HIGH - 1.2, -BAR - 1.2), Vector3(GATE_X, GATE_HIGH - 1.2, -BAR + 1.2), Vector3(-GATE_X, GATE_HIGH - 1.2, -BAR + 1.2)], bar, [0, 0, 0, 0])
	for end: float in [-1.0, 1.0]:      # ... and a pylon at each corner of the pad
		for side: float in [-1.0, 1.0]:
			var x := side * GATE_X
			var z := -BAR + end * PAD_HALF
			_quad(st, [Vector3(x - 0.9, 0, z), Vector3(x + 0.9, 0, z), Vector3(x + 0.9, PYLON_HIGH, z), Vector3(x - 0.9, PYLON_HIGH, z)], bar, [0, 0, 0, 0])
			_quad(st, [Vector3(x, 0, z - 0.9), Vector3(x, 0, z + 0.9), Vector3(x, PYLON_HIGH, z + 0.9), Vector3(x, PYLON_HIGH, z - 0.9)], bar, [0, 0, 0, 0])
	for end: float in [-1.0, 1.0]:      # the box's two ends and two sides
		var z := -BAR + end * PAD_HALF
		_quad(st, [Vector3(-PAD_WIDE, y, z - 0.8), Vector3(PAD_WIDE, y, z - 0.8), Vector3(PAD_WIDE, y, z + 0.8), Vector3(-PAD_WIDE, y, z + 0.8)], box, [0, 0, 0, 0])
		var x := end * PAD_WIDE
		_quad(st, [Vector3(x - 0.8, y, -BAR - PAD_HALF), Vector3(x + 0.8, y, -BAR - PAD_HALF), Vector3(x + 0.8, y, -BAR + PAD_HALF), Vector3(x - 0.8, y, -BAR + PAD_HALF)], box, [0, 0, 0, 0])
	var tips := []
	for k in ROAD_CHEVRONS:               # from the road: their points toward the tube
		tips.append([-BAR - 110.0 - 60.0 * k, 1.0])
	for k in SEAL_CHEVRONS:               # from the seal: their points toward the road (the last ends 44 m short of the seal)
		tips.append([-BAR + 100.0 + 55.0 * k, -1.0])
	for tip: Array in tips:
		var z0: float = tip[0]
		var way: float = tip[1]
		for side: float in [-1.0, 1.0]:
			var a := Vector3(0, y, z0)
			var b := Vector3(0, y, z0 - way * 6.0)
			var c := Vector3(side * 34.0, y, z0 - way * 36.0)
			var d := Vector3(side * 34.0, y, z0 - way * 30.0)
			_quad(st, [a, b, c, d], run, [absf(a.z + BAR), absf(b.z + BAR), absf(c.z + BAR), absf(d.z + BAR)])
	return st.commit()


## Strips of light under the glass floor for the last APPROACH metres inside the seal: one every
## 60 m, 16 m long and 48 m across, following the floor as it goes from flat at the threshold to
## the hull's curve. (From a seat a metre over the floor they close up into a band of light to the
## horizon, and it is the pulses running along it that are seen.)
func _approach_strips() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var run := Color(0, 1, 0)
	var z := 30.0
	while z <= APPROACH:
		for k in 6:
			var s0 := -24.0 + 8.0 * k
			var s1 := s0 + 8.0
			_quad(st, [hull(s0, z - 8.0, 0.35), hull(s1, z - 8.0, 0.35), hull(s1, z + 8.0, 0.35), hull(s0, z + 8.0, 0.35)], run, [z + BAR, z + BAR, z + BAR, z + BAR])
		z += 60.0
	return st.commit()


## A flat ring about the origin facing along z, from r0 to r1: whole, or (count, share) so many
## dashes each that share of its pitch. UV.x runs once round, clockwise from the top for a pilot
## looking into the tube; UV.y from its inner edge to its outer. With a `sweep` it is an arc of
## that many radians over the top, UV.x from its left end to its right.
func _annulus(r0: float, r1: float, steps: int, kind: Color, share := 1.0, sweep := TAU) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var per := 1 if share >= 1.0 else 6           # a dash's own steps round its arc
	for j in steps:
		for q in per:
			var u0 := (j + share * q / per) / steps
			var u1 := (j + share * (q + 1) / per) / steps
			var corners := []
			var uvs := []
			for corner: Array in [[u0, r0, 0.0], [u1, r0, 0.0], [u1, r1, 1.0], [u0, r1, 1.0]]:
				var a := TAU * float(corner[0]) if sweep >= TAU else (float(corner[0]) - 0.5) * sweep
				corners.append(Vector3(-sin(a), cos(a), 0.0) * float(corner[1]))
				uvs.append(Vector2(float(corner[0]), float(corner[2])))
			for i in [0, 1, 2, 0, 2, 3]:
				st.set_color(kind)
				st.set_uv(uvs[i])
				st.set_normal(Vector3.BACK)
				st.add_vertex(corners[i])
	return st.commit()


## A ring round the hull `z` metres inside the seal, from `near` to `far` metres outside the glass,
## added to a mesh being built. It follows the hull's own outline there: within the apron the lower
## panels are still unfolding from the flat, and a circle would cut through their corners.
func _hull_ring(st: SurfaceTool, z: float, near: float, far: float, steps: int, kind: Color) -> void:
	var around := TAU * Tube.RADIUS
	for j in steps:
		var s0 := around * j / steps
		var s1 := around * (j + 1) / steps
		var corners := [hull(s0, z, near), hull(s1, z, near), hull(s1, z, far), hull(s0, z, far)]
		for i in [0, 1, 2, 0, 2, 3]:
			st.set_color(kind)
			st.set_uv(Vector2(0.5, z + BAR))
			st.set_normal(Vector3.BACK)
			st.add_vertex(corners[i])


## The sign beyond the pad: two masts outside the road, a beam, and a rail 42 m over the deck. An
## open frame: its words are light (a panel behind them hid the lock from a pilot coming by road).
func _gantry() -> ArrayMesh:
	var z := -BAR - SIGN_AT
	var steel := Color(0.34, 0.45, 0.49)
	var parts := []
	for side: float in [-1.0, 1.0]:
		parts.append([Kit.box(Vector3(4, 124, 4)), Kit.at(Vector3(side * 106.0, 50.0, z)), steel])
	parts.append([Kit.box(Vector3(216, 3, 3)), Kit.at(Vector3(0, 110.5, z)), steel])
	parts.append([Kit.box(Vector3(216, 1.6, 1.6)), Kit.at(Vector3(0, 42.0, z)), steel])
	return Kit.compound(parts)
