## EngineAudio: one voice per pod engine, built from the piano-baked loops in res://audio/engines
## (tools/engine_bake.py). Each voice blends three machines: a V8 for the low-end burble, a V12
## that takes over through the mid range, and a turbine whine that rides the spool, over a roar
## that opens up with it. The afterburner and ramjet add a burner rumble on top.
## Every layer is one master performance played at the engine's speed (pitch = rpm / rate_at),
## so a ramp is one continuous signal. (Per-RPM bands crossfaded into each other "stepped
## through selected tones": every band had its own timbre.) Pitching up to 15x would alias, so
## each master comes as anti-alias levels, sample-aligned copies an octave of pitch apart, and
## crossfading them only fades the top octave. The muffler is a fixed low-pass per layer and the
## roar's low-pass follows the spool, so neither moves with pitch. The left engine pans left and
## the right engine pans right, so a lever split or a dead engine is something you hear.
## The second engine is a big-bang four that lights once the craft passes second_on_mph: each
## side cranks and coughs, catches with a bang (left first, right a beat later), runs on its
## lever behind a fixed throat EQ, and backfires and winds down below second_off_mph. Its rpm
## also lifts with speed above that, so it winds up as you accelerate on a steady lever. Sound
## only for now: it adds no thrust.
## Under it all, the bass rotor: the first engine's low end, wound up by airspeed like a big
## turbine. A ~28 Hz rumble at a standstill climbs three octaves by second_on_mph behind a
## low-pass that opens with it, swells with each side's lever, and steps back for the second
## engine once that side is running.
## Polish: the right engine runs a hair off the left (wandering), so equal levers beat slowly
## like twin engines that never quite sync. Lifting off at high revs spits pops and crackle
## for a moment. The spool is a spring: a lever stab revs up in ~0.15 s, flares ~11% past the
## lever and barks (+3 dB for a moment); lifting settles clean, with no undershoot.
## flat (tests) switches all three off: it isolates the crossfader.
##   add_child(audio); audio.setup(sim)    once, inside the tree
##   audio.update(inp, delta)              every frame, after the sim steps
class_name EngineAudio
extends Node

const DIR := "res://audio/engines/"
const LAYERS := ["v8", "v12", "turbine", "roar", "burner", "second", "rotor"]
const FILTERED := ["v8", "v12", "roar", "second", "rotor"]   # layers with their own low-pass bus under each engine
const SECOND_STATES := ["off", "wait", "crank", "run", "stop"]

