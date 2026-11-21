## The start-up's own sounds (vr/startup_sequence.gd): the switches, the guard, the battery bus
## coming up, the self-test's chime, the binder striking, each engine's starter, the parking brake's
## clamp, and the blip of a refused control. All of them are worked out here from sines and noise,
## once a run (about a quarter of a second, in the dark of the first load); none is a recording.
## The engines' own voices (turning over, catching, idling) are EngineAudio's, told by its `off`
## and `crank`.
## Unverified by ear: their lengths, levels and pitches are measured (tests/test_startup_audio.gd),
## and that is all that can be said of them until a pilot has heard them.
##   add_child(a); a.setup()        once, inside the tree
##   a.play("click")                a sound by name; play("starter", 1) for the right engine's
class_name StartupAudio
extends Node

const Sequence := preload("res://vr/startup_sequence.gd")
const RATE := 32000
const NAMES := ["click", "clack", "button", "power", "down", "chime", "arc", "starter", "clamp", "release", "refuse"]
const LEVEL_DB := {"click": -9.0, "clack": -8.0, "button": -7.0, "power": -10.0, "down": -12.0, "chime": -14.0,
	"arc": -8.0, "starter": -9.0, "clamp": -6.0, "release": -6.0, "refuse": -12.0}
const POLYPHONY := 3
static var _bank := {}      # name -> AudioStreamWAV, worked out once a run

var players := {}           # name -> [AudioStreamPlayer]: centre, or [left, right] for the starters
var played: Array[String] = []   # what has been asked for, in order (the tests read it)


func setup() -> void:
	bank()
	var bus := "Cockpit"
	if AudioServer.get_bus_index(bus) < 0:
		var i := AudioServer.bus_count
		AudioServer.add_bus(i)
		AudioServer.set_bus_name(i, bus)
		AudioServer.set_bus_send(i, "Master")
	for name: String in NAMES:
		var list := []
		for k in (2 if name == "starter" else 1):
			var p := AudioStreamPlayer.new()
			p.stream = _bank[name]
			p.volume_db = LEVEL_DB[name]
			p.max_polyphony = POLYPHONY
			# a starter is its engine's: panned with it (the pops' bus carries the pan and no low-pass)
			var side := "EngineL_pops" if k == 0 else "EngineR_pops"
			p.bus = side if name == "starter" and AudioServer.get_bus_index(side) >= 0 else bus
			add_child(p)
			list.append(p)
		players[name] = list


func play(sound: String, side := 0) -> void:
	played.append(sound)
	if not players.has(sound):
		return
	var list: Array = players[sound]
	(list[mini(side, list.size() - 1)] as AudioStreamPlayer).play()


## Stop a sound that is still running (a starter, when the engines are cut mid-start).
func stop(sound: String) -> void:
	for p: AudioStreamPlayer in players.get(sound, []):
		p.stop()


## Every sound, worked out on first asking.
static func bank() -> Dictionary:
	if _bank.is_empty():
		var rng := RandomNumberGenerator.new()
		rng.seed = 20261120
		for name: String in NAMES:
			_bank[name] = _wav(_make(name, rng))
	return _bank


static func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var peak := 0.0001
	for v in samples:
		peak = maxf(peak, absf(v))
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	var k := 0.7 / peak             # every sound peaks at -3 dB; its player sets its level
	for i in samples.size():
		bytes.encode_s16(i * 2, clampi(roundi(samples[i] * k * 32767.0), -32768, 32767))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	return w


## A struck thing: a sine at `hz` dying over `tau`, from `at` seconds in.
static func _ring(out: PackedFloat32Array, at: float, hz: float, tau: float, amp: float) -> void:
	var from := int(at * RATE)
	var n := mini(out.size() - from, int(tau * 7.0 * RATE))
	var w := TAU * hz / RATE
	var decay := exp(-1.0 / (tau * RATE))
	var a := amp
	for i in n:
		out[from + i] += a * sin(w * i)
		a *= decay


## A burst of noise dying over `tau`, through a one-pole low-pass at `hz`, from `at` seconds in.
static func _burst(out: PackedFloat32Array, rng: RandomNumberGenerator, at: float, hz: float, tau: float, amp: float) -> void:
	var from := int(at * RATE)
	var n := mini(out.size() - from, int(tau * 7.0 * RATE))
	var k := 1.0 - exp(-TAU * hz / RATE)
	var decay := exp(-1.0 / (tau * RATE))
	var a := amp
	var y := 0.0
	for i in n:
		y += (rng.randf_range(-1.0, 1.0) - y) * k
		out[from + i] += a * y
		a *= decay


