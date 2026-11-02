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
			fails += _check_slab()
			fails += _check_plume()
			fails += _check_bank()
			var good := fails == 0 and passed == LEGS.size() + 4
			print("CRAFT MODEL ", "PASS" if good else "FAIL (%d failed, %d of %d ran)" % [fails, passed + fails, LEGS.size() + 4])
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
	# geometry: an open flap's trailing edge lifts off the slab's top (or bottom) skin; a shut one
	# lies flat on it
	var spread := []
	for e in 2:
		var eng: Node3D = c.engines[e]
		var far := 0.0
		for hinge in c.flaps[e]:
			var tip: Vector3 = (hinge as Node3D).global_transform * Vector3(0, 0, 1.3)
			var local := eng.global_transform.affine_inverse() * tip
			far = maxf(far, absf(local.y))
		spread.append(far)
	var skin: float = c.ENG_H / 2.0 + 0.01
	var want := [skin + 1.3 * sin(deg_to_rad(68.0) * L[3]), skin + 1.3 * sin(deg_to_rad(68.0) * L[4])]
	var ok_g := absf(spread[0] - want[0]) < 0.12 and absf(spread[1] - want[1]) < 0.12
	fails += _check("%-13s L flaps %.2f (want %.1f)  R flaps %.2f (want %.1f)  pod %.2f (want %.1f)  tip radius L %.2f R %.2f m" % [
		L[0], c.flap_open[0], L[3], c.flap_open[1], L[4], c.pod_flap_open, L[5], spread[0], spread[1]], ok_l and ok_r and ok_p and ok_g)


