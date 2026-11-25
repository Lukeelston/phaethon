## One craft on its service stands. Flight owns the same StartupSequence once the
## pilot departs. The hull and nacelle transforms belong exclusively to the stands.
extends Node3D

const Airframe := preload("res://garage/parked_airframe.gd")
const Flight := preload("res://sim/craft_sim.gd")
const Fleet := preload("res://sim/pilot_craft.gd")
const Sequence := preload("res://vr/startup_sequence.gd")
const EngineVoice := preload("res://audio/engine_audio.gd")
const SwitchVoice := preload("res://audio/startup_audio.gd")
const NEUTRAL := {"thrL": 0.0, "thrR": 0.0, "brkL": 0.0, "brkR": 0.0}
const EXTERIOR_TICK := 1.0 / 15.0

var startup: Sequence
var operated := false
var switch_settings := {}
var controls := NEUTRAL.duplicate()
var telemetry := {
	"handling": "speed", "slide": true, "gear": 0, "overdrive": false, "mode": "normal", "armed": false, "gate": 0.88,
	"heat": [0.0, 0.0], "health": [1.0, 1.0], "strain": [0.0, 0.0],
	"thrust": [0.0, 0.0], "flameout": [false, false], "battery": 1.0,
}
var sim: Flight
var seated := false
var _airframe: Airframe
var _reported_stages: Array[String] = ["off", "off"]
var _vehicle := ""
var _elapsed := 0.0
var _arc_elapsed := 0.0
var _settling := 0.0
var _engine_audio: SeatVoice
var _switch_audio: SwitchVoice
var _anchors := {}
var _engine_mounts: Array[Node3D] = []
var _outside: Array[AudioStreamPlayer3D] = []
var _exterior_screening := 0.0
var _muted := OS.get_cmdline_user_args().has("--mute")


## Decode the full cockpit mix a few milliseconds at a time. The wake signal lives
## on the voice itself, so dismounting cancels even an unfinished bank cleanly.
class SeatVoice extends EngineVoice:
	signal next_slice
	var prepared := false
	var _until_usec := 0

	func prepare(craft: Flight, sequence: Sequence) -> void:
		_until_usec = Time.get_ticks_usec() + 1800
		await setup(craft, _checkpoint)
		for k in 2:
			if sequence.stage[k] not in ["catch", "run"]:
				var voice: Dictionary = voices[k]
				voice.spool = -0.33
				voice.fire = 0.0
				voice.alive = 0.0
				voice.was_held = true
		prepared = true
		set_process(false)

	func _checkpoint() -> void:
		if Time.get_ticks_usec() >= _until_usec:
			await next_slice

	func _process(_delta: float) -> void:
		_until_usec = Time.get_ticks_usec() + 1800
		next_slice.emit()


## Load cabin sounds while the pilot approaches a bay. All vehicles share the
## switchgear. A scene change cancels any work still pending between frames.
static func prewarm_switches(garage: Node) -> void:
	if OS.get_cmdline_user_args().has("--mute"):
		return
	var tree := garage.get_tree()
	for sound: String in SwitchVoice.NAMES:
		await tree.process_frame
		if not is_instance_valid(garage) or not garage.is_inside_tree():
			return
		SwitchVoice.load_sound(sound)


func setup(airframe: Airframe, incoming: Sequence = null) -> void:
	_airframe = airframe
	_vehicle = airframe.sim.P.vehicle
	# The range preset creates the three production bodies without a circuit or road
	# network. Their step is never called, so yaw, speed and position stay fixed.
	sim = Flight.new({"track": "range", "vehicle": _vehicle})
	telemetry.gate = sim.P.gate
	telemetry.battery = sim.battery
	set_startup(incoming)


func set_startup(incoming: Sequence) -> void:
	startup = incoming
	if startup == null:
		operated = false
		startup = Sequence.new()
		startup.cold()
	else:
		operated = true
	controls = NEUTRAL.duplicate()
	_settling = 2.0
	_apply_hardware(1.0)
	if seated and not _muted and startup.batt:
		_open_cockpit_audio()
	set_process(true)


func set_seated(value: bool, pods := {}) -> void:
	if seated == value:
		return
	seated = value
	controls = NEUTRAL.duplicate()
	_elapsed = 0.0
	if seated:
		for side in pods:
			var anchor := Node3D.new()
			add_child(anchor)
			anchor.global_transform = (pods[side] as Node3D).global_transform
			_anchors[side] = anchor
		if not _muted and (startup.batt or startup.starting() or startup.all_running()):
			_open_cockpit_audio(startup.master or startup.assisting)
	else:
		_close_cockpit_audio()
		_exterior_sound()
	set_process(true)


