## WindAudio: the air the pod is tearing through. Three stereo noise loops, synthesized once at
## setup (no assets), decorrelated left and right so the wind sits around your head. Each is a loop
## of its own length (NOISE_LOOP_S), long enough that its repeat is not heard:
##   rush    pink noise: the airstream. Louder with speed; its low-pass opens with speed, so
##           it brightens from a hiss at a jog to a tearing roar at 5,000 mph.
##   buffet  brown-noise rumble with slow gusts: kicks up when the craft slides (slip angle)
##           and when it's airborne.
##   whistle a resonant shriek that comes in above ~1,000 mph and rises in pitch.
##   flaps   the air brakes: a deep rumbling roar heaved by a slow buffet, one per side, panned
##           to that ear, louder with speed and with how far that side's flaps are open.
##   drag    both air brakes hard out at speed: a bass rush under everything, the whole craft
##           leaning on the air. It needs both (one brake alone is a turn, not a stop), and the
##           seal does not shut it out: it comes through the hull.
## Plus a one-shot sonic boom on the way through Mach 1 (re-arms below Mach 0.9), on its own
## "Boom" bus: a heavy double-crack N-wave, its reflection off the desert floor, a sub thump and
## four seconds of rolling thunder, soft-clipped dense. The engines and the wind duck under it,
## and `boomed` fires so the cockpit can kick the controllers. From the second engine's lighting
## speed you're sealed in: the field's hum powers up on its own "Field" bus, then the wind shuts
## out behind it, quieter and muffled (`_seal`); under its off speed the air comes back.
## The field has a fixed, deep reverberation and a separate tone that rises with actual airspeed.
## Gear changes, throttle and engine RPM never retune either layer.
## Silent at rest, ducked with the picture on a crash. Same bus pattern as EngineAudio: the
## layers feed a "Wind" bus with a hard limiter, so wind can never clip the mix.
##   add_child(wind); wind.setup(sim)    once, inside the tree
##   wind.update(inp, delta)             every frame, after the sim steps
extends Node

const EngineAudio := preload("res://audio/engine_audio.gd")   # the seal follows its second engine
const RATE := 44100
const LOOP_S := 2.0     # the flaps', the drag's, the hum's and the speed tone's loops: their heaves and partials are whole cycles in it
# The three noise beds' loops, each its own length so their repeats never line up. (They were LOOP_S. Luke,
# after flight 35: "the tunnels has a swooshing sound every second and a half": the 2 s rush loop, played at
# pitch 1.14 at 1,127 mph, came round every 1.75 s, and under a city's hall the roof's reverb lifts the Wind
# bus about 9 dB. Measured in the game's mix, tests/film_swoosh.gd.) At its highest pitch (1.2) the rush now
# repeats every 8.3 s; each is normalised to the RMS its 2 s loop had, so every layer's level holds.
const NOISE_LOOP_S := {"rush": 10.0, "whistle": 8.3, "buffet": 7.1}
const XF_S := 0.25      # loop crossfade
const SOUND := 343.0    # m/s
const BOOM_S := 4.2
const BOOM_DB := -7.0      # boom player level. It was +2 into the Boom bus limiter (Luke, after flying it: "turn down the sonic boom at mach 1")
const DUCK_DB := -8.0      # engines and wind under the boom (was -14: a quieter boom needs less room made for it) ...
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
	# The bass rush (Luke: "a super bassy wind rush when both air brakes are fully depressed at
	# speed"): its level with both sides' flaps past drag_full[1], fading in from drag_full[0], and
	# over speed g drag_g[0] -> drag_g[1] (about 180 -> 950 mph).
	"drag_db": -5.0, "drag_full": [0.8, 0.98], "drag_g": [0.45, 0.8],
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
	"speed_tone_db": [-27.0, -21.0],    # separate from the deep layer, behind the engines
	"speed_tone_per_double": 0.65,     # pitch ratio added for each doubling of airspeed; no top-speed cap
	"speed_tone_tau": 0.25,            # smooth real acceleration/deceleration without a power-up sweep
}

