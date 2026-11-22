## The dashboard and the shorter cockpit opening (tools/art_dash_hd.py, fitted by
## vr/cockpit_interior.gd; Luke: "remove 12 inches of 'legroom' between the gauges and seat. The idea
## is to have good visibility through the smallest opening possible", and "move it [the gauge
## cluster] up to the rail, and create a true dash board"):
##   fitted    the dashboard and the seal along its top's outer edge, both sides, in the cockpit's shell
##   nearer    the instruments are 12 inches nearer the seat than they were, and the opening's front
##             edge has come back with them: the opening is smaller, and no wider or longer aft
##   the rail  from the seated eye the instruments' cowl reaches the coaming: its crest is seen
##             against the roll, between the lip's top and its hem
##   closes    a look under the rim, anywhere round the front of the opening and from any head that
##             fits under the roof, lands on the dashboard: never on the open nose behind it
##   clear     of the levers' travel and the deck's treads' run, and no higher than the rim's underside
## Prints DASH PASS.
extends SceneTree

const View := preload("res://view/craft_view.gd")
const Cockpit := preload("res://vr/vr_cockpit.gd")
const CM := preload("res://view/craft_model.gd")
const Instruments := preload("res://vr/dashboard.gd")
const WAS_Z := -0.70             # where the instruments stood (push 20)
const WAS_FRONT := 1.15          # the opening's half-length ahead of its widest point, as it was
var failures := 0


func _initialize() -> void:
	View.track_override = "range"
	View.job_override = "none"
	View.best_dir = OS.get_user_data_dir().path_join("test_dash_")
	_run.call_deferred()


func _check(label: String, passed: bool) -> void:
	print(("PASS " if passed else "FAIL ") + label)
	failures += int(not passed)


var roll := PackedVector3Array()      # the coaming's own mesh, rig metres (the padded roll round the opening and its band)


## Does a look land on the coaming (its roll round the opening's edge, or the band under it)?
func _on_roll(from: Vector3, to: Vector3) -> bool:
	return _hits(roll, from, to)


func _hits(faces: PackedVector3Array, from: Vector3, to: Vector3) -> bool:
	var along := (to - from).normalized()
	var reach := from.distance_to(to)
	for i in range(0, faces.size(), 3):
		var at = Geometry3D.ray_intersects_triangle(from, along, faces[i], faces[i + 1], faces[i + 2])
		if at != null and from.distance_to(at) < reach:
			return true
	return false


