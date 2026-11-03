## Real WindAudio update and Field-bus capture: a fixed sub-bass layer plus a separate
## airspeed tone, independent of gear/throttle/RPM, including speeds beyond the old top speed.
extends SceneTree

const Sim := preload("res://sim/craft_sim.gd")
const Wind := preload("res://audio/wind_audio.gd")
const DT := 1.0 / 120.0
const SPEEDS := [1500.0, 3000.0, 6000.0, 12000.0]
var sim
var wind
var fails := 0
var checks := 0
var output := ""

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			output = arg.get_slice("=", 1)
	_run.call_deferred()

func _run() -> void:
	sim = Sim.new({"track": "range"})
	wind = Wind.new()
	root.add_child(wind)
	wind.setup(sim)
	var low_hz := _peak_hz(wind.hum_player.stream, 20, 260)
	_check("the low shield layer has its dominant frequency at 30-40 Hz (%.0f Hz)" % low_hz,
		low_hz >= 30.0 and low_hz <= 40.0)
	var speed_player = wind.get("speed_player")
	_check("the speed tone is a separate playing voice", speed_player is AudioStreamPlayer and speed_player.playing)
	await _advance(1490.0, 2.0)
	_check("shield is open below engagement speed", not wind.sealed and wind.hum < 0.001 and wind.seal < 0.001)
	await _advance(1501.0, 0.5)
	_check("engagement still waits for the second-engine catch", wind.sealed and wind.hum < 0.001 and wind.seal < 0.001)
	await _advance(1501.0, 0.5)
	_check("the hum still rises before the wind seals", wind.hum > 0.4 and wind.seal < 0.01)
	await _advance(1501.0, 2.0)
	_check("the field still seals the wind", wind.hum > 0.99 and wind.seal > 0.99)
	var low_pitches := []
	var tones := []
	for mph in SPEEDS:
		await _advance(mph, 3.0)
		low_pitches.append(float(wind.hum_player.pitch_scale))
		if speed_player is AudioStreamPlayer:
			tones.append(float(speed_player.pitch_scale))
	for k in range(1, SPEEDS.size()):
		_check("low layer stays fixed at %.0f mph" % SPEEDS[k], absf(low_pitches[k] - low_pitches[0]) < 0.0001)
		if tones.size() == SPEEDS.size():
			_check("speed tone continues rising at %.0f mph" % SPEEDS[k], tones[k] > tones[k - 1] + 0.25)
	if speed_player is AudioStreamPlayer:
		await _advance(6000.0, 4.0)
		var steady: float = speed_player.pitch_scale
		var stable := true
		for gear in 5:
			for rpm in [0.0, 0.5, 1.08]:
				_tick(6000.0, DT, {"gearIndex": gear, "gearRpm": rpm, "thrL": rpm, "thrR": 1.0 - rpm})
				stable = stable and absf(speed_player.pitch_scale - steady) < 0.001
		_check("gear changes and RPM swings cannot reset or dip the shield tone", stable)
		await _advance(6000.0, 2.0, {"thrL": 0.0, "thrR": 0.0, "gearIndex": 4, "gearRpm": 0.0})
		_check("throttle lift at held airspeed keeps the shield tone and seal", absf(speed_player.pitch_scale - steady) < 0.001 and wind.seal > 0.99)
		await _advance(3000.0, 3.0)
		_check("actual deceleration lowers the speed tone", speed_player.pitch_scale < steady - 0.25)
	await _advance(1301.0, 2.0)
	_check("hysteresis holds the shield below its engagement speed", wind.sealed and wind.seal > 0.99)
	await _advance(1299.0, 3.0)
	_check("below 1300 mph the hum releases and the wind reopens", not wind.sealed and wind.hum < 0.01 and wind.seal < 0.001)
	if speed_player is AudioStreamPlayer:
		_check("both field voices release together", wind.hum_player.volume_db < -60.0 and speed_player.volume_db < -60.0)
		await _capture()
	var effect_counts := _field_effect_counts()
	wind.queue_free()
	await process_frame
	wind = Wind.new()
	root.add_child(wind)
	wind.setup(sim)
	_check("scene reload does not duplicate field effects", _field_effect_counts() == effect_counts)
	for player in wind.get_children():
		if player is AudioStreamPlayer:
			player.stop()
	wind.queue_free()
	await process_frame
	wind = null
	sim = null
	await process_frame
	print("SPEED SHIELD METRICS: low_source_hz=", low_hz, " low_pitch=", low_pitches, " speed_pitch=", tones)
	print("SPEED SHIELD %s (%d checks, %d failures)" % ["PASS" if fails == 0 else "FAIL", checks, fails])
	quit(0 if fails == 0 else 1)

