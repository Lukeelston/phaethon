## The racing pilots of the Eridanus track (Luke, 2026-11-22: "Add AI racing pilots to Eridanus to
## battle, target is 140 - 150 seconds"). Five craft gridded round the pilot at the start line,
## each lapping the 199 km course in its own time between 140 and 150 s (his own laps there: a
## best of 134.9 s, 143.2 s on the night he asked), there to be raced: they hold a line, go by a
## slower craft with room to spare, cover a craft coming up behind them once, and give way to the
## pilot rather than touch him.
##
## They are not sims. Each follows the course's centre line at a distance along it (`s`), a
## distance left of it (`lat`) and a speed. The speed is a share of one reference lap's (`env`:
## the fastest the course's bends, a craft's push and its air brakes allow, the limits read off
## his own flying), and the share is what sets a pilot's lap time, exactly. Round one another and
## round him they choose where to be across the road from what is in their way (`_plan`).
## Touching one is touching traffic: near the pilot each is two of the sim's forcefield obstacles
## (sim.obstacles: a shove and a 'bump', if obstacle collisions are on), and never at a closing
## speed that would be a smash.
##   var r := RacePilots.new(); add_child(r); r.build(view)
##   r.update(delta)       every frame, after the sim's steps
##   r.page() / r.line()   the pilot's place and the gaps, for the glass and the dash
## Tests drive it without a view's frames: r.step(dt), r.player (a stand-in for the pilot).
extends Node3D

const CraftModelScript := preload("res://view/craft_model.gd")
const Kit := preload("res://view/mesh_kit.gd")
const GameSettings := preload("res://release/game_settings.gd")

## A test's or a render's word ("on" / "off"), over the saved choice and the launch flags.
static var forced := ""

# The field, front of the grid to the back (the slower start ahead of him, the quicker behind).
# lap: seconds a flying lap. town: its pace in the towns against its own average (the rest is
# made up on the loop), so two pilots of the same lap time are quick in different places and
# trade places every lap. lane: where it likes to run across a straight, -1 the right edge of
# the usable road .. 1 the left. slot: [m ahead of the pilot on the grid, m left of him].
const PILOTS := [
	{"name": "RANA", "lap": 149.5, "town": 1.03, "lane": 0.30, "slot": [135.0, 22.0], "colour": Color(0.93, 0.74, 0.18)},
	{"name": "ACAMAR", "lap": 147.5, "town": 0.97, "lane": -0.30, "slot": [90.0, -22.0], "colour": Color(0.80, 0.25, 0.78)},
	{"name": "ZAURAK", "lap": 145.0, "town": 1.04, "lane": 0.15, "slot": [45.0, 22.0], "colour": Color(0.25, 0.85, 0.80)},
	{"name": "CURSA", "lap": 142.5, "town": 0.96, "lane": -0.15, "slot": [-45.0, -22.0], "colour": Color(0.92, 0.94, 0.98)},
	{"name": "ACHERNAR", "lap": 140.5, "town": 1.02, "lane": 0.0, "slot": [-90.0, 22.0], "colour": Color(0.35, 0.55, 1.0)},
]

# The reference lap's limits (m, s): read off his own lap of 2026-11-21 (flight 17's log).
const A_LAT := 255.0          # across a bend, on the centre line's radius (his: 200-270 on the loop, 225-310 in the towns)
const V_TOWN := 540.0         # a STARFIGHTER's top speed (1,200 mph): the towns
const V_LOOP := 3150.0        # the most he reached on the loop's long straight (7,060 mph)
const BRAKE_0 := 140.0        # the air brakes: this at a standstill ...
const BRAKE_K := 4.5e-4       # ... and this times the speed squared more ...
const BRAKE_MAX := 800.0      # ... to this (he shed 900 m/s in a second from 1,600)
const KAP_R_TOWN := 5         # samples each way the bends are eased over for the speed (60 m) ...
const KAP_R_LOOP := 40        # ... and on the loop (480 m)
const LINE_R_TOWN := 40       # ... and for the line across the road (480 m: they set up for a bend) ...
const LINE_R_LOOP := 120      # ... 1,440 m
const LINE_K_TOWN := 600.0    # a bend of this radius or tighter has them right at the inside ...
const LINE_K_LOOP := 25000.0
const APEX := 0.75            # ... which is this share of the usable half-width
const MIX_R := 30             # samples each way a pilot's pace turns from its town pace to its loop pace (360 m)
const EXIT := 100             # samples before the loop a craft is let go in a town (1,200 m: its last straight, where he changes to SPEEDCRAFT)

