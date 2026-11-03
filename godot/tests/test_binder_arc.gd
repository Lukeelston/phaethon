extends SceneTree
var failed := 0
func _initialize() -> void:
	var script = load("res://view/binder_arc.gd")
	if script == null:
		print("BINDER ARC FAIL: missing coherent branching discharge renderer")
		quit(1)
		return
	var arc = script.new()
	root.add_child(arc)
	var a := Vector3(-3, 1, -2)
	var b := Vector3(3, 2, -3)
	arc.update_arc(a, b, 0.3, false, 1.0 / 120.0)
	var initial: PackedVector3Array = arc.channel.duplicate()
	check(initial[0].is_equal_approx(a) and initial[-1].is_equal_approx(b), "attached to both emitters")
	var deviation := 0.0
	for i in range(1, initial.size() - 1):
		deviation = maxf(deviation, initial[i].distance_to(a.lerp(b, float(i) / (initial.size() - 1))))
	check(deviation > 0.04, "discharge is not a straight cable")
	check(arc.branches.size() >= 2, "branching discharge")
	var revisions: int = arc.revision
	for i in 120:
		arc.update_arc(a, b, 0.7, false, 1.0 / 120.0)
	check(arc.revision - revisions >= 15 and arc.revision - revisions <= 30, "restrikes bounded independently of refresh rate")
	check(arc.channel != initial, "channel wanders over time")
	a += Vector3(0, 2, 1)
	b += Vector3(0, -1, 2)
	arc.update_arc(a, b, 0.3, false, 1.0 / 120.0)
	check(arc.channel[0].is_equal_approx(a) and arc.channel[-1].is_equal_approx(b), "moving endpoints have no lag")
	var vertices := 0
	for s in arc.mesh.get_surface_count():
		var points: PackedVector3Array = arc.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
		vertices += points.size()
		for p in points:
			if not p.is_finite():
				failed += 1
	check(vertices > 0 and vertices < 7000, "finite bounded geometry")
	var started := Time.get_ticks_usec()
	for i in 360:
		arc.update_arc(a, b, 0.3, false, 1.0 / 120.0)
	print("  arc update average %.3f ms, %d vertices" % [(Time.get_ticks_usec() - started) / 360000.0, vertices])
	arc.update_arc(a, b, 1.0, true, 1.0 / 120.0)
	check(arc.mesh.get_surface_count() == 0, "broken binder removes core and corona")
	arc.update_arc(a, a, 0.0, false, 1.0 / 120.0)
	check(arc.mesh.get_surface_count() == 0, "coincident emitters are safe")
	print("BINDER ARC ", "PASS" if failed == 0 else "FAIL")
	quit(0 if failed == 0 else 1)
func check(ok: bool, label: String) -> void:
	print("  ", "PASS " if ok else "FAIL ", label)
	failed += int(not ok)
