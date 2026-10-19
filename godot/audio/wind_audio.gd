## WindAudio: the air the pod is tearing through. Three stereo noise loops, synthesized once at
## setup (no assets), decorrelated left and right so the wind sits around your head:
##   rush    pink noise: the airstream. Louder with speed; its low-pass opens with speed, so
##           it brightens from a hiss at a jog to a tearing roar at 5,000 mph.
##   buffet  brown-noise rumble with slow gusts: kicks up when the craft slides (slip angle)
##           and when it's airborne.
##   whistle a resonant shriek that comes in above ~1,000 mph and rises in pitch.
##   flaps   the air brakes: a deep rumbling roar heaved by a slow buffet, one per side, panned
##           to that ear, louder with speed and with how far that side's flaps are open.
## Plus a one-shot sonic boom on the way through Mach 1 (re-arms below Mach 0.9), on its own
## "Boom" bus: a heavy double-crack N-wave, its reflection off the desert floor, a sub thump and
## four seconds of rolling thunder, soft-clipped dense. The engines and the wind duck under it,
## and `boomed` fires so the cockpit can kick the controllers. From the second engine's lighting
## speed you're sealed in: the field's hum powers up on its own "Field" bus, then the wind shuts
## out behind it, quieter and muffled (`_seal`); under its off speed the air comes back.
## Silent at rest, ducked with the picture on a crash. Same bus pattern as EngineAudio: the
## layers feed a "Wind" bus with a hard limiter, so wind can never clip the mix.
##   add_child(wind); wind.setup(sim)    once, inside the tree
##   wind.update(inp, delta)             every frame, after the sim steps
extends Node

const EngineAudio := preload("res://audio/engine_audio.gd")   # the seal follows its second engine
const RATE := 44100
const LOOP_S := 2.0     # seamless loops; filtering and gusts hide the repeat
const XF_S := 0.25      # loop crossfade
const SOUND := 343.0    # m/s
const BOOM_S := 4.2
const BOOM_DB := 2.0       # boom player level (the Boom bus limiter holds the ceiling)
const DUCK_DB := -14.0     # engines and wind under the boom ...
const DUCK_HOLD := 0.35    # ... held this long ...
const DUCK_REL := 1.6      # ... then back over this long

signal boomed

const TUNE := {
	"mph_lo": 20.0, "mph_hi": 2500.0,   # speed range mapped onto g = 0..1 (log scale)
	"rush_db": [-46.0, -9.0],
	"rush_hz": [300.0, 12000.0],        # rush low-pass, g 0 -> 1
	"rush_hp_hz": 140.0,                # rush high-pass: below this is the buffet's band
	"buffet_db": [-52.0, -13.0],
	"buffet_hz": 150.0,
	"whistle_db": [-60.0, -18.0],       # fades in over g 0.62..1 (~1,000 -> 2,500 mph)
	"slip_db": 12.0, "air_db": 6.0, "gust_db": 6.0,
	"flap_db": [-41.0, -4.0],           # one side's flaps fully open, g 0 -> 1 (Luke: "could still be louder")
	"flap_shudder": 0.5,                # how hard the open flaps buffet the roar (volume swing, linear)
	"flap_pan": 0.75, "flap_tau": 0.11,  # pan per side; follows the brake like the flaps move
	"smooth": 0.08,                     # parameter smoothing, s
	# The seal (Luke: "an electronic hum then a wind sound dampening at second engine engagement.
	# Something that seals that you're in a totally different environment"): when the second
	# engine lights (EngineAudio's second_on_mph, off below second_off_mph), the field powers up
	# with a hum, then the wind shuts out behind it; under the off speed it all opens again.
	"seal_catch_s": 0.7,                # the second engine cranks this long before it catches: the hum then
	"seal_shut_s": 0.45,                # ... and the wind seals this long after the hum
	"seal_db": -15.0,                   # the wind, sealed
	"seal_hz": [20000.0, 650.0],        # the Wind bus low-pass, open -> sealed
	"seal_close": 0.22, "seal_open": 0.3,   # the seal shutting, opening (s)
	"hum_db": [-20.0, -14.0],           # the field's hum at second_on_mph -> 4,000 mph
	"hum_attack": 0.35, "hum_release": 0.5,
	"hum_rise": [0.72, 1.0], "hum_rise_s": 0.9,   # powering up: its pitch climbs over this long
}