# Round each other and round him (m, s)
const LEN := 30.0             # a craft, nose of its engines to its pod's tail, and a little
const CLEAR := 20.0           # two craft side by side: their middles at least this far apart
const PASS := 26.0            # ... and this far when one goes by another
const LOOK_S := 2.2           # how far ahead a pilot plans: what it would close on in this long ...
const LOOK_V := 0.10          # ... and this many seconds of its own speed ...
const LOOK_NEAR := 60.0       # ... and never less than this far past its own length (m: a craft standing on the grid ahead of it)
const BEHIND := 25.0          # a craft this close behind its tail is still beside it (it does not cut across)
const FOLLOW := 0.8           # stuck behind one: this much speed over its own for each metre of room, a second
const DEFEND := 14.0          # the one move a pilot makes across a craft coming up behind (m) ...
const DEFEND_S := 2.5         # ... held this long ...
const DEFEND_COOL := 9.0      # ... and not again for this long
const DEFEND_REACH := 0.9     # ... made when the craft behind is within this many seconds ...
const YIELD_V := 40.0         # ... and closing slower than this (90 mph). One closing faster is not fought: it has its lane,
const YIELD_S := 1.2          # from this many seconds of its closing behind (no pilot chooses a place across its nose)
const START_HOLD := 2.0       # off the grid a pilot holds its own lane this long after it goes ...
const START_SETTLE := 6.0     # ... and is on its line by this long
const LAT_K := 6.0            # how a pilot moves across the road: a spring to where it wants to be ...
const LAT_C := 5.0            # ... damped ...
const LAT_A := 120.0          # ... pulling no harder than this (12 g; a craft corners at 25) ...
const LAT_V0 := 8.0           # ... nor crossing faster than this ...
const LAT_VK := 0.08          # ... and this share of its speed
const TAPER := 75             # samples ahead the road's narrowing is seen from (900 m: a town's mouth)
const WALL := 8.0             # no pilot's middle nearer a wall than this
const EDGE := 18.0            # the usable road stops this short of a wall, or EDGE_W of the width if that is more
const EDGE_W := 0.12
const TANGIBLE_V := 400.0     # a pilot is one of the sim's obstacles only while it and the craft close slower than this (a smash is 670)
const TANGIBLE_R := 700.0     # ... and within this of the pod
const DRAW_R := 12000.0       # a pilot further off than this is not drawn ...
const WHOLE_R := 700.0        # ... and one further off than this is three plain blocks in its colour (a craft's own meshes are 47,000 triangles)
const GO_V := 3.0             # the pilot moving this fast is the start
const PAGE_S := 0.25           # the glass's page is written this often, and at once when his place changes (each new one is a picture drawn)
const PAGE_NEAR := 3.0         # the glass carries the race while a craft is within this many seconds of him ...
const PAGE_FAR := 4.0          # ... until none is within this many ...
const PAGE_CHANGE := 6.0       # ... and for this long after his place changes

var view
var sim
var on := true                # (a view sets this false to stand them still; tests)
var ghost := false            # tests: the pilot is not there (clean lap times)
var player := {}              # tests: a stand-in for the pilot {s, lat, v}, in place of the sim's craft
var eye := Vector2.INF        # where they are looked at from, if not his pod (an outside camera's place in the sim's plane)
var pilots: Array = []
var started := false
var clock := 0.0              # s since the start
var length := 0.0             # the lap, m
var n := 0                    # the course's samples
var cum := PackedFloat64Array()     # m along the centre line to each sample (n + 1)
var kap := PackedFloat64Array()     # each sample's curvature, eased (1/m, + a left-hander)
var env := PackedFloat64Array()     # the reference lap's speed at each sample
var mix := PackedFloat64Array()     # 0 in a town .. 1 on the loop
var power := PackedFloat64Array()   # 0 a STARFIGHTER's push and top speed, 1 a SPEEDCRAFT's: the loop, and a town's last EXIT samples
var racing := PackedFloat64Array()  # the line across the road, -1 .. 1 of the usable half-width (+ left)
var room := PackedFloat64Array()    # the usable half-width
var lanes := PackedFloat64Array()   # ... and what of it the pilots use: no more than the road will be in the next TAPER samples
var reference_lap := 0.0            # the reference lap's time, s (a pilot's pace is a share of it)
var town_time := 0.0                # ... of which in the towns
var me := {"s": 0.0, "lat": 0.0, "v": 0.0, "there": false, "prog": 0.0}   # the pilot, as the others see him
var place := 1                # his place in the race
var ahead := {}               # the craft next ahead of him {name, s (seconds)}; {} none
var behind := {}              # ... and next behind
var closest := INF            # tests: the nearest any pilot's middle has come to another craft's while level with it (m)
var _me_s := -1.0
var _page := ""
var _page_t := -1.0
var _was_started := false
var _page_place := 0
var _page_up := true
var _changed_at := 0.0
var _meshes := {}
var _cands := PackedFloat64Array()
var _lap_logged := 0


class Pilot:
	var name := ""
	var colour := Color.WHITE
	var lap_target := 0.0
	var f_town := 1.0
	var f_loop := 1.0
	var lane := 0.0
	var slot := Vector2.ZERO
	var s := 0.0
	var i := 0
	var lat := 0.0
	var lat_v := 0.0
	var v := 0.0
	var target := 0.0
	var prog := 0.0           # m from the start line since the grid (the race's order)
	var lap := 0              # laps begun (0 until it first crosses the line)
	var lap_t0 := -1.0
	var last_lap := -1.0
	var laps: Array = []      # its lap times, flying or not
	var go_at := 0.0
	var defend := 0.0
	var defend_t := 0.0
	var defend_cool := 0.0
	var blocked := false      # this frame: held up behind a craft it cannot go round
	var id_pod := ""          # its two forcefields' names in the pilot's sim
	var id_engines := ""
	var x := 0.0
	var y := 0.0
	var z := 0.0
	var th := 0.0
	var roll := 0.0
	var push := 0.0           # 0..1, for its flames
	var node: Node3D
	var engines: Array[Node3D] = []
	var flames: Array[MeshInstance3D] = []
	var cables: Array[MeshInstance3D] = []
	var pod: MeshInstance3D
	var far: Node3D           # the three blocks it is drawn as from a distance
	var whole := true         # ... or its whole self


