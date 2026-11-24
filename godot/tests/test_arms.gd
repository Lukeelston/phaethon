## The arms (view/arms/<craft>_arms.gd): the small contract every craft's weapon hardware fills, which Codex's models
## fill later (docs/superpowers/specs/2026-11-24-raids-art-brief-codex.md), the stand-ins for the Phaethon (a cannon
## in the nose of each engine) and the Talon (a gun at each wing root), and the weapon table (sim/pilot_craft.gd
## WEAPONS, weapon_of, TRAITS[..].weapon).
##   contract     the Phaethon's and the Talon's arms have build, set_deploy, muzzles and heat; where they ride
##   stowed       at t = 0 no barrel's box pokes out of its housing's, and nothing of them is drawn
##   deployed     set_deploy(1): two muzzles, each -Z within 2 degrees of the craft's forward, each barrel run out
##                0.6 m, and nothing of the craft ahead of either muzzle
##   table        weapon_of for all seven; the rows (the Basilisk's repeats its power's fireS/coolS); {} for the rest
##   Basilisk     its turret built exactly as turret.gd builds it, fired through its own mount, and no arms
##   others       the Shrike carries none
##   VR seat      the Talon's arms ride on the hull the seat sees; the Phaethon's stay on its engines; stowed, none
##                drawn; with the GUN switch never armed, no fire control made
## (The barrels and housings are found by name: a "Barrel" and its sibling "Housing" under one gun node.)
## --headless --xr-mode off --audio-driver Dummy -s res://tests/test_arms.gd -- --mute
## Prints ARMS PASS.
extends SceneTree