func _tick(mph: float, dt: float, inp: Dictionary = {}) -> void:
	sim.pod.vx = mph / 2.236936
	sim.pod.vy = 0.0
	wind.update(inp, dt)

func _advance(mph: float, seconds: float, inp: Dictionary = {}) -> void:
	for frame in int(seconds / DT):
		_tick(mph, DT, inp)
		if frame % 120 == 119:
			await process_frame

## Capture the real mixed Field bus, including its reverb. Hold each speed for 3 s, then stop
## the sources for 1 s so the recording also proves there is a decaying reverberant tail.
func _capture() -> void:
	await _advance(1501.0, 4.0)
	var field := AudioServer.get_bus_index("Field")
	var rec := AudioEffectRecord.new()
	AudioServer.add_bus_effect(field, rec)
	rec.set_recording_active(true)
	var began := Time.get_ticks_usec()
	var previous := began
	while Time.get_ticks_usec() - began < 12000000:
		var now := Time.get_ticks_usec()
		var t := (now - began) / 1000000.0
		_tick(SPEEDS[mini(3, int(t / 3.0))], (now - previous) / 1000000.0)
		previous = now
		await process_frame
	wind.hum_player.stop()
	wind.speed_player.stop()
	await create_timer(1.0).timeout
	rec.set_recording_active(false)
	var wav := rec.get_recording()
	AudioServer.remove_bus_effect(field, AudioServer.get_bus_effect_count(field) - 1)
	var lows := []
	var highs := []
	for k in SPEEDS.size():
		lows.append(_peak_hz(wav, 25, 45, k * 3.0 + 1.6, k * 3.0 + 2.6))
		highs.append(_peak_hz(wav, 160, 650, k * 3.0 + 1.6, k * 3.0 + 2.6))
		_check("captured low reverberation stays at 30-40 Hz at %.0f mph" % SPEEDS[k], lows[k] >= 30.0 and lows[k] <= 40.0)
		if k > 0:
			_check("captured speed tone rises at %.0f mph" % SPEEDS[k], highs[k] > highs[k - 1] + 60.0)
	var steady_db := _rms_db(wav, 10.5, 11.5)
	var tail_db := _rms_db(wav, 12.1, 12.4)
	var end_db := _rms_db(wav, 12.7, 12.95)
	_check("captured field is audible with moderate headroom", steady_db > -40.0 and steady_db < -10.0)
	_check("field reverberates after its sources stop and decays", tail_db > -65.0 and tail_db < steady_db and end_db < tail_db - 2.0)
	if output != "":
		_check("saved shield capture", wav.save_to_wav(output) == OK)
	print("SPEED SHIELD CAPTURE: low_hz=", lows, " speed_hz=", highs, " steady_db=", steady_db, " tail_db=", tail_db, " end_db=", end_db)

func _field_effect_counts() -> Dictionary:
	var counts := {}
	for bus in AudioServer.bus_count:
		var name := AudioServer.get_bus_name(bus)
		if name.begins_with("Field"):
			counts[name] = AudioServer.get_bus_effect_count(bus)
	return counts

## Goertzel frequency scan on actual PCM, decimated 16x. Resolution is 1 Hz; all probed
## frequencies stay below the resulting Nyquist limit. No production tuning is reused.
func _peak_hz(wav: AudioStreamWAV, low: int, high: int, start := 0.0, end := 1.8) -> float:
	var data := wav.data
	var channels := 2 if wav.stereo else 1
	var a := int(start * wav.mix_rate)
	var b := mini(int(end * wav.mix_rate), data.size() / (channels * 2))
	var samples := PackedFloat64Array()
	for i in range(a, b, 16):
		samples.append(float(data.decode_s16(i * channels * 2)) / 32768.0)
	var rate := float(wav.mix_rate) / 16.0
	var best := -INF
	var hz := 0.0
	for f in range(low, high + 1):
		var coefficient := 2.0 * cos(TAU * f / rate)
		var p1 := 0.0
		var p2 := 0.0
		for sample in samples:
			var value := sample + coefficient * p1 - p2
			p2 = p1
			p1 = value
		var power := p1 * p1 + p2 * p2 - coefficient * p1 * p2
		if power > best:
			best = power
			hz = float(f)
	return hz

func _rms_db(wav: AudioStreamWAV, start: float, end: float) -> float:
	var data := wav.data
	var a := int(start * wav.mix_rate)
	var b := mini(int(end * wav.mix_rate), data.size() / 4)
	var sq := 0.0
	for i in range(a, b):
		var sample := float(data.decode_s16(i * 4)) / 32768.0
		sq += sample * sample
	return linear_to_db(sqrt(sq / maxf(1.0, b - a)))

func _check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		fails += 1
	print(("PASS " if passed else "FAIL ") + label)
