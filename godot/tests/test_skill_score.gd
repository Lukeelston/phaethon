## Reward actual driving outcomes; reject ghost impacts, warps and steering noise.
extends SceneTree
const Sim := preload("res://sim/craft_sim.gd")
const Traffic := preload("res://view/network_traffic.gd")
var checks := 0
var failures := 0
var sim
var Score
var road := -1

func check(label: String, ok: bool) -> void:
	checks += 1
	failures += int(not ok)
	print(("PASS " if ok else "FAIL ") + label)

func fresh(path := ""):
	var score = Score.new()
	score.setup(sim, path)
	return score

func pose(distance: float, speed := 2000.0, heading_error := 0.0) -> void:
	var R = sim.roads[road]
	var f := 6000.0 + distance / 24.0
	var i := int(f)
	sim.respawn_on(road, i, 1)
	for b in sim.bodies:
		b.x += R.tx[i] * (f - i) * 24.0
		b.y += R.ty[i] * (f - i) * 24.0
		b.vx = speed * R.tx[i]
		b.vy = speed * R.ty[i]
		b.th += heading_error
	sim.pair_th = atan2(R.ty[i], R.tx[i]) + heading_error

func has_award(score, kind: String) -> bool:
	for event in score.feedback:
		if event.kind == kind:
			return true
	return false

func passing(lateral: float, height := 0.0, warp := false):
	pose(0.0)
	var score = fresh()
	var R = sim.roads[road]
	var c = Traffic.Car.new()
	c.id = 99
	c.road = road
	c.f = 6012.5
	c.hx = R.tx[6000]
	c.hy = R.ty[6000]
	c.x = sim.pod.x + c.hx * 300.0 + R.nx[6000] * lateral
	c.y = sim.pod.y + c.hy * 300.0 + R.ny[6000] * lateral
	var saved = sim._net_h.get(road, null)
	if height > 0:
		sim._net_h[road] = [[0, height, 0.0], [R.N - 1, height, 0.0]]
	for frame in 9:
		pose(frame * (600.0 if warp else 100.0))
		if height > 0:
			for b in sim.bodies:
				b.z = sim.P.rideH
		score.step(0.05)
		score.observe_traffic([c], 0.05)
	if saved == null:
		sim._net_h.erase(road)
	else:
		sim._net_h[road] = saved
	return score

func corners(noisy := false, wall := false):
	var original := road
	for r in sim.roads.size():
		if sim.roads[r].name == "K0":
			road = r
	var R = sim.roads[road]
	var start := 0
	for i in R.N:
		if absf(R.kap[i]) > 0.00001:
			start = i + 10
			break
	pose((start - 6000.0) * 24.0)
	var score = fresh()
	for f in 400:
		pose((start - 6000.0) * 24.0 + f * 100.0)
		if noisy:
			var angle: float = sim.pod.th + (0.04 if f % 2 else -0.04)
			for b in sim.bodies:
				b.vx = 2000.0 * cos(angle)
				b.vy = 2000.0 * sin(angle)
				b.th = angle
		if wall:
			for b in sim.bodies:
				b.contact = [true, false]
		score.step(0.05)
	road = original
	return score

func _initialize() -> void:
	if not FileAccess.file_exists("res://view/skill_score.gd"):
		check("skill rewards are available to the game", false)
		quit(1)
		return
	Score = load("res://view/skill_score.gd")
	sim = Sim.new({"track": "network"})
	for r in sim.roads.size():
		if sim.roads[r].name == "E2":
			road = r
	pose(0.0)
	var score = fresh()
	for f in 100:
		pose(f * 100.0)
		score.step(0.05)
	check("sustained useful speed earns points", score.total > 0)
	check("throttle alone cannot build a skill multiplier", score.multiplier == 1.0)
	var before: int = score.total
	score.step(0.0)
	check("zero elapsed time cannot earn points", score.total == before)
	var near_pass = passing(18.0)
	check("clean fast overtake earns a near miss", has_award(near_pass, "near"))
	var near_count := 0
	for event in near_pass.feedback:
		near_count += int(event.kind == "near")
	check("one passing car cannot award repeatedly", near_count == 1)
	check("actual overlap earns no near miss even with collisions off", not has_award(passing(0.0), "near"))
	check("ordinary distant traffic earns no near miss", not has_award(passing(70.0), "near"))
	check("another deck earns no near miss", not has_award(passing(18.0, 600.0), "near"))
	check("teleport across traffic earns no near miss", not has_award(passing(18.0, 0.0, true), "near"))
	check("real broad high-speed road bends earn precision", has_award(corners(), "turn"))
	check("alternating steering noise cannot farm turns", not has_award(corners(true), "turn"))
	check("wall riding cannot farm turns", not has_award(corners(false, true), "turn"))
	pose(0.0)
	score = fresh()
	for j in 4:
		score.on_event({"type": "airborne", "lip": true})
		for b in sim.bodies:
			b.off_road = true
		for f in 30:
			score.step(0.05)
		for b in sim.bodies:
			b.off_road = false
		score.on_event({"type": "catch"})
		for f in 20:
			score.step(0.05)
	check("controlled landings build a skill chain", has_award(score, "jump") and score.multiplier > 1.0)
	for f in 160:
		score.step(0.05)
	check("speed alone cannot keep an expired skill chain alive", score.multiplier == 1.0)
	for j in 3:
		score.on_event({"type": "airborne", "lip": true})
		for b in sim.bodies:
			b.off_road = true
		score.step(1.0)
		for b in sim.bodies:
			b.off_road = false
		score.on_event({"type": "catch"})
		score.step(0.5)
	check("new clean skills rebuild an expired chain", score.multiplier > 1.0)
	before = score.total
	score.on_event({"type": "bump"})
	check("impact breaks chain without deleting points", score.multiplier == 1.0 and score.total == before)
	for f in 100:
		score.step(0.05)
	check("inactivity leaves multiplier at one", score.multiplier == 1.0)
	var test_path := "user://v022_skill_test.json"
	if FileAccess.file_exists(test_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(test_path))
	score = fresh(test_path)
	for f in 30:
		pose(f * 100.0)
		score.step(0.05)
	before = score.total
	score.reset_run()
	check("restart clears current run but preserves best", score.total == 0 and score.best == before and before > 0)
	var loaded = fresh(test_path)
	check("best survives a new tracker", loaded.best == before)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(test_path))
	print("SKILL SCORE %s (%d checks, %d failures)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(int(failures > 0))