## Whether this flight has racing pilots: the Eridanus course itself, not its emergency run.
static func available(s) -> bool:
	return s != null and s.course and s.track_name == "eridanus" and s.job.is_empty()


## ... and whether they are wanted: the quick menu's RACING PILOTS (saved, on unless switched off),
## --racers / --no-racers for one flight, or a test's word.
static func wanted(args: PackedStringArray) -> bool:
	if forced != "":
		return forced == "on"
	if "--no-racers" in args:
		return false
	return "--racers" in args or GameSettings.choice("racers", ["on", "off"]) == "on"


static func save_wanted(yes: bool) -> void:
	GameSettings.set_choice("racers", "on" if yes else "off")


# ---- the course, read once ----

static func _box(a: PackedFloat64Array, modes: PackedByteArray, r_town: int, r_loop: int) -> PackedFloat64Array:
	var count := a.size()
	var pre := PackedFloat64Array()
	pre.resize(count + 1)
	for i in count:
		pre[i + 1] = pre[i] + a[i]
	var out := PackedFloat64Array()
	out.resize(count)
	for i in count:
		var r := r_loop if modes[i] == 1 else r_town
		var lo := i - r
		var hi := i + r
		var sum := 0.0
		if lo < 0:
			sum = pre[count] - pre[lo + count] + pre[hi + 1]
		elif hi >= count:
			sum = pre[count] - pre[lo] + pre[hi + 1 - count]
		else:
			sum = pre[hi + 1] - pre[lo]
		out[i] = sum / float(2 * r + 1)
	return out


static func brake(v: float) -> float:
	return minf(BRAKE_MAX, BRAKE_0 + BRAKE_K * v * v)


## A craft's push at speed v: in a town (0) a STARFIGHTER's, on the loop and down a town's last
## straight to it (1) a SPEEDCRAFT's with its burner and ramjet (his: 120 m/s2 off the line in the
## town; out of a town 250 to 400 up to 1,300 m/s, 160 at 2,000, 100 to 120 from 2,600 to 3,150).
static func push_at(v: float, loop: float) -> float:
	return lerpf(maxf(12.0, 10.0 + 125.0 * (1.0 - v / 480.0)), clampf(330.0 - 0.243 * (v - 1300.0), 100.0, 330.0), loop)


## Read the course out of the sim: its length, bends, the reference lap, the line and the room.
func read_course(s) -> void:
	sim = s
	n = s.N
	cum.resize(n + 1)
	var raw := PackedFloat64Array()
	raw.resize(n)
	var modes: PackedByteArray = s.tmode
	for i in n:
		cum[i + 1] = cum[i] + s.tlen[i]
		var j := (i + 1) % n
		var turn: float = wrapf(atan2(s.tty[j], s.ttx[j]) - atan2(s.tty[i], s.ttx[i]), -PI, PI)
		raw[i] = turn / s.tlen[i]
	length = cum[n]
	kap = _box(raw, modes, KAP_R_TOWN, KAP_R_LOOP)
	var as_float := PackedFloat64Array()
	as_float.resize(n)
	for i in n:
		as_float[i] = float(modes[i])
	var ones := PackedByteArray()
	ones.resize(n)
	mix = _box(as_float, ones, MIX_R, MIX_R)
	# the line: toward the inside of what is coming, by how tight it is
	var wide := _box(raw, modes, LINE_R_TOWN, LINE_R_LOOP)
	racing.resize(n)
	room.resize(n)
	for i in n:
		var k_full: float = 1.0 / (LINE_K_LOOP if modes[i] == 1 else LINE_K_TOWN)
		racing[i] = clampf(wide[i] / k_full, -1.0, 1.0) * APEX
		room[i] = maxf(4.0, float(s.tw[i]) / 2.0 - maxf(EDGE, EDGE_W * float(s.tw[i])))
	# coming to a town the road narrows from 400 m to 140 in 480 m: the pilots are in by then
	var narrow := PackedFloat64Array()
	narrow.resize(n)
	for i in n:
		var least := room[i]
		for k in range(5, TAPER + 1, 5):
			least = minf(least, room[(i + k) % n])
		narrow[i] = least
	lanes = _box(narrow, ones, 15, 15)
	for i in n:
		lanes[i] = minf(lanes[i], room[i])
	# the reference lap: no faster than the bends allow, braked for and pushed out of
	power.resize(n)
	var to_loop := EXIT + 1      # samples to the next of the loop's
	for k in 2 * n:
		var i := posmod(n - 1 - k, n)
		to_loop = 0 if modes[i] == 1 else to_loop + 1
		power[i] = 1.0 if to_loop <= EXIT else 0.0
	env.resize(n)
	for i in n:
		var cap := V_LOOP if power[i] > 0.5 else V_TOWN
		env[i] = minf(cap, sqrt(A_LAT / maxf(absf(kap[i]), 1e-7)))
	for k in 2 * n:
		var i := posmod(n - 1 - k, n)
		var nxt := (i + 1) % n
		env[i] = minf(env[i], sqrt(env[nxt] * env[nxt] + 2.0 * brake(env[nxt]) * s.tlen[i]))
	for k in 2 * n:
		var i := k % n
		var nxt := (i + 1) % n
		env[nxt] = minf(env[nxt], sqrt(env[i] * env[i] + 2.0 * push_at(env[i], power[i]) * s.tlen[i]))
	reference_lap = 0.0
	town_time = 0.0
	for i in n:
		var dt: float = s.tlen[i] / (0.5 * (env[i] + env[(i + 1) % n]))
		reference_lap += dt
		town_time += dt * (1.0 - mix[i])


