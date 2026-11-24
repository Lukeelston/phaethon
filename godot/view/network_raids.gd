## Raids on the Network: hostile raiders attack a city and the pilot shoots them (free flight; the Network only;
## docs/superpowers/specs/2026-11-24-network-raids-design.md). The director, after chase mode (view/network_chase.gd):
##   waiting   ""      a clock runs while one may start (a public road, not a shaft, at speed, and traffic's floor
##                     free: no street race or chase holding traffic.race_state): first_after s the first time
##   called    an alarm: of the ground cities that are neither the one the pilot is in (net.from, while within
##             arrive_r of its town) nor the last raid's, the nearest ahead in a straight line (within 90 degrees of the
##             way the craft goes; none ahead, the nearest); traffic's floor held ("raid"), so no racer or chase begins. Until the pilot is within arrive_r of its town zone it is not simulated: a commuter is
##             lost every tick_every s; at tick_cap, not reached, it is lost
##   on        arrived: the pack is placed in the town zone (R.mode == 0) on the city's road, over its lanes, as
##             traffic's own cars (hostile: kept wherever they are, never turned round). It ends when no raider is
##             left (cleared if any was killed, else lost), or lost: the pilot away_t s beyond R_KEEP of the town,
##             or time_limit s gone. Surviving raiders flee: taken out of traffic. The floor is released
##   over      the lull after one, lull s (the same clock as the first wait) until the next is called
## A restart (reset), or a crash and the sim's respawn after it, sets a raid aside: no award, the pack gone, the
## floor free.
##   var raids := Raids.new(); view.add_child(raids); raids.traffic = view.traffic_net; raids.build(view)
##   raids.update(delta)            every frame, after traffic's own update and chase's
##   raids.on_kill(car)             a raider shot (the gun's, before traffic.knock_out)
##   raids.reset()                  on a restart (a crash's respawn it sees for itself: sim.crash_t)
##   raids.text()                   the dash's line while a raid is on ("" otherwise)
##   raids.result                   "cleared" | "lost", once, for the view to take
## Log lines (the flight log): RAID: alarm <CITY> <km> | arrived | kill | cleared | lost (<why>)
extends Node3D

const Settings := preload("res://release/game_settings.gd")
const Traffic := preload("res://view/network_traffic.gd")
const MODES := [["off", "Off"], ["on", "On"]]       # the menus' row: [id, name]
const MPH := 2.236936
const RAIDER_VISUAL := Traffic.DEMON     # the raiders' model (a demon's, until Codex's raider has its own slot)
const READY_V := 900.0 / MPH             # m/s: "at speed", chase's figure
const ZONE_STEP := 20                    # samples (480 m) between the town zone's points its distance is read from
const CLEAR_OF_PILOT := 1500.0           # m: no raider is put down nearer the pilot than this (unless the zone has no room)
const HEADING_BELOW := 30.0              # m/s: slower, the pick looks the way the craft points, not the way it goes

static var enabled := false      # raids
static var pinned := false       # a test or a render chose it: the saved choice does not replace it

var traffic
var view
var sim
var result := ""
var tally := {"cleared": 0, "lost": 0}
var state := ""                  # "" waiting | "called" | "on" | "over" (the lull after one)
var city := -1                   # the raid's city: an index into sim.cities
var lost := 0                    # commuters lost: off-screen ticks (and, task 4, the raiders' kills)
var kills := 0                   # raiders shot
var fled := 0                    # raiders gone without being shot (task 4)
var pack: Array = []             # this raid's raiders still in traffic
var called_m := 0.0              # m to the city (a straight line to its centre) when the alarm went
# tunables (tests shorten them)
var first_after := 60.0          # s of waiting before a flight's first
var lull := Vector2(60.0, 90.0)  # s of waiting after one, drawn between these
var arrive_r := 15000.0          # m from the town zone: in range, and the pack is placed
var time_limit := 120.0          # s from arriving
var away_t := 20.0               # s beyond R_KEEP of the town zone after arriving
var tick_every := 5.0            # s between commuters lost while it is off-screen
var tick_cap := 40               # ... and the most lost that way
var pack_size := Vector2i(4, 6)  # the first raid brings x, each later one 1 more, up to y

var _clock := 0.0                # s it may start (it falls back while it may not)
var _lull_len := -1.0            # s of this lull (-1: none drawn yet)
var _count := 0                  # raids called this flight
var _made := 0                   # raiders made this flight (their ids)
var _tick_t := 0.0               # s toward the next commuter lost off-screen
var _t := 0.0                    # s since arriving
var _away := 0.0                 # s beyond R_KEEP of the town zone
var _why := ""                   # why the last was lost: "away" | "time" | "fled" | "not reached"
var _last_city := -1             # the last raid's city: not picked for the next
var _wrecked := false            # the craft is down (sim.crash_t): the sim respawns it when that runs out
var _killed := {}                # Car -> true: this raid's raiders shot (on_kill), before traffic loses them
var _zones := {}                 # city -> {"road", "z": Vector2i(first, last sample of its town zone), "pts"}
var _rng := RandomNumberGenerator.new()


