## Speed guide gate (view/speed_guide.gd; Luke: "a series of variable lights that tell you how close
## you're gonna cut it. Green lights if approaching corner at safe speed, red if you're gonna blow
## past ... a 'proximity sensor' to the line of least wrecks"):
##   brakes   the guide's full-braking model stops within 8% of the sim itself: SPEEDCRAFT from
##            4,000 to 1,250 mph, STARFIGHTER from 1,200 to 400 mph, on Eridanus' long straight
##            (below 1,250 mph the guide counts on STARFIGHTER's drag: you flip as you slow)
##   the line safe speeds: 1,200 mph or less in the towns, the top on the loop's straights, the
##            sweepers in between
##   the cut  at the 8-mile board at 4,000 mph the town ahead is green, at the 4-mile board red, at
##            the 4-mile board at 2,000 mph green again; the colours run green, amber, red
##   honest   the autopilot's clean lap never needs more than full brakes for a town
## Prints SPEED GUIDE PASS.
## Run: Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_speed_guide.gd
extends SceneTree

const Sim := preload("res://sim/craft_sim.gd")
const Guide := preload("res://view/speed_guide.gd")
const CW := preload("res://view/course_world.gd")
const DT := 1.0 / 480.0
const MPH := 2.236936
const CHECKS := 6
var fails := 0
var passed := 0


func _initialize() -> void:
	# brakes: the model against the sim
	var res := []
	for c in [["speed", 4000.0, 1250.0], ["starfighter", 1200.0, 400.0]]:
		var sim = Sim.new({"track": "eridanus", "handling": c[0]})
		var g = Guide.new()
		g.setup(sim)
		var i := _straight(sim)
		_place(sim, i, c[1] / MPH)
		var b: Vector4 = g.brake_model()
		var want: float = g.stop_distance(c[1] / MPH, c[2] / MPH, b, g.brake_model("starfighter"))
		var d := 0.0
		var steps := 0
		while sqrt(sim.pod.vx * sim.pod.vx + sim.pod.vy * sim.pod.vy) > c[2] / MPH and steps < 480 * 60:
			sim.step({"thrL": 0.0, "thrR": 0.0, "brkL": 1.0, "brkR": 1.0, "repair": false, "reignite": true}, DT)
			sim.events.clear()
			d += sqrt(sim.pod.vx * sim.pod.vx + sim.pod.vy * sim.pod.vy) * DT
			steps += 1
		res.append([c[0], c[1], c[2], d, want])
	var ok := true
	var said := []
	for r in res:
		ok = ok and absf(r[4] - r[3]) / r[3] < 0.08
		said.append("%s %d->%d mph: sim %.2f mi, guide %.2f mi" % [r[0], r[1], r[2], r[3] / 1609.344, r[4] / 1609.344])
	_check("brakes: the guide's full-brake stop matches the sim (%s)" % "; ".join(said), ok)
	# the line
	var sim = Sim.new({"track": "eridanus"})
	var g = Guide.new()
	g.setup(sim)
	var town_max := 0.0
	var loop_top := 0.0
	var loop_min := INF
	for i in sim.N:
		if sim.tmode[i] == 0:
			town_max = maxf(town_max, g.vlim[i])
		elif sim.tmode[posmod(i - 10, sim.N)] == 1 and sim.tmode[(i + 10) % sim.N] == 1:   # the loop, clear of the towns' corners
			loop_top = maxf(loop_top, g.vlim[i])
			loop_min = minf(loop_min, g.vlim[i])
	_check("the line: towns at most %.0f mph, the loop's straights %.0f mph, its tightest sweeper %.0f mph; %d towns" % [
		town_max * MPH, loop_top * MPH, loop_min * MPH, g.mouths.size()],
		town_max * MPH <= 1200.5 and loop_top * MPH > 4299.0 and loop_min * MPH > 1500.0 and loop_min * MPH < 3500.0 and g.mouths.size() == 2)
	# the cut at the boards, flown in SPEEDCRAFT
	sim = Sim.new({"track": "eridanus", "handling": "speed"})
	g = Guide.new()
	g.setup(sim)
	var town: int = g.mouths[0]
	var q8 := _cut_at(sim, g, town, 8.0, 4000.0)
	var q4 := _cut_at(sim, g, town, 4.0, 4000.0)
	var q4s := _cut_at(sim, g, town, 4.0, 2000.0)
	_check("the cut for the town: at the 8-mile board at 4,000 mph %.2f (green), at the 4-mile board %.2f (red), there at 2,000 mph %.2f (green)" % [q8, q4, q4s],
		q8 < Guide.AMBER_AT and q4 > Guide.RED_AT and q4s < Guide.AMBER_AT)
	var cg: Color = Guide.color(0.2)
	var ca: Color = Guide.color(0.8)
	var cr: Color = Guide.color(1.2)
	_check("colours: green %s, amber %s, red %s" % [cg.to_html(false), ca.to_html(false), cr.to_html(false)],
		cg.g > 0.8 and cg.r < 0.3 and ca.r > 0.9 and ca.g > 0.5 and ca.b < 0.2 and cr.r > 0.9 and cr.g < 0.15)
	# honest: the autopilot's clean lap
	var inputs: Array = JSON.parse_string(FileAccess.get_file_as_string("res://tests/replay/eridanus_inputs.json"))
	var run = Sim.new({"track": "eridanus"})
	var gr = Guide.new()
	gr.setup(run)
	var worst := 0.0
	var ask := ["", "speed", "starfighter"]
	for u in inputs:
		var inp := {"thrL": u[0], "thrR": u[1], "brkL": u[2], "brkR": u[3], "repair": false, "reignite": true}
		if int(u[4]) > 0:
			inp["handling"] = ask[int(u[4])]
		for k in 8:
			run.step(inp, DT)
		run.events.clear()
		var v: float = sqrt(run.pod.vx * run.pod.vx + run.pod.vy * run.pod.vy)
		worst = maxf(worst, gr.town_cut(v, gr.brake_model(), gr.brake_model("starfighter")))
	_check("honest: the autopilot's clean lap never needs more than %.2f of full braking for a town" % worst, worst < Guide.RED_AT)
	# wired into the trackside: the boards' material and the lights' share the guide
	var code: String = FileAccess.get_file_as_string("res://view/guide.gdshaderinc")
	_check("the GPU's sums are the guide's (view/guide.gdshaderinc: three-piece stop, AMBER_AT %.1f, RED_AT %.1f)" % [Guide.AMBER_AT, Guide.RED_AT],
		code.contains("guide_stop") and code.contains("%.1f" % Guide.AMBER_AT) and code.contains("%.1f" % Guide.RED_AT)
		and FileAccess.get_file_as_string("res://view/beacon.gdshader").contains("guide.gdshaderinc")
		and FileAccess.get_file_as_string("res://view/pylon.gdshader").contains("guide.gdshaderinc")
		and FileAccess.get_file_as_string("res://view/board.gdshader").contains("guide.gdshaderinc"))
	var good: bool = fails == 0 and passed == CHECKS
	print("SPEED GUIDE ", "PASS" if good else "FAIL (%d failed, %d of %d passed)" % [fails, passed, CHECKS])
	quit(0 if good else 1)


