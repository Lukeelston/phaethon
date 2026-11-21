## The start-up's own sounds (vr/startup_sequence.gd): the switches, the guard, the battery bus
## coming up behind its contactor, the self-test's chime, the fuel pumps priming and the binder
## striking, each engine's starter and the moment it catches, the parking brake's clamp and its air,
## and the knock of a refused control.
## Every one is cut from a field recording (Luke, after the eleventh flight: the synthesised ones
## "sound like an 80's racing arcade box. Use real free assets if you must"): a metal switch, a
## hinged lid, a sprung button, a large relay, a server's fans, a motorcycle's fuel pump, a Tesla
## coil, a car's starter turning an engine that will not fire, a five-litre V8 lighting, a breaker
## and an air valve. tools/startup_audio_bake.py trims, layers and levels them into res://audio/startup;
## its CREDITS.md lists each source (all CC0).
## The engines' own voices (turning over, catching, idling) are still EngineAudio's, told by its
## `off` and `crank`.
## A switch's sound comes from its pod when the panel is fitted (a 3D player there, panned by where
## the head is turned); the rest are the whole cockpit's, and a starter and a catch are their engine's.
## Unverified by ear: lengths, peaks and loudness are measured (each new sound was set as loud as
## the one it replaced), and that is all that can be said until a pilot has heard them.
##   add_child(a); a.setup(overhead.pods)      once, inside the tree ({} or nothing: no pods)
##   a.play("toggle_on")                        a sound by name; play("starter", 1) for the right engine's
##   a.hum(power, running, delta)               every frame: the fans, heard while the engines are dark
class_name StartupAudio
extends Node

const DIR := "res://audio/startup/"
const RATE := 48000
const NAMES := ["toggle_on", "toggle_off", "paddle_on", "paddle_off", "guard_up", "guard_down", "button", "power", "down",
	"avionics", "chime", "pump", "arc", "starter", "catch", "clamp", "release", "refuse"]
const POLYPHONY := 3
## The pod a control's sound comes from (OverheadPanel.pods' keys: -1 left, 1 right).
const AT_POD := {"toggle_on": -1.0, "toggle_off": -1.0, "guard_up": -1.0, "guard_down": -1.0,
	"button": 1.0, "paddle_on": 1.0, "paddle_off": 1.0}
const BY_ENGINE := ["starter", "catch"]     # one player an engine, panned with it
const LOOP := "avionics"
const VARY := 1.03                          # a switch's every throw up to 3% higher or lower than the last
const HUM_TAU := 1.2                        # s: the fans' loop coming in under the power-up, and going
static var _bank := {}      # name -> Array[AudioStreamWAV]: its takes
static var _levels := {}    # name -> dB

var players := {}           # name -> [player]: one, or [left, right] for an engine's
var played: Array[String] = []   # what has been asked for, in order (the tests read it)
var hum_gain := 0.0         # the fans' loop, 0..1 (the tests read it)
var _hum: AudioStreamPlayer


func setup(pods := {}) -> void:
	bank()
	var bus := "Cockpit"
	if AudioServer.get_bus_index(bus) < 0:
		var i := AudioServer.bus_count
		AudioServer.add_bus(i)
		AudioServer.set_bus_name(i, bus)
		AudioServer.set_bus_send(i, "Master")
	for sound: String in NAMES:
		var takes: Array = _bank[sound]
		if sound == LOOP:
			_hum = AudioStreamPlayer.new()
			_hum.stream = takes[0]
			_hum.volume_db = -80.0
			_hum.bus = bus
			add_child(_hum)
			players[sound] = [_hum]
			continue
		var list := []
		if sound in BY_ENGINE:
			for k in 2:
				var p := AudioStreamPlayer.new()
				p.stream = takes[mini(k, takes.size() - 1)]
				# (one take for both: the right engine's a little lower, as its starter is)
				p.pitch_scale = 0.96 if k == 1 and takes.size() == 1 else 1.0
				# the pops' bus carries the engine's pan and no low-pass
				var side := "EngineL_pops" if k == 0 else "EngineR_pops"
				p.bus = side if AudioServer.get_bus_index(side) >= 0 else bus
				list.append(p)
				add_child(p)
		elif AT_POD.has(sound) and pods.has(AT_POD[sound]):
			var p := AudioStreamPlayer3D.new()
			p.stream = _varied(takes)
			p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED   # 0.4 m away: placed, not faded
			p.attenuation_filter_cutoff_hz = 20500.0                        # ... nor dulled
			p.bus = bus
			list.append(p)
			(pods[AT_POD[sound]] as Node3D).add_child(p)
		else:
			var p := AudioStreamPlayer.new()
			p.stream = _varied(takes) if AT_POD.has(sound) else takes[0]
			p.bus = bus
			list.append(p)
			add_child(p)
		for p in list:
			p.volume_db = _levels[sound]
			p.max_polyphony = POLYPHONY
		players[sound] = list


## A switch's takes, played in turn at a slightly different pitch each time.
static func _varied(takes: Array) -> AudioStreamRandomizer:
	var r := AudioStreamRandomizer.new()
	r.playback_mode = AudioStreamRandomizer.PLAYBACK_RANDOM_NO_REPEATS
	r.random_pitch = VARY
	for w: AudioStreamWAV in takes:
		r.add_stream(-1, w)
	return r


func play(sound: String, side := 0) -> void:
	played.append(sound)
	if not players.has(sound):
		return
	var list: Array = players[sound]
	var p: Node = list[mini(side, list.size() - 1)]
	if is_instance_valid(p):
		p.call("play")


## Stop a sound that is still running (a starter, when the engines are cut mid-start).
func stop(sound: String) -> void:
	for p: Node in players.get(sound, []):
		if is_instance_valid(p):
			p.call("stop")


## The fans and gyros left running on the battery: heard with the bus up (power 0..1) and the
## engines dark, gone under them once they run (running 0..1). Call every frame.
func hum(power: float, running: float, delta: float) -> void:
	var want := clampf(power, 0.0, 1.0) * (1.0 - clampf(running, 0.0, 1.0))
	hum_gain = lerpf(hum_gain, want, 1.0 if delta <= 0.0 else 1.0 - exp(-delta / HUM_TAU))
	if _hum == null:
		return
	if hum_gain < 0.003:
		if _hum.playing:
			_hum.stop()
		return
	_hum.volume_db = float(_levels[LOOP]) + linear_to_db(hum_gain)
	if not _hum.playing:
		_hum.play()


## Every sound's takes, loaded on first asking.
static func bank() -> Dictionary:
	if _bank.is_empty():
		var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DIR + "manifest.json"))
		for sound: String in NAMES:
			var spec: Dictionary = manifest.sounds[sound]
			var takes := []
			for f: String in spec.files:
				var w := (ResourceLoader.load(DIR + f) as AudioStreamWAV).duplicate() as AudioStreamWAV
				w.loop_mode = AudioStreamWAV.LOOP_FORWARD if spec.get("loop", false) else AudioStreamWAV.LOOP_DISABLED
				if spec.get("loop", false):
					w.loop_begin = 0
					w.loop_end = w.data.size() >> 1   # 16-bit mono frames
				takes.append(w)
			_bank[sound] = takes
			_levels[sound] = float(spec.level_db)
	return _bank


static func level_db(sound: String) -> float:
	bank()
	return _levels[sound]