## Everything that shapes the sound. Spool s: -0.33 stopped, 0 idle, 1 full lever; the
## afterburner and ramjet push past 1. Mix curves are [s, gain] knots, piecewise linear.
const TUNE := {
	"windmill": 1.6,                 # spool time constant winding down from a flameout, s
	"relight": 0.8,                  # spool-up time constant while still below idle (reignite)
	# The spool is a spring: [rising, falling]. Rising is snappy and flares ~11% past the lever
	# (90% of a stab in 0.14 s); falling is critically damped, so a lift settles clean.
	"rev_w": [16.0, 7.0], "rev_z": [0.65, 1.0],
	"bark_db": 3.0, "bark_s": 0.15,  # a quick stab barks: up to +3 dB, gone in 0.15 s
	"crank": 0.3,                    # pistons bottom out at this fraction of idle RPM
	"burner_spool": 0.15, "ramjet_spool": 0.3,
	"v8_rpm": [850.0, 7600.0], "v12_rpm": [1100.0, 11800.0], "turbine_n": [0.25, 1.0],
	"mix_v8": [[0.0, 1.0], [0.35, 0.85], [0.8, 0.45], [1.3, 0.35]],
	"mix_v12": [[0.0, 0.12], [0.3, 0.45], [0.7, 0.95], [1.3, 1.0]],
	"mix_turbine": [[-0.33, 0.0], [0.0, 0.3], [0.6, 0.5], [1.0, 0.7], [1.3, 0.9]],
	"burner_gain": 0.8, "burner_fade": 0.25,
	"muffler_hz": {"v8": 2400.0, "v12": 7000.0, "second": 1200.0},   # fixed: the exhaust colour doesn't ride the pitch
	"roar_hz": [250.0, 3450.0],      # roar low-pass, turbine spool 0 -> 1
	"roar_gain": [0.35, 1.0],        # roar level relative to the whine, spool 0 -> 1
	"level_db": [-15.0, -8.0],       # whole voice, idle -> full lever
	"lp_hz": [700.0, 16000.0],       # bus low-pass, off-load (lifting) -> on-load (pulling)
	"pan": 0.6,
	"cough_s": 0.7,                  # after a reignite, combustion catches in fits for this long
	# The second engine (sound only): lights above second_on_mph, dies below second_off_mph.
	"second_on_mph": 1500.0, "second_off_mph": 1300.0,
	"second_rpm": [600.0, 3800.0],   # low and slow: ~63 Hz doublets at full lever, the lope at half that
	"second_stagger": 0.3,           # the right side lights this long after the left
	"second_crank_s": 0.7,           # cranking and coughing before it catches
	"second_wind": 1.2,              # winding down once it stops, s (it revs on the same spring)
	"second_level_db": [-15.0, -7.0],   # its own level, idle -> full lever: leads the mix by ~6 dB when lit
	"second_eq_db": [6.0, 8.0, 2.0, -2.0, -8.0, -14.0],   # EQ6 at 32/100/320/1k/3.2k/10k Hz: chest and throat
	"bang_db": [-2.0, -8.0],         # catching, backfiring on the way down
	"second_lift": 0.7, "second_lift_mph": 4500.0,   # rpm x (1 + lift) from second_on_mph to this
	# The bass rotor: pitch 2^(rotor_oct * (speed / second_on_mph)^rotor_curve).
	"rotor_oct": 3.0,                # octaves it climbs from a standstill to second_on_mph
	"rotor_curve": 0.8,              # under 1: it climbs quicker off the line
	"rotor_tau": 0.3,                # follows airspeed with this lag, s
	"rotor_lever_pitch": 0.06,       # each side's lever lifts its rotor this much more
	"rotor_lp_hz": [160.0, 3000.0],  # its low-pass, standstill -> second_on_mph: boomy, then singing
	"rotor_db": [-5.0, -11.0],       # standstill -> second_on_mph: bassiest down low
	"rotor_lever": [0.4, 1.0],       # level scale, lever 0 -> 1
	"rotor_handover_db": -10.0,      # once that side's second engine is running
	# Twin engines never quite sync: the right one runs this much fast, wandering, so equal
	# levers beat slowly (pistons, second engine, rotor; the 2.4 kHz whine would just go rough).
	"twin_detune": 0.0035, "twin_wander": [0.0015, 17.0],   # [amplitude, period s]
	# Overrun: lifting off from above pop_rpm spool, pop_lift or more over the lever, spits
	# pops and crackle for pop_s, tapering from pop_rate per second.
	"pop_rpm": 0.5, "pop_lift": 0.2, "pop_s": 1.2, "pop_rate": 14.0,
	"pop_db": -9.0,                  # first engine; the randomizer varies each pop by 8 dB
	"pop2_pitch": 0.65, "pop2_db": -7.0,   # the second engine's pops, deeper, through its throat
}

var sim
var solo := ""   # "v8", "v12", "turbine" or "burner": hear one layer alone (tests, tuning)
var flat := false   # tests: every gain held at 1 and the low-pass open, so only crossfades move the level
var voices: Array = []
var _bands := {}   # layer -> PackedFloat64Array of baked rpm / spool values
var _streams := {}   # layer -> Array[AudioStreamWAV]
var _rho := {}   # layer -> PackedFloat64Array: correlation of level i with level i + 1
var _rate_at := {}   # layer -> rpm (or spool) the master sounds at on pitch 1, 0 = pitch per band
var _bang: AudioStreamWAV
var _pops: AudioStreamRandomizer
var _t := 0.0   # seconds of update, for the twin wander
var second_on := false   # craft fast enough for the second engine (with hysteresis)


