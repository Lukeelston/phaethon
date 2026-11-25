## Raids on the Network: hostile raiders attack a city and the pilot shoots them (free flight; the Network only;
## docs/superpowers/specs/2026-11-24-network-raids-design.md). The director, after chase mode (view/network_chase.gd):
##   waiting   ""      a clock runs while one may start (a public road, not a shaft, at speed, and traffic's floor
##                     free: no street race or chase holding traffic.race_state): first_after s the first time
##   called    an alarm: of the ground cities that are neither the one the pilot is in (net.from, while within
##             arrive_r of its town) nor the last raid's, the nearest ahead in a straight line (within 90 degrees of the
##             way the craft goes; none ahead, the nearest); traffic's floor held ("raid"), so no racer or chase begins. Until the pilot is within arrive_r of its town zone it is not simulated: a commuter is
##             lost every tick_every s; at tick_cap, not reached, it is lost
##   on        arrived: the pack is placed in the town zone (R.mode == 0) on the city's road, over its lanes, as
##             traffic's own cars (hostile: kept wherever they are; traffic never turns one round). They keep to the
##             zone: TURN_SHORT m short of either end a raider turns round (_keep_in_zone), or on a one-way road (the
##             pilot's, traffic.oneway) is held there. It ends when no raider is left (cleared if any was killed,
##             else lost), or lost: the pilot away_t s beyond R_KEEP of the town and of every raider, or time_limit s
##             gone. Surviving raiders flee: taken out of traffic. The floor is released
##   over      the lull after one, lull s (the same clock as the first wait) until the next is called
## A restart (reset), or a crash and the sim's respawn after it, sets a raid aside: no award, the pack gone, the
## floor free.
##   var raids := Raids.new(); view.add_child(raids); raids.traffic = view.traffic_net; raids.build(view)
##   raids.update(delta)            every frame, after traffic's own update and chase's
##   raids.on_kill(car)             a raider shot (the gun's, before traffic.knock_out)
##   raids.prey_of(car)             a raider's prey: the nearest commuter ahead on its road and way, within 3 km (or null)
##   raids.reset()                  on a restart (a crash's respawn it sees for itself: sim.crash_t)
##   raids.text()                   the dash's line while one is called or on ("" otherwise): traffic's race_text() gives it
##   raids.result                   "cleared" | "lost", once, for the view to take
## Hunting: each frame a raider takes its prey's lane and the speed of it plus HUNT_DV (headway 0.05), and on contact
## (CONTACT_ALONG, CONTACT_LAT) the commuter is knocked out and lost; with no prey it cruises at the town limit. A raider
## gone from traffic without on_kill is fled: no award, kills unchanged.
## Contact: a raider within CONTACT_CRAFT of the pod or either engine is one hit taken a GRACE s (signal hit_taken: the
## view jolts, and the score takes its points; never health).
## Log lines (the flight log): RAID: alarm <CITY> <km> | arrived | kill | commuter lost | hit taken | raider fled | cleared | lost (<why>)
## The alarm: a tone made in code (alarm_tone: no recording), played once at each call on the director's own player (none
## in a flight without sound: --mute, a shot). A commuter run down: a burst where it was (view/raid_burst.gd), drawn from
## commuter_lost for whatever craft, armed or not. The tone, its player and the bursts' batch and shader are made at
## build (which only raids on reach), not at their first use mid-flight.
extends Node3D

## A commuter run down, at (x, y) in the sims' frame (for the view's effects).
signal commuter_lost(x: float, y: float)

## A raider rammed the craft: one hit taken (at most one a GRACE). `source` names what hit it.
signal hit_taken(source: String)

