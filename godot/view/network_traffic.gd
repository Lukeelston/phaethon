## The Network's traffic and racers (docs/superpowers/specs/2026-10-19-network-design.md, phase 2):
## regular traffic at speed, driven here, outside the sims; the sims see the vehicles near the craft
## as moving forcefield obstacles (sim.obstacles: a shove, a 'bump'; a catastrophic closing speed is a
## 'smash').
##   one way    traffic always goes the way the pilot is going (Luke: "oncoming traffic cuts the
##              available road in half"): on the pilot's road every vehicle goes the pilot's way, across
##              the whole width: eight lanes on a highway (45 m apart), four on a ramp, a bypass or a
##              turnaround. Nothing merges onto it against you; when you come back the other way (a
##              turnaround) the far ones turn with you and the near ones are cleared. Lanes counted from
##              the right: slow pods and trains keep right, demons left
##   kinds      cars (2,000-3,000 mph, 30% faster on express decks), slow pods (1,000-1,500),
##              speed demons (4,000-4,800, 10% faster on express decks, weaving), transport pods
##              (a tractor hauling seven freight cars, ~1,600 mph, the outside lane). Higher roads have
##              more hot rods and racers; lower roads have more shuttles and freight.
##   driving    each keeps a headway to the one ahead in its lane (the craft counts) or changes lane
##              when it can; slows for curves (its own grip) and the cities' STARFIGHTER zones; at a
##              junction it may take the other road (where the two coincide, the way a road can be
##              entered); toward a highway's end it takes the turnaround. Ordinary traffic makes
##              one safe, gradual move for a persistent faster follower, whoever is driving it.
##   density    kept round the craft: thicker near the cities and the interchanges; spawned out in
##              the haze (14-28 km), dropped past 30 km
##   racers     now and then a racer drops in behind you on a highway and shadows you; light your
##              ramjet and it's on: first a mile ahead wins (distance driven since the start); ignore
##              it and it peels off. Names and styles; the tally in network.json (the view saves it)
## Rendering: a MultiMesh per kind (the craft's floating origin), near and far; a far body is never
## drawn under a couple of pixels wide (art/traffic/fleet.gdshader). And a pair of lamps per vehicle
## (view/traffic_lamps.gdshader): its tail lamps, or its head lamps when its nose is toward the eye,
## the size they are, so a vehicle a kilometre off is a pair and the far end of a busy road a string
## of faint points, not one red glow.
##   var t := NetworkTraffic.new(); add_child(t); t.build(sim, view, world)
##   t.update(delta)     every frame, after the sim's steps (sets sim.obstacles for the next ones)
class_name NetworkTraffic
extends Node3D

const Simulation := preload("res://sim/craft_sim.gd")
const RoadWorld := preload("res://view/network_world.gd")
const Batch := preload("res://view/traffic_batch.gd")
const Outlook := preload("res://view/outlook.gd")
const MPH := 2.236936
const G := 9.81
const LANES_HWY := [-157.5, -112.5, -67.5, -22.5, 22.5, 67.5, 112.5, 157.5]   # m left of the centreline
const LANES_RAMP := [-75.0, -25.0, 25.0, 75.0]
const FLIP_FAR := 5000.0         # m: an oncoming vehicle on the pilot's road this far off turns round (nearer: cleared)
const R_KEEP := 19000.0          # vehicles kept within this of the craft
const R_SPAWN := Vector2(11000.0, 18000.0)   # spawned this far out (in the haze)
const TARGET := 220              # the most vehicles round the craft (near a city); mid-country fewer (_target)
const SCALE := 2.0               # the vehicles' size: big enough to read at these speeds (a car 24 m, a freight car 34 m)
const R_FIELD := 2500.0          # vehicles within this are the sims' obstacles, at the very most (feed_reach)
# The feed is made again every frame, so the sim need only be given what the craft can reach before the next one.
# (It was every vehicle within R_FIELD and every pillar within 1,000 m: at the Eridanus pad some 400 circles, each
# tested against the craft's three bodies on each of the sim's 480 steps a second. With OBSTACLE COLLISIONS on that
# doubled the sim's cost, 150 us a step to 320: Luke's sixteenth and seventeenth flights, 82 fps for 94.)
const FEED_REACH := 120.0        # m: the craft's own length (its engines fly 22 m ahead of the pod), a vehicle's, and room
const FEED_AHEAD_S := 0.12       # s of flying: the feed is a frame old at most, and the view clamps a frame at 0.05 s
const FEED_CLOSING := 200.0      # m/s: a vehicle's own speed, coming the other way
const TRAIN := 8                 # cars in a transport pod's train
const TRAIN_GAP := 38.0          # m between their centres
const SF_V := 1150.0 / MPH       # through a city's STARFIGHTER zone
const BRAKE := 4.0 * 9.81        # m/s^2: how hard they plan to brake for what's ahead (6 g at most when they must)
const PLAN_AHEAD := 40000.0      # m: a vehicle decides on a junction this far before it (and slows for the road beyond)
const CAP_EVERY := 3            # frames between a car's readings of its road ahead (staggered: a third of them a frame)
const NEAR := 6000.0             # m (either way): nearer vehicles are driven every frame; farther, every other
                                 # (half of them a frame, for both frames' time) and drawn where they'll be.
                                 # The sims' obstacles (R_FIELD) are all near. Round a city ~70% are far
const BRAKE_AT := [250.0, 500.0, 1000.0, 2000.0, 3000.0, 4500.0, 6000.0, 8000.0, 10000.0, 12000.0, 16000.0, 22000.0, 30000.0, 40000.0, 50000.0]   # straight highways let demons reach speeds that need >30 km to brake
const BRAKE_BY := [0.0, 250.0, 500.0, 1000.0, 2000.0, 3000.0, 4500.0, 6000.0, 8000.0, 10000.0, 12000.0, 16000.0, 22000.0, 30000.0, 40000.0]   # ... and where it's slowed for each: the reading
	# before it (a limit read at 500 m may start at 251: braked for at 500 they crossed a zone's edge 70 mph over)
const AFTER := [0.0, 1000.0, 2000.0, 3500.0, 5000.0, 7000.0, 9000.0, 11000.0, 13000.0, 15000.0, 20000.0, 28000.0, 38000.0, 50000.0]   # m along a road it'll take: where its limits are read
enum { CAR, SLOW, DEMON, TRANSPORT, RACER }
# A vehicle's lamps, by kind: [half the pair's spacing, a lamp's radius, how far from its middle its nose's and
# its tail's lamps are], in metres as drawn (view/traffic_lamps.gdshader). Wide and big on a freighter, close and
# small on a racer: from a distance the pair's width is the vehicle's size. The reach is each model's own longer
# end and 0.6 m: one figure of 13 m for all stood a shuttle's, a racer's and a freight car's lamp inside its
# body (they are 13.9, 14.0 and 17.5 m from middle to end), where the body hid it from straight behind.
const LAMPS := [Vector3(3.0, 0.42, 12.5), Vector3(3.8, 0.5, 14.5), Vector3(1.7, 0.34, 13.5), Vector3(4.2, 0.6, 18.1), Vector3(1.7, 0.34, 14.6)]
const TRACTOR_NOSE := 17.6       # ... and a transport's head lamps, on its tractor
const LAMP_MIN_PX := 1.5         # a lamp's least radius on the picture, pixels of the eye's own buffer: smaller, and it flickers as it crosses them
const LAMP_ENERGY := Vector2(6.0, 4.5)   # the lamps' strength by day and at night: by day they have a lit road to show against
# Tail lamps by kind: a car's and a demon's red, a racer's its own magenta, and the slow ones' amber (the slow pods
# and the transports, which keep right at half a car's speed): past two kilometres a vehicle is a point or two of
# light, and its colour is what says whether it is something to overtake wide. Head lamps are white on all of them.
const TAIL := [Color(1.0, 0.15, 0.08), Color(1.0, 0.5, 0.1), Color(1.0, 0.15, 0.08), Color(1.0, 0.5, 0.1), Color(1.0, 0.3, 0.9)]
const HEAD := Color(1.0, 0.95, 0.85)
const BODY_MIN_ANG := 0.0011     # a car's least half-width on the picture: it and every other body grow together past 3.6 km
const BODY_HALF_WIDTH := 4.3     # ... a car's, m as drawn
const TRACTOR := 5 # Render slot for the lead unit of a transport.
const FLEET := [
	preload("res://art/traffic/commuter.glb"), preload("res://art/traffic/shuttle.glb"),
	preload("res://art/traffic/demon.glb"), preload("res://art/traffic/cargo.glb"),
	preload("res://art/traffic/racer.glb"), preload("res://art/traffic/tractor.glb"),
]
const NUMBER_BOARDS := {"VEGA": 0.0, "KESTREL": 1.0/3.0, "MARROW": 2.0/3.0, "TALLOW": 1.0}
# [top mph, lateral grip g, headway s, colour]: a racer's style
const RACERS := {
	"VEGA": [6300.0, 7.0, 0.5, Color(1.0, 0.25, 0.65)],      # a straight-line monster, soft in the bends
	"KESTREL": [5900.0, 10.0, 0.25, Color(0.25, 1.0, 0.55)],  # fearless in traffic
	"MARROW": [6050.0, 9.0, 0.4, Color(1.0, 0.55, 0.1)],      # all-round
	"TALLOW": [5800.0, 12.0, 0.45, Color(0.4, 0.75, 1.0)],    # the corner king
}
const RACER_FIRST := 40.0        # s on a highway before the first racer
const RACER_EVERY := 90.0        # s between racers
const RACER_PATIENCE := 45.0     # s it shadows you before it peels off
const RACE_WIN := 1609.344       # a mile