func setup(craft_sim) -> void:
	sim = craft_sim
	_load_streams()
	# Engines and Wind each limit their own bus to -1 dB, but their sum lands on Master unlimited:
	# with both peaking together it could clip (engines + wind measured -0.05 dBFS on Master).
	# A last-resort limiter there touches only true overs.
	var has_limiter := false
	for i in AudioServer.get_bus_effect_count(0):
		has_limiter = has_limiter or AudioServer.get_bus_effect(0, i) is AudioEffectHardLimiter
	if not has_limiter:
		var safety := AudioEffectHardLimiter.new()
		safety.ceiling_db = -0.3
		AudioServer.add_bus_effect(0, safety)
	var engines_bus := _bus("Engines", "Master")
	if AudioServer.get_bus_effect_count(engines_bus) == 0:
		var lim := AudioEffectHardLimiter.new()
		lim.ceiling_db = -1.0
		AudioServer.add_bus_effect(engines_bus, lim)
	for k in 2:
		var name: String = ["EngineL", "EngineR"][k]
		var bus := _bus(name, "Engines")
		if AudioServer.get_bus_effect_count(bus) == 0:
			AudioServer.add_bus_effect(bus, AudioEffectLowPassFilter.new())
			var pan := AudioEffectPanner.new()
			pan.pan = -TUNE.pan if k == 0 else TUNE.pan
			AudioServer.add_bus_effect(bus, pan)
		var subs := {}
		for layer in FILTERED:
			var sub := _bus("%s_%s" % [name, layer], name)
			if AudioServer.get_bus_effect_count(sub) == 0:
				AudioServer.add_bus_effect(sub, AudioEffectLowPassFilter.new())
			var lp := AudioServer.get_bus_effect(sub, 0) as AudioEffectLowPassFilter
			lp.cutoff_hz = TUNE.muffler_hz.get(layer, TUNE.roar_hz[0])
			if layer == "second" and AudioServer.get_bus_effect_count(sub) == 1:
				var eq := AudioEffectEQ6.new()
				for band in 6:
					eq.set_band_gain_db(band, TUNE.second_eq_db[band])
				AudioServer.add_bus_effect(sub, eq)
			subs[layer] = sub
		var bang := AudioStreamPlayer.new()
		bang.stream = _bang
		bang.bus = "%s_second" % name
		add_child(bang)
		# pops skip the load low-pass (which closes on a lift): their own bus, same pan
		var pop_bus := _bus("%s_pops" % name, "Engines")
		if AudioServer.get_bus_effect_count(pop_bus) == 0:
			var pp := AudioEffectPanner.new()
			pp.pan = -TUNE.pan if k == 0 else TUNE.pan
			AudioServer.add_bus_effect(pop_bus, pp)
		var pops := AudioStreamPlayer.new()
		pops.stream = _pops
		pops.bus = "%s_pops" % name
		pops.max_polyphony = 6
		pops.volume_db = TUNE.pop_db
		add_child(pops)
		var pops2 := AudioStreamPlayer.new()
		pops2.stream = _pops
		pops2.bus = "%s_second" % name
		pops2.max_polyphony = 6
		pops2.pitch_scale = TUNE.pop2_pitch
		pops2.volume_db = TUNE.pop2_db
		add_child(pops2)
		var v := {"bus": bus, "subs": subs, "spool": 0.0, "comb": 1.0, "fire": 1.0, "load": 0.5, "burn": 0.0,
			"was_out": false, "cough_t": 0.0, "cough_k": 1.0, "cough_next": 0.0, "players": {}, "at": {},
			"bang": bang, "sec": {"state": "off", "t": 0.0, "spool": -0.33, "vel": 0.0, "fire": 0.0, "cough_k": 0.0, "cough_next": 0.0},
			"rotor_mph": 0.0, "rotor_p": 1.0, "sec_run": 0.0,
			"spool_v": 0.0, "lever_prev": 0.0, "bark": 0.0,
			"pops": pops, "pops2": pops2, "pop_t": 0.0, "pop_k": 0.0, "pop2_t": 0.0, "pop2_k": 0.0, "pops_n": 0}
		for layer in LAYERS:
			var ps: Array[AudioStreamPlayer] = []
			var start := randf()   # per engine, so the two engines never phase against each other
			for i in _streams[layer].size():
				var s: AudioStreamWAV = _streams[layer][i]
				var p := AudioStreamPlayer.new()
				p.stream = s
				p.bus = "%s_%s" % [name, layer] if layer in FILTERED else name
				p.volume_db = -80.0
				add_child(p)
				# anti-alias levels: all from the same spot, in the same frame, so in lockstep
				p.play((start if _rate_at[layer] > 0.0 else randf()) * s.get_length())
				ps.append(p)
			v.players[layer] = ps
		voices.append(v)
	var loops := 0
	for layer in LAYERS:
		loops += _streams[layer].size()
	print("AUDIO: EngineAudio up, %d voices x %d loops, driver %s at %d Hz" % [voices.size(), loops,
		AudioServer.get_driver_name(), AudioServer.get_mix_rate()])


