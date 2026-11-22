## The avoidance field's eyes (Luke, 2026-11-22: "Add a collision avoidance force field"): once a
## frame, what is the craft about to hit on the road ahead, and what sideways push would miss it?
## The sims do the pushing (sim/craft_sim.gd `_avoid_apply`, inp.avoidPush) and the wall's cushion,
## which they can work out from what they already have to hand; they are not asked to look ahead
## (400 obstacle circles tested 480 times a second once doubled the sim's cost: this looks once a
## frame, at vehicles and pillars, and hands on two numbers).
##
## What it sees: the Network's traffic (view/network_traffic.gd `cars`) and the pillars under its
## decks (view/network_world.gd `obstacles_near`), on the craft's own level, that the craft's path
## passes within its own half-width of, inside LOOK_S seconds. Only with OBSTACLE COLLISIONS on:
## off, the craft passes through them and there is nothing to miss.
## What it asks for: the push that slides the path clear by the time it gets there (2 d / t^2), to
## the side the thing is not on, if the road has room that side and nothing else stands in it;
## the other side if not; nothing if neither (the sim's own forcefield, or a smash, is what is left).
##   var eyes := AvoidanceField.new()
##   eyes.look(sim, traffic, world) -> Vector2    the push, m/s^2 in the world (ZERO: nothing to miss)
##   eyes.threat, eyes.side, eyes.seen            what it is ("vehicle", "pillar", ""), which way it dodges
##                                                (+1 the pilot's left), how many things it weighed
extends RefCounted

const LOOK_S := 1.6           # s ahead it looks ...
const LOOK_MAX := 3200.0      # ... and m at the most (1.6 s at 4,500 mph)
const PILLAR_LOOK := 900.0    # m: pillars stand still, and are looked for no further off than this
const CRAFT_HALF := 5.0       # m: the craft's own half-width (its engines fly 3 m either side of its middle)
const MARGIN := 5.0           # m to spare past the craft and the thing
const MIN_CLOSING := 60.0     # m/s: slower than this nothing is a smash, and the pilot has it
const MIN_A := 20.0           # m/s^2: a miss that needs less than 2 g is left to the pilot
const EDGE_KEEP := 14.0       # m: a dodge that would end nearer the road's wall than this is not asked for
const MIN_SPEED := 50.0       # m/s: under this it does not look

var push := Vector2.ZERO
var threat := ""
var side := 0.0
var seen := 0
var _things: Array = []       # [along the path (m), miss (m, + the thing is left of the path), room it needs (m), what]


## A thing at (x, y) moving at (vx, vy), `radius` m across: weighed if the craft's path passes it.
func _weigh(px: float, py: float, vx: float, vy: float, x: float, y: float, ovx: float, ovy: float, radius: float, what: String) -> void:
	var rx := vx - ovx
	var ry := vy - ovy
	var closing := sqrt(rx * rx + ry * ry)
	if closing < MIN_CLOSING:
		return
	var ux := rx / closing
	var uy := ry / closing
	var dx := x - px
	var dy := y - py
	var along := dx * ux + dy * uy
	if along <= 0.0 or along > closing * LOOK_S:
		return
	var miss := ux * dy - uy * dx
	var need := CRAFT_HALF + radius + MARGIN
	if absf(miss) >= need + 40.0:      # (well clear either way: not even in the way of a dodge)
		return
	_things.append([along / closing, miss, need, what])