func set_controls(values: Dictionary) -> void:
	if not seated:
		return
	for field in NEUTRAL:
		var amount := clampf(float(values.get(field, 0.0)), 0.0, 1.0)
		if not is_equal_approx(amount, controls[field]):
			controls[field] = amount
			if not startup.batt:
				_settling = 2.0
				set_process(true)
	telemetry.gear = int(values.get("gearIndex", values.get("gear", 0)))
	telemetry.overdrive = bool(values.get("gearOverdrive", false))


## Physical controls use the panel's original signed flick; dir=0 on PARK is the shortcut.
func work(control: String, dir := 0) -> String:
	if not seated:
		return ""
	if control in ["handling", "slide"]:
		if dir == 0:
			return ""
		if control == "handling":
			apply_switches({"handling": "starfighter" if dir > 0 else "speed"})
		else:
			apply_switches({"slide": dir > 0})
		return control
	if control not in ["power", "batt", "engine", "start", "park"]:
		return ""
	if not _muted:
		_open_cockpit_audio(control == "power" or (control == "start" and startup.master))
	set_process(true)
	_settling = 2.0
	if control == "power":
		operated = true
		return startup.power_shortcut()
	var direction := dir
	if control == "park" and direction == 0:
		direction = -1 if startup.park else 1
	var result := startup.press_start() if control == "start" else startup.flick(control, direction)
	if result not in ["", "refused", "dead"]:
		operated = true
	return result


## Only selectors actually moved are handed back to flight; the rest keep the pilot's preferences.
func apply_switches(settings: Dictionary) -> void:
	if settings.has("handling") and settings.handling in ["speed", "starfighter"]:
		switch_settings.handling = settings.handling
		telemetry.handling = settings.handling
		sim.set_handling(settings.handling)
	if settings.has("slide"):
		switch_settings.slide = bool(settings.slide)
		telemetry.slide = switch_settings.slide


func status_text() -> String:
	if startup == null:
		return ""
	if startup.assisting or startup.starting():
		return "Starting engines"
	if startup.all_running():
		var action := "Engine run-up" if maxf(controls.thrL, controls.thrR) > 0.08 else "Engines idling"
		return action + (" · Park brake set" if startup.park else " · Park brake released")
	if startup.master:
		return "Engine power on"
	if startup.batt:
		return "Battery on"
	if startup.power > 0.01 or startup.charge > 0.01:
		return "Shutting down"
	return "Power off"


func _process(delta: float) -> void:
	_elapsed += delta
	if not seated and _elapsed < EXTERIOR_TICK:
		return
	var dt := minf(_elapsed, 0.1)
	_elapsed = 0.0
	startup.step(dt, [controls.thrL, controls.thrR], telemetry.gear, [controls.brkL, controls.brkR])
	_apply_hardware(dt)
	if _switch_audio:
		for e in startup.events:
			_switch_audio.event(e, startup.school)
		_switch_audio.hum(startup.power, 0.5 * (float(startup.running(0)) + float(startup.running(1))), dt)
	startup.events.clear()
	if _engine_audio and _engine_audio.prepared:
		for k in 2:
			_engine_audio.off[k] = _airframe.model.held[k]
			_engine_audio.crank[k] = startup.stage[k] == "crank"
		_engine_audio.test_stage = startup.turbine if startup.held() else 0.0
		_engine_audio.update(controls, dt)
		for emitter in _outside:
			if emitter.playing:
				emitter.volume_db = move_toward(emitter.volume_db, -64.0, 250.0 * dt)
				if emitter.volume_db <= -64.0:
					emitter.stop()
	elif not seated:
		_exterior_sound()
	if not startup.batt and not startup.master and not startup.assisting:
		_settling = maxf(0.0, _settling - dt)
		if _settling == 0.0:
			if _engine_audio:
				_engine_audio.queue_free()
				_engine_audio = null
			set_process(false)


