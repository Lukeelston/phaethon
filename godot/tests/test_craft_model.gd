## Craft model gate: each engine's air-brake flaps answer to that engine's brake alone, open
## outward, and close again; the pod's flaps follow the pod brake (the lesser of the two). And
## the nose is an open cage you can see the track through: no skin between the cage's ends,
## tubes on both cut edges.
## Prints CRAFT MODEL PASS when every check passes.
## Run: Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_craft_model.gd -- --mute
extends SceneTree

const ViewScript := preload("res://view/craft_view.gd")
# [label, brkL, brkR, expected left flaps, right flaps, pod flaps]
const LEGS := [["no brake", 0.0, 0.0, 0.0, 0.0, 0.0], ["left trigger", 1.0, 0.0, 1.0, 0.0, 0.0],
	["right trigger", 0.0, 1.0, 0.0, 1.0, 0.0], ["half left", 0.5, 0.0, 0.5, 0.0, 0.0],
	["both", 1.0, 1.0, 1.0, 1.0, 1.0], ["released", 0.0, 0.0, 0.0, 0.0, 0.0]]
const LEG_S := 0.4

var v
var t := 0.0
var leg := -1
var fails := 0
var passed := 0   # a script error aborts a check without failing it, so PASS needs every one


func _initialize() -> void:
	v = ViewScript.new()
	v.cruise = 0.3   # hold the levers; the test sets the brakes
	root.add_child(v)


func _process(delta: float) -> bool:
	t += delta
	var k := mini(int(t / LEG_S), LEGS.size())
	if k != leg:
		if leg >= 0:
			_check_leg(LEGS[leg])
		leg = k
		if leg >= LEGS.size():
			fails += _check_cage()
			var good := fails == 0 and passed == LEGS.size() + 1
			print("CRAFT MODEL ", "PASS" if good else "FAIL (%d failed, %d of %d ran)" % [fails, passed + fails, LEGS.size()])
			quit(0 if good else 1)
			return true
	var L: Array = LEGS[leg]
	v.inp = {"thrL": 0.3, "thrR": 0.3, "brkL": L[1], "brkR": L[2], "repair": false, "reignite": true}
	return false


func _check_leg(L: Array) -> void:
	var c = v.craft
	var ok_l := absf(c.flap_open[0] - L[3]) < 0.02
	var ok_r := absf(c.flap_open[1] - L[4]) < 0.02
	var ok_p := absf(c.pod_flap_open - L[5]) < 0.02
	# geometry: an open flap's trailing edge stands off the engine axis; a shut one lies flat
	var spread := []
	for e in 2:
		var eng: Node3D = c.engines[e]
		var far := 0.0
		for hinge in c.flaps[e]:
			var tip: Vector3 = (hinge as Node3D).global_transform * Vector3(0, 0, 1.3)
			var local := eng.global_transform.affine_inverse() * tip
			far = maxf(far, Vector2(local.x, local.y).length())
		spread.append(far)
	var want := [0.83 + 1.2 * sin(deg_to_rad(68.0) * L[3]), 0.83 + 1.2 * sin(deg_to_rad(68.0) * L[4])]
	var ok_g := absf(spread[0] - want[0]) < 0.12 and absf(spread[1] - want[1]) < 0.12
	fails += _check("%-13s L flaps %.2f (want %.1f)  R flaps %.2f (want %.1f)  pod %.2f (want %.1f)  tip radius L %.2f R %.2f m" % [
		L[0], c.flap_open[0], L[3], c.flap_open[1], L[4], c.pod_flap_open, L[5], spread[0], spread[1]], ok_l and ok_r and ok_p and ok_g)


func _check_cage() -> int:
	var CM = v.craft.get_script()
	var mesh: ArrayMesh = CM.pod_hull()
	var skin_in_cage := 0
	for surf in 2:   # outer skin, inner trim
		var a := mesh.surface_get_arrays(surf)
		var vx: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
		for k in range(0, idx.size(), 3):
			var cz := (vx[idx[k]].z + vx[idx[k + 1]].z + vx[idx[k + 2]].z) / 3.0
			if cz > CM.CAGE_Z1 + 0.06 and cz < CM.CAGE_Z0 - 0.06:
				skin_in_cage += 1
	var cage: PackedVector3Array = mesh.surface_get_arrays(4)[Mesh.ARRAY_VERTEX]
	var zmin := INF
	var zmax := -INF
	for p in cage:
		zmin = minf(zmin, p.z)
		zmax = maxf(zmax, p.z)
	var ok := skin_in_cage == 0 and cage.size() > 1000 and absf(zmin - CM.CAGE_Z1) < 0.08 and absf(zmax - CM.CAGE_Z0) < 0.08
	return _check("nose cage: %d skin triangles between z %.2f and %.2f, %d cage vertices spanning %.2f..%.2f" % [
		skin_in_cage, CM.CAGE_Z1, CM.CAGE_Z0, cage.size(), zmin, zmax], ok)


func _check(label: String, ok: bool) -> int:
	print(("  ok   " if ok else "  FAIL ") + label)
	passed += 1 if ok else 0
	return 0 if ok else 1
