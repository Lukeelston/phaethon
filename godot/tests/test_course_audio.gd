## Course audio gate (audio/course_audio.gd: the courses' places and the emergency run in sound).
##   synthesis   every loop and cue is sound: not silent, no NaNs, loops that join without a click
##               (the seam no bigger a step than 4x the loop's own typical one)
##   enclosure   under a covered ramp's roof the air closes in (the reverb's wet up, the hall's ring
##               with your speed); out on the open loop it's gone
##   the dawn    its roar grows as the front nears and the searing hiss comes in over the last km
##   the pad     a beep each half second you hold on it, then the drop's chime
##   the gate    a chirp as the shade line's gate opens for you, a buzzer if it shuts
##   the result  a chord when you make it; the roar when the dawn catches you
## Prints COURSE AUDIO PASS.
## Run: Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_course_audio.gd -- --mute
extends SceneTree

const Sim := preload("res://sim/craft_sim.gd")
const CA := preload("res://audio/course_audio.gd")
const DT := 1.0 / 480.0
const CHECKS := 7
var fails := 0
var passed := 0


func _initialize() -> void:
	# synthesis
	var worst := ""
	for pair in [["rumble", CA.make_rumble()], ["hiss", CA.make_hiss()], ["hall", CA.make_hall()]]:
		var e := _peaks(pair[1])
		if e[0] < 0.02 or e[1] > 0.01 or is_nan(e[0]):
			worst += "%s (peak %.3f, seam %.3f) " % [pair[0], e[0], e[1]]
	for pair in [["beep", CA.make_beep(880.0, 0.12)], ["chime", CA.make_chime([523.25, 659.25, 783.99], 1.6)], ["buzzer", CA.make_buzzer()], ["roar", CA.make_roar()]]:
		var e := _peaks(pair[1])
		if e[0] < 0.05 or is_nan(e[0]):
			worst += "%s (peak %.3f) " % [pair[0], e[0]]
	_check("synthesis: every loop and cue is sound, the loops seamless%s" % ("" if worst == "" else ": " + worst), worst == "")

	# enclosure: under a receiving ramp's roof at 3,000 mph, then out on the open loop
	var sim = Sim.new({"track": "eridanus", "handling": "speed"})
	var ca = CA.new()
	root.add_child(ca)
	ca.setup(sim)
	var r: Array = sim.covered_ramps.filter(func(q): return int(q[1]) == sim.mouth - 1)[0]
	_go(sim, int(r[0]) + 200, 3000.0)
	_run(sim, ca, 2.0, INF)
	var inside: float = ca.wet
	var hall_db: float = ca.hall_db
	_go(sim, 3000, 3000.0)
	_run(sim, ca, 3.0, INF)
	_check("enclosure: under the ramp's roof the reverb is %.2f wet and the hall rings at %.1f dB; out on the loop %.2f wet, the ring %.1f dB" % [inside, hall_db, ca.wet, ca.hall_db],
		inside > 0.9 and hall_db > -20.0 and ca.wet < 0.05 and ca.hall_db < -60.0)

	# the dawn: far, then close
	var js = Sim.new({"track": "eridanus", "job": "emergency", "dawnT0": 1e9})
	var cj = CA.new()
	root.add_child(cj)
	cj.setup(js)
	_go(js, 3000, 0.0)
	_run(js, cj, 1.5, 60000.0)
	var far_db: float = cj.dawn_db
	_run(js, cj, 1.5, 1500.0)
	_check("the dawn: its roar %.1f dB with the front 60 km off, %.1f dB at 1.5 km, the hiss in at %.1f dB" % [far_db, cj.dawn_db, cj.hiss_db],
		far_db < -40.0 and cj.dawn_db > -12.0 and cj.hiss_db > -25.0)

	# the pad: stopped on it, held to the drop
	_go(js, js.pad, 0.0)
	js.job.t0 = 0.0
	_run(js, cj, 2.0, 60000.0)
	_check("the pad: %d beeps while held, then %s" % [cj.beeps, cj.cues], cj.beeps >= 2 and cj.cues.has("drop"))

	# the gate: decided open, then shut
	js.gate[0] = true
	cj.update(1.0 / 60.0, 60000.0)
	js.gate[0] = null
	cj.update(1.0 / 60.0, 60000.0)
	js.gate[0] = false
	cj.update(1.0 / 60.0, 60000.0)
	_check("the gate: %s" % [cj.cues], cj.cues.has("gate_open") and cj.cues.has("gate_shut"))

	# the result
	js.job.stage = "done"
	cj.update(1.0 / 60.0, 60000.0)
	var made: bool = cj.cues.has("made_it")
	var s2 = Sim.new({"track": "eridanus", "job": "emergency"})
	var c2 = CA.new()
	root.add_child(c2)
	c2.setup(s2)
	c2.update(1.0 / 60.0, INF)
	s2.job.stage = "failed"
	s2.job.reason = "dawn"
	c2.update(1.0 / 60.0, 0.0)
	_check("the result: made it %s, caught %s" % [made, c2.cues], made and c2.cues.has("caught"))
	# no job: no dawn, no cues
	var free_db: float = ca.dawn_db
	_check("free Eridanus: no dawn (%.0f dB), no cues %s" % [free_db, ca.cues], free_db <= -79.0 and ca.cues.is_empty())
	var good: bool = fails == 0 and passed == CHECKS
	print("COURSE AUDIO ", "PASS" if good else "FAIL (%d failed, %d of %d passed)" % [fails, passed, CHECKS])
	quit(0 if good else 1)


func _go(sim, i: int, mph: float) -> void:
	sim.respawn(-1, i)
	for b in sim.bodies:
		b.vx = mph / 2.236936 * sim.ttx[i]
		b.vy = mph / 2.236936 * sim.tty[i]


## Step the sim and the audio for `secs` (levers at idle), the dawn `dist` m off.
func _run(sim, ca, secs: float, dist: float) -> void:
	var inp := {"thrL": 0.0, "thrR": 0.0, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": true}
	for f in int(secs * 60.0):
		for k in 8:
			sim.step(inp, DT)
		sim.events.clear()
		ca.update(1.0 / 60.0, dist)


## [peak, the loop's seam jump] of a 16-bit stereo stream (0..1).
func _peaks(w: AudioStreamWAV) -> Array:
	var d: PackedByteArray = w.data
	var n := d.size() / 2
	var peak := 0.0
	for k in range(0, n, 7):
		peak = maxf(peak, absf(d.decode_s16(k * 2) / 32768.0))
	# the seam's jump (last frame to first, left channel) against the loop's own typical jump
	var sq := 0.0
	var cnt := 0
	for k in range(0, n - 4, 2 * 13):
		var j := float(d.decode_s16((k + 2) * 2) - d.decode_s16(k * 2)) / 32768.0
		sq += j * j
		cnt += 1
	var typical := sqrt(sq / maxf(cnt, 1))
	var seam := absf(d.decode_s16(0) - d.decode_s16((n - 2) * 2)) / 32768.0
	return [peak, seam / maxf(typical, 1e-6) * 0.0025]   # 4x a typical step reads 0.01


func _check(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if ok:
		passed += 1
	else:
		fails += 1