func _load_streams() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DIR + "manifest.json"))
	for layer in LAYERS:
		var ats := PackedFloat64Array()
		var list: Array[AudioStreamWAV] = []
		var rhos := PackedFloat64Array()
		var spec: Dictionary = manifest.layers[layer]
		for b: Dictionary in spec.bands:
			var w := AudioStreamWAV.load_from_file(DIR + b.file, {"compress/mode": 0})
			w.loop_mode = AudioStreamWAV.LOOP_FORWARD
			w.loop_begin = 0
			w.loop_end = w.data.size() >> 1   # 16-bit mono frames
			list.append(w)
			ats.append(b.at)
			rhos.append(b.get("rho_next", 0.0))
		_streams[layer] = list
		_bands[layer] = ats
		_rho[layer] = rhos
		_rate_at[layer] = float(spec.get("rate_at", 0.0)) if spec.get("sync", false) else 0.0
	_bang = AudioStreamWAV.load_from_file(DIR + manifest.oneshots.bang, {"compress/mode": 0})
	_bang.loop_mode = AudioStreamWAV.LOOP_DISABLED
	_pops = AudioStreamRandomizer.new()
	_pops.playback_mode = AudioStreamRandomizer.PLAYBACK_RANDOM_NO_REPEATS
	_pops.random_pitch = 1.15            # each pop up to 15% up or down
	_pops.random_volume_offset_db = 8.0  # and up to 8 dB quieter
	for f: String in manifest.oneshots.pops:
		var w := AudioStreamWAV.load_from_file(DIR + f, {"compress/mode": 0})
		w.loop_mode = AudioStreamWAV.LOOP_DISABLED
		_pops.add_stream(-1, w)


## Get or create a bus routed into `send`.
static func _bus(name: String, send: String) -> int:
	var i := AudioServer.get_bus_index(name)
	if i < 0:
		i = AudioServer.bus_count
		AudioServer.add_bus(i)
		AudioServer.set_bus_name(i, name)
	AudioServer.set_bus_send(i, send)
	return i


static func _curve(knots: Array, x: float) -> float:
	if x <= knots[0][0]:
		return knots[0][1]
	for i in range(1, knots.size()):
		if x <= knots[i][0]:
			var a: Array = knots[i - 1]
			var b: Array = knots[i]
			return lerpf(a[1], b[1], (x - a[0]) / (b[0] - a[0]))
	return knots[-1][1]


static func _follow(cur: float, target: float, tau: float, dt: float) -> float:
	return target + (cur - target) * exp(-dt / maxf(tau, 1e-4))


## The layer's RPM (or turbine spool) for engine spool s. Below idle (a flameout winding
## down, a reignite catching) the pistons sink toward cranking speed and the turbine to a stop.
func layer_at(layer: String, s: float) -> float:
	match layer:
		"v8", "v12", "second":
			var r: Array = TUNE[layer + "_rpm"]
			if s >= 0.0:
				return lerpf(r[0], r[1], s)
			return r[0] * maxf(TUNE.crank, 1.0 + s / 0.33 * (1.0 - TUNE.crank))
		"roar":
			return 0.85 + 0.25 * clampf(s, 0.0, 1.3)   # a little pitch lift; the low-pass does the rest
		_:
			return maxf(0.02, lerpf(TUNE.turbine_n[0], TUNE.turbine_n[1], s))


