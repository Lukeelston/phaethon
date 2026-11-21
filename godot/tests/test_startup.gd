## The start-up (Luke: "design a 'startup' sequence for the vehicle, similar to a jet startup
## sequence ... a covered switch for engine power, and another for a parking brake that holds the
## vehicle steady at rest to startup the turbines and test them. And then of course a dope start
## button"): vr/startup_sequence.gd's logic on its own, the sounds it asks for, the panel under the
## roof's header (vr/overhead_panel.gd), and the whole of it worked by a hand in a real cockpit,
## from cold and dark to flying.
## Run it with --mute for the cockpit and the logic; without it the engines' voices are checked too
## (which of them is silent, turning over, running; the turbines spooled on the brake).
extends SceneTree

const View := preload("res://view/craft_view.gd")
const Cockpit := preload("res://vr/vr_cockpit.gd")
const Sequence := preload("res://vr/startup_sequence.gd")
const Overhead := preload("res://vr/overhead_panel.gd")
const Sounds := preload("res://audio/startup_audio.gd")
const Projector := preload("res://view/approach_projector.gd")
const Reflection := preload("res://view/screen_reflection.gd")
var v
var hand: Node3D
var failures := 0
var checks := 0


func _initialize() -> void:
	View.track_override = "network"
	View.job_override = "none"
	View.best_dir = OS.get_user_data_dir().path_join("test_startup_")
	Cockpit.camera = "cockpit"
	Cockpit._camera_loaded = true      # the pilot's saved choices stay out of this
	Cockpit._nose_loaded = true
	Cockpit._slide_loaded = true
	Cockpit._startup_loaded = true
	Cockpit.cold_start = true
	_run.call_deferred()


func _check(label: String, passed: bool) -> void:
	checks += 1
	print(("PASS " if passed else "FAIL ") + label)
	failures += int(not passed)


# ---- the logic alone ----

func _run_for(s, seconds: float, thr := [0.0, 0.0], gear := 1) -> void:
	var left := seconds
	while left > 1e-6:
		var dt := minf(left, 1.0 / 90.0)
		s.step(dt, thr, gear)
		left -= dt