var sim
var streams := {}   # layer -> AudioStreamWAV (tests read these)
var players := {}   # layer -> AudioStreamPlayer
var levels := {"rush": 0.0, "buffet": 0.0, "whistle": 0.0, "flapL": 0.0, "flapR": 0.0, "drag": 0.0}   # smoothed linear gains (tests read these)
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
var speed_player: AudioStreamPlayer   # the shield's separate airspeed tone
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
	var busmap := {"rush": "WindRush", "buffet": "WindBuffet", "whistle": "Wind", "flapL": "WindFlapL", "flapR": "WindFlapR", "drag": "Wind"}
	var t0 := Time.get_ticks_msec()
	streams.flap = make_loop("flap", 1777)
	streams.drag = make_loop("drag", 2024)
	for layer in ["rush", "buffet", "whistle", "flapL", "flapR", "drag"]:
		if not layer.begins_with("flap") and not streams.has(layer):
			streams[layer] = make_loop(layer, 1000 + layer.length(), NOISE_LOOP_S.get(layer, LOOP_S))
		var p := AudioStreamPlayer.new()
		p.stream = streams.flap if layer.begins_with("flap") else streams[layer]
		p.bus = busmap[layer]
		p.volume_db = -80.0
		add_child(p)
		p.play(randf() * p.stream.get_length())
		players[layer] = p
	_bus("Field", "Master")   # the field bypasses the sealed wind's low-pass
	var rumble_bus := _bus("FieldRumble", "Field")
	# Buses outlive scenes. Reuse the reverb after a course restart instead of stacking tails.
	# Only the low layer reverberates: comb filtering must not obscure the speed tone's pitch.
	var has_reverb := false
	for k in AudioServer.get_bus_effect_count(rumble_bus):
		has_reverb = has_reverb or AudioServer.get_bus_effect(rumble_bus, k) is AudioEffectReverb
	if not has_reverb:
		var reverb := AudioEffectReverb.new()
		reverb.room_size = 0.8
		reverb.damping = 0.75
		reverb.hipass = 0.0   # preserve the36Hz foundation
		reverb.predelay_msec = 35.0
		reverb.predelay_feedback = 0.2
		reverb.dry = 0.85
		reverb.wet = 0.32
		AudioServer.add_bus_effect(rumble_bus, reverb)
	hum_player = AudioStreamPlayer.new()
	hum_player.stream = make_hum()
	hum_player.bus = "FieldRumble"
	hum_player.volume_db = -80.0
	add_child(hum_player)
	hum_player.play()
	speed_player = AudioStreamPlayer.new()
	speed_player.stream = make_speed_tone()
	speed_player.bus = "Field"
	speed_player.volume_db = -80.0
	add_child(speed_player)
	speed_player.play()
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
	print("AUDIO: WindAudio up, 5 stereo loops + a boom synthesized in %d ms (%d more booms on a worker)" % [Time.get_ticks_msec() - t0, BOOM_VARIANTS.size() - 1])


## Get or create a bus routed into `send` (same helper as EngineAudio).
static func _bus(name: String, send: String) -> int:
	var i := AudioServer.get_bus_index(name)
	if i < 0:
		i = AudioServer.bus_count
		AudioServer.add_bus(i)
		AudioServer.set_bus_name(i, name)
	AudioServer.set_bus_send(i, send)
	return i


