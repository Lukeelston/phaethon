## Raids' flyers: the drones over a raided city's town zone (docs/superpowers/specs/2026-11-24-network-raids-design.md,
## "Drones and the gunship"; the stage 2 plan, task 2). Made by the raid director at its build (view/network_raids.gd,
## so with Raids on only), and empty until a raid arrives; the drone's model (Codex's, view/raid_flyer_art.gd) is loaded
## when the first drones are put down, and its batch kept for the flight.
##   drones   put down at the arrival (spawn_drones) in groups of two to four, spread along the zone's road (clear of the
##            pilot where it has room, as the raiders are), each group circling its own point of the road at CIRCLE_V,
##            each drone at its own height, DRONE_ALT above the road. One off its rest (DIVE_REST s from its last dive's
##            end) looks for its prey every LOOK_EVERY frames (staggered by its id): the pilot, if this dive is to be the
##            pilot's (drawn at each dive's end: PILOT_SHARE of them) and the craft is within PILOT_REACH of it over the
##            ground; else the nearest commuter under its group that no other drone is diving on (on the group's road,
##            either way, within PREY_REACH of its point along it: looked for in traffic's buckets, traffic.same_way, as
##            the director's prey_of looks).
##            It dives from where it is to its prey's height over DIVE_S, nose first (its red lamp leading), led to where
##            its prey will be at the dive's end: a commuter's all the way down; the pilot's until DIVE_COMMIT s from it,
##            and then straight on to that point, so a dive on the craft seen coming can be dodged (a commuter braking into
##            the town at 4 g would be missed by 11 m from such a point). A dive on the craft ends DIVE_SHORT short of the
##            pod along its way in, at the pod's height: on the craft, never through the cockpit and the pilot's eye. One
##            that ends within DIVE_HIT of a commuter knocks it out (the director's _run_down: traffic.knock_out, lost,
##            commuter_lost); one that ends within DIVE_HIT of the pod or an engine is a hit taken (the director's
##            hit_by("drone"): its one GRACE clock, shared with the raiders' rams). Then it climbs back to its place in its
##            group's circle over CLIMB_S.
##   shot     DRONE_HP hits: the fire control's damage calls hit(f, n), which destroys it at none left; the director then
##            counts it from its own kind (on_kill: kills_by.drone)
## Positions are the sims' frame (x, y, height), as the fire control's bolts are; the drones' batch is drawn about the
## view's floating origin, its buffer written once a frame. A frame of theirs (update) allocates nothing (a look for
## prey halves a bucket; the batch's buffer is kept); only what a dive's end sets off does (a commuter's run-down, a
## hit taken, their log lines).
##   flyers.build(view, director)              the director's build (no model loaded, nothing drawn)
##   flyers.spawn_drones(zone, n)              its arrival: `zone` is the director's _zone(k) ({road, z, pts})
##   flyers.update(delta)                      each frame of a raid on, in the director's update: they fly; drawn
##   flyers.clear()                            the raid's end, a restart: every flyer gone
##   flyers.all() / has(f) / count(kind)       the director's rules, the fire control's targets (all() is the live list)
##   flyers.ray_pick(o, d, reach)              the fire control's aim: {"car": Flyer, "t": m along the ray} or {}
##   flyers.ray_flyer(f, o, d, pad)            ... one flyer's sphere (its pick radius r, fattened by pad): t, or -1
##   flyers.hit(f, n) / destroy(f)             the fire control's damage
##   flyers.marks(x, y, r)                     the maps: [[x, y, Traffic.HOSTILE_MARK], ...] within r of (x, y)
extends Node3D

const Traffic := preload("res://view/network_traffic.gd")
const Art := preload("res://view/raid_flyer_art.gd")