static func _blank(seconds: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(int(seconds * RATE))
	return out


static func _make(sound: String, rng: RandomNumberGenerator) -> PackedFloat32Array:
	match sound:
		"click":        # a toggle going over centre: the snap, and the panel answering
			var o := _blank(0.07)
			_burst(o, rng, 0.0, 6000.0, 0.0022, 1.0)
			_ring(o, 0.0, 2900.0, 0.004, 0.5)
			_ring(o, 0.001, 210.0, 0.012, 0.6)
			return o
		"clack":        # the guard: a hollow cover, landing twice
			var o := _blank(0.14)
			for hit in [[0.0, 1.0], [0.034, 0.45]]:
				_burst(o, rng, hit[0], 5000.0, 0.003, hit[1])
				_ring(o, hit[0], 1150.0, 0.011, 0.7 * hit[1])
				_ring(o, hit[0], 3300.0, 0.005, 0.3 * hit[1])
			return o
		"button":       # the start button: a deep thock, then its return
			var o := _blank(0.16)
			_ring(o, 0.0, 135.0, 0.03, 1.0)
			_burst(o, rng, 0.0, 2500.0, 0.004, 0.6)
			_burst(o, rng, 0.085, 4000.0, 0.003, 0.25)
			return o
		"power":        # the battery bus: a contactor, then inverters and gyros winding up
			var o := _blank(1.5)
			_ring(o, 0.0, 95.0, 0.04, 1.0)
			_burst(o, rng, 0.0, 3000.0, 0.005, 0.6)
			var phase := 0.0
			var phase2 := 0.0
			for i in o.size():
				var t := float(i) / RATE
				var rise := 1.0 - exp(-t / 0.35)
				var env := minf(t / 0.05, 1.0) * exp(-maxf(0.0, t - 0.9) / 0.22)
				phase += TAU * lerpf(180.0, 400.0, rise) / RATE
				phase2 += TAU * lerpf(700.0, 2350.0, rise) / RATE
				o[i] += env * (0.22 * sin(phase) + 0.08 * sin(2.0 * phase) + 0.05 * sin(phase2))
			return o
		"down":         # the bus dying: the same wound down
			var o := _blank(0.9)
			_ring(o, 0.0, 95.0, 0.035, 0.8)
			var phase := 0.0
			for i in o.size():
				var t := float(i) / RATE
				phase += TAU * lerpf(400.0, 90.0, 1.0 - exp(-t / 0.3)) / RATE
				o[i] += 0.3 * exp(-t / 0.28) * (sin(phase) + 0.3 * sin(2.0 * phase))
			return o
		"chime":        # the self-test, passed: two soft notes
			var o := _blank(0.75)
			_ring(o, 0.0, 880.0, 0.11, 0.7)
			_ring(o, 0.0, 1760.0, 0.05, 0.15)
			_ring(o, 0.19, 1318.5, 0.16, 0.7)
			_ring(o, 0.19, 2637.0, 0.06, 0.12)
			return o
		"arc":          # the binder striking: a crack, a buzz that settles into a hum
			var o := _blank(0.9)
			_burst(o, rng, 0.0, 9000.0, 0.012, 1.0)
			var y := 0.0
			for i in o.size():
				var t := float(i) / RATE
				y += (rng.randf_range(-1.0, 1.0) - y) * 0.35
				var buzz := 0.5 + 0.5 * signf(sin(TAU * 120.0 * t))
				o[i] += 0.55 * exp(-t / 0.16) * y * buzz + 0.25 * minf(t / 0.1, 1.0) * exp(-maxf(0.0, t - 0.5) / 0.12) * (sin(TAU * 120.0 * t) + 0.4 * sin(TAU * 240.0 * t))
			return o
		"starter":      # an engine's starter: a geared motor winding up under load, let go as it catches
			var o := _blank(Sequence.CRANK_S + 0.55)
			var phase := 0.0
			var y := 0.0
			for i in o.size():
				var t := float(i) / RATE
				var up := 1.0 - exp(-t / 0.55)
				var hz := lerpf(150.0, 640.0, up)
				phase += TAU * hz / RATE
				var env := minf(t / 0.04, 1.0) * exp(-maxf(0.0, t - Sequence.CRANK_S) / 0.14)
				var mesh := 0.75 + 0.25 * sin(phase * 7.0)                     # the gear's teeth
				var labour := 1.0 - 0.18 * maxf(0.0, sin(TAU * (2.0 + 9.0 * up) * t))   # each compression drags it
				y += (rng.randf_range(-1.0, 1.0) - y) * 0.2
				o[i] = env * labour * (0.5 * sin(phase) * mesh + 0.22 * sin(2.0 * phase) + 0.12 * sin(3.0 * phase) + 0.07 * sin(5.0 * phase) + 0.1 * y)
			return o
		"clamp":        # the parking brake going on: a heavy latch
			var o := _blank(0.3)
			_ring(o, 0.0, 72.0, 0.05, 1.0)
			_ring(o, 0.0, 1400.0, 0.02, 0.25)
			_burst(o, rng, 0.0, 2500.0, 0.006, 0.5)
			return o
		"release":      # ... and coming off: the latch, and the air let out of it
			var o := _blank(0.5)
			_ring(o, 0.0, 84.0, 0.04, 0.9)
			_burst(o, rng, 0.0, 2500.0, 0.005, 0.5)
			_burst(o, rng, 0.03, 7000.0, 0.09, 0.4)
			return o
		_:              # "refuse": two flat blips
			var o := _blank(0.3)
			for at in [0.0, 0.14]:
				var from := int(at * RATE)
				for i in int(0.085 * RATE):
					var t := float(i) / RATE
					o[from + i] += minf(t / 0.004, 1.0) * minf((0.085 - t) / 0.01, 1.0) * (sin(TAU * 233.0 * t) + 0.35 * sin(TAU * 699.0 * t))
			return o
