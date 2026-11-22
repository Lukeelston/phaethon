## Power-ups (view/power_ups.gd; Luke, 2026-11-22: "I also think we need power-ups in some way"):
## where the gates stand (the Network's open road only, clear of ends, junctions, towns, slopes,
## shafts, deck roads, the Aurora Line and the jumps; Eridanus's open straights), that flying
## through one inside its span takes it and outside it does not, what it gives (a surge the sims
## see as inp.surge; with the consumables on, charge or cooling by its colour), that a taken gate
## is gone for a while, and that a bare view, a cruise and a replay have none.
## --headless --xr-mode off --audio-driver Dummy -s res://tests/test_power_ups.gd -- --mute
## Prints POWER UPS PASS.
extends SceneTree

const View := preload("res://view/craft_view.gd")
const Sim := preload("res://sim/craft_sim.gd")
const PowerUps := preload("res://view/power_ups.gd")
var failures := 0
var checks := 0


func _initialize() -> void:
	View.track_override = "network"
	View.job_override = "none"
	View.best_dir = OS.get_user_data_dir().path_join("test_power_ups_")
	_run.call_deferred()


func _check(label: String, passed: bool) -> void:
	checks += 1
	print(("PASS " if passed else "FAIL ") + label)
	failures += int(not passed)


## The pod set down on road r at fractional sample f, `lat` m left of the centreline, and the view's origin on it.
func _put(v, r: int, f: float, lat: float) -> void:
	var R = v.sim.roads[r]
	var i := int(floor(f))
	var t := f - float(i)
	v.sim.pod.x = R.px[i] + R.tx[i] * R.len[i] * t + R.nx[i] * lat
	v.sim.pod.y = R.py[i] + R.ty[i] * R.len[i] * t + R.ny[i] * lat
	v.sim.pod.hint = i
	v.sim.pod.path = r
	v.sim.pod.off_road = false
	v.org_x = v.sim.pod.x
	v.org_y = v.sim.pod.y


## Fly the pod through gate g's line at `lat`, half a sample a frame. -> gates taken on the way.
func _through(v, g: Dictionary, lat: float, back := false) -> int:
	var before: int = v.power_ups.took
	for k in 13:
		var f := float(g.i) + (float(k) - 6.0) * 0.5 * (-1.0 if back else 1.0)
		_put(v, int(g.road), f, lat)
		v.power_ups.sync()
	return int(v.power_ups.took) - before


func _places(sim) -> Dictionary:
	var step: float = Sim.NET_STEP
	var total := 0
	var roads_with := 0
	var wrong := []
	var closest := INF
	for r in sim.roads.size():
		var R = sim.roads[r]
		var gates: Array = PowerUps.network_gates(sim, r)
		total += gates.size()
		roads_with += int(not gates.is_empty())
		var last := -1
		for g in gates:
			var i: int = g.i
			var why := ""
			if R.shaft or R.deck or R.role != "" or r == int(Sim.NET_PRESSURE[0]):
				why = "a road that has none"
			elif R.mode[i] != 1:
				why = "in a town"
			elif float(i) * step < PowerUps.END_CLEAR - step or float(R.N - 1 - i) * step < PowerUps.END_CLEAR - step:
				why = "near the road's end"
			elif absf(sim.net_height(r, float(i + 2)) - sim.net_height(r, float(i - 2))) / (4.0 * step) > PowerUps.MAX_GRADE:
				why = "on a slope"
			elif absf(float(g.lat)) + float(g.hw) > float(R.w[i]) / 2.0 - Sim.net_edge_span(R.w[i]):
				why = "over the edge's ramp"
			for j in R.jx:      # its junctions' samples, found again here
				var J: Array = sim.junctions[j]
				for side in [0, 3]:
					if int(J[side]) == r and i >= mini(int(J[side + 1]), int(J[side + 2])) - int(PowerUps.JUNCTION_CLEAR / step) + 1 \
							and i <= maxi(int(J[side + 1]), int(J[side + 2])) + int(PowerUps.JUNCTION_CLEAR / step) - 1:
						why = "at a junction"
			if last >= 0:
				closest = minf(closest, float(i - last) * step)
			last = i
			if why != "":
				wrong.append("%s@%d %s" % [R.name, i, why])
	return {"total": total, "roads": roads_with, "wrong": wrong, "closest": closest}


