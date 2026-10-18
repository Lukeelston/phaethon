## WindAudio: the air the pod is tearing through. Three stereo noise loops, synthesized once at
## setup (no assets), decorrelated left and right so the wind sits around your head:
##   rush    pink noise: the airstream. Louder with speed; its low-pass opens with speed, so
##           it brightens from a hiss at a jog to a tearing roar at 5,000 mph.
##   buffet  brown-noise rumble with slow gusts: kicks up when the craft slides (slip angle)
##           and when it's airborne.
##   whistle a resonant shriek that comes in above ~1,000 mph and rises in pitch.
## Silent at rest, ducked with the picture on a crash. Same bus pattern as EngineAudio: the
## layers feed a "Wind" bus with a hard limiter, so wind can never clip the mix.
##   add_child(wind); wind.setup(sim)    once, inside the tree
##   wind.update(inp, delta)             every frame, after the sim steps
extends Node

const RATE := 44100
const LOOP_S := 2.0     # seamless loops; filtering and gusts hide the repeat
const XF_S := 0.25      # loop crossfade

const TUNE := {
	"mph_lo": 20.0, "mph_hi": 2500.0,   # speed range mapped onto g = 0..1 (log scale)
	"rush_db": [-46.0, -9.0],
	"rush_hz": [300.0, 12000.0],        # rush low-pass, g 0 -> 1
	"rush_hp_hz": 140.0,                # rush high-pass: below this is the buffet's band
	"buffet_db": [-52.0, -13.0],
	"buffet_hz": 150.0,
	"whistle_db": [-60.0, -18.0],       # fades in over g 0.62..1 (~1,000 -> 2,500 mph)
	"slip_db": 12.0, "air_db": 6.0, "gust_db": 6.0,
	"smooth": 0.08,                     # parameter smoothing, s
}

var sim
var streams := {}   # layer -> AudioStreamWAV (tests read these)
var players := {}   # layer -> AudioStreamPlayer
var levels := {"rush": 0.0, "buffet": 0.0, "whistle": 0.0}   # smoothed linear gains (tests read these)
var _cut := 300.0
var _t := 0.0
var _noise := FastNoiseLite.new()
var _rush_bus := 0


func setup(craft_sim) -> void:
	sim = craft_sim
	_noise.seed = 4242
	_noise.frequency = 0.9
	var wind_bus := _bus("Wind", "Master")
	if AudioServer.get_bus_effect_count(wind_bus) == 0:
		var lim := AudioEffectHardLimiter.new()
		lim.ceiling_db = -1.0
		AudioServer.add_bus_effect(wind_bus, lim)
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
	var busmap := {"rush": "WindRush", "buffet": "WindBuffet", "whistle": "Wind"}
	var t0 := Time.get_ticks_msec()
	for layer in ["rush", "buffet", "whistle"]:
		streams[layer] = make_loop(layer, 1000 + layer.length())
		var p := AudioStreamPlayer.new()
		p.stream = streams[layer]
		p.bus = busmap[layer]
		p.volume_db = -80.0
		add_child(p)
		p.play(randf() * LOOP_S)
		players[layer] = p
	print("AUDIO: WindAudio up, 3 stereo loops synthesized in %d ms" % (Time.get_ticks_msec() - t0))


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


static func _follow(cur: float, target: float, tau: float, dt: float) -> float:
	return target + (cur - target) * exp(-dt / maxf(tau, 1e-4))


## Speed onto 0..1, log scale: 20 mph -> 0, 2,500 mph -> 1.
static func speed_g(mph: float) -> float:
	return clampf(log(maxf(mph, 1.0) / TUNE.mph_lo) / log(TUNE.mph_hi / TUNE.mph_lo), 0.0, 1.0)


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
	var gust := 0.5 + 0.5 * _noise.get_noise_1d(_t * (0.8 + 2.5 * g))   # gusts quicken with speed
	var targets := {
		"rush": db_to_linear(lerpf(TUNE.rush_db[0], TUNE.rush_db[1], pow(g, 0.8))),
		"buffet": db_to_linear(lerpf(TUNE.buffet_db[0], TUNE.buffet_db[1], g)
			+ TUNE.gust_db * (gust - 0.5) + TUNE.slip_db * slip + TUNE.air_db * air),
		"whistle": db_to_linear(lerpf(TUNE.whistle_db[0], TUNE.whistle_db[1], smoothstep(0.62, 1.0, g))),
	}
	for layer in levels:
		levels[layer] = _follow(levels[layer], targets[layer] * moving * duck, TUNE.smooth, dt)
		var lin: float = levels[layer]
		players[layer].volume_db = linear_to_db(lin) if lin > 1e-4 else -80.0
	players.rush.pitch_scale = 0.85 + 0.35 * g
	players.whistle.pitch_scale = 0.8 + 0.7 * g
	var cut: float = TUNE.rush_hz[0] * pow(TUNE.rush_hz[1] / TUNE.rush_hz[0], g) * (1.0 - 0.35 * air)
	_cut = _follow(_cut, cut, TUNE.smooth, dt)
	(AudioServer.get_bus_effect(_rush_bus, 0) as AudioEffectLowPassFilter).cutoff_hz = _cut
