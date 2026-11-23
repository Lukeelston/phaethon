## The pilot an inch forward, and the pod pitched under him (vr_cockpit.gd SEAT_FWD, POD_PITCH, pod_pose;
## Luke, 2026-11-23, from the seat: "move the pilot forward about an inch", and "Can you also angle the
## vehicle down a few degrees? I like the nose being enclosed, but it does make it tough to see the road in
## turns"). In the production cockpit (XR off), on the range:
##   the seat     the eye is an inch ahead of where it was, among the same fittings.
##   the pose     the pod stands a few degrees nose-down on the rig, turned about the pilot's own eye point
##                and nothing else: that point is the same place in the pod and on the rig.
##   his head     the headset's origin is on the rig at the eye point, not turned; the camera is level, over
##                the craft where it always was, and looks along her way: the horizon has not moved.
##   leaning      rolled over in a turn the camera rolls with the rig as it did, the head stays where it
##                was, and the pod is still that pitch under the view, about the view's own level line.
##   the nose     is lower in his view by the pitch: the hooks on it by the pitch exactly.
##   the links    the engines stand level as they did; each tow link's swivel is on its hook on the pitched
##                nose (the hull's own, the rig's marker, the model's anchor: one place) and stands along the
##                pod's up, not the rig's.
##   his face     nothing in the cockpit is nearer his eyes than the start panel overhead, at rest or with
##                the speed rush's travel fully back.
## --headless --xr-mode off --audio-driver Dummy -s res://tests/test_pod_pitch.gd -- --mute
## Prints POD PITCH PASS. (tests/probe_pod_pitch.gd has what it changes in numbers: the road in sight, his
## reach, the dash.)
extends SceneTree

const View := preload("res://view/craft_view.gd")
const Cockpit := preload("res://vr/vr_cockpit.gd")
const CM := preload("res://view/craft_model.gd")
const Rush := preload("res://vr/speed_rush.gd")
const ClashKit := preload("res://tests/clash_kit.gd")
const FRAME := 1.0 / 90.0
var v
var failures := 0
var checks := 0


func _initialize() -> void:
	View.track_override = "range"
	View.job_override = "none"
	View.best_dir = OS.get_user_data_dir().path_join("test_pod_pitch_")
	Cockpit.camera = "cockpit"
	Cockpit._camera_loaded = true      # the pilot's saved choices stay out of this
	Cockpit._nose_loaded = true
	Cockpit._slide_loaded = true
	Cockpit._startup_loaded = true
	Cockpit._map_loaded = true
	Cockpit._school_loaded = true
	Cockpit._rush_loaded = true
	Cockpit.speed_rush = false         # (the shell at its place: the speed rush has its own test)
	Cockpit.cold_start = false
	Cockpit.school = false
	_run.call_deferred()


func _check(label: String, passed: bool) -> void:
	checks += 1
	print(("PASS " if passed else "FAIL ") + label)
	failures += int(not passed)


## A frame of the cockpit as the game runs one (the sim not stepped: she stands where she is).
func _frame() -> void:
	await process_frame
	v._follow_origin()
	v._sync_craft(FRAME)
	v._place_camera(1.0)
	v.craft.sync_cables(v.sim, FRAME)
	v._apply_shudder(FRAME)


## The nearest thing to a point of the cockpit's own space: [metres, its name].
func _nearest(kit, space: PhysicsDirectSpaceState3D, point: Vector3) -> Array:
	var sphere := SphereShape3D.new()
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = sphere
	q.transform = Transform3D(Basis.IDENTITY, point)
	var lo := 0.0
	var hi := 1.2
	var who := "nothing"
	sphere.radius = hi
	if space.intersect_shape(q, 1).is_empty():
		return [hi, who]
	while hi - lo > 0.0005:
		var mid := (lo + hi) * 0.5
		sphere.radius = mid
		var found := space.intersect_shape(q, 1)
		if found.is_empty():
			lo = mid
		else:
			hi = mid
			who = kit.names[int(kit._index.get((found[0].collider as Object).get_instance_id(), 0))]
	return [hi, who]