const DRONE_HP := 2                       # hits a drone takes
const DRONE_ALT := Vector2(60.0, 120.0)   # m above the road a drone circles at (each its own)
const DIVE_S := 2.0                       # s a dive takes from its start to its prey's height (never under 1.5 on the pilot)
const DIVE_REST := 4.0                    # s from a dive's end before that drone may dive again
const PILOT_SHARE := 0.25                 # of dives go at the pilot (when it is within PILOT_REACH)
const DIVE_HIT := 10.0                    # m: a dive that ends this near its prey (the pod or an engine) takes it
const LOOK_EVERY := 6                     # frames between a drone's looks for prey (staggered by its id)
const DRONE_R := 6.0                      # m: a drone's pick radius
const MAX_DRONES := 10                    # the batch's room (the most a raid brings)
const DIVE_COMMIT := 0.75                 # s before a dive's end on the pilot it stops leading the craft: on in a straight line
const DIVE_SHORT := 6.0                   # m short of the pod (along the drone's way in, over the ground) a dive on the pilot ends
const CLIMB_S := 3.0                      # s to climb back to its place in its group's circle
const PILOT_REACH := 1500.0               # m over the ground from a drone to the craft for it to dive on the pilot
const PREY_REACH := 1000.0                # m along the road from its group's point: a commuter there is under it
const CIRCLE_R := Vector2(120.0, 220.0)   # m: a group's circle (each its own)
const CIRCLE_V := 80.0                    # m/s round it
const BANK := 0.35                        # rad: a circling drone's bank into its turn
const CLEAR_OF_PILOT := 1500.0            # m: no group is put down nearer the pilot than this (where the zone has room)
const ID_BASE := 970000                   # flyers' ids (the raiders' are 960000 on)
const NONE := {}                          # (ray_pick's miss: read only)


## One flyer: what the fire control reads off a traffic Car (x, y, hx, hy, v, id, hostile) and a flyer's own.
class Flyer:
	var id := 0
	var kind := "drone"         # "drone" | "gunship"
	var x := 0.0                # the sims' frame: m east, north, and up
	var y := 0.0
	var z := 0.0
	var vx := 0.0               # m/s
	var vy := 0.0
	var vz := 0.0
	var hx := 1.0               # its heading over the ground (a unit vector) and its speed there, kept each frame
	var hy := 0.0
	var v := 0.0
	var hp := 0
	var hp_max := 0
	var r := 6.0                # m: its pick radius
	var hostile := true
	var flyer := true
	var state := "circle"       # a drone's: "circle" | "dive" | "climb"
	var group := 0              # its group (an index into the module's _groups)
	var alt := 90.0             # m above the road it circles at
	var phase := 0.0            # rad: its place round its group's circle
	var rest := 0.0             # s before it may dive again
	var dive_t := 0.0           # s into its dive, or its climb
	var prey = null             # the commuter it dives on (a traffic Car), or null
	var at_pod := false         # its dive is the pilot's (before it: its next dive is to be, if the craft is near)
	var ax := 0.0               # where its dive (or its climb) ends, the sims' frame
	var ay := 0.0
	var az := 0.0


## A group of drones: its point on the zone's road, and its circle about it.
class Group:
	var road := 0
	var f := 0.0                # its point: a sample of the zone's road
	var x := 0.0                # ... there, the sims' frame
	var y := 0.0
	var deck := 0.0             # the road's height there
	var radius := 160.0         # m
	var spin := 0.5             # rad/s round it (+: counterclockwise seen from above, a left turn)


var view
var director
var sim
var traffic
var batch: MultiMeshInstance3D = null     # the drones' batch (Codex's model), made when the first drones are put down
var pilot_share := PILOT_SHARE            # (tests set it)
var update_ms := 0.0                      # what the last update took (tests read it)
var _list: Array = []                     # every flyer up
var _groups: Array = []                   # the drones' groups (Group)
var _made := 0                            # flyers made this flight (their ids)
var _frame_n := 0                         # frames flown (the looks are staggered by it)
var _buf := PackedFloat32Array()          # the batch's buffer: a 3x4 transform a drone, written once a frame
var _rng := RandomNumberGenerator.new()


func build(v, d) -> void:
	view = v
	director = d
	sim = v.sim
	traffic = d.traffic
	name = "raid_flyers"
	_rng.seed = 20261126