class HeightSpan:
	var first := -INF
	var end := INF
	var height := 0.0
	var flat := true
	var inv_length := 0.0
	var b := 0.0
	var c := 0.0
	var d := 0.0

	func at(f: float) -> float:
		if flat:
			return height
		var u := (f - first) * inv_length
		return height + u * (b + u * (c + u * d))


class FleetFrame:
	var roads: Array[Simulation.TrackPath]
	var shaft: RoadWorld.ShaftScript
	var grade_spans: Array[Array]
	var writers: Array[Batch.Writer] = []
	var tractor: Batch.Writer
	var ox := 0.0
	var oy := 0.0
	var eye := Vector3.ZERO
	var eye_x := 0.0      # ... and where that is on the map (sim metres): which end of a vehicle it sees
	var eye_y := 0.0
	var pod_v := Vector2.ZERO
	var grade := true

	func height(road: int, f: float) -> float:
		var spans := grade_spans[road]
		if spans.is_empty():
			return 0.0
		var span: HeightSpan = spans[clampi(int(f), 0, spans.size() - 1)]
		if f < span.first or f > span.end:
			return 0.0
		return span.height if span.flat else span.at(f)


class Car:
	var id := 0
	var bucket := -1
	var bucket_order := -1
	var kind := 0
	var road := 0
	var f := 0.0          # fractional sample along its road
	var dir := 1          # 1 up the samples, -1 down
	var lane := 0
	var lat := 0.0        # m left of the centreline
	var left_width := 7.0
	var right_width := 7.0
	var front := 24.0
	var rear := 24.0
	var v := 0.0          # m/s
	var vdes := 0.0
	var cruise := 0.0     # the vehicle's own lower-deck cruise; express roads scale cars/hot rods
	var cruise_goal := 0.0 # road-dependent target, approached gradually across a level change
	var a_up := 1.5 * 9.81
	var a_lat := 9.0 * 9.81
	var headway := 1.2
	var turn_p := 0.3
	var x := 0.0
	var y := 0.0
	var hx := 1.0         # the way it's going (unit)
	var hy := 0.0
	var lc_cool := 0.0
	var flow_clock := 0.0  # staggered rearward glance, not a scan of every car every frame
	var flow_source := -1 # the same approaching road user must persist before a move
	var flow_notice := 0.0
	var col := Color.WHITE
	var name := ""
	var plan = null       # the switch it's decided on ahead (it slows for that road beforehand), or null
	var decided := -1     # the sample of the last switch it decided about (taken or not)
	var nsp = null        # the next switch ahead on its road its way (null: none), found once, not every frame
	var nsp_road := -1    # ... found for this road and way (-1: find it again)
	var nsp_dir := 0
	var vcap := 0.0       # the most it may go for what's ahead (its road's limits and its exit's), read every CAP_EVERY frames
	var vcap_road := -1   # ... read on this road (-1: read it now)
	var brake_road := -1
	var brake_dir := 0
	var brake_grip := 0.0
	var brake_lo := INF
	var brake_hi := -INF
	var brake_here := INF
	var brake_ahead_sq := INF
	var owed := 0.0       # s since it was last driven (a far one is driven every other frame)
	var chase := ""       # chase mode's craft (view/network_chase.gd): "fugitive" picks its own exits, "pursuer" follows the pilot's
	var craft := false    # ... drawn there as a pod and its engines, not here as one of the fleet


	var draw_hx := INF
	var draw_hy := INF
	var draw_yaw := Basis.IDENTITY
	var draw_basis := Basis.IDENTITY
	var flat_road := -1
	var flat_from := INF
	var flat_to := -INF
	var flat_height := 0.0
	var flat_spans: Array
	var path_data: Simulation.TrackPath
	var path_x := PackedFloat64Array()
	var path_y := PackedFloat64Array()
	var path_tx := PackedFloat64Array()
	var path_ty := PackedFloat64Array()
	var path_lengths := PackedFloat64Array()
	var place_pending := false

	var lamp_position := Vector3.ZERO
	var lamp_color := Color.WHITE
	var lamp_basis := Basis.IDENTITY   # x: its own left-to-right, half its lamps' spacing long; y: a lamp's radius; z: the body's reach (view/traffic_lamps.gdshader)
	var lamp_nose := 13.0              # m from its middle forward to its head lamps
	var lamp_tail := 13.0              # ... and back to its tail lamps (a transport's: behind the last of its train)
	var lamp_tail_color := Color.RED   # its kind's (TAIL), kept here so a frame reads it and looks nothing up

	func draw(frame: FleetFrame, batch: Batch.Writer) -> void:
		if place_pending:
			place(frame.roads[road])
			place_pending = false
		var cx: float = x + hx * v * owed
		var cy: float = y + hy * v * owed
		if hx != draw_hx or hy != draw_hy:
			draw_hx = hx
			draw_hy = hy
			draw_yaw = Basis(Vector3.UP, atan2(-hx, hy))
			draw_basis = draw_yaw.scaled(Vector3.ONE * SCALE)
			var lamps: Vector3 = LAMPS[kind]
			lamp_basis = draw_yaw * Basis.from_scale(lamps)
			lamp_nose = TRACTOR_NOSE if kind == TRANSPORT else lamps.z
			lamp_tail = lamps.z + ((TRAIN - 1) * TRAIN_GAP if kind == TRANSPORT else 0.0)
			lamp_tail_color = TAIL[kind]
		var banked: Simulation.TrackPath = frame.roads[road]
		if banked.banked:
			var at := clampi(int(f), 0, banked.N - 2)
			if banked.bank[at] != 0.0 or banked.bank[at + 1] != 0.0:
				draw_banked(frame, batch, cx, cy, banked)
				return
		var spans := frame.grade_spans[road]
		if flat_road == road and is_same(flat_spans, spans) and f >= flat_from and f < flat_to:
			draw_flat(frame, batch, cx, cy, flat_height)
			return
		var last: float = frame.roads[road].N - 1.0
		var h := 1.0
		var graded := false
		if not spans.is_empty():
			var span: HeightSpan = spans[clampi(int(f), 0, int(last))]
			if f >= span.first and f <= span.end:
				h += span.height if span.flat else span.at(f)
			var reach := (TRAIN if kind == TRANSPORT else 1) * TRAIN_GAP / 24.0
			graded = frame.grade and (not span.flat or f - reach < span.first or f + reach > span.end)
		var shaft_on: bool = frame.roads[road].shaft and frame.shaft.on(road, f)
		if not frame.roads[road].shaft:
			var span: HeightSpan = null if spans.is_empty() else spans[clampi(int(f), 0, int(last))]
			if span == null or span.flat:
				flat_road = road
				flat_spans = spans
				flat_height = h
				var reach := TRAIN * TRAIN_GAP / 24.0
				flat_from = -INF if span == null else span.first + reach
				flat_to = INF if span == null else span.end - reach
		# A road with a height profile (a hill, a ramp, a deck's approach): every body sits at its
		# own height and noses up or down with the grade. They used to stay level at the lead's
		# height, so a transport's train floated off a climb or sank into it (Luke: "busses look
		# hilarious half sticking out going up hills"). A level road costs nothing more.
		graded = graded and not shaft_on
		var step: float = dir * TRAIN_GAP / 24.0   # samples from one body's centre to the next
		var h_ahead := h
		var h_here := h
		if graded:
			h_ahead = frame.height(road, clampf(f + step, 0.0, last)) + 1.0
		var b := draw_basis
		var cnt := TRAIN if kind == TRANSPORT else 1
		var board: float = NUMBER_BOARDS.get(name, 0.0) if kind == RACER else 0.0
		for k in (0 if craft else cnt):
			var back := k * TRAIN_GAP
			var p := Vector3(cx - hx * back - frame.ox, h, -(cy - hy * back - frame.oy))
			var body_basis := b
			if graded:
				# the grade under this body: from a body length ahead of it to one behind
				var h_behind := frame.height(road, clampf(f - step * (k + 1), 0.0, last)) + 1.0
				p.y = h_here
				body_basis = (draw_yaw * Basis(Vector3.RIGHT, atan((h_ahead - h_behind) / (2.0 * TRAIN_GAP)))).scaled(Vector3.ONE * SCALE)
				h_ahead = h_here
				h_here = h_behind
			if shaft_on:
				var station := f - dir * back / 24.0
				p = frame.shaft.point(road, station, lat, 1.0, frame.ox, frame.oy)
				body_basis = frame.shaft.frame(road, station) * Basis(Vector3.UP, PI if dir < 0 else 0.0)
				body_basis = body_basis.scaled(Vector3.ONE * SCALE)
			var unit: Batch.Writer = frame.tractor if kind == TRANSPORT and k == 0 else batch
			unit.put(Transform3D(body_basis, p), frame.eye, col, board)
		# the light you see: its tail if it's going your way, its head lamps if it's coming at you
		var coming: bool = hx * (frame.eye_x - cx) + hy * (frame.eye_y - cy) > 0.0      # its nose is toward the eye
		var off := -lamp_nose if coming else lamp_tail
		var lp := Vector3(cx - hx * off - frame.ox, h + 1.2 * SCALE, -(cy - hy * off - frame.oy))
		if graded:   # the lamp rides at its own end's height
			lp.y = frame.height(road, clampf(f - dir * off / 24.0, 0.0, last)) + 1.0 + 1.2 * SCALE
		if shaft_on:
			lp = frame.shaft.point(road, f - dir * off / 24.0, lat, 1.0 + 1.2 * SCALE, frame.ox, frame.oy)

		var lc := HEAD if coming else lamp_tail_color
		if chase == "pursuer":      # a patrol's lights, seen from any distance: red, blue, red, blue
			lc = Color(1.0, 0.1, 0.08) if int(Time.get_ticks_msec() / 200) % 2 == 0 else Color(0.15, 0.35, 1.0)
		lamp_position = lp
		lamp_color = lc
		if shaft_on:      # round a shaft's bulb the vehicle's own left-to-right is the bulb's, not the map's
			lamp_basis = (frame.shaft.frame(road, f) * Basis(Vector3.UP, PI if dir < 0 else 0.0)) * Basis.from_scale(LAMPS[kind])
			draw_hx = INF      # (and its heading's own frame is found again when it comes off the bulb)

	## On a banked bend (CraftSim.NET_BANKS) every body stands on the deck as it leans there: at the deck's
	## height at its own place along the road, lifted by the bank where it is across it, rolled with the
	## bank and nosed along the grade. Its lamp rides at its own end's height.
	func draw_banked(frame: FleetFrame, batch: Batch.Writer, cx: float, cy: float, R: Simulation.TrackPath) -> void:
		var last: float = R.N - 1.0
		var step: float = dir * TRAIN_GAP / 24.0   # samples from one body's centre to the next
		var board: float = NUMBER_BOARDS.get(name, 0.0) if kind == RACER else 0.0
		for k in (0 if craft else (TRAIN if kind == TRANSPORT else 1)):
			var back := k * TRAIN_GAP
			var fk := clampf(f - step * k, 0.0, last)
			var ik := clampi(int(fk), 0, R.N - 2)
			var h: float = frame.height(road, fk) + 1.0 + Simulation.net_bank_lift(R, ik, fk - ik, lat)
			var pitch := 0.0
			if frame.grade:
				pitch = atan((frame.height(road, clampf(fk + step, 0.0, last)) - frame.height(road, clampf(fk - step, 0.0, last))) / (2.0 * TRAIN_GAP))
			var body_basis := (draw_yaw * Basis(Vector3.RIGHT, pitch) * Basis(Vector3.BACK, Simulation.net_bank(R, ik, fk - ik) * dir)).scaled(Vector3.ONE * SCALE)
			var unit: Batch.Writer = frame.tractor if kind == TRANSPORT and k == 0 else batch
			unit.put(Transform3D(body_basis, Vector3(cx - hx * back - frame.ox, h, -(cy - hy * back - frame.oy))), frame.eye, col, board)
		var coming: bool = hx * (frame.eye_x - cx) + hy * (frame.eye_y - cy) > 0.0
		var off := -lamp_nose if coming else lamp_tail
		var fl := clampf(f - dir * off / 24.0, 0.0, last)
		var il := clampi(int(fl), 0, R.N - 2)
		lamp_position = Vector3(cx - hx * off - frame.ox, frame.height(road, fl) + 1.0 + 1.2 * SCALE + Simulation.net_bank_lift(R, il, fl - il, lat), -(cy - hy * off - frame.oy))
		lamp_color = HEAD if coming else lamp_tail_color
		if chase == "pursuer":
			lamp_color = Color(1.0, 0.1, 0.08) if int(Time.get_ticks_msec() / 200) % 2 == 0 else Color(0.15, 0.35, 1.0)

	## In a constant Hermite span, every axle and the lights share one deck height.
	## The cached interval allows the entire train plus the grade lookahead.
	func draw_flat(frame: FleetFrame, batch: Batch.Writer, cx: float, cy: float, h: float) -> void:
		var board: float = NUMBER_BOARDS.get(name, 0.0) if kind == RACER else 0.0
		var count := TRAIN if kind == TRANSPORT else 1
		if not craft:
			var lead := frame.tractor if kind == TRANSPORT else batch
			lead.put(Transform3D(draw_basis, Vector3(cx - frame.ox, h, -(cy - frame.oy))), frame.eye, col, board)
			for i in range(1, count):
				var back := i * TRAIN_GAP
				var at := Vector3(cx - hx * back - frame.ox, h, -(cy - hy * back - frame.oy))
				batch.put(Transform3D(draw_basis, at), frame.eye, col, board)
		var coming := hx * (frame.eye_x - cx) + hy * (frame.eye_y - cy) > 0.0
		var off := -lamp_nose if coming else lamp_tail
		lamp_position = Vector3(cx - hx * off - frame.ox, h + 1.2 * SCALE, -(cy - hy * off - frame.oy))
		lamp_color = HEAD if coming else lamp_tail_color
		if chase == "pursuer":
			lamp_color = Color(1.0, 0.1, 0.08) if int(Time.get_ticks_msec() / 200) % 2 == 0 else Color(0.15, 0.35, 1.0)

	func place(R: Simulation.TrackPath) -> void:
		if path_data != R:
			path_data = R
			path_x = R.px
			path_y = R.py
			path_tx = R.tx
			path_ty = R.ty
			path_lengths = R.len
		var i := clampi(int(f), 0, R.N - 2)
		var t := clampf(f - i, 0.0, 1.0)
		var tx0 := path_tx[i]
		var ty0 := path_ty[i]
		var ds := path_lengths[i]
		var tx: float = lerpf(tx0, path_tx[i + 1], t)
		var ty: float = lerpf(ty0, path_ty[i + 1], t)
		var l := sqrt(tx * tx + ty * ty)
		tx /= l
		ty /= l
		x = path_x[i] + tx0 * ds * t - ty * lat
		y = path_y[i] + ty0 * ds * t + tx * lat
		hx = tx * dir
		hy = ty * dir


	func drive(traffic: NetworkTraffic, arr: Array, idx: int, delta: float, defer_place: bool) -> void:
		var original_road := road
		var R := traffic.sim.roads[road]
		var lanes: Array = traffic._lanes[road]
		var nl := lanes.size()
		lc_cool = maxf(0.0, lc_cool - delta)
		flow_clock = maxf(0.0, flow_clock - delta)
		if nsp_road != road or nsp_dir != dir:
			traffic._next_switch(self)
		# the speed it wants: its own, the curve's, and slow enough to brake (at BRAKE) for every limit up
		# to 50 km ahead (demons can reach full speed on the straight highways), and for the road
		# beyond the exit it's taking. Read every CAP_EVERY frames, as if from where it'll be by the next.
		var read_cap := vcap_road != road or (traffic._tick + id) % CAP_EVERY == 0
		if kind != RACER or chase == "fugitive":      # (a runner picks its exits as traffic does)
			if nsp != null and int(nsp[0]) != decided:
				traffic._decide(self)
				read_cap = read_cap or vcap_road != road
			if cruise > 0.0:
				if read_cap:
					if kind == CAR or kind == DEMON:
						cruise_goal = traffic._cruise_for(self, traffic._traffic_tier(road, f))
					else:
						cruise_goal = cruise
				if vdes != cruise_goal:
					vdes = move_toward(vdes, cruise_goal, BRAKE * delta)
		if read_cap:
			vcap = traffic._speed_cap(self, CAP_EVERY * v * delta)
			vcap_road = road
		var vt := minf(vcap, vdes)
		if kind == RACER and traffic.race_state == "tail":
			vt = traffic._tail_speed(self)
		# the one ahead in its lane
		var lead: Car = null
		var gap := INF
		var headway_gap := v * headway
		# A busy adjacent lane must not hide the actual leader beyond nine entries.
		for k in range(idx + 1, arr.size()):
			var o: Car = arr[k]
			if o.road != road or o.dir != dir:
				continue
			var separation := (o.f - f) * dir
			if separation <= 0.0:
				continue
			# Ahead entries have not been driven yet. Once outside the headway,
			# every later entry on this road and direction is outside it too.
			var clearance := separation * 24.0 - 20.0 * SCALE
			if clearance >= headway_gap:
				break
			if o.id == 0 and chase == "pursuer":
				continue      # (a patrol keeps no headway from the craft it is after: it comes onto its tail)
			if absf(o.lat - lat) < 22.0:
				lead = o
				gap = clearance
				break
		if lead:
			flow_source = -1
			flow_notice = 0.0
			var moved := false
			if lc_cool <= 0.0 and kind != TRANSPORT:
				for dl in ([-1, 1] if traffic._rng.randf() < 0.5 else [1, -1]):
					var ln: int = lane + dl
					if ln < 0 or ln >= nl:
						continue
					var lat_n := traffic._lane_lat(self, ln)
					if traffic._clear(arr, idx, self, lat_n):
						lane = ln
						lc_cool = 1.0 if kind == DEMON or kind == RACER else 3.0
						moved = true
						break
			if not moved:
				# A blocked gap does not improve sixty times a second. Keep braking at full
				# rate, but stagger another gap search; full safety scans stay inexpensive.
				if lc_cool <= 0.0:
					lc_cool = (0.22 if kind == DEMON or kind == RACER else 0.40) + float(id % 5) * 0.03
				vt = minf(vt, lead.v + (gap - v * headway * 0.5) / maxf(headway, 0.3))
		elif (flow_clock <= 0.0 or flow_source >= 0) and traffic._courtesy(self, arr, idx):
			pass
		elif kind == DEMON and lc_cool <= 0.0 and traffic._rng.randf() < 0.004:
			var ln2 := clampi(lane + (1 if traffic._rng.randf() < 0.5 else -1), 0, nl - 1)   # weaving for the joy of it
			if traffic._clear(arr, idx, self, traffic._lane_lat(self, ln2)):
				lane = ln2
				lc_cool = 1.0
		# speed and place
		var dv := vt - v
		v += clampf(dv, -6.0 * G * delta, a_up * delta)
		v = maxf(v, 0.0)
		var lane_index := mini(lane, nl - 1)
		var lt: float = lanes[lane_index if dir > 0 else nl - 1 - lane_index]
		lat = move_toward(lat, lt, (60.0 if kind == DEMON or kind == RACER else 30.0) * delta)
		var f0 := f
		f += dir * v * delta / R.len[clampi(int(f), 0, R.N - 1)]
		# a junction it's passing: take the other road? (nothing to pass before its next switch)
		if nsp != null and (float(nsp[0]) - f) * dir <= 0.0:
			for sp in traffic._switch[road]:
				if int(sp[1]) != dir:
					continue
				var at := float(sp[0])
				if (at - f0) * dir > 0.0 and (at - f) * dir <= 0.0:
					var take: bool = sp[5] or (plan != null and plan == sp)
					if kind == RACER and chase != "fugitive":
						take = traffic._racer_takes(self, sp)
					if take and int(traffic.oneway.get(int(sp[2]), int(sp[4]))) != int(sp[4]) and self != traffic.racer:
						if sp[5]:
							v = -1.0   # its road ends here and the only way on is against the pilot: gone
						take = false
					if take:
						traffic._switch_to(self, sp)
						break
			nsp_road = -1   # passed it: find the next
		var R2: Simulation.TrackPath = R if road == original_road else traffic.sim.roads[road]
		if f < 0.5 or f > R2.N - 1.5:   # off an end it couldn't leave: gone (or a racer: kept on the road)
			if self == traffic.racer:
				f = clampf(f, 0.5, R2.N - 1.5)
				v = 0.0
				nsp_road = -1
			else:
				v = -1.0
		# Headway, merges and courtesy use road coordinates exclusively. The
		# frame's geometry pass projects ordinary drivers after these decisions.
		place_pending = defer_place and self != traffic.racer
		if not place_pending:
			place(R2)
		if v < 0.0:
			traffic.cars.erase(self)


