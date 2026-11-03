## Approach guidance follows the real highway -> exit ramp -> launch fork for all twenty ascents.
extends SceneTree
const Sim := preload("res://sim/craft_sim.gd")
const View := preload("res://view/craft_view.gd")
var checks := 0
var failures := 0

func check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", label)

func place(sim, road: int, sample: int, direction: int, mph: float) -> void:
	sim.respawn_on(road, sample, direction)
	var R = sim.roads[road]
	for body in sim.bodies:
		body.vx = R.tx[sample] * direction * mph / 2.236936
		body.vy = R.ty[sample] * direction * mph / 2.236936

## Independent oracle: find the physical endpoint using every parent point, not junction padding.
func physical_parent_sample(sim, J: Array, child: int) -> int:
	var P = sim.roads[int(J[0])]
	var C = sim.roads[int(J[3])]
	var closest := -1
	var distance := INF
	for i in P.N:
		var dx: float = P.px[i] - C.px[child]
		var dy: float = P.py[i] - C.py[child]
		var d := dx * dx + dy * dy
		if d < distance:
			distance = d
			closest = i
	return closest

func _initialize() -> void:
	var sim = Sim.new({"track": "network"})
	var view = View.new()
	view.sim = sim
	for jump in sim.jumps:
		var lane := int(jump[0])
		var L = sim.roads[lane]
		var title := "ASCENT %s " % L.name
		var fork: Array = []
		for ji in L.jx:
			var J: Array = sim.junctions[ji]
			if int(J[3]) == lane and int(J[4]) == 0:
				fork = J
		check("%s has a ramp fork" % L.name, not fork.is_empty())
		if fork.is_empty(): continue
		var ramp := int(fork[0])
		var R = sim.roads[ramp]
		var direction := int(fork[6])
		var fork_sample := physical_parent_sample(sim, fork, 0)
		var entry_sample: int = 0 if direction > 0 else R.N - 1
		var highway: Array = []
		for ji in R.jx:
			var J: Array = sim.junctions[ji]
			if int(J[3]) == ramp and int(J[4]) <= entry_sample and entry_sample <= int(J[5]):
				highway = J
		check("%s ramp has a highway entrance" % L.name, not highway.is_empty())
		if highway.is_empty(): continue
		var h := int(highway[0])
		var way := direction * int(highway[6])
		var before := physical_parent_sample(sim, highway, entry_sample) - way * 84
		place(sim, h, before, way, float(jump[2]) - 100.0)
		var text: String = view._net_jump_approach_text()
		check("%s highway exit warns before entering ramp: %s" % [L.name, text], text.contains(title) and text.contains("RIGHT EXIT") and text.contains("TOO SLOW"))
		check("%s highway action leads with direction and time" % L.name, text.begins_with("RIGHT EXIT") and text.split("\n")[0].contains(" S"))
		var mouth := physical_parent_sample(sim, highway, entry_sample)
		place(sim, h, mouth - way * 2000, way, 12000.0)
		text = view._net_jump_approach_text()
		check("%s fast approach gives at least eight seconds to prepare" % L.name, text.contains(title) and text.contains("RIGHT EXIT") and text.contains("KEEP RIGHT"))
		place(sim, h, mouth - way * 2, way, 12000.0)
		text = view._net_jump_approach_text()
		check("%s stays visible 48 m before physical highway mouth" % L.name, text.contains(title) and text.begins_with("RIGHT EXIT"))
		place(sim, h, mouth + way * 2, way, 12000.0)
		check("%s passed entrance stops directing to that jump" % L.name, not view._net_jump_approach_text().contains(title))
		place(sim, ramp, fork_sample - direction * 7, direction, float(jump[2]) + 100.0)
		text = view._net_jump_approach_text()
		check("%s ramp fork says straight, not right: %s" % [L.name, text], text.contains(title) and text.begins_with("JUMP STRAIGHT") and text.contains("READY") and not text.contains("RIGHT"))
		place(sim, ramp, fork_sample - direction * 2, direction, 4000.0)
		text = view._net_jump_approach_text()
		check("%s stays visible 48 m before physical straight fork" % L.name, text.contains(title) and text.begins_with("JUMP STRAIGHT"))
		place(sim, ramp, fork_sample + direction * 2, direction, 4000.0)
		check("%s hides after physical straight fork" % L.name, not view._net_jump_approach_text().contains(title))
		place(sim, lane, int(L.N / 2), 1, float(jump[2]) + 100.0)
		text = view._net_jump_approach_text()
		check("%s launch shows lip and varied minimum" % L.name, text.contains(title) and text.begins_with("JUMP LIP") and text.contains("MIN %d,%03d MPH" % [int(jump[2]) / 1000, int(jump[2]) % 1000]))
		var catch_road = sim.roads[int(jump[1])]
		for ji in catch_road.jx:
			var J: Array = sim.junctions[ji]
			if int(J[3]) == int(jump[1]) and int(J[5]) == catch_road.N - 1:
				var destination := int(J[0])
				var level := "UPPER" if sim.net_height(destination, physical_parent_sample(sim, J, catch_road.N - 1)) >= 300.0 else "LOWER"
				check("%s names actual catch destination and level" % L.name, text.contains("%s %s" % [sim.roads[destination].name, level]))
		place(sim, lane, int(L.N / 2), -1, 4000.0)
		text = view._net_jump_approach_text()
		check("%s reverse launch is a wrong-way warning, never READY" % L.name, text.contains("WRONG WAY") and not text.contains("READY"))
		place(sim, h, before, -way, float(jump[2]))
		check("%s reverse approach never names that wrong-way spur" % L.name, not view._net_jump_approach_text().contains(title))
	view.free()
	print("JUMP APPROACH %s (%d checks, %d failures)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(int(failures > 0))
