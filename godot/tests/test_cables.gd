## Cable gate: both tow links (view/tow_link.gd; they were cables) hook to real hardware at both
## ends, in a hard banked turn, in the flat view (the drawn pod's bullring) and in the VR cockpit
## (its own, the pod being hidden); they are rigid, jointed and telescoping, and keep the cables'
## light. Prints CABLES PASS when every check passes.
## Run: Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_cables.gd -- --track=range --mute
extends SceneTree

const FlatScript := preload("res://view/craft_view.gd")
const VRScript := preload("res://vr/vr_cockpit.gd")
const TowLink := preload("res://view/tow_link.gd")
const TOL := 0.03   # metres
var v
var t := 0.0
var phase := 0
var fails := 0
var passed := 0


func _initialize() -> void:
	_start(FlatScript)


func _start(script) -> void:
	v = script.new()
	v.cruise = 0.5
	root.add_child(v)
	t = 0.0


func _process(_delta: float) -> bool:
	# The craft's own clock, not the wall's. (On a busy machine building the VR cockpit takes seconds; by the
	# wall clock its turn was then measured before it had been flown: "banked -1 deg", once, beside another Godot.)
	t = v.sim.time
	# straight for 2 s, then a hard left (right engine on, left off, left brake) for 1.5 s
	var turning := t > 2.0
	v.inp = {"thrL": 0.0 if turning else 0.5, "thrR": 0.5, "brkL": 1.0 if turning else 0.0, "brkR": 0.0, "repair": false, "reignite": true}
	if t < 3.5:
		return false
	_measure("VR cockpit" if phase == 1 else "flat view")
	v.queue_free()
	phase += 1
	if phase == 1:
		_start(VRScript)
		return false
	var good: bool = fails == 0 and passed == 13
	print("CABLES ", "PASS" if good else "FAIL (%d failed, %d passed)" % [fails, passed])
	quit(0 if good else 1)
	return true


func _measure(label: String) -> void:
	var c = v.craft
	var bank := rad_to_deg(c.bank[2])
	var peak := rad_to_deg(c.roll_rate_peak)
	var cap := rad_to_deg(c.get_script().BANK_RATE_OUT)   # the faster cap: rolling back toward level
	_check("%s: banked %.0f deg in the turn, never rolling faster than %.1f deg/s (cap %.0f)" % [label, bank, peak, cap],
		absf(bank) > 15.0 and peak <= cap + 1e-6 and peak > 20.0)
	# energized: in the turn the left engine is off and the right at half: its cable alone glows
	var gl: float = c.cable_mats[0].emission_energy_multiplier
	var gr: float = c.cable_mats[1].emission_energy_multiplier
	var g_idle: float = c.cable_glow(0.0)[0]
	var g_full: float = c.cable_glow(1.0)[0]
	var g_burn: float = c.cable_glow(1.4)[0]
	# (the left engine is off but braking, so its cable may be lit by strain instead: amber, not the thrust blue)
	var sl: float = c.cable_strain[0]
	var left_ok: bool = gl == 0.0 if sl <= 0.5 else (c.cable_mats[0].emission.r > 0.8 and c.cable_mats[0].emission.b < 0.4)
	_check("%s: cables glow with their own engine's thrust (left off: %.2f, strain %.2f; right at %.2f thrust %.2f; idle %.1f, full %.1f, burner %.1f)" % [
		label, gl, sl, v.sim.eR.thrust, gr, g_idle, g_full, g_burn],
		left_ok and gr > 0.8 and g_idle == 0.0 and g_full > 3.0 and g_burn > g_full)
	# rigid, and telescoping (they were ropes: a slack one hung 2 m, and they swayed): a link stands
	# straight between its pins and its rod runs in and out of its barrel with the span; strain
	# turns its glow amber then red
	var CMs = c.get_script()
	var closed: float = TowLink.exposed_for(16.0) - TowLink.exposed_for(14.0)
	var stretched: float = TowLink.exposed_for(16.2) - TowLink.exposed_for(16.0)
	var glow := Color(0.25, 0.65, 1.0)
	var amber: Color = CMs.strain_color(glow, 0.8)
	var red: Color = CMs.strain_color(glow, 1.15)
	var live_ok := true
	for k in 2:
		live_ok = live_ok and c.cable_sag[k] == 0.0 and absf(c.link_exposed[k] - (c.link_span[k] - TowLink.BARREL)) < 1e-4 and c.link_exposed[k] > 6.0
	_check("%s: the links are rigid (their middles %.2f / %.2f m off the line) and telescope (2 m closed up draws the rod in %.2f m, 0.2 m of stretch draws it out %.2f m; live, %.2f / %.2f m of rod showing on spans of %.2f / %.2f m) and colour with strain (glow at 0.3, amber at 0.8 %s, red at 1.15 %s)" % [
		label, c.cable_sag[0], c.cable_sag[1], closed, stretched, c.link_exposed[0], c.link_exposed[1], c.link_span[0], c.link_span[1], amber.to_html(false), red.to_html(false)],
		absf(closed - 2.0) < 1e-4 and absf(stretched - 0.2) < 1e-4 and live_ok and CMs.strain_color(glow, 0.3) == glow and amber.r > 0.85 and amber.b < 0.3 and red.g < 0.2)
	var eyes: Array[Vector3] = []
	var pod_up: Vector3
	if c.pod_frame:
		for n in ["hardpoint_l", "hardpoint_r"]:
			eyes.append((c.pod_frame.get_node(n) as Node3D).transform.origin)
		eyes = [c.pod_frame.transform * eyes[0], c.pod_frame.transform * eyes[1]]
		# (the pod's own up: in the headset it stands pitched on the rig, under a pilot whose view stays level)
		pod_up = (c.pod_frame.transform.basis * c.pod_frame_pose.basis).y.normalized()
	else:
		eyes = [c.pod.transform * Vector3(-0.18, c.POD_EYE_H, -2.1), c.pod.transform * Vector3(0.18, c.POD_EYE_H, -2.1)]
		pod_up = c.pod.transform.basis.y.normalized()
	# jointed: each swivel stands on its post along the pod's own up (banked over with it), each yoke's
	# pin lies along its engine's, and both have turned to the link (tests/test_tow_links.gd has the rest)
	var worst_post := 0.0
	var worst_lug := 0.0
	var turned := 0.0
	var all_shown := true
	for k in 2:
		var parts: Array = c.link_parts[k]
		for part in parts:
			all_shown = all_shown and (part as Node3D).visible
		worst_post = maxf(worst_post, maxf((parts[0] as Node3D).transform.origin.distance_to(c.cable_ends[k][1]), 1.0 - (parts[0] as Node3D).transform.basis.y.dot(pod_up)))
		worst_lug = maxf(worst_lug, maxf((parts[3] as Node3D).transform.origin.distance_to(c.cable_ends[k][0]), 1.0 - absf((parts[3] as Node3D).transform.basis.x.dot(c.engines[k].transform.basis.x.normalized()))))
		turned = maxf(turned, maxf(absf(c.link_angles[k][0]), absf(c.link_angles[k][3])))
	_check("%s: the links are jointed: each swivel on its post along the pod's up (worst %.4f), each yoke on its engine's lug pin (worst %.4f), turned to their links (up to %.0f deg in this turn)" % [label, worst_post, worst_lug, rad_to_deg(turned)],
		all_shown and worst_post < 1e-3 and worst_lug < 1e-3 and turned > deg_to_rad(5.0))
	var worst_pod := 0.0
	var worst_eng := 0.0
	var both := {}
	for k in 2:
		var ends: Array = c.cable_ends[k]
		var eng_eye: Vector3 = c.engines[k].transform * c.ENGINE_EYE
		var e0: float = (ends[0] - eng_eye).length()
		var e1: float = (ends[1] - eng_eye).length()
		var pod_end: Vector3 = ends[1] if e0 < e1 else ends[0]
		worst_eng = maxf(worst_eng, minf(e0, e1))
		var d0 := (pod_end - eyes[0]).length()
		var d1 := (pod_end - eyes[1]).length()
		worst_pod = maxf(worst_pod, minf(d0, d1))
		both[0 if d0 < d1 else 1] = true
	_check("%s: each cable starts on its engine's eye (worst %.3f m)" % [label, worst_eng], worst_eng <= TOL)
	_check("%s: and ends on a nose hardpoint, one cable per eye (worst %.3f m)" % [label, worst_pod], worst_pod <= TOL and both.size() == 2)
	if c.pod_frame:
		_fittings_clear(c.pod_frame)