var sim: Simulation
var view
var world: RoadWorld
var cars: Array[Car] = []
var _next_id := 1
var _rng := RandomNumberGenerator.new()
var _vlim := []           # per road: the speed limit at each sample (curvature, STARFIGHTER zones)
var _limit_start: Array[PackedInt32Array] = []
var _limit_end: Array[PackedInt32Array] = []
var _grade_spans: Array[Array] = []
var _grade_sources := []
var _drawing := FleetFrame.new()
var _switch := []         # per road: [at sample, need dir, to road, to sample, to dir, forced]
var _lanes := []          # per road: its lane offsets
var _mm := {}             # kind -> MultiMeshInstance3D
var _groups := {}         # Per road + direction; retain last frame's mostly sorted order.
var _grouped_count := -1
var _way_road := -1
var _way_dir := 0
var _way_lo := -INF
var _way_hi := INF
var _pilot := Car.new()
var _beams: MultiMeshInstance3D
var _beam_capacity := 0
var _beam_colors := PackedColorArray()
var _lamp_dark := -1.0    # the darkness the lamps' strength was last set for (view/outlook.gd)
var spawned := 0          # tests read these
var switched := 0
var illegal := 0
var update_ms := 0.0
var _tick := 0
var _brake_at_s := PackedFloat64Array()   # BRAKE_AT in samples (m / 24), BRAKE_BY, for _brake_for
var _brake_by := PackedFloat64Array()
# the racer
var racer: Car = null
var chase = null          # chase mode, when it is on (view/network_chase.gd): its craft has the racer's slot while one runs
var race_state := ""      # "" | "tail" | "race" | "done"
var race_t := 0.0         # s in this state
var race_gap := 0.0       # m: + the craft ahead
var race_result := ""     # "won" | "lost" | "peeled", once, for the view to take
var race_name := ""       # who: the racer's name (kept after it's gone)
const RACE_CLOSE := 600.0        # m: it's shadowing you this close behind (the ramjet then starts the race)
var _hw_time := 0.0       # s on a highway since the last racer
var _racer_count := 0
var _p_switches := []     # the craft's road changes: [from road, from sample, to road, to sample, to dir]
var _pod_prev := Vector2i(-1, -1)
var grade := true         # vehicles follow the road's grade (off: level at the lead's height, as v0.3.2, for comparisons)
var collide := false      # traffic's forcefields in the sims (off: the craft passes through; the tests turn them on)
var proad := -1           # the pilot's road and the way it's going on it: the way all traffic there goes
var pdir := 0
var oneway := {}          # road -> the way everything on it goes: the pilot's road, and every road it hands on to ahead (the way a craft joining it would go)
var _warm := 3            # frames: every kind drawn once under the ground, so its shaders compile at the start, not on first sight