const Settings := preload("res://release/game_settings.gd")
const Traffic := preload("res://view/network_traffic.gd")
const Synth := preload("res://audio/course_audio.gd")
const Burst := preload("res://view/raid_burst.gd")
const ALARM_DB := -10.0                  # the alarm's level (unheard: 9 dB over the reward chimes' -19, 8 under the jolt's thump)
const MODES := [["off", "Off"], ["on", "On"]]       # the menus' row: [id, name]
const MPH := 2.236936
const RAIDER_VISUAL := Traffic.DEMON     # the raiders' model (a demon's, until Codex's raider has its own slot)
const READY_V := 900.0 / MPH             # m/s: "at speed", chase's figure
const ZONE_STEP := 20                    # samples (480 m) between the town zone's points its distance is read from
const CLEAR_OF_PILOT := 1500.0           # m: no raider is put down nearer the pilot than this (unless the zone has no room)
const HUNT_DV := 140.0 / MPH             # m/s: a hunting raider's closing speed over its prey
const CONTACT_ALONG := 30.0              # m along the road, and ...
const CONTACT_LAT := 12.0                # ... across it: contact with its prey, which is lost
const RAIDER_HEADWAY := 0.45              # s: a raider's headway with no prey
const PREY_REACH := 3000.0               # m: the farthest ahead a commuter is its prey
const HEADING_BELOW := 30.0              # m/s: slower, the pick looks the way the craft points, not the way it goes
const GRACE := 1.0                       # s: a raider in contact is one hit taken, then none for this long
const SAVED_START := 60                  # commuters a raid starts with: the clearing pays for each one not lost
## The score (view/skill_score.gd): raiders shot and raids cleared are awards; commuters lost, hits taken and
## commuters struck by the pilot's own fire are deductions (never health).
const RAID_POINTS := {"raider": 250, "cleared": 2000, "saved_each": 20, "commuter_lost": 40, "hit": 100, "struck": 150}
const CONTACT_CRAFT := 14.0              # m from the pod or either engine's centre to a raider's centre, in three dimensions: a ram
const TURN_SHORT := 500.0                # m short of either end of its town zone a raider turns round (or is held, one-way)

static var enabled := false      # raids
static var pinned := false       # a test or a render chose it: the saved choice does not replace it
static var _alarm_wav: AudioStreamWAV

var traffic
var view
var sim
var result := ""
var tally := {"cleared": 0, "lost": 0}
var state := ""                  # "" waiting | "called" | "on" | "over" (the lull after one)
var city := -1                   # the raid's city: an index into sim.cities
var lost := 0                    # commuters lost: off-screen ticks, and the commuters the raiders ran down
var kills := 0                   # raiders shot
var fled := 0                    # raiders gone without being shot
var pack: Array = []             # this raid's raiders still in traffic
var called_m := 0.0              # m to the city (a straight line to its centre) when the alarm went
var alarm: AlarmPlayer = null    # the alarm's player (made at build; none in a flight without sound)
var burst = null                 # the lost commuters' bursts (view/raid_burst.gd; made at build)
# tunables (tests shorten them)
var first_after := 60.0          # s of waiting before a flight's first
var lull := Vector2(60.0, 90.0)  # s of waiting after one, drawn between these
var arrive_r := 15000.0          # m from the town zone: in range, and the pack is placed
var time_limit := 120.0          # s from arriving
var away_t := 20.0               # s beyond R_KEEP of the town zone, and of every raider, after arriving
var tick_every := 5.0            # s between commuters lost while it is off-screen
var tick_cap := 40               # ... and the most lost that way
var pack_size := Vector2i(4, 6)  # the first raid brings x, each later one 1 more, up to y

var _grace := 0.0                # s before another hit may be taken
var _clock := 0.0                # s it may start (it falls back while it may not)
var _lull_len := -1.0            # s of this lull (-1: none drawn yet)
var _count := 0                  # raids called this flight
var _made := 0                   # raiders made this flight (their ids)
var _tick_t := 0.0               # s toward the next commuter lost off-screen
var _t := 0.0                    # s since arriving
var _away := 0.0                 # s beyond R_KEEP of the town zone and of every raider
var _why := ""                   # why the last was lost: "away" | "time" | "fled" | "not reached"
var _last_city := -1             # the last raid's city: not picked for the next
var _wrecked := false            # the craft is down (sim.crash_t): the sim respawns it when that runs out
var _killed := {}                # Car -> true: this raid's raiders shot (on_kill), before traffic loses them
var _zones := {}                 # city -> {"road", "z": Vector2i(first, last sample of its town zone), "pts"}
var _rng := RandomNumberGenerator.new()


## The alarm's player: it counts its plays.
class AlarmPlayer extends AudioStreamPlayer:
	var plays := 0

	func sound() -> void:
		plays += 1
		play()


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
	if not commuter_lost.is_connected(_burst_at):
		commuter_lost.connect(_burst_at)      # (the flash for a commuter lost: the director's own, whatever the craft)
	alarm_tone()          # (made now, not at the first call)
	_alarm_player()
	_make_burst()