## The raid's drones put down over `zone` (the director's _zone(k)): `n` of them (as many as the batch has room for),
## in groups of two to four spread along its road, clear of the pilot where it has room.
func spawn_drones(zone: Dictionary, n: int) -> void:
	n = mini(n, MAX_DRONES - count("drone"))
	if n <= 0:
		return
	traffic = director.traffic
	_make_batch()
	var road: int = zone.road
	var z: Vector2i = zone.z
	var R = sim.roads[road]
	var ng := maxi(1, ceili(n / 3.0))     # (groups of three, two or four: 6 is 3 + 3, 7 is 3 + 2 + 2, 10 is 3 + 3 + 2 + 2)
	var at := Vector2(sim.pod.x, sim.pod.y)
	var stations := []
	var room := []
	var m := ng * 4
	for s in m:
		var f := lerpf(float(z.x) + 2.0, float(z.y) - 2.0, (s + 0.5) / m)
		var i := clampi(int(f), 0, R.N - 1)
		stations.append(f)
		if at.distance_to(Vector2(R.px[i], R.py[i])) >= CLEAR_OF_PILOT:
			room.append(f)
	if room.size() < ng:
		room = stations      # (the pilot is in the middle of it: anywhere in the zone)
	for k in ng:
		var G := Group.new()
		G.road = road
		G.f = float(room[int((k + 0.5) * room.size() / ng)])
		var i := clampi(int(G.f), 0, R.N - 1)
		G.x = R.px[i]
		G.y = R.py[i]
		G.deck = sim.net_height(road, G.f)
		G.radius = _rng.randf_range(CIRCLE_R.x, CIRCLE_R.y)
		G.spin = (1.0 if _rng.randf() < 0.5 else -1.0) * CIRCLE_V / G.radius
		_groups.append(G)
		var size := n / ng + int(k < n % ng)
		var phase0 := _rng.randf() * TAU
		for j in size:
			var f := Flyer.new()
			f.id = ID_BASE + _made
			_made += 1
			f.kind = "drone"
			f.hp = DRONE_HP
			f.hp_max = DRONE_HP
			f.r = DRONE_R
			f.group = _groups.size() - 1
			f.alt = _rng.randf_range(DRONE_ALT.x, DRONE_ALT.y)
			f.phase = phase0 + TAU * j / size
			f.rest = _rng.randf_range(0.5, DIVE_REST)      # (a group's drones do not all dive at once)
			f.at_pod = _rng.randf() < pilot_share
			f.state = "circle"
			_circle(f, G, 0.0)
			_list.append(f)
	print("RAID: %d drones over %s in %d groups" % [n, R.name, ng])
	_draw_batch()


## The drones' batch: Codex's model, loaded now (the first drones put down), and kept. Never culled for where its
## mesh's own box is (it is drawn about the floating origin), and drawn larger far off as traffic's bodies are, so a
## drone is never under a couple of pixels wide.
func _make_batch() -> void:
	if batch != null:
		return
	batch = Art.drone_batch(MAX_DRONES)
	batch.custom_aabb = Traffic.BODY_BOUNDS
	batch.set_instance_shader_parameter("grow_per_m", Traffic.BODY_MIN_ANG / 3.0)      # (a drone's half width, about 3 m)
	add_child(batch)
	_buf.resize(MAX_DRONES * 12)
	_buf.fill(0.0)


