## The seat's tub (tools/art_tub_hd.py, fitted by vr/cockpit_interior.gd; Luke: "close up the sides
## by the pilot's butt so that its more of a monocoque design"):
##   fitted   one mesh, both sides, in the cockpit's shell
##   closes   from the seated eye, a look down beside either hip, or behind either console, lands on
##            the tub: not on the hull's floor or its wall, as it did
##   clear    of the seat, the consoles and the levers' travel; and no higher than the rim
## Prints SEAT TUB PASS.
extends SceneTree

const View := preload("res://view/craft_view.gd")
const Cockpit := preload("res://vr/vr_cockpit.gd")
const CM := preload("res://view/craft_model.gd")
var failures := 0


func _initialize() -> void:
	View.track_override = "range"
	View.job_override = "none"
	View.best_dir = OS.get_user_data_dir().path_join("test_seat_tub_")
	_run.call_deferred()


func _check(label: String, passed: bool) -> void:
	print(("PASS " if passed else "FAIL ") + label)
	failures += int(not passed)


func _run() -> void:
	var v = Cockpit.new()
	root.add_child(v)
	await process_frame
	v.set_process(false)
	var tub := v.interior.get_node_or_null("SeatTub") as MeshInstance3D
	_check("the tub is fitted in the cockpit", tub != null and tub.mesh != null)
	if tub == null:
		quit(1)
		return
	var faces: PackedVector3Array = tub.mesh.get_faces()      # rig metres: the interior sits at the shell's origin
	var box := tub.mesh.get_aabb()
	_check("both sides, %d triangles, from %.2f to %.2f m back, %.2f to %.2f m up, out to %.2f m" % [faces.size() / 3, box.position.z, box.end.z, box.position.y, box.end.y, box.end.x],
		faces.size() / 3 > 3000 and absf(box.position.x + box.end.x) < 0.005 and box.position.z > -0.02 and box.end.z < 1.2 and box.position.y > 0.12)
	# what a look from the seat lands on
	var eye := Cockpit.SEAT
	var looks := {"beside the left hip": Vector3(-0.44, 0.06, 0.74), "beside the right hip": Vector3(0.44, 0.06, 0.74),
		"by the left thigh": Vector3(-0.47, 0.06, 0.62), "by the right thigh": Vector3(0.47, 0.06, 0.62),
		"behind the left console": Vector3(-0.66, 0.2, 0.98), "behind the right console": Vector3(0.66, 0.2, 0.98),
		"under the rim, left": Vector3(-0.75, 0.42, 1.02), "under the rim, right": Vector3(0.75, 0.42, 1.02)}
	var missed := []
	for name in looks:
		var to: Vector3 = (looks[name] as Vector3) - eye
		var hit := false
		for i in range(0, faces.size(), 3):
			var at = Geometry3D.ray_intersects_triangle(eye, to.normalized(), faces[i], faces[i + 1], faces[i + 2])
			if at != null and eye.distance_to(at) < to.length():
				hit = true
				break
		if not hit:
			missed.append(name)
	_check("a look from the seat down either side lands on the tub (%d places; missed %s)" % [looks.size(), missed], missed.is_empty())
	# clear of what stands in it
	var seat := AABB(Vector3(-0.32, 0.085, 0.60), Vector3(0.64, 0.85, 0.6))
	var levers := AABB(Vector3(-0.6, 0.0, 0.0), Vector3(1.2, 0.6, 0.44))
	var into_seat := 0
	var into_levers := 0
	var over_rim := -INF
	for p in faces:
		into_seat += int(seat.has_point(p))
		into_levers += int(levers.has_point(p) and absf(p.x) < 0.53)
		over_rim = maxf(over_rim, p.y - (CM.hull_top(p.x, p.z) + CM.POD_FRAME_UP))
	_check("clear of the seat (%d points in it) and of the levers' travel (%d); its top %.3f m under the hull's" % [into_seat, into_levers, -over_rim],
		into_seat == 0 and into_levers == 0 and over_rim < -0.02)
	v.queue_free()
	await process_frame
	print("SEAT TUB %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)
