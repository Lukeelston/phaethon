## CourseAudio: the course's places and the emergency run, in sound (Luke, 2026-10-19: "a big
## polish run ... focus on the graphics and sound design"). Everything is synthesized at load, like
## WindAudio, and plays on its own buses; the engine audio's buses are left alone.
##   enclosure   under a covered ramp's roof or the shade line's canopy the air closes in: a big
##               reverb opens on the Wind bus (your own rush rings off the hall) and a low tunnel
##               ring rises with your speed, both eased in and out
##   the dawn    (the emergency run) a deep roar that grows as the front nears, a searing hiss over
##               it the last few km, both muffled under shelter
##   the pad     a beep each half second you hold on it, climbing, then the drop's chime
##   the gate    a two-note chirp as the shade line's gate opens for you, a buzzer if it shuts
##   the result  a rising chord when you make it; a roaring white-out swell when the dawn catches you
##   var ca := CourseAudio.new(); add_child(ca); ca.setup(sim)   once, on a course with ramps or a job
##   ca.update(delta, dawn_dist)                                  every frame (dawn_dist: m to the front)
extends Node

const RATE := 44100
const RATE_LO := 22050          # the low loops (the roar, the hall's ring) don't need more
const XF := 0.25                # loop crossfade, s
const ENCLOSE_TAU := 0.35       # s: the enclosure eases in and out
const DAWN_NEAR := 40000.0      # m: the roar builds as the front closes from here ...
const HISS_NEAR := 6000.0       # ... the hiss from here
const PAD_BEEP := 0.5           # s between the pad's beeps

var sim
var wet := 0.0                  # the enclosure, 0..1 (tests read it)
var net_halls := {}             # the Network: road -> [first, last sample] of its city's hall (view/network_world.gd)
var hall_db := -80.0            # the tunnel ring's level (tests)
var dawn_db := -80.0            # the dawn's roar (tests)
var hiss_db := -80.0            # its hiss (tests)
var beeps := 0                  # the pad's beeps played (tests)
var cues: Array[String] = []    # one-shot cues played, in order (tests)
var _wind_rev: AudioEffectReverb
var _wind_bus := -1
var _hall: AudioStreamPlayer
var _rumble: AudioStreamPlayer
var _hiss: AudioStreamPlayer
var _shots: Array[AudioStreamPlayer] = []
var _cue_streams := {}
var _stage := ""
var _gate = null
var _beep_n := 0


func setup(craft_sim) -> void:
	sim = craft_sim
	var course := _bus("Course", "Master")
	if AudioServer.get_bus_effect_count(course) == 0:
		var lim := AudioEffectHardLimiter.new()
		lim.ceiling_db = -1.0
		AudioServer.add_bus_effect(course, lim)
	var hall := _bus("Hall", "Course")
	if AudioServer.get_bus_effect_count(hall) == 0:
		var rv := AudioEffectReverb.new()
		rv.room_size = 0.9
		rv.damping = 0.3
		rv.wet = 0.55
		rv.dry = 0.8
		AudioServer.add_bus_effect(hall, rv)
	_bus("Dawn", "Course")
	# the enclosure's reverb on the Wind bus (WindAudio's), ahead of its limiter; removed on exit
	_wind_bus = AudioServer.get_bus_index("Wind")
	if _wind_bus >= 0:
		_wind_rev = AudioEffectReverb.new()
		_wind_rev.room_size = 0.85
		_wind_rev.damping = 0.35
		_wind_rev.spread = 1.0
		_wind_rev.wet = 0.0
		var at := AudioServer.get_bus_effect_count(_wind_bus)
		for k in at:
			if AudioServer.get_bus_effect(_wind_bus, k) is AudioEffectHardLimiter:
				at = k
				break
		AudioServer.add_bus_effect(_wind_bus, _wind_rev, at)
	_hall = _player(make_hall(), "Hall")
	if not sim.job.is_empty():
		_rumble = _player(make_rumble(), "Dawn")
		_hiss = _player(make_hiss(), "Dawn")
		_cue_streams = {"beep": [make_beep(660.0, 0.11), make_beep(740.0, 0.11), make_beep(880.0, 0.11)],
			"drop": make_chime([659.25, 987.77], 1.4), "made_it": make_chime([523.25, 659.25, 783.99, 1046.5], 2.4),
			"gate_open": make_chime([880.0, 1318.5], 0.7), "gate_shut": make_buzzer(), "caught": make_roar()}
		for k in 3:
			var p := AudioStreamPlayer.new()
			p.bus = "Course"
			add_child(p)
			_shots.append(p)
		_stage = sim.job.stage