## Where a pilot of that lane runs across the road at sample i, left to itself (m left of the middle).
func nominal(i: int, lane: float) -> float:
	var l := racing[i]
	return lanes[i] * clampf(l + lane * (1.0 - absf(l)), -1.0, 1.0)


## A flying lap's time for paces f_town and f_loop on that lane (the inside of a bend is shorter).
func lap_time(f_town: float, f_loop: float, lane: float) -> float:
	var t := 0.0
	for i in n:
		var f := lerpf(f_town, f_loop, mix[i])
		t += sim.tlen[i] * maxf(0.6, 1.0 - kap[i] * nominal(i, lane)) / (f * 0.5 * (env[i] + env[(i + 1) % n]))
	return t


## The same with the pilot's own way of moving across the road (it lags its line a little, and the
## outside of a bend is longer): the lap a pilot alone would turn. One pass round the course.
func lone_lap(f_town: float, f_loop: float, lane: float) -> float:
	var first := n - 2000
	var lat := nominal(first, lane)
	var lat_v := 0.0
	var t := 0.0
	for k in range(first, 2 * n):
		var i := k % n
		var f := lerpf(f_town, f_loop, mix[i])
		var v := f * 0.5 * (env[i] + env[(i + 1) % n])
		var dt: float = sim.tlen[i] * maxf(0.6, 1.0 - kap[i] * lat) / v
		var limit := LAT_V0 + LAT_VK * v
		var a := clampf(LAT_K * (nominal(i, lane) - lat) - LAT_C * lat_v, -LAT_A, LAT_A)
		lat_v = clampf(lat_v + a * dt, -limit, limit)
		lat += lat_v * dt
		var hard: float = float(sim.tw[i]) / 2.0 - WALL
		if absf(lat) > hard:
			lat = clampf(lat, -hard, hard)
			lat_v = 0.0
		if k >= n:
			t += dt
	return t


# ---- the field ----

## `v` the view they are drawn in. Without one (a test of the race alone) pass the sim as `s`:
## nothing is drawn, and step() is the caller's to run.
func build(v, s = null) -> void:
	view = v
	name = "race_pilots"
	var began := Time.get_ticks_msec()
	read_course(v.sim if v != null else s)
	for d: Dictionary in PILOTS:
		var p := Pilot.new()
		p.name = d.name
		p.colour = d.colour
		p.lap_target = d.lap
		p.lane = d.lane
		p.slot = Vector2(d.slot[0], d.slot[1])
		p.id_pod = "race:%s:pod" % p.name
		p.id_engines = "race:%s:engines" % p.name
		# its pace: town against loop as its character says, the whole scaled to its lap time
		var loop_share := 2.0 - float(d.town)
		var t := lap_time(float(d.town), loop_share, p.lane)
		p.f_town = float(d.town) * t / p.lap_target
		p.f_loop = loop_share * t / p.lap_target
		t = lone_lap(p.f_town, p.f_loop, p.lane)      # (the line as it will fly it: a few tenths more)
		p.f_town *= t / p.lap_target
		p.f_loop *= t / p.lap_target
		pilots.append(p)
		if view != null:
			_build_craft(p)
	grid()
	var laps := PackedStringArray()
	for p: Pilot in pilots:
		laps.append("%.1f" % p.lap_target)
	print("RACE: %d pilots on Eridanus, laps %s s (the reference lap %.1f s, %.1f of it in the towns); read and solved in %d ms" % [pilots.size(), ", ".join(laps), reference_lap, town_time, Time.get_ticks_msec() - began])


## Everyone back on the grid round the pilot's own place (the start line), standing.
func grid() -> void:
	started = false
	clock = 0.0
	closest = INF
	_lap_logged = 0
	_me_s = -1.0
	me.prog = 0.0
	for p: Pilot in pilots:
		p.s = fposmod(p.slot.x, length)
		p.i = _sample(p.s, 0)
		p.lat = p.slot.y
		p.lat_v = 0.0
		p.target = p.lat
		p.v = 0.0
		p.prog = p.slot.x
		p.lap = 1 if p.slot.x >= 0.0 else 0
		p.lap_t0 = -1.0
		p.last_lap = -1.0
		p.laps = []
		p.defend = 0.0
		p.defend_t = 0.0
		p.defend_cool = 0.0
		p.push = 0.0
		_pose(p)
	_rank()
	_page_t = -1.0
	_page_up = true
	_changed_at = 0.0


func _sample(s: float, from: int) -> int:
	var i := clampi(from, 0, n - 1)
	while s >= cum[i + 1] and i < n - 1:
		i += 1
	while s < cum[i] and i > 0:
		i -= 1
	return i


## Signed metres from a to b along the lap, the short way round.
func _gap(a: float, b: float) -> float:
	var d := fposmod(b - a, length)
	return d - length if d > length * 0.5 else d


# ---- the pilot, as the others see him ----