func build(s, v, w) -> void:
	sim = s
	view = v
	world = w
	collide = bool(sim.P.obstacleCollisions)
	_rng.seed = 20261019
	for k in BRAKE_AT.size():
		_brake_at_s.append(float(BRAKE_AT[k]) / 24.0)
		_brake_by.append(float(BRAKE_BY[k]))
	for r in sim.roads.size():
		var R := sim.roads[r]
		_grade_sources.append(sim._net_h.get(r))
		_grade_spans.append(_grade_table(r, R.N))
		var lim := PackedFloat32Array()
		lim.resize(R.N)
		var kap := PackedFloat32Array()   # each sample's turn per metre (the cross product of its tangents)
		kap.resize(R.N)
		for j in R.N - 1:
			kap[j] = absf(R.tx[j] * R.ty[j + 1] - R.ty[j] * R.tx[j + 1]) / R.len[j]
		for i in R.N:
			var k := 0.0
			for j in range(maxi(0, i - 6), mini(R.N - 2, i + 6)):
				k = maxf(k, kap[j])
			lim[i] = 1e9 if k < 1e-7 else sqrt(G / k)   # per g of grip: times sqrt(grip) for each vehicle
			if R.mode[i] == 0:
				lim[i] = -SF_V   # a STARFIGHTER zone: a fixed cap (negative marks it)
			if R.shaft and world.shaft.on(r, float(i)):
				lim[i] = 1e9     # a shaft's bulb is the plan's, not a bend: it carries them round
		_vlim.append(lim)
		# All readings in a run give exactly the same limit, even on a constant-radius bend.
		var starts := PackedInt32Array()
		var ends := PackedInt32Array()
		starts.resize(R.N)
		ends.resize(R.N)
		for i in range(1, R.N):
			starts[i] = starts[i - 1] if lim[i] == lim[i - 1] else i
		ends[R.N - 1] = R.N
		for i in range(R.N - 2, -1, -1):
			ends[i] = ends[i + 1] if lim[i] == lim[i + 1] else i + 1
		_limit_start.append(starts)
		_limit_end.append(ends)
		_lanes.append(LANES_HWY if R.w[0] >= 300.0 else LANES_RAMP)
		_switch.append([])
	for J in sim.junctions:
		var C := sim.roads[int(J[3])]
		if not _public_road(C):
			continue
		var cb: int = 0 if int(J[4]) == 0 else C.N - 1
		var ca: int = world._map(J, cb)
		for side in 2:   # from the parent onto the joining road, and back
			var r: int = int(J[0]) if side == 0 else int(J[3])
			var q: int = int(J[3]) if side == 0 else int(J[0])
			var at: int = ca if side == 0 else cb
			var iq: int = cb if side == 0 else ca
			for d in [1, -1]:
				var dq: int = d * int(J[6])
				var qz0: int = int(J[4]) if side == 0 else int(J[1])
				var qz1: int = int(J[5]) if side == 0 else int(J[2])
				if qz0 == 0 and dq < 0:
					continue
				if qz1 == sim.roads[q].N - 1 and dq > 0:
					continue
				var R := sim.roads[r]
				var to_end: int = (R.N - 1 - at) if d > 0 else at
				var after := []   # the road beyond: [m on, its limit there (the vlim code)]
				var Q := sim.roads[q]
				for dd in AFTER:
					var qi := clampi(iq + dq * int(dd / 24.0), 0, Q.N - 1)
					after.append([dd, _vlim[q][qi]])
				_switch[r].append([at, d, q, iq, dq, to_end < 260, after, {}])
	_drawing.roads = sim.roads
	_drawing.shaft = world.shaft
	_drawing.grade_spans = _grade_spans
	_build_meshes()


## Hermite spans used by the simulation. Index by the integer part of the station,
## so a freight train can sample its deck eight times without eight binary searches.
func _grade_table(road: int, count: int) -> Array:
	var keys: Array = sim._net_h.get(road, [])
	var spans: Array[HeightSpan] = []
	if keys.size() < 2:
		return spans
	spans.resize(count)
	var before := HeightSpan.new()
	before.end = float(keys[0][0])
	var after := HeightSpan.new()
	after.first = float(keys[-1][0])
	spans.fill(after)
	for i in range(int(before.end)):
		spans[i] = before
	for k in keys.size() - 1:
		var a: Array = keys[k]
		var z: Array = keys[k + 1]
		var span := HeightSpan.new()
		span.first = float(a[0])
		span.end = float(z[0])
		span.height = float(a[1])
		var rise := float(z[1]) - span.height
		var length := maxf(1.0, span.end - span.first)
		span.inv_length = 1.0 / length
		span.b = length * Simulation.NET_STEP * float(a[2])
		var last_tangent := length * Simulation.NET_STEP * float(z[2])
		span.c = 3.0 * rise - 2.0 * span.b - last_tangent
		span.d = -2.0 * rise + span.b + last_tangent
		span.flat = rise == 0.0 and span.b == 0.0 and last_tangent == 0.0
		for i in range(int(span.first), int(span.end)):
			spans[i] = span
		if k == keys.size() - 2:
			spans[int(span.end)] = span
	return spans




