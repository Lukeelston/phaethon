## The seat's tub (tools/art_tub_hd.py, fitted by vr/cockpit_interior.gd; Luke: "close up the sides
## by the pilot's butt so that its more of a monocoque design"):
##   fitted   one mesh, both sides, in the cockpit's shell
##   closes   from the seated eye, a look down beside either hip, or behind either console, lands on
##            the tub: not on the hull's floor or its wall, as it did. And its bottom (Luke: "i'd like
##            to see the bottom of the tub fixed please"): a look down between the deck plate and
##            either console lands on a sill, and one between the deck plate and the cushion on the
##            apron
##   clear    of the seat (but for the apron, which is tucked into the cushion's front and under the
##            bolsters' noses), the consoles and the levers' travel (the sills lie under it and are
##            slotted for the levers); and no higher than the rim
## Prints SEAT TUB PASS.
extends SceneTree

const View := preload("res://view/craft_view.gd")
const Cockpit := preload("res://vr/vr_cockpit.gd")
const CM := preload("res://view/craft_model.gd")


var roll := PackedVector3Array()      # what else is solid round the opening, rig metres: the coaming, the rim light under it and its holder, the consoles, the roof's frame


## Does a look land on one of those before it gets where it was going?
func _on_roll(from: Vector3, to: Vector3) -> bool:
	var along := (to - from).normalized()
	var reach := from.distance_to(to)
	for i in range(0, roll.size(), 3):
		var at = Geometry3D.ray_intersects_triangle(from, along, roll[i], roll[i + 1], roll[i + 2])
		if at != null and from.distance_to(at) < reach:
			return true
	return false
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
	for node: Node in [v.interior.get_node_or_null("SegmentedCoaming"), v.interior.get_node_or_null("RimLightHolder"), v.interior.get_node_or_null("RimLighting"),
			v.interior.get_node_or_null("ConsoleL"), v.interior.get_node_or_null("ConsoleR"), v.canopy.find_child("roof", true, false) if v.canopy != null else null]:
		var solid := node as MeshInstance3D
		if solid == null or solid.mesh == null:
			continue
		var to_rig: Transform3D = v.shell.global_transform.affine_inverse() * solid.global_transform
		for p in solid.mesh.get_faces():
			roll.append(to_rig * p)
	var box := tub.mesh.get_aabb()
	_check("both sides, %d triangles, from %.2f to %.2f m back, %.2f to %.2f m up, out to %.2f m" % [faces.size() / 3, box.position.z, box.end.z, box.position.y, box.end.y, box.end.x],
		faces.size() / 3 > 3000 and absf(box.position.x + box.end.x) < 0.005 and box.position.z > -0.09 and box.end.z < 1.2 and box.position.y > 0.06)   # (the sills run forward past the consoles' fronts and their lips roll down toward the floor: test_cables holds them clear of it)
	# what a look from the seat lands on
	var eye := Cockpit.EYE   # (where the pilot's eyes are: SEAT_RISE over the point the cabin is laid out round)
	var looks := {"beside the left hip": Vector3(-0.44, 0.06, 0.74), "beside the right hip": Vector3(0.44, 0.06, 0.74),
		"by the left thigh": Vector3(-0.47, 0.06, 0.62), "by the right thigh": Vector3(0.47, 0.06, 0.62),
		"behind the left console": Vector3(-0.66, 0.2, 0.98), "behind the right console": Vector3(0.66, 0.2, 0.98),
		"under the rim, left": Vector3(-0.75, 0.42, 1.02), "under the rim, right": Vector3(0.75, 0.42, 1.02),
		"between the deck and the left console": Vector3(-0.52, 0.0, 0.42), "between the deck and the right console": Vector3(0.52, 0.0, 0.42),
		"ahead of the left quadrant": Vector3(-0.5, 0.0, -0.03), "ahead of the right quadrant": Vector3(0.5, 0.0, -0.03),
		"between the deck and the cushion": Vector3(0.0, 0.0, 0.572), "between the deck and the cushion, left": Vector3(-0.22, 0.0, 0.572),
		"under the left bolster's nose": Vector3(-0.29, 0.1, 0.665), "under the right bolster's nose": Vector3(0.29, 0.1, 0.665)}
	# From the point the cabin was laid out round, every look lands on the tub itself. From the pilot's own
	# height (SEAT_RISE over it) a look under the rim comes down steeper and meets the coaming's padded roll
	# first: that has landed too.
	var missed := []
	var on_roll := []
	for from: Vector3 in [Cockpit.SEAT, eye]:
		for name in looks:
			var to: Vector3 = (looks[name] as Vector3) - from
			# (the places were chosen just inside the tub as seen from the laid-out seat; from 9 cm higher the same
			# look reaches a place a little before the panel behind it, so it is followed 0.15 m further)
			var reach: float = to.length() + (0.15 if from == eye else 0.0)
			var hit := false
			for i in range(0, faces.size(), 3):
				var at = Geometry3D.ray_intersects_triangle(from, to.normalized(), faces[i], faces[i + 1], faces[i + 2])
				if at != null and from.distance_to(at) < reach:
					hit = true
					break
			if not hit and from == eye and _on_roll(from, from + to):
				on_roll.append(name)
			elif not hit:
				missed.append("%s (%s)" % [name, "the pilot's own height" if from == eye else "the laid-out seat"])
	_check("a look from the seat down either side lands on the tub (%d places, from the laid-out seat and from the pilot's own height; missed %s; on the coaming's roll first: %s)" % [looks.size(), missed, on_roll], missed.is_empty())
	# clear of what stands in it
	var seat := AABB(Vector3(-0.32, 0.085, 0.60), Vector3(0.64, 0.85, 0.6))
	# The apron is tucked into the cushion's front and runs on under the bolsters' noses, below the
	# cushion's top (0.215) all the way: that much of the seat's own space it may lie in.
	var tuck := AABB(Vector3(-0.34, 0.085, 0.60), Vector3(0.68, 0.12, 0.11))
	# The levers swing above the sills (0.112 up) and stand in their slots through them.
	var levers := AABB(Vector3(-0.6, 0.125, 0.0), Vector3(1.2, 0.475, 0.44))
	var into_seat := 0
	var tucked := 0
	var into_levers := 0
	var in_slots := 0
	var over_rim := -INF
	for p in faces:
		if seat.has_point(p):
			if tuck.has_point(p):
				tucked += 1
			else:
				into_seat += 1
		into_levers += int(levers.has_point(p) and absf(p.x) < 0.53)
		in_slots += int(absf(absf(p.x) - 0.46) < 0.018 and p.z > 0.05 and p.z < 0.35 and p.y < 0.2)
		over_rim = maxf(over_rim, p.y - (CM.hull_top(p.x, p.z) + CM.POD_FRAME_UP))
	_check("clear of the seat (%d points in it; %d of the apron's tucked under its front), of the levers' travel (%d) and of their slots (%d); its top %.3f m under the hull's" % [into_seat, tucked, into_levers, in_slots, -over_rim],
		into_seat == 0 and tucked > 0 and into_levers == 0 and in_slots == 0 and over_rim < -0.02)
	v.queue_free()
	await process_frame
	print("SEAT TUB %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)