func _read_player() -> void:
	if ghost:
		me.there = false
		return
	if not player.is_empty():
		me.s = fposmod(float(player.s), length)
		me.lat = float(player.lat)
		me.v = float(player.v)
		me.there = true
	else:
		var P = sim.pod
		if P.path != 0:
			me.there = false
			return
		var i: int = clampi(P.hint, 0, n - 1)
		var along: float = (P.x - sim.tpx[i]) * sim.ttx[i] + (P.y - sim.tpy[i]) * sim.tty[i]
		me.s = fposmod(cum[i] + along, length)
		me.lat = (P.x - sim.tpx[i]) * sim.tnx[i] + (P.y - sim.tpy[i]) * sim.tny[i]
		me.v = P.vx * sim.ttx[i] + P.vy * sim.tty[i]
		me.there = true
	if _me_s >= 0.0:
		me.prog += _gap(_me_s, me.s)
	else:
		me.prog = _gap(0.0, me.s)      # (from the start line: nothing on the grid, more if the race began mid-lap)
	_me_s = me.s


# ---- a frame ----

func update(delta: float) -> void:
	step(delta)
	for p: Pilot in pilots:
		_draw(p)
	_feed_obstacles()


## The start: they go (the pilot's first move is the start; tests and demos call it themselves).
func go() -> void:
	started = true
	clock = 0.0
	print("RACE: away, %d pilots and the craft" % pilots.size())
	for k in pilots.size():
		# each its own reaction and its engines' coming up: his own craft made 38 m/s in its first second
		# off this line and 123 more in its next (flight 17), about 0.7 s of nothing first
		(pilots[k] as Pilot).go_at = 0.45 + 0.09 * float((k * 3) % 5)


## The race, one frame on (no drawing).
func step(delta: float) -> void:
	var dt := clampf(delta, 0.0, 0.05)
	_read_player()
	# a restart (the sim's: the lap clock back at nothing, the craft back on the line) is a new grid
	if started and player.is_empty() and not ghost and sim.lap_start < 0.0 and sim.lap == 0 and absf(me.v) < 1.0 and absf(_gap(0.0, me.s)) < 40.0 and clock > 3.0:
		grid()
		_read_player()
	if not on or dt <= 0.0:
		return
	if not started:
		if ghost or (me.there and absf(me.v) > GO_V):
			go()
		else:
			_rank()
			return
	clock += dt
	for p: Pilot in pilots:
		_plan(p, dt)
	for p: Pilot in pilots:
		_move(p, dt)
	_rank()
	# the flight's log: where he stood each time he crossed the line
	if player.is_empty() and not ghost and int(sim.lap) != _lap_logged:
		_lap_logged = int(sim.lap)
		if _lap_logged > 0:
			print("RACE: lap %d done in %.2f s: %s" % [_lap_logged, float(sim.last_lap), line()])


## Where pilot p wants to be across the road and how fast it may go, from what is round it.
func _plan(p: Pilot, dt: float) -> void:
	var i := p.i
	var use := lanes[i]
	p.defend_cool = maxf(0.0, p.defend_cool - dt)
	p.defend_t = maxf(0.0, p.defend_t - dt)
	if p.defend_t <= 0.0:
		p.defend = 0.0
	var line := nominal(i, p.lane)
	if p.lap <= 1 and clock - p.go_at < START_SETTLE and p.prog < 4000.0:      # off the grid: its own lane first
		line = lerpf(p.slot.y, line, smoothstep(START_HOLD, START_SETTLE, clock - p.go_at))
	var nom := clampf(line + p.defend, -use, use)
	var cap := INF
	var horizon0 := LEN + maxf(LOOK_NEAR, LOOK_V * p.v)
	# the craft in its window: beside it, or ahead within what it plans for
	_cands.resize(0)        # [lat, gap, v] of each
	var count := pilots.size() + (1 if me.there else 0)
	for k in count:
		var q_s: float
		var q_lat: float
		var q_v: float
		var clear := CLEAR
		if k < pilots.size():
			var q: Pilot = pilots[k]
			if q == p:
				continue
			q_s = q.s
			q_lat = q.lat
			q_v = q.v
		else:
			q_s = me.s
			q_lat = me.lat
			q_v = me.v
			clear = CLEAR + 4.0     # (him: more room, he is not following a plan)
		var gap := _gap(p.s, q_s)
		var gaining := q_v - p.v        # (of one behind: how fast it is coming)
		if gap < -(LEN + BEHIND) - maxf(DEFEND_REACH * p.v, gaining * YIELD_S) or gap > horizon0 + maxf(0.0, p.v - q_v) * LOOK_S:
			continue
		if gap < -(LEN + BEHIND):
			if gaining > YIELD_V:
				# coming fast: it has its lane. A thing to keep clear of across the road, nothing to slow for.
				if -gap < LEN + BEHIND + gaining * YIELD_S:
					_cands.append(q_lat)
					_cands.append(gap)
					_cands.append(q_v)
					_cands.append(clear)
				continue
			# coming up slowly: cover it, once
			var dl := q_lat - p.lat
			if p.defend_cool <= 0.0 and gaining > 4.0 and absf(dl) > 6.0 and absf(dl) < 40.0 and p.v > 60.0:
				p.defend = signf(dl) * minf(DEFEND, absf(dl) - 2.0)
				p.defend_t = DEFEND_S
				p.defend_cool = DEFEND_COOL
				nom = clampf(line + p.defend, -use, use)
			continue
		_cands.append(q_lat)
		_cands.append(gap)
		_cands.append(q_v)
		_cands.append(clear)
		if absf(gap) < LEN:
			closest = minf(closest, absf(q_lat - p.lat))
	var m := _cands.size() / 4
	var escape := NAN
	p.blocked = false
	if m == 0:
		p.target = nom
	else:
		# the places it could run: its own line, or to either side of each of them; the nearest to
		# where it is (and a little toward its line) that is on the road and clear of them all
		var best := INF
		var found := false
		var choice := clampf(p.lat, -use, use)
		for c in 1 + 2 * m:
			var at := nom
			if c > 0:
				var which := (c - 1) / 2
				at = _cands[which * 4] + (PASS if (c - 1) % 2 == 0 else -PASS)
			if absf(at) > use + 0.01:
				continue
			var ok := true
			for k in m:
				var their := _cands[k * 4]
				# clear of each of them, and not on the far side of one that is level with it (not through it)
				if absf(at - their) < _cands[k * 4 + 3] - 0.5 or (absf(_cands[k * 4 + 1]) < LEN + 10.0 and (at - their) * (p.lat - their) < 0.0):
					ok = false
					break
			if not ok:
				continue
			var cost := absf(at - p.lat) + 0.3 * absf(at - nom)
			if cost < best:
				best = cost
				choice = at
				found = true
		p.target = choice
		for k in m:
			var q_lat := _cands[k * 4]
			var gap := _cands[k * 4 + 1]
			var q_v := _cands[k * 4 + 2]
			if absf(q_lat - p.lat) >= _cands[k * 4 + 3] - 2.0:
				continue                 # clear of it across the road: no need to slow
			if gap >= LEN:               # one ahead, not yet cleared: close on it gently
				cap = minf(cap, maxf(0.0, q_v) + maxf(0.0, gap - LEN - 10.0) * FOLLOW)
				p.blocked = not found
			elif gap >= -5.0 and not found:  # level with one and squeezed (no room left to give): drop back, smartly
				cap = minf(cap, maxf(0.0, q_v) - 40.0)
				p.blocked = true
			if absf(gap) < LEN + 10.0 and not found:   # ... and meanwhile the last of the road, out to the wall's margin
				escape = (1.0 if p.lat >= q_lat else -1.0) * (float(sim.tw[i]) / 2.0 - WALL)
	p.target = clampf(p.target, -use, use)
	if not is_nan(escape):
		p.target = escape
	# its speed: its share of the reference lap's, held to what is in its way
	var u := clampf((p.s - cum[i]) / maxf(1e-6, cum[i + 1] - cum[i]), 0.0, 1.0)
	var j := (i + 1) % n
	var f := lerpf(p.f_town, p.f_loop, lerpf(mix[i], mix[j], u))
	var want := minf(f * lerpf(env[i], env[j], u), cap)
	if clock < p.go_at:
		want = 0.0
	var before := p.v
	if want >= p.v:
		p.v = minf(want, p.v + push_at(p.v, power[i]) * f * dt)
	else:
		p.v = maxf(want, p.v - brake(p.v) * dt)
	p.push = clampf((p.v - before) / maxf(1e-6, dt) / 150.0 + 0.35, 0.0, 1.0) if p.v > 1.0 else 0.0