var sim
var streams := {}   # layer -> AudioStreamWAV (tests read these)
var players := {}   # layer -> AudioStreamPlayer
var levels := {"rush": 0.0, "buffet": 0.0, "whistle": 0.0, "flapL": 0.0, "flapR": 0.0}   # smoothed linear gains (tests read these)
var _open := [0.0, 0.0]   # each side's flaps, following its brake
var shudder := [0.0, 0.0] # each side's air-brake shudder right now, 0..1 (the cockpit's haptics read it)
var shake := [0.0, 0.0]   # ... and its signed waveform, -1..1 (the cockpit's shake reads it)
var _cut := 300.0
var _t := 0.0
var _noise := FastNoiseLite.new()
var _rush_bus := 0
var boom_player: AudioStreamPlayer
var booms := 0          # booms fired this session (tests read this)
var boom_streams: Array[AudioStreamWAV] = []   # one per BOOM_VARIANTS
var _last_boom := -1
var _boom_rng := RandomNumberGenerator.new()
var _boom_task := -1     # the worker making the other variants
var _more_booms: Array[AudioStreamWAV] = []
var _boom_armed := true
var duck_db := 0.0      # current duck on the Engines and Wind buses (tests read this)
var _since_boom := INF
var sealed := false     # past the second engine's lighting speed (with its hysteresis)
var seal := 0.0         # the wind's seal, 0 open .. 1 shut (tests read this)
var hum := 0.0          # the field hum's level, 0..1 (tests read this)
var hum_player: AudioStreamPlayer
var _seal_age := 0.0    # since `sealed` last changed, s
var _seal_fx := 0       # the Wind bus's seal low-pass