func update(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_frame_n += 1
	for f: Flyer in _list:
		if f.kind == "drone":
			_drone(f, delta)
	_draw_batch()
	update_ms = (Time.get_ticks_usec() - t0) / 1000.0


## One drone's frame: its rest runs down; it dives, climbs, or circles (and, off its rest, looks for its prey).
func _drone(f: Flyer, delta: float) -> void:
	var G: Group = _groups[f.group]
	f.rest = maxf(f.rest - delta, 0.0)
	if f.state == "dive":
		_dive_step(f, delta)
	elif f.state == "climb":
		_climb_step(f, G, delta)
	else:
		_circle(f, G, delta)
		if f.rest <= 0.0 and (_frame_n + f.id) % LOOK_EVERY == 0:
			_look(f, G)


## Round its group's circle, `delta` s on: its place and its way.
func _circle(f: Flyer, G: Group, delta: float) -> void:
	f.phase = fmod(f.phase + G.spin * delta, TAU)
	var c := cos(f.phase)
	var s := sin(f.phase)
	f.x = G.x + G.radius * c
	f.y = G.y + G.radius * s
	f.z = G.deck + f.alt
	_moving(f, -s * G.radius * G.spin, c * G.radius * G.spin, 0.0)


## Its velocity, and its heading and speed over the ground from it (the fire control leads it by these).
static func _moving(f: Flyer, vx: float, vy: float, vz: float) -> void:
	f.vx = vx
	f.vy = vy
	f.vz = vz
	f.v = sqrt(vx * vx + vy * vy)
	if f.v > 0.01:
		f.hx = vx / f.v
		f.hy = vy / f.v


## A drone off its rest looks for its prey: the pilot, when this dive is to be the pilot's and the craft is within
## PILOT_REACH of it over the ground (and not down); else the nearest commuter under its group. With none it circles on
## and looks again LOOK_EVERY frames later.
func _look(f: Flyer, G: Group) -> void:
	var P = sim.pod
	if f.at_pod and sim.crash_t <= 0.0:
		var dx: float = P.x - f.x
		var dy: float = P.y - f.y
		if dx * dx + dy * dy <= PILOT_REACH * PILOT_REACH:
			_dive(f, null, true)
			return
	var c = _prey_for(f, G)
	if c != null:
		_dive(f, c, false)


## The nearest commuter to drone f under its group that no other drone is diving on: on the group's road, either way,
## within PREY_REACH of its point along the road. Looked for in traffic's two buckets of that road (traffic.same_way:
## each in order along its way, mostly, entered by halving), not among every car; when the fleet has changed since
## traffic's update, among every car. One gone since that update is none (it looks again next time).
func _prey_for(f: Flyer, G: Group):
	var R = sim.roads[G.road]
	var span: float = PREY_REACH / float(R.len[clampi(int(G.f), 0, R.N - 1)])
	var best = null
	var bd := INF
	for k in 2:
		var way := 1 - 2 * k
		var pool = traffic.same_way(G.road, way)
		if pool == null:
			return _prey_among_all(f, G, span)
		# the bucket runs up its way (f x way rising): its first entry at or past the span's near end, by halving
		var near_key: float = G.f * way - span
		var far_key: float = G.f * way + span
		var lo := 0
		var hi: int = pool.size()
		while lo < hi:
			var mid := (lo + hi) >> 1
			var o = pool[mid]
			if o.f * o.dir < near_key:
				lo = mid + 1
			else:
				hi = mid
		for i in range(lo, pool.size()):
			var o = pool[i]
			if o.f * o.dir > far_key:
				break
			if o.hostile or o.id == 0 or o.craft or o == traffic.racer or o.road != G.road or o.dir != way:      # (the pod's stand-in; one moved on since)
				continue
			var dx: float = o.x - f.x
			var dy: float = o.y - f.y
			var d2 := dx * dx + dy * dy
			if d2 < bd and not _dived_on(o):
				bd = d2
				best = o
	if best != null and not traffic.cars.has(best):
		return null      # (gone since traffic's update this frame)
	return best


## ... among every car (the fleet changed since traffic's update: its buckets are stale).
func _prey_among_all(f: Flyer, G: Group, span: float):
	var best = null
	var bd := INF
	for o in traffic.cars:
		if o.hostile or o.craft or o == traffic.racer or o.road != G.road or absf(o.f - G.f) > span:
			continue
		var dx: float = o.x - f.x
		var dy: float = o.y - f.y
		var d2 := dx * dx + dy * dy
		if d2 < bd and not _dived_on(o):
			bd = d2
			best = o
	return best


## Is a drone diving on commuter c already?
func _dived_on(c) -> bool:
	for o: Flyer in _list:
		if o.prey == c:
			return true
	return false


## Drone f dives, from where it is, over DIVE_S: on `prey` (a commuter), or on the pilot (`pilot`).
func _dive(f: Flyer, prey, pilot: bool) -> void:
	f.state = "dive"
	f.dive_t = 0.0
	f.prey = null if pilot else prey
	f.at_pod = pilot
	_aim(f, DIVE_S)
	if pilot:
		print("RAID: drone dives on you")


## Where drone f's prey will be `left` s on, the sims' frame: the pod (its way led; DIVE_SHORT short of it, back
## toward the drone over the ground), or the commuter's middle (its way along its road led, at the height of its body
## there now).
func _aim(f: Flyer, left: float) -> void:
	if f.at_pod:
		var P = sim.pod
		f.ax = P.x + P.vx * left
		f.ay = P.y + P.vy * left
		f.az = P.z + P.vz * left
		var bx: float = f.x - f.ax
		var by: float = f.y - f.ay
		var back := sqrt(bx * bx + by * by)
		if back < 0.001:      # (straight above it: beside it, to its left)
			bx = cos(float(P.th) + PI * 0.5)
			by = sin(float(P.th) + PI * 0.5)
			back = 1.0
		f.ax += bx / back * DIVE_SHORT
		f.ay += by / back * DIVE_SHORT
	elif f.prey != null:
		var c = f.prey
		f.ax = c.x + c.hx * c.v * left
		f.ay = c.y + c.hy * c.v * left
		f.az = traffic.body_height(c)


## A dive's frame: led to where its prey will be at the dive's end (the pilot's until DIVE_COMMIT s from it: then on
## to that point in a straight line), arriving at its end; there, what it ends on. (`left` is from the last frame; its
## prey's place is this frame's, so the end is left - delta on from it.)
func _dive_step(f: Flyer, delta: float) -> void:
	var left := DIVE_S - f.dive_t
	if left > DIVE_COMMIT or not f.at_pod:
		_aim(f, maxf(left - delta, 0.0))
	if left <= delta + 1.0e-6:
		var last := maxf(left, 1.0e-3)
		_moving(f, (f.ax - f.x) / last, (f.ay - f.y) / last, (f.az - f.z) / last)
		f.x = f.ax
		f.y = f.ay
		f.z = f.az
		f.dive_t = DIVE_S
		_dive_end(f)
		return
	var vx := (f.ax - f.x) / left
	var vy := (f.ay - f.y) / left
	var vz := (f.az - f.z) / left
	_moving(f, vx, vy, vz)
	f.x += vx * delta
	f.y += vy * delta
	f.z += vz * delta
	f.dive_t += delta


## A dive's end: on the pilot, within DIVE_HIT of the pod or an engine, a hit taken (under the director's one grace);
## on a commuter still in traffic, within DIVE_HIT of its middle, it is knocked out and lost. Then the climb back, its
## rest begun, and whether its next dive is to be the pilot's drawn.
func _dive_end(f: Flyer) -> void:
	var r2 := DIVE_HIT * DIVE_HIT
	if f.at_pod:
		for b in sim.bodies:
			var dx: float = b.x - f.x
			var dy: float = b.y - f.y
			var dz: float = b.z - f.z
			if dx * dx + dy * dy + dz * dz <= r2:
				director.hit_by("drone")
				break
	elif f.prey != null:
		var c = f.prey
		if not c.hostile and traffic.cars.has(c):
			var dx: float = c.x - f.x
			var dy: float = c.y - f.y
			var dz: float = traffic.body_height(c) - f.z
			if dx * dx + dy * dy + dz * dz <= r2:
				director._run_down(c)
	f.prey = null
	f.state = "climb"
	f.dive_t = 0.0
	f.rest = DIVE_REST
	f.at_pod = _rng.randf() < pilot_share


## A climb's frame: on to its place in its group's circle as that will be at the climb's end, arriving then; there, it
## circles again.
func _climb_step(f: Flyer, G: Group, delta: float) -> void:
	f.phase = fmod(f.phase + G.spin * delta, TAU)      # (its place in the circle goes on round meanwhile)
	var left := CLIMB_S - f.dive_t
	f.dive_t += delta
	if left <= delta + 1.0e-6:
		f.state = "circle"
		_circle(f, G, 0.0)
		return
	var a := f.phase + G.spin * (left - delta)      # (its place at the climb's end: the phase is this frame's already)
	var vx := (G.x + G.radius * cos(a) - f.x) / left
	var vy := (G.y + G.radius * sin(a) - f.y) / left
	var vz := (G.deck + f.alt - f.z) / left
	_moving(f, vx, vy, vz)
	f.x += vx * delta
	f.y += vy * delta
	f.z += vz * delta


## The drones drawn: each one's transform (render frame, about the view's floating origin) into the batch's buffer, in
## all()'s order, and the buffer written once.
func _draw_batch() -> void:
	if batch == null:
		return
	var mm := batch.multimesh
	var ox: float = view.org_x
	var oy: float = view.org_y
	var n := 0
	for f: Flyer in _list:
		if f.kind != "drone":
			continue
		var b := _pose(f)
		var k := n * 12
		_buf[k] = b.x.x
		_buf[k + 1] = b.y.x
		_buf[k + 2] = b.z.x
		_buf[k + 3] = f.x - ox
		_buf[k + 4] = b.x.y
		_buf[k + 5] = b.y.y
		_buf[k + 6] = b.z.y
		_buf[k + 7] = f.z
		_buf[k + 8] = b.x.z
		_buf[k + 9] = b.y.z
		_buf[k + 10] = b.z.z
		_buf[k + 11] = -(f.y - oy)
		n += 1
	if n == 0 and mm.visible_instance_count == 0:
		return
	mm.buffer = _buf
	mm.visible_instance_count = n


## A drone's turn in the render frame: its nose (-Z, its lamp) along its way; circling, banked into its turn.
func _pose(f: Flyer) -> Basis:
	var fwd := Vector3(f.vx, f.vz, -f.vy)
	var speed := fwd.length()
	if speed < 0.5:
		fwd = Vector3(f.hx, 0.0, -f.hy)      # (all but still: the way it last went)
	else:
		fwd /= speed
	var up := Vector3.UP if absf(fwd.y) < 0.98 else Vector3(f.hx, 0.0, -f.hy)
	var b := Basis.looking_at(fwd, up)
	if f.state == "circle":
		var G: Group = _groups[f.group]
		b = b * Basis(Vector3(0, 0, 1), BANK * signf(G.spin))
	return b


## Every flyer gone (the raid's end, a restart), and nothing drawn.
func clear() -> void:
	_list.clear()
	_groups.clear()
	if batch != null:
		batch.multimesh.visible_instance_count = 0


## Every flyer up: the live list (read it; duplicate() it to destroy flyers while going through it).
func all() -> Array:
	return _list


func has(f) -> bool:
	return _list.has(f)


func count(kind: String) -> int:
	var n := 0
	for f: Flyer in _list:
		n += int(f.kind == kind)
	return n


## The nearest flyer along the ray (sims' frame: o, and d a unit vector) within `reach`: {"car": it, "t": m along the
## ray to its pick sphere}, or {} (NONE).
func ray_pick(o: Vector3, d: Vector3, reach: float) -> Dictionary:
	var best = null
	var best_t := reach
	for f: Flyer in _list:
		var t := ray_flyer(f, o, d)
		if t >= 0.0 and t < best_t:
			best_t = t
			best = f
	if best == null:
		return NONE
	return {"car": best, "t": best_t}


## Where the ray (o + t d, t >= 0, d a unit vector) first meets flyer f's pick sphere (its r, fattened by `pad`): t, or -1.
func ray_flyer(f, o: Vector3, d: Vector3, pad := 0.0) -> float:
	var cx: float = f.x - o.x
	var cy: float = f.y - o.y
	var cz: float = f.z - o.z
	var along := cx * d.x + cy * d.y + cz * d.z
	var miss2 := cx * cx + cy * cy + cz * cz - along * along
	var r: float = float(f.r) + pad
	if miss2 > r * r:
		return -1.0
	var back := sqrt(r * r - miss2)
	if along + back < 0.0:
		return -1.0      # (behind)
	return maxf(0.0, along - back)


## `n` hits on flyer f (the fire control's damage): true when that leaves it none, and it is destroyed.
func hit(f, n: int) -> bool:
	if not _list.has(f):
		return false
	f.hp -= n
	if f.hp > 0:
		return false
	destroy(f)
	return true


## Flyer f gone (shot down: the director counts it from its kind; or taken away).
func destroy(f) -> void:
	_list.erase(f)


## The flyers on the map: [[x, y, Traffic.HOSTILE_MARK], ...] within r of (x, y).
func marks(x: float, y: float, r: float) -> Array:
	var out := []
	for f: Flyer in _list:
		if absf(f.x - x) < r and absf(f.y - y) < r:
			out.append([f.x, f.y, Traffic.HOSTILE_MARK])
	return out