func update(inp: Dictionary, delta: float) -> void:
	var dt := minf(delta, 0.1)
	_t += dt
	var gate: float = sim.P.gate
	var boost: float = {"burner": TUNE.burner_spool, "ramjet": TUNE.ramjet_spool}.get(sim.mode, 0.0)
	var duck := 0.0 if sim.crash_t > 0.0 else 1.0   # crash: the engines go with the picture
	var bodies := [sim.eL, sim.eR]
	var thr := [inp.thrL, inp.thrR]
	var mph: float = sqrt(sim.pod.vx * sim.pod.vx + sim.pod.vy * sim.pod.vy) * 2.23694
	if not second_on and mph >= TUNE.second_on_mph:
		second_on = true
	elif second_on and mph < TUNE.second_off_mph:
		second_on = false
	for k in 2:
		var v: Dictionary = voices[k]
		var e = bodies[k]
		var lever := minf(thr[k], gate) / gate
		if inp.get("repair", false):
			lever = minf(lever, 0.6)
		var target: float = -0.33 if e.flameout else lever + boost
		if e.flameout or v.spool < 0.0:
			# winding down from a flameout, or relighting from below idle: no flare
			v.spool = _follow(v.spool, target, TUNE.windmill if e.flameout else TUNE.relight, dt)
			v.spool_v = 0.0
		else:
			_rev(v, "spool", "spool_v", target, dt)
		# a quick stab barks; the bark dies away in bark_s
		var stab: float = clampf((lever - v.lever_prev) / maxf(dt, 1e-4) * 0.12, 0.0, 1.0)
		v.lever_prev = lever
		v.bark = maxf(v.bark * exp(-dt / TUNE.bark_s), stab)

		# Combustion: off at a flameout, in fits for a moment after a reignite, and the sim's
		# own sputter (a damaged engine misfiring) chops it on top.
		if v.was_out and not e.flameout:
			v.cough_t = TUNE.cough_s
		v.was_out = e.flameout
		if v.cough_t > 0.0:
			v.cough_t -= dt
			v.cough_next -= dt
			if v.cough_next <= 0.0:
				v.cough_next = randf_range(0.04, 0.12)
				v.cough_k = 0.15 if randf() < 0.5 else 1.0
		else:
			v.cough_k = 1.0
		var fire: float = 0.0 if e.flameout else v.cough_k
		v.fire = _follow(v.fire, fire, 0.05 if fire < v.fire else 0.12, dt)
		v.comb = _follow(v.comb, e.sputter, 0.02, dt)
		var burning: float = v.fire * v.comb

		# Load: pulling (lever ahead of spool) opens the low-pass, lifting closes it.
		var load := clampf(0.35 + 0.65 * lever + 3.0 * (target - v.spool), 0.0, 1.0)
		v.load = _follow(v.load, load, 0.12, dt)
		var lp: float = TUNE.lp_hz[1] if flat else TUNE.lp_hz[0] * pow(TUNE.lp_hz[1] / TUNE.lp_hz[0], v.load)
		AudioServer.get_bus_effect(v.bus, 0).cutoff_hz = lp

		var s: float = v.spool
		var level := db_to_linear(TUNE.level_db[1] if flat else lerpf(TUNE.level_db[0], TUNE.level_db[1], clampf(s, 0.0, 1.0))) * duck
		var bark := 1.0 if flat else db_to_linear(TUNE.bark_db * v.bark)
		# Overrun: lifting off at high revs spits pops and crackle for a moment.
		var over: float = v.spool - target
		if not flat and not e.flameout and v.spool > TUNE.pop_rpm and over > TUNE.pop_lift and v.pop_t <= 0.0:
			v.pop_t = TUNE.pop_s
			v.pop_k = clampf(over / 0.5, 0.3, 1.0)
		_pop(v, "pops", "pop_t", "pop_k", dt, duck)
		v.burn = _follow(v.burn, 1.0 if boost > 0.0 and not e.flameout else 0.0, TUNE.burner_fade, dt)
		var n_spool := clampf(layer_at("turbine", s), 0.0, 1.0)
		var turb := _curve(TUNE.mix_turbine, s)
		var gains := {
			"v8": _curve(TUNE.mix_v8, s) * burning * bark,
			"v12": _curve(TUNE.mix_v12, s) * burning * bark,
			"turbine": turb * (0.55 + 0.45 * burning),
			"roar": turb * lerpf(TUNE.roar_gain[0], TUNE.roar_gain[1], n_spool) * (0.4 + 0.6 * burning),
			"burner": TUNE.burner_gain * v.burn * burning,
		}
		var sec_gain := _second(v, k, lever + boost, dt, duck)
		gains["second"] = sec_gain * bark
		gains["rotor"] = _rotor(v, lever, mph, dt, duck)
		if flat:
			gains = {"v8": burning, "v12": burning, "turbine": 1.0, "roar": 1.0, "burner": v.burn * burning,
				"second": v.sec.fire, "rotor": 1.0}
		var roar_lp := AudioServer.get_bus_effect(v.subs.roar, 0) as AudioEffectLowPassFilter
		roar_lp.cutoff_hz = TUNE.roar_hz[1] if flat else lerpf(TUNE.roar_hz[0], TUNE.roar_hz[1], n_spool)
		var lift: float = 1.0 + TUNE.second_lift * clampf((mph - TUNE.second_on_mph)
			/ (TUNE.second_lift_mph - TUNE.second_on_mph), 0.0, 1.0)
		var twin := 1.0
		if k == 1 and not flat:
			twin += TUNE.twin_detune + TUNE.twin_wander[0] * sin(TAU * _t / TUNE.twin_wander[1])
		for layer in LAYERS:
			# the second engine and the rotor carry their own levels
			var own: float = level if not layer in ["second", "rotor"] or flat else 1.0
			var g: float = gains[layer] * own if solo == "" or solo == layer else 0.0
			var at: float
			match layer:
				"second":
					at = layer_at("second", v.sec.spool) * lift * twin
				"rotor":
					at = v.rotor_p * twin
				"burner":
					at = 1.0 + 0.1 * maxf(0.0, s - 1.0)
				"v8", "v12":
					at = layer_at(layer, s) * twin
				_:
					at = layer_at(layer, s)
			v.at[layer] = at
			_drive(v.players[layer], layer, at, g)