## Is the pilot where one can begin: on a public road, not in a shaft, at speed, with traffic's floor free?
func _ready_for_one() -> bool:
	var P = sim.pod
	if P.off_road or traffic.race_state != "" or sim.crash_t > 0.0:      # (the craft is down: no alarm until its respawn)
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
	if burst != null:
		burst.sync(delta)
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
					if not _killed.has(pack[k]):       # gone and not shot: a safety net (traffic never drops one itself)
						fled += 1
						print("RAID: raider fled")
					pack.remove_at(k)
			if pack.is_empty():
				_end("cleared" if kills > 0 else "lost", "fled" if fled > 0 else "")
				return
			for c in pack:
				_hunt(c, delta)
				_keep_in_zone(c)
			_grace = maxf(_grace - delta, 0.0)
			if _grace <= 0.0 and sim.crash_t <= 0.0 and _in_contact():
				_grace = GRACE
				print("RAID: hit taken")
				hit_taken.emit("raider")
			_away = _away + delta if _far_from_it() else 0.0
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
	_grace = 0.0
	_count += 1
	print("RAID: alarm %s %d" % [sim.cities[k].name, roundi(called_m / 1000.0)])
	_sound_alarm()
	return true


## The alarm, once at the call (none in a flight without sound: --mute, a shot).
func _sound_alarm() -> void:
	var a := _alarm_player()
	if a != null:
		a.sound()


## The alarm's player: made at build, or at a call if sound came on since; null in a flight without sound.
func _alarm_player() -> AlarmPlayer:
	if view == null or view.muted or String(view.shot_path) != "":
		return null
	if alarm == null:
		alarm = AlarmPlayer.new()
		alarm.name = "RaidAlarm"
		alarm.stream = alarm_tone()
		alarm.volume_db = ALARM_DB
		add_child(alarm)
	return alarm


## The bursts' batch and its shader (hidden until a commuter is lost).
func _make_burst() -> void:
	if burst == null:
		burst = Burst.new()
		add_child(burst)
		burst.build(view)


## The raid's alarm, made in code: three rising whoops, battle stations (each climbs from 380 to 1,150 Hz in 0.42 s,
## fast and then slower, and cuts off; 0.12 s between), a bright tone (its second and third harmonics, and a little of
## a square's edge). 1.62 s, once. Chase's siren wails up and down; this only climbs.
static func alarm_tone(rate := 22050) -> AudioStreamWAV:
	if _alarm_wav != null:
		return _alarm_wav
	var whoop := 0.42
	var every := 0.54
	var n := int(3.0 * every * rate)
	var l := PackedFloat32Array()
	l.resize(n)
	var phase := 0.0
	for i in n:
		var k := fmod(float(i) / rate, every)
		if k >= whoop:
			continue         # (between whoops: silence)
		var u := k / whoop
		phase += TAU * lerpf(380.0, 1150.0, 1.0 - (1.0 - u) * (1.0 - u)) / rate
		var s := sin(phase)
		var edge := minf(k / 0.008, 1.0) * minf((whoop - k) / 0.03, 1.0)
		l[i] = edge * (0.6 * s + 0.24 * sin(2.0 * phase) + 0.14 * sin(3.0 * phase) + 0.1 * clampf(4.0 * s, -1.0, 1.0))
	_alarm_wav = Synth._wav(l, l.duplicate(), rate, 0.7)
	return _alarm_wav


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


## Is the pilot away from the raid: beyond R_KEEP of its town zone and of every raider still in it? (A raider kept
## to the zone is never the nearer, but the pack is the fight: a pilot after one is not away.)
func _far_from_it() -> bool:
	if _gap(city) <= Traffic.R_KEEP:
		return false
	var r2 := Traffic.R_KEEP * Traffic.R_KEEP
	for c in pack:
		if Vector2(c.x - sim.pod.x, c.y - sim.pod.y).length_squared() <= r2:
			return false
	return true


## A raider keeps to the raid's town zone: on the zone's road, TURN_SHORT m short of its end the way it goes, it turns
## round (its way the other, its lane mirrored so it stays where it is across the road, its next junction found
## again); on a one-way road (traffic.oneway: the pilot's, where nothing comes at the pilot) it is held there instead,
## stopped. A raider off the zone's road is left to traffic. (Run each frame after _hunt, which sets its speed.)
func _keep_in_zone(c) -> void:
	var zone := _zone(city)
	if c.road != int(zone.road):
		return
	var z: Vector2i = zone.z
	var R = sim.roads[c.road]
	var short: float = TURN_SHORT / float(R.len[clampi(int(c.f), 0, R.N - 1)])
	var end: float = float(z.y) - short if c.dir > 0 else float(z.x) + short
	if (c.f - end) * c.dir < 0.0:
		return
	if int(traffic.oneway.get(c.road, 0)) == c.dir:      # (turned round, it would come against the pilot's way)
		c.f = end
		c.v = 0.0
		c.vdes = 0.0
		traffic._place(c)
		return
	c.dir = -c.dir
	c.lane = traffic._lanes[c.road].size() - 1 - c.lane
	c.nsp_road = -1
	c.plan = null
	c.decided = -1
	c.vcap_road = -1
	traffic._place(c)


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
		c.vdes = Traffic.SF_V          # the town's limit (_hunt sets it toward its prey)
		c.a_up = 3.0 * Traffic.G
		c.a_lat = 11.0 * Traffic.G
		c.headway = RAIDER_HEADWAY
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
	_grace = 0.0
	print("RAID: arrived")