func setup(craft_sim) -> void:
	sim = craft_sim
	_noise.seed = 4242
	_noise.frequency = 0.9
	var wind_bus := _bus("Wind", "Master")
	if AudioServer.get_bus_effect_count(wind_bus) == 0:
		var lim := AudioEffectHardLimiter.new()
		lim.ceiling_db = -1.0
		AudioServer.add_bus_effect(wind_bus, lim)
	_seal_fx = -1   # the seal's low-pass on the Wind bus, ahead of its limiter (buses outlive scene reloads)
	for k in AudioServer.get_bus_effect_count(wind_bus):
		if AudioServer.get_bus_effect(wind_bus, k) is AudioEffectLowPassFilter:
			_seal_fx = k
	if _seal_fx < 0:
		var slp := AudioEffectLowPassFilter.new()
		slp.cutoff_hz = TUNE.seal_hz[0]
		AudioServer.add_bus_effect(wind_bus, slp, 0)
		_seal_fx = 0
	_rush_bus = _bus("WindRush", "Wind")
	if AudioServer.get_bus_effect_count(_rush_bus) == 0:
		AudioServer.add_bus_effect(_rush_bus, AudioEffectLowPassFilter.new())   # index 0: follows speed
		var hp := AudioEffectHighPassFilter.new()   # the lows belong to the buffet
		hp.cutoff_hz = TUNE.rush_hp_hz
		AudioServer.add_bus_effect(_rush_bus, hp)
	var buffet_bus := _bus("WindBuffet", "Wind")
	if AudioServer.get_bus_effect_count(buffet_bus) == 0:
		var lp := AudioEffectLowPassFilter.new()
		lp.cutoff_hz = TUNE.buffet_hz
		AudioServer.add_bus_effect(buffet_bus, lp)
	for side in ["L", "R"]:   # the flaps: one bus per side, panned to that ear
		var fb := _bus("WindFlap" + side, "Wind")
		if AudioServer.get_bus_effect_count(fb) == 0:
			var pan := AudioEffectPanner.new()
			pan.pan = TUNE.flap_pan * (-1.0 if side == "L" else 1.0)
			AudioServer.add_bus_effect(fb, pan)
	var busmap := {"rush": "WindRush", "buffet": "WindBuffet", "whistle": "Wind", "flapL": "WindFlapL", "flapR": "WindFlapR"}
	var t0 := Time.get_ticks_msec()
	streams.flap = make_loop("flap", 1777)
	for layer in ["rush", "buffet", "whistle", "flapL", "flapR"]:
		if not layer.begins_with("flap"):
			streams[layer] = make_loop(layer, 1000 + layer.length())
		var p := AudioStreamPlayer.new()
		p.stream = streams.flap if layer.begins_with("flap") else streams[layer]
		p.bus = busmap[layer]
		p.volume_db = -80.0
		add_child(p)
		p.play(randf() * LOOP_S)
		players[layer] = p
	_bus("Field", "Master")   # the hum on its own bus: the seal doesn't muffle it
	hum_player = AudioStreamPlayer.new()
	hum_player.stream = make_hum()
	hum_player.bus = "Field"
	hum_player.volume_db = -80.0
	add_child(hum_player)
	hum_player.play()
	var boom_bus := _bus("Boom", "Master")
	if AudioServer.get_bus_effect_count(boom_bus) == 0:
		var blim := AudioEffectHardLimiter.new()
		blim.ceiling_db = -0.3
		AudioServer.add_bus_effect(boom_bus, blim)
	_boom_rng.randomize()
	boom_streams.append(make_boom(0))
	_boom_task = WorkerThreadPool.add_task(_make_more_booms)   # the rest off the main thread: ~0.5 s each
	boom_player = AudioStreamPlayer.new()
	boom_player.stream = boom_streams[0]
	boom_player.bus = "Boom"
	boom_player.volume_db = BOOM_DB
	add_child(boom_player)
	print("AUDIO: WindAudio up, 4 stereo loops + a boom synthesized in %d ms (%d more booms on a worker)" % [Time.get_ticks_msec() - t0, BOOM_VARIANTS.size() - 1])


## Get or create a bus routed into `send` (same helper as EngineAudio).
static func _bus(name: String, send: String) -> int:
	var i := AudioServer.get_bus_index(name)
	if i < 0:
		i = AudioServer.bus_count
		AudioServer.add_bus(i)
		AudioServer.set_bus_name(i, name)
	AudioServer.set_bus_send(i, send)
	return i


