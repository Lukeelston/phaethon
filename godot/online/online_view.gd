## Shared by desktop and VR. Tick even while the local menu is open.
extends Node
const Remote := preload("res://online/remote_craft.gd")
var view
var session
var remotes := {}
var send_acc := 0.0
var hud: Label
var vr_label: Label3D
var summary := ""

func build(v) -> void:
	view = v
	session = get_node("/root/RaceSession")
	if "rig" in view and view.rig != null:
		vr_label = Label3D.new()
		vr_label.font_size = 24
		vr_label.pixel_size = 0.0008
		vr_label.position = Vector3(0, 0.9, -1.5)
		vr_label.modulate = Color(0.4, 0.9, 1.0)
		view.rig.add_child(vr_label)
	else:
		var layer := CanvasLayer.new()
		hud = Label.new()
		hud.position = Vector2(18, 670)
		hud.add_theme_font_size_override("font_size", 18)
		hud.add_theme_color_override("font_color", Color(0.4, 0.95, 1.0))
		hud.add_theme_color_override("font_outline_color", Color.BLACK)
		hud.add_theme_constant_override("outline_size", 6)
		layer.add_child(hud)
		add_child(layer)

func capture_pose() -> PackedFloat64Array:
	session.sequence += 1.0
	var out := PackedFloat64Array([session.sequence, session.epoch])
	for body in [view.craft.pod, view.craft.engines[0], view.craft.engines[1]]:
		var xf: Transform3D = body.transform
		var q := xf.basis.orthonormalized().get_rotation_quaternion()
		out.append_array(PackedFloat64Array([
			float(xf.origin.x) + float(view.org_x), float(xf.origin.y), float(xf.origin.z) - float(view.org_y),
			q.x, q.y, q.z, q.w]))
	out.append_array(PackedFloat64Array([
		clampf(view.sim.eL.thrust, 0, 2), clampf(view.sim.eR.thrust, 0, 2),
		2.0 if view.sim.mode == "ramjet" else (0.0 if view.sim.mode == "normal" else 1.0)]))
	return out

func update(delta: float) -> void:
	send_acc += delta
	if send_acc >= 0.05 and session.active:
		send_acc = fmod(send_acc, 0.05)
		session.publish_pose(capture_pose())
	for id in remotes.keys():
		if not session.players.has(id):
			remotes[id].queue_free()
			remotes.erase(id)
	summary = session.status
	for id in session.players:
		if id == multiplayer.get_unique_id(): continue
		if not remotes.has(id):
			var remote := Remote.new()
			view.add_child(remote)
			remote.build(session.players[id])
			remotes[id] = remote
		var pose: PackedFloat64Array = session.pose_for(id)
		remotes[id].visible = not pose.is_empty()
		if pose.is_empty():
			summary = "%s · waiting for position" % session.players[id]
			continue
		remotes[id].apply_pose(pose, view.org_x, view.org_y)
		var distance: float = remotes[id].bodies[0].position.length()
		remotes[id].visible = distance < 40000.0
		var relative: Vector3 = view.cam.global_transform.affine_inverse() * remotes[id].bodies[0].global_position
		var direction := "ahead" if relative.z < 0 else "behind"
		if absf(relative.x) > absf(relative.z) * 0.5:
			direction += " left" if relative.x < 0 else " right"
		summary = "%s · %.2f mi · %s" % [session.players[id], distance / 1609.344, direction]
	if view.menu.open: summary += " · your craft is paused"
	if hud: hud.text = summary + "  |  Esc: menu / leave"
	if vr_label: vr_label.text = summary
