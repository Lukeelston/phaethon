## Job flow gate (the emergency run in the cockpit, docs/superpowers/specs/2026-10-19-emergency-run-design.md):
##   eridanus only   the job asked for on the range builds no job
##   the dash        the progress line through the run (tests/replay/job_open): the briefing
##                   (EMERGENCY  LAKE TOWN MINE  DAWN m:ss), HOLD on the pad counting down, HOME with
##                   the dawn's countdown, MADE IT  +m.m s  (OPEN); the late run: CAUGHT BY THE DAWN
##   the countdown   DAWN m:ss counts to each route's own deadline: the pad out; from the drop on,
##                   the receiving ramp on the loop, the canopy once on the shade line; then UNDER COVER
##   the pad         findable (Luke flew straight past it): on the job a red light column stands at
##                   it and a sign over the road before it; the dash calls MEDICAL PAD x.x mi from 8 mi
##                   out, STOP ON THE PAD on it, PAD BEHIND if you overshoot
##   best time       saved when the run is made, not when it's caught; read from where the views
##                   are pointed from the build on (never the player's own best)
##   off the loop    on the shade line (tests/replay/job_shade) the speed guide is neutral (guide_on
##                   0, no town cut) and the minimap's path ahead follows the branch, no errors
##   the cycle       the menu hold's tracks: range -> gp -> eridanus -> emergency -> range
## Prints JOB FLOW PASS.
## Run: Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_job_flow.gd -- --mute
extends SceneTree

const ViewScript := preload("res://view/craft_view.gd")
const Cockpit := preload("res://vr/vr_cockpit.gd")
const DT := 1.0 / 480.0
const SUB := 8
const ASK := ["", "speed", "starfighter"]
const PREFIX := "user://test_job_flow_"
const CHECKS := 12
var fails := 0
var passed := 0
var frames := 0
var stage := 0
var v


func _initialize() -> void:
	_check("the menu hold's cycle: range -> %s -> %s -> %s -> %s -> %s" % [Cockpit.next_track("range"), Cockpit.next_track("gp"), Cockpit.next_track("eridanus"), Cockpit.next_track("emergency"), Cockpit.next_track("network")],
		Cockpit.next_track("range") == "gp" and Cockpit.next_track("gp") == "eridanus" and Cockpit.next_track("eridanus") == "emergency" and Cockpit.next_track("emergency") == "network" and Cockpit.next_track("network") == "range")
	_view("range")


func _view(track: String) -> void:
	ViewScript.track_override = track
	ViewScript.job_override = "emergency"
	v = ViewScript.new()
	root.add_child(v)
	frames = 0


func _process(_d: float) -> bool:
	frames += 1
	if frames < 3:
		return false
	ViewScript.track_override = ""
	ViewScript.job_override = ""
	match stage:
		0:
			_check("eridanus only: the job asked for on the range builds none (%s, job %s)" % [v.sim.kind, v.sim.job], v.sim.kind == "range" and v.sim.job.is_empty())
			var f := FileAccess.open(PREFIX + "eridanus_emergency_best.json", FileAccess.WRITE)   # a best of the test's own
			f.store_string(JSON.stringify({"best": 1.0}))
			f.close()
			ViewScript.best_dir = PREFIX
			_next("eridanus")
		1:
			_open_run()
			ViewScript.best_dir = PREFIX + "late_"
			_next("eridanus")
		2:
			_late_run()
			ViewScript.best_dir = PREFIX + "shade_"   # it makes it too: keep its best out of the player's
			_next("eridanus")
		3:
			_shade_run()
			v.queue_free()
			ViewScript.best_dir = "user://"
			for f in ["eridanus_emergency_best.json", "late_eridanus_emergency_best.json", "shade_eridanus_emergency_best.json"]:
				DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFIX + f))
			var good: bool = fails == 0 and passed == CHECKS
			print("JOB FLOW ", "PASS" if good else "FAIL (%d failed, %d of %d passed)" % [fails, passed, CHECKS])
			quit(0 if good else 1)
			return true
	return false


func _next(track: String) -> void:
	v.queue_free()
	stage += 1
	_view(track)


