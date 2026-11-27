## The raid's own sounds (the stage 2 plan, task 9): the drones' whine, the gunship's drone and its shot's report, and the
## sounds of four craft's weapons (the Shrike's missiles leaving, the Kiln's lance burning, the Vesper's pulse released, an
## Orrery orb striking). Each is made in code at load, with Raids on only (the director's build and the fire control it
## makes then), once a run, and kept; none with --mute or in a shot, and none with Raids off, armed or not (Ruling AF: a
## weapon then plays the turret's stand-ins, view/gunnery.gd play_own).
## Made from recordings already in the game (Ruling AD: the owner had synthesised sounds rebuilt from recordings): cut,
## run faster or slower as a tape is (pitch and pace together), layered and shaped. A loop's layer is a steady stretch of
## a recording, its end folded into its start (_chunk), or, from a stretch too short for that, grains of it laid half
## over one another round the loop (_grains); a one-shot's is a slice from a point with its own rise and fall (_slice).
## The sources and their credits: audio/startup/CREDITS.md (the CC0 field recordings: a server fan, sparks and a Tesla
## coil, a breaker, an air valve, a switch), audio/workshop (cut from the same recordings by
## tools/garage_audio_bake.py: the garage door's motor), audio/ramjet/CREDITS.md (NASA's and klangfabrik's rocket
## engines: the shuttle's roar and its ignition's thump and cut-off, the RS-25's crackle) and audio/engines/CREDITS.md
## (Salamander piano, CC BY 3.0: the engines' bang). Nothing is synthesised but the throb laid over two loops (a swell in
## level: a rotor's beat) and the fades. None of it has been heard by anyone: lengths, peaks and levels are measured.
## Each is a 16-bit mono AudioStreamWAV (at RATE, or its recipe's rate). LEVELS is each one's level as made: the RMS of
## its loudest 100 ms, dBFS (a loop's is about its whole length's); every one peaks under PEAK. A source missing or
## unreadable (not 16-bit PCM: an import left at its QOA default) leaves that sound null, said once in the log: its
## player then plays the stand-in it replaced (STAND_IN: a turret sound re-pitched, view/gunnery.gd), or, for the
## flyers', nothing (they had none).
##   RaidSounds.drone_whine() ... orb_strike()     the stream (made the first time it is asked for), or null
##   RaidSounds.make(name)                         the same, by its name
##   RaidSounds.heard(view)                        has the flight sound (not --mute, not a shot)? none is made without
##   RaidSounds.sources                            where each recording is read from (SRC's; a test points one nowhere)
extends RefCounted

const RATE := 24000
const PEAK := 0.84                # the most any sample reaches: -1.5 dBFS (none at full scale: nothing clips)
const KNEE := 0.5                 # ... over this the loudest moments are rounded off toward PEAK (tanh), not cut
const FOLD := 0.12                # s: a chunk's end folded into its start
const NAMES := ["drone_whine", "gunship_drone", "gunship_shot", "missile_launch", "lance_hum", "pulse_boom", "orb_strike"]
const LOOPS := ["drone_whine", "gunship_drone", "lance_hum"]
## dBFS: the RMS of each one's loudest 100 ms as made. Set by measure, not by ear, in the game's own mix (the movie
## writer's recording of tests/record_raid_sounds.gd, the two ears' power together, which no turn of the head changes):
## there the jolt's thump is -15.0 and the turret's shot through the fire control's gun pool -14.6 (its servo at 1.35,
## the hum's stand-in, -20.7), and the gun pool at the cockpit gives a sound its own level to within 1 dB. So the
## weapons', through that pool at their mount: the launch and the boom 1.5 dB under the thump, the strike 5, the hum
## no louder than the stand-in it replaces. The flyers' play on their own players (view/raid_flyers.gd), whose most sets
## theirs: the report's 4 dB under the thump, the loops' at least 12 dB under the engines at cruise.
const LEVELS := {"drone_whine": -16.0, "gunship_drone": -16.0, "gunship_shot": -14.0, "missile_launch": -16.5,
	"lance_hum": -21.0, "pulse_boom": -16.5, "orb_strike": -19.0}