func _run() -> void:
	var prefs_before := FileAccess.get_file_as_string(Cockpit.PREFS) if FileAccess.file_exists(Cockpit.PREFS) else ""
	v = Cockpit.new()
	root.add_child(v)
	for i in 8:                        # (a few frames of the game itself: the sim has stepped, and has its tow links)
		await process_frame
	v.set_process(false)
	for hand in v.hands.values():
		hand.get_child(0).visible = false
	for i in 30:
		await _frame()

	# ---- the seat, and the pose
	var eye: Vector3 = Cockpit.EYE
	_check("the pilot sits %.1f mm ahead of where he did (about an inch), as high as he was: the eye at %s in the pod, the point the cabin is laid out round still %s" % [Cockpit.SEAT_FWD * 1000.0, eye, Cockpit.SEAT],
		absf(Cockpit.SEAT_FWD - 0.0254) < 0.003 and eye.is_equal_approx(Cockpit.SEAT + Vector3(0.0, Cockpit.SEAT_RISE, -Cockpit.SEAT_FWD)) and Cockpit.SEAT == Vector3(0.0, 0.72, 0.6) and is_equal_approx(Cockpit.SEAT_RISE, 0.089))
	var pose: Transform3D = Cockpit.pod_pose()
	var nose: Vector3 = pose.basis * Vector3.FORWARD
	_check("the pod's pose on the rig is %.2f degrees nose-down (a few), about its own level line across, and turns about the pilot's eye point: that point is %.4f mm from itself in the two frames" % [rad_to_deg(asin(-nose.y)), (pose * eye).distance_to(eye) * 1000.0],
		Cockpit.POD_PITCH >= deg_to_rad(2.0) and Cockpit.POD_PITCH <= deg_to_rad(4.0) and absf(asin(-nose.y) - Cockpit.POD_PITCH) < 1e-5 and absf(nose.x) < 1e-7 and pose.basis.x.is_equal_approx(Vector3.RIGHT)
		and pose.basis.is_equal_approx(pose.basis.orthonormalized()) and (pose * eye).distance_to(eye) < 1e-6)

	# ---- at rest: the shell at the pose, his head and the horizon where they were
	var sim = v.sim
	var yaw: float = sim.pod.th - PI / 2.0
	var over: Vector3 = v.wz(sim.pod.x, sim.pod.y, sim.pod.z - 0.8 + CM.POD_LIFT) + Basis(Vector3.UP, yaw) * eye      # the head over the craft's floor, the cockpit level (vr_cockpit.gd _place_camera)
	var cam: Camera3D = v.cam
	var head: Vector3 = (v.global_transform.affine_inverse() * cam.global_transform).origin
	var way := Basis(Vector3.UP, yaw) * Vector3.FORWARD
	_check("at rest the shell stands exactly at that pose; the headset's origin is on the rig at the eye point and not turned; the camera is level (its up %.6f of the world's) and looks along the craft's way (%.4f degrees off it), %.3f mm from where the craft's own place puts the head" % [
			cam.global_basis.y.dot(Vector3.UP), rad_to_deg((-cam.global_basis.z).angle_to(way)), head.distance_to(over) * 1000.0],
		v.shell.transform == pose and v.origin.transform == Transform3D(Basis.IDENTITY, eye) and cam.global_basis.y.dot(Vector3.UP) > 0.999999
		and (-cam.global_basis.z).angle_to(way) < deg_to_rad(0.01) and head.distance_to(over) < 0.0002 and not v.shell.is_ancestor_of(cam))
	var shell_at: Transform3D = v.shell.global_transform
	var hull := v.shell.get_node("PodHull") as Node3D
	var under: float = (-shell_at.basis.z).angle_to(-cam.global_basis.z)
	var in_pod: Vector3 = shell_at.affine_inverse() * cam.global_position
	_check("the pod (its hull with it) is %.3f degrees nose-down under that level view, about the view's own line across; his eyes are at the eye point in it (%.4f mm off)" % [rad_to_deg(under), in_pod.distance_to(eye) * 1000.0],
		absf(under - Cockpit.POD_PITCH) < 1e-4 and (-shell_at.basis.z).y < 0.0 and shell_at.basis.x.dot(cam.global_basis.x) > 0.999999 and hull != null
		and hull.global_basis.is_equal_approx(shell_at.basis) and in_pod.distance_to(eye) < 1e-5)

	# ---- the nose in his view, and the links
	var hooks := [Vector3(-0.18, CM.POD_FRAME_UP + CM.POD_EYE_H, -2.1), Vector3(0.18, CM.POD_FRAME_UP + CM.POD_EYE_H, -2.1)]      # on the hull's nose, pod metres (vr_cockpit.gd _build_cockpit)
	var rig: Transform3D = v.rig.transform
	var was_down := rad_to_deg(asin((eye.y - (hooks[0] as Vector3).y) / (hooks[0] as Vector3).distance_to(eye)))
	var seen: Vector3 = (pose * (hooks[0] as Vector3)) - eye
	var now_down := rad_to_deg(asin(-seen.y / seen.length()))
	var drop: float = (hooks[0] as Vector3).y - (pose * (hooks[0] as Vector3)).y
	_check("the nose is lower in his view: the tow links' hooks on it are %.2f degrees under his level gaze (%.2f with the pod level: %.2f more), %.0f mm lower on the rig" % [now_down, was_down, now_down - was_down, drop * 1000.0],
		absf(now_down - was_down - rad_to_deg(Cockpit.POD_PITCH)) < 0.01 and drop > 0.1 and drop < 0.2)
	var c = v.craft
	var pod_up: Vector3 = (rig.basis * pose.basis).y.normalized()
	var worst_marker := 0.0
	var worst_anchor := 0.0
	var worst_end := 0.0
	var worst_post := 0.0
	var worst_up := 0.0
	var off_rig := 1.0
	var shown := true
	var level := 1.0
	for k in 2:
		var hook: Vector3 = rig * (pose * (hooks[k] as Vector3))                 # where the hull's own nose has it, in the view's space
		worst_marker = maxf(worst_marker, (rig * (v._hardpoints[k].position as Vector3)).distance_to(hook))
		worst_anchor = maxf(worst_anchor, (c._pod_anchor(sim, k) as Vector3).distance_to(hook))
		worst_end = maxf(worst_end, (c.cable_ends[k][1] as Vector3).distance_to(hook))
		var swivel: Transform3D = (c.link_parts[k][0] as Node3D).transform
		worst_post = maxf(worst_post, swivel.origin.distance_to(hook))
		worst_up = maxf(worst_up, 1.0 - swivel.basis.y.normalized().dot(pod_up))
		off_rig = minf(off_rig, 1.0 - swivel.basis.y.normalized().dot(rig.basis.y.normalized()))
		shown = shown and bool(c._link_shown[k]) and (c.link_parts[k][0] as Node3D).visible
		level = minf(level, (c.engines[k] as Node3D).transform.basis.y.normalized().dot(Vector3.UP))
	_check("each tow link meets the pitched nose: the hull's hook, the rig's marker (%.4f mm off it), the model's anchor (%.4f mm), the link's pod end (%.4f mm) and its swivel (%.4f mm) are one place, and the swivel stands along the pod's own up (%.6f off it), not the rig's (%.5f off that: a %.1f degree lean)" % [
			worst_marker * 1000.0, worst_anchor * 1000.0, worst_end * 1000.0, worst_post * 1000.0, worst_up, off_rig, rad_to_deg(acos(clampf(1.0 - off_rig, -1.0, 1.0)))],
		shown and worst_marker < 1e-5 and worst_anchor < 1e-5 and worst_end < 1e-5 and worst_post < 1e-5 and worst_up < 1e-6 and absf(acos(clampf(1.0 - off_rig, -1.0, 1.0)) - Cockpit.POD_PITCH) < 1e-3)
	_check("the engines keep their own attitude: level on the range at rest (their up %.6f of the world's), while the pod's is %.6f" % [level, pod_up.dot(Vector3.UP)],
		level > 0.99999 and absf(pod_up.dot(Vector3.UP) - cos(Cockpit.POD_PITCH)) < 1e-5)

	# ---- leaning: rolled over as in a hard turn
	var head_was: Vector3 = cam.global_position
	c.bank[2] = deg_to_rad(58.0)             # the craft's own lean in a 20 g bend ...
	v._comfort_roll = deg_to_rad(25.0)       # ... and the cockpit's share of it, there already
	v._comfort_roll_rate = 0.0
	v._place_camera(1.0)
	var rolled: float = absf(v.rig.rotation.z)
	shell_at = v.shell.global_transform
	under = (-shell_at.basis.z).angle_to(-cam.global_basis.z)
	in_pod = shell_at.affine_inverse() * cam.global_position
	_check("rolled %.0f degrees in a hard turn the camera rolls with the rig as it did (the origin still not turned on it), his head stays where it was (%.3f mm), and the pod is still %.3f degrees nose-down under the view, about the view's own line across, his eyes at the eye point in it (%.4f mm off)" % [
			rad_to_deg(rolled), cam.global_position.distance_to(head_was) * 1000.0, rad_to_deg(under), in_pod.distance_to(eye) * 1000.0],
		rolled > deg_to_rad(20.0) and cam.global_basis.is_equal_approx(v.rig.global_basis) and v.origin.transform == Transform3D(Basis.IDENTITY, eye) and cam.global_position.distance_to(head_was) < 0.0005
		and absf(under - Cockpit.POD_PITCH) < 1e-4 and shell_at.basis.x.dot(cam.global_basis.x) > 0.999999 and in_pod.distance_to(eye) < 1e-5)
	c.bank[2] = 0.0
	v._comfort_roll = 0.0
	v._comfort_roll_rate = 0.0
	v._place_camera(1.0)

	# ---- his face: the nearest thing to his eyes, at rest and with the speed rush's travel fully back
	var kit = ClashKit.new()
	kit.gather(v.shell)                # (the pod's own space: the eye point is the same place in it)
	kit.arm(root)
	await physics_frame
	await physics_frame
	var space := root.world_3d.direct_space_state
	var at_rest := _nearest(kit, space, eye)
	var thrown := _nearest(kit, space, eye - Vector3(0.0, 0.0, Rush.AFT_MAX))      # the cockpit moved back toward him is his eyes moved forward in it
	kit.free_bodies()
	_check("the nearest thing to his eyes is the start panel over his brow: %.3f m off at rest (%s), %.3f m with the speed rush's travel fully back, %.1f mm (%s); nothing in the cockpit is nearer than 0.28 m" % [
			float(at_rest[0]), String(at_rest[1]), float(thrown[0]), Rush.AFT_MAX * 1000.0, String(thrown[1])],
		float(at_rest[0]) > 0.30 and float(thrown[0]) > 0.28 and String(at_rest[1]).contains("OverheadPanel") and String(thrown[1]).contains("OverheadPanel"))

	v.queue_free()
	await process_frame
	if prefs_before != "":
		var out := FileAccess.open(Cockpit.PREFS, FileAccess.WRITE)
		out.store_string(prefs_before)
		out.close()
	Cockpit.speed_rush = true
	print("POD PITCH %s (%d checks, %d failures)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)