## The push that misses what is ahead, in the world's frame (m/s^2), ZERO for none.
func look(sim, traffic, world) -> Vector2:
	push = Vector2.ZERO
	threat = ""
	side = 0.0
	seen = 0
	if sim.kind != "network" or not sim.P.obstacleCollisions or sim.pod.off_road or sim.crash_t > 0.0:
		return push
	var px: float = sim.pod.x
	var py: float = sim.pod.y
	var vx: float = sim.pod.vx
	var vy: float = sim.pod.vy
	var speed := sqrt(vx * vx + vy * vy)
	if speed < MIN_SPEED:
		return push
	var fx := vx / speed
	var fy := vy / speed
	var pz: float = sim.pod.z
	_things.clear()
	var reach := minf(LOOK_MAX, speed * LOOK_S) + 400.0
	if traffic != null:
		for c in traffic.cars:
			var dx: float = c.x - px
			var dy: float = c.y - py
			if absf(dx) > reach or absf(dy) > reach:
				continue
			var train: bool = c.kind == traffic.TRANSPORT
			var cx: float = c.x
			var cy: float = c.y
			if train and dx * c.hx + dy * c.hy > 0.0:      # coming up behind a train: its last car is the one met
				cx -= c.hx * (traffic.TRAIN - 1) * traffic.TRAIN_GAP
				cy -= c.hy * (traffic.TRAIN - 1) * traffic.TRAIN_GAP
			var before := _things.size()
			_weigh(px, py, vx, vy, cx, cy, c.hx * c.v, c.hy * c.v, (4.2 if train else (3.2 if c.kind == traffic.SLOW else 2.6)) * traffic.SCALE, "vehicle")
			if _things.size() > before:                    # on another level (a deck over, a road under): not in the way
				var h: float = traffic._drawing.height(c.road, c.f)
				if pz + 1.0 < h or pz - 1.0 > h + (9.6 if train else 6.0):
					_things.pop_back()
	if world != null:
		var ahead := minf(PILLAR_LOOK, speed * LOOK_S) * 0.5
		for pillar in world.obstacles_near(px + fx * ahead, py + fy * ahead, ahead + 30.0):
			if pz + 1.0 < float(pillar.get("zMin", -INF)) or pz - 1.0 > float(pillar.get("zMax", INF)):
				continue
			var half: float = pillar.get("halfSize", 0.0)
			_weigh(px, py, vx, vy, pillar.x, pillar.y, 0.0, 0.0, half * 1.414214 if half > 0.0 else float(pillar.get("r", 2.0)), "pillar")
	seen = _things.size()
	if seen == 0:
		return push
	# the most pressing of those the path would hit
	var worst := -1
	var worst_a := 0.0
	for k in seen:
		var t: Array = _things[k]
		if absf(t[1]) >= t[2]:
			continue
		var a: float = 2.0 * (float(t[2]) - absf(t[1])) / maxf(float(t[0]) * float(t[0]), 1e-4)
		if a > worst_a:
			worst_a = a
			worst = k
	if worst < 0 or worst_a < MIN_A:
		return push
	# which way: away from it, if the road has the room and nothing else stands there; else the other way
	var R = sim.roads[sim.pod.path]
	var i: int = clampi(int(sim.pod.hint), 0, int(R.N) - 1)
	var lat: float = (px - R.px[i]) * R.nx[i] + (py - R.py[i]) * R.ny[i]              # m left of the road's middle, as its samples run
	var way := signf(fx * R.tx[i] + fy * R.ty[i])                                        # (flown the other way, the pilot's left is the road's right)
	var room: float = 0.5 * float(R.w[i]) - EDGE_KEEP
	var w: Array = _things[worst]
	var first := -1.0 if float(w[1]) > 0.0 else 1.0                                      # +1: dodge to the path's left
	for dir in [first, -first]:
		var shift: float = float(w[2]) - absf(w[1]) if dir == first else float(w[2]) + absf(w[1])
		if absf(lat + dir * way * shift) > room:
			continue
		var blocked := false
		for k in seen:
			if k == worst:
				continue
			var o: Array = _things[k]
			if absf(float(o[1]) - dir * shift) < float(o[2]) and absf(float(o[0]) - float(w[0])) < 0.6:   # it would be slid into this one, met at about the same time
				blocked = true
				break
		if blocked:
			continue
		var a: float = 2.0 * shift / maxf(float(w[0]) * float(w[0]), 1e-4)
		push = Vector2(-fy, fx) * dir * a
		threat = String(w[3])
		side = dir
		return push
	return push
