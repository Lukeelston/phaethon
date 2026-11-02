## The emergency run's job in GDScript CraftSim, mirroring tools/job_test.js's scripted states
## (place the pod, set the clock, step): the dawn's timing, the clock starting on the first move,
## caught in the open, the shelter (towns, the shade line's canopy), the pad (1.5 s stopped in its
## box), the finish on each route with its own margin, a crash, restart, and no job without one.
## Prints JOB PASS.
## Run: Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_job.gd
extends SceneTree

const CraftSimScript := preload("res://sim/craft_sim.gd")
const DT := 1.0 / 480.0
const MPH := 2.236936
const IDLE := {"thrL": 0.0, "thrR": 0.0, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": true}
const PUSH := {"thrL": 0.3, "thrR": 0.3, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": true}


func _initialize() -> void:
	var fails := 0
	# no job
	var free = CraftSimScript.new({"track": "eridanus"})
	var ev := _steps(free, 1.0, {"thrL": 0.5, "thrR": 0.5, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": true})
	fails += _check("no job: job %s, no job events" % [free.job], free.job.is_empty() and ev.filter(func(e): return e.type == "job" or e.type == "dawn").is_empty())
	# lit
	var sim = _job_sim()
	var ux: float = 447.04 * cos(sim.P.dawnDir)   # floats: Vector2 is single precision
	var uy: float = 447.04 * sin(sim.P.dawnDir)
	var t1: float = sim.t_lit(ux, uy) - sim.t_lit(0.0, 0.0)
	fails += _check("lit: the start line's point at dawnT0 (%s vs %s), 447.04 m on %.9f s later" % [sim.t_lit(0.0, 0.0), sim.P.dawnT0, t1],
		sim.t_lit(0.0, 0.0) == sim.P.dawnT0 and absf(t1 - 1.0) < 1e-9 and sim.P.dawnSpeed == 447.04)
	fails += _check("a job: %s, pad %d, mouth %d" % [sim.job, sim.pad, sim.mouth],
		sim.job.stage == "out" and sim.job.t == 0.0 and sim.job.route == "open" and sim.job.reason == "" and sim.pad == 6932 and sim.mouth == 16046)
	# clock
	sim = _job_sim()
	_steps(sim, 2.0)
	var t0: float = sim.job.t
	_steps(sim, 1.0, PUSH)
	fails += _check("clock: %s s after 2 s at rest, %.3f s a second after the levers move" % [t0, sim.job.t], t0 == 0.0 and absf(sim.job.t - 1.0) < 0.01)
	# caught, and not yet
	sim = _job_sim()
	var i := _first_sp(sim, 2000)
	_place_main(sim, i, 0.0)
	_clock_at(sim, sim.t_lit(sim.pod.x, sim.pod.y) - 0.5)
	_steps(sim, DT)
	var before: String = sim.job.stage
	_clock_at(sim, sim.t_lit(sim.pod.x, sim.pod.y) + 0.001)
	ev = _steps(sim, DT)
	var dawns := ev.filter(func(e): return e.type == "dawn").size()
	fails += _check("caught on the loop (sample %d): %s half a second before, then %s (%s), %d dawn event, crash_t %.2f" % [i, before, sim.job.stage, sim.job.reason, dawns, sim.crash_t],
		before == "out" and sim.job.stage == "failed" and sim.job.reason == "dawn" and dawns == 1
		and ev.any(func(e): return e.type == "job" and e.stage == "failed") and sim.crash_t > 1.5)
	ev = _steps(sim, 3.0)
	fails += _check("failed stays failed through the fade and respawn", sim.job.stage == "failed" and ev.filter(func(e): return e.type == "dawn" or e.type == "job").is_empty())
	# shelter
	sim = _job_sim()
	_place_main(sim, sim.pad, 0.0)
	_clock_at(sim, sim.t_lit(sim.pod.x, sim.pod.y) + 5.0)
	_steps(sim, DT)
	var town: String = sim.job.stage
	var s2 = _job_sim()
	var B = s2.branches[0]
	_place_branch(s2, B.covered.x + 50, 0.0)
	_clock_at(s2, s2.t_lit(s2.pod.x, s2.pod.y) + 5.0)
	_steps(s2, DT)
	var s3 = _job_sim()
	_place_branch(s3, B.covered.x - 50, 0.0)
	_clock_at(s3, s3.t_lit(s3.pod.x, s3.pod.y) + 0.001)
	_steps(s3, DT)
	fails += _check("shelter: in the lake town %s; under the canopy %s (path %d); on the shade line short of it %s (%s)" % [town, s2.job.stage, s2.pod.path, s3.job.stage, s3.job.reason],
		town == "out" and s2.job.stage == "out" and s2.pod.path == 1 and s3.job.stage == "failed" and s3.job.reason == "dawn")
	# the pad
	sim = _job_sim()
	_place_main(sim, sim.pad, 0.0)
	_clock_at(sim, 10.0)
	_steps(sim, 1.4)
	var held: float = sim.job.held
	var at14: String = sim.job.stage
	ev = _steps(sim, 0.2)
	var at16: String = sim.job.stage
	var drops := ev.filter(func(e): return e.type == "job").map(func(e): return e.stage)
	_place_main(sim, sim.pad + 20, 0.0)
	ev = _steps(sim, DT)
	fails += _check("pad: held %.3f s at 1.4 s, still %s; %s by 1.6 s %s; %s once off it" % [held, at14, at16, drops, sim.job.stage],
		at14 == "out" and held > 1.3 and at16 == "drop" and drops == ["drop"] and sim.job.stage == "home" and ev.any(func(e): return e.type == "job" and e.stage == "home"))
	sim = _job_sim()
	_place_main(sim, sim.pad, 60.0)
	_clock_at(sim, 10.0)
	_steps(sim, 0.5)
	fails += _check("pad: rolling through it doesn't count (%s, held %s)" % [sim.job.stage, sim.job.held], sim.job.stage == "out" and sim.job.held == 0.0)
	# done: the open loop
	sim = _job_sim()
	_place_main(sim, sim.mouth - 20, 400.0)
	sim.job.stage = "home"
	_clock_at(sim, 50.0)
	ev = _steps(sim, 3.0)
	var done := ev.filter(func(e): return e.type == "job" and e.stage == "done")
	var want: float = sim.t_lit(sim.tpx[sim.mouth], sim.tpy[sim.mouth]) - sim.job.t
	fails += _check("done on the open loop: %s, route %s, margin %.2f s (want %.2f), event %s" % [sim.job.stage, sim.job.route, sim.job.margin, want, done],
		sim.job.stage == "done" and sim.job.route == "open" and sim.job.margin > 0.0 and absf(sim.job.margin - want) < 1e-9
		and done.size() == 1 and done[0].route == "open" and done[0].margin == sim.job.margin)
	# done: the shade line
	sim = _job_sim()
	B = sim.branches[0]
	_place_branch(sim, B.covered.x - 10, 600.0)
	sim.job.stage = "home"
	_clock_at(sim, 50.0)
	_steps(sim, 1.0)
	var m: float = sim.job.margin
	var r: String = sim.job.route
	_place_branch(sim, B.N - 25, 500.0)
	ev = _steps(sim, 3.0)
	done = ev.filter(func(e): return e.type == "job" and e.stage == "done")
	fails += _check("done off the shade line: under the canopy route %s, margin %.2f s; %s at the mouth, route %s, margin %.2f" % [r, m, sim.job.stage, sim.job.route, sim.job.margin],
		r == "shade" and m > 0.0 and sim.job.stage == "done" and sim.job.route == "shade" and sim.job.margin == m and done.size() == 1 and done[0].route == "shade")
	# the shade line's merge: under the canopy you've made it, onto the main road and into the town
	sim = _job_sim()
	B = sim.branches[0]
	_place_branch(sim, B.covered.x - 10, 600.0)
	sim.job.stage = "home"
	_clock_at(sim, 50.0)
	_steps(sim, 1.0)
	m = sim.job.margin
	_place_branch(sim, B.N - 25, 500.0)
	var q: int = B.join_i - 40
	_clock_at(sim, sim.t_lit(sim.tpx[q], sim.tpy[q]) + 5.0)   # the merge long since lit
	ev = _steps(sim, 3.0)
	fails += _check("the shade line's merge, lit: %s (%s), route %s, margin %.2f (the canopy's %.2f)" % [sim.job.stage, sim.job.reason, sim.job.route, sim.job.margin, m],
		sim.job.stage == "done" and sim.job.route == "shade" and sim.job.margin == m and not ev.any(func(e): return e.type == "dawn"))
	# the covered ramps (Luke: "a 'receiving' and 'outgoing' onramp ... reach speed inside of a structure")
	sim = _job_sim()
	var lens := []
	var ends_ok: bool = sim.covered_ramps.size() == 4
	for rp in sim.covered_ramps:
		var acc := 0.0
		for k in range(int(rp[0]), int(rp[1]) + 1):
			acc += sim.tlen[k]
		lens.append(acc / 1609.344)
		ends_ok = ends_ok and absf(acc / 1609.344 - 4.0) < 0.02 and sim.tmode[int(rp[0])] == 1 and sim.tmode[int(rp[1])] == 1
	for k in range(1, sim.N):
		if sim.tmode[k] != sim.tmode[k - 1]:
			var exit_: bool = sim.tmode[k] == 1
			ends_ok = ends_ok and sim.covered_ramps.any(func(q): return int(q[0]) == k if exit_ else int(q[1]) == k - 1)
	fails += _check("ramps: %s, %s mi, one at each end of each town, on the loop" % [sim.covered_ramps, lens], ends_ok)
	var rr: Array = sim.covered_ramps.filter(func(q): return int(q[1]) == sim.mouth - 1)[0]
	_place_main(sim, int(rr[0]) + 100, 0.0)
	_clock_at(sim, sim.t_lit(sim.pod.x, sim.pod.y) + 5.0)
	_steps(sim, DT)
	var in_ramp: String = sim.job.stage
	var s4 = CraftSimScript.new({"track": "eridanus", "job": "emergency", "handling": "speed"})   # coasting: STARFIGHTER's drag would stop it
	_place_main(s4, int(rr[0]) - 60, 3000.0)
	s4.job.stage = "home"
	_clock_at(s4, 50.0)
	ev = _steps(s4, 1.5)
	var m4: float = s4.job.margin
	var want4: float = s4.t_lit(s4.tpx[int(rr[0])], s4.tpy[int(rr[0])]) - 50.0 - (60.0 * 12.0) / (3000.0 / MPH)
	var safe4: bool = s4.job.safe
	ev.append_array(_steps(s4, 12.0))
	done = ev.filter(func(e): return e.type == "job" and e.stage == "done")
	fails += _check("ramps: sheltered inside one (%s); home along the loop the margin is taken at the receiving ramp's entrance (%.2f s, about %.2f; %s), done at the mouth with it (%s)" % [in_ramp, m4, want4, s4.job.route, done],
		in_ramp == "out" and safe4 and s4.job.route == "open" and absf(m4 - want4) < 0.5 and done.size() == 1 and done[0].margin == m4)
	# the shade line is a STARFIGHTER line: asking for SPEEDCRAFT there does nothing
	var s5 = CraftSimScript.new({"track": "eridanus", "job": "emergency", "dawnT0": 1e9, "handling": "speed"})
	_place_branch(s5, 150, 600.0)
	_steps(s5, 1.5, {"thrL": 0.3, "thrR": 0.3, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": true, "handling": "speed"})
	fails += _check("the shade line holds STARFIGHTER: arrived in SPEEDCRAFT, asking for it, after 1.5 s: %s, blend %.2f (path %d)" % [s5.hwant, s5.hblend, s5.pod.path],
		s5.pod.path == 1 and s5.hwant == "starfighter" and s5.hblend == 1.0)
	# crash, restart
	sim = _job_sim()
	_place_main(sim, 3000, 300.0)
	_clock_at(sim, 5.0)
	sim.pod.health = 0.0
	_steps(sim, DT)
	var st: String = sim.job.stage
	var rs: String = sim.job.reason
	sim.restart()
	fails += _check("crash: %s (%s); restart: %s" % [st, rs, sim.job],
		st == "failed" and rs == "crash" and sim.job.stage == "out" and sim.job.t == 0.0 and sim.job.held == 0.0 and sim.job.route == "open" and sim.job.reason == "" and sim.job.t0 == null)
	print("JOB PASS" if fails == 0 else "JOB FAIL (%d)" % fails)
	quit(1 if fails else 0)


func _job_sim():
	return CraftSimScript.new({"track": "eridanus", "job": "emergency"})


func _steps(sim, secs: float, inp: Dictionary = IDLE) -> Array:
	var ev := []
	for k in roundi(secs / DT):
		sim.step(inp, DT)
		ev.append_array(sim.events)
		sim.events.clear()
	return ev


## Every body on main sample i, moving at mph along the road there.
func _place_main(sim, i: int, mph: float) -> void:
	sim.respawn(-1, i)
	var v := mph / MPH
	for b in sim.bodies:
		b.vx = v * sim.ttx[i]
		b.vy = v * sim.tty[i]


## Every body on branch sample j, laid out as respawn lays them on the main road.
func _place_branch(sim, j: int, mph: float) -> void:
	var B = sim.branches[0]
	var f: int = B.from_i
	sim.respawn(-1, f)
	var v := mph / MPH
	var dth: float = atan2(B.ty[j], B.tx[j]) - atan2(sim.tty[f], sim.ttx[f])
	for b in sim.bodies:
		var rx: float = b.x - sim.tpx[f]
		var ry: float = b.y - sim.tpy[f]
		var al: float = rx * sim.ttx[f] + ry * sim.tty[f]
		var ac: float = rx * sim.tnx[f] + ry * sim.tny[f]
		b.x = B.px[j] + al * B.tx[j] + ac * B.nx[j]
		b.y = B.py[j] + al * B.ty[j] + ac * B.ny[j]
		b.th += dth
		b.path = 1
		b.hint = mini(B.N - 1, j + roundi(al / 12.0))
		b.vx = v * B.tx[j]
		b.vy = v * B.ty[j]


## The clock running since the job's start, now at t.
func _clock_at(sim, t: float) -> void:
	sim.job.t0 = 0.0
	sim.time = t


func _first_sp(sim, from: int) -> int:
	for i in range(from, sim.N):
		if sim.tmode[i] == 1:
			return i
	return -1


func _check(label: String, ok: bool) -> int:
	print(("  ok   " if ok else "  FAIL ") + label)
	return 0 if ok else 1
