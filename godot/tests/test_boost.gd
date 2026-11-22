## The boost and the consumables, in the sim (Luke, 2026-11-22: "Holding the ramjet arm button
## should give an extra boost", "bring back heat and energy as optional consumables"):
##   not asked for, nothing changes (a flight with no boost keys is the flight with them false,
##   to the last bit); a stage is thrust times 1.3, two are 1.69; thirty seconds at full lever
##   end 14% faster; with the limits on a held boost spends the battery in five seconds and is
##   then dead until it is let go, heats the engines, and a surge is free; the limits switched
##   where the craft is (set_limits) leave a whole, cool craft either way.
## The figures are sim-core.js's (node tools/boost_test.js sim-core.js): the two sims agree.
## --headless -s res://tests/test_boost.gd      Prints BOOST PASS.
extends SceneTree

const S := preload("res://sim/craft_sim.gd")
const DT := 1.0 / 480.0
const MPH := 2.236936
# tools/boost_test.js, 2026-11-22
const JS := {"plain_x": -20761.764256, "thrust_none": 0.988636, "thrust_held": 1.285227, "thrust_both": 1.670795,
	"mph30_plain": 4441.752804, "mph30_held": 5069.179265, "mph30_late": 5023.768287,
	"battery_2s": 0.6, "heat_2s": 0.253951, "heat_2s_plain": 0.075844}
var fails := 0
var checks := 0


func _check(label: String, ok: bool) -> void:
	checks += 1
	print(("PASS " if ok else "FAIL ") + label)
	fails += int(not ok)


func _fresh(extra := {}) -> S:
	var o := {"track": "range", "startY": -3000.0}
	o.merge(extra, true)
	return S.new(o)