func _exit_tree() -> void:
	# the Wind bus outlives the scene (a track switch reloads it): take the enclosure's reverb with us
	if _wind_rev and _wind_bus >= 0 and _wind_bus < AudioServer.bus_count:
		for k in AudioServer.get_bus_effect_count(_wind_bus):
			if AudioServer.get_bus_effect(_wind_bus, k) == _wind_rev:
				AudioServer.remove_bus_effect(_wind_bus, k)
				break


func _player(s: AudioStreamWAV, bus: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = s
	p.bus = bus
	p.volume_db = -80.0
	add_child(p)
	return p


## Get or create a bus routed into `send` (as WindAudio's).
static func _bus(name: String, send: String) -> int:
	var i := AudioServer.get_bus_index(name)
	if i < 0:
		i = AudioServer.bus_count
		AudioServer.add_bus(i)
		AudioServer.set_bus_name(i, name)
	AudioServer.set_bus_send(i, send)
	return i


## Under a roof: a covered ramp's hall, or the shade line past its canopy's start.
func enclosed() -> bool:
	var Pd = sim.pod
	if sim.kind == "network":   # in a city's hall
		var span = net_halls.get(Pd.path)
		return not Pd.off_road and span != null and Pd.hint >= int(span[0]) and Pd.hint < int(span[1])
	if Pd.path > 0:
		return Pd.hint >= sim.branches[Pd.path - 1].covered.x
	return Pd.hint < sim.tcover.size() and sim.tcover[Pd.hint] == 1


func update(delta: float, dawn_dist: float) -> void:
	var Pd = sim.pod
	var v: float = sqrt(Pd.vx * Pd.vx + Pd.vy * Pd.vy)
	var enc := enclosed()
	wet = _follow(wet, 1.0 if enc else 0.0, ENCLOSE_TAU, delta)
	if _wind_rev:
		_wind_rev.wet = 0.42 * wet
		_wind_rev.dry = 1.0 - 0.2 * wet
	var ring := wet * clampf(v / 900.0, 0.0, 1.0)
	hall_db = linear_to_db(ring) - 4.0 if ring > 1e-3 else -80.0
	_level(_hall, hall_db)
	if sim.job.is_empty():
		dawn_db = -80.0
		return
	var J: Dictionary = sim.job
	var live: bool = J.stage in ["out", "drop", "home"]
	var near := clampf(1.0 - absf(dawn_dist) / DAWN_NEAR, 0.0, 1.0) if live else 0.0
	var close := clampf(1.0 - absf(dawn_dist) / HISS_NEAR, 0.0, 1.0) if live else 0.0
	var muffle := 8.0 if enc else 0.0
	dawn_db = _follow(dawn_db, (lerpf(-60.0, -6.0, pow(near, 1.4)) - muffle) if near > 0.0 else -80.0, 0.4, delta)
	hiss_db = _follow(hiss_db, (lerpf(-60.0, -8.0, pow(close, 1.2)) - 2.0 * muffle) if close > 0.0 else -80.0, 0.25, delta)
	_level(_rumble, dawn_db)
	_level(_hiss, hiss_db)
	# the pad: a beep each half second held, climbing
	if J.stage == "out" and float(J.held) > 0.0:
		var n := int(float(J.held) / PAD_BEEP)
		if n > _beep_n and float(J.held) < sim.PAD_HOLD - 0.05:
			_beep_n = n
			beeps += 1
			_play((_cue_streams.beep as Array)[mini(n - 1, 2)], "beep", -6.0)
	else:
		_beep_n = 0
	# the stages
	if J.stage != _stage:
		match J.stage:
			"drop":
				_play(_cue_streams.drop, "drop", -4.0)
			"done":
				_play(_cue_streams.made_it, "made_it", -3.0)
			"failed":
				if J.reason == "dawn":
					_play(_cue_streams.caught, "caught", 0.0)
		_stage = J.stage
	# the shade line's gate, as it decides for this pass
	if not sim.gate.is_empty() and sim.gate[0] != _gate:
		if sim.gate[0] == true:
			_play(_cue_streams.gate_open, "gate_open", -6.0)
		elif sim.gate[0] == false:
			_play(_cue_streams.gate_shut, "gate_shut", -6.0)
		_gate = sim.gate[0]


func _play(s: AudioStreamWAV, name: String, db: float) -> void:
	cues.append(name)
	var p: AudioStreamPlayer = _shots[0]
	for q in _shots:
		if not q.playing:
			p = q
			break
	p.stream = s
	p.volume_db = db
	p.play()


## A loop's level: playing above -70 dB, stopped below.
static func _level(p: AudioStreamPlayer, db: float) -> void:
	if p == null:
		return
	p.volume_db = db
	if db > -70.0 and not p.playing:
		p.play()
	elif db <= -70.0 and p.playing:
		p.stop()


static func _follow(cur: float, target: float, tau: float, dt: float) -> float:
	return target + (cur - target) * exp(-dt / maxf(tau, 1e-4))


# --- synthesis ------------------------------------------------------------------------------------

## Two channels into a 16-bit stereo stream at `rate`, normalized to `peak`; `n` > 0 makes it a
## seamless loop of n samples (the extra tail crossfaded into the head).
static func _wav(l: PackedFloat32Array, r: PackedFloat32Array, rate: int, peak: float, n := 0) -> AudioStreamWAV:
	var m := l.size()
	var out_n := n if n > 0 else m
	if n > 0:
		var xf := m - n
		for i in xf:
			var a := float(i) / xf
			l[i] = l[i] * a + l[n + i] * (1.0 - a)
			r[i] = r[i] * a + r[n + i] * (1.0 - a)
	var top := 1e-6
	for i in out_n:
		top = maxf(top, maxf(absf(l[i]), absf(r[i])))
	var g := peak / top
	var data := PackedByteArray()
	data.resize(out_n * 4)
	for i in out_n:
		data.encode_s16(i * 4, int(clampf(l[i] * g, -1.0, 1.0) * 32767.0))
		data.encode_s16(i * 4 + 2, int(clampf(r[i] * g, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.stereo = true
	w.mix_rate = rate
	w.data = data
	if n > 0:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_end = out_n
	return w


## The dawn's roar: deep brown noise round two slow-beating lows (34 and 51 Hz), 3 s loop.
static func make_rumble() -> AudioStreamWAV:
	var n := int(3.0 * RATE_LO)
	var m := n + int(XF * RATE_LO)
	var rng := RandomNumberGenerator.new()
	rng.seed = 2701
	var l := PackedFloat32Array()
	var r := PackedFloat32Array()
	l.resize(m)
	r.resize(m)
	var a := 1.0 - exp(-TAU * 70.0 / RATE_LO)
	var yl := 0.0
	var yr := 0.0
	var zl := 0.0
	var zr := 0.0
	for i in m:
		var t := float(i) / RATE_LO
		yl += a * (rng.randf_range(-1.0, 1.0) - yl)
		yr += a * (rng.randf_range(-1.0, 1.0) - yr)
		zl += a * (yl - zl)
		zr += a * (yr - zr)
		var lows := 0.5 * sin(TAU * 34.0 * t) + 0.35 * sin(TAU * 51.0 * t + 0.7)
		var beat := 0.75 + 0.25 * sin(TAU * t / 3.0)   # one slow swell a loop
		l[i] = (zl * 9.0 + lows * 0.5) * beat
		r[i] = (zr * 9.0 + lows * 0.5) * beat
	return _wav(l, r, RATE_LO, 0.85, n)


## Its searing edge: white noise between 3 and 9 kHz, flickering, 2 s loop.
static func make_hiss() -> AudioStreamWAV:
	var n := int(2.0 * RATE)
	var m := n + int(XF * RATE)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3313
	var l := PackedFloat32Array()
	var r := PackedFloat32Array()
	l.resize(m)
	r.resize(m)
	var ah := 1.0 - exp(-TAU * 3000.0 / RATE)
	var al := 1.0 - exp(-TAU * 9000.0 / RATE)
	var hl := 0.0
	var hr := 0.0
	var ll := 0.0
	var lr := 0.0
	for i in m:
		var t := float(i) / RATE
		var xl := rng.randf_range(-1.0, 1.0)
		var xr := rng.randf_range(-1.0, 1.0)
		hl += ah * (xl - hl)
		hr += ah * (xr - hr)
		ll += al * ((xl - hl) - ll)
		lr += al * ((xr - hr) - lr)
		var flick := 0.8 + 0.2 * sin(TAU * 7.0 * t) * sin(TAU * 1.5 * t)
		l[i] = ll * flick
		r[i] = lr * flick
	return _wav(l, r, RATE, 0.7, n)


## A hall's ring at speed: band noise (120-600 Hz) through a resonant comb at 85 Hz, 2 s loop.
static func make_hall() -> AudioStreamWAV:
	var n := int(2.0 * RATE_LO)
	var m := n + int(XF * RATE_LO)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1187
	var l := PackedFloat32Array()
	var r := PackedFloat32Array()
	l.resize(m)
	r.resize(m)
	var a_lo := 1.0 - exp(-TAU * 600.0 / RATE_LO)
	var a_hi := 1.0 - exp(-TAU * 120.0 / RATE_LO)
	var d := int(RATE_LO / 85.0)
	var bl := 0.0
	var br := 0.0
	var hl := 0.0
	var hr := 0.0
	for i in m:
		var xl := rng.randf_range(-1.0, 1.0)
		var xr := rng.randf_range(-1.0, 1.0)
		bl += a_lo * (xl - bl)
		br += a_lo * (xr - br)
		hl += a_hi * (bl - hl)
		hr += a_hi * (br - hr)
		var sl := bl - hl
		var sr := br - hr
		l[i] = sl + (0.72 * l[i - d] if i >= d else 0.0)
		r[i] = sr + (0.72 * r[i - d] if i >= d else 0.0)
	return _wav(l, r, RATE_LO, 0.8, n)


## A short beep: a sine at f, 5 ms attack, quick decay.
static func make_beep(f: float, dur: float) -> AudioStreamWAV:
	var m := int(dur * RATE)
	var l := PackedFloat32Array()
	l.resize(m)
	for i in m:
		var t := float(i) / RATE
		l[i] = sin(TAU * f * t) * minf(1.0, t / 0.005) * exp(-t / (dur * 0.35))
	return _wav(l, l.duplicate(), RATE, 0.7)


## A chime: the notes struck 0.12 s apart, each a bell (its fundamental and a 2.76x partial) ringing down.
static func make_chime(freqs: Array, dur: float) -> AudioStreamWAV:
	var m := int(dur * RATE)
	var l := PackedFloat32Array()
	var r := PackedFloat32Array()
	l.resize(m)
	r.resize(m)
	for k in freqs.size():
		var f: float = freqs[k]
		var t0 := 0.12 * k
		var pan := 0.5 + 0.35 * (float(k) / maxf(freqs.size() - 1, 1) - 0.5)
		for i in range(int(t0 * RATE), m):
			var t := float(i) / RATE - t0
			var s := (sin(TAU * f * t) + 0.3 * sin(TAU * f * 2.76 * t) * exp(-t / 0.15)) * minf(1.0, t / 0.004) * exp(-t / (dur * 0.3))
			l[i] += s * (1.0 - pan)
			r[i] += s * pan
	return _wav(l, r, RATE, 0.75)


## A buzzer: three blunt pulses of a square chord (140 and 210 Hz).
static func make_buzzer() -> AudioStreamWAV:
	var m := int(0.7 * RATE)
	var l := PackedFloat32Array()
	l.resize(m)
	for i in m:
		var t := float(i) / RATE
		var on := 1.0 if fmod(t, 0.23) < 0.16 else 0.0
		var sq := signf(sin(TAU * 140.0 * t)) + 0.7 * signf(sin(TAU * 210.0 * t))
		l[i] = sq * on * 0.5
	return _wav(l, l.duplicate(), RATE, 0.55)


## The white-out: a noise swell opening from a muffled roar to a full-band blast, a low thump under it.
static func make_roar() -> AudioStreamWAV:
	var m := int(3.0 * RATE)
	var rng := RandomNumberGenerator.new()
	rng.seed = 911
	var l := PackedFloat32Array()
	var r := PackedFloat32Array()
	l.resize(m)
	r.resize(m)
	var yl := 0.0
	var yr := 0.0
	for i in m:
		var t := float(i) / RATE
		var fc := lerpf(300.0, 7000.0, clampf(t / 0.8, 0.0, 1.0))
		var a := 1.0 - exp(-TAU * fc / RATE)
		yl += a * (rng.randf_range(-1.0, 1.0) - yl)
		yr += a * (rng.randf_range(-1.0, 1.0) - yr)
		var env := clampf(t / 0.5, 0.0, 1.0) * exp(-maxf(t - 0.9, 0.0) / 0.8)
		var thump := sin(TAU * 42.0 * t) * exp(-t / 0.6)
		l[i] = yl * env + 0.6 * thump
		r[i] = yr * env + 0.6 * thump
	return _wav(l, r, RATE, 0.9)