func _logic() -> void:
	var s = Sequence.new()
	var marks := []          # the glass's tally at each thing done: it must only go up
	var glass := {}
	var full := {"thrL": 1.0, "thrR": 1.0, "brkL": 0.0, "brkR": 0.0, "burner": true}
	_check("a sequence is born running, the brake off: the sim is given exactly what is asked", s.is_hot() and s.cleared and is_same(s.gate(full), full) and s.message() == "")
	s.cold()
	var held: Dictionary = s.gate(full)
	_check("cold and dark: brake set, nothing on; the sim is given no thrust (%s / %s, burner %s) and both air brakes full out (%s / %s); the ask itself is untouched" % [held.thrL, held.thrR, held.burner, held.brkL, held.brkR],
		s.park and not s.batt and not s.master and held.thrL == 0.0 and held.thrR == 0.0 and held.burner == false and held.brkL == 1.0 and held.brkR == 1.0
		and full.thrL == 1.0 and full.brkL == 0.0 and s.power == 0.0)
	_check("with the battery dead there is nothing to read, and the control to work is the battery: \"%s\", \"%s\"" % [s.message(), s.next_control()], s.message() == "" and s.next_control() == "batt" and s.step_number() == 1)
	_check("... and nothing for the glass to draw", s.display().is_empty() and s.start_progress(0) == 0.0)
	_check("the start button does nothing on a dead bus: \"%s\"" % s.press_start(), s.events.has("dead") and s.stage == ["off", "off"])
	_check("the guard is in the way of a push down, and the first flick up only lifts it", s.flick("engine", -1) == "" and s.flick("engine", 1) == "guard_open" and s.guard_open and not s.master)
	var did: String = s.flick("engine", 1)
	_check("engine power is refused without the battery: \"%s\"" % s.refusal, did == "refused" and s.refusal == "BATTERY FIRST" and not s.master)
	_run_for(s, Sequence.GUARD_OPEN_S + 0.1)
	_check("left alone, the guard falls shut again", not s.guard_open and s.events.has("guard_close"))
	s.events.clear()
	_check("1 BATT: the bus comes up and the self-test starts", s.flick("batt", 1) == "batt_on" and s.batt and s.selftest == 0.0 and not s.tested)
	_run_for(s, Sequence.SELFTEST_S * 0.5)
	_check("... half way through it, power is up (%.2f) and the glass says so: %s" % [s.power, s.message().replace("\n", " / ")], s.power == 1.0 and s.selftest > 0.0 and s.message().contains("ENGINE POWER  2 / 5") and s.message().contains("LIFT THE RED GUARD") and s.message().contains("SELF TEST"))
	glass = s.display()
	marks.append(glass.mark)
	_check("... and the glass is given it to draw: one step behind (the battery), the control to work overhead left, the bus's bar half way across (%s)" % [glass.bars],
		glass.done == 1 and glass.aim == -1 and not glass.pair and absf(glass.bars[0] - 1.0) < 0.03 and glass.bars[1] < 0.03 and glass.cleared == -1.0 and not glass.alert)
	_run_for(s, Sequence.SELFTEST_S * 0.5 + 0.05)
	_check("... and it finishes in %.1f s" % Sequence.SELFTEST_S, s.tested and s.selftest < 0.0 and s.events.has("selftest_done") and s.next_control() == "guard")
	marks.append(s.display().mark)
	did = s.press_start()
	_check("the start button is refused without engine power: \"%s\"" % s.refusal, did == "refused" and s.refusal == "ENGINE POWER FIRST")
	_check("... which the glass is told, to put a bar under the words", s.display().alert and s.display().bars == [1.0, 1.0])
	s.flick("engine", 1)
	marks.append(s.display().mark)      # the guard lifted
	s.flick("engine", 1)
	glass = s.display()
	marks.append(glass.mark)
	_check("engine power on: two steps behind, the control to work overhead right, and the bar is the binder's charge, from nothing (%s)" % [glass.bars], glass.done == 2 and glass.aim == 1 and glass.bars == [0.0, 0.0])
	s.flick("engine", -1)               # (off again, and the guard shut, for the checks that follow)
	s.flick("engine", -1)
	_check("2 ENGINE: lift the guard, then the switch", s.flick("engine", 1) == "guard_open" and s.next_control() == "engine" and s.flick("engine", 1) == "master_on" and s.master)
	did = s.flick("batt", -1)
	_check("the battery will not go off under engine power: \"%s\"" % s.refusal, did == "refused" and s.batt and s.refusal == "ENGINE POWER OFF FIRST")
	_run_for(s, Sequence.GUARD_AFTER_S + 0.1)
	_check("the binder charges in %.1f s, the guard falls shut over the switch, and the button is on offer: %s" % [Sequence.CHARGE_S, s.message().replace("\n", " / ")],
		s.charge == 1.0 and not s.guard_open and s.next_control() == "start" and s.message().contains("PRESS 3 START") and s.message().contains("ARMED"))
	marks.append(s.display().mark)
	_check("... its bar full", s.display().bars == [1.0, 1.0] and s.display().done == 2)
	s.flick("park", -1)
	did = s.press_start(0.0)
	_check("at rest it will not start without the parking brake: \"%s\", and the glass says so: %s" % [s.refusal, s.message().replace("
", " / ")],
		did == "refused" and s.refusal == "SET THE PARK BRAKE TO START" and s.stage == ["off", "off"] and s.message().contains("SET THE PARK BRAKE TO START | NO BRAKE"))
	_check("the brake goes on again at rest, and not at 80 mph", s.flick("park", 1, 80.0) == "refused" and not s.park and s.flick("park", 1, 2.0) == "park_set" and s.park)
	s.events.clear()
	_check("3 START: the left engine turns over at once, the right waits its turn", s.press_start(0.0) == "start" and s.stage == ["wait", "wait"])
	_run_for(s, 0.05)
	_check("... %s" % [s.stage], s.stage == ["crank", "wait"] and s.events.has("crank0") and s.starting() and s.next_control() == "")
	glass = s.display()
	marks.append(glass.mark)
	_check("the glass has a bar for each engine now: the left one just begun (%.3f), the right at nothing, no control to work" % glass.bars[0], glass.pair and glass.bars[0] > 0.0 and glass.bars[0] < 0.05 and glass.bars[1] == 0.0 and glass.aim == 0 and glass.done == 2)
	_run_for(s, Sequence.STAGGER_S)
	_check("... %.1f s later the right one too: %s" % [Sequence.STAGGER_S, s.message().replace("\n", " / ")], s.stage == ["crank", "crank"] and s.message().contains("LEFT CRANKING > RIGHT CRANKING"))
	marks.append(s.display().mark)
	_run_for(s, Sequence.CRANK_S - Sequence.STAGGER_S)
	_check("... the left catches after %.1f s on the starter (a flare of %.2f), the right still cranking" % [Sequence.CRANK_S, s.catch_flare(0)], s.stage == ["catch", "crank"] and s.events.has("light0") and not s.events.has("light1"))
	glass = s.display()
	marks.append(glass.mark)
	_check("... its bar seven tenths across as it catches (%.2f), the right engine's part way (%.2f)" % [glass.bars[0], glass.bars[1]], absf(glass.bars[0] - 0.7) < 0.02 and glass.bars[1] > 0.1 and glass.bars[1] < 0.3)
	_run_for(s, Sequence.CATCH_S * 0.5)
	_check("... and half way to its idle it flares (%.2f; bar %.2f)" % [s.display().flare[0], s.display().bars[0]], s.display().flare[0] > 0.9 and absf(s.display().bars[0] - 0.85) < 0.03 and s.display().flare[1] == 0.0)
	var before: Dictionary = s.gate(full)
	_run_for(s, Sequence.STAGGER_S + Sequence.CATCH_S * 0.5 + 0.05)
	_check("... and both are running %.1f s after the button" % (Sequence.STAGGER_S + Sequence.CRANK_S + Sequence.CATCH_S), s.all_running() and s.events.has("running") and before.thrL == 0.0)
	held = s.gate(full)
	_check("4 PARK holds her: engines running, levers full, and the sim is given no thrust (%s / %s) and full air brakes (%s / %s)" % [held.thrL, held.thrR, held.brkL, held.brkR],
		s.held() and held.thrL == 0.0 and held.thrR == 0.0 and held.brkL == 1.0 and held.brkR == 1.0 and not s.cleared)
	glass = s.display()
	marks.append(glass.mark)
	_check("the glass: three steps behind, one bar again and empty (the turbines), no control to work but the levers", glass.done == 3 and not glass.pair and glass.bars == [0.0, 0.0] and glass.aim == 0 and glass.flare == [0.0, 0.0])
	_check("without a gearbox the run-up asks for the levers and the turbines: %s" % s.message().split("\n")[1], s.message().contains("LEVERS -- -- > TURBINES --") and not s.message().contains("GEAR"))
	s.gears = true
	_check("with one, for a shift too: %s" % s.message().replace("\n", " / "), s.message().contains("RUN-UP  4 / 5") and s.message().contains("LEVERS -- -- > GEAR -- > TURBINES --") and s.next_control() == "park")
	_run_for(s, 0.2, [0.7, 0.0])
	_check("a lever tried is ticked, its own alone: %s" % [s.checks], s.checks.thrL and not s.checks.thrR and not s.checks.gear and not s.checks.turbines)
	marks.append(s.display().mark)
	_run_for(s, 0.2, [0.0, 0.7], 2)
	_check("the other lever, and a shift from first to second: %s" % [s.checks], s.checks.thrR and s.checks.gear and not s.checks_done())
	marks.append(s.display().mark)
	_run_for(s, Sequence.TURBINE_UP_S * 0.5, [1.0, 1.0], 2)
	_check("both levers held forward spool the turbines (%.0f%% half way): %s" % [s.turbine * 100.0, s.message().split("\n")[1]], s.turbine > 0.4 and s.turbine < 0.6 and not s.checks.turbines and s.message().contains("LEVERS OK OK > GEAR OK > TURBINES 50%"))
	_check("... the glass's bar with them, half way across (%s)" % [s.display().bars], absf(s.display().bars[0] - 1.0) < 0.05 and s.display().bars[1] < 0.05)
	_run_for(s, Sequence.TURBINE_UP_S * 0.5 + 0.05, [1.0, 1.0], 2)
	_check("... to their test speed in %.1f s, and the checks are done: %s" % [Sequence.TURBINE_UP_S, s.message().replace("\n", " / ")], s.checks.turbines and s.checks_done() and s.events.has("turbines_ok") and s.message().contains("RELEASE PARK BRAKE  5 / 5") and s.message().contains("| READY"))
	glass = s.display()
	marks.append(glass.mark)
	_check("the glass: four steps behind, the bar full, the control to work overhead right", glass.done == 4 and glass.bars == [1.0, 1.0] and glass.aim == 1)
	_run_for(s, Sequence.TURBINE_DOWN_S + 0.1)
	_check("let go, they wind down again", s.turbine == 0.0)
	_check("the brake released: the air brakes stow and she is yours (the sim is given what is asked), and the glass says CLEARED for a moment", s.flick("park", -1) == "park_release" and is_same(s.gate(full), full) and s.gate(full).brkL == 0.0)
	_run_for(s, 0.1)
	_check("... \"%s\"" % s.message().split("\n")[0], s.cleared and s.events.has("cleared") and s.message().begins_with("CLEARED"))
	glass = s.display()
	marks.append(glass.mark)
	var rising := true
	for i in range(1, marks.size()):
		rising = rising and marks[i] > marks[i - 1]
	_check("the glass is told how long ago the brake came off (%.2f s), all five steps behind; and through the whole start its tally only ever went up (%s)" % [glass.cleared, marks],
		absf(glass.cleared - 0.1) < 0.02 and glass.done == 5 and glass.aim == 0 and rising and marks.size() == 13)
	_run_for(s, Sequence.CLEARED_S + 0.1)
	_check("... and then nothing more", s.message() == "" and s.next_control() == "")
	_check("... on the glass either", s.display().is_empty())
	# in flight
	_check("in flight a push down on the guarded switch does nothing; lifted first, it cuts both engines", s.flick("engine", -1, 3000.0) == "" and s.master and s.flick("engine", 1, 3000.0) == "guard_open" and s.flick("engine", -1, 3000.0) == "master_off" and s.stage == ["off", "off"])
	held = s.gate(full)
	_check("... and nothing reaches the sim from a dead engine", held.thrL == 0.0 and held.thrR == 0.0 and not s.cleared)
	_check("the guard is still up: engine power back on, and START relights them without the brake at speed", s.flick("engine", 1, 3000.0) == "master_on" and s.press_start(3000.0) == "start")
	_run_for(s, Sequence.STAGGER_S + Sequence.CRANK_S + Sequence.CATCH_S + 0.1)
	_check("... running again, nothing held back", s.all_running() and s.is_hot() and is_same(s.gate(full), full))
	# shut down in order
	s.flick("park", 1, 0.0)
	s.flick("engine", 1)
	_check("shut down in the order it came up: engine power, then the battery", s.flick("engine", -1) == "master_off" and s.flick("batt", -1) == "batt_off" and not s.batt)
	_run_for(s, Sequence.POWER_DOWN_S + 0.1)
	_check("... dark again, at step 1", s.power == 0.0 and s.message() == "" and s.step_number() == 1 and s.next_control() == "batt")


# ---- the sounds ----

func _sounds() -> void:
	var t0 := Time.get_ticks_msec()
	var bank: Dictionary = Sounds.bank()
	var took := Time.get_ticks_msec() - t0
	_check("every sound is loaded once, in %d ms (under 1,500)" % took, bank.size() == Sounds.NAMES.size() and took < 1500)
	# recordings (tools/startup_audio_bake.py): a switch is a tenth of a second or four, a starter outlasts its crank
	var lengths := {"toggle_on": [0.1, 0.4], "toggle_off": [0.1, 0.4], "paddle_on": [0.2, 0.6], "paddle_off": [0.2, 0.6],
		"guard_up": [0.15, 0.5], "guard_down": [0.15, 0.5], "button": [0.15, 0.45], "power": [2.0, 3.5], "down": [0.6, 1.4],
		"avionics": [1.5, 4.0], "chime": [1.0, 2.6], "pump": [1.0, 2.0], "arc": [0.8, 1.8],
		"starter": [Sequence.CRANK_S, Sequence.CRANK_S + 0.8], "catch": [1.0, 2.0], "clamp": [0.25, 0.7], "release": [0.7, 1.4], "refuse": [0.2, 0.4]}
	var report := []
	var all_ok := true
	var takes := []
	for sound: String in Sounds.NAMES:
		for w: AudioStreamWAV in bank[sound]:
			takes.append([sound, w])
	_check("two takes of each throw of a toggle and of the starter (one an engine), %d files in all, each with its level (the starter at %.1f dB)" % [takes.size(), Sounds.level_db("starter")],
		(bank.toggle_on as Array).size() == 2 and (bank.toggle_off as Array).size() == 2 and (bank.starter as Array).size() == 2 and takes.size() == 21
		and Sounds.level_db("starter") < 0.0 and Sounds.level_db("avionics") < -20.0)
	_check("the fans' loop loops, and nothing else does", (bank.avionics[0] as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_FORWARD and (bank.starter[0] as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_DISABLED)
	for take: Array in takes:
		var sound: String = take[0]
		var w: AudioStreamWAV = take[1]
		var n := w.data.size() / 2
		var peak := 0.0
		var sum := 0.0
		var crossings := 0
		var last := 0.0
		for i in n:
			var x := w.data.decode_s16(i * 2) / 32768.0
			peak = maxf(peak, absf(x))
			sum += x * x
			crossings += int((x >= 0.0) != (last >= 0.0))
			last = x
		var seconds := float(n) / Sounds.RATE
		var rms := sqrt(sum / n)
		var range: Array = lengths[sound]
		var ok := seconds >= float(range[0]) and seconds <= float(range[1]) and peak > 0.6 and peak <= 0.71 and rms > 0.01 \
			and w.format == AudioStreamWAV.FORMAT_16_BITS and not w.stereo and w.mix_rate == Sounds.RATE
		all_ok = all_ok and ok
		report.append("%s %.2f s peak %.2f rms %.3f ~%d Hz%s" % [sound, seconds, peak, rms, roundi(crossings / 2.0 / seconds), "" if ok else " (!)"])
	_check("each is the length it should be, mono at 48 kHz, peaks at -3 dB and is not silence: %s" % ", ".join(report), all_ok)


# ---- a hand on the panel ----

## A controller's tip put at a place on a pod (pod metres).
func _tip_at(pod: Node3D, at: Vector3) -> void:
	hand.global_position = pod.global_transform * at - hand.global_basis * Overhead.TIP


## A flick through a toggle's zone, up (+1) or down (-1), a sixtieth of a second long: what the panel reports.
func _flick(control: String, dir: int) -> Array:
	var c: Array = Overhead.CONTROLS[control]
	var pod: Node3D = v.overhead.pods[c[0]]
	var worked := []
	_tip_at(pod, Vector3(c[1], -0.012 * dir, 0.04))
	v.overhead.poke(hand, 0.0)                   # (the hand arrives: where it came from is no part of the flick)
	_tip_at(pod, Vector3(c[1], 0.012 * dir, 0.04))
	return v.overhead.poke(hand, 1.0 / 60.0)


## A push into the start button's face.
func _press() -> Array:
	var c: Array = Overhead.CONTROLS["start"]
	var pod: Node3D = v.overhead.pods[c[0]]
	var worked := []
	_tip_at(pod, Vector3(c[1], 0.0, 0.05))
	v.overhead.poke(hand, 0.0)
	_tip_at(pod, Vector3(c[1], 0.0, 0.012))
	worked = v.overhead.poke(hand, 1.0 / 60.0)
	_tip_at(pod, Vector3(c[1], 0.0, 0.08))      # and away again
	v.overhead.poke(hand, 1.0 / 60.0)
	return worked


## What the cockpit does with what the panel reported (as _read_input does).
func _work(worked: Array) -> String:
	var did := ""
	for hit: Array in worked:
		did = v.startup_work(String(hit[0]), int(hit[1]))
	return did


## Time passing in the cockpit with these levers and brakes asked: the sequence, the sim, the model,
## the instruments (what _process does, without a controller to read).
func _fly(seconds: float, thr := [0.0, 0.0], brk := [0.0, 0.0]) -> void:
	var left := seconds
	while left > 1e-6:
		var dt := minf(left, 1.0 / 90.0)
		v.inp = {"thrL": thr[0], "thrR": thr[1], "brkL": brk[0], "brkR": brk[1], "repair": false, "reignite": false}
		v.startup.gears = v.quest.scheme == "triggers" and v.quest.gear >= 1
		v.startup.step(dt, thr, v.quest.display_gear())
		v._apply_startup(dt)
		v._apply_shudder(dt)
		for i in roundi(dt / View.DT):
			v._sim_step()
		if v.engine_audio:
			v.engine_audio.update(v._engine_inp(), dt)
		v._sync_craft(dt)
		v.craft.sync_cables(v.sim, dt)
		v.interior.set_power(v.startup.power)
		v.interior.set_mode(v.sim.mode, v.sim.hblend)
		v._update_hud()
		v.approach_display._process(dt)       # (the checklist's own clockwork: no frames are drawn while this runs)
		left -= dt


func _speed() -> float:
	return sqrt(v.sim.pod.vx * v.sim.pod.vx + v.sim.pod.vy * v.sim.pod.vy)


func _lit(names: Array) -> int:
	var n := 0
	for name: String in names:
		n += int((v.dashboard.lamps[name] as Color).a > 0.0)
	return n


## How loud a layer of an engine's voice is being played, as a gain (its loudest level).
func _gain(k: int, layer: String) -> float:
	var best := 0.0
	for p: AudioStreamPlayer in v.engine_audio.voices[k].players[layer]:
		best = maxf(best, db_to_linear(p.volume_db))
	return best


func _cockpit() -> Node:
	var c = Cockpit.new()
	root.add_child(c)
	return c


func _panel() -> void:
	var p = v.overhead
	_check("the cockpit has its start panel, hung in the canopy with the projector", p != null and p.get_script() == Overhead and p.get_parent() == v.canopy and v.approach_display != null)
	if p == null:
		return
	var eye: Vector3 = Overhead.EYE
	var order := []
	var reach := []
	var lowest := 90.0
	var faces := 1.0
	for control: String in ["batt", "engine", "start", "park"]:
		var at: Vector3 = Overhead.control_point(control)
		order.append(at.x)
		reach.append(eye.distance_to(at))
	for side: float in p.pods:
		var pod: Node3D = p.pods[side]
		faces = minf(faces, pod.transform.basis.z.dot((eye - pod.position).normalized()))
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				var corner: Vector3 = pod.transform * Vector3(sx * Overhead.BODY.x * 0.5, Overhead.BODY_Y + sy * Overhead.BODY.z * 0.5, 0.0)
				var d := corner - eye
				lowest = minf(lowest, rad_to_deg(atan2(d.y, Vector2(d.x, d.z).length())))
	_check("read from the seat left to right they are 1 BATT, 2 ENGINE, 3 START, 4 PARK (x %s)" % [order], order[0] < order[1] and order[1] < 0.0 and 0.0 < order[2] and order[2] < order[3])
	var words := []
	for l: Label3D in p.legends:
		words.append(l.text)
	words.sort()
	_check("each legend carries its number, printed: %s" % [words], words == ["1  BATT", "2  ENGINE", "3  START", "4  PARK"])
	_check("each is an arm's reach from the seated eye (%.2f to %.2f m)" % [reach.min(), reach.max()], reach.min() > 0.3 and reach.max() < 0.62)
	_check("each pod is turned to the seated eye (within %.0f degrees of square)" % rad_to_deg(acos(clampf(faces, -1.0, 1.0))), faces > cos(deg_to_rad(10.0)))
	var image_top := rad_to_deg(Projector.IMAGE_ELEVATION + Projector.IMAGE_WIDTH * Projector.SIZE.y / Projector.SIZE.x * 0.5)
	var inner: Vector3 = Overhead.pod_frame(1.0) * Vector3(-Overhead.BODY.x * 0.5, Overhead.BODY_Y - Overhead.BODY.z * 0.5, 0.0) - eye
	var beside := rad_to_deg(atan2(absf(inner.x), -inner.z))
	_check("the pods hang in the screen's upper corners, over the road and beside the guidance: lowest corner %.1f degrees up (the guidance's top edge is %.1f), inner corner %.1f degrees out (its side edge is %.1f)" % [lowest, image_top, beside, rad_to_deg(Projector.IMAGE_WIDTH) * 0.5],
		lowest > image_top + 1.5 and beside > rad_to_deg(Projector.IMAGE_WIDTH) * 0.5 + 3.0)
	_check("they stand clear of the projector's housing between them (inner ends %.3f m out, the housing 0.125)" % (absf(Overhead.pod_frame(1.0).origin.x) - Overhead.BODY.x * 0.5), absf(Overhead.pod_frame(1.0).origin.x) - Overhead.BODY.x * 0.5 > 0.14)
	# inside the windscreen, and clear of the roof's shell
	var screen := []
	for i in 61:
		for j in 31:
			var u := lerpf(0.5, 1.0, i / 60.0)
			var w := lerpf(0.6, 1.0, j / 30.0)
			screen.append([Reflection.screen(u, w), Reflection.facing(u, w)])
	var roof := (v.canopy.get_node("roof") as MeshInstance3D)
	var shell: PackedVector3Array = roof.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var inside := INF
	var from_roof := INF
	var pod_r: Node3D = p.pods[1.0]          # (the left one is its mirror image)
	for part: MeshInstance3D in pod_r.find_children("*", "MeshInstance3D", true, false):
		if part.name == "Clamps":
			continue                             # the clamps go up to the rail and round it: that is what they are
		var to_canopy: Transform3D = v.canopy.global_transform.affine_inverse() * part.global_transform
		var points: PackedVector3Array = part.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for k in range(0, points.size(), 3):
			var q := to_canopy * points[k]
			var nearest := INF
			var side := 0.0
			for sample: Array in screen:
				var d2 := q.distance_squared_to(sample[0])
				if d2 < nearest:
					nearest = d2
					side = (q - (sample[0] as Vector3)).dot(sample[1])
			inside = minf(inside, side)
			for r in range(0, shell.size(), 2):
				from_roof = minf(from_roof, q.distance_squared_to(shell[r] + roof.position))
	_check("a pod is wholly inside the windscreen (nearest point %.0f mm in from the glass) and off the roof's shell (%.0f mm from its nearest vertex)" % [inside * 1000.0, sqrt(from_roof) * 1000.0], inside > 0.004 and sqrt(from_roof) > 0.004)
	var outside := 0
	for node in p.find_children("*", "GeometryInstance3D", true, false):
		outside += int(node.is_in_group("exterior"))
	_check("its %d parts are the roof's, not the hull's fittings" % outside, outside == p.find_children("*", "GeometryInstance3D", true, false).size() and outside > 20)


func _run() -> void:
	_logic()
	_sounds()

	# a cockpit built any way but from the menu is running, as it always was
	v = _cockpit()
	await process_frame
	_check("a cockpit not chosen from the menu starts running: nothing held, the panel showing it", v.startup.is_hot() and v.startup.cleared and not v.craft.held[0] and v.craft.energised == 1.0)
	_panel()
	if v.overhead == null:
		print("STARTUP FAIL (no panel: %d failures)" % failures)
		quit(1)
		return
	_check("on a running craft BATT and ENGINE are up, PARK is down, the guard is shut and the ring is green",
		v.overhead.swings.batt < 0.0 and v.overhead.swings.engine < 0.0 and v.overhead.swings.park > 0.0 and v.overhead.guard_swing < 0.01
		and v.overhead.ring_colour.g > 1.0 and v.overhead.ring_progress == 1.0 and (v.overhead.lamps.park as StandardMaterial3D).albedo_color == Color.BLACK)
	v.queue_free()
	await process_frame

	# chosen from the menu: parked, cold and dark
	Cockpit.cold_on_entry = true
	v = _cockpit()
	for i in 4:
		await process_frame            # its own _process, a few real frames
	var s = v.startup
	_check("a flight chosen from the menu begins cold and dark, and the menu's word is used up", not s.batt and not s.master and s.park and s.stage == ["off", "off"] and not Cockpit.cold_on_entry)
	var dark := 0
	for name: String in v.dashboard.lamps:
		dark += int((v.dashboard.lamps[name] as Color).a == 0.0)
	var rim: Color = v.interior.rim_mat.albedo_color
	_check("dark: no lamp of the cluster's %d is lit, its strips are blank, its needles lie on their stops, the rim light is out, the map is off, the glass is blank" % v.dashboard.lamps.size(),
		dark == v.dashboard.lamps.size() and not (v.dashboard.labels.mach as Label3D).visible and v.dashboard.values.thrL == 0.0 and rim.r + rim.g + rim.b == 0.0
		and not v.minimap_panel.live and v.approach_display.message == "")
	var glass = v.approach_display
	_check("... and none of the checklist's drawing is up or running (the sheet hidden, the projector idle)", not glass.sheet.visible and glass.checklist.is_empty() and not glass.is_processing())
	_check("cold: both engines dark, the binder dead (no arc, its emitters and the cables unlit), the strobes out; parked: her air brakes out full (%.2f / %.2f, the pod's %.2f)" % [v.craft.flap_open[0], v.craft.flap_open[1], v.craft.pod_flap_open],
		v.craft.held[0] and v.craft.held[1] and v.craft.energised == 0.0 and (v.craft.binder_arc.mesh as ArrayMesh).get_surface_count() == 0
		and v.craft.cable_mats[0].emission_energy_multiplier == 0.0 and v.craft.binder_mats[0].albedo_color.b == 0.0 and not v.craft.lights_on and not v.craft.strobes[0].visible
		and v.craft.flap_open[0] > 0.99 and v.craft.flap_open[1] > 0.99 and v.craft.pod_flap_open > 0.99)
	_check("the panel shows it: BATT and ENGINE down, PARK up, only the standby lamp alight",
		v.overhead.swings.batt > 0.0 and v.overhead.swings.engine > 0.0 and v.overhead.swings.park < 0.0
		and (v.overhead.lamps.standby as StandardMaterial3D).albedo_color.g > 0.0 and (v.overhead.lamps.batt as StandardMaterial3D).albedo_color == Color.BLACK
		and v.overhead.ring_colour.r + v.overhead.ring_colour.g + v.overhead.ring_colour.b == 0.0 and (v.overhead.lamps.park as StandardMaterial3D).albedo_color == Color.BLACK)
	v.set_process(false)
	hand = Node3D.new()
	root.add_child(hand)
	var at0 := Vector2(v.sim.pod.x, v.sim.pod.y)
	_fly(3.0, [1.0, 1.0])
	_check("both levers full for 3 s with everything off: she has not moved (%.2f m, %.2f m/s)" % [at0.distance_to(Vector2(v.sim.pod.x, v.sim.pod.y)), _speed()],
		at0.distance_to(Vector2(v.sim.pod.x, v.sim.pod.y)) < 0.5 and _speed() < 0.2 and v.dashboard.values.thrL == 0.0)
	if v.engine_audio:
		_check("... and the engines are silent, the rotor's rumble with them (v8 %.4f, rotor %.4f, turbine %.4f)" % [_gain(0, "v8"), _gain(0, "rotor"), _gain(1, "turbine")],
			_gain(0, "v8") < 0.001 and _gain(1, "v8") < 0.001 and _gain(0, "rotor") < 0.001 and _gain(1, "roar") < 0.001)

	# 1 BATT
	_check("a hand flicks 1 BATT up: \"%s\"" % _work(_flick("batt", 1)), s.batt)
	_check("the same hand cannot throw the switch beside it in the same sweep (a rest between throws on a pod)", _flick("engine", 1).is_empty())
	_fly(0.7)
	_check("the bus comes up: the glass opens on the checklist (%.2f s up), its sheet drawn under the type with a pointer of its own in the gutter, the rail's first segment being wiped full (%.2f)" % [glass.clock, glass.ticked],
		glass.sheet.visible and glass.panel.visible and glass.checklist.done == 1 and glass.clock > 0.1 and glass.clock < 0.6 and glass.ticked > 0.0 and glass.ticked < 1.0
		and float(glass.surface.get_shader_parameter("pointer")) == 0.0 and absf(float(glass.sheet_mat.get_shader_parameter("age")) - glass.clock) < 0.001)
	_fly(Sequence.SELFTEST_S * 0.5 - 0.7)
	var bus: Vector2 = glass.sheet_mat.get_shader_parameter("bars")
	_check("half way through the self-test its bar is half way across the glass (%s), the page is written in full (%.2f) and the pointer beats at %.2f Hz toward the left pod" % [bus, glass.typing, Projector.BEAT_HZ],
		absf(bus.x - 1.0) < 0.05 and bus.y < 0.05 and glass.typing == 1.0 and glass.action.text == "ENGINE POWER" and float(glass.sheet_mat.get_shader_parameter("aim")) == -1.0
		and float(glass.sheet_mat.get_shader_parameter("ask")) == 1.0 and Projector.BEAT_HZ < 3.0)
	var telltales := ["burner", "armed", "ramjet", "turbines", "flameoutL", "flameoutR", "hotL", "hotR"]
	_check("the self-test: every telltale lit (%d of %d), every needle half way up its sweep and back (mach %.2f, heat %.2f), eights in the speed" % [_lit(telltales), telltales.size(), v.dashboard.values.mach, v.dashboard.values.heatL],
		_lit(telltales) == telltales.size() and v.dashboard.values.mach > 0.9 and is_equal_approx(v.dashboard.values.mach, v.dashboard.values.heatL) and v.dashboard._speed == 8888)
	_fly(Sequence.SELFTEST_S * 0.5 + 0.2)
	rim = v.interior.rim_mat.albedo_color
	_check("then the cockpit is alive: instruments lit and reading (needles down, no warning lamps, speed 0), rim light on, map on, strobes flashing, the checklist on the glass: %s" % v.approach_display.message.replace("\n", " / "),
		(v.dashboard.lamps.backlight as Color).a > 0.0 and _lit(telltales) == 0 and v.dashboard.values.mach < 0.01 and v.dashboard._speed == 0 and rim.b > 0.5 and v.minimap_panel.live
		and v.craft.lights_on and v.approach_display.message.contains("ENGINE POWER  2 / 5") and (v.dashboard.labels.progress as Label3D).text.contains("LIFT THE RED GUARD"))
	_fly(0.2)
	# 2 ENGINE
	_check("2 ENGINE: a flick lifts the guard: \"%s\"" % _work(_flick("engine", 1)), s.guard_open and not s.master)
	_fly(0.1)
	_check("... and a sweep crosses the middle line as its words change (%.2f of the way; \"%s\")" % [glass.sweeping, glass.route.text], glass.sweeping > 0.05 and glass.sweeping < 0.5 and glass.route.text.contains("FLICK 2 ENGINE UP") and glass.ticking == 0.0)
	_fly(0.6)
	_check("... it swings up (%.0f degrees), and the next flick throws the switch: \"%s\"" % [rad_to_deg(v.overhead.guard_swing), _work(_flick("engine", 1))], s.master and v.overhead.guard_swing > 1.5)
	_fly(0.1)
	_check("the step is ticked off before the next is shown: its page stays on the glass (\"%s\", though the sequence has moved on to \"%s\"), its segment of the rail being wiped (%.2f), the pointer still" % [glass.action.text, glass.message.split("\n")[0], glass.ticked],
		glass.ticking > 0.0 and glass.action.text == "ENGINE POWER" and glass.message.contains("START ENGINES") and glass.ticked > 0.0 and glass.ticked < 0.5 and glass.checklist.done == 2
		and float(glass.sheet_mat.get_shader_parameter("ask")) == 0.0)
	_fly(Projector.TICK_TIME + 0.05)
	_check("... then the next step's page is written, line by line (\"%s\", %.2f of the way in: the top line %.2f, the foot %.2f)" % [glass.action.text, glass.typing, glass.action.modulate.a, glass.advice.modulate.a],
		glass.ticking == 0.0 and glass.action.text == "START ENGINES" and glass.typing > 0.0 and glass.typing < 0.6 and glass.action.modulate.a > glass.advice.modulate.a)
	_fly(Sequence.CHARGE_S + 0.3 - 0.15 - Projector.TICK_TIME)
	_check("the binder strikes between the engines, its emitters alight (charge %.2f, core %.2f); the guard has fallen shut; the ring round START breathes" % [v.craft.energised, v.craft.binder_mats[0].albedo_color.b],
		v.craft.energised == 1.0 and (v.craft.binder_arc.mesh as ArrayMesh).get_surface_count() > 0 and v.craft.binder_mats[0].albedo_color.b > 0.3 and not s.guard_open
		and v.overhead.ring_colour.r > 0.2 and v.overhead.ring_progress == 1.0)
	# 3 START
	_check("3 START: the button pressed: \"%s\"" % _work(_press()), s.stage[0] != "off")
	_fly(0.6)
	_check("the left engine turns over (the right hand's, with crossed triggers: rumble %.2f there) and has not lit; the ring has begun to fill (%.2f)" % [v.startup_rumble(0), v.overhead.ring_progress],
		s.stage == ["crank", "wait"] and v.craft.held[0] and v.startup_rumble(0) > 0.1 and v._hand_engine(1) == 0 and v._engine_hand(0) == v.hands.right
		and v.overhead.ring_progress > 0.02 and v.overhead.ring_progress < 0.2)
	bus = glass.sheet_mat.get_shader_parameter("bars")
	_check("... and the glass has a bar for each engine, the left one filling (%.2f, %.2f)" % [bus.x, bus.y], bool(glass.sheet_mat.get_shader_parameter("pair")) and bus.x > 0.1 and bus.x < 0.4 and bus.y == 0.0 and glass.action.text == "STARTING")
	if v.engine_audio:
		_check("... its voice turning at cranking speed (spool %.2f), the right one still silent (%.4f)" % [v.engine_audio.voices[0].spool, _gain(1, "v8")],
			v.engine_audio.crank[0] and v.engine_audio.voices[0].spool > -0.3 and v.engine_audio.voices[0].spool < -0.1 and _gain(1, "v8") < 0.001 and v.startup_audio.played.has("starter"))
	_fly(Sequence.CRANK_S - 0.6 + Sequence.CATCH_S * 0.5)
	_check("it catches: a burst of flame at its nozzle (thrust shown %.2f), and no thrust in the sim (%.3f)" % [v.craft.shown_thrust[0], v.sim.eL.thrust],
		s.stage[0] == "catch" and not v.craft.held[0] and v.craft.flames[0].visible and v.craft.shown_thrust[0] > 0.4 and v.sim.eL.thrust < 0.01)
	_check("... and its bar flares (%.2f)" % (glass.sheet_mat.get_shader_parameter("flare") as Vector2).x, (glass.sheet_mat.get_shader_parameter("flare") as Vector2).x > 0.9)
	_fly(Sequence.STAGGER_S + Sequence.CATCH_S + 0.3)
	_check("both running, the ring green, a pilot light in each nozzle, and the glass asks for the run-up: %s" % v.approach_display.message.replace("\n", " / "),
		s.all_running() and v.overhead.ring_colour.g > 1.0 and v.overhead.ring_progress == 1.0 and v.craft.flames[0].visible and v.craft.flames[1].visible and v.approach_display.message.contains("RUN-UP  4 / 5"))
	if v.engine_audio:
		_check("... and both idling: v8 %.3f / %.3f at spool %.2f" % [_gain(0, "v8"), _gain(1, "v8"), v.engine_audio.voices[0].spool], _gain(0, "v8") > 0.05 and _gain(1, "v8") > 0.05 and v.engine_audio.voices[0].spool > -0.05)
		var heard: Array[String] = v.startup_audio.played
		_check("what was heard on the way, in order: %s" % ", ".join(heard),
			heard.find("toggle_on") < heard.find("power") and heard.find("power") < heard.find("guard_up") and heard.has("guard_down") and heard.find("guard_up") < heard.find("pump")
			and heard.has("arc") and heard.find("arc") < heard.find("button") and heard.count("starter") == 2 and heard.count("catch") == 2 and heard.find("starter") < heard.find("catch")
			and not heard.has("refuse"))
		var at_left: Node = v.startup_audio.players.toggle_on[0]
		var at_right: Node = v.startup_audio.players.button[0]
		_check("a switch's sound comes from its own pod (BATT's from the left, START's from the right), a starter from its engine",
			at_left is AudioStreamPlayer3D and at_left.get_parent() == v.overhead.pods[-1.0] and at_right is AudioStreamPlayer3D and at_right.get_parent() == v.overhead.pods[1.0]
			and v.startup_audio.players.guard_up[0].get_parent() == v.overhead.pods[-1.0] and v.startup_audio.players.paddle_on[0].get_parent() == v.overhead.pods[1.0]
			and (v.startup_audio.players.starter as Array).size() == 2 and (v.startup_audio.players.catch as Array).size() == 2)
		var fans: float = v.startup_audio.hum_gain
		_fly(4.0)
		_check("the fans' loop, heard on the battery (%.2f as the engines came up), has gone under them (%.3f)" % [fans, v.startup_audio.hum_gain], fans > v.startup_audio.hum_gain and v.startup_audio.hum_gain < 0.05)
	# 4 PARK: the run-up
	at0 = Vector2(v.sim.pod.x, v.sim.pod.y)
	_fly(0.5, [1.0, 0.0])
	_check("the run-up, the left lever alone: its dial reads it (%.2f, the right %.2f), its nozzle burns (%.2f) and its cable glows (%.1f), its hand rumbles (%.2f); the right engine idles" % [v.dashboard.values.thrL, v.dashboard.values.thrR, v.craft.shown_thrust[0], v.craft.cable_mats[0].emission_energy_multiplier, v.startup_rumble(0)],
		v.dashboard.values.thrL > 0.9 and v.dashboard.values.thrR < 0.05 and v.craft.shown_thrust[0] > 0.9 and v.craft.shown_thrust[1] < 0.1 and v.craft.cable_mats[0].emission_energy_multiplier > 1.0
		and v.startup_rumble(0) > 0.4 and v.startup_rumble(1) == 0.0 and s.checks.thrL and not s.checks.thrR)
	_check("the brake holds both engines' air brakes out to their full extent: the flaps (%.2f / %.2f, the pod's %.2f), the brake needles (%.2f / %.2f), and what the sim is given (%.1f / %.1f) with no grip squeezed" % [v.craft.flap_open[0], v.craft.flap_open[1], v.craft.pod_flap_open, v.dashboard.values.brkL, v.dashboard.values.brkR, s.gate(v.inp).brkL, s.gate(v.inp).brkR],
		v.craft.flap_open[0] > 0.99 and v.craft.flap_open[1] > 0.99 and v.craft.pod_flap_open > 0.99 and v.dashboard.values.brkL > 0.99 and v.dashboard.values.brkR > 0.99
		and v.inp.brkL == 0.0 and s.gate(v.inp).brkL == 1.0 and s.gate(v.inp).brkR == 1.0)
	_fly(0.5, [0.0, 1.0])
	_check("the run-up asks for a shift (first gear, trigger throttles): %s" % v.approach_display.message.split("\n")[1], s.gears and v.quest.display_gear() == 1 and s.checks.thrR and not s.checks.gear and v.approach_display.message.contains("GEAR --"))
	v.quest.set_gear(2)
	_fly(0.3)
	_check("second gear taken: ticked, and the centre dial shows it", s.checks.gear and v.dashboard._gear == 2)
	v.quest.set_gear(1)
	_fly(Sequence.TURBINE_UP_S + 0.3, [1.0, 1.0])
	_check("both levers held: the turbines reach their test speed and the TURBINES lamp lights; the cockpit trembles (%.1f mm)" % (v._startup_shake(0.0).length() * 1000.0), s.checks.turbines and v._turbine_lamp and _lit(["turbines"]) == 1 and v._run_shake > 0.5)
	if v.engine_audio:
		_check("... the engines revving to the levers (spool %.2f) with the turbines in (stage %.2f, whine %.3f), the V8 calmed (temper %.2f)" % [v.engine_audio.voices[0].spool, v.engine_audio.stage, _gain(0, "turbine"), v.engine_audio.anger],
			v.engine_audio.voices[0].spool > 0.8 and v.engine_audio.stage > 0.7 and _gain(0, "turbine") > 0.05 and v.engine_audio.anger < 0.3)
	_check("through all of it she has not moved (%.2f m, %.2f m/s), and the glass says so: %s" % [at0.distance_to(Vector2(v.sim.pod.x, v.sim.pod.y)), _speed(), v.approach_display.message.replace("\n", " / ")],
		at0.distance_to(Vector2(v.sim.pod.x, v.sim.pod.y)) < 0.5 and _speed() < 0.2 and v.approach_display.message.contains("RELEASE PARK BRAKE  5 / 5"))
	_check("standing on the brake with the engines run up, the g-meter reads the seat's own 1 g (%.2f; the needle %.2f of its scale)" % [v.g_load(), v.dashboard.values.g], absf(v.g_load() - 1.0) < 0.02 and absf(v.dashboard.values.g - 0.150) < 0.01)
	_fly(Sequence.TURBINE_DOWN_S + 0.5)
	_check("levers back: the turbines wind down and their lamp goes out", not v._turbine_lamp and _lit(["turbines"]) == 0)
	_check("a hand flicks 4 PARK down: \"%s\"" % _work(_flick("park", -1)), not s.park and s.is_hot())
	_fly(2.0, [1.0, 1.0])
	_check("and she flies: %.0f m/s after 2 s of full levers, the fire the sim's own again (%.2f), the air brakes stowed (%.2f / %.2f, needles %.2f / %.2f)" % [_speed(), v.craft.shown_thrust[0], v.craft.flap_open[0], v.craft.flap_open[1], v.dashboard.values.brkL, v.dashboard.values.brkR],
		_speed() > 20.0 and s.cleared and v.craft.shown_thrust[0] < 0.0 and v.craft.flap_open[0] < 0.01 and v.craft.flap_open[1] < 0.01 and v.dashboard.values.brkL < 0.01)
	_check("CLEARED is on the glass, landed at once and larger than it stays (now %.2f of its size, %.1f s on; it came in at %.2f), the rail lit along its length" % [glass.action.scale.x, glass.checklist.cleared, Projector.arrival(0.0)],
		glass.action.text == "CLEARED" and glass.checklist.done == 5 and glass.checklist.cleared > 1.5 and glass.action.scale.x == 1.0 and Projector.arrival(0.0) > 1.2 and Projector.arrival(0.2) > 1.0
		and float(glass.sheet_mat.get_shader_parameter("cleared")) > 1.5 and glass.sheet.visible)
	var mean_g: float = _speed() / 2.0 / 9.81
	_check("the g-meter has the launch: %.1f g along the craft now (%.1f on average over the 2 s) and %.1f across, %.1f g in all on the dial (%.2f of its scale; the tell-tale at %.1f)" % [v.g_along, mean_g, v.g_across, v.g_load(), v.dashboard.values.g, v.dashboard.g_peak],
		v.g_along > 0.3 * mean_g and v.g_along < 3.0 * mean_g and absf(v.g_across) < 0.1 * maxf(v.g_along, 10.0) and v.g_load() > 1.0
		and absf(v.dashboard.values.g - minf(log(1.0 + v.g_load()) / log(101.0), 1.035)) < 0.01 and v.dashboard.g_peak >= v.g_load() - 0.01)
	_fly(Sequence.CLEARED_S - 2.0 + Projector.CLOSE_TIME + 0.2, [1.0, 1.0])
	_check("then the checklist is put away with the glass: the sheet hidden, the gutter's arrow given back, the top line its own size, and nothing of it running", not glass.sheet.visible and glass.checklist.is_empty()
		and float(glass.surface.get_shader_parameter("pointer")) == 1.0 and glass.action.scale == Vector3.ONE and (glass.message != "" or (not glass.panel.visible and not glass.is_processing())))
	var mph := _speed() * 2.236936
	var answer := _work(_flick("park", 1))
	_check("at %.0f mph the brake is refused: \"%s\"" % [mph, s.refusal], answer == "refused" and not s.park)
	v._respawn()
	_check("a restart is a restart: still running, nothing to do over", s.is_hot() and s.cleared)

	# the pilot's choice
	var at_menu := -1
	v.menu.items = v._menu_items()
	for i in v.menu.items.size():
		if v.menu.items[i].key == "startup":
			at_menu = i
	_check("the quick menu has COLD START, ON", at_menu >= 0 and v.menu.items[at_menu].label == "COLD START" and v.menu.items[at_menu].value == "ON")
	v.menu.at = at_menu
	v.menu_choose()
	_check("chosen, it is OFF and saved", not Cockpit.cold_start and v._load_prefs().get("startup", "") == "hot" and v.menu.items[at_menu].value == "OFF")
	hand.queue_free()
	v.queue_free()
	await process_frame
	Cockpit.cold_on_entry = true
	v = _cockpit()
	await process_frame
	_check("with COLD START off a flight chosen from the menu starts running", v.startup.is_hot())
	Cockpit.cold_start = true
	v._save_prefs()
	v.queue_free()
	await process_frame
	print("STARTUP %s (%d checks, %d failures)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)
