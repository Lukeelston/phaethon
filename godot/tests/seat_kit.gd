## The VR seat flown on its own frames at speed, for the weapons' tests (Raids stage 2, Ruling AA: a weapon's reach and
## timing are checked with the world still and again on the seat's own frames, the craft at about 1,500 mph and its
## targets keeping its pace). Shared by tests/test_pulse.gd and tests/test_orbs.gd.
##   var seat := SeatKit.new()
##   seat.on_a_straight(v)                     the craft put at the start of a straight, level stretch of its road
##   seat.hold_speed(v)                        all three bodies at `speed` along the road under the pod, level
##   seat.road_way(v)                          the road's way at the pod (a unit vector in the sims' plane)
##   seat.seat_frame(v, g, held, paced)        one of the cockpit's own frames: the pulses sent to the hands in it
##   seat.pace(v, paced)                       paced raiders stood where they must be after the frame to come
##   seat.ready_on_seat(v, g, over, ready)     the weapon's last use over, made ready by hand, the craft on a straight again
extends RefCounted

const Sim := preload("res://sim/craft_sim.gd")
const DT := 1.0 / 120.0
const MPH := 0.44704
const SPEED := 1500.0 * MPH     # m/s
const STRAIGHT := 1600.0        # m of road ahead that must run straight and level
var way := 1                    # the craft's way along its road (on_a_straight: 1)


## Put the craft at the start of a straight, level stretch of its road (STRAIGHT m of it ahead).
func on_a_straight(v) -> void:
	var sim = v.sim
	var span := int(ceil(STRAIGHT / float(Sim.NET_STEP)))
	var roads := [int(sim.pod.path)]
	for r in sim.roads.size():
		if r != roads[0]:
			roads.append(r)
	for r: int in roads:
		var R = sim.roads[r]
		if R.deck or R.shaft or R.banked or R.role != "" or R.N < span + 400:
			continue
		var from := clampi(int(sim.pod.hint), 300, R.N - span - 100) if r == roads[0] else 300
		for i in range(from, R.N - span - 100, 6):
			var th := atan2(R.ty[i], R.tx[i])
			var h0: float = sim.road_h(r, float(i))
			var ok := true
			for k in range(i, i + span + 1, 2):
				if absf(angle_difference(th, atan2(R.ty[k], R.tx[k]))) > deg_to_rad(0.15) or absf(sim.road_h(r, float(k)) - h0) > 1.0 \
						or sim.in_pressure(r, k):
					ok = false
					break
			if ok:
				sim.respawn_on(r, i, 1)
				way = 1
				print("  on road %s at sample %d: %.1f km straight and level ahead, %.0f m wide" % [R.name, i, STRAIGHT / 1000.0, R.w[i]])
				return
	print("  (no straight found: flying where it starts)")


## All three bodies at SPEED along the road under the pod, level.
func hold_speed(v) -> void:
	var sim = v.sim
	var R = sim.roads[sim.pod.path]
	var i := clampi(int(sim.pod.hint), 0, R.N - 1)
	for b in [sim.eL, sim.eR, sim.pod]:
		b.vx = R.tx[i] * way * SPEED
		b.vy = R.ty[i] * way * SPEED
		b.vz = 0.0


## The road's way at the pod (a unit vector in the sims' plane).
func road_way(v) -> Vector2:
	var sim = v.sim
	var R = sim.roads[sim.pod.path]
	var i := clampi(int(sim.pod.hint), 0, R.N - 1)
	return Vector2(R.tx[i], R.ty[i]) * way


## One of the cockpit's own frames, the craft held at speed, the trigger held or not, the paced raiders (`paced`: see
## pace) put where they must stand for it: the pulses sent in it.
func seat_frame(v, g, held := false, paced := []) -> Array:
	v.gun_pulses.clear()
	g.hold_fire = held
	hold_speed(v)
	pace(v, paced)
	v._process(DT)
	g.hold_fire = false
	return v.gun_pulses.duplicate()


## Each paced raider ([car, m along the road from the craft, lanes over from the craft's, ...]) stood where it must be
## after the frame to come: that far along the road from where the pod will be (its speed held: SPEED x DT on), in the
## middle of the lane nearest the pod's place across the road (the E2 is 400 m wide) or the given number of lanes over,
## stopped (traffic's own drive then moves it a hair at most). So it keeps the craft's own pace.
func pace(v, paced: Array) -> void:
	if paced.is_empty():
		return
	var sim = v.sim
	var T = v.traffic_net
	var R = sim.roads[sim.pod.path]
	var i := clampi(int(sim.pod.hint), 0, R.N - 2)
	var dx: float = sim.pod.x - R.px[i]
	var dy: float = sim.pod.y - R.py[i]
	var f_pod: float = i + (dx * R.tx[i] + dy * R.ty[i]) / float(R.len[i])
	var lat_pod: float = -dx * R.ty[i] + dy * R.tx[i]
	for row: Array in paced:
		var c = row[0]
		var lanes: int = (T._lanes[c.road] as Array).size()
		var near := 0
		for k in lanes:
			if absf(T._lane_lat(c, k) - lat_pod) < absf(T._lane_lat(c, near) - lat_pod):
				near = k
		c.f = f_pod + way * (float(row[1]) + SPEED * DT) / float(R.len[i])
		c.lane = clampi(near + int(row[2]), 0, lanes - 1)
		c.lat = T._lane_lat(c, c.lane)
		c.v = 0.0
		c.place(R)


## The weapon's last use over (`over` answers true, or a second of the seat's frames has gone), made ready by hand
## (`ready`: a recharge or a rest that would fly the craft off its straight, ended now), and the craft put on a straight
## again, ten of the seat's frames flown.
func ready_on_seat(v, g, over: Callable, ready: Callable) -> void:
	for i in int(1.0 / DT):
		if over.call():
			break
		seat_frame(v, g)
	ready.call()
	on_a_straight(v)
	for i in 10:
		seat_frame(v, g)