## One side of the second engine: off, waiting its turn (the right side lights a beat after the
## left), cranking in coughs, running on its lever, or stopping. Returns its gain, level included.
func _second(v: Dictionary, k: int, target_run: float, dt: float, duck: float) -> float:
	var sc: Dictionary = v.sec
	match sc.state:
		"off":
			if second_on:
				sc.state = "wait"
				sc.t = TUNE.second_stagger * k
		"wait":
			sc.t -= dt
			if not second_on:
				sc.state = "off"
			elif sc.t <= 0.0:
				sc.state = "crank"
				sc.t = TUNE.second_crank_s
		"crank":
			sc.t -= dt
			sc.cough_next -= dt
			if sc.cough_next <= 0.0:
				sc.cough_next = randf_range(0.05, 0.14)
				sc.cough_k = 1.0 if randf() < 0.45 else 0.0
			if not second_on:
				sc.state = "stop"
			elif sc.t <= 0.0:
				sc.state = "run"
				_play_bang(v, TUNE.bang_db[0], duck)
		"run":
			if not second_on:
				sc.state = "stop"
				_play_bang(v, TUNE.bang_db[1], duck)
			elif not flat and sc.spool > TUNE.pop_rpm and sc.spool - target_run > TUNE.pop_lift and v.pop2_t <= 0.0:
				v.pop2_t = TUNE.pop_s
				v.pop2_k = clampf((sc.spool - target_run) / 0.5, 0.3, 1.0)
		"stop":
			if second_on:
				sc.state = "crank"
				sc.t = TUNE.second_crank_s
			elif sc.spool < -0.3:
				sc.state = "off"
	var target := -0.33
	var tau: float = TUNE.second_wind
	var fire := 0.0
	match sc.state:
		"crank":
			target = -0.15   # turning over on the starter
			tau = 0.3
			fire = sc.cough_k
		"run":
			target = target_run
			fire = 1.0
	if sc.state == "run" and sc.spool >= 0.0:
		_rev(sc, "spool", "vel", target, dt)
	else:
		sc.spool = _follow(sc.spool, target, tau, dt)
		sc.vel = 0.0
	_pop(v, "pops2", "pop2_t", "pop2_k", dt, duck)
	sc.fire = _follow(sc.fire, fire, 0.05 if fire > sc.fire else 0.08, dt)
	var lvl := db_to_linear(lerpf(TUNE.second_level_db[0], TUNE.second_level_db[1], clampf(sc.spool, 0.0, 1.0)))
	return sc.fire * lvl * duck


