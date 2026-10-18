## Cable gate: both cables hook to real hardware at both ends, in a hard banked turn, in the
## flat view (the drawn pod's nose eyes) and in the VR cockpit (its own nose eyes, the pod
## being hidden). Prints CABLES PASS when every check passes.
## Run: Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_cables.gd -- --track=range --mute
extends SceneTree

const FlatScript := preload("res://view/craft_view.gd")
const VRScript := preload("res://vr/vr_cockpit.gd")
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


func _process(delta: float) -> bool:
	t += delta
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
	var good: bool = fails == 0 and passed == 11
	print("CABLES ", "PASS" if good else "FAIL (%d failed, %d passed)" % [fails, passed])
	quit(0 if good else 1)
	return true


func _measure(label: String) -> void:
	var c = v.craft
	var bank := rad_to_deg(c.bank[2])
	var peak := rad_to_deg(c.roll_rate_peak)
	_check("%s: banked %.0f deg in the turn, never rolling faster than %.1f deg/s (cap 55)" % [label, bank, peak],
		absf(bank) > 15.0 and peak <= 55.0 + 1e-6 and peak > 20.0)
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
	# flex and colour: a slack cable hangs by rope geometry, a taut one runs nearly straight;
	# strain turns its glow amber then red; the live sway stays sane
	var CMs = c.get_script()
	var sag_slack: float = CMs.cable_sag_for(14.0, 16.0)
	var sag_taut: float = CMs.cable_sag_for(16.2, 16.0)
	var glow := Color(0.25, 0.65, 1.0)
	var amber: Color = CMs.strain_color(glow, 0.8)
	var red: Color = CMs.strain_color(glow, 1.15)
	var live_ok: bool = c.cable_sag[0] <= 0.25 * 16.5 and c.cable_sag[1] <= 0.25 * 16.5
	_check("%s: cables flex (2 m of slack sags %.2f m, taut %.2f m; live sway %.2f / %.2f m) and colour with strain (glow at 0.3, amber at 0.8 %s, red at 1.15 %s)" % [
		label, sag_slack, sag_taut, c.cable_sag[0], c.cable_sag[1], amber.to_html(false), red.to_html(false)],
		sag_slack > 1.5 and sag_taut < 0.1 and live_ok and CMs.strain_color(glow, 0.3) == glow and amber.r > 0.85 and amber.b < 0.3 and red.g < 0.2)
	var eyes: Array[Vector3] = []
	if c.pod_frame:
		for n in ["hardpoint_l", "hardpoint_r"]:
			eyes.append((c.pod_frame.get_node(n) as Node3D).transform.origin)
		eyes = [c.pod_frame.transform * eyes[0], c.pod_frame.transform * eyes[1]]
	else:
		eyes = [c.pod.transform * Vector3(-0.18, -0.05, -2.1), c.pod.transform * Vector3(0.18, -0.05, -2.1)]
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
	var to_rig := rig.global_transform.affine_inverse()
	var n := 0
	var parts := {}
	var example := ""
	for node in rig.find_children("*", "VisualInstance3D", true, false):
		var vi := node as VisualInstance3D
		if vi is MeshInstance3D and (vi as MeshInstance3D).mesh == CM.pod_hull():
			continue   # the hull itself
		if vi.find_parent("*") is XROrigin3D or _under(vi, "XROrigin3D"):
			continue   # hands and the fade sphere ride the player, not the pod
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
		for q in pts:
			var pod: Vector3 = to_rig * (vi.global_transform * q) - Vector3(0, CM.POD_FRAME_UP, 0)
			var why: String = CM.hull_clearance(pod)
			n += 1
			if why != "":
				parts[path] = parts.get(path, 0) + 1
				example = "%s %s at pod (%.2f, %.2f, %.2f)" % [path, why, pod.x, pod.y, pod.z]
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
