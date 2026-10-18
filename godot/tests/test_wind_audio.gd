## WindAudio gate: holds the pod at a ladder of speeds (plus a slide and an airborne leg),
## records the Wind bus, and measures each leg. Prints WIND AUDIO PASS when every check passes.
## Run: Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_wind_audio.gd
## Checks: quiet at rest; louder at every step up the ladder; brighter (zero-crossing rate) from
## 100 to 4,000 mph; a slide and leaving the ground both add buffet; no clipping; the loops are
## seamless (the jump back to the start is no bigger than an ordinary step); exactly one sonic
## boom (the ladder crosses Mach 1 once), loud up front and dying away, on its own bus.
extends SceneTree

const CraftSimScript := preload("res://sim/craft_sim.gd")
const WindAudioScript := preload("res://audio/wind_audio.gd")
const LEG := 2.5      # seconds per leg
const SETTLE := 0.8   # skip the start of each leg while the smoothing catches up
# [label, mph, slip radians, airborne, left brake, right brake]
const LEGS := [["rest", 0.0, 0.0, false, 0.0, 0.0], ["100 mph", 100.0, 0.0, false, 0.0, 0.0], ["500 mph", 500.0, 0.0, false, 0.0, 0.0],
	["1500 mph", 1500.0, 0.0, false, 0.0, 0.0], ["4000 mph", 4000.0, 0.0, false, 0.0, 0.0],
	["1500 mph sliding", 1500.0, 0.3, false, 0.0, 0.0], ["1500 mph airborne", 1500.0, 0.0, true, 0.0, 0.0],
	["1500 mph both brakes", 1500.0, 0.0, false, 1.0, 1.0], ["1500 mph left brake", 1500.0, 0.0, false, 1.0, 0.0]]

var sim
var wind
var rec: AudioEffectRecord
var clock: AudioStreamPlayer
var started := false
var boom_signals := 0
var shud_max := []     # per leg: [max shudder L, max shudder R, min flapL volume_db, max flapL volume_db]
var t := 0.0


func _initialize() -> void:
	sim = CraftSimScript.new({"track": "range"})


func _process(_delta: float) -> bool:
	if not started:
		wind = WindAudioScript.new()
		root.add_child(wind)
		wind.setup(sim)
		wind.boomed.connect(func(): boom_signals += 1)
		rec = AudioEffectRecord.new()
		AudioServer.add_bus_effect(AudioServer.get_bus_index("Wind"), rec)
		# time from the audio clock (a silent player), as in test_engine_audio.gd
		var silence := AudioStreamWAV.new()
		silence.mix_rate = 8000
		var zeros := PackedByteArray()
		zeros.resize(8000 * int(LEGS.size() * LEG + 10.0))
		silence.data = zeros
		clock = AudioStreamPlayer.new()
		clock.stream = silence
		clock.volume_db = -80.0
		root.add_child(clock)
		clock.play()
		rec.set_recording_active(true)
		started = true
		return false
	var now := clock.get_playback_position() + AudioServer.get_time_since_last_mix()
	var delta := maxf(0.0, now - t)
	t = now
	var leg: Array = LEGS[mini(int(t / LEG), LEGS.size() - 1)]
	var v: float = leg[1] / 2.236936
	sim.pod.vx = v
	sim.pod.vy = 0.0
	sim.pod.th = leg[2]
	sim.pod.grip = 0.0 if leg[3] else 1.0
	wind.update({"brkL": leg[4], "brkR": leg[5]}, delta)
	var li := mini(int(t / LEG), LEGS.size() - 1)
	while shud_max.size() <= li:
		shud_max.append([0.0, 0.0, INF, -INF])
	if fmod(t, LEG) > SETTLE:
		shud_max[li][0] = maxf(shud_max[li][0], wind.shudder[0])
		shud_max[li][1] = maxf(shud_max[li][1], wind.shudder[1])
		var vdb: float = wind.players.flapL.volume_db
		shud_max[li][2] = minf(shud_max[li][2], vdb)
		shud_max[li][3] = maxf(shud_max[li][3], vdb)
	if t < LEGS.size() * LEG:
		return false
	rec.set_recording_active(false)
	_report(rec.get_recording())
	return true