## One side's bass rotor: wound up by airspeed, swelled by its lever, stepping back once that
## side's second engine runs. Sets its pitch and low-pass; returns its gain, level included.
func _rotor(v: Dictionary, lever: float, mph: float, dt: float, duck: float) -> float:
	v.rotor_mph = _follow(v.rotor_mph, mph, TUNE.rotor_tau, dt)
	var frac: float = clampf(v.rotor_mph / TUNE.second_on_mph, 0.0, 1.4)
	v.rotor_p = pow(2.0, TUNE.rotor_oct * pow(frac, TUNE.rotor_curve)) * (1.0 + TUNE.rotor_lever_pitch * lever)
	var lp: float = TUNE.rotor_lp_hz[0] * pow(TUNE.rotor_lp_hz[1] / TUNE.rotor_lp_hz[0], clampf(frac, 0.0, 1.0))
	(AudioServer.get_bus_effect(v.subs.rotor, 0) as AudioEffectLowPassFilter).cutoff_hz = TUNE.rotor_lp_hz[1] if flat else lp
	v.sec_run = _follow(v.sec_run, 1.0 if v.sec.state == "run" else 0.0, 0.6, dt)
	var db: float = lerpf(TUNE.rotor_db[0], TUNE.rotor_db[1], clampf(frac, 0.0, 1.0)) + TUNE.rotor_handover_db * v.sec_run
	return db_to_linear(db) * lerpf(TUNE.rotor_lever[0], TUNE.rotor_lever[1], lever) * duck


## The spool spring: snappy and flaring a touch past the lever on the way up, settling clean
## on the way down. Fixed 240 Hz substeps: stepped once per frame, the flare shrank with the
## frame rate (10% at 144 fps, 5% at 45, none at 20) and one long frame kicked the revs.
func _rev(d: Dictionary, key: String, vkey: String, target: float, dt: float) -> void:
	var n := maxi(1, ceili(dt * 240.0))
	var h := dt / n
	for i in n:
		var up: bool = target > d[key]
		var w: float = TUNE.rev_w[0] if up else TUNE.rev_w[1]
		var z: float = TUNE.rev_z[0] if up else TUNE.rev_z[1]
		d[vkey] += (w * w * (target - d[key]) - 2.0 * z * w * d[vkey]) * h
		d[key] += d[vkey] * h


## While an overrun burst is live, fire pops at random, tapering over pop_s.
func _pop(v: Dictionary, player: String, tkey: String, kkey: String, dt: float, duck: float) -> void:
	if v[tkey] <= 0.0:
		return
	v[tkey] -= dt
	var rate: float = TUNE.pop_rate * v[kkey] * maxf(v[tkey], 0.0) / TUNE.pop_s
	if duck > 0.0 and (solo == "" or solo == "pops") and randf() < rate * dt:
		(v[player] as AudioStreamPlayer).play()
		v.pops_n += 1


func _play_bang(v: Dictionary, db: float, duck: float) -> void:
	if duck <= 0.0 or (solo != "" and solo != "second"):
		return
	var p: AudioStreamPlayer = v.bang
	p.volume_db = db
	p.play()


## Crossfade weights for the levels around `at` (log spacing): linear shapes, normalized for the
## pair's correlation so the blend holds the level (rho 0 is equal power, 1 is linear).
## Off the ends, the end level carries it alone.
static func crossfade(ats: PackedFloat64Array, rhos: PackedFloat64Array, at: float) -> PackedFloat64Array:
	var n := ats.size()
	var w := PackedFloat64Array()
	w.resize(n)
	if n == 1 or at <= ats[0]:
		w[0] = 1.0
		return w
	if at >= ats[n - 1]:
		w[n - 1] = 1.0
		return w
	var lo := 0
	while at >= ats[lo + 1]:
		lo += 1
	var t := log(at / ats[lo]) / log(ats[lo + 1] / ats[lo])
	var a := 1.0 - t
	var g := 1.0 / sqrt(a * a + t * t + 2.0 * rhos[lo] * a * t)
	w[lo] = a * g
	w[lo + 1] = t * g
	return w


## Every level of the layer is pitched every frame, audible or not. A master's levels all get
## the identical pitch, which is what keeps them in lockstep.
func _drive(players: Array, layer: String, at: float, gain: float) -> void:
	var ats: PackedFloat64Array = _bands[layer]
	var w := crossfade(ats, _rho[layer], at)
	var rate_at: float = _rate_at[layer]
	for i in ats.size():
		var p: AudioStreamPlayer = players[i]
		p.pitch_scale = clampf(at / (rate_at if rate_at > 0.0 else ats[i]), 0.01, 16.0)
		var lin := w[i] * gain
		p.volume_db = linear_to_db(lin) if lin > 1e-4 else -80.0