func _run() -> void:
	var v = Cockpit.new()
	root.add_child(v)
	await process_frame
	v.set_process(false)
	var dash := v.interior.get_node_or_null("Dashboard") as MeshInstance3D
	var seal := v.interior.get_node_or_null("DashboardSeal") as MeshInstance3D
	_check("the dashboard and its seal are fitted in the cockpit", dash != null and dash.mesh != null and seal != null and seal.mesh != null and seal.is_in_group("under_the_lip"))
	if dash == null or seal == null:
		quit(1)
		return
	var faces: PackedVector3Array = dash.mesh.get_faces()      # rig metres: the interior sits at the shell's origin
	var edging: PackedVector3Array = seal.mesh.get_faces()
	var coaming := v.interior.get_node_or_null("SegmentedCoaming") as MeshInstance3D
	if coaming != null and coaming.mesh != null:
		roll = coaming.mesh.get_faces()
	var box := dash.mesh.get_aabb()
	_check("both sides, %d triangles and %d in the seal, from %.2f m ahead to %.2f m, %.2f to %.2f m up, out to %.2f m" % [faces.size() / 3, edging.size() / 3, -box.position.z, -box.end.z, box.position.y, box.end.y, box.end.x],
		faces.size() / 3 > 3000 and edging.size() / 3 > 100 and absf(box.position.x + box.end.x) < 0.005 and box.position.z > -0.58 and box.end.z < 0.02 and box.position.y > 0.05)

	# nearer: the instruments by 12 inches, the opening's front with them
	var mount := Instruments.mount()
	var front: Vector2 = CM.open_edge(-PI / 2.0)
	var side: Vector2 = CM.open_edge(0.0)
	var back: Vector2 = CM.open_edge(PI / 2.0)
	var area := PI * CM.OPEN_AX * (CM.OPEN_AZ + CM.OPEN_AZ_FRONT) / 2.0
	var area_was := PI * CM.OPEN_AX * (CM.OPEN_AZ + WAS_FRONT) / 2.0
	var eye := Cockpit.SEAT
	_check("the instruments are %.1f inches nearer the seat (%.2f m from the eye; they were %.2f m); the opening's front edge is %.2f m nearer and the opening %.0f %% smaller (%.2f m2), no wider (%.2f m) and no longer aft (%.2f m)" % [
			(mount.origin.z - WAS_Z) / 0.0254, eye.distance_to(mount.origin), eye.distance_to(Vector3(0, 0.27, WAS_Z)), front.y - (CM.OPEN_ZC - WAS_FRONT), (1.0 - area / area_was) * 100.0, area, side.x * 2.0, back.y],
		absf((mount.origin.z - WAS_Z) / 0.0254 - 12.0) < 0.25 and front.y > CM.OPEN_ZC - WAS_FRONT + 0.3 and is_equal_approx(side.x, 0.72) and is_equal_approx(back.y, CM.OPEN_ZC + 1.15))

	# the rail: where the cowl's crest is seen from the seat, against the coaming's roll at the nose
	var crest := INF
	var body := v.dashboard.get_node_or_null("binnacle") as MeshInstance3D
	if body:
		var to_rig: Transform3D = v.shell.global_transform.affine_inverse() * body.global_transform
		for p in body.mesh.get_faces():
			var q: Vector3 = to_rig * p
			crest = minf(crest, rad_to_deg(atan2(eye.y - q.y, Vector2(q.x - eye.x, q.z - eye.z).length())))
	var rim_y: float = CM.hull_top(front.x, front.y) + CM.POD_FRAME_UP
	var lip_top := rad_to_deg(atan2(eye.y - (rim_y + CM.LIP_R), eye.z - front.y))
	var hem := rad_to_deg(atan2(eye.y - (rim_y - 0.05), eye.z - (front.y + 0.02)))
	_check("up to the rail: the cowl's crest is seen %.1f degrees under level, against the coaming (its top %.1f, its hem %.1f)" % [crest, lip_top, hem],
		body != null and crest > lip_top and crest < hem)

	# closes: looks under the rim, round the front of the opening, from the seat and from a head moved about
	var heads := {"seated": eye, "low": eye + Vector3(0, -0.12, 0), "leaning forward": eye + Vector3(0, 0.02, -0.3), "leaning left": eye + Vector3(-0.2, -0.03, -0.05),
		"leaning right": eye + Vector3(0.2, -0.03, -0.05), "low and forward": eye + Vector3(0, -0.14, -0.25),
		# (the pilot's own eye is SEAT_RISE over the point the cabin is laid out round: his looks too)
		"the pilot's own": Cockpit.EYE, "his, leaning forward": Cockpit.EYE + Vector3(0, 0.02, -0.3), "his, leaning left": Cockpit.EYE + Vector3(-0.2, -0.03, -0.05),
		"his, leaning right": Cockpit.EYE + Vector3(0.2, -0.03, -0.05)}
	var consoles: Array[AABB] = []       # (as vr/cockpit_interior.gd has them: a look that enters one has landed on it)
	for side_x in [-1.0, 1.0]:
		consoles.append(AABB(Vector3(side_x * 0.615 - 0.065, 0.105, -0.055), Vector3(0.13, 0.29, 0.95)))
	var looks := 0
	var on_roll := 0
	var open := []
	for name in heads:
		var from: Vector3 = heads[name]
		for k in range(-15, 16):
			var ph := -PI / 2.0 + deg_to_rad(k * 5.0 + 0.4)      # (a little off the fives: a look dead along the centreline runs down the seam between the two halves)
			var e: Vector2 = CM.open_edge(ph)
			var top: float = CM.hull_top(e.x, e.y) + CM.POD_FRAME_UP
			for drop in [0.062, 0.07, 0.09, 0.14, 0.2, 0.28, 0.36]:
				var to := Vector3(e.x, top - drop, e.y)
				if to.y < 0.15:      # (under the deck's top: the deck is in the way)
					continue
				looks += 1
				if consoles[0].intersects_segment(from, to) != null or consoles[1].intersects_segment(from, to) != null:
					continue
				if not _hits(faces, from, to) and not _hits(edging, from, to):
					# (from the pilot's own height a look comes down steeper, and what it meets first is the coaming's
					# padded roll round the opening: that has landed too. The six heads the cabin was laid out for must
					# still land on the dashboard itself.)
					if String(name).begins_with("his") or String(name) == "the pilot's own":
						if _on_roll(from, to):
							on_roll += 1
							continue
					open.append("%s, %d degrees round, %.3f m under the hull's top" % [name, k * 5, drop])
	_check("a look under the rim lands on the dashboard: %d looks from %d heads (%d from the pilot's own height land on the coaming's roll first), %d reach the nose%s" % [looks, heads.size(), on_roll, open.size(), "" if open.is_empty() else " (" + "; ".join(open.slice(0, 16)) + ")"],
		open.is_empty())

	# clear of what moves and of the rim
	var levers := AABB(Vector3(-0.6, 0.125, 0.0), Vector3(1.2, 0.475, 0.44))
	var into_levers := 0
	var over_rim := -INF
	for p in faces:
		into_levers += int(levers.has_point(p))
		over_rim = maxf(over_rim, p.y - (CM.hull_top(p.x, p.z) + CM.POD_FRAME_UP))
	var knee := INF       # the fascia at knee height, either side of the centreline
	for p in faces:
		if absf(p.y - 0.35) < 0.02 and absf(p.x) < 0.3:
			knee = minf(knee, 0.60 - p.z)
	_check("clear of the levers' travel (%d points in it); its top %.3f m under the hull's; %.2f m from the cushion's front to the fascia at the knee" % [into_levers, -over_rim, knee],
		into_levers == 0 and over_rim < -0.05 and knee > 0.9)
	v.queue_free()
	await process_frame
	print("DASH %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)