## What each plays in its place when it was not made: the stand-in it replaced, [the fire control's pool, its turret sound,
## its pitch] (view/gunnery.gd play_own); the flyers' had none, and play nothing. None louder than the jolt's thump: the
## pulse's is the turret's impact, lower (-15.7 dBFS on disk, 1.3 s), not the burst it first was (-8.6, 5.5 dB over the
## thump through the gun pool, 4.7 s: the whole-branch review).
const STAND_IN := {"missile_launch": ["gun", "fire", 0.55], "lance_hum": ["gun", "deploy", 1.35],
	"pulse_boom": ["gun", "impact", 0.45], "orb_strike": ["world", "impact", 1.5], "drone_whine": [], "gunship_drone": [],
	"gunship_shot": []}
const SRC := {"fan": "res://audio/startup/avionics.wav", "arc": "res://audio/startup/arc.wav",
	"valve": "res://audio/startup/release.wav", "breaker": "res://audio/startup/clamp.wav",
	"switch": "res://audio/startup/toggle_on_0.wav",
	"motor": "res://audio/workshop/door_motor.wav", "roar": "res://audio/ramjet/ramjet_body.wav",
	"crackle": "res://audio/ramjet/ramjet_tear.wav", "ignition": "res://audio/ramjet/ramjet_light_0.wav",
	"cutoff": "res://audio/ramjet/ramjet_out_0.wav", "bang": "res://audio/engines/bang.wav"}

static var sources := SRC.duplicate()      # where each recording is read from (a test points one elsewhere: a missing source)
static var _cache := {}           # name -> AudioStreamWAV, or null once it could not be made (tests read it)
static var make_ms := {}          # name -> ms its making took (tests and the cost probe read it)
static var fills := {}            # name -> [[samples filled, samples wanted], ...] a layer, as made (tests read it): a layer
                                  # whose recording ran out part way filled fewer, and its sound was said once in the log


static func drone_whine() -> AudioStream:
	return make("drone_whine")


static func gunship_drone() -> AudioStream:
	return make("gunship_drone")


static func gunship_shot() -> AudioStream:
	return make("gunship_shot")


static func missile_launch() -> AudioStream:
	return make("missile_launch")


static func lance_hum() -> AudioStream:
	return make("lance_hum")


static func pulse_boom() -> AudioStream:
	return make("pulse_boom")


static func orb_strike() -> AudioStream:
	return make("orb_strike")


## Has view's flight sound: not --mute, not a shot (as the director's alarm asks)? None of these is made in one without.
static func heard(view) -> bool:
	return view != null and view.get("muted") == false and view.get("shot_path") == ""


## The sound called `name` (one of NAMES): made the first time, then kept; null if a source of it could not be read.
static func make(name: String) -> AudioStream:
	if _cache.has(name):
		return _cache[name]
	var t0 := Time.get_ticks_usec()
	var spec: Dictionary = _recipe(name)
	var rate: int = spec.get("rate", RATE)
	var out := PackedFloat32Array()
	out.resize(int(float(spec.length) * rate) & ~1)      # (even: the stream is written two samples at a time)
	var ok: bool = not (spec.layers as Array).is_empty()
	var got := []           # each layer's [samples filled, samples wanted]
	var short := []
	for layer: Dictionary in spec.layers:
		var rec := _recording(String(layer.src))
		if rec == null:
			ok = false
			break
		var fill: Array
		if not spec.loop:
			fill = _slice(out, rate, rec, layer)
		elif layer.has("grain"):
			fill = _grains(out, rate, rec, layer)
		else:
			fill = _chunk(out, rate, rec, layer)
		got.append(fill)
		if int(fill[0]) < int(fill[1]):
			short.append("layer %d (%s) %d of %d samples" % [got.size(), layer.src, fill[0], fill[1]])
	fills[name] = got
	if ok and not short.is_empty():      # (it is still made: that layer shorter, or absent)
		print("RAID SOUNDS: %s: its recording ran out for %s" % [name, ", ".join(short)])
	var w: AudioStreamWAV = null
	if ok:
		if spec.has("throb"):
			_throb(out, spec.throb)
		w = _wav(out, rate, float(LEVELS[name]), bool(spec.loop))
	else:
		print("RAID SOUNDS: %s not made (a source of it is missing or not 16-bit PCM): %s" % [name,
			"its stand-in plays" if not (STAND_IN[name] as Array).is_empty() else "it is not heard (it had no stand-in)"])
	_cache[name] = w
	make_ms[name] = (Time.get_ticks_usec() - t0) / 1000.0
	return w


