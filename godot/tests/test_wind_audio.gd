## WindAudio gate: holds the pod at a ladder of speeds (plus a slide and an airborne leg),
## records the Wind bus, and measures each leg. Prints WIND AUDIO PASS when every check passes.
## Run: Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_wind_audio.gd
## Checks: quiet at rest; louder at every step up the ladder; brighter (zero-crossing rate) from
## 100 to 4,000 mph; a slide and leaving the ground both add buffet; no clipping; the loops are
## seamless (the jump back to the start is no bigger than an ordinary step).
extends SceneTree

const CraftSimScript := preload("res://sim/craft_sim.gd")
const WindAudioScript := preload("res://audio/wind_audio.gd")
const LEG := 2.5      # seconds per leg
const SETTLE := 0.8   # skip the start of each leg while the smoothing catches up
# [label, mph, slip radians, airborne]
const LEGS := [["rest", 0.0, 0.0, false], ["100 mph", 100.0, 0.0, false], ["500 mph", 500.0, 0.0, false],
	["1500 mph", 1500.0, 0.0, false], ["4000 mph", 4000.0, 0.0, false],
	["1500 mph sliding", 1500.0, 0.3, false], ["1500 mph airborne", 1500.0, 0.0, true]]

var sim
var wind
var rec: AudioEffectRecord
var clock: AudioStreamPlayer
var started := false
var t := 0.0


func _initialize() -> void:
	sim = CraftSimScript.new({"track": "range"})


func _process(_delta: float) -> bool:
	if not started:
		wind = WindAudioScript.new()
		root.add_child(wind)
		wind.setup(sim)
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
	wind.update({}, delta)
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
		var sq_low := 0.0
		var lp := 0.0
		var lp_a := 1.0 - exp(-TAU * 200.0 / rate)   # one-pole low-pass at 200 Hz: the buffet band
		var zc := 0
		var prev := 0
		var n := 0
		for i in range(a, b):
			var s := data.decode_s16(i * 4)   # left channel
			peak = maxi(peak, absi(s))
			sq += float(s) * s
			lp += lp_a * (s - lp)
			sq_low += lp * lp
			if (s >= 0) != (prev >= 0):
				zc += 1
			prev = s
			n += 1
		var rms_db := 20.0 * log(maxf(sqrt(sq / maxf(n, 1)), 1e-3) / 32768.0) / log(10.0)
		var low_db := 20.0 * log(maxf(sqrt(sq_low / maxf(n, 1)), 1e-3) / 32768.0) / log(10.0)
		var zcr := float(zc) / maxf(float(n) / rate, 1e-3)
		stats.append([rms_db, zcr, low_db])
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
	print("WIND AUDIO ", "PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(1 if fails > 0 else 0)


func _check(label: String, ok: bool) -> int:
	print(("  ok   " if ok else "  FAIL ") + label)
	return 0 if ok else 1