## One seamless stereo loop of the given noise colour. Generated LOOP_S + XF_S long, then the
## tail is crossfaded (equal power) into the head, so the jump from the last sample back to the
## first lands on the sample that originally followed it.
static func make_loop(kind: String, seed: int) -> AudioStreamWAV:
	var n := int(RATE * LOOP_S)
	var xf := int(RATE * XF_S)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var chans: Array[PackedFloat32Array] = []
	for c in 2:
		var buf := PackedFloat32Array()
		buf.resize(n + xf)
		if kind == "rush":   # pink (Paul Kellett, economy)
			var b0 := 0.0
			var b1 := 0.0
			var b2 := 0.0
			for i in n + xf:
				var w := rng.randf_range(-1.0, 1.0)
				b0 = 0.99765 * b0 + w * 0.0990460
				b1 = 0.96300 * b1 + w * 0.2965164
				b2 = 0.57000 * b2 + w * 1.0526913
				buf[i] = b0 + b1 + b2 + w * 0.1848
		elif kind == "flap":
			# The air brakes: a deep, rumbling roar. No hiss (Luke: the first one "sounds like grass
			# and a rattlesnake": half its energy was over 1 kHz, with an 11 Hz flutter on top).
			# Brown noise band-limited to ~80-800 Hz, plus the flap panels drumming at 72/150/235 Hz,
			# heaved by a slow irregular buffet, then softly saturated so the rumble still reads on
			# the headset's small speakers. The test gate measures all of that.
			var m := n + xf
			var parts: Array[PackedFloat32Array] = []
			for p in 4:
				var a := PackedFloat32Array()
				a.resize(m)
				parts.append(a)
			var lp_a := 1.0 - exp(-TAU * 520.0 / RATE)
			var hp_a := exp(-TAU * 80.0 / RATE)
			var res_r := [0.996, 0.995, 0.994]
			var res_a1 := []
			for r in 3:
				res_a1.append(2.0 * res_r[r] * cos(TAU * [72.0, 150.0, 235.0][r] / RATE))
			var y1 := [0.0, 0.0, 0.0]
			var y2 := [0.0, 0.0, 0.0]
			var br := 0.0
			var l1 := 0.0
			var l2 := 0.0
			var h1 := 0.0
			var h1_in := 0.0
			var h2 := 0.0
			var h2_in := 0.0
			var sq := [0.0, 0.0, 0.0, 0.0]
			for i in m:
				var w := rng.randf_range(-1.0, 1.0)
				br = (br + 0.02 * w) / 1.02   # brown
				l1 += lp_a * (br - l1)
				l2 += lp_a * (l1 - l2)
				h1 = hp_a * (h1 + l2 - h1_in)
				h1_in = l2
				h2 = hp_a * (h2 + h1 - h2_in)
				h2_in = h1
				parts[0][i] = h2
				sq[0] += h2 * h2
				for r in 3:   # the panels drumming
					var rr: float = res_r[r]
					var y: float = (1.0 - rr) * w + res_a1[r] * y1[r] - rr * rr * y2[r]
					y2[r] = y1[r]
					y1[r] = y
					parts[r + 1][i] = y
					sq[r + 1] += y * y
			var gains := [1.0, 1.15, 1.0, 0.6]
			for p in 4:
				gains[p] = gains[p] / sqrt(maxf(sq[p] / m, 1e-20))
			var ph := [rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU]
			var lp_b := 1.0 - exp(-TAU * 800.0 / RATE)
			var lo := 0.0
			var sum_sq := 0.0
			for i in m:
				var x: float = gains[0] * parts[0][i] + gains[1] * parts[1][i] + gains[2] * parts[2][i] + gains[3] * parts[3][i]
				lo += lp_b * (x - lo)
				# the buffet: 1.5, 2.5 and 4 Hz, whole cycles in the 2 s loop so it stays seamless
				var t := float(i % n) / RATE
				var heave: float = 0.6 + 0.22 * sin(TAU * 1.5 * t + ph[0]) + 0.12 * sin(TAU * 2.5 * t + ph[1]) + 0.06 * sin(TAU * 4.0 * t + ph[2])
				buf[i] = lo * heave
				sum_sq += buf[i] * buf[i]
			var drive := 1.5 / sqrt(maxf(sum_sq / m, 1e-20))   # driven harder: a growl the small speakers carry
			for i in m:
				buf[i] = tanh(drive * buf[i]) / 1.5
		elif kind == "buffet":   # brown
			var b := 0.0
			for i in n + xf:
				b = (b + 0.02 * rng.randf_range(-1.0, 1.0)) / 1.02
				buf[i] = b
		else:   # whistle: noise through a narrow resonator, slightly detuned per ear
			var f0 := 1150.0 * (1.0 if c == 0 else 1.04)
			var r := 0.9965
			var a1 := 2.0 * r * cos(TAU * f0 / RATE)
			var a2 := -r * r
			var y1 := 0.0
			var y2 := 0.0
			for i in n + xf:
				var y := a1 * y1 + a2 * y2 + rng.randf_range(-1.0, 1.0)
				y2 = y1
				y1 = y
				buf[i] = y
		for i in xf:
			var a := float(i) / xf
			buf[i] = buf[i] * sqrt(a) + buf[n + i] * sqrt(1.0 - a)
		buf.resize(n)
		chans.append(buf)
	var peak := 1e-9
	for buf in chans:
		for v in buf:
			peak = maxf(peak, absf(v))
	var k := 0.7 / peak
	var left := chans[0]
	var right := chans[1]
	var data := PackedByteArray()
	data.resize(n * 4)
	for i in n:
		data.encode_s16(i * 4, int(left[i] * k * 32767.0))
		data.encode_s16(i * 4 + 2, int(right[i] * k * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.stereo = true
	w.mix_rate = RATE
	w.data = data
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = n
	return w


## The field's hum: an electrical 120 Hz buzz with its harmonics, soft-clipped, the two ears half a
## hertz apart so it beats slowly, a faint high shimmer over it. Every partial fits a whole number
## of cycles in LOOP_S, so the loop is seamless. All of it above ~100 Hz: the Quest's speakers play it.
static func make_hum() -> AudioStreamWAV:
	var n := int(RATE * LOOP_S)
	var data := PackedByteArray()
	data.resize(n * 4)
	for i in n:
		var t := float(i) / RATE
		for c in 2:
			var f := 120.0 + 0.5 * c
			var x := 0.5 * sin(TAU * f * t) + 0.35 * sin(TAU * 2.0 * f * t + 0.3) + 0.18 * sin(TAU * 3.0 * f * t + 1.1) \
				+ 0.12 * sin(TAU * 4.0 * f * t + 2.0) + 0.06 * sin(TAU * 5.0 * f * t + 0.7)
			x = tanh(1.4 * x) + 0.035 * sin(TAU * 1800.0 * t) * (0.5 + 0.5 * sin(TAU * 3.0 * t + c))
			data.encode_s16(i * 4 + c * 2, int(clampf(x * 0.78, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.stereo = true
	w.mix_rate = RATE
	w.data = data
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_end = n
	return w


## The booms, so it isn't the same one every time (Luke: "add a few variations of the sonic
## boom"): each moves the bow-to-tail gap, the N-wave's length, the ground reflection, the sub
## thump's pitch, the thunder's size and roll and its crackle; one adds a far echo off the hills.
##   gap s, N-wave s, reflection s, sub Hz, sub Hz, rumble size, rumble roll s, crackle, echo s
const BOOM_VARIANTS := [
	[0.16, 0.13, 0.011, 32.0, 55.0, 1.0, 2.2, 1.0, 0.0],
	[0.11, 0.10, 0.016, 28.0, 47.0, 1.15, 2.8, 1.4, 0.0],
	[0.21, 0.15, 0.008, 36.0, 61.0, 0.85, 1.8, 0.7, 0.0],
	[0.14, 0.12, 0.020, 30.0, 52.0, 1.05, 2.5, 1.2, 0.55],
	[0.18, 0.14, 0.013, 34.0, 58.0, 1.25, 3.2, 0.9, 0.0],
]

## A sonic boom (`variant` of BOOM_VARIANTS). Two N-waves (pressure snaps up, ramps down
## through zero, snaps back: each is a double crack), the bow and tail shocks apart, each with
## its reflection off the ground a few ms later (a touch different per ear); a sub thump under
## them; then thunder: brown-noise rumble with crackle rolling away over ~4 s. Soft-clipped so
## the whole thing sits loud and dense instead of one peak and a whisper.
static func make_boom(variant := 0) -> AudioStreamWAV:
	var V: Array = BOOM_VARIANTS[variant]
	var n := int(RATE * BOOM_S)
	var rng := RandomNumberGenerator.new()
	rng.seed = 767 + 31 * variant
	var t0 := 0.01
	var tn: float = V[1]    # N-wave length
	var gap: float = V[0]   # bow shock to tail shock
	var echo: float = V[8]
	var chans: Array[PackedFloat32Array] = []
	for c in 2:
		var buf := PackedFloat32Array()
		buf.resize(n)
		var refl: float = V[2] + 0.005 * c
		var lp := 0.0
		var lp2 := 0.0
		var lp3 := 0.0
		var brown := 0.0
		for i in n:
			var t := float(i) / RATE
			var x := 0.0
			var waves := [[t0, 1.0], [t0 + refl, 0.65], [t0 + gap, 0.85], [t0 + gap + refl, 0.55]]
			if echo > 0.0:
				waves.append([t0 + echo + 0.004 * c, 0.32])
				waves.append([t0 + echo + gap + 0.004 * c, 0.26])
			for w in waves:
				var u: float = t - w[0]
				if u >= 0.0 and u < tn:
					x += w[1] * (1.0 - 2.0 * u / tn)
			lp += 0.55 * (x - lp)   # take the digital edge off the cracks, keep them sharp
			var e := t - t0
			var sub := 0.0
			var rumble := 0.0
			var crackle := 0.0
			if e > 0.0:
				var env := minf(1.0, e / 0.003)
				sub = env * (0.9 * sin(TAU * V[3] * e) * exp(-e / 0.45) + 0.5 * sin(TAU * V[4] * e) * exp(-e / 0.25))
				brown = (brown + 0.03 * rng.randf_range(-1.0, 1.0)) / 1.03
				lp2 += 0.03 * (brown - lp2)
				rumble = 12.0 * V[5] * lp2 * (0.35 + 0.65 * exp(-e / 1.1)) * exp(-e / V[6]) * minf(1.0, e / 0.04)
				# crackle: sparse sharp ticks thinning out as the thunder rolls away
				if rng.randf() < 0.004 * V[7] * exp(-e / 0.9):
					lp3 = rng.randf_range(-1.0, 1.0) * 0.6
				lp3 *= 0.93
				crackle = lp3 * exp(-e / 1.5)
			var tail := clampf((BOOM_S - t) / 0.8, 0.0, 1.0)   # roll into silence, never chop
			buf[i] = tanh(1.6 * (1.2 * lp + sub + rumble + crackle)) * (0.5 - 0.5 * cos(PI * tail))
		chans.append(buf)
	var peak := 1e-9
	for buf in chans:
		for v in buf:
			peak = maxf(peak, absf(v))
	var k := 0.97 / peak
	var data := PackedByteArray()
	data.resize(n * 4)
	for i in n:
		data.encode_s16(i * 4, int(chans[0][i] * k * 32767.0))
		data.encode_s16(i * 4 + 2, int(chans[1][i] * k * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.stereo = true
	w.mix_rate = RATE
	w.data = data
	return w


func _make_more_booms() -> void:
	var more: Array[AudioStreamWAV] = []
	for v in range(1, BOOM_VARIANTS.size()):
		more.append(make_boom(v))
	_more_booms = more   # handed over whole; collected on the main thread


## Take in the variants the worker has made (all at once, once it's done; `wait`: block for them).
func collect_booms(wait := false) -> void:
	if _boom_task < 0 or not (wait or WorkerThreadPool.is_task_completed(_boom_task)):
		return
	WorkerThreadPool.wait_for_task_completion(_boom_task)
	_boom_task = -1
	boom_streams.append_array(_more_booms)
	_more_booms = []


func _exit_tree() -> void:
	collect_booms(true)   # never leave the worker running into a scene reload


## The next boom's variant: any but the last one.
func pick_boom() -> int:
	collect_booms()
	if boom_streams.size() < 2:
		return 0
	var k := _boom_rng.randi_range(0, boom_streams.size() - 2)
	if k >= _last_boom:
		k += 1
	_last_boom = k
	return k


func boom() -> void:
	booms += 1
	boom_player.stream = boom_streams[pick_boom()]
	boom_player.play()
	_since_boom = 0.0
	boomed.emit()


## Engines and wind sink under the boom, then come back.
func _duck(dt: float) -> void:
	_since_boom += dt
	var d := 0.0
	if _since_boom < DUCK_HOLD:
		d = DUCK_DB
	elif _since_boom < DUCK_HOLD + DUCK_REL:
		d = DUCK_DB * (1.0 - smoothstep(0.0, 1.0, (_since_boom - DUCK_HOLD) / DUCK_REL))
	if d == duck_db:
		return
	duck_db = d
	for bus in ["Engines", "Wind"]:
		var i := AudioServer.get_bus_index(bus)
		if i >= 0:
			AudioServer.set_bus_volume_db(i, duck_db)


## The seal: the second engine lights -> the hum powers up -> the wind shuts out (TUNE.seal_*).
func _seal(mph: float, dt: float, duck: float) -> void:
	var on_mph: float = EngineAudio.TUNE.second_on_mph
	var off_mph: float = EngineAudio.TUNE.second_off_mph
	if not sealed and mph >= on_mph:
		sealed = true
		_seal_age = 0.0
	elif sealed and mph < off_mph:
		sealed = false
		_seal_age = 0.0
	_seal_age += dt
	var hum_on: bool = sealed and _seal_age >= TUNE.seal_catch_s
	var shut: bool = sealed and _seal_age >= TUNE.seal_catch_s + TUNE.seal_shut_s
	hum = _follow(hum, 1.0 if hum_on else 0.0, TUNE.hum_attack if hum_on else TUNE.hum_release, dt)
	seal = _follow(seal, 1.0 if shut else 0.0, TUNE.seal_close if shut else TUNE.seal_open, dt)
	var lvl: float = hum * duck * db_to_linear(lerpf(TUNE.hum_db[0], TUNE.hum_db[1], smoothstep(on_mph, 4000.0, mph)))
	hum_player.volume_db = linear_to_db(lvl) if lvl > 1e-4 else -80.0
	var rise: float = clampf((_seal_age - TUNE.seal_catch_s) / TUNE.hum_rise_s, 0.0, 1.0) if sealed else 1.0
	hum_player.pitch_scale = lerpf(TUNE.hum_rise[0], TUNE.hum_rise[1], smoothstep(0.0, 1.0, rise)) * (1.0 + 0.04 * smoothstep(on_mph, 4500.0, mph))
	var lp := AudioServer.get_bus_effect(AudioServer.get_bus_index("Wind"), _seal_fx) as AudioEffectLowPassFilter
	if lp:
		lp.cutoff_hz = TUNE.seal_hz[0] * pow(TUNE.seal_hz[1] / TUNE.seal_hz[0], seal)


static func _follow(cur: float, target: float, tau: float, dt: float) -> float:
	return target + (cur - target) * exp(-dt / maxf(tau, 1e-4))


## Speed onto 0..1, log scale: 20 mph -> 0, 2,500 mph -> 1.
static func speed_g(mph: float) -> float:
	return clampf(log(maxf(mph, 1.0) / TUNE.mph_lo) / log(TUNE.mph_hi / TUNE.mph_lo), 0.0, 1.0)


## The air-brake shudder's waveform for side k at time t, -1..1: three incommensurate buffets
## (4.3, 6.9, 9.4 Hz) gated by a slower surge, so it comes in uneven bursts, never a steady buzz.
static func shudder_wave(t: float, k: int) -> float:
	var w := 0.5 * sin(TAU * 4.3 * t + k * 1.7) + 0.3 * sin(TAU * 6.9 * t + k * 0.6 + 2.0) + 0.2 * sin(TAU * 9.4 * t + k * 2.9 + 4.1)
	return w * (0.4 + 0.6 * (0.5 + 0.5 * sin(TAU * 1.1 * t + k)))


func update(_inp: Dictionary, delta: float) -> void:
	var dt := minf(delta, 0.1)
	_t += dt
	var p = sim.pod
	var v: float = sqrt(p.vx * p.vx + p.vy * p.vy)
	var mph := v * 2.236936
	var g := speed_g(mph)
	var moving := smoothstep(3.0, 25.0, mph)   # fade in from a standstill
	var slip := 0.0
	if v > 10.0:
		slip = clampf(absf(angle_difference(atan2(p.vy, p.vx), p.th)) / 0.25, 0.0, 1.0)
	var air := 1.0 - clampf(p.grip, 0.0, 1.0)
	var duck := 0.0 if sim.crash_t > 0.0 else 1.0
	var mach := v / SOUND
	if _boom_armed and mach >= 1.0 and duck > 0.0:
		_boom_armed = false
		boom()
	elif mach < 0.9:
		_boom_armed = true
	_duck(dt)
	_seal(mph, dt, duck)
	var gust := 0.5 + 0.5 * _noise.get_noise_1d(_t * (0.8 + 2.5 * g))   # gusts quicken with speed
	var targets := {
		"rush": db_to_linear(lerpf(TUNE.rush_db[0], TUNE.rush_db[1], pow(g, 0.8))),
		"buffet": db_to_linear(lerpf(TUNE.buffet_db[0], TUNE.buffet_db[1], g)
			+ TUNE.gust_db * (gust - 0.5) + TUNE.slip_db * slip + TUNE.air_db * air),
		"whistle": db_to_linear(lerpf(TUNE.whistle_db[0], TUNE.whistle_db[1], smoothstep(0.62, 1.0, g))),
	}
	# air brakes: each side's flaps follow its brake; the roar grows with speed and opening
	var brk := [float(_inp.get("brkL", 0.0)), float(_inp.get("brkR", 0.0))]
	for k in 2:
		_open[k] = _follow(_open[k], clampf(brk[k], 0.0, 1.0), TUNE.flap_tau, dt)
		targets["flap" + ("L" if k == 0 else "R")] = db_to_linear(lerpf(TUNE.flap_db[0], TUNE.flap_db[1], pow(g, 0.9))) * pow(_open[k], 0.7)
	# the shudder: open flaps at speed buffet in irregular 4-9 Hz bursts (Luke: "should have a
	# shudder to them too"), heard in the roar and felt through the cockpit
	var buffet_g := smoothstep(0.15, 0.7, g) * moving * duck
	for k in 2:
		shake[k] = shudder_wave(_t, k)
		shudder[k] = pow(_open[k], 0.8) * buffet_g * (0.55 + 0.45 * absf(shake[k]))
	for layer in levels:
		levels[layer] = _follow(levels[layer], targets[layer] * moving * duck, TUNE.smooth, dt)
		var lin: float = levels[layer]
		if layer.begins_with("flap"):
			var k := 0 if layer == "flapL" else 1
			lin *= 1.0 + TUNE.flap_shudder * pow(_open[k], 0.8) * buffet_g * shake[k]
		lin *= db_to_linear(TUNE.seal_db * seal)   # sealed in: the wind shut out
		players[layer].volume_db = linear_to_db(lin) if lin > 1e-4 else -80.0
	players.rush.pitch_scale = 0.85 + 0.35 * g
	players.whistle.pitch_scale = 0.8 + 0.7 * g
	players.flapL.pitch_scale = 0.75 + 0.3 * g    # the rumble deepens as you slow (and stays a rumble flat out)
	players.flapR.pitch_scale = 0.77 + 0.3 * g    # a touch apart, so the two sides don't phase
	var cut: float = TUNE.rush_hz[0] * pow(TUNE.rush_hz[1] / TUNE.rush_hz[0], g) * (1.0 - 0.35 * air)
	_cut = _follow(_cut, cut, TUNE.smooth, dt)
	(AudioServer.get_bus_effect(_rush_bus, 0) as AudioEffectLowPassFilter).cutoff_hz = _cut