## Each sound's recipe: its length (s), its rate (RATE if not given), whether it loops, its layers (each a recording, SRC,
## and how it is laid in) and a throb. The layers' levels are against one another; the whole is then brought to LEVELS.
##   a loop's layer:     {src, from (s into it: a steady stretch), ratio (its speed, pitch and pace), db}, and with
##                       `grain` (s) and `to` (s): grains from from .. to (a stretch too short to run the loop's length)
##   a one-shot's layer: {src, from (s into it), ratio, glide (its ratio at the sound's end, if it falls), at (s into
##                       the sound it starts), rise (s), fall (s: the e-folding of its decay), db}
##   throb:              [[depth, cycles], ...]: a swell in the level, a whole number of times round the loop
static func _recipe(name: String) -> Dictionary:
	match name:
		"drone_whine":       # small rotors: the door's motor run half as fast again, a second at twice its speed (from its
			return {"length": 1.2, "loop": true, "throb": [[0.16, 12], [0.08, 9]], "layers": [      # start: the loop and its
				{"src": "motor", "from": 0.3, "ratio": 1.55, "db": 0.0},                               # fold need 2.64 s of its
				{"src": "motor", "from": 0.0, "ratio": 2.0, "db": -6.0},                               # 2.70), the fan's air
				{"src": "fan", "from": 0.2, "ratio": 1.3, "db": -4.0}]}
		"gunship_drone":     # a heavy lifter: the fan run at 0.42 (a big rotor's blades), the motor an octave down (its
			return {"length": 1.6, "rate": 16000, "loop": true, "throb": [[0.45, 7]], "layers": [  # turbine), the shuttle's
				{"src": "fan", "from": 0.2, "ratio": 0.42, "db": 0.0},                                 # roar under them; the
				{"src": "motor", "from": 0.3, "ratio": 0.5, "db": -5.0},                               # blades' beat
				{"src": "roar", "from": 2.0, "ratio": 1.25, "db": -2.0}]}
		"lance_hum":         # the Tesla coil's buzz from the binder's arc, and the same an octave down
			return {"length": 1.0, "loop": true, "layers": [
				{"src": "arc", "from": 0.15, "to": 0.52, "ratio": 1.0, "grain": 0.12, "db": 0.0},
				{"src": "arc", "from": 0.15, "to": 0.52, "ratio": 0.5, "grain": 0.16, "db": -4.0}]}
		"gunship_shot":      # a cannon's report: the shuttle's ignition thump, quicker, a breaker's metal slowed, a bang
			return {"length": 1.1, "rate": 16000, "loop": false, "layers": [
				{"src": "ignition", "from": 0.0, "ratio": 1.35, "at": 0.0, "rise": 0.003, "fall": 0.25, "db": 0.0},
				{"src": "breaker", "from": 0.0, "ratio": 0.55, "at": 0.0, "rise": 0.001, "fall": 0.08, "db": -4.0},
				{"src": "bang", "from": 0.0, "ratio": 1.2, "at": 0.0, "rise": 0.002, "fall": 0.2, "db": -3.0}]}
		"missile_launch":    # a rail's latch, the air valve's rush slowed and falling (the motor's hiss leaving: gone
			return {"length": 0.9, "loop": false, "layers": [                                       # before its burst ends),
				{"src": "breaker", "from": 0.0, "ratio": 1.1, "at": 0.0, "rise": 0.001, "fall": 0.05, "db": -6.0},      # the
				{"src": "valve", "from": 0.24, "ratio": 0.8, "glide": 0.6, "at": 0.02, "rise": 0.01, "fall": 0.12, "db": 0.0},  # RS-25's
				{"src": "crackle", "from": 1.0, "ratio": 2.4, "at": 0.03, "rise": 0.02, "fall": 0.3, "db": -2.0},       # crackle
				{"src": "ignition", "from": 0.05, "ratio": 1.8, "at": 0.0, "rise": 0.005, "fall": 0.15, "db": -5.0}]}
		"pulse_boom":        # a shock leaving: the ignition's thump slowed and falling, the bang slowed, the cut-off's
			return {"length": 1.8, "rate": 16000, "loop": false, "layers": [                       # rush after, air
				{"src": "ignition", "from": 0.0, "ratio": 0.8, "glide": 0.6, "at": 0.0, "rise": 0.004, "fall": 0.6, "db": 0.0},
				{"src": "bang", "from": 0.0, "ratio": 0.7, "at": 0.0, "rise": 0.002, "fall": 0.35, "db": -2.0},
				{"src": "cutoff", "from": 0.0, "ratio": 0.9, "at": 0.08, "rise": 0.01, "fall": 0.5, "db": -6.0},
				{"src": "valve", "from": 0.24, "ratio": 0.45, "at": 0.02, "rise": 0.03, "fall": 0.4, "db": -10.0}]}
		"orb_strike":        # a hard, bright strike: the breaker's metal clack higher, the arc's first sparks (gone before
			return {"length": 0.35, "loop": false, "layers": [                                    # its hum), a switch's click
				{"src": "breaker", "from": 0.0, "ratio": 1.4, "at": 0.0, "rise": 0.001, "fall": 0.05, "db": 0.0},
				{"src": "arc", "from": 0.0, "ratio": 1.25, "at": 0.0, "rise": 0.002, "fall": 0.03, "db": -3.0},
				{"src": "switch", "from": 0.0, "ratio": 1.3, "at": 0.0, "rise": 0.001, "fall": 0.04, "db": -6.0}]}
	push_error("RaidSounds: no sound \"%s\"" % name)
	return {"length": 0.1, "loop": false, "layers": []}