## One seamless stereo loop of the given noise colour. Generated `secs` + XF_S long, then the
## tail is crossfaded (equal power) into the head, so the jump from the last sample back to the
## first lands on the sample that originally followed it. `secs` is the noise beds' own (rush,
## buffet, whistle: NOISE_LOOP_S); the flap's and the drag's heaves are whole cycles in LOOP_S, so
## theirs is always LOOP_S. Longer than LOOP_S, a loop is scaled to the RMS its LOOP_S loop (the
## same seed) has, not to the same peak: a longer stretch of noise reaches a higher peak, and
## peak-normalised it came out about 1 dB quieter.
static func make_loop(kind: String, seed: int, secs := LOOP_S) -> AudioStreamWAV:
	if not kind in ["rush", "buffet", "whistle"]:
		secs = LOOP_S
	var n := int(RATE * secs)
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
		elif kind == "drag":
			# Both air brakes hard out at speed: the whole craft leaning on the air. Deeper than the
			# flaps' roar: brown noise held to about 28-150 Hz with the hull booming at 52, 78 and
			# 116 Hz (at 41, 62 and 93 it measured 81% under 80 Hz: felt on a subwoofer, absent in a
			# headset), heaved slowly, then saturated hard so its harmonics carry the weight up to where
			# a headset's small speakers can play it (they give back little under 80 Hz), and
			# low-passed again so none of it turns to hiss.
			var m := n + xf
			var parts: Array[PackedFloat32Array] = []
			for p in 4:
				var a := PackedFloat32Array()
				a.resize(m)
				parts.append(a)
			var lp_a := 1.0 - exp(-TAU * 150.0 / RATE)
			var hp_a := exp(-TAU * 28.0 / RATE)
			var res_r := [0.9985, 0.998, 0.9975]
			var res_a1 := []
			for r in 3:
				res_a1.append(2.0 * res_r[r] * cos(TAU * [52.0, 78.0, 116.0][r] / RATE))
			var y1 := [0.0, 0.0, 0.0]
			var y2 := [0.0, 0.0, 0.0]
			var br := 0.0
			var l1 := 0.0
			var l2 := 0.0
			var h1 := 0.0
			var h1_in := 0.0
			var sq := [0.0, 0.0, 0.0, 0.0]
			for i in m:
				var w := rng.randf_range(-1.0, 1.0)
				br = (br + 0.02 * w) / 1.02   # brown
				l1 += lp_a * (br - l1)
				l2 += lp_a * (l1 - l2)
				h1 = hp_a * (h1 + l2 - h1_in)
				h1_in = l2
				parts[0][i] = h1
				sq[0] += h1 * h1
				for r in 3:   # the hull booming
					var rr: float = res_r[r]
					var y: float = (1.0 - rr) * w + res_a1[r] * y1[r] - rr * rr * y2[r]
					y2[r] = y1[r]
					y1[r] = y
					parts[r + 1][i] = y
					sq[r + 1] += y * y
			var gains := [0.6, 0.8, 1.1, 1.6]
			for p in 4:
				gains[p] = gains[p] / sqrt(maxf(sq[p] / m, 1e-20))
			var ph := [rng.randf() * TAU, rng.randf() * TAU]
			var sum_sq := 0.0
			for i in m:
				# the heave: 0.5 and 1.5 Hz, whole cycles in the 2 s loop so it stays seamless
				var t := float(i % n) / RATE
				var heave: float = 0.72 + 0.18 * sin(TAU * 0.5 * t + ph[0]) + 0.1 * sin(TAU * 1.5 * t + ph[1])
				buf[i] = (gains[0] * parts[0][i] + gains[1] * parts[1][i] + gains[2] * parts[2][i] + gains[3] * parts[3][i]) * heave
				sum_sq += buf[i] * buf[i]
			var drive := 4.5 / sqrt(maxf(sum_sq / m, 1e-20))   # hard: the third and fifth harmonics (156-580 Hz) are what a headset plays best
			var lp_b := 1.0 - exp(-TAU * 400.0 / RATE)
			var s1 := 0.0
			var s2 := 0.0
			for i in m:
				s1 += lp_b * (tanh(drive * buf[i]) - s1)
				s2 += lp_b * (s1 - s2)
				buf[i] = s2
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
	if secs != LOOP_S:   # the level its LOOP_S loop had
		var want := _rms16(make_loop(kind, seed))
		var sq := 0.0
		for buf in chans:
			for v in buf:
				sq += v * v
		k = want / (32767.0 * sqrt(sq / (2.0 * n)))
	var left := chans[0]
	var right := chans[1]
	var data := PackedByteArray()
	data.resize(n * 4)
	for i in n:
		data.encode_s16(i * 4, int(clampf(left[i] * k, -1.0, 1.0) * 32767.0))
		data.encode_s16(i * 4 + 2, int(clampf(right[i] * k, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.stereo = true
	w.mix_rate = RATE
	w.data = data
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = n
	return w


## A 16-bit stereo stream's RMS, both channels, in sample units.
static func _rms16(w: AudioStreamWAV) -> float:
	var d := w.data
	var sq := 0.0
	for i in d.size() / 2:
		var v := float(d.decode_s16(i * 2))
		sq += v * v
	return sqrt(sq / maxf(d.size() / 2, 1))


## A fixed, deep field resonance: 36 Hz with gentle harmonics at 72/108/144 Hz so the headset's
## small speakers still carry its weight. The ears beat slowly; FieldRumble supplies the tail.
## Every partial and the slow heave fit whole cycles in LOOP_S, keeping the loop seamless.
static func make_hum() -> AudioStreamWAV:
	var n := int(RATE * LOOP_S)
	var data := PackedByteArray()
	data.resize(n * 4)
	for i in n:
		var t := float(i) / RATE
		for c in 2:
			var f := 36.0 + 0.5 * c
			var x := 0.68 * sin(TAU * f * t) + 0.24 * sin(TAU * 2.0 * f * t + 0.3) \
				+ 0.18 * sin(TAU * 3.0 * f * t + 1.1) + 0.08 * sin(TAU * 4.0 * f * t + 2.0)
			x *= 0.72 * (0.92 + 0.08 * sin(TAU * 0.5 * t + c * 0.4))
			data.encode_s16(i * 4 + c * 2, int(clampf(x, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.stereo = true
	w.mix_rate = RATE
	w.data = data
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_end = n
	return w


## A separate, restrained tone above the rumble. Its playback pitch follows airspeed only.
static func make_speed_tone() -> AudioStreamWAV:
	var n := int(RATE * LOOP_S)
	var data := PackedByteArray()
	data.resize(n * 4)
	for i in n:
		var t := float(i) / RATE
		for c in 2:
			var phase := c * 0.3
			var x := 0.68 * sin(TAU * 180.0 * t + phase) + 0.16 * sin(TAU * 360.0 * t + phase + 0.4) \
				+ 0.05 * sin(TAU * 540.0 * t + phase + 1.0)
			data.encode_s16(i * 4 + c * 2, int(x * 0.7 * 32767.0))
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
	hum_player.pitch_scale = 1.0
	var tone_level: float = hum * duck * db_to_linear(lerpf(TUNE.speed_tone_db[0], TUNE.speed_tone_db[1], smoothstep(on_mph, 4000.0, mph)))
	speed_player.volume_db = linear_to_db(tone_level) if tone_level > 1e-4 else -80.0
	# Use the pod's measured speed, never the gearbox's RPM or the levers. Logarithmic growth
	# remains audible beyond fifth gear's old top speed without quickly turning into a shriek.
	var pitch: float = 1.0 + TUNE.speed_tone_per_double * log(maxf(mph, on_mph) / on_mph) / log(2.0)
	speed_player.pitch_scale = _follow(speed_player.pitch_scale, pitch, TUNE.speed_tone_tau, dt)
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
	var v: float = sqrt(p.vx * p.vx + p.vy * p.vy) / (float(sim.line_speed()) if sim.has_method("line_speed") else 1.0)   # the air the craft meets
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
	# both hard out at speed: the bass rush
	targets["drag"] = db_to_linear(TUNE.drag_db) * smoothstep(TUNE.drag_g[0], TUNE.drag_g[1], g) \
		* smoothstep(TUNE.drag_full[0], TUNE.drag_full[1], minf(_open[0], _open[1]))
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
		if layer != "drag":   # (the bass rush comes through the hull)
			lin *= db_to_linear(TUNE.seal_db * seal)   # sealed in: the wind shut out
		players[layer].volume_db = linear_to_db(lin) if lin > 1e-4 else -80.0
	players.rush.pitch_scale = 0.85 + 0.35 * g
	players.whistle.pitch_scale = 0.8 + 0.7 * g
	players.flapL.pitch_scale = 0.75 + 0.3 * g    # the rumble deepens as you slow (and stays a rumble flat out)
	players.flapR.pitch_scale = 0.77 + 0.3 * g    # a touch apart, so the two sides don't phase
	players.drag.pitch_scale = 0.85 + 0.3 * g
	var cut: float = TUNE.rush_hz[0] * pow(TUNE.rush_hz[1] / TUNE.rush_hz[0], g) * (1.0 - 0.35 * air)
	_cut = _follow(_cut, cut, TUNE.smooth, dt)
	(AudioServer.get_bus_effect(_rush_bus, 0) as AudioEffectLowPassFilter).cutoff_hz = _cut