static func _inp(o := {}) -> Dictionary:
	var d := {"thrL": 0.0, "thrR": 0.0, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": true}
	d.merge(o, true)
	return d


func _run(sim: S, inp: Dictionary, secs: float) -> void:
	for k in int(round(secs / DT)):
		sim.step(inp, DT)
		sim.events.clear()


static func _mph(sim: S) -> float:
	return sqrt(sim.pod.vx * sim.pod.vx + sim.pod.vy * sim.pod.vy) * MPH


func _initialize() -> void:
	# 1. not asked for, nothing changes
	var a := _fresh()
	var b := _fresh()
	_run(a, _inp({"thrL": 0.87, "thrR": 0.6}), 20.0)
	_run(b, _inp({"thrL": 0.87, "thrR": 0.6, "boost": false, "surge": false}), 20.0)
	_check("a flight with no boost keys and the same flight with them false end in the same place, to the bit (x %.6f; sim-core.js %.6f)" % [a.pod.x, JS.plain_x],
		a.pod.x == b.pod.x and a.pod.y == b.pod.y and a.pod.vx == b.pod.vx and a.eL.th == b.eL.th and absf(a.pod.x - JS.plain_x) < 0.01)
	# 2. the thrust a stage
	var thrust := {}
	var stages := {}
	for row in [["none", {}], ["held", {"boost": true}], ["surge", {"surge": true}], ["both", {"boost": true, "surge": true}]]:
		var sim := _fresh()
		var o := {"thrL": 0.87, "thrR": 0.87}
		o.merge(row[1])
		sim.step(_inp(o), DT)
		thrust[row[0]] = sim.eL.thrust
		stages[row[0]] = sim.boost
	_check("full lever: thrust %.4f of the scale; the boost held %.4f, a surge %.4f, both %.4f: times %.2f a stage (sim-core.js %.4f, %.4f, %.4f)" % [
		thrust.none, thrust.held, thrust.surge, thrust.both, S.DEFAULTS.boostMult, JS.thrust_none, JS.thrust_held, JS.thrust_both],
		absf(thrust.none - JS.thrust_none) < 1e-5 and absf(thrust.held - JS.thrust_held) < 1e-5 and thrust.surge == thrust.held
		and absf(thrust.both - JS.thrust_both) < 1e-5 and stages == {"none": 0, "held": 1, "surge": 1, "both": 2}
		and absf(thrust.held / thrust.none - 1.3) < 1e-6 and absf(thrust.both / thrust.none - 1.69) < 1e-6)
	# 3. thirty seconds at full lever
	var mph := {}
	for row in [["plain", 1e9], ["held", 0.0], ["late", 20.0]]:
		var sim := _fresh()
		for k in int(round(30.0 / DT)):
			var o := {"thrL": 0.87, "thrR": 0.87}
			if float(k) * DT >= float(row[1]):
				o["boost"] = true
			sim.step(_inp(o), DT)
			sim.events.clear()
		mph[row[0]] = _mph(sim)
	_check("thirty seconds at full lever: %.0f mph; with the boost held throughout %.0f (%.0f%% more), held for the last ten %.0f (sim-core.js %.0f, %.0f, %.0f)" % [
		mph.plain, mph.held, (mph.held / mph.plain - 1.0) * 100.0, mph.late, JS.mph30_plain, JS.mph30_held, JS.mph30_late],
		absf(mph.plain - JS.mph30_plain) < 0.5 and absf(mph.held - JS.mph30_held) < 0.5 and absf(mph.late - JS.mph30_late) < 0.5 and mph.held > 1.1 * mph.plain)
	# 4. the consumables
	var c := _fresh({"limits": true})
	var held := _inp({"thrL": 0.87, "thrR": 0.87, "boost": true})
	_run(c, held, 2.0)
	var plain := _fresh({"limits": true})
	_run(plain, _inp({"thrL": 0.87, "thrR": 0.87}), 2.0)
	_check("the limits on, two seconds of held boost: the battery at %.3f (it spends %.2f a second: five seconds from full), the engines at %.3f of their heat against %.3f without it (sim-core.js %.3f, %.3f, %.3f)" % [
		c.battery, S.DEFAULTS.boostDrain, c.eL.heat, plain.eL.heat, JS.battery_2s, JS.heat_2s, JS.heat_2s_plain],
		absf(c.battery - JS.battery_2s) < 1e-4 and absf(c.eL.heat - JS.heat_2s) < 1e-4 and absf(plain.eL.heat - JS.heat_2s_plain) < 1e-4 and c.eL.heat > plain.eL.heat + 0.1)
	_run(c, held, 8.0)
	var flat_stages: int = c.boost
	var flat_thrust: float = c.eL.thrust
	c.step(_inp({"thrL": 0.87, "thrR": 0.87, "boost": true, "surge": true}), DT)
	var flat_surge: int = c.boost
	_check("ten seconds of it: the battery flat (%.3f), the boost dead while it is still held (%d stages, thrust %.4f), a power-up's surge still given (%d)" % [c.battery, flat_stages, flat_thrust, flat_surge],
		c.battery == 0.0 and flat_stages == 0 and absf(flat_thrust - JS.thrust_none) < 1e-5 and flat_surge == 1)
	_run(c, _inp({"thrL": 0.87, "thrR": 0.87}), 4.0)
	c.step(held, DT)
	_check("let go for four seconds the battery has charge again (%.3f) and the boost lights" % c.battery, c.battery > 0.15 and c.boost == 1)
	var off := _fresh()
	_run(off, held, 10.0)
	_check("the limits off (as flown): ten seconds of held boost and the battery is full (%.2f), the engines cold (%.2f), the boost still burning (%d)" % [off.battery, off.eL.heat, off.boost],
		off.battery == 1.0 and off.eL.heat == 0.0 and off.boost == 1)
	# 5. the limits switched where the craft is
	var live := _fresh()
	_run(live, _inp({"thrL": 0.87, "thrR": 0.87}), 3.0)
	live.set_limits(true)
	var on_heat: float = live.eL.heat
	live.armed = true
	var ram := _inp({"thrL": 1.0, "thrR": 1.0, "boost": true})
	var t_out := -1.0
	for k in int(round(12.0 / DT)):
		live.step(ram, DT)
		if t_out < 0.0 and live.eL.flameout:
			t_out = float(k) * DT
	var flamed: bool = live.eL.flameout
	live.set_handling("starfighter")
	var kept: bool = live.P.limits
	live.set_limits(false)
	_check("switched on in flight the engines start at their resting heat (%.2f); the ramjet and the boost together flame them out in %.1f s; a handling switch keeps the limits (%s); switched off, the engines are alight and cold again and the battery full" % [on_heat, t_out, kept],
		on_heat == 0.3 and (flamed or t_out > 0.0) and t_out > 1.0 and t_out < 6.0 and kept and not live.P.limits and not live.eL.flameout and live.eL.heat == 0.0 and live.battery == 1.0)
	print("BOOST %s (%d checks, %d failures)" % ["PASS" if fails == 0 else "FAIL", checks, fails])
	quit(0 if fails == 0 else 1)