func _move(p: Pilot, dt: float) -> void:
	var limit := LAT_V0 + LAT_VK * p.v
	var a := clampf(LAT_K * (p.target - p.lat) - LAT_C * p.lat_v, -LAT_A, LAT_A)
	p.lat_v = clampf(p.lat_v + a * dt, -limit, limit)
	p.lat += p.lat_v * dt
	var hard: float = float(sim.tw[p.i]) / 2.0 - WALL
	if absf(p.lat) > hard:
		p.lat = clampf(p.lat, -hard, hard)
		p.lat_v = 0.0
	var ds := p.v * dt / maxf(0.6, 1.0 - kap[p.i] * p.lat)
	p.s += ds
	p.prog += ds
	if p.s >= length:
		p.s -= length
		p.i = 0
		if p.lap_t0 >= 0.0:
			p.last_lap = clock - p.lap_t0
			p.laps.append(p.last_lap)
		p.lap_t0 = clock
		p.lap += 1
	p.i = _sample(p.s, p.i)
	_pose(p)


## Where it is in the sim's plane, its height on the banked road and its attitude.
func _pose(p: Pilot) -> void:
	var i := p.i
	var j := (i + 1) % n
	var u := clampf((p.s - cum[i]) / maxf(1e-6, cum[i + 1] - cum[i]), 0.0, 1.0)
	var tx: float = lerpf(sim.ttx[i], sim.ttx[j], u)
	var ty: float = lerpf(sim.tty[i], sim.tty[j], u)
	var along: float = (p.s - cum[i])
	p.x = sim.tpx[i] + sim.ttx[i] * along + sim.tnx[i] * p.lat
	p.y = sim.tpy[i] + sim.tty[i] * along + sim.tny[i] * p.lat
	p.th = atan2(ty, tx) + atan2(p.lat_v, maxf(p.v, 20.0))
	var bank := 0.0
	if not sim.tb.is_empty():
		bank = lerpf(sim.tb[i], sim.tb[j], u)
	p.z = sim.bank_height(float(sim.tw[i]) / 2.0, p.lat, bank) + float(sim.P.rideH)
	# it lies on the banked road, and leans into what it is pulling across it (+ = left side down, as
	# the craft model's own lean and the sim's bank are)
	p.roll = bank + clampf(kap[i] * p.v * p.v / 500.0 + p.lat_v / 80.0, -0.5, 0.5)