## The engines are flat rounded slabs that keep every detail of the old cylinders and add
## vectoring vanes, lights, a strobe, twin fans and a ring-emitter binder.
func _check_slab() -> int:
	var c = v.craft
	var eng: Node3D = c.engines[0]
	var body: MeshInstance3D = eng.get_child(0)
	# a slice through the nacelle, clear of the fin and stabiliser: how wide and how tall
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for vtx in (body.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
		if vtx.z > -1.9 and vtx.z < -1.7:
			lo = Vector2(minf(lo.x, vtx.x), minf(lo.y, vtx.y))
			hi = Vector2(maxf(hi.x, vtx.x), maxf(hi.y, vtx.y))
	var box := AABB(Vector3(lo.x, lo.y, 0), Vector3(hi.x - lo.x, hi.y - lo.y, 0))
	var flat: bool = box.size.x > 2.0 * box.size.y and absf(box.size.x - 2.4) < 0.2
	var kept: bool = c.rotors[0].size() == 2 and c.flaps[0].size() == 4 and c.hot_mats.size() == 2 		and c.glow_mats.size() == 2 and c.flames.size() == 2
	var added: bool = c.vanes[0].size() == 3 and c.strobes.size() == 2 and c.binder_mats.size() == 2
	# the front speed brakes: two petals an engine, out with the sim's e.front, both outward
	v.sim.eL.front = 1.0
	v.sim.eR.front = 0.0
	for i in 30:
		c.sync(v.sim, {"thrL": 0.0, "thrR": 0.0, "brkL": 1.0, "brkR": 0.0}, 1.0 / 60.0)
	var fl: Node3D = c.front_flaps[0][0]
	var fr: Node3D = c.front_flaps[0][1]
	var tip_l: Vector3 = fl.transform * Vector3(0.0, 0.0, 1.0)
	var tip_r: Vector3 = fr.transform * Vector3(0.0, 0.0, 1.0)
	var fronts: bool = c.front_flaps[0].size() == 2 and c.front_flaps[1].size() == 2 and absf(c.front_open[0] - 1.0) < 0.01 and c.front_open[1] < 0.01 \
		and tip_l.x < fl.position.x - 0.5 and tip_r.x > fr.position.x + 0.5
	print("  front speed brakes: left engine %.2f open (its petals' tails out to x %.2f / %.2f), right %.2f" % [c.front_open[0], tip_l.x, tip_r.x, c.front_open[1]])
	v.sim.eL.front = 0.0
	added = added and fronts
	# the vanes follow a steering split (left engine harder: a right turn: trailing edges right)
	v.sim.eL.thrust = 0.9
	v.sim.eR.thrust = 0.2
	for i in 60:
		c.sync(v.sim, {"thrL": 0.9, "thrR": 0.2, "brkL": 0.0, "brkR": 0.0}, 1.0 / 60.0)
	var swing: float = c.vane_angle
	var flashes := 0
	for i in 150:   # 1.25 s of strobe
		c.sync(v.sim, {"thrL": 0.3, "thrR": 0.3, "brkL": 0.0, "brkR": 0.0}, 1.0 / 120.0)
		OS.delay_msec(8)
		flashes += int(c.strobes[0].visible)
	return _check("engines are flat slabs (%.2f wide x %.2f tall through the nacelle), all the old detail kept, plus 3 vectoring vanes (%.2f rad on a right turn), strobes (%d lit frames in 1.25 s), ring-emitter binder" % [
		box.size.x, box.size.y, swing, flashes], flat and kept and added and swing > 0.2 and flashes > 0 and flashes < 60)


func _check_cage() -> int:
	var CM = v.craft.get_script()
	var mesh: ArrayMesh = CM.pod_hull()
	var skin_in_cage := 0
	for surf in [0, 1, 5]:   # outer skin, inner trim, paint
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


## The exhaust plume (view/flame.gdshader on two cones per engine, plus a nozzle light): on dry
## thrust a short faint plume and no light; on the burner the shader's burner share eases up,
## the plume stretches long and the nozzle light comes on; a flamed-out engine shows nothing.
func _check_plume() -> int:
	var c = v.craft
	var sim = v.sim
	var wired := true
	for k in 2:
		wired = wired and c.flame_mats[k].size() == 2 and c.nozzle_lights.size() == 2
		for m in c.flame_mats[k]:
			wired = wired and m is ShaderMaterial and (m as ShaderMaterial).shader.resource_path == "res://view/flame.gdshader"
	var probe := func(mode: String) -> Array:
		sim.mode = mode
		sim.eL.thrust = 0.8
		sim.eR.thrust = 0.8
		for i in 90:   # 1.5 s: the burner share eases over ~0.2 s
			c.sync(sim, {"thrL": 0.8, "thrR": 0.8, "brkL": 0.0, "brkR": 0.0}, 1.0 / 60.0)
		var cones: Node3D = c.flames[0].get_node("cones")
		return [float((c.flame_mats[0][0] as ShaderMaterial).get_shader_parameter("burner")), cones.transform.basis.get_scale().y,
			(c.nozzle_lights[0] as OmniLight3D).light_energy, c.flames[0].visible]
	var dry: Array = probe.call("normal")
	var hot: Array = probe.call("burner")
	sim.eL.flameout = true
	var out: Array = probe.call("normal")
	sim.eL.flameout = false
	sim.mode = "normal"
	return _check("plume: shader on both cones of both engines; dry burner share %.2f, %.1f m long, light %.1f; burner share %.2f, %.1f m long, light %.1f; flamed out: plume %s, light %.1f" % [
		dry[0], dry[1], dry[2], hot[0], hot[1], hot[2], "shown" if out[3] else "hidden", out[2]],
		wired and dry[0] < 0.05 and dry[2] == 0.0 and hot[0] > 0.95 and hot[1] > 2.0 * dry[1] and hot[2] > 1.0 and not out[3] and out[2] == 0.0)


## The lean into turns (CraftModel.ease_bank), at 72 Hz with a hard 15 g turn held 3 s, then
## let go. Luke: 55 deg/s both ways felt "artificially slow, especially returning to horizontal";
## the unrated original felt "sickeningly fast". Rolling in still builds (not a snap), coming back
## to level is quicker than rolling in, and neither exceeds its cap.
func _check_bank() -> int:
	var CM = v.craft.get_script()
	var dt := 1.0 / 72.0
	var b := 0.0
	var l := 0.0
	var steady: float = CM.BANK_MAX * tanh(15.0 / CM.BANK_G)
	var t_in := -1.0
	var pk_in := 0.0
	for i in int(3.0 / dt):
		var was := b
		var e: Array = CM.ease_bank(b, l, 15.0, dt)
		b = e[0]
		l = e[1]
		pk_in = maxf(pk_in, absf(b - was) / dt)
		if t_in < 0.0 and absf(b) >= 0.9 * absf(steady):
			t_in = (i + 1) * dt
	var t_out := -1.0
	var pk_out := 0.0
	for i in int(4.0 / dt):
		var was := b
		var e: Array = CM.ease_bank(b, l, 0.0, dt)
		b = e[0]
		l = e[1]
		pk_out = maxf(pk_out, absf(b - was) / dt)
		if t_out < 0.0 and absf(rad_to_deg(b)) < 3.0:
			t_out = (i + 1) * dt
	return _check("lean: a 15 g turn rolls in to %.0f deg in %.2f s (peak %.0f deg/s, cap %.0f) and back to level in %.2f s (peak %.0f, cap %.0f)" % [
		rad_to_deg(steady), t_in, rad_to_deg(pk_in), rad_to_deg(CM.BANK_RATE), t_out, rad_to_deg(pk_out), rad_to_deg(CM.BANK_RATE_OUT)],
		t_in > 0.5 and t_in < 0.85 and t_out > 0.3 and t_out < 0.75 and t_out < t_in
		and pk_in <= CM.BANK_RATE + 1e-6 and pk_out <= CM.BANK_RATE_OUT + 1e-6)
