## The traffic's whooshes (audio/traffic_audio.gd), on made-up passes, the pod at 1,000 m/s:
##   whoosh     the sound: 1.1 s, mono, not silent, its energy falling from high to low (the doppler fall)
##   passes     overtaking a car 30 m beside you (closing 200 m/s) and a faster one passing you 50 m
##              off (300 m/s): a whoosh each; one passing 300 m off, and one keeping pace 10 m off: none
##   follow     the voice follows its car while it sounds; nearer and harder is louder
## Prints TRAFFIC AUDIO PASS.
## Run: Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_traffic_audio.gd
extends SceneTree

const TA := preload("res://audio/traffic_audio.gd")
var fails := 0


func _initialize() -> void:
	var w: AudioStreamWAV = TA.make_whoosh()
	var n := w.data.size() / 2
	var e0 := 0.0
	var e1 := 0.0
	var hi0 := 0.0
	var hi1 := 0.0
	var prev := 0.0
	for k in n:
		var x := w.data.decode_s16(k * 2) / 32768.0
		var dx := x - prev   # a crude high-pass: its share of the energy is the brightness
		prev = x
		if k < n / 2:
			e0 += x * x
			hi0 += dx * dx
		else:
			e1 += x * x
			hi1 += dx * dx
	var b0 := hi0 / maxf(e0, 1e-9)
	var b1 := hi1 / maxf(e1, 1e-9)
	_check("whoosh: %.2f s, %s, brightness %.3f in its first half, %.3f in its second" % [float(n) / w.mix_rate, "stereo" if w.stereo else "mono", b0, b1],
		absf(float(n) / w.mix_rate - 1.1) < 0.01 and not w.stereo and e0 + e1 > 1.0 and b1 < b0 * 0.7)
	var ta = TA.new()
	root.add_child(ta)
	ta.setup()
	ta.set_speed(1000.0)
	var pos := []
	var to_world := func(x: float, y: float, h: float) -> Vector3:
		return Vector3(x, h, -y)
	var dbs := {}
	for f in 180:
		var t := f / 60.0
		var cars := [
			[1, 200.0 + (800.0 - 1000.0) * t, 30.0, 2.0, 800.0, 0.0],     # overtaken, 30 m off
			[2, -300.0 + (1300.0 - 1000.0) * t, -50.0, 2.0, 1300.0, 0.0],  # passing you, 50 m off
			[3, 200.0 + (800.0 - 1000.0) * t, 300.0, 2.0, 800.0, 0.0],    # 300 m off
			[4, 5.0, 10.0, 2.0, 1000.0, 0.0],                              # keeping pace
		]
		var p0: int = ta.passes
		ta.update(Vector2.ZERO, Vector2(1.0, 0.0), cars, to_world, 1.0 / 60.0)
		if ta.passes > p0:
			dbs[ta.passes] = ta.last_db
		if f == 75:
			for k in ta._voices.size():
				if ta._left[k] > 0.0:
					pos.append(ta._voices[k].position)
	_check("passes: %d whooshes (want 2), at %s dB" % [ta.passes, dbs.values()], ta.passes == 2)
	_check("follow: the voices at %s (their cars, a moment after their passes); the nearer, slower pass %s dB, the further, harder one %s dB" % [pos, dbs.get(1, -80.0), dbs.get(2, -80.0)],
		pos.size() >= 1 and dbs.get(1, -80.0) > -30.0 and dbs.get(2, -80.0) > -30.0)
	print("TRAFFIC AUDIO ", "PASS" if fails == 0 else "FAIL (%d failed)" % fails)
	quit(0 if fails == 0 else 1)


func _check(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if not ok:
		fails += 1