## A recording (the stream under sources[key], SRC's), or null if it is missing or not 16-bit mono PCM (its import's
## compress/mode must be 0, uncompressed: a QOA stream's data is not samples).
static func _recording(key: String) -> AudioStreamWAV:
	var path: String = sources.get(key, "")
	var w = ResourceLoader.load(path) if path != "" and ResourceLoader.exists(path) else null
	if not (w is AudioStreamWAV) or w.format != AudioStreamWAV.FORMAT_16_BITS or w.stereo:
		return null
	return w


## Recording w's samples from about `from` s (the even sample at or before it) for `seconds` (what of them it has), -1..1,
## and their prefix sum: [x, S], S[k] = x[0] + ... + x[k - 1] (a sample of the output reads the box of x it spans from S).
static func _read(w: AudioStreamWAV, from: float, seconds: float) -> Array:
	var data := w.data
	var total := data.size() / 2
	var a := clampi(int(from * w.mix_rate), 0, total) & ~1
	var pairs := clampi((int(ceil(seconds * w.mix_rate)) + 4) / 2, 0, (total - a) / 2)
	var two := data.slice(a * 2, (a + pairs * 2) * 2).to_int32_array()      # (two samples an int: low, then high)
	var n := pairs * 2
	var x := PackedFloat32Array()
	x.resize(n)
	var S := PackedFloat64Array()
	S.resize(n + 1)
	var acc := 0.0
	for j in pairs:
		var v := two[j]
		var lo := v & 0xFFFF
		if lo >= 32768:
			lo -= 65536
		var s0 := lo / 32768.0
		var s1 := (v >> 16) / 32768.0
		x[2 * j] = s0
		x[2 * j + 1] = s1
		S[2 * j] = acc
		acc += s0
		S[2 * j + 1] = acc
		acc += s1
	S[n] = acc
	return [x, S]


## `count` output samples of x (prefix sum S) from source position p (fractional), each `step` source samples on from the
## last: each the mean of the source over the step it spans (step >= 1: a box, so a recording run faster does not fold
## its top back down into what is heard), or read between two samples (step < 1). -> [the samples (count of them), how
## many were filled]: it stops short, the rest silent, where x ends (none filled from p at or past its end, or from an
## empty x).
static func _run(x: PackedFloat32Array, S: PackedFloat64Array, p: float, step: float, count: int) -> Array:
	var y := PackedFloat32Array()
	y.resize(count)
	var last := x.size() - 2.0
	if p < 0.0 or p > last:
		return [y, 0]
	var filled := 0
	if step >= 1.0:
		var inv := 1.0 / step
		var ia := int(p)
		var sa := S[ia] + (p - ia) * x[ia]
		for i in count:
			var b := p + step
			if b > last:
				break
			var ib := int(b)
			var sb := S[ib] + (b - ib) * x[ib]
			y[i] = (sb - sa) * inv
			sa = sb
			p = b
			filled += 1
	else:
		for i in count:
			if p > last:
				break
			var k := int(p)
			y[i] = x[k] + (x[k + 1] - x[k]) * (p - k)
			p += step
			filled += 1
	return [y, filled]