func _rank() -> void:
	place = 1
	ahead = {}
	behind = {}
	if not me.there:
		return
	var near_up := INF
	var near_down := INF
	for p: Pilot in pilots:
		var d: float = p.prog - float(me.prog)
		if d > 0.0:
			place += 1
			if d < near_up:
				near_up = d
				ahead = {"name": p.name, "s": d / maxf(p.v, 80.0), "m": d}
		elif -d < near_down:
			near_down = -d
			behind = {"name": p.name, "s": -d / maxf(p.v, 80.0), "m": -d}


# ---- what the pilot is told ----

static func _gap_text(g: Dictionary) -> String:
	if g.is_empty():
		return "NOBODY"
	if float(g.m) < 1000.0 or float(g.s) < 0.95:
		return "%s  %.1f S" % [g.name, float(g.s)]
	return "%s  %d S" % [g.name, roundi(float(g.s))]


## The glass's page (the checklist's three lines: "ACTION  COUNT", "WHERE > WHAT", "NOTE | STATUS").
func page() -> String:
	if not me.there:
		return ""
	if _page_t >= 0.0 and (not started or clock - _page_t < PAGE_S) and _was_started == started and _page_place == place:
		return _page
	if _page_place != place or _was_started != started:
		_changed_at = clock
	_page_t = clock
	_was_started = started
	_page_place = place
	var field := pilots.size() + 1
	# alone on the road the glass is clear: the race is on it when there is one to read
	var nearest := minf(float(ahead.get("s", INF)), float(behind.get("s", INF)))
	_page_up = not started or clock - _changed_at < PAGE_CHANGE or nearest <= (PAGE_FAR if _page_up else PAGE_NEAR)
	if not _page_up:
		_page = ""
		return _page
	if not started:
		_page = "GRID  %d / %d\nSTART LINE > THEY GO WHEN YOU GO\n%s AHEAD | READY" % [place, field, "NOBODY" if ahead.is_empty() else String(ahead.name)]
	else:
		_page = "PLACE  %d / %d\nAHEAD > %s\nBEHIND  %s | LAP %d" % [place, field, _gap_text(ahead), _gap_text(behind), int(sim.lap) + 1]
	return _page


## The same in a line, for a dash or a flat screen.
func line() -> String:
	if not me.there:
		return ""
	var field := pilots.size() + 1
	if not started:
		return "GRID %d OF %d   THEY GO WHEN YOU GO" % [place, field]
	return "P%d OF %d   AHEAD %s   BEHIND %s" % [place, field, _gap_text(ahead), _gap_text(behind)]


## For the map: each pilot as the Network's racer is marked ([x, y, 4]).
func marks() -> Array:
	var out := []
	for p: Pilot in pilots:
		out.append([p.x, p.y, 4])
	return out


# ---- touching one ----

## Near the pilot each is two forcefields in his sim (its pod, its engines), as traffic is. Never
## while it and he close fast enough to be a smash: then it is not there to hit.
func _feed_obstacles() -> void:
	var obs: Array = []
	var P = sim.pod
	for p: Pilot in pilots:
		var dx: float = p.x - P.x
		var dy: float = p.y - P.y
		if dx * dx + dy * dy > TANGIBLE_R * TANGIBLE_R:
			continue
		var c := cos(p.th)
		var s := sin(p.th)
		var vx := c * p.v
		var vy := s * p.v
		if Vector2(vx - P.vx, vy - P.vy).length() > TANGIBLE_V:
			continue
		var reach := _engines_ahead()
		obs.append({"id": p.id_pod, "x": p.x, "y": p.y, "vx": vx, "vy": vy, "r": 2.6})
		obs.append({"id": p.id_engines, "x": p.x + c * reach, "y": p.y + s * reach, "vx": vx, "vy": vy, "r": 5.0})
	sim.obstacles = obs


func _engines_ahead() -> float:
	var lat: float = sim.P.engineGap / 2.0 - sim.P.podAnchorW * sim.P.podWidth / 2.0
	return sqrt(sim.P.cableLen * sim.P.cableLen - lat * lat) + sim.P.podLen / 2.0 + sim.P.engineLen / 2.0


# ---- how one looks: the driving partner's craft, in its own colour ----

func _mesh(key: String, make: Callable) -> Mesh:
	if not _meshes.has(key):
		_meshes[key] = make.call()
	return _meshes[key]