## Replay a recorded run through the view's own event handling (its _process held off), calling
## `each` after every frame. Returns the frames run.
func _replay(name: String, each: Callable) -> int:
	v.set_process(false)
	var inputs: Array = JSON.parse_string(FileAccess.get_file_as_string("res://tests/replay/job_%s_inputs.json" % name))
	var sim = v.sim
	for f in inputs.size():
		var u: Array = inputs[f]
		v.inp = {"thrL": u[0], "thrR": u[1], "brkL": u[2], "brkR": u[3], "repair": false, "reignite": true}
		if int(u[4]) > 0:
			v.inp["handling"] = ASK[int(u[4])]
		for k in SUB:
			sim.step(v.inp, DT)
			for e in sim.events:
				v._on_event(e)
			sim.events.clear()
		each.call(f)
	return inputs.size()


## The pad, findable: its column and sign on the job, and the dash's call as you come up to it.
func _pad_marks() -> void:
	var sim = v.sim
	var cw = v.course_world
	var col_ok := false
	if cw.pad_column:
		var p: Vector3 = (cw.pad_column as Node3D).global_position
		col_ok = Vector2(p.x + v.org_x - sim.tpx[sim.pad], -p.z + v.org_y - sim.tpy[sim.pad]).length() < 150.0
	_check("the pad on the job: a light column at it (%s) and a sign over the road before it (%s); stars in the twilight sky (%s)" % [col_ok, cw.pad_sign != null, v.stars != null],
		col_ok and cw.pad_sign != null and v.stars != null and (v.stars as Node3D).visible)
	# the dash as you come up to it: far, 2 mi out, on it, past it
	var texts := []
	var save := [sim.time, sim.job.t0]
	sim.job.t0 = 0.0
	sim.time = 10.0
	for k in [-2000, -268, 0, 30]:   # samples from the pad (268 is ~2 mi)
		sim.respawn(-1, posmod(sim.pad + k, sim.N))
		texts.append(v._progress_text())
	sim.time = save[0]
	sim.job.t0 = save[1]
	sim.restart()
	_check("the dash comes up to the pad: %s" % [texts],
		texts[0].begins_with("EMERGENCY  LAKE TOWN MINE") and texts[1].begins_with("MEDICAL PAD  2.0 mi") and texts[2].begins_with("STOP ON THE PAD")
		and texts[3].begins_with("PAD BEHIND"))


## The DAWN m:ss on the dash, in seconds (-1 when there's none).
func _dawn_secs(t: String) -> int:
	var m := RegEx.create_from_string("DAWN (\\d+):(\\d\\d)").search(t)
	return -1 if m == null else int(m.get_string(1)) * 60 + int(m.get_string(2))


## What the dash should count: whole seconds until the dawn lights (x, y).
func _want_secs(x: float, y: float) -> int:
	return int(maxf(v.sim.t_lit(x, y) - v.sim.job_time(), 0.0))


func _open_run() -> void:
	_pad_marks()
	_check("best time: the view read the best from where it was pointed, at its build (%s; the planted 1.0)" % v.best_saved, v.best_saved == 1.0)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFIX + "eridanus_emergency_best.json"))
	v.best_saved = -1.0
	var seen := {"brief": v._progress_text(), "hold": "", "home": "", "done": ""}
	var sim = v.sim
	var ramp: int = -1
	for r in sim.covered_ramps:
		if int(r[1]) == sim.mouth - 1:
			ramp = int(r[0])
	var cnt := {"drop": 0, "drop_ok": 0, "home": 0, "home_ok": 0}
	_replay("open", func(_f):
		var J: Dictionary = v.sim.job
		var t: String = v._progress_text()
		if J.stage == "drop" or (J.stage == "home" and not J.safe):
			var key: String = "drop" if J.stage == "drop" else "home"
			cnt[key] += 1
			cnt[key + "_ok"] += 1 if _dawn_secs(t) == _want_secs(sim.tpx[ramp], sim.tpy[ramp]) else 0
		if J.stage == "out" and J.held > 0.5 and seen.hold == "":
			seen.hold = t
		elif J.stage == "home" and seen.home == "" and J.t > 120.0:
			seen.home = t
		elif J.stage == "done" and seen.done == "":
			seen.done = t)
	_check("the countdown: from the drop on it counts to the start town's receiving ramp (drop %d/%d frames, home %d/%d)" % [cnt.drop_ok, cnt.drop, cnt.home_ok, cnt.home],
		cnt.drop > 0 and cnt.drop_ok == cnt.drop and cnt.home > 1000 and cnt.home_ok == cnt.home)
	var rx := RegEx.create_from_string("DAWN \\d+:\\d\\d")
	_check("the dash: briefing '%s', on the pad '%s', home '%s', made it '%s'" % [seen.brief, seen.hold, seen.home, seen.done.replace("\n", " / ")],
		seen.brief.begins_with("EMERGENCY  LAKE TOWN MINE") and rx.search(seen.brief) != null
		and seen.hold.begins_with("HOLD  ") and seen.home.begins_with("HOME") and rx.search(seen.home) != null
		and seen.done.begins_with("MADE IT  +%.1f s  (OPEN)" % v.sim.job.margin))
	var path := PREFIX + "eridanus_emergency_best.json"
	var saved = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	_check("best time: saved on making it (%s; the run %.2f s)" % [saved, v.sim.job.t], saved is Dictionary and absf(float(saved.best) - v.sim.job.t) < 1e-6)


