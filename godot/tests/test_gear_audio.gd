## Exercises the real view-to-audio path. Higher gears wind up more slowly,
## finish at higher notes, and still drop promptly on an upshift.
extends SceneTree

const Sim := preload("res://sim/craft_sim.gd")
const View := preload("res://view/craft_view.gd")
const EngineSound := preload("res://audio/engine_audio.gd")
const Controls := preload("res://input/quest_controls.gd")
const DT := 1.0 / 120.0
var failures := 0
var checks := 0
var audio
var view
var sim

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	sim = Sim.new({"track": "range"})
	view = View.new()
	view.sim = sim
	audio = EngineSound.new()
	root.add_child(audio)
	audio.setup(sim)
	var primary := []
	var secondary := []
	var v8_ceilings := []
	var v12_ceilings := []
	var second_ceilings := []
	var rotor_pitch := []
	for gear in 5:
		_reset()
		var trace: Array = await _trace(gear, 1.0, 1440)
		primary.append(_metrics(trace, 0))
		secondary.append(_metrics(trace, 1))
		v8_ceilings.append(float(audio.voices[0].at.v8))
		v12_ceilings.append(float(audio.voices[0].at.v12))
		second_ceilings.append(float(audio.voices[0].at.second))
		rotor_pitch.append(float(audio.voices[0].at.rotor))
		await _trace(gear, 1.0, 120, 0.0)
		_check("gear %d winds down both piston voices promptly on throttle release" % (gear + 1),
			audio.voices[0].spool < trace[-1][0] * 0.5 and audio.voices[0].sec.spool < trace[-1][1] * 0.5)
	for gear in range(1, 5):
		_check("gear %d reaches higher primary and secondary RPM ceilings" % (gear + 1),
			v8_ceilings[gear] > v8_ceilings[gear - 1] + 400.0 and
			v12_ceilings[gear] > v12_ceilings[gear - 1] + 600.0 and
			second_ceilings[gear] > second_ceilings[gear - 1] + 200.0)
		_check("gear %d takes longer to wind up both piston voices" % (gear + 1),
			primary[gear].rise90 > primary[gear - 1].rise90 * 1.2 and
			secondary[gear].rise90 > secondary[gear - 1].rise90 * 1.2)
		_check("gear %d has a slower maximum RPM climb in both piston voices" % (gear + 1),
			primary[gear].rate < primary[gear - 1].rate * 0.85 and
			secondary[gear].rate < secondary[gear - 1].rate * 0.85)
		_check("gear %d leaves the airspeed-driven rotor pitch alone" % (gear + 1),
			absf(rotor_pitch[gear] - rotor_pitch[0]) < 0.001)
	# Starfighter uses profile 0; Speedcraft shifts only between profiles 1-4.
	for gear in range(1, 4):
		_reset()
		await _trace(gear, 0.95, 1440)
		var before: float = audio.voices[0].at.v8
		var second_before: float = audio.voices[0].at.second
		var next_revs: float = 0.95 * Controls.GEARS[gear][2] / Controls.GEARS[gear + 1][2]
		await _trace(gear + 1, next_revs, 120)
		_check("Speedcraft upshift %d -> %d drops both engine notes within a second" % [gear, gear + 1],
			audio.voices[0].at.v8 < before * 0.98 and audio.voices[0].at.second < second_before * 0.98)
	_reset()
	var legacy: Array = await _trace(-1, 1.0, 120, float(sim.P.gate))
	_check("desktop without a gearbox keeps its original fast rev and flare",
		_metrics(legacy, 0).rise90 < 0.2 and _peak(legacy, 0) > 1.04)
	_check("desktop without a gearbox retains its original RPM ceiling",
		absf(audio.voices[0].at.v8 - 7600.0) < 50.0)
	_check("audio mapping never changes the physics input",
		view.inp.thrL == sim.P.gate and not view.inp.has("gearIndex"))
	_reset()
	await _trace(4, 1.0, 1440)
	var normal: float = audio.voices[0].spool
	sim.mode = "burner"
	await _trace(4, 1.0, 360)
	_check("afterburner still raises RPM beyond Speedcraft fourth's normal ceiling",
		audio.voices[0].spool > normal + 0.1 and audio.voices[0].burn > 0.99)
	sim.mode = "ramjet"
	await _trace(4, 1.0, 360)
	_check("ramjet still raises RPM beyond the afterburner", audio.voices[0].spool > normal + 0.25)
	sim.mode = "normal"
	await _trace(4, 1.0, 120, 0.87, true)
	_check("repair still limits the running engine note", audio.voices[0].spool < 0.65)
	sim.eL.flameout = true
	await _trace(4, 1.0, 600)
	_check("flameout still winds the failed side below idle without stopping the healthy side",
		audio.voices[0].spool < -0.28 and audio.voices[0].fire < 0.001 and audio.voices[1].spool > 0.9)
	sim.eL.flameout = false
	await _trace(4, 1.0, 120)
	_check("relight still brings the failed side above idle", audio.voices[0].spool > 0.0 and audio.voices[0].fire > 0.1)
	print("GEAR AUDIO METRICS: V8 RPM=", v8_ceilings, " primary=", primary, " secondary=", secondary)
	view.free()
	view = null
	for child in audio.get_children():
		if child is AudioStreamPlayer:
			child.stop()
	audio.queue_free()
	await process_frame
	audio = null
	sim = null
	await process_frame
	print("GEAR AUDIO %s (%d checks, %d failures)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)

## Begin from already-running, idling engines at the same airspeed. Startup timing and
## the right engine's stagger belong to the existing engine capture regression.
func _reset() -> void:
	sim.mode = "normal"
	sim.eL.flameout = false
	sim.eR.flameout = false
	sim.pod.vx = 1600.0 / 2.23694
	sim.pod.vy = 0.0
	audio.second_on = true
	for voice in audio.voices:
		voice.spool = 0.0
		voice.spool_v = 0.0
		voice.lever_prev = 0.0
		voice.sec.state = "run"
		voice.sec.spool = 0.0
		voice.sec.vel = 0.0
		voice.rotor_mph = 0.0

func _trace(gear: int, revs: float, frames: int, lever := 0.87, repair := false) -> Array:
	var trace := []
	for frame in frames:
		view.inp = {"thrL": lever, "thrR": lever, "repair": repair}
		if gear >= 0:
			view.inp.gearRpm = revs
			view.inp.gearIndex = gear
		audio.update(view._engine_inp(), DT)
		trace.append([float(audio.voices[0].spool), float(audio.voices[0].sec.spool)])
		# Let the audio server drain updates instead of queuing the entire probe in one frame.
		if frame % 120 == 119:
			await process_frame
	return trace

func _metrics(trace: Array, column: int) -> Dictionary:
	var reached := trace.size() * DT
	var fastest := 0.0
	var previous := 0.0
	for frame in trace.size():
		if trace[frame][column] >= trace[-1][column] * 0.9:
			reached = minf(reached, (frame + 1) * DT)
		fastest = maxf(fastest, (trace[frame][column] - previous) / DT)
		previous = trace[frame][column]
	return {"rise90": reached, "rate": fastest}

func _peak(trace: Array, column: int) -> float:
	var peak := 0.0
	for row in trace:
		peak = maxf(peak, row[column])
	return peak

func _check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
	print(("PASS " if passed else "FAIL ") + label)