## Every frame: spawn and drop round the craft, drive, follow the craft's racer, render, and hand the
## near ones to the sim as obstacles.
func update(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_tick += 1
	var px: float = sim.pod.x
	var py: float = sim.pod.y
	_track_pod()
	# Detect external changes too: tests and chase mode can replace the fleet.
	var regroup := cars.size() != _grouped_count
	for k in range(cars.size() - 1, -1, -1):
		var c := cars[k]
		if c != racer and Vector2(c.x - px, c.y - py).length_squared() > R_KEEP * R_KEEP:
			cars.remove_at(k)
			regroup = true
		elif c.bucket_order != k or c.bucket != c.road * 2 + int(c.dir > 0):
			regroup = true
	var tries := 0
	var want := _target(px, py)
	while cars.size() < want and tries < 12:
		tries += 1
		_spawn(px, py, spawned < want)   # at the start: anywhere from 2 km out, so there's traffic at once
	var pod_car := _pod_as_car(_pilot)
	regroup = regroup or cars.size() != _grouped_count or pod_car.bucket != pod_car.road * 2 + int(pod_car.dir > 0)
	if regroup:
		_groups.clear()
		_grouped_count = cars.size()
		for i in cars.size() + 1:
			var car := pod_car if i == cars.size() else cars[i]
			car.bucket = car.road * 2 + int(car.dir > 0)
			car.bucket_order = i
			if not _groups.has(car.bucket):
				_groups[car.bucket] = []
			_groups[car.bucket].append(car)
	# (standing on a pad too: nothing comes the wrong way past a craft parked at the roadside)
	if pod_car and (pod_car.v > 20.0 or bool(sim.P.get("pads", false))):
		proad = pod_car.road
		pdir = pod_car.dir
	# Nothing comes at you on your road, nor on a road you may be about to join (they came the wrong way
	# until the craft was on it: an exit taken into a stream of oncoming traffic). Far ones turn round, near ones go.
	var hint := float(sim.pod.hint)
	var new_way := proad != _way_road or pdir != _way_dir or hint < _way_lo or hint >= _way_hi
	if new_way:
		_way_road = proad
		_way_dir = pdir
		_way_lo = -INF
		_way_hi = INF
		oneway.clear()
		if proad >= 0:
			oneway[proad] = pdir
			for sp in _switch[proad]:
				if int(sp[1]) != pdir:
					continue
				# Integer hints. For dir=-1 the first included hint is at-19,
				# for dir=+1 the first excluded hint is at+20.
				var boundary := float(sp[0]) + (20.0 if pdir > 0 else -19.0)
				if hint < boundary:
					_way_hi = minf(_way_hi, boundary)
				else:
					_way_lo = maxf(_way_lo, boundary)
				if (float(sp[0]) - hint) * pdir > -20.0 and not oneway.has(int(sp[2])):
					oneway[int(sp[2])] = int(sp[4])
	if proad >= 0 and (regroup or new_way):
		for k in range(cars.size() - 1, -1, -1):
			var c := cars[k]
			var way: int = oneway.get(c.road, 0)
			if way == 0 or c.dir == way or c == racer:
				continue
			if Vector2(c.x - px, c.y - py).length_squared() > FLIP_FAR * FLIP_FAR:
				c.lane = _lanes[c.road].size() - 1 - c.lane   # the same place across, the other way
				c.dir = way
				_place(c)
			else:
				cars.remove_at(k)
	for key: int in _groups:
		var road: int = key >> 1
		var profile = sim._net_h.get(road)
		if not is_same(profile, _grade_sources[road]):
			_grade_sources[road] = profile
			_grade_spans[road] = _grade_table(road, sim.roads[road].N)
		var arr: Array = _groups[key]
		# Traffic usually keeps its order between frames. Only an overtake,
		# a merge or a new arrival requires moving an entry.
		var last := -INF
		var last_order := -1
		for i in arr.size():
			var car: Car = arr[i]
			var along := car.f * car.dir
			if along > last or (along == last and car.bucket_order >= last_order):
				last = along
				last_order = car.bucket_order
				continue
			var j := i
			while j > 0:
				var prior: Car = arr[j - 1]
				var other := prior.f * prior.dir
				if other < along or (other == along and prior.bucket_order < car.bucket_order):
					break
				arr[j] = prior
				j -= 1
			arr[j] = car
		for idx in arr.size():
			var c: Car = arr[idx]
			if c == pod_car:
				continue
			c.owed += delta
			if c != racer and (absf(c.x - px) > NEAR or absf(c.y - py) > NEAR) and (_tick + c.id) % 2 != 0:
				continue
			c.drive(self, arr, idx, c.owed, true)
			c.owed = 0.0
	_race(delta, pod_car)
	_render()
	_feed()
	update_ms = (Time.get_ticks_usec() - t0) / 1000.0


## How many vehicles to keep round (x, y): 60 mid-country, up to TARGET round a city.
func _target(x: float, y: float) -> int:
	var w := 0.0
	for city in sim.cities:
		w = maxf(w, exp(-pow(Vector2(x - city.cx, y - city.cy).length() / 40000.0, 2.0)))
	return int(90.0 + (TARGET - 90.0) * w)


## Lane `lane` counted from the right (the way the car goes): its place across the road.
func _lane_lat(c: Car, lane: int) -> float:
	var L: Array = _lanes[c.road]
	var k := mini(lane, L.size() - 1)
	return L[k] if c.dir > 0 else L[L.size() - 1 - k]


## The craft as a vehicle (for the others' headways): its road, its way, its place across.
func _pod_as_car(c: Car = null) -> Car:
	var P := sim.pod
	var R := sim.roads[P.path]
	var i: int = clampi(P.hint, 0, R.N - 1)
	var along: float = P.vx * R.tx[i] + P.vy * R.ty[i]
	if c == null:
		c = Car.new()
	c.left_width = 7.0
	c.right_width = 7.0
	c.front = 24.0
	c.rear = 24.0
	c.id = 0
	c.road = P.path
	c.dir = 1 if along >= 0.0 else -1
	if absf(along) < 1.0:      # at rest: the way it faces (its speed says nothing)
		c.dir = 1 if cos(P.th) * R.tx[i] + sin(P.th) * R.ty[i] >= 0.0 else -1
	c.f = float(i)
	c.v = absf(along)
	c.lat = (P.x - R.px[i]) * R.nx[i] + (P.y - R.py[i]) * R.ny[i]
	# The engines can swing wider and run well ahead of the pod. Other drivers
	# reserve that physical corridor, not just the cockpit's centre point.
	for body in sim.bodies:
		var dx: float = body.x - P.x
		var dy: float = body.y - P.y
		var across: float = dx * R.nx[i] + dy * R.ny[i]
		var ahead: float = (dx * R.tx[i] + dy * R.ty[i]) * c.dir
		c.left_width = maxf(c.left_width, across + 3.0)
		c.right_width = maxf(c.right_width, -across + 3.0)
		c.front = maxf(c.front, ahead + 5.0)
		c.rear = maxf(c.rear, -ahead + 5.0)
	return c


static func _public_road(road: Simulation.TrackPath) -> bool:
	# (not Mount Hyperion's road either: traffic goes by the map, and up an 88 degree wall that is 29 times the speed along it)
	return road.role == "" and road.name != "SAurora" and not road.deck and not RoadWorld.STUNT_ROADS.has(road.name)


func _spawn(px: float, py: float, first: bool) -> void:
	# a random chunk round the craft, a random sample in it
	var gc := Vector2i(int(floor(px / world.CELL)), int(floor(py / world.CELL)))
	var rc := int(ceil(R_SPAWN.y / world.CELL))
	var cell := gc + Vector2i(_rng.randi_range(-rc, rc), _rng.randi_range(-rc, rc))
	var entries: Array = world.grid.get(cell, [])
	if entries.is_empty():
		return
	var e: Array = entries[_rng.randi() % entries.size()]
	var r: int = e[0]
	var R := sim.roads[r]
	if not _public_road(R):
		return
	var i: int = clampi(e[1] * world.CH + _rng.randi_range(0, world.CH - 1), 1, R.N - 2)
	var d := Vector2(R.px[i] - px, R.py[i] - py).length()
	if d > R_SPAWN.y or d < (2000.0 if first else R_SPAWN.x):
		return
	# thicker near the cities and the interchanges
	var w := 0.35
	for city in sim.cities:
		w += 1.2 * exp(-pow(Vector2(R.px[i] - city.cx, R.py[i] - city.cy).length() / 25000.0, 2.0))
	if R.w[0] < 300.0:
		w += 0.6   # ramps and bypasses: at the interchanges
	if _rng.randf() * 1.6 > w:
		return
	var c := Car.new()
	c.id = _next_id
	_next_id += 1
	c.road = r
	c.f = float(i)
	c.dir = 1 if _rng.randf() < 0.5 else -1
	if oneway.has(r):
		c.dir = oneway[r]
	var roll := _rng.randf()
	var express := _traffic_tier(r, c.f)
	var car_cut := lerpf(0.58, 0.48, express)
	var slow_cut := car_cut + lerpf(0.22, 0.05, express)
	var demon_cut := slow_cut + lerpf(0.06, 0.39, express)
	c.kind = CAR if roll < car_cut else (SLOW if roll < slow_cut else (DEMON if roll < demon_cut else TRANSPORT))
	var nl: int = _lanes[r].size()
	match c.kind:
		CAR:
			c.vdes = _rng.randf_range(2000.0, 3000.0) / MPH
			c.lane = _rng.randi_range(0, nl - 1)
			c.col = [Color(0.85, 0.86, 0.9), Color(0.2, 0.35, 0.8), Color(0.75, 0.12, 0.1), Color(0.95, 0.75, 0.2), Color(0.15, 0.16, 0.18), Color(0.3, 0.6, 0.45)][_rng.randi() % 6]
			c.a_up = 1.5 * G
			c.a_lat = 9.0 * G
			c.headway = 1.2
		SLOW:
			c.vdes = _rng.randf_range(1000.0, 1500.0) / MPH
			c.lane = 0 if _rng.randf() < 0.6 else 1
			c.col = [Color(0.82, 0.77, 0.62), Color(0.38, 0.61, 0.65), Color(0.78, 0.48, 0.25), Color(0.57, 0.62, 0.69)][_rng.randi() % 4]
			c.a_up = 0.8 * G
			c.a_lat = 7.0 * G
			c.headway = 1.6
		DEMON:
			c.vdes = _rng.randf_range(4000.0, 4800.0) / MPH
			c.lane = nl - 1
			c.col = [Color(0.9, 0.1, 0.6), Color(0.1, 0.9, 0.9), Color(0.6, 0.1, 0.95)][_rng.randi() % 3]
			c.a_up = 3.0 * G
			c.a_lat = 11.0 * G
			c.headway = 0.45
		TRANSPORT:
			c.vdes = _rng.randf_range(1450.0, 1750.0) / MPH
			c.lane = 0
			c.col = [Color(0.9, 0.55, 0.15), Color(0.65, 0.22, 0.16), Color(0.33, 0.49, 0.61), Color(0.43, 0.52, 0.29)][_rng.randi() % 4]
			c.a_up = 0.5 * G
			c.a_lat = 6.0 * G
			c.headway = 2.0
	c.cruise = c.vdes
	c.cruise_goal = _cruise_for(c, express)
	c.vdes = c.cruise_goal
	c.turn_p = 0.35 if c.kind != TRANSPORT else 0.15
	c.lat = _lane_lat(c, c.lane)
	# A car can spawn beside an exit. Choose its route before its initial speed,
	# so it is already able to brake for that road's curves and city zone.
	_next_switch(c)
	_decide(c)
	c.v = _speed_cap(c, 0.0)
	if not _spawn_clear(c):
		return
	_place(c)
	cars.append(c)
	spawned += 1


## Admission happens in the haze: never insert a car into a gap that already
## needs impossible braking. Include approaching followers and freight tails.
func _spawn_clear(c: Car) -> bool:
	var nearby: Array = cars.duplicate()
	var pod := _pod_as_car()
	if pod:
		nearby.append(pod)
	for o: Car in nearby:
		if o.road != c.road or o.dir != c.dir:
			continue
		var committed := o.lat if o.id == 0 else _lane_lat(o, o.lane)
		if c.lat < minf(o.lat, committed) - 25.0 or c.lat > maxf(o.lat, committed) + 25.0:
			continue
		var gap := (o.f - c.f) * c.dir * 24.0
		var leader: Car = o if gap >= 0.0 else c
		var follower: Car = c if gap >= 0.0 else o
		var closing := maxf(0.0, follower.v - leader.v)
		var tail := (TRAIN - 1) * TRAIN_GAP if leader.kind == TRANSPORT else 0.0
		var space := 40.0 + tail + maxf(100.0, follower.v * follower.headway * 0.5)
		space += closing * closing / (2.0 * BRAKE)
		if absf(gap) < space:
			return false
	return true


## The speed it can hold here: its grip in the curve, a city's STARFIGHTER cap.
func _limit(c: Car) -> float:
	var l: float = _vlim[c.road][clampi(int(c.f), 0, _vlim[c.road].size() - 1)]
	if l < 0.0:
		return -l
	return l * sqrt(c.a_lat / G)


## A gradual express fraction along the actual ramps. A shaft's climb is not another
## traffic tier: keep its entrance altitude, also for a carried recovery twist.
func _traffic_tier(road: int, f: float) -> float:
	var at := f
	if world.shaft.maps.has(road):
		var span: Dictionary = world.shaft.maps[road]
		if f >= float(span.i0) and f <= float(span.i1):
			at = float(span.i0)
	return smoothstep(120.0, 500.0, sim.net_height(road, at))


func _cruise_for(c: Car, express: float) -> float:
	var boost := 0.30 if c.kind == CAR else (0.10 if c.kind == DEMON else 0.0)
	return c.cruise * (1.0 + boost * express)


func _drive(c: Car, arr: Array, idx: int, delta: float) -> void:
	c.drive(self, arr, idx, delta, false)


## The fastest it can go here and still brake (at BRAKE) for every limit on its road up to 50 km on
## (down to each by the reading before it), each `margin` m nearer than it is.
func _brake_for(c: Car, margin := 0.0) -> float:
	var ordinary_margin := margin >= 0.0 and margin <= _brake_by[1]
	if ordinary_margin and c.brake_road == c.road and c.dir == c.brake_dir and c.a_lat == c.brake_grip and c.f >= c.brake_lo and c.f < c.brake_hi:
		return minf(minf(c.vdes, c.brake_here), sqrt(maxf(0.0, c.brake_ahead_sq - 2.0 * BRAKE * margin)))
	var vl: PackedFloat32Array = _vlim[c.road]
	var starts := _limit_start[c.road]
	var ends := _limit_end[c.road]
	var grip := sqrt(c.a_lat / G)
	var lo := -INF
	var hi := INF
	var here := INF
	var ahead_sq := INF
	var exact := c.vdes
	for k in range(-1, _brake_at_s.size()):
		var offset := 0.0 if k < 0 else c.dir * _brake_at_s[k]
		var i := clampi(int(c.f + offset), 0, vl.size() - 1)
		if starts[i] > 0:
			lo = maxf(lo, starts[i] - offset)
		if ends[i] < vl.size():
			hi = minf(hi, ends[i] - offset)
		var raw := vl[i]
		var limit := -raw if raw < 0.0 else raw * grip
		if k <= 0:
			here = minf(here, limit)
		else:
			ahead_sq = minf(ahead_sq, limit * limit + 2.0 * BRAKE * _brake_by[k])
		if not ordinary_margin:
			exact = minf(exact, limit if k < 0 else sqrt(limit * limit + 2.0 * BRAKE * maxf(0.0, _brake_by[k] - margin)))
	c.brake_lo = lo
	c.brake_hi = hi
	c.brake_road = c.road
	c.brake_dir = c.dir
	c.brake_grip = c.a_lat
	c.brake_here = here
	c.brake_ahead_sq = ahead_sq
	return minf(minf(c.vdes, here), sqrt(maxf(0.0, ahead_sq - 2.0 * BRAKE * margin))) if ordinary_margin else exact


## _brake_for, and slow enough for the road beyond the exit it's decided on.
func _speed_cap(c: Car, margin: float) -> float:
	var vt := _brake_for(c, margin)
	if c.plan != null:
		var ds: float = (float(c.plan[0]) - c.f) * c.dir * 24.0
		if ds > 0.0:   # (not passed it yet)
			ds = maxf(0.0, ds - margin)
			var limits: Dictionary = c.plan[7]
			if not limits.has(c.a_lat):
				var ahead_sq := INF
				var by := 0.0
				for pr in c.plan[6]:
					var raw: float = pr[1]
					var limit := -raw if raw < 0.0 else raw * sqrt(c.a_lat / G)
					ahead_sq = minf(ahead_sq, limit * limit + 2.0 * BRAKE * by)
					by = float(pr[0])
				limits[c.a_lat] = ahead_sq
			vt = minf(vt, sqrt(float(limits[c.a_lat]) + 2.0 * BRAKE * ds))
	return vt


## Is the complete merge clear? A chosen destination is occupied before the body arrives.
## Full road bucket: eight cars in other lanes must not hide a fast ninth follower.
func _clear(arr: Array, idx: int, c: Car, lat_n: float) -> bool:
	var duration := absf(lat_n - c.lat) / (60.0 if c.kind == DEMON or c.kind == RACER else 30.0) + 0.6
	var swept_lo := minf(c.lat, lat_n) - c.right_width
	var swept_hi := maxf(c.lat, lat_n) + c.left_width
	var front_gap := c.v * c.headway * 1.3 + c.front
	var rear_gap := c.rear + 12.0
	var n := arr.size()
	for step in range(1, n):
		var offset := (step + 1) >> 1
		var k := idx + (offset if step % 2 == 1 else -offset)
		k = posmod(k, n)
		var o: Car = arr[k]
		if o.road != c.road or o.dir != c.dir:
			continue # a road switch or a direction normalization can leave a stale bucket entry
		var g: float = (o.f - c.f) * c.dir * 24.0
		var future := g + (o.v - c.v) * duration
		var tail := (TRAIN - 1) * TRAIN_GAP if o.kind == TRANSPORT else 0.0
		var unsafe_gap := minf(g, future) < front_gap + o.rear + tail if g > 0.0 else maxf(g, future) > -(rear_gap + o.front)
		if not unsafe_gap:
			continue
		var committed := o.lat if o.id == 0 else _lane_lat(o, o.lane)
		if swept_hi >= minf(o.lat, committed) - o.right_width - 10.0 and swept_lo <= maxf(o.lat, committed) + o.left_width + 10.0:
			return false
	return true


## Ordinary road manners: a persistent faster follower gets room if an adjacent gap exists.
## No player-specific steering, speed concession or last-second rescue. Racers and freight
## keep their established behavior; all of them can still be the approaching road user.
func _courtesy(c: Car, arr: Array, idx: int) -> bool:
	if c.kind == RACER or c.kind == TRANSPORT:
		return false
	if c.lc_cool > 0.0 or absf(c.lat - _lane_lat(c, c.lane)) > 1.0:
		c.flow_source = -1
		c.flow_notice = 0.0
		return false
	if c.flow_clock > 0.0:
		return false
	var glance := 0.30 + float(c.id % 3) * 0.021
	c.flow_clock = glance
	var lateral_speed := 60.0 if c.kind == DEMON else 30.0
	var maneuver := (45.0 if _lanes[c.road].size() == 8 else 50.0) / lateral_speed
	var protected_distance := c.v * (maneuver + 0.9) + 300.0
	var route_clear := true
	if c.nsp != null and (float(c.nsp[0]) - c.f) * c.dir * 24.0 < protected_distance:
		route_clear = false
	if world.shaft.maps.has(c.road):
		var sh: Dictionary = world.shaft.maps[c.road]
		var to_f := c.f + c.dir * protected_distance / 24.0
		if maxf(c.f, to_f) >= float(sh.i0) and minf(c.f, to_f) <= float(sh.i1):
			route_clear = false
	var follower: Car = null
	if route_clear:
		for k in range(idx - 1, -1, -1):
			var o: Car = arr[k]
			if o.road != c.road or o.dir != c.dir:
				continue
			var behind := (c.f - o.f) * c.dir * 24.0
			if behind > R_SPAWN.y:
				break
			var corridor_lo := o.lat - o.right_width - c.left_width - 18.0
			var corridor_hi := o.lat + o.left_width + c.right_width + 18.0
			if behind <= 0.0 or c.lat < corridor_lo or c.lat > corridor_hi:
				continue
			# The nearest vehicle in this corridor is the one actually approaching us.
			var closing := o.v - c.v
			if closing > 120.0:
				var catch_time := behind / closing
				if catch_time > maneuver + 0.9 and catch_time < 11.0:
					follower = o
			break
	if follower == null:
		c.flow_source = -1
		c.flow_notice = 0.0
		return false
	if c.flow_source != follower.id:
		c.flow_source = follower.id
		c.flow_notice = 0.0
		return false
	c.flow_notice += glance
	if c.flow_notice < 0.30 + float(c.id % 7) * 0.055:
		return false
	# Prefer the move that opens the largest gap, keeping right on a tie.
	# Commit once; do not mirror steering or repeatedly chase the follower's lane.
	var chosen := -1
	var clearance := 0.0
	for dl in [-1, 1]:
		var lane: int = c.lane + dl
		if lane < 0 or lane >= _lanes[c.road].size():
			continue
		var target := _lane_lat(c, lane)
		var gap := maxf(target - follower.lat - follower.left_width - c.right_width, follower.lat - target - follower.right_width - c.left_width)
		if gap > clearance and _clear(arr, idx, c, target):
			chosen = lane
			clearance = gap
	if chosen >= 0:
		c.lane = chosen
		c.lc_cool = 5.0 + float(c.id % 7) * 0.45
		c.flow_source = -1
		c.flow_notice = 0.0
		return true
	return false


## The next junction ahead within PLAN_AHEAD: decided once, whether it takes it (forced ones always;
## never onto the pilot's road against the pilot).
func _decide(c: Car) -> void:
	var best = c.nsp
	if best == null:
		return
	var bd: float = (float(best[0]) - c.f) * c.dir * 24.0
	if best == null or bd > PLAN_AHEAD or int(best[0]) == c.decided:
		return
	c.decided = int(best[0])
	c.vcap_road = -1   # read the road ahead again now (it may be slowing for this exit)
	var take: bool = best[5] or _rng.randf() < c.turn_p
	if int(oneway.get(int(best[2]), int(best[4]))) != int(best[4]) and not best[5]:
		take = false
	c.plan = best if take else null


## The nearest switch strictly ahead on its road its way (the first listed, of several at one sample).
func _next_switch(c: Car) -> void:
	c.nsp = null
	c.nsp_road = c.road
	c.nsp_dir = c.dir
	var bd := INF
	for sp in _switch[c.road]:
		if int(sp[1]) != c.dir:
			continue
		var ds: float = (float(sp[0]) - c.f) * c.dir
		if ds > 0.0 and ds < bd:
			bd = ds
			c.nsp = sp


func _switch_to(c: Car, sp: Array) -> void:
	var over: float = (c.f - float(sp[0])) * c.dir   # samples past the switch
	c.road = sp[2]
	c.dir = sp[4]
	c.f = float(sp[3]) + over * c.dir
	var R := sim.roads[c.road]
	var i := clampi(int(c.f), 0, R.N - 1)
	c.lat = (c.x - R.px[i]) * R.nx[i] + (c.y - R.py[i]) * R.ny[i]   # where it is across the new road
	c.lane = mini(c.lane, _lanes[c.road].size() - 1)
	c.plan = null
	c.decided = -1
	c.nsp_road = -1
	c.lc_cool = maxf(c.lc_cool, 3.0)
	c.flow_source = -1
	c.flow_notice = 0.0
	switched += 1


func _place(c: Car) -> void:
	c.place(sim.roads[c.road])


# --- the racer -----------------------------------------------------------------------------------

## The craft's road changes, so a racer behind it can follow.
func _track_pod() -> void:
	var cur := Vector2i(sim.pod.path, sim.pod.hint)
	if _pod_prev.x >= 0 and cur.x != _pod_prev.x:
		var R := sim.roads[cur.x]
		var along: float = sim.pod.vx * R.tx[cur.y] + sim.pod.vy * R.ty[cur.y]
		_p_switches.append([_pod_prev.x, _pod_prev.y, cur.x, cur.y, 1 if along >= 0.0 else -1])
		if _p_switches.size() > 12:
			_p_switches.pop_front()
	_pod_prev = cur


func _racer_takes(c: Car, sp: Array) -> bool:
	for s in _p_switches:   # where the craft went from this road
		if int(s[0]) == c.road and int(s[2]) == int(sp[2]) and absi(int(s[1]) - int(sp[0])) < 200:
			return true
	return sp[5]


func _tail_speed(c: Car) -> float:
	var P := sim.pod
	var pv := Vector2(P.vx, P.vy).length()
	var behind := _gap_to_pod(c)   # m the craft is ahead
	return clampf(pv + (behind - 160.0) * 0.6, 0.0, 6500.0 / MPH)


## How far ahead of the racer the craft is, along the racer's way (straight line projected).
func _gap_to_pod(c: Car) -> float:
	return (sim.pod.x - c.x) * c.hx + (sim.pod.y - c.y) * c.hy


func _race(delta: float, pod_car: Car) -> void:
	var P := sim.pod
	var pv := Vector2(P.vx, P.vy).length()
	var on_hwy: bool = sim.roads[P.path].w[0] >= 300.0 and _public_road(sim.roads[P.path])
	if race_state == "":
		if on_hwy and pv > 2000.0 / MPH:
			_hw_time += delta * lerpf(0.85, 1.30, _traffic_tier(P.path, float(P.hint)))
		if _hw_time >= (RACER_FIRST if _racer_count == 0 else RACER_EVERY) and pod_car and on_hwy and pv > 2000.0 / MPH:
			_spawn_racer(pod_car)
		return
	race_t += delta
	if racer == null or not cars.has(racer):
		race_state = ""
		racer = null
		return
	match race_state:
		"tail":
			var gp := _gap_to_pod(racer)
			if sim.mode == "ramjet" and gp > -50.0 and gp < RACE_CLOSE:
				race_state = "race"
				race_t = 0.0
				race_gap = _gap_to_pod(racer)
				var st: Array = RACERS[racer.name]
				racer.vdes = st[0] / MPH
				racer.a_up = 3.5 * G
			elif race_t > RACER_PATIENCE or _gap_to_pod(racer) > 6000.0:
				_end_race("peeled")
		"race":
			race_gap += (pv - racer.v) * delta
			if race_gap >= RACE_WIN:
				_end_race("won")
			elif race_gap <= -RACE_WIN:
				_end_race("lost")
		"done":
			if race_t > 20.0 or Vector2(racer.x - P.x, racer.y - P.y).length() > 20000.0:
				cars.erase(racer)
				racer = null
				race_state = ""


func _spawn_racer(pc: Car) -> void:
	var names := RACERS.keys()
	var nm: String = names[_racer_count % names.size()]
	var st: Array = RACERS[nm]
	var c := Car.new()
	c.id = 900000 + _racer_count
	c.kind = RACER
	c.name = nm
	c.road = pc.road
	c.dir = pc.dir
	c.f = pc.f - pc.dir * 2500.0 / 24.0
	c.nsp_road = -1
	var R := sim.roads[c.road]
	if c.f < 2.0 or c.f > R.N - 3.0:
		return
	c.v = pc.v + 300.0 / MPH
	c.vdes = c.v
	c.a_up = 3.0 * G
	c.a_lat = st[1] * G
	c.headway = st[2]
	c.col = st[3]
	var nl: int = _lanes[c.road].size()
	var plane := 0
	var best := INF
	for k in nl:
		var d := absf(_lane_lat(c, k) - pc.lat)
		if d < best:
			best = d
			plane = k
	c.lane = clampi(plane + (1 if plane < nl - 1 else -1), 0, nl - 1)
	c.lat = _lane_lat(c, c.lane)
	c.turn_p = 0.0
	_place(c)
	cars.append(c)
	racer = c
	race_name = nm
	race_state = "tail"
	race_t = 0.0
	_racer_count += 1
	_hw_time = 0.0


func _end_race(result: String) -> void:
	race_state = "done"
	race_t = 0.0
	race_result = result
	if racer:
		racer.vdes = 2200.0 / MPH   # off the gas: it drops back and leaves


## The dash's line while a racer is about ("" when none).
func race_text() -> String:
	if chase != null and chase.state == "on":
		return chase.text()
	if racer == null or race_state == "" or race_state == "done":
		return ""
	if race_state == "tail":
		var gp := _gap_to_pod(racer)
		if gp > RACE_CLOSE:
			return "RACER CLOSING  %s  %.1f mi back" % [racer.name, gp / 1609.344]
		return "RACER BEHIND  %s   light the ramjet to race" % racer.name
	var mi := race_gap / 1609.344
	var bar := ""
	var k := clampi(roundi((race_gap / RACE_WIN + 1.0) * 5.0), 0, 10)
	for q in 11:
		bar += "|" if q == 5 else ("=" if (q < 5 and q >= k) or (q > 5 and q <= k) else ".")
	return "RACE  %s  YOU %s%.2f mi  [%s]" % [racer.name, "+" if mi >= 0.0 else "-", absf(mi), bar]


# --- rendering and the sims' obstacles ---------------------------------------------------------

func _build_meshes() -> void:
	var bounds := AABB(Vector3(-40000, -100, -40000), Vector3(80000, 20000, 80000))
	for kind in FLEET.size():
		var batch := Batch.new()
		batch.name = "traffic_tractor" if kind == TRACTOR else "traffic_%d" % kind
		var slots := TARGET * (TRAIN - 1) if kind == TRANSPORT else TARGET + 8
		batch.configure(FLEET[kind], slots, 500.0, bounds, true, kind == RACER)
		add_child(batch)
		_mm[kind] = batch
		_drawing.writers.append(batch.writer)
	_drawing.tractor = _drawing.writers[TRACTOR]
	# Far bodies: never under a couple of pixels wide (art/traffic/fleet.gdshader), every kind grown alike so a
	# freighter stays bigger than a car at any distance.
	for kind in _mm:
		for node in [_mm[kind], (_mm[kind] as Node).get_node("Distance")]:
			(node as GeometryInstance3D).set_instance_shader_parameter("grow_per_m", BODY_MIN_ANG / BODY_HALF_WIDTH)
	# A pair of lamps per vehicle: its tail lamps, or its head lamps when its nose is toward the eye, the size
	# they are, so a vehicle a kilometre off is a pair and one at the horizon a faint point. They were one glow a
	# vehicle, a quarter of a degree across at any distance (as wide as the vehicle past a kilometre) and as
	# bright at the horizon as beside you (Luke: "it just looks like a blur of taillights from far away").
	var bmm := MultiMesh.new()
	bmm.transform_format = MultiMesh.TRANSFORM_3D
	bmm.use_colors = true
	bmm.mesh = lamp_mesh()
	bmm.instance_count = TARGET + 12
	_beam_capacity = bmm.instance_count
	_beam_colors.resize(_beam_capacity)
	bmm.visible_instance_count = 0
	_beams = MultiMeshInstance3D.new()
	_beams.name = "traffic_lights"
	_beams.multimesh = bmm
	var bm := ShaderMaterial.new()
	bm.shader = preload("res://view/traffic_lamps.gdshader")
	bm.set_shader_parameter("min_px", LAMP_MIN_PX)
	bm.set_shader_parameter("grow_per_m", BODY_MIN_ANG / BODY_HALF_WIDTH)
	_beams.material_override = bm
	_beams.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beams.custom_aabb = AABB(Vector3(-40000, -100, -40000), Vector3(80000, 20000, 80000))
	add_child(_beams)


## The lamps' mesh: a quad with all four corners at one point, its corner in UV (the shader spreads it).
static func lamp_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for uv in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		st.set_color(Color.WHITE)
		st.set_uv(uv)
		st.set_normal(Vector3.UP)
		st.add_vertex(Vector3.ZERO)
	return st.commit()


func _render() -> void:
	_drawing.ox = view.org_x
	_drawing.oy = view.org_y
	_drawing.grade = grade
	var camera := get_viewport().get_camera_3d()
	_drawing.eye = camera.global_position if camera else Vector3.ZERO
	_drawing.eye_x = _drawing.eye.x + _drawing.ox
	_drawing.eye_y = _drawing.oy - _drawing.eye.z
	_drawing.pod_v = Vector2(sim.pod.vx, sim.pod.vy)
	for c in cars:
		c.draw(_drawing, _drawing.writers[c.kind])
	var dark: float = Outlook.darkness()
	if dark != _lamp_dark:      # (the hour changes with the menu, or not at all)
		_lamp_dark = dark
		(_beams.material_override as ShaderMaterial).set_shader_parameter("energy", lerpf(LAMP_ENERGY.x, LAMP_ENERGY.y, dark))
	var bmm := _beams.multimesh
	var nb := mini(cars.size(), _beam_capacity)
	for i in nb:
		var c := cars[i]
		bmm.set_instance_transform(i, Transform3D(c.lamp_basis, c.lamp_position))
		if _beam_colors[i] != c.lamp_color:
			_beam_colors[i] = c.lamp_color
			bmm.set_instance_color(i, c.lamp_color)
	for kind in _mm:
		(_mm[kind] as Batch).finish_frame(_warm > 0)
	if _warm > 0:
		_warm -= 1
		if nb == 0:
			bmm.set_instance_transform(0, Transform3D(Basis(), Vector3(0.0, -60.0, -40.0)))
			nb = 1
	bmm.visible_instance_count = nb


## The near vehicles as the sims' obstacles: circles along each body (a train's cars each), with
## its velocity (the sim moves them between frames).
## How far from the pod an obstacle can matter before the next feed, at the craft's speed (m/s).
static func feed_reach(speed: float) -> float:
	return minf(R_FIELD, FEED_REACH + (maxf(speed, 0.0) + FEED_CLOSING) * FEED_AHEAD_S)


func _feed() -> void:
	if not collide or not sim.P.obstacleCollisions:
		sim.obstacles = []
		return
	var px: float = sim.pod.x
	var py: float = sim.pod.y
	var reach := feed_reach(Vector2(sim.pod.vx, sim.pod.vy).length())
	var obs: Array = world.obstacles_near(px, py, reach)
	for c in cars:
		var trail := TRAIN * TRAIN_GAP if c.kind == TRANSPORT else 0.0      # (a train's cars string out behind its lead)
		if Vector2(c.x - px, c.y - py).length_squared() > (reach + trail) * (reach + trail):
			continue
		var vx := c.hx * c.v
		var vy := c.hy * c.v
		var units := TRAIN if c.kind == TRANSPORT else 1
		var half := (4.5 if c.kind == TRANSPORT else (4.0 if c.kind == SLOW else 3.5)) * SCALE
		var radius := (4.2 if c.kind == TRANSPORT else (3.2 if c.kind == SLOW else 2.6)) * SCALE
		var lead_height := _drawing.height(c.road, c.f)
		var shaft_on: bool = world.shaft.on(c.road, c.f)
		for q in 2 * units:
			var center_back := (q >> 1) * TRAIN_GAP
			var back := center_back + (half if q % 2 == 0 else -half)
			var x: float = c.x - c.hx * back
			var y: float = c.y - c.hy * back
			var h := lead_height
			# A level road's train is rigid at the lead's height. A shaft carries each car at its
			# own sample: project the collision footprint to that same sample in the flat sim. On a
			# graded road each part stands at its own height, as it is drawn (below).
			if shaft_on:
				var f: float = c.f - c.dir * center_back / 24.0
				var R := sim.roads[c.road]
				var i := clampi(int(f), 0, R.N - 2)
				var t := clampf(f - i, 0.0, 1.0)
				var tangent := Vector2(lerpf(R.tx[i], R.tx[i + 1], t), lerpf(R.ty[i], R.ty[i + 1], t)).normalized()
				x = R.px[i] + R.tx[i] * R.len[i] * t - tangent.y * c.lat - tangent.x * c.dir * (back - center_back)
				y = R.py[i] + R.ty[i] * R.len[i] * t + tangent.x * c.lat - tangent.y * c.dir * (back - center_back)
				h = _drawing.height(c.road, f)
			elif grade and sim._net_h.has(c.road):
				h = _drawing.height(c.road, clampf(c.f - c.dir * back / 24.0, 0.0, sim.roads[c.road].N - 1.0))
			if sim.roads[c.road].banked:      # (on a banked bend it stands on the deck as it leans there, as it is drawn)
				var road_banked = sim.roads[c.road]
				var fb := clampf(c.f - c.dir * back / 24.0, 0.0, road_banked.N - 1.0)
				var ib := clampi(int(fb), 0, road_banked.N - 2)
				h += Simulation.net_bank_lift(road_banked, ib, fb - ib, c.lat)
			if Vector2(x - px, y - py).length_squared() > reach * reach:      # (the far cars of a near train)
				continue
			obs.append({"id": c.id * 32 + q, "r": radius, "x": x, "y": y,
				"vx": vx, "vy": vy, "zMin": h, "zMax": h + (9.6 if c.kind == TRANSPORT else 6.0)})
	sim.obstacles = obs


## The vehicles on the map: [[x, y, kind], ...] within r of (x, y).
func marks(x: float, y: float, r: float) -> Array:
	var out := []
	for c in cars:
		if absf(c.x - x) < r and absf(c.y - y) < r:
			out.append([c.x, c.y, c.kind])
	return out