func _apply_hardware(delta: float) -> void:
	var model := _airframe.model
	model.energised = startup.charge
	model.lights_on = startup.power > 0.5
	for k in 2:
		if startup.stage[k] != _reported_stages[k]:
			_reported_stages[k] = startup.stage[k]
			_airframe.engine_stage_changed.emit(k, _reported_stages[k])
		var body := sim.eL if k == 0 else sim.eR
		var lever := float(controls.thrL if k == 0 else controls.thrR)
		model.held[k] = startup.stage[k] not in ["catch", "run"]
		var thrust := 0.0
		if startup.stage[k] == "catch":
			thrust = 0.06 + 0.5 * startup.catch_flare(k)
		elif startup.running(k):
			thrust = 0.05 + 0.95 * lever
		body.thrust = thrust
		telemetry.thrust[k] = thrust
		var glow := model.cable_glow(thrust, sim.hblend)
		model.cable_mats[k].emission = glow[1]
		model.cable_mats[k].emission_energy_multiplier = float(glow[0]) * startup.charge
	var actuators := startup.gate(controls).duplicate()
	actuators.park = startup.park
	model.sync_hardware(sim, actuators, delta)
	_arc_elapsed += delta
	if model.energised < 0.35:
		model.binder_arc.hide()
	elif _arc_elapsed >= EXTERIOR_TICK or not model.binder_arc.visible:
		model.binder_arc.show()
		model.sync_binder(sim, minf(_arc_elapsed, 0.1))
		_arc_elapsed = 0.0


func _open_cockpit_audio(engines := true) -> void:
	if _switch_audio == null:
		for engine in _airframe.model.engines:
			var anchor := Node3D.new()
			add_child(anchor)
			anchor.global_transform = (engine as Node3D).global_transform
			_engine_mounts.append(anchor)
		_switch_audio = SwitchVoice.new()
		add_child(_switch_audio)
		_switch_audio.setup(_anchors, _vehicle, _engine_mounts)
	if engines and _engine_audio == null:
		_engine_audio = SeatVoice.new()
		add_child(_engine_audio)
		_engine_audio.prepare(sim, startup)


func _close_cockpit_audio() -> void:
	if _engine_audio:
		_engine_audio.queue_free()
		_engine_audio = null
	if _switch_audio:
		_switch_audio.queue_free()
		_switch_audio = null
	for anchor in _engine_mounts:
		anchor.queue_free()
	_engine_mounts.clear()
	for anchor: Node3D in _anchors.values():
		anchor.queue_free()
	_anchors.clear()


func screen_exterior(amount: float) -> void:
	_exterior_screening = amount
	for emitter in _outside:
		_filter_exterior(emitter)


func _filter_exterior(emitter: AudioStreamPlayer3D) -> void:
	# The laminated window passes the idle's low rumble more readily than
	# bearing and exhaust detail. Scale the spatial reference distance so the
	# existing engine gain and its cockpit boarding fade can work independently.
	emitter.unit_size = 4.0 * db_to_linear(-3.0 * _exterior_screening)
	emitter.attenuation_filter_cutoff_hz = 5000.0 * pow(.12, _exterior_screening)


## When the pilot steps out, only two spatial idle loops remain in the hall.
## Both sounds originate at the actual parked engine, using that craft's low-bank take.
func _exterior_sound() -> void:
	if _muted:
		return
	var tuning: Vector2 = EngineVoice.FLEET_VOICES.get(_vehicle, {}).get("v8", Vector2.ONE)
	if _outside.is_empty():
		if not startup.running(0) and not startup.running(1):
			return
		var bank_dir := EngineVoice.DIR if _vehicle == Fleet.STANDARD else EngineVoice.FLEET_DIR % Fleet.sound_bank(_vehicle)
		var wav := (load(bank_dir + "v8_mip0.wav") as AudioStreamWAV).duplicate() as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_end = wav.get_length() * wav.mix_rate
		for engine in _airframe.model.engines:
			var emitter := AudioStreamPlayer3D.new()
			emitter.stream = wav
			_filter_exterior(emitter)
			emitter.max_distance = 34.0
			emitter.pitch_scale = float(EngineVoice.TUNE.v8_rpm[0]) / 800.0 * tuning.y
			add_child(emitter)
			emitter.global_position = (engine as Node3D).global_position
			_outside.append(emitter)
	for k in _outside.size():
		if startup.running(k):
			_outside[k].volume_db = -10.0 + linear_to_db(tuning.x)
			if not _outside[k].playing:
				_outside[k].play()
		elif _outside[k].playing:
			_outside[k].stop()