static func ids(rows: Array) -> Array:
	return rows.map(func(entry): return entry[0])


static func load_saved() -> void:
	if not pinned:
		enabled = Settings.choice("raids", ids(MODES)) == "on"


func build(v) -> void:           # (set `traffic` first: view.traffic_net)
	view = v
	sim = v.sim
	name = "network_raids"
	_rng.seed = 20261124


## Is the pilot where one can begin: on a public road, not in a shaft, at speed, with traffic's floor free?
func _ready_for_one() -> bool:
	var P = sim.pod
	if P.off_road or traffic.race_state != "":
		return false
	var R = sim.roads[P.path]
	return traffic._public_road(R) and not R.shaft and Vector2(P.vx, P.vy).length() > READY_V


## The wait before the next: a flight's first, or this lull.
func _due() -> float:
	if _count == 0:
		return first_after
	return _lull_len if _lull_len >= 0.0 else lull.x


func update(delta: float) -> void:
	if traffic == null:
		return
	# A crash (any of the sim's: smash, binder, wreck) sets crash_t, and the sim respawns the craft when it runs out
	# (craft_sim.gd step): a raid then is set aside as a restart sets it aside.
	if sim.crash_t > 0.0:
		_wrecked = true
	elif _wrecked:
		_wrecked = false
		if state == "called" or state == "on":
			reset("crash")
			return
	match state:
		"", "over":
			_clock = _clock + delta if _ready_for_one() else maxf(_clock - delta, 0.0)
			if _clock >= _due() and not _alarm():
				_clock *= 0.5
		"called":
			_tick_t += delta
			while _tick_t >= tick_every and lost < tick_cap:
				_tick_t -= tick_every
				lost += 1
			if _gap(city) <= arrive_r:
				_arrive()
			elif lost >= tick_cap:      # it is over before the pilot got there
				_end("lost", "not reached")
		"on":
			_t += delta
			for k in range(pack.size() - 1, -1, -1):
				if not traffic.cars.has(pack[k]):      # shot (on_kill, then knock_out) or gone
					pack.remove_at(k)
			if pack.is_empty():
				_end("cleared" if kills > 0 else "lost", "fled")
				return
			_away = _away + delta if _gap(city) > Traffic.R_KEEP else 0.0
			if _away >= away_t:
				_end("lost", "away")
			elif _t >= time_limit:
				_end("lost", "time")


## The alarm: a city picked and traffic's floor taken. -> false if there is none to pick.
func _alarm() -> bool:
	var k := _pick()
	if k < 0:
		return false
	city = k
	_last_city = k
	state = "called"
	traffic.race_state = "raid"     # (not one of the racer's own states: its machine stands by while this runs)
	traffic.race_t = 0.0
	lost = 0
	kills = 0
	fled = 0
	pack.clear()
	_killed.clear()
	_tick_t = 0.0
	_t = 0.0
	_away = 0.0
	_count += 1
	print("RAID: alarm %s %d" % [sim.cities[k].name, roundi(called_m / 1000.0)])
	return true


## The raid's city, of the ground cities (an orbit entry is never one) that are not the one the pilot is in
## (net.from, while within arrive_r of its town) nor the last raid's: the nearest in a straight line (to its centre)
## of those ahead, its bearing within 90 degrees of the way the craft goes (its velocity; the way it points when
## slower than HEADING_BELOW), so it is not sent to one behind it; none ahead, the nearest. -1 for none. Sets
## called_m. (Five distances: nothing to see in a frame.)
func _pick() -> int:
	var P = sim.pod
	var at := Vector2(P.x, P.y)
	var way := Vector2(P.vx, P.vy)
	if way.length() < HEADING_BELOW:
		way = Vector2(cos(P.th), sin(P.th))
	var best := -1
	var bd := INF
	var ahead := -1
	var ad := INF
	for k in sim.cities.size():
		var c: Dictionary = sim.cities[k]
		if String(c.get("kind", "")) == "orbit" or k == _last_city:
			continue
		if k == int(sim.net.from) and _gap(k) <= arrive_r:
			continue
		var to := Vector2(float(c.cx), float(c.cy)) - at
		var d := to.length()
		if d < bd:
			bd = d
			best = k
		if to.dot(way) > 0.0 and d < ad:
			ad = d
			ahead = k
	if ahead >= 0:
		called_m = ad
		return ahead
	called_m = bd
	return best


