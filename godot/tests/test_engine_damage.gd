## Engine damage gate. The GP failure Luke hit ("my left trigger isn't working right": weak or
## nothing): on the anticlockwise GP a sloppy line scrapes the outside wall, the right engine,
## which the left trigger drives; wall damage persisted, cost thrust and made the engine
## sputter, invisibly. Now the GP's walls deflect (TRACKS.gp in the sims): checks that a sloppy
## line mostly scrapes (feel it, don't pay for it) and keeps going; that a hard impact still
## damages; that a wrecked engine really is weak; that X (repair) heals it; and that Y (the
## view's restart) gives a fresh start on the grid with both engines whole.
## (The dash showing it: tests/test_dashboard.gd.)
## Run: Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_engine_damage.gd -- --track=gp --mute
extends SceneTree

const S := preload("res://sim/craft_sim.gd")
const ViewScript := preload("res://view/craft_view.gd")
const DT := 1.0 / 480.0
var fails := 0
var passed := 0
var v
var frames := 0


func _initialize() -> void:
	# 1. a sloppy pilot (runs wide) on the GP: who takes the hits?
	var sim = S.new({"track": "gp", "damage": true})
	var hits := {"L": 0, "R": 0, "pod": 0}
	var scrapes := {"L": 0, "R": 0, "pod": 0}
	for f in 60 * 72:
		var spd: float = sqrt(sim.pod.vx * sim.pod.vx + sim.pod.vy * sim.pod.vy)
		var ahead: int = (sim.pod.hint + int((60.0 + spd * 0.9) / 12.0)) % sim.N
		var err: float = S.wrap_angle(atan2(sim.tpy[ahead] - (sim.eL.y + sim.eR.y) / 2.0, sim.tpx[ahead] - (sim.eL.x + sim.eR.x) / 2.0) - sim.pair_th)
		var k := clampf(err * 4.0, -1.0, 1.0)
		var base := 0.87 if spd < 200.0 else 0.6
		var inp := {"thrL": base * (1.0 - maxf(0.0, k)), "thrR": base * (1.0 + minf(0.0, k)), "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": true}
		for s in 480 / 72:
			sim.step(inp, DT)
			for e in sim.events:
				if e.type == "hit":
					hits[e.who] += 1
				elif e.type == "scrape":
					scrapes[e.who] += 1
			sim.events.clear()
	var n_hits: int = hits.L + hits.R + hits.pod
	var n_scr: int = scrapes.L + scrapes.R + scrapes.pod
	var km: float = sim.pod.hint * sim.track_length / sim.N / 1000.0
	_check("a wild line on the GP mostly scrapes (%d scrapes, %d damaging hits), the outside (right) engine most, and keeps going: %.1f km, no wreck (pod %.2f), engines %.2f/%.2f" % [n_scr, n_hits, km, sim.pod.health, sim.eL.health, sim.eR.health],
		n_scr > 3 * n_hits and scrapes.R > scrapes.L and km > 10.0 and sim.pod.health > 0.3)
	# a hard impact still costs: everything flung sideways into the right-hand wall at 120 m/s
	var sim1 = S.new({"track": "gp", "damage": true})
	for b in [sim1.eL, sim1.eR, sim1.pod]:   # 4 m off the right-hand wall, then thrown at it
		b.y -= sim1.GP_WIDTH / 2.0 - 7.0   # (the wall moves out with the track width)
		b.vx = 0.0
		b.vy = -120.0
	var before: float = sim1.eL.health + sim1.eR.health + sim1.pod.health
	for i in 240:
		sim1.step({"thrL": 0.0, "thrR": 0.0, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": true}, DT)
		sim1.events.clear()
	var lost: float = before - (sim1.eL.health + sim1.eR.health + maxf(sim1.pod.health, 0.0))
	_check("a hard impact still damages (thrown into the wall at 120 m/s: %.2f health lost)" % lost, lost >= 0.3)
	# with damage off (the default) the same impact registers but costs nothing
	var sim0 = S.new({"track": "gp"})
	for b in [sim0.eL, sim0.eR, sim0.pod]:
		b.y -= sim0.GP_WIDTH / 2.0 - 7.0
		b.vx = 0.0
		b.vy = -120.0
	var hits0 := 0
	for i in 240:
		sim0.step({"thrL": 0.0, "thrR": 0.0, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": true}, DT)
		for e in sim0.events:
			if e.type == "hit":
				hits0 += 1
		sim0.events.clear()
	_check("damage off by default: the same impact registers (%d hits) but costs nothing (%.2f / %.2f / pod %.2f)" % [hits0, sim0.eL.health, sim0.eR.health, sim0.pod.health],
		not sim0.P.damage and hits0 > 0 and sim0.eL.health == 1.0 and sim0.eR.health == 1.0 and sim0.pod.health == 1.0)
	# 2. a wrecked engine is weak: average thrust at full lever, left whole vs right wrecked
	var sim2 = S.new({"track": "gp", "damage": true})
	sim2.eR.health = 0.0
	var tl := 0.0
	var tr := 0.0
	for i in 480 * 3:
		sim2.step({"thrL": 0.87, "thrR": 0.87, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": true}, DT)
		tl += sim2.eL.thrust
		tr += sim2.eR.thrust
		sim2.events.clear()
	_check("a wrecked engine at full lever gives %.0f%% of a whole one's thrust (sputtering)" % (tr / tl * 100.0), tr / tl < 0.45)
	# 3. X heals it
	var sim3 = S.new({"track": "gp", "damage": true})
	sim3.eR.health = 0.0
	for i in 480 * 4:
		sim3.step({"thrL": 0.0, "thrR": 0.0, "brkL": 0.0, "brkR": 0.0, "repair": true, "reignite": true}, DT)
		sim3.events.clear()
	_check("holding X (repair) for 4 s heals it to %.2f" % sim3.eR.health, sim3.eR.health >= 0.45)
	# 4. Y in the game (the view's restart): fresh engines, back on the grid, lap reset
	v = ViewScript.new()
	root.add_child(v)


func _process(_d: float) -> bool:
	frames += 1
	if frames < 2:
		return false
	var sim = v.sim
	for i in 480 * 4:
		sim.step({"thrL": 0.6, "thrR": 0.6, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": true}, DT)
		sim.events.clear()
	sim.eR.health = 0.05
	sim.eL.health = 0.7
	v._respawn()
	var d := Vector2(sim.pod.x - sim.tpx[0], sim.pod.y - sim.tpy[0]).length()
	_check("Y on the GP: whole engines (%.2f/%.2f), at rest on the grid (%.1f m from the line), lap reset (%d)" % [sim.eL.health, sim.eR.health, d, sim.lap],
		sim.eL.health == 1.0 and sim.eR.health == 1.0 and d < 40.0 and sim.lap == 0 and sim.lap_start < 0.0)
	var good: bool = fails == 0 and passed == 6
	print("ENGINE DAMAGE ", "PASS" if good else "FAIL (%d failed, %d passed)" % [fails, passed])
	quit(0 if good else 1)
	return true


func _check(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if ok:
		passed += 1
	else:
		fails += 1