## The raider's prey: the nearest commuter (not hostile) ahead of it on its road and way, within PREY_REACH m, or null.
## One it has just passed within contact range still counts (it may yet be run down).
func prey_of(c) -> Variant:
	var R = sim.roads[c.road]
	var m: float = R.len[clampi(int(c.f), 0, R.N - 1)]
	var best = null
	var bd := INF
	for o in traffic.cars:
		if o.hostile or o.road != c.road or o.dir != c.dir:
			continue
		var along: float = (o.f - c.f) * c.dir * m
		if along < -CONTACT_ALONG or along > PREY_REACH or along >= bd:
			continue
		bd = along
		best = o
	return best


## One raider's driving: after its prey's lane, at its speed plus HUNT_DV, close behind (headway 0.05); with no prey,
## the town's limit. Contact runs the commuter down.
func _hunt(c, delta: float) -> void:
	var p = prey_of(c)
	if p == null:
		c.vdes = Traffic.SF_V
		c.headway = RAIDER_HEADWAY
		return
	c.lane = p.lane
	c.vdes = p.v + HUNT_DV
	c.headway = 0.05
	var R = sim.roads[c.road]
	var along: float = (p.f - c.f) * c.dir * float(R.len[clampi(int(c.f), 0, R.N - 1)])
	if absf(along) <= CONTACT_ALONG and absf(p.lat - c.lat) <= CONTACT_LAT:
		_run_down(p)


## Is a raider on the craft: the centre of one within CONTACT_CRAFT of the pod's or either engine's?
func _in_contact() -> bool:
	var r2 := CONTACT_CRAFT * CONTACT_CRAFT
	for c in pack:
		var zc: float = traffic.body_height(c)      # (the raider's height: its deck and half its body)
		for b in sim.bodies:
			var dz: float = b.z - zc
			if Vector2(b.x - c.x, b.y - c.y).length_squared() + dz * dz <= r2:      # (a raider on another deck is not on the craft)
				return true
	return false


## A commuter lost (commuter_lost): its burst where it was, standing on the deck there, for whatever craft.
func _burst_at(x: float, y: float) -> void:
	_make_burst()
	burst.add(Vector3(x, y, _deck_at(x, y)))


## The deck's height at (x, y), the sims' frame: on the raid city's road (where its commuters are run down), found from
## its town zone's points and then along the road; with no city, the craft's own road.
func _deck_at(x: float, y: float) -> float:
	var road: int = sim.pod.path
	var i: int = sim.pod.hint
	if city >= 0:
		var zone := _zone(city)
		road = zone.road
		var pts: PackedVector2Array = zone.pts
		var near := INF
		for k in pts.size():
			var d := pts[k].distance_squared_to(Vector2(x, y))
			if d < near:
				near = d
				i = mini(int(zone.z.x) + k * ZONE_STEP, int(zone.z.y))
	var R = sim.roads[road]
	var f := float(clampi(i, 0, R.N - 2))
	for k in 3:      # (along the road from there: it bends)
		var j := clampi(int(f), 0, R.N - 2)
		f = clampf(float(j) + ((x - R.px[j]) * R.tx[j] + (y - R.py[j]) * R.ty[j]) / maxf(1.0, R.len[j]), 0.0, R.N - 1.001)
	return sim.net_height(road, f)


## A commuter run down: out of traffic, lost, and commuter_lost for the flash.
func _run_down(p) -> void:
	traffic.knock_out(p)
	lost += 1
	print("RAID: commuter lost")
	commuter_lost.emit(p.x, p.y)      # (the flash is drawn from this, for every craft)


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
	_grace = 0.0
	if _count > 0:
		_lull_len = _rng.randf_range(lull.x, lull.y)


## The dash's line (traffic's race_text() gives it while the raid holds the floor). Called: the city, how far (a
## straight line to its centre, as the dash reads a distance) and the commuters lost so far. On: the raiders left and
## the time left. Otherwise "".
func text() -> String:
	match state:
		"called":
			var c: Dictionary = sim.cities[city]
			return "RAID  %s  %s  %d LOST" % [c.name, view._far(Vector2(float(c.cx) - sim.pod.x, float(c.cy) - sim.pod.y).length()), lost]
		"on":
			var left := int(maxf(time_limit - _t, 0.0))
			return "RAID  %d RAIDERS  %d:%02d" % [pack.size(), left / 60, left % 60]
	return ""