func _run() -> void:
	View.power_ups_on = false
	var v = View.new()
	root.add_child(v)
	await process_frame
	v.set_process(false)
	_check("a bare view has no power-ups", v.power_ups == null and v.surge == 0.0)
	v.cruise = 0.5
	v.set_power_ups(true)
	var cruising: bool = v.power_ups == null
	v.cruise = -1.0
	v.replay = [[0.0, 0.0, 0.0, 0.0]]
	v.set_power_ups(true)
	var replaying: bool = v.power_ups == null
	v.replay = []
	_check("asked for on a cruise or a replay there are still none", cruising and replaying)
	v.set_power_ups(true)
	_check("asked for by a pilot, they are built: %d gates in the pool, none drawn yet" % v.power_ups._slots.size(), v.power_ups != null and v.power_ups._slots.size() == PowerUps.POOL)
	# where they stand
	var sim = v.sim
	var P := _places(sim)
	_check("the Network: %d gates on %d of its %d roads, never under %.0f km apart on a road; wrongly placed: %s" % [P.total, P.roads, sim.roads.size(), P.closest / 1000.0, P.wrong],
		P.total >= 30 and P.roads >= 5 and P.wrong.is_empty() and P.closest >= PowerUps.SPACING - Sim.NET_STEP)
	var eri = Sim.new({"track": "eridanus"})
	var E: Array = PowerUps.course_gates(eri)
	var e_ok := true
	var e_at := []
	for g in E:
		e_ok = e_ok and eri.tw[g.i] >= 300.0 and (eri.tb.is_empty() or absf(eri.tb[g.i]) <= 0.005) and absf(float(g.lat)) + float(g.hw) < eri.tw[g.i] / 2.0
		e_at.append(int(g.i))
	_check("Eridanus (%.0f km round): %d gates, each on a straight, level, open stretch (samples %s of %d)" % [eri.track_length / 1000.0, E.size(), e_at, eri.N],
		E.size() >= 3 and E.size() <= 8 and e_ok)
	_check("the range and the grand prix have none", PowerUps.course_gates(Sim.new({"track": "gp"})).is_empty() and PowerUps.network_gates(Sim.new({"track": "range"}), 0).is_empty())
	# a road with gates, and its second one
	var road := -1
	for r in sim.roads.size():
		if road < 0 and PowerUps.network_gates(sim, r).size() >= 4:
			road = r
	var gates: Array = PowerUps.network_gates(sim, road)
	var g: Dictionary = gates[1]
	_put(v, road, float(g.i) - 60.0, float(g.lat))
	v.power_ups.sync()
	var at: Transform3D = (v.power_ups._slots[0].node as Node3D).transform
	for slot in v.power_ups._slots:
		if slot.key == PowerUps.key_of(g):
			at = (slot.node as Node3D).transform
	var R = sim.roads[road]
	var ahead := Vector3(R.tx[g.i], 0.0, -R.ty[g.i])
	_check("60 samples short of %s's second gate (%.0f m wide there, the gate %.0f m across in its lane %.0f m left of the middle): it is drawn, %.0f m ahead on the road, square across it (%d drawn)" % [
		R.name, R.w[g.i], 2.0 * float(g.hw), float(g.lat), at.origin.length(), v.power_ups.drawn()],
		v.power_ups.drawn() >= 1 and absf(at.origin.length() - 60.0 * Sim.NET_STEP) < 2.0 * Sim.NET_STEP and absf(at.basis.z.normalized().dot(ahead)) > 0.999
		and absf(at.origin.y - sim.net_height(road, float(g.i))) < 0.01)
	# through it
	v.sim.set_limits(false)
	var missed := _through(v, g, float(g.lat) + float(g.hw) + PowerUps.CATCH + 4.0)
	_check("flown past %.0f m outside its post: not taken" % (PowerUps.CATCH + 4.0), missed == 0 and v.surge == 0.0)
	var got := _through(v, g, float(g.lat) + float(g.hw) - 1.0)
	_check("flown through a metre inside its post: taken, a surge of %.0f s begun, the line on the dash \"%s\"" % [v.surge, v.flash_msg],
		got == 1 and v.surge == PowerUps.SURGE_S and v.flash_msg == "SURGE")
	var gone := true
	for slot in v.power_ups._slots:
		gone = gone and slot.key != PowerUps.key_of(g)
	var again := _through(v, g, float(g.lat), true)
	_check("it is gone (not drawn), and flown back through at once gives nothing", gone and again == 0)
	v.sim.time += PowerUps.REARM_S + 1.0
	var later := _through(v, g, float(g.lat), true)
	_check("%.0f s later it is back, and taken from the other side" % PowerUps.REARM_S, later == 1)
	# the surge in the sim
	v.inp = {"thrL": 0.87, "thrR": 0.87, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": true}
	v.surge = PowerUps.SURGE_S
	v._sim_step()
	var lit: int = v.sim.boost
	var steps := 0
	while v.sim.boost > 0 and steps < 5000:
		v._sim_step()
		steps += 1
	_check("the surge is the sims' inp.surge: a stage of boost (\"%s\") for %.2f s, then gone from the input" % ["BOOST" if lit == 1 else str(lit), float(steps + 1) / 480.0],
		lit == 1 and absf(float(steps + 1) / 480.0 - PowerUps.SURGE_S) < 0.01 and not v.inp.has("surge"))
	# the consumables: the colours, and what each gives
	var kinds := []
	for k in 4:
		kinds.append(PowerUps.kind_of(k, true))
	_check("with heat and energy off every gate is the plain surge; on, along a road they run %s" % [kinds],
		PowerUps.kind_of(1, false) == "boost" and PowerUps.kind_of(3, false) == "boost" and kinds == ["boost", "energy", "boost", "coolant"])
	v.sim.set_limits(true)
	v.sim.battery = 0.2
	v.sim.time += PowerUps.REARM_S + 1.0
	var energy := _through(v, g, float(g.lat))            # the road's second gate: k 1, the cyan one
	var charged: float = v.sim.battery
	v.sim.eL.heat = 0.9
	v.sim.eR.heat = 0.7
	var cool := _through(v, gates[3], float(gates[3].lat))   # its fourth: the white one
	_check("heat and energy on: the cyan gate takes a battery at 20%% to %.0f%% (\"%s\" was its line), the white one engines at 0.90 and 0.70 to %.2f and %.2f" % [charged * 100.0, "SURGE  /  ENERGY +50%", v.sim.eL.heat, v.sim.eR.heat],
		energy == 1 and absf(charged - 0.7) < 1e-6 and cool == 1 and absf(v.sim.eL.heat - 0.4) < 1e-6 and absf(v.sim.eR.heat - 0.2) < 1e-6 and v.flash_msg == "SURGE  /  ENGINES COOLED")
	# off the roads, and switched off
	v.sim.pod.off_road = true
	v.power_ups.sync()
	_check("off the roads nothing is drawn", v.power_ups.drawn() == 0)
	v.set_power_ups(false)
	await process_frame
	_check("switched off: the gates gone, any surge with them", v.power_ups == null and v.surge == 0.0 and not View.power_ups_on)
	v.queue_free()
	await process_frame
	# Eridanus, flown: its first gate drawn on the road and taken
	View.track_override = "eridanus"
	View.power_ups_on = true
	var e = View.new()
	root.add_child(e)
	await process_frame
	e.set_process(false)
	var es = e.sim
	var eg: Array = e.power_ups.gates_on(0) if e.power_ups != null else []
	var took := 0
	var shown := 0
	var off_road := INF
	if not eg.is_empty():
		var g0: Dictionary = eg[0]
		for k in 13:
			var i: int = int(g0.i) + (k - 6) / 2
			var t := 0.5 * float(posmod(k - 6, 2))
			es.pod.x = es.tpx[i] + es.ttx[i] * es.tlen[i] * t + es.tnx[i] * float(g0.lat)
			es.pod.y = es.tpy[i] + es.tty[i] * es.tlen[i] * t + es.tny[i] * float(g0.lat)
			es.pod.hint = i
			es.pod.path = 0
			e.org_x = es.pod.x
			e.org_y = es.pod.y
			e.power_ups.sync()
			if k == 0:
				shown = e.power_ups.drawn()
				for slot in e.power_ups._slots:
					if slot.key == PowerUps.key_of(g0):
						off_road = absf((slot.node as Node3D).transform.origin.y - es.surface_at(es.pod.x, es.pod.y, int(g0.i), 0).x)
		took = e.power_ups.took
	_check("Eridanus in a view (%s, %s): %d gates, the first drawn on the road's surface (%d drawn, %.3f m off it) and taken flying through (%d), a surge begun (%.0f s)" % [es.track_name, es.kind, eg.size(), shown, off_road, took, e.surge],
		es.track_name == "eridanus" and eg.size() >= 3 and shown >= 1 and off_road < 0.01 and took == 1 and e.surge == PowerUps.SURGE_S)
	e.queue_free()
	await process_frame
	print("POWER UPS %s (%d checks, %d failures)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)