## The start of Eridanus' longest straight (36 km, on the loop).
func _straight(sim) -> int:
	var best := 0
	var run := 0
	var start := 0
	for i in sim.N:
		var straight: bool = absf(sim.ttx[i] - sim.ttx[(i + 1) % sim.N]) + absf(sim.tty[i] - sim.tty[(i + 1) % sim.N]) < 1e-9
		if straight:
			run += 1
			if run > best:
				best = run
				start = i - run + 1
		else:
			run = 0
	return start + 10


## The whole craft at sample i, along the track at v m/s.
func _place(sim, i: int, v: float) -> void:
	sim.respawn(-1, i)
	for b in [sim.eL, sim.eR, sim.pod]:
		b.vx = sim.ttx[i] * v
		b.vy = sim.tty[i] * v
	sim.pod.hint = i


## The town's cut with the craft `miles` before its mouth at `mph`.
func _cut_at(sim, g, town: int, miles: float, mph: float) -> float:
	var i: int = town
	var d := 0.0
	while d < miles * 1609.344:
		i = posmod(i - 1, sim.N)
		d += sim.tlen[i]
	_place(sim, i, mph / MPH)
	return g.town_cut(mph / MPH, g.brake_model(), g.brake_model("starfighter"))


func _check(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if ok:
		passed += 1
	else:
		fails += 1
