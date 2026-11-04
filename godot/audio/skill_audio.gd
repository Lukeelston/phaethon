## Short original synthesized reward tones. At most one cue per 0.65 seconds;
## speed ticks remain quiet. View owns mute/pause and consumes the event queue.
extends Node
const Synth := preload("res://audio/course_audio.gd")
var player: AudioStreamPlayer
var tones := {}
var cooldown := 0.0

func setup() -> void:
	tones = {
		"speed": Synth.make_chime([520.0], 0.18),
		"near": Synth.make_chime([660.0, 990.0], 0.32),
		"turn": Synth.make_chime([587.33, 880.0], 0.32),
		"jump": Synth.make_chime([523.25, 783.99, 1046.5], 0.46),
	}
	player = AudioStreamPlayer.new()
	add_child(player)

func update(dt: float, events: Array) -> void:
	cooldown = maxf(0.0, cooldown - dt)
	if events.is_empty() or cooldown > 0.0:
		return
	var best: Dictionary = events[0]
	for event in events:
		if event.points > best.points:
			best = event
	player.stream = tones.get(best.kind, tones.near)
	player.volume_db = -27.0 if best.kind == "speed" else -19.0
	player.pitch_scale = 1.0 + (best.multiplier - 1.0) * 0.045
	player.play()
	cooldown = 0.65
