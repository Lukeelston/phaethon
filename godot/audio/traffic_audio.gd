## TrafficAudio: the Network's traffic going by (phase 2's deferred "traffic sounds: a whoosh as you
## pass"). A vehicle you pass close by, or that passes you, sounds a whoosh from where it is: louder
## the nearer and the harder the pass, pitched by the closing speed. The whoosh is synthesized at load
## (a noise burst through a falling band: the doppler fall as it goes by), mono, on its own bus
## ("Traffic", into Master), VOICES 3D voices that follow their vehicles while they sound.
##   var ta := TrafficAudio.new(); add_child(ta); ta.setup()      once (the Network, not muted)
##   ta.update(pod, heading, cars, to_world, delta)                every frame
##     pod: Vector2 the pod (sim m), heading: Vector2 its unit velocity (0 at rest), cars: [[id, x, y,
##     h, vx, vy], ...] the vehicles near (sim m and m/s; h their height), to_world: Callable(x, y, h)
##     -> the render position (the view's floating origin)
extends Node3D

const RATE := 44100
const VOICES := 6
const NEAR := 120.0      # m: a pass this close beside you is heard
const MIN_DV := 25.0     # m/s: ... and this much faster or slower than you
const FAR := 3000.0      # m: vehicles further than this along the road aren't followed

var passes := 0          # whooshes played (tests)
var last_db := -80.0     # the last one's level (tests)
var _along := {}         # vehicle id -> its offset along your way last frame (m, + ahead)
var _voices: Array[AudioStreamPlayer3D] = []
var _follow: Array = []  # per voice: the vehicle id it follows, or -1
var _left: Array = []    # per voice: s of its whoosh still to run (it follows its vehicle till then)
var _whoosh: AudioStreamWAV


func setup() -> void:
	var i := AudioServer.get_bus_index("Traffic")
	if i < 0:
		i = AudioServer.bus_count
		AudioServer.add_bus(i)
		AudioServer.set_bus_name(i, "Traffic")
	AudioServer.set_bus_send(i, "Master")
	_whoosh = make_whoosh()
	for k in VOICES:
		var p := AudioStreamPlayer3D.new()
		p.stream = _whoosh
		p.bus = "Traffic"
		p.unit_size = 40.0
		p.max_distance = 2500.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(p)
		_voices.append(p)
		_follow.append(-1)
		_left.append(0.0)


## The whoosh: 1.1 s of noise through a band falling from ~2.4 kHz to ~350 Hz, swelling in fast and
## out slow, a little low rumble under it.
static func make_whoosh() -> AudioStreamWAV:
	var n := int(1.1 * RATE)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var buf := PackedFloat32Array()
	buf.resize(n)
	var lp := 0.0
	var bp := 0.0
	var low := 0.0
	for k in n:
		var t := float(k) / n
		var fc := lerpf(2400.0, 350.0, smoothstep(0.25, 0.75, t))   # the doppler fall
		var a := 1.0 - exp(-TAU * fc / RATE)
		var x := rng.randf_range(-1.0, 1.0)
		lp += (x - lp) * a                       # low-pass at fc ...
		bp += ((x - lp) - bp) * 0.35             # ... and its complement smoothed: a band round fc
		low += (x - low) * (TAU * 90.0 / RATE)   # the rumble
		var env := smoothstep(0.0, 0.3, t) * (1.0 - smoothstep(0.45, 1.0, t))
		buf[k] = (lp * 0.6 + bp * 0.9 * (fc / 2400.0) + low * 1.4) * env   # the band's hiss falls away with it
	var top := 1e-6
	for k in n:
		top = maxf(top, absf(buf[k]))
	var data := PackedByteArray()
	data.resize(n * 2)
	for k in n:
		data.encode_s16(k * 2, int(clampf(buf[k] / top * 0.9, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.stereo = false
	w.mix_rate = RATE
	w.data = data
	return w


func update(pod: Vector2, heading: Vector2, cars: Array, to_world: Callable, delta: float) -> void:
	var seen := {}
	var where := {}
	for c: Array in cars:
		var id: int = c[0]
		var d := Vector2(float(c[1]), float(c[2])) - pod
		var along := d.dot(heading)
		var lat := absf(d.cross(heading))
		seen[id] = along
		where[id] = c
		if heading == Vector2.ZERO or absf(along) > FAR:
			continue
		var was = _along.get(id)
		if was != null and (float(was) >= 0.0) != (along >= 0.0) and lat < NEAR:   # it went by
			var dv := absf(Vector2(float(c[4]), float(c[5])).dot(heading) - _pod_speed)
			if dv > MIN_DV:
				_play(id, c, lat, dv, to_world)
	_along = seen
	# the voices follow their vehicles while they sound
	for k in _voices.size():
		_left[k] = maxf(0.0, float(_left[k]) - delta)
		if _left[k] <= 0.0 or _follow[k] < 0:
			continue
		var c = where.get(_follow[k])
		if c != null:
			_voices[k].position = to_world.call(float(c[1]), float(c[2]), float(c[3]))


var _pod_speed := 0.0    # m/s along heading (set by the caller before update: set_speed)


func set_speed(v: float) -> void:
	_pod_speed = v


func _play(id: int, c: Array, lat: float, dv: float, to_world: Callable) -> void:
	passes += 1
	# louder the nearer and the harder the pass: full at 20 m and 600 m/s, down 18 dB at NEAR or 25 m/s
	var db := -4.0 - 18.0 * clampf((lat - 20.0) / (NEAR - 20.0), 0.0, 1.0) - 12.0 * (1.0 - clampf(dv / 600.0, 0.0, 1.0))
	last_db = db
	if _voices.is_empty():
		return
	var k := 0
	for q in _voices.size():   # a free voice, else the one nearest its end
		if _left[q] <= 0.0:
			k = q
			break
		if _left[q] < _left[k]:
			k = q
	var p := _voices[k]
	p.volume_db = db
	p.pitch_scale = clampf(0.75 + dv / 900.0, 0.75, 1.6)
	p.position = to_world.call(float(c[1]), float(c[2]), float(c[3]))
	_follow[k] = id
	_left[k] = _whoosh.get_length() / p.pitch_scale
	p.play()