func _report(wav: AudioStreamWAV) -> void:
	var data := wav.data
	var rate := wav.mix_rate
	var frames := data.size() >> 2
	var stats := []
	var peak := 0
	for k in LEGS.size():
		var a := int((k * LEG + SETTLE) * rate)
		var b := mini(int((k + 1) * LEG * rate), frames)
		var sq := 0.0
		var sq_r := 0.0
		var sq_low := 0.0
		var lp := 0.0
		var lp_a := 1.0 - exp(-TAU * 200.0 / rate)   # one-pole low-pass at 200 Hz: the buffet band
		var zc := 0
		var prev := 0
		var n := 0
		for i in range(a, b):
			var s := data.decode_s16(i * 4)   # left channel
			var sr := data.decode_s16(i * 4 + 2)   # right channel
			peak = maxi(peak, maxi(absi(s), absi(sr)))
			sq += float(s) * s
			sq_r += float(sr) * sr
			lp += lp_a * (s - lp)
			sq_low += lp * lp
			if (s >= 0) != (prev >= 0):
				zc += 1
			prev = s
			n += 1
		var rms_db := 20.0 * log(maxf(sqrt(sq / maxf(n, 1)), 1e-3) / 32768.0) / log(10.0)
		var low_db := 20.0 * log(maxf(sqrt(sq_low / maxf(n, 1)), 1e-3) / 32768.0) / log(10.0)
		var zcr := float(zc) / maxf(float(n) / rate, 1e-3)
		var rms_r_db := 20.0 * log(maxf(sqrt(sq_r / maxf(n, 1)), 1e-3) / 32768.0) / log(10.0)
		stats.append([rms_db, zcr, low_db, rms_r_db])
		print("  %-18s rms %6.1f dBFS   low band %6.1f dBFS   zero crossings %6.0f /s" % [LEGS[k][0], rms_db, low_db, zcr])
	var fails := 0
	fails += _check("captured %.1f s" % (float(frames) / rate), frames > rate * (LEGS.size() * LEG - 1.0))
	fails += _check("quiet at rest (%.1f dBFS < -60)" % stats[0][0], stats[0][0] < -60.0)
	for k in range(2, 5):
		fails += _check("%s louder than %s by >= 3 dB" % [LEGS[k][0], LEGS[k - 1][0]], stats[k][0] >= stats[k - 1][0] + 3.0)
	fails += _check("brighter at 4000 than 100 mph (%.0f vs %.0f crossings/s)" % [stats[4][1], stats[1][1]], stats[4][1] > stats[1][1] * 1.5)
	fails += _check("sliding adds buffet (low band +%.1f dB)" % (stats[5][2] - stats[3][2]), stats[5][2] > stats[3][2] + 3.0)
	fails += _check("airborne adds buffet (low band +%.1f dB)" % (stats[6][2] - stats[3][2]), stats[6][2] > stats[3][2] + 2.0)
	fails += _check("airborne rush darker (%.0f vs %.0f crossings/s)" % [stats[6][1], stats[3][1]], stats[6][1] < stats[3][1])
	var both: float = (stats[7][0] + stats[7][3]) / 2.0
	var plain: float = (stats[3][0] + stats[3][3]) / 2.0
	fails += _check("air brakes out at 1500 mph add their roar (+%.1f dB)" % (both - plain), both >= plain + 3.0)
	fails += _check("both brakes sit in the middle (L %.1f / R %.1f dBFS)" % [stats[7][0], stats[7][3]], absf(stats[7][0] - stats[7][3]) < 1.5)
	fails += _check("the left brake's roar is on the left (L %.1f / R %.1f dBFS)" % [stats[8][0], stats[8][3]], stats[8][0] >= stats[8][3] + 2.0)
	fails += _check("no clipping (peak %.1f dBFS)" % (20.0 * log(maxf(peak, 1) / 32768.0) / log(10.0)), peak < 32767)
	for layer in wind.streams:
		var s: AudioStreamWAV = wind.streams[layer]
		var d := s.data
		var n: int = s.loop_end
		var steps := PackedFloat32Array()
		for i in range(1, n, 97):
			steps.append(absf(d.decode_s16(i * 4) - d.decode_s16((i - 1) * 4)))
		steps.sort()
		var typical: float = steps[int(steps.size() * 0.99)]
		var seam := absf(d.decode_s16(0) - d.decode_s16((n - 1) * 4))
		fails += _check("%s loop seamless (seam %.0f vs 99th-pct step %.0f)" % [layer, seam, typical], seam <= typical)
	fails += _flap_is_deep(wind.streams.flap)
	var sb: Array = shud_max[7]
	var sl: Array = shud_max[8]
	var sp: Array = shud_max[3]
	fails += _check("air brakes shudder at speed: both out L %.2f / R %.2f, left only L %.2f / R %.2f, none without (%.2f / %.2f)" % [sb[0], sb[1], sl[0], sl[1], sp[0], sp[1]],
		sb[0] > 0.5 and sb[1] > 0.5 and sl[0] > 0.5 and sl[1] < 0.02 and sp[0] < 0.02 and sp[1] < 0.02)
	fails += _check("... and the roar buffets with it (left flap volume swings %.1f dB)" % (sb[3] - sb[2]), sb[3] - sb[2] > 4.0)
	fails += _check("one sonic boom on the way through Mach 1 (%d)" % wind.booms, wind.booms == 1)
	fails += _check("boom on its own bus (%s)" % wind.boom_player.bus, wind.boom_player.bus == "Boom")
	var bd: PackedByteArray = wind.boom_player.stream.data
	var bn := bd.size() >> 2
	var head := 0.0
	var tail := 0.0
	var win := int(0.3 * 44100)
	for i in win:
		head += pow(bd.decode_s16(i * 4), 2.0)
		tail += pow(bd.decode_s16((bn - win + i) * 4), 2.0)
	var drop := 10.0 * log(maxf(head, 1.0) / maxf(tail, 1.0)) / log(10.0)
	fails += _check("boom dies away (first 0.3 s %.0f dB over the last)" % drop, drop > 30.0)
	var bpeak := 0
	var bsq := 0.0
	for i in 44100:
		var x := bd.decode_s16(i * 4)
		bpeak = maxi(bpeak, absi(x))
		bsq += float(x) * x
	var b_rms := 20.0 * log(sqrt(bsq / 44100.0) / 32768.0) / log(10.0)
	fails += _check("boom is loud: peak %.1f dBFS, first-second RMS %.1f dBFS (>= -14)" % [
		20.0 * log(bpeak / 32768.0) / log(10.0), b_rms], bpeak > 30000 and b_rms >= -14.0)
	fails += _check("engines and wind back up after the duck (%.1f dB)" % wind.duck_db, wind.duck_db == 0.0)
	fails += _check("boomed signal fired (%d)" % boom_signals, boom_signals == 1)
	print("WIND AUDIO ", "PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(1 if fails > 0 else 0)


## The air-brake roar must rumble, not hiss or rattle (Luke: the first one "sounds like grass and
## a rattlesnake": 48% of its energy over 1 kHz, 5,800 zero crossings/s, an 11 Hz flutter).
## Deep: little energy above 1 kHz (two one-pole high-passes, 12 dB/oct) and few zero crossings.
## Rumble, not rattle: the loudness envelope (10 ms windows) heaves slowly (0.5-6 Hz) far more
## than it flutters (8-20 Hz).
func _flap_is_deep(s: AudioStreamWAV) -> int:
	var d := s.data
	var n: int = s.loop_end
	var a := exp(-TAU * 1000.0 / s.mix_rate)
	var h1 := 0.0
	var h1_in := 0.0
	var h2 := 0.0
	var h2_in := 0.0
	var sq := 0.0
	var sq_hi := 0.0
	var zc := 0
	var prev := 0
	var win := 441
	var env := PackedFloat32Array()
	var acc := 0.0
	for i in n:
		var x := d.decode_s16(i * 4)
		h1 = a * (h1 + x - h1_in)
		h1_in = x
		h2 = a * (h2 + h1 - h2_in)
		h2_in = h1
		sq += float(x) * x
		sq_hi += h2 * h2
		if (x >= 0) != (prev >= 0):
			zc += 1
		prev = x
		acc += float(x) * x
		if (i + 1) % win == 0:
			env.append(sqrt(acc / win))
			acc = 0.0
	var hi_pct := 100.0 * sq_hi / maxf(sq, 1.0)
	var zcr := float(zc) / (float(n) / s.mix_rate)
	var mean := 0.0
	for e in env:
		mean += e
	mean /= env.size()
	var env_rate := float(s.mix_rate) / win
	var slow := 0.0
	var fast := 0.0
	for k in range(1, env.size() / 2):
		var f := k * env_rate / env.size()
		if f > 20.0:
			break
		var re := 0.0
		var im := 0.0
		for j in env.size():
			var ang := TAU * k * j / env.size()
			re += (env[j] - mean) * cos(ang)
			im -= (env[j] - mean) * sin(ang)
		var p := re * re + im * im
		if f >= 0.5 and f <= 6.0:
			slow += p
		elif f >= 8.0:
			fast += p
	var ratio := slow / maxf(fast, 1e-9)
	var fails := 0
	fails += _check("flap roar is deep: %.1f%% of it above 1 kHz (< 2), %.0f zero crossings/s (< 600)" % [hi_pct, zcr], hi_pct < 2.0 and zcr < 600.0)
	fails += _check("flap roar rumbles, not rattles: slow heave %.1fx the fast flutter (> 1.5)" % ratio, ratio > 1.5)
	return fails


func _check(label: String, ok: bool) -> int:
	print(("  ok   " if ok else "  FAIL ") + label)
	return 0 if ok else 1