## City k's town zone: the run of STARFIGHTER samples (R.mode == 0) about its terminal on its road, and points
## along it every ZONE_STEP samples (its distance is read from them).
func _zone(k: int) -> Dictionary:
	if _zones.has(k):
		return _zones[k]
	var c: Dictionary = sim.cities[k]
	var road := int(c.road)
	var R = sim.roads[road]
	var i := clampi(int(c.i), 0, R.N - 1)
	var at := -1
	for d in R.N:
		if i - d >= 0 and R.mode[i - d] == 0:
			at = i - d
			break
		if i + d < R.N and R.mode[i + d] == 0:
			at = i + d
			break
	var z := Vector2i(maxi(i - 40, 0), mini(i + 40, R.N - 1))     # (a road with no zone: about its terminal)
	if at >= 0:
		z = Vector2i(at, at)
		while z.x > 0 and R.mode[z.x - 1] == 0:
			z.x -= 1
		while z.y < R.N - 1 and R.mode[z.y + 1] == 0:
			z.y += 1
	var pts := PackedVector2Array()
	for s in range(z.x, z.y, ZONE_STEP):
		pts.append(Vector2(R.px[s], R.py[s]))
	pts.append(Vector2(R.px[z.y], R.py[z.y]))
	_zones[k] = {"road": road, "z": z, "pts": pts}
	return _zones[k]


## m from the pilot to city k's town zone (to its nearest point read).
func _gap(k: int) -> float:
	var at := Vector2(sim.pod.x, sim.pod.y)
	var best := INF
	for p: Vector2 in _zone(k).pts:
		best = minf(best, at.distance_squared_to(p))
	return sqrt(best)


## In range: the pack is put down in the town zone on the city's road, spread along it and over its lanes, clear
## of the pilot and of traffic where there is room, going the way the road's traffic goes.
func _arrive() -> void:
	var zone := _zone(city)
	var road: int = zone.road
	var z: Vector2i = zone.z
	var R = sim.roads[road]
	var n := mini(pack_size.x + _count - 1, pack_size.y)
	var nl: int = traffic._lanes[road].size()
	var way := int(traffic.oneway.get(road, 1))
	var at := Vector2(sim.pod.x, sim.pod.y)
	var stations := []
	var room := []
	var m := n * 4
	for s in m:
		var f := lerpf(float(z.x) + 2.0, float(z.y) - 2.0, (s + 0.5) / m)
		var i := clampi(int(f), 0, R.N - 1)
		stations.append(f)
		if at.distance_to(Vector2(R.px[i], R.py[i])) >= CLEAR_OF_PILOT:
			room.append(f)
	if room.size() < n:
		room = stations      # (the pilot is in the middle of it: anywhere in the zone)
	for k in n:
		var c := Traffic.Car.new()
		c.id = 960000 + _made
		_made += 1
		c.kind = Traffic.DEMON
		c.visual = RAIDER_VISUAL
		c.hostile = true
		c.name = "RAIDER"
		c.road = road
		c.dir = way
		c.f = float(room[int((k + 0.5) * room.size() / n)])
		c.v = Traffic.SF_V
		c.vdes = Traffic.SF_V          # the town's limit (task 4 sets it toward its prey)
		c.a_up = 3.0 * Traffic.G
		c.a_lat = 11.0 * Traffic.G
		c.headway = 0.45
		c.turn_p = 0.0                 # it keeps to the city's road
		c.col = Traffic.HOSTILE_COL
		c.nsp_road = -1
		var spread := int((k + 0.5) * nl / n)
		c.lane = spread
		for dl in nl:                  # its lane, or the next one clear of the traffic there
			c.lane = (spread + dl) % nl
			c.lat = traffic._lane_lat(c, c.lane)
			if traffic._spawn_clear(c):
				break
			c.lane = spread
		c.lat = traffic._lane_lat(c, c.lane)
		traffic._place(c)
		traffic.cars.append(c)
		pack.append(c)
	state = "on"
	_t = 0.0
	_away = 0.0
	print("RAID: arrived")


## A raider shot (the gun's: before traffic.knock_out takes it out of traffic).
func on_kill(c) -> void:
	if not pack.has(c) or _killed.has(c):
		return
	_killed[c] = true
	kills += 1
	print("RAID: kill")


func _end(how: String, why := "") -> void:
	result = how
	tally[how] = int(tally[how]) + 1
	_why = why if how == "lost" else ""
	if how == "cleared":
		print("RAID: cleared")
	else:
		print("RAID: lost (%s)" % why)
	_disband()
	state = "over"
	_clock = 0.0
	_lull_len = _rng.randf_range(lull.x, lull.y)


## The pack flees: what is left of it is taken out of traffic, and the floor is free again.
func _disband() -> void:
	for c in pack:
		traffic.cars.erase(c)
	pack.clear()
	_killed.clear()
	if traffic.race_state == "raid":
		traffic.race_state = ""


func reset(why := "restart") -> void:
	if traffic != null:
		if state == "called" or state == "on":
			print("RAID: set aside (%s)" % why)
		_disband()
	result = ""
	state = ""
	city = -1
	lost = 0
	kills = 0
	fled = 0
	_clock = 0.0
	_tick_t = 0.0
	_t = 0.0
	_away = 0.0
	if _count > 0:
		_lull_len = _rng.randf_range(lull.x, lull.y)


func text() -> String:
	return ""