const Pilot := preload("res://sim/pilot_craft.gd")
const View := preload("res://view/craft_view.gd")
const Seat := preload("res://vr/vr_cockpit.gd")
const Livery := preload("res://view/livery.gd")
const TurretScript := preload("res://view/turret.gd")
const PREFS := "user://vr_prefs.json"
const IDLE := {"thrL": 0.0, "thrR": 0.0, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": true}
const ROWS := {
	"phaethon": {"rate": 10.0, "boltV": 1300.0, "hits": 1, "reach": 2600.0, "fireS": 5.0, "coolS": 3.0, "assistDeg": 3.0},
	"talon": {"rate": 18.0, "boltV": 1400.0, "hits": 1, "reach": 2200.0, "fireS": 4.0, "coolS": 2.5, "assistDeg": 3.0},
}
const RUN := 0.6      # the stand-ins' barrels run this far out
var failures := 0
var checks := 0


func _initialize() -> void:
	_run.call_deferred()


func check(label: String, ok: bool) -> void:
	checks += 1
	failures += int(not ok)
	print(("  ok   " if ok else "  FAIL ") + label)


func _run() -> void:
	var prefs_existed := FileAccess.file_exists(PREFS)
	var prefs := FileAccess.get_file_as_bytes(PREFS) if prefs_existed else PackedByteArray()
	Livery.pinned = true
	Livery.current = Livery.FACTORY
	View.track_override = "range"
	View.job_override = "none"
	print("table")
	check_weapon_rows()
	for id: String in [Pilot.STANDARD, Pilot.TALON]:
		print(id)
		var game = await _flat(id)
		check_contract(id, game.craft)
		check_stowed(id, game.craft)
		check_deployed(id, game.craft)
		game.free()
		await process_frame
	print("basilisk")
	await check_basilisk_unchanged()
	print("shrike")
	await check_no_arms(Pilot.SHRIKE)
	print("VR seat")
	await check_vr_seat()
	View.vehicle_override = ""
	if prefs_existed:
		var file := FileAccess.open(PREFS, FileAccess.WRITE)
		file.store_buffer(prefs)
		file.close()
	elif FileAccess.file_exists(PREFS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	print("ARMS %s (%d checks, %d failed)" % ["PASS" if failures == 0 and checks >= 20 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)


## A flat-view flight in `id` on the range, its craft placed as the sim has it.
func _flat(id: String):
	View.vehicle_override = id
	var game = View.new()
	root.add_child(game)
	game.set_process(false)
	await process_frame
	game._follow_origin()
	for i in 3:
		game.craft.sync(game.sim, IDLE, 1.0 / 60.0)
	return game


## Each gun's [barrel, its housing] under `top`.
static func _guns(top: Node) -> Array:
	var out := []
	for barrel: MeshInstance3D in top.find_children("Barrel*", "MeshInstance3D", true, false):
		out.append([barrel, barrel.get_parent().get_node_or_null("Housing")])
	return out


## Each barrel whose box pokes out of its housing's (in the housing's frame; a missing housing counts).
static func _poking(guns: Array) -> Array:
	var out := []
	for gun: Array in guns:
		var barrel: MeshInstance3D = gun[0]
		var housing: MeshInstance3D = gun[1]
		if housing == null:
			out.append("%s has no housing" % barrel.get_path())
			continue
		var into: Transform3D = housing.global_transform.affine_inverse() * barrel.global_transform
		var box: AABB = into * barrel.mesh.get_aabb()
		if not housing.mesh.get_aabb().grow(0.0005).encloses(box):
			out.append("%s: %s outside %s" % [barrel.get_parent().name, box, housing.mesh.get_aabb()])
	return out


## Is anything of the guns under `top` drawn?
static func _drawn(top: Node) -> Array:
	var shown := []
	for gun: Array in _guns(top):
		for part: MeshInstance3D in (gun[0] as Node).get_parent().find_children("*", "MeshInstance3D", true, false):
			if part.is_visible_in_tree():
				shown.append(part.name)
	return shown


func check_weapon_rows() -> void:
	var want := {"phaethon": "cannons", "talon": "wing_guns", "shrike": "", "orrery": "", "kiln": "", "vesper": "", "basilisk": "turret"}
	var got := {}
	for id: String in Pilot.ORDER:
		got[id] = Pilot.weapon_of(id)
	check("weapon_of is right for all seven: %s" % [got], Pilot.ORDER.size() == 7 and got == want)
	check("WEAPONS names the three that carry one", Pilot.WEAPONS == {Pilot.STANDARD: "cannons", Pilot.TALON: "wing_guns", Pilot.BASILISK: "turret"})
	var empty := []
	for id: String in [Pilot.SHRIKE, Pilot.ORRERY, Pilot.KILN, Pilot.VESPER]:
		var row = Pilot.traits(id).get("weapon")
		if row is Dictionary and (row as Dictionary).is_empty():
			empty.append(id)
	check("traits(id).weapon is {} for shrike, orrery, kiln and vesper (%s)" % [empty], empty.size() == 4)
	for id: String in ROWS:
		var row = Pilot.traits(id).get("weapon")
		check("%s's weapon row is %s" % [id, row], row is Dictionary and row == ROWS[id])
	var bas := Pilot.traits(Pilot.BASILISK)
	check("the Basilisk's weapon row repeats its power's fireS/coolS (%s)" % [bas.get("weapon")],
		bas.get("weapon") is Dictionary and bas.weapon == {"fireS": bas.power.fireS, "coolS": bas.power.coolS})
	var copy: Dictionary = Pilot.traits(Pilot.STANDARD).weapon
	copy.rate = 99.0
	check("traits() hands out a copy of the weapon row, as of the power", Pilot.traits(Pilot.STANDARD).weapon.rate == 10.0)


func check_contract(id: String, craft) -> void:
	var arms = craft.arms
	var has := []
	if arms != null:
		for member: String in ["build", "set_deploy", "muzzles"]:
			if arms.has_method(member):
				has.append(member)
		if "heat" in arms and typeof(arms.heat) == TYPE_FLOAT:
			has.append("heat")
	check("%s carries arms with the contract's four members (%s)" % [id, has], has.size() == 4)
	if arms == null:
		return
	var guns := _guns(craft)
	if id == Pilot.STANDARD:
		var on := []
		for eng: Node3D in craft.engines:
			on.append(_guns(eng).size())
		check("one cannon in the nose of each engine (%s)" % [on], on == [1, 1] and guns.size() == 2)
	else:
		check("two guns, on the pod (%d)" % guns.size(), arms.get_parent() == craft.pod and _guns(arms).size() == 2 and guns.size() == 2)
	arms.heat = 0.5
	var half: float = arms.heat
	arms.heat = 0.0
	var cold := _glow(guns)
	arms.heat = 1.0
	var hot := _glow(guns)
	arms.heat = 0.0
	check("its heat reads back (%.2f) and the barrels' glow follows it (%.2f cold, %.2f hot)" % [half, cold, hot], is_equal_approx(half, 0.5) and hot > cold + 1.0)


## The barrels' glow: their material's emission, energy times brightness.
static func _glow(guns: Array) -> float:
	var most := 0.0
	for gun: Array in guns:
		var mat := (gun[0] as MeshInstance3D).get_active_material(0) as StandardMaterial3D
		if mat and mat.emission_enabled:
			most = maxf(most, mat.emission_energy_multiplier * mat.emission.get_luminance())
	return most * 10.0


func check_stowed(id: String, craft) -> void:
	if craft.arms == null:
		check("%s stowed: no arms to stow" % id, false)
		return
	craft.arms.set_deploy(0.0)
	var guns := _guns(craft)
	var poking := _poking(guns)
	check("%s stowed: %d barrels, none poking out of its housing %s" % [id, guns.size(), poking], guns.size() == 2 and poking.is_empty())
	var shown := _drawn(craft)
	check("%s stowed: nothing of the arms is drawn (%s)" % [id, shown], shown.is_empty())


func check_deployed(id: String, craft) -> void:
	if craft.arms == null:
		check("%s deployed: no arms to deploy" % id, false)
		return
	var stowed: Array = craft.arms.muzzles()
	craft.arms.set_deploy(1.0)
	var out: Array = craft.arms.muzzles()
	var forward: Vector3 = -craft.pod.global_basis.z.normalized()
	var worst := 0.0
	var runs := []
	for i in out.size():
		var m: Transform3D = out[i]
		worst = maxf(worst, rad_to_deg((-m.basis.z).normalized().angle_to(forward)))
		if i < stowed.size():
			runs.append(snappedf(((m.origin - (stowed[i] as Transform3D).origin)).dot(forward), 0.001))
	check("%s deployed: %d muzzles, each firing within 2 degrees of the craft's forward (the worst %.3f deg)" % [id, out.size(), worst], out.size() == 2 and worst < 2.0)
	check("%s deployed: each barrel run %s m out (%.1f)" % [id, runs, RUN], runs.size() == 2 and runs.all(func(r: float) -> bool: return absf(r - RUN) < 0.005))
	var shown := _drawn(craft)
	check("%s deployed: its barrels and housings are drawn (%s)" % [id, shown], shown.count("Barrel") == 2 and shown.count("Housing") == 2)
	check("%s deployed: each barrel stands out of its housing (%d of 2)" % [id, _poking(_guns(craft)).size()], _poking(_guns(craft)).size() == 2)
	# Nothing of the craft ahead of a muzzle: a ray forward from each meets neither the pod's hull nor an engine's fairing.
	var meshes := [craft.pod]
	for eng: Node3D in craft.engines:
		for part: MeshInstance3D in eng.get_children().filter(func(n): return n is MeshInstance3D and String(n.name).ends_with("Fairing")):
			meshes.append(part)
	var blocked := []
	for m: Transform3D in out:
		for part: MeshInstance3D in meshes:
			var into := part.global_transform.affine_inverse()
			var hit := part.mesh.generate_triangle_mesh().intersect_ray(into * m.origin, (into.basis * -m.basis.z).normalized())
			if not hit.is_empty():
				blocked.append("%s at %s" % [part.name, hit.position])
	check("%s deployed: nothing of the craft stands ahead of either muzzle (%s)" % [id, blocked], out.size() == 2 and blocked.is_empty())
	craft.arms.set_deploy(0.0)


## A node's parts, for comparing two builds: each descendant's path, transform, and its mesh's box and surfaces.
static func _signature(top: Node) -> Array:
	var out := []
	for node: Node in top.find_children("*", "", true, false):
		var row := [String(top.get_path_to(node)), node.get_class()]
		if node is Node3D:
			row.append((node as Node3D).transform)
		if node is MeshInstance3D and (node as MeshInstance3D).mesh:
			row.append((node as MeshInstance3D).mesh.get_aabb())
			row.append((node as MeshInstance3D).mesh.get_surface_count())
		out.append(row)
	return out


func check_basilisk_unchanged() -> void:
	var game = await _flat(Pilot.BASILISK)
	var craft = game.craft
	var turret = craft.turret
	var fresh := TurretScript.new()
	fresh.build(craft.fleet)
	var same: bool = turret != null and _signature(turret) == _signature(fresh)
	check("the Basilisk's turret is built exactly as turret.gd builds it (%d parts), on its pod, stowed" % (_signature(fresh).size()),
		same and turret.get_parent() == craft.pod and turret.t == 0.0 and turret.hatch.rotation.z == 0.0)
	check("... and is fired through its own mount", craft.weapon != null and craft.weapon.get("turret") == turret)
	check("... and the Basilisk carries no arms", craft.get("arms") == null and _guns(craft).is_empty())
	fresh.free()
	game.free()
	await process_frame


func check_no_arms(id: String) -> void:
	var game = await _flat(id)
	check("the %s carries no arms (its weapon is not built yet), nor a turret" % id, game.craft.get("arms") == null and _guns(game.craft).is_empty() and game.craft.turret == null)
	game.free()
	await process_frame


func check_vr_seat() -> void:
	Seat._camera_loaded = true
	Seat.camera = "cockpit"
	Seat._startup_loaded = true
	Seat.cold_start = false
	Seat._nose_loaded = true
	Seat._slide_loaded = true
	Seat._map_loaded = true
	Seat._school_loaded = true
	for id: String in [Pilot.TALON, Pilot.STANDARD]:
		Seat.vehicle_override = id
		var game = Seat.new()
		root.add_child(game)
		game.set_process(false)
		for i in 6:
			game._process(1.0 / 120.0)
		var arms = game.craft.arms
		var hull := game.shell.get_node("PodHull") as MeshInstance3D
		if id == Pilot.TALON:
			check("in the VR seat the Talon's arms ride on the hull the seat sees", arms != null and arms.get_parent() == hull and _guns(hull).size() == 2)
			if arms != null:      # (for the fire control: the hull stands nose-down under the pilot, vr_cockpit.gd POD_PITCH, and the guns with it)
				arms.set_deploy(1.0)
				var bore := Vector3.ZERO
				for m: Transform3D in arms.muzzles():
					bore += -m.basis.z
				var rig: Basis = game.rig.global_basis.orthonormalized()
				print("  (out, the Talon's bore in the VR seat stands %.2f deg %s the rig's level forward)" % [rad_to_deg(bore.normalized().angle_to(-rig.z)),
					"below" if bore.dot(rig.y) < 0.0 else "above"])
				arms.set_deploy(0.0)
		else:
			var on := []
			for eng: Node3D in game.craft.engines:
				on.append(_guns(eng).size())
			check("in the VR seat the Phaethon's cannons stay on its engines (%s), none on the hull" % [on], arms != null and on == [1, 1] and _guns(hull).is_empty())
		check("... stowed, nothing of them is drawn (%s)" % [_drawn(game)], _drawn(game).is_empty())
		check("... and with the GUN switch never armed no fire control is made (%s)" % [game.gunnery], game.gunnery == null)
		Seat.vehicle_override = ""
		game.free()
		await process_frame