## A loop's layer, added into `out` (the whole loop): the recording from `from`, run at `ratio`, the loop's length and
## FOLD more of it, its last FOLD laid over its first under an equal-power cross-fade, so it runs on from its end into its
## start: seamless (if the recording holds all of it: -> [samples filled, the loop's length and FOLD]).
static func _chunk(out: PackedFloat32Array, rate: int, w: AudioStreamWAV, layer: Dictionary) -> Array:
	var n := out.size()
	var f := int(FOLD * rate)
	var step := float(layer.ratio) * w.mix_rate / rate
	var read: Array = _read(w, float(layer.from), (n + f) * step / w.mix_rate)
	var ran: Array = _run(read[0], read[1], 0.0, step, n + f)
	var y: PackedFloat32Array = ran[0]
	var gain := db_to_linear(float(layer.db))
	for i in f:
		var u := (i + 0.5) / f * PI * 0.5
		out[i] += (y[i] * sin(u) + y[n + i] * cos(u)) * gain
	for i in range(f, n):
		out[i] += y[i] * gain
	return [ran[1], n + f]


## A loop's layer from a short steady stretch (from .. to s), added into `out`: grains of it, each from its own place in
## the stretch (a fixed draw), run at `ratio`, laid half over one another under a sine window (their power sums level)
## round the loop's end and back into its start: seamless wherever it is cut. -> [samples filled, samples wanted], over
## all its grains.
static func _grains(out: PackedFloat32Array, rate: int, w: AudioStreamWAV, layer: Dictionary) -> Array:
	var read: Array = _read(w, float(layer.from), float(layer.to) - float(layer.from))
	var x: PackedFloat32Array = read[0]
	var step := float(layer.ratio) * w.mix_rate / rate
	var n := out.size()
	var hops := maxi(2, roundi(n / (float(layer.grain) * rate * 0.5)))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(String(layer.src)) + roundi(float(layer.ratio) * 1000.0)
	var gain := db_to_linear(float(layer.db))
	var filled := 0
	var wanted := 0
	for j in hops:      # (grain j from j/hops of the loop to (j + 2)/hops: every sample under two of them)
		var start := j * n / hops
		var g := (j + 2) * n / hops - start
		var ran: Array = _run(x, read[1], rng.randf_range(0.0, maxf(0.0, x.size() - 3.0 - g * step)), step, g)
		var y: PackedFloat32Array = ran[0]
		filled += int(ran[1])
		wanted += g
		var c := cos(PI / g)      # (the window, sin(pi (i + 1/2) / g), turned on a sample at a time)
		var s := sin(PI / g)
		var wy := sin(PI * 0.5 / g)
		var wx := cos(PI * 0.5 / g)
		for i in g:
			out[(start + i) % n] += y[i] * wy * gain
			var t := wy * c + wx * s
			wx = wx * c - wy * s
			wy = t
	return [filled, wanted]


## A one-shot's layer, added into `out`: the recording from `from` s, run at `ratio` (falling to `glide` by the sound's
## end, if given), starting `at` s into the sound, rising over `rise` and dying away with `fall` (its e-folding). ->
## [samples filled, samples wanted]: wanted till it has died 60 dB away or the sound ends, whichever is first.
static func _slice(out: PackedFloat32Array, rate: int, w: AudioStreamWAV, layer: Dictionary) -> Array:
	var start := int(float(layer.at) * rate)
	var length := out.size() - start
	var r0 := float(layer.ratio)
	var r1 := float(layer.get("glide", r0))
	var read: Array = _read(w, float(layer.from), maxf(r0, r1) * length / rate)
	var y: PackedFloat32Array
	var filled := 0
	if r1 == r0:
		var ran: Array = _run(read[0], read[1], 0.0, r0 * w.mix_rate / rate, length)
		y = ran[0]
		filled = ran[1]
	else:      # (its speed falling: run in eight stretches, each at its own; one that runs out ends them, the rest silent)
		y = PackedFloat32Array()
		var p := 0.0
		for k in 8:
			var count := (k + 1) * length / 8 - k * length / 8
			var step := lerpf(r0, r1, (k + 0.5) / 8.0) * w.mix_rate / rate
			var ran: Array = _run(read[0], read[1], p, step, count)
			y.append_array(ran[0])
			filled += int(ran[1])
			if int(ran[1]) < count:
				break
			p += step * count
		y.resize(length)
	var rise := maxf(float(layer.rise) * rate, 1.0)
	var life := mini(length, int(rise + maxf(float(layer.fall) * rate, 1.0) * log(1000.0)))      # (60 dB down)
	var decay := exp(-1.0 / maxf(float(layer.fall) * rate, 1.0))
	var gain := db_to_linear(float(layer.db))
	var env := gain
	for i in length:
		var v := y[i] * env
		if i < rise:
			v *= i / rise
		else:
			env *= decay
			if env < 1e-4 * gain:
				break      # (died away: 80 dB down)
		out[start + i] += v
	var want := life
	if filled < life and filled > 0 and _died(read[0]):
		want = filled      # (its recording died away before it ended: all it had to give)
	return [mini(filled, life), want]


