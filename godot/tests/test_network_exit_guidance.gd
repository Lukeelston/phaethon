## Real ordinary interchange branches: both sides, travel directions, passed exits and ETA.
extends SceneTree
const Sim := preload("res://sim/craft_sim.gd")
const View := preload("res://view/craft_view.gd")
var checks := 0
var failures := 0

func check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
		print("FAIL ", label)

func place(sim, road: int, sample: int, direction: int, mph: float) -> void:
	sim.respawn_on(road, sample, direction)
	var R = sim.roads[road]
	for body in sim.bodies:
		body.vx = R.tx[sample] * direction * mph / 2.236936
		body.vy = R.ty[sample] * direction * mph / 2.236936

func _initialize() -> void:
	var sim = Sim.new({"track": "network"})
	var view = View.new()
	view.sim = sim
	# Isolate each real entrance to prove the chosen branch cannot inherit a hard-coded RIGHT.
	# Jumps are absent at this corner; disabling them also makes nearest-exit tests independent.
	sim.jumps = []
	for fixture in [["R00WS", "E1", 1, "RIGHT", "N1 UPPER"], ["R00WN", "E1", 1, "LEFT", "N1 UPPER"], ["R00ES", "E1", -1, "LEFT", "N1 UPPER"], ["R00EN", "E1", -1, "RIGHT", "N1 UPPER"], ["R00WS", "N1", 1, "LEFT", "E1 LOWER"], ["R00ES", "N1", 1, "RIGHT", "E1 LOWER"]]:
		var branch := -1
		var highway := -1
		for r in sim.roads.size():
			if sim.roads[r].name == fixture[0]: branch = r
			if sim.roads[r].name == fixture[1]: highway = r
		var junction_index := -1
		for ji in sim.roads[branch].jx:
			if int(sim.junctions[ji][0]) == highway: junction_index = ji
		var J: Array = sim.junctions[junction_index]
		var end: int = 0 if int(J[4]) == 0 else sim.roads[branch].N - 1
		# Exhaustive physical nearest point, independent of the padded junction-to-parent map.
		var H = sim.roads[highway]
		var R = sim.roads[branch]
		var mouth := -1
		var nearest := INF
		for i in H.N:
			var dx: float = H.px[i] - R.px[end]
			var dy: float = H.py[i] - R.py[end]
			var d := dx * dx + dy * dy
			if d < nearest:
				nearest = d
				mouth = i
		var original: Array = sim.roads[highway].jx.duplicate()
		sim.roads[highway].jx = [junction_index]
		var way := int(fixture[2])
		place(sim, highway, mouth - way * 2000, way, 12000.0)
		var text: String = view._net_jump_approach_text()
		check("%s from %s gives early %s exit" % [fixture[0], fixture[1], fixture[3]], text.begins_with(fixture[3] + " EXIT") and text.split("\n")[0].contains(" S"))
		check("%s names connected destination level" % fixture[0], text.contains(fixture[4]) and not text.contains("ASCENT"))
		check("ordinary exit never invents a jump minimum", not text.contains("MIN ") and not text.contains("READY"))
		place(sim, highway, mouth - way * 84, way, 0.0)
		text = view._net_jump_approach_text()
		check("stopped approach keeps direction without inventing ETA", text.contains("-- S") and not text.contains("INF") and not text.contains("NAN"))
		place(sim, highway, mouth - way * 2, way, 4000.0)
		text = view._net_jump_approach_text()
		check("ordinary entrance remains visible just before its physical mouth", text.begins_with(fixture[3] + " EXIT") and text.contains(fixture[4]))
		place(sim, highway, mouth + way * 2, way, 4000.0)
		check("passed ordinary entrance hides", view._net_jump_approach_text().is_empty())
		place(sim, highway, mouth - way * 84, -way, 4000.0)
		check("wrong-direction ordinary branch is not offered", view._net_jump_approach_text().is_empty())
		sim.roads[highway].jx = original
	# Two successive exits on the same highway; list the farther one first deliberately.
	var near_junction := -1
	var far_junction := -1
	for ji in sim.roads[0].jx:
		var child: String = sim.roads[int(sim.junctions[ji][3])].name
		if child == "R00WS": near_junction = ji
		if child == "R10WS": far_junction = ji
	sim.roads[0].jx = [far_junction, near_junction]
	place(sim, 0, 2000, 1, 60000.0)
	check("nearest ordinary exit wins over junction list order", view._net_jump_approach_text().contains("N1 UPPER"))
	view.free()
	print("EXIT GUIDANCE %s (%d checks, %d failures)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(int(failures > 0))