## VR: every fitting in the cockpit (seat, levers, instrument panel, ...) clears the hull it
## sits in: real mesh vertices and label corners, checked in the pod's frame.
func _fittings_clear(rig: Node3D) -> void:
	var CM := preload("res://view/craft_model.gd")
	var hull := rig.get_node("shell/PodHull") as MeshInstance3D
	var to_hull := hull.global_transform.affine_inverse()
	var n := 0
	var parts := {}
	var example := ""
	# Lights also inherit VisualInstance3D. Their influence volumes are not fittings.
	for node in rig.find_children("*", "GeometryInstance3D", true, false):
		var vi := node as GeometryInstance3D
		if vi == hull:
			continue   # the hull itself
		if vi.find_parent("*") is XROrigin3D or _under(vi, "XROrigin3D"):
			continue   # hands and the fade sphere ride the player, not the pod
		if vi.is_in_group("exterior"):
			continue   # the windscreen sits on the lip and the forcefield wraps the hull by design (tests/test_canopy.gd)
		var pts := PackedVector3Array()
		if vi is MeshInstance3D:
			var mesh: Mesh = (vi as MeshInstance3D).mesh
			pts = (mesh as PrimitiveMesh).get_mesh_arrays()[Mesh.ARRAY_VERTEX] if mesh is PrimitiveMesh else mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		else:
			var box := vi.get_aabb()
			if box.size == Vector3.ZERO:
				continue
			for k in 8:
				pts.append(box.get_endpoint(k))
		var path := str(rig.get_path_to(vi))
		# (the rim light is fastened against the lip's underside, under the coaming's hem: it may lie
		# against the lip, and must not be in it. Everything else keeps a centimetre clear.)
		var margin := 0.0 if vi.is_in_group("under_the_lip") else 0.01
		# The fittings and the hull shudder together. Compare them in the hull frame.
		var local: Transform3D = to_hull * vi.global_transform
		for q in pts:
			var pod: Vector3 = local * q
			var why: String = CM.hull_clearance(pod, margin)
			n += 1
			if why != "":
				if not parts.has(path):      # (every part that clips, and where it first does: one example hid the others)
					example += "%s%s %s at pod (%.3f, %.3f, %.3f)" % ["" if example.is_empty() else "; ", path, why, pod.x, pod.y, pod.z]
				parts[path] = parts.get(path, 0) + 1
	_check("VR cockpit: every fitting clears the hull (%d points, %d parts clipping%s)" % [n, parts.size(), "" if parts.is_empty() else ": " + example],
		parts.is_empty() and n > 1000)


static func _under(node: Node, cls: String) -> bool:
	var p := node.get_parent()
	while p:
		if p.is_class(cls):
			return true
		p = p.get_parent()
	return false


func _check(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if ok:
		passed += 1
	else:
		fails += 1
