## Mono field recordings. Distance and panning follow the actual opponent. Use relative
## velocity for pitch: Godot's world-space Doppler would see jumps at floating-origin shifts.
extends RefCounted

const ENGINE := preload("res://audio/race/rival_v10.wav")
const START := preload("res://audio/pad/clear_eridanus.wav")
const EARSHOT := 450.0
var green := AudioStreamPlayer.new()
var voices: Array[AudioStreamPlayer3D] = []

func build(parent: Node, count: int) -> void:
	parent.add_child(green)
	green.stream = START
	green.volume_db = -7.0
	for i in count:
		var voice := AudioStreamPlayer3D.new()
		voice.stream = ENGINE
		voice.unit_size = 24.0
		voice.max_distance = EARSHOT
		voice.volume_db = -9.0
		voice.max_db = -5.0
		parent.add_child(voice)
		voices.append(voice)

func reset() -> void:
	green.stop()
	for voice in voices:
		voice.stop()

func sync(race) -> void:
	var pod = race.sim.pod
	for p in race.pilots:
		var voice := voices[int(p.number)]
		var offset := Vector2(p.x - pod.x, p.y - pod.y)
		if p.v < 10.0 or offset.length_squared() > EARSHOT * EARSHOT:
			if voice.playing:
				voice.stop()
			continue
		var relative := Vector2.from_angle(p.th) * float(p.v) - Vector2(pod.vx, pod.vy)
		var approach := -offset.normalized().dot(relative)
		voice.pitch_scale = (1.0 + 0.04 * p.number + 0.18 * p.push) * (1.0 + 0.32 * tanh(approach / 220.0))
		voice.position = race._w(p.x, p.y, p.z)
		if not voice.playing:
			voice.play(fmod(p.number * 0.27, ENGINE.get_length()))