func _build_craft(p: Pilot) -> void:
	p.node = Node3D.new()
	p.node.name = p.name
	add_child(p.node)
	var finish := Kit.polished(0.55, 0.38)
	finish.albedo_color = p.colour
	var lit := Kit.vertex_colors(true)
	var flame_mat := StandardMaterial3D.new()
	flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flame_mat.albedo_color = Color(1.0, 0.6, 0.25)
	var cable_mat := StandardMaterial3D.new()
	cable_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cable_mat.albedo_color = p.colour
	for k in 2:
		var out := -1.0 if k == 0 else 1.0
		var eng := Node3D.new()
		p.node.add_child(eng)
		p.engines.append(eng)
		var body := MeshInstance3D.new()
		body.mesh = _mesh("body%d" % k, func(): return CraftModelScript._engine_body(out))
		body.material_override = finish
		body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		eng.add_child(body)
		var lights := MeshInstance3D.new()
		lights.mesh = _mesh("lights%d" % k, func(): return CraftModelScript._engine_lights(out))
		lights.material_override = lit
		lights.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		eng.add_child(lights)
		var fl := MeshInstance3D.new()
		fl.mesh = _mesh("flame", func(): return Kit.box(Vector3(CraftModelScript.ENG_W - 0.6, 0.4, 1.0)))
		fl.material_override = flame_mat
		fl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		eng.add_child(fl)
		p.flames.append(fl)
		var c := MeshInstance3D.new()
		c.mesh = _mesh("cable", func(): return Kit.box(Vector3(0.12, 0.12, 1.0)))
		c.material_override = cable_mat
		c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		p.node.add_child(c)
		p.cables.append(c)
	p.pod = MeshInstance3D.new()
	p.pod.mesh = _mesh("pod", func(): return CraftModelScript.pod_hull())
	p.pod.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.node.add_child(p.pod)
	# its own colour down the pod, so the five can be told apart from the seat
	var stripe := MeshInstance3D.new()
	stripe.mesh = _mesh("stripe", func(): return Kit.box(Vector3(0.5, 0.06, 3.2)))
	var stripe_mat := StandardMaterial3D.new()
	stripe_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	stripe_mat.albedo_color = p.colour
	stripe.material_override = stripe_mat
	stripe.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	stripe.position = Vector3(0.0, 0.62, 0.3)
	p.pod.add_child(stripe)
	# ... and a bar of it across the tail, to be found by from behind
	var tail := MeshInstance3D.new()
	tail.mesh = _mesh("tail", func(): return Kit.box(Vector3(1.9, 0.24, 0.12)))
	tail.material_override = stripe_mat
	tail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	tail.position = Vector3(0.0, 0.2, 2.08)
	p.pod.add_child(tail)
	# from a distance: a pod and two engines as plain blocks, in the pod's own frame (its nose is -z)
	p.far = Node3D.new()
	p.far.visible = false
	p.node.add_child(p.far)
	var reach := _engines_ahead()
	var blocks := [[Vector3(float(sim.P.podWidth), 1.1, float(sim.P.podLen)), Vector3(0.0, 0.3, 0.0), stripe_mat]]
	for side in [-1.0, 1.0]:
		blocks.append([Vector3(CraftModelScript.ENG_W, 1.3, float(sim.P.engineLen)), Vector3(side * float(sim.P.engineGap) / 2.0, 0.3 - CraftModelScript.POD_LIFT, -reach), finish])
	for b: Array in blocks:
		var block := MeshInstance3D.new()
		var size: Vector3 = b[0]
		block.mesh = _mesh("block%s" % size, func(): return Kit.box(size))
		block.material_override = b[2]
		block.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		block.position = b[1]
		p.far.add_child(block)


## A place in the sim's plane at height z over the flat ground, as the view draws it (its floating
## origin). Not the view's own w3: that adds the banked road's height as it is near the pilot's pod,
## and a racing pilot's own (in _pose) is of where it is, which may be a hundred kilometres off.
func _w(x: float, y: float, z: float) -> Vector3:
	return Vector3(x - view.org_x, z, -(y - view.org_y))


func _draw(p: Pilot) -> void:
	if p.node == null:
		return
	var from := eye if eye.is_finite() else Vector2(sim.pod.x, sim.pod.y)
	var near: bool = absf(p.x - from.x) < DRAW_R and absf(p.y - from.y) < DRAW_R
	if p.node.visible != near:
		p.node.visible = near
	if not near:
		return
	var fw := Vector2(cos(p.th), sin(p.th))
	var lf := Vector2(-fw.y, fw.x)
	var reach := _engines_ahead()
	var att := Basis.from_euler(Vector3(0.0, p.th - PI / 2.0, p.roll))
	var whole: bool = absf(p.x - from.x) < WHOLE_R and absf(p.y - from.y) < WHOLE_R
	if whole != p.whole:
		p.whole = whole
		p.far.visible = not whole
		p.pod.visible = whole
		for k in 2:
			p.engines[k].visible = whole
			p.cables[k].visible = whole
	if not whole:
		p.far.transform = Transform3D(att, _w(p.x, p.y, p.z - 0.2 + CraftModelScript.POD_LIFT))
		return
	p.pod.transform = Transform3D(att, _w(p.x, p.y, p.z - 0.2 + CraftModelScript.POD_LIFT))
	for k in 2:
		var sd := 1.0 if k == 0 else -1.0
		var e: Vector2 = Vector2(p.x, p.y) + fw * reach + lf * sd * sim.P.engineGap / 2.0
		var eng: Node3D = p.engines[k]
		# (the engines stand on the same banked road: a little higher or lower than the pod across it)
		eng.transform = Transform3D(att, _w(e.x, e.y, p.z + 0.1 - sd * sim.P.engineGap / 2.0 * sin(p.roll)))
		var fl: MeshInstance3D = p.flames[k]
		fl.visible = p.push > 0.02
		if fl.visible:
			var ln := 1.5 + 2.0 * p.push + (10.0 * p.push if p.v > 700.0 else 0.0)
			fl.scale = Vector3(1.0, 1.0, ln)
			fl.position = Vector3(0.0, 0.0, 4.0 + ln / 2.0)
		var a: Vector3 = eng.transform * CraftModelScript.ENGINE_EYE
		var b: Vector3 = p.pod.transform * Vector3(-sd * sim.P.podAnchorW * sim.P.podWidth / 2.0, CraftModelScript.POD_EYE_H, -sim.P.podLen / 2.0 - 0.1)
		var c: MeshInstance3D = p.cables[k]
		var span := a - b
		if span.length() > 0.1:
			c.transform = Transform3D(Basis.looking_at(span, att.y) * Basis.from_scale(Vector3(1.0, 1.0, span.length())), (a + b) / 2.0)
