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

func parent_sample(J: Array, child: int) -> int:
	var u := float(child - int(J[4])) / maxf(1.0, float(int(J[5]) - int(J[4])))
	return roundi(lerpf(float(J[1]), float(J[2]), u if int(J[6]) > 0 else 1.0 - u))

func _initialize() -> void:
	var sim = Sim.new({"track": "network"})
	var view = View.new()
	view.sim = sim
	for jump in sim.jumps:
		var lane := int(jump[0])
		var L = sim.roads[lane]
		var title := "ASCENT %s  " % L.name
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
		var fork_sample := parent_sample(fork, 0)
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
		var before := parent_sample(highway, entry_sample) - way * 84
		place(sim, h, before, way, float(jump[2]) - 100.0)
		var text: String = view._net_jump_approach_text()
		check("%s highway exit warns before entering ramp: %s" % [L.name, text], text.begins_with(title) and text.contains("RIGHT EXIT") and text.contains("TOO SLOW"))
		place(sim, ramp, fork_sample - direction * 7, direction, float(jump[2]) + 100.0)
		text = view._net_jump_approach_text()
		check("%s ramp fork says straight, not right: %s" % [L.name, text], text.begins_with(title) and text.contains("STRAIGHT") and text.contains("READY") and not text.contains("RIGHT"))
		place(sim, lane, int(L.N / 2), 1, float(jump[2]) + 100.0)
		text = view._net_jump_approach_text()
		check("%s launch shows lip and varied minimum" % L.name, text.begins_with(title) and text.contains("LIP") and text.contains("MIN %d,%03d MPH" % [int(jump[2]) / 1000, int(jump[2]) % 1000]))
		place(sim, h, before, -way, float(jump[2]))
		check("%s reverse approach never names that wrong-way spur" % L.name, not view._net_jump_approach_text().begins_with(title))
	view.free()
	print("JUMP APPROACH %s (%d checks, %d failures)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(int(failures > 0))
