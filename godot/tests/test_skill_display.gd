## Render and exercise the quiet corner -> earning -> fade -> corner lifecycle.
extends SceneTree
const View := preload("res://view/craft_view.gd")
const VR := preload("res://vr/vr_cockpit.gd")
var checks := 0
var failures := 0
class Cockpit extends VR:
	func _load_prefs() -> Dictionary:
		return {"scheme":"triggers", "handling":"speed"}
	func _save_prefs() -> void:
		pass
func check(label: String, ok: bool) -> void:
	checks += 1
	failures += int(not ok)
	print(("PASS " if ok else "FAIL ") + label)
func _initialize() -> void:
	_run.call_deferred()
func shot(v, name: String) -> void:
	v._update_hud()
	for frame in 5:
		await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var directory := ProjectSettings.globalize_path("res://../evidence/v023-score")
		DirAccess.make_dir_recursive_absolute(directory)
		root.get_texture().get_image().save_png(directory.path_join(name + ".png"))
func _run() -> void:
	View.track_override = "range"
	View.job_override = "none"
	for vr in [false, true]:
		var v = Cockpit.new() if vr else View.new()
		root.add_child(v)
		v.set_process(false)
		v.skill_score.path = ""
		v._follow_origin()
		v._sync_craft(0.016)
		v._place_camera(1.0)
		v._update_hud()
		var label = v.get("_skill_readout") if vr else v.get("_skill_label")
		var award = v.get("_skill_award") if vr else v.get("_skill_award_label")
		check("separate total and temporary award displays VR=%s" % vr, label != null and award != null)
		if label == null or award == null:
			v.free()
			continue
		var corner = label.position
		check("idle total is quiet in the right corner VR=%s" % vr, corner.x > 0.5 and label.modulate.a < 0.7 and award.modulate.a == 0.0)
		await shot(v, "vr-idle" if vr else "desktop-idle")
		v.skill_score._award("turn", "HIGH-SPEED PRECISION", 1225)
		await shot(v, "vr-earning" if vr else "desktop-earning")
		var active = label.position
		check("earned points pop center-top with a readable award VR=%s" % vr, active.x < corner.x and label.modulate.a > 0.95 and award.text.contains("PRECISION") and award.modulate.a > 0.95)
		v.skill_score.time += 1.5
		await shot(v, "vr-fading" if vr else "desktop-fading")
		check("total and award visibly fade toward corner VR=%s" % vr, label.position.x > active.x and label.position.x < corner.x and award.modulate.a > 0.0 and award.modulate.a < 1.0)
		v.skill_score.time += 1.0
		await shot(v, "vr-returned" if vr else "desktop-returned")
		check("after earning stops only quiet total remains VR=%s" % vr, label.position.distance_to(corner) < 0.001 and label.text.contains("1225") and award.modulate.a == 0.0)
		if vr:
			check("faded VR award leaves no outline ghost", award.outline_modulate.a == 0.0)
		v.skill_score._award("speed", "SPEED", 18, false)
		v._update_hud()
		check("new points reactivate center display VR=%s" % vr, label.position.distance_to(active) < 0.001 and label.modulate.a > 0.95)
		v.menu_open(true)
		check("pause hides score overlay VR=%s" % vr, not label.visible and not award.visible)
		v.menu_open(false)
		v._respawn()
		v._update_hud()
		check("restart restores quiet zero without replaying reward VR=%s" % vr, label.position.distance_to(corner) < 0.001 and label.text == "0 PTS")
		v.free()
	View.track_override = ""
	View.job_override = ""
	print("SKILL DISPLAY %s (%d checks, %d failures)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(int(failures > 0))