func _late_run() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFIX + "late_eridanus_emergency_best.json"))
	var last := [""]
	_replay("late", func(_f): last[0] = v._progress_text())
	_check("caught: '%s', no best saved (%s)" % [last[0].replace("\n", " / "), FileAccess.file_exists(PREFIX + "late_eridanus_emergency_best.json")],
		last[0].begins_with("CAUGHT BY THE DAWN") and not FileAccess.file_exists(PREFIX + "late_eridanus_emergency_best.json"))


func _shade_run() -> void:
	var sim = v.sim
	var guide = v.course_world.guide
	var mat := ShaderMaterial.new()
	var st := {"on": 0, "lit": 0, "cut": 0.0, "pts": 0, "off": 0, "pre": 0, "pre_ok": 0, "safe": 0, "safe_ok": 0}
	var B = sim.branches[0]
	# the map's points sit on samples: the shade line's, or the loop's past its join and before its split
	var grid := {}
	var put := func(x: float, y: float):
		var k := Vector2i(floori(x / 100.0), floori(y / 100.0))
		if not grid.has(k):
			grid[k] = []
		grid[k].append(Vector2(x, y))
	for i in B.N:
		put.call(B.px[i], B.py[i])
	for k in range(-1500, 1500):
		var m: int = posmod(B.join_i + k, sim.N) if k >= 0 else posmod(B.from_i + k, sim.N)
		put.call(sim.tpx[m], sim.tpy[m])
	_replay("shade", func(_f):
		var txt: String = v._progress_text()
		if sim.job.stage == "home" and sim.job.safe:
			st.safe += 1
			st.safe_ok += 1 if txt.contains("UNDER COVER") and _dawn_secs(txt) == -1 else 0
		if sim.pod.path <= 0:
			return
		if sim.job.stage == "home" and sim.pod.hint < B.covered.x:
			st.pre += 1
			st.pre_ok += 1 if _dawn_secs(txt) == _want_secs(B.px[B.covered.x], B.py[B.covered.x]) else 0
		st.on += 1
		guide.apply(mat)
		st.lit += 1 if float(mat.get_shader_parameter("guide_on")) != 0.0 else 0
		st.cut = maxf(st.cut, guide.town_cut(500.0, guide.brake_model(), guide.brake_model("starfighter")))
		var th: float = sim.pod.th
		var f: Dictionary = v.minimap.update(th, 1.0 / 60.0)
		var fx := cos(th)
		var fy := sin(th)
		for p in f.pts:
			if p.y < 50.0:
				continue
			var x: float = sim.pod.x + p.x * fy + p.y * fx
			var y: float = sim.pod.y - p.x * fx + p.y * fy
			st.pts += 1
			var c := Vector2i(floori(x / 100.0), floori(y / 100.0))
			var near := INF
			for dx in range(-1, 2):
				for dy in range(-1, 2):
					for q in grid.get(Vector2i(c.x + dx, c.y + dy), []):
						near = minf(near, (q as Vector2).distance_to(Vector2(x, y)))
			if near > 0.5:
				st.off += 1)
	_check("the countdown on the shade line: to the canopy before it (%d/%d frames), UNDER COVER after (%d/%d)" % [st.pre_ok, st.pre, st.safe_ok, st.safe],
		st.pre > 100 and st.pre_ok == st.pre and st.safe > 100 and st.safe_ok == st.safe)
	_check("off the loop: on the shade line for %d frames, the guide lit on %d of them, its town cut %.2f" % [st.on, st.lit, st.cut], st.on > 1000 and st.lit == 0 and st.cut == 0.0)
	_check("off the loop: the minimap's path ahead follows the shade line (%d of %d points off it and off the town's road past it)" % [st.off, st.pts], st.pts > 10000 and st.off == 0)


func _check(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if ok:
		passed += 1
	else:
		fails += 1