## Has recording stretch x died away at its end (its last 10 ms under -50 dBFS: the bank's one-shots end in silence)?
static func _died(x: PackedFloat32Array) -> bool:
	var n := x.size()
	var k := mini(n, 480)
	var acc := 0.0
	for i in range(n - k, n):
		acc += x[i] * x[i]
	return k > 0 and sqrt(acc / k) < 0.00316


## A loop's throb: its level swelling by each [depth, cycles] a whole number of times round it (so it is seamless).
static func _throb(out: PackedFloat32Array, swells: Array) -> void:
	var n := out.size()
	for sw: Array in swells:
		var depth := float(sw[0])
		var c := cos(TAU * float(sw[1]) / n)
		var s := sin(TAU * float(sw[1]) / n)
		var co := 1.0
		var si := 0.0
		for i in n:
			out[i] *= 1.0 - depth * (0.5 + 0.5 * co)
			var t := co * c - si * s
			si = si * c + co * s
			co = t


## The samples brought to `level` (the RMS of their loudest 100 ms, dBFS), their loudest moments rounded off over KNEE
## toward PEAK, a one-shot's last 20 ms faded to nothing; as a 16-bit mono stream at `rate` (a loop's points round it).
static func _wav(x: PackedFloat32Array, rate: int, level: float, loop: bool) -> AudioStreamWAV:
	var n := x.size() & ~1
	var gain := db_to_linear(level) / maxf(loudest(x, rate), 1e-9)
	var fade := 0 if loop else int(0.02 * rate)
	var two := PackedInt32Array()      # (two samples an int: low, then high)
	two.resize(n / 2)
	var lo := 0
	for i in n:
		var v := x[i] * gain
		if i >= n - fade:
			v *= float(n - 1 - i) / fade
		var m := absf(v)
		if m > KNEE:
			v = signf(v) * (KNEE + (PEAK - KNEE) * tanh((m - KNEE) / (PEAK - KNEE)))
		var q := roundi(v * 32767.0)
		if i & 1 == 0:
			lo = q & 0xFFFF
		else:
			two[i >> 1] = (q << 16) | lo
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.stereo = false
	w.mix_rate = rate
	w.data = two.to_byte_array()
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = n
	return w


## The RMS (linear) of x's loudest 100 ms at `rate` (its whole length if it is shorter).
static func loudest(x: PackedFloat32Array, rate: int) -> float:
	var n := x.size()
	var w := mini(n, int(0.1 * rate))
	if w <= 0:
		return 0.0
	var acc := 0.0
	for i in w:
		acc += x[i] * x[i]
	var best := acc
	for i in range(w, n):
		acc += x[i] * x[i] - x[i - w] * x[i - w]
		if acc > best:
			best = acc
	return sqrt(maxf(best, 0.0) / w)


## A stream's samples, -1..1 (16-bit mono, as made here; [] for anything else).
static func samples(w: AudioStreamWAV) -> PackedFloat32Array:
	var x := PackedFloat32Array()
	if w == null or w.format != AudioStreamWAV.FORMAT_16_BITS or w.stereo:
		return x
	var n := w.data.size() / 2
	x.resize(n)
	for i in n:
		x[i] = w.data.decode_s16(i * 2) / 32768.0
	return x
