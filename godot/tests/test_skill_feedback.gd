## Actual desktop/VR presentation, lifecycle and mixed reward audio.
extends SceneTree
const View := preload("res://view/craft_view.gd")
const VR := preload("res://vr/vr_cockpit.gd")
const Audio := preload("res://audio/skill_audio.gd")
var checks := 0
var failures := 0

class Cockpit extends VR:
	func _load_prefs() -> Dictionary:
		return {"scheme": "triggers", "handling": "speed"}
	func _save_prefs() -> void:
		pass

func check(label: String, ok: bool) -> void:
	checks += 1
	failures += int(not ok)
	print(("PASS " if ok else "FAIL ") + label)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var out := ProjectSettings.globalize_path("res://../evidence/v023-feedback")
	DirAccess.make_dir_recursive_absolute(out)
	View.best_dir = out.path_join("fixture_")
	View.track_override = "range"
	View.job_override = "none"
	for vr in [false, true]:
		var v = Cockpit.new() if vr else View.new()
		root.add_child(v)
		v.set_process(false)
		v.skill_score.path = "" # rendering fixtures never become best scores
		check("mute suppresses reward audio VR=%s" % vr, v.skill_audio == null)
		v.skill_score.total = 123456
		v.skill_score.multiplier = 3.5
		v.skill_score.award_text = "HIGH-SPEED PRECISION  +1,225"
		v.skill_score.best = 182350
		for body in v.sim.bodies:
			body.vx = 2700.0
		v._follow_origin()
		v._sync_craft(0.016)
		v._place_camera(1.0)
		v._update_hud()
		for f in 50:
			await process_frame
		var words: String = (v._skill_readout.text + v._skill_award.text) if vr else (v._skill_label.text + v._skill_award_label.text)
		check("score and award are visible to the actual view VR=%s" % vr, words.contains("123456") and words.contains("PRECISION"))
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			check("render saved VR=%s" % vr, root.get_texture().get_image().save_png(out.path_join("vr.png" if vr else "desktop.png")) == OK)
		v.menu_open(true)
		var before: float = v.skill_score.time
		for f in 60:
			v._process(0.016)
		check("pause freezes score and multiplier VR=%s" % vr, v.skill_score.time == before and v.skill_score.total == 123456 and v.skill_score.multiplier == 3.5)
		v.menu_open(false)
		v._respawn()
		check("view restart clears run and keeps best VR=%s" % vr, v.skill_score.total == 0 and v.skill_score.best == 182350)
		v.free()
	# Capture the actual audio mix, rather than merely checking play() was called.
	var sound := Audio.new()
	root.add_child(sound)
	sound.setup()
	var capture := AudioEffectCapture.new()
	capture.buffer_length = 2.0
	var effect_index := AudioServer.get_bus_effect_count(0)
	AudioServer.add_bus_effect(0, capture)
	sound.update(0.1, [{"kind": "turn", "points": 1225, "multiplier": 3.5}])
	var first_stream = sound.player.stream
	sound.update(0.05, [{"kind": "jump", "points": 1600, "multiplier": 4.0}])
	check("dense rewards do not interrupt the current cue", sound.player.stream == first_stream)
	await create_timer(0.65).timeout
	var frames := capture.get_buffer(capture.get_frames_available())
	var peak := 0.0
	for sample in frames:
		peak = maxf(peak, maxf(absf(sample.x), absf(sample.y)))
	check("mixed reward chime is audible and unclipped: %.5f" % peak, peak > 0.001 and peak < 0.95)
	var left := PackedFloat32Array()
	var right := PackedFloat32Array()
	for sample in frames:
		left.append(sample.x)
		right.append(sample.y)
	if not left.is_empty():
		Audio.Synth._wav(left, right, int(AudioServer.get_mix_rate()), peak).save_to_wav(out.path_join("reward-mix.wav"))
	AudioServer.remove_bus_effect(0, effect_index)
	sound.free()
	View.track_override = ""
	View.job_override = ""
	View.best_dir = "user://"
	print("SKILL FEEDBACK %s (%d checks, %d failures)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(int(failures > 0))
