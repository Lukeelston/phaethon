## The tow links (view/tow_link.gd; Luke: "more mechanical than loose swinging cable"): that their
## joints are real ones and their telescope's travel is the sim's span.
##   on paper   solve() at rest and with each body turned about each axis: every pin stays in its
##              hole (the swivel on its post, the barrel on the swivel's pitch pin, the yoke on the
##              lug's pin, the rod's fork on the yoke's yaw pin, the rod down the barrel's bore), and
##              the joint that should take each motion is the one that moves; the rod runs in and
##              out one for one with the span, and stays in the barrel; the boot at the barrel's
##              mouth gives and takes with it; the stencils read the right way up from their own
##              side; what both links and the bullring cost in triangles
##   flown      straight, a hard left, coasting: every pin in its hole on every frame, and the rod
##              showing follows the sim's own span; each boot stands as long as its telescope says;
##              then the sim closed up by hand, and the rods drawn in by what its spans closed (and
##              the boots folded solid); both links drawn in three kinds of material
## --headless --xr-mode off --audio-driver Dummy -s res://tests/test_tow_links.gd -- --track=range --mute
## Prints TOW LINKS PASS.
extends SceneTree

const FlatScript := preload("res://view/craft_view.gd")
const TowLink := preload("res://view/tow_link.gd")
const Model := preload("res://view/craft_model.gd")
const Kit := preload("res://view/mesh_kit.gd")
const CHECKS := 21
var v
var fails := 0
var passed := 0
var rows: Array = []      # [sim time, [sim span, drawn span, rod showing] per link]
var parts_ok := true
var worst_fit := 0.0
var closed: Array = []    # the rows before and after the sim is closed up by hand
var boot_fit := 0.0       # the worst a boot's drawn length was off what its telescope says
var boot_ok := true
var boot_run := [[INF, -INF], [INF, -INF]]   # how long each boot stood, least and most, over the flight


func _initialize() -> void:
	_on_paper()
	# (the flight is the Range's, whatever the command line says: the suite's runner passes no --track,
	# and on a Network road the hard left meets the wall at 2.8 s and throws an engine)
	FlatScript.track_override = "range"
	v = FlatScript.new()
	v.cruise = 0.5
	root.add_child(v)


func _check(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if ok:
		passed += 1
	else:
		fails += 1


## How far out of its hole the worst pin of a solved link is (m, or its lines' misalignment as a sine).
static func _fit(s: Dictionary, eye: Vector3, engine: Basis, post: Vector3, pod: Basis) -> float:
	var swivel: Transform3D = s.swivel
	var barrel: Transform3D = s.barrel
	var rod: Transform3D = s.rod
	var yoke: Transform3D = s.yoke
	var worst := 0.0
	worst = maxf(worst, swivel.origin.distance_to(post))                                             # the swivel is on its post ...
	worst = maxf(worst, swivel.basis.y.cross(pod.y.normalized()).length())                           # ... which stands along the pod's up
	worst = maxf(worst, barrel.origin.distance_to(swivel * Vector3(0, 0, TowLink.POD_PIN)))          # the barrel's eye is on the swivel's pitch pin ...
	worst = maxf(worst, barrel.basis.x.normalized().cross(swivel.basis.x).length())                  # ... and turns about that pin's own line
	worst = maxf(worst, yoke.origin.distance_to(eye))                                                # the yoke is on the lug's pin ...
	worst = maxf(worst, yoke.basis.x.cross(engine.x.normalized()).length())                          # ... which lies along the engine's x
	worst = maxf(worst, rod.origin.distance_to(yoke * Vector3(0, 0, TowLink.ENGINE_PIN)))            # the rod's fork is on the yoke's yaw pin ...
	worst = maxf(worst, rod.basis.y.normalized().cross(yoke.basis.y).length())                       # ... and turns about that pin's line
	var along := barrel.basis.z.normalized()
	worst = maxf(worst, along.cross(-rod.basis.z.normalized()).length())                             # the rod lies along the barrel ...
	var off := rod.origin - barrel.origin
	worst = maxf(worst, (off - along * off.dot(along)).length())                                     # ... and down the middle of its bore
	for part in [swivel, barrel, rod, yoke]:      # each part is a rigid thing, the right way out
		var b: Basis = (part as Transform3D).basis.orthonormalized()
		worst = maxf(worst, absf(b.determinant() - 1.0))
		worst = maxf(worst, absf((part as Transform3D).basis.x.dot((part as Transform3D).basis.y)))
	return worst


func _on_paper() -> void:
	# the craft at rest, as it is drawn: the pod's post 2 m over the lug, 16.4 m behind it, 2.8 m inboard
	var post := Vector3(-0.18, 1.25, -2.1)
	var eye := Vector3(-3.0, -0.75, -18.3)
	var rest: Dictionary = TowLink.solve(eye, Basis.IDENTITY, post, Basis.IDENTITY)
	_check("at rest every pin is in its hole (worst %.6f), the link %.2f m pin to pin: %.2f m of barrel, %.2f m of rod showing, %.2f m of it inside" % [
		_fit(rest, eye, Basis.IDENTITY, post, Basis.IDENTITY), rest.span, TowLink.BARREL, rest.exposed, rest.buried],
		_fit(rest, eye, Basis.IDENTITY, post, Basis.IDENTITY) < 1e-4 and absf(rest.span - (rest.pins[0] as Vector3).distance_to(rest.pins[1])) < 1e-5
		and absf(rest.exposed + TowLink.BARREL - rest.span) < 1e-5 and rest.buried > TowLink.BURIED and rest.buried < TowLink.BARREL - 0.2)
	var a0: Array = rest.angles
	_check("at rest the joints stand where the geometry puts them: the swivel turned %.1f deg outboard, the barrel pitched %.1f deg down, the yoke %.1f deg up, the rod %.1f deg inboard" % [
		rad_to_deg(a0[0]), rad_to_deg(a0[1]), rad_to_deg(a0[2]), rad_to_deg(a0[3])],
		a0[0] < deg_to_rad(-8.0) and a0[0] > deg_to_rad(-12.0) and a0[1] < deg_to_rad(-5.0) and a0[1] > deg_to_rad(-9.0) and a0[2] > deg_to_rad(5.0) and a0[2] < deg_to_rad(9.0) and absf(a0[3]) > deg_to_rad(8.0) and absf(a0[3]) < deg_to_rad(12.0))
	# each body turned 20 degrees about each of its axes, about its own fitting (so only the attitude changes)
	var turn := deg_to_rad(20.0)
	var cases := [
		["the pod yawed", Basis.IDENTITY, Basis(Vector3.UP, turn), 0],
		["the pod pitched", Basis.IDENTITY, Basis(Vector3.RIGHT, turn), 1],
		["the pod banked", Basis.IDENTITY, Basis(Vector3.BACK, turn), -1],
		["the engine pitched", Basis(Vector3.RIGHT, turn), Basis.IDENTITY, 2],
		["the engine yawed", Basis(Vector3.UP, turn), Basis.IDENTITY, 3],
		["the engine banked", Basis(Vector3.BACK, turn), Basis.IDENTITY, -1],
	]
	for case in cases:
		var engine: Basis = case[1]
		var pod: Basis = case[2]
		var s: Dictionary = TowLink.solve(eye, engine, post, pod)
		var fit := _fit(s, eye, engine, post, pod)
		var moved: Array = []
		for j in 4:
			moved.append(rad_to_deg(float(s.angles[j]) - float(a0[j])))
		var which: int = case[3]
		var ok := fit < 1e-4
		var note := ""
		if which >= 0:      # the joint that takes it moves by about the turn, the other joint at that end by much less
			var other: int = [1, 0, 3, 2][which]
			ok = ok and absf(absf(moved[which]) - 20.0) < 3.0 and absf(moved[other]) < 5.0
			note = ": its %s takes it" % ["swivel", "barrel's pitch pin", "yoke", "rod's yaw pin"][which]
		else:               # a bank is shared between that end's two pins, and something has to move
			var end := [0, 1] if case[0].begins_with("the pod") else [2, 3]
			ok = ok and absf(moved[end[0]]) + absf(moved[end[1]]) > 2.0
			note = ": both pins at that end share it"
		_check("%s 20 deg, every pin still in its hole (worst %.6f)%s (joints moved %.1f, %.1f, %.1f, %.1f deg)" % [case[0], fit, note, moved[0], moved[1], moved[2], moved[3]], ok)
	# everything at once, hard: the pod banked 55 deg and yawed, the engine yawed, banked and pitched, and thrown wide
	var wild_e := Basis(Vector3.UP, 0.6) * Basis(Vector3.RIGHT, -0.2) * Basis(Vector3.BACK, 0.5)
	var wild_p := Basis(Vector3.UP, -0.4) * Basis(Vector3.BACK, deg_to_rad(55.0))
	var wild: Dictionary = TowLink.solve(eye + Vector3(-5.0, 1.5, 2.0), wild_e, post, wild_p)
	_check("everything at once (the pod banked 55 deg and yawed, the engine yawed, banked, pitched and thrown wide): every pin still in its hole (worst %.6f)" % _fit(wild, eye + Vector3(-5.0, 1.5, 2.0), wild_e, post, wild_p),
		_fit(wild, eye + Vector3(-5.0, 1.5, 2.0), wild_e, post, wild_p) < 1e-4)
	# the telescope: the engine brought back along the link, and pulled away
	var line := ((rest.pins[1] as Vector3) - (rest.pins[0] as Vector3)).normalized()      # from the engine's end toward the pod's
	var seen := []
	var tele_ok := true
	for move in [-0.3, 0.2, 1.0, 2.0, 3.0]:      # m closer (negative: stretched)
		var s: Dictionary = TowLink.solve(eye + line * move, Basis.IDENTITY, post, Basis.IDENTITY)
		var drawn: float = float(rest.exposed) - float(s.exposed)
		seen.append("%.1f: %.3f" % [move, drawn])
		tele_ok = tele_ok and absf(drawn - move) < 0.01 and absf((s.rod as Transform3D).basis.z.length() - 1.0) < 1e-6 and absf((s.barrel as Transform3D).basis.z.length() - 1.0) < 1e-6 \
			and s.buried >= TowLink.BURIED - 1e-6 and s.buried <= TowLink.BARREL - 0.19 and _fit(s, eye + line * move, Basis.IDENTITY, post, Basis.IDENTITY) < 1e-4
	_check("the telescope: the engine brought toward the pod along the link draws the rod in one for one, nothing stretched or squashed, its piston always inside the barrel (m closer: m drawn in; %s)" % ", ".join(seen), tele_ok)
	# past what the parts can do, they are drawn short or long rather than apart
	var far: Dictionary = TowLink.solve(eye - line * 1.5, Basis.IDENTITY, post, Basis.IDENTITY)
	var near: Dictionary = TowLink.solve(eye + line * 6.0, Basis.IDENTITY, post, Basis.IDENTITY)
	var wreck: Dictionary = TowLink.solve(eye + line * 13.0, Basis.IDENTITY, post, Basis.IDENTITY)
	_check("past its travel a link is drawn whole: pulled 1.5 m past taut the rod still reaches %.2f m into the barrel (drawn %.0f%% long); closed up 6 m its piston stays %.2f m short of the barrel's back (drawn %.0f%%); a wreck's 3 m span shortens the barrel too (%.0f%%)" % [
		far.buried, (far.rod as Transform3D).basis.z.length() * 100.0, float(near.span) - (float(near.exposed) + float(near.buried)),
		(near.rod as Transform3D).basis.z.length() * 100.0, (wreck.barrel as Transform3D).basis.z.length() * 100.0],
		absf(far.buried - TowLink.BURIED) < 1e-6 and (far.rod as Transform3D).basis.z.length() > 1.0
		and float(near.exposed) + float(near.buried) <= float(near.span) - 0.19 and (near.rod as Transform3D).basis.z.length() < 1.0
		and (wreck.barrel as Transform3D).basis.z.length() < 0.7 and wreck.exposed > 0.0 and wreck.buried > 0.0)
	# another craft's links: the Shrike's are 12.5 m taut, and its rods are cut to suit
	var short_rod: float = TowLink.rod_for(12.5)
	var s_post := Vector3(-0.18, 1.25, -2.1)
	var s_eye := Vector3(-3.6, -0.75, -14.57)      # (its engines 7.2 m apart, 18.0 m ahead)
	var shrike: Dictionary = TowLink.solve(s_eye, Basis.IDENTITY, s_post, Basis.IDENTITY, short_rod)
	var s_line := ((shrike.pins[1] as Vector3) - (shrike.pins[0] as Vector3)).normalized()
	var s_closed: Dictionary = TowLink.solve(s_eye + s_line * 3.0, Basis.IDENTITY, s_post, Basis.IDENTITY, short_rod)
	_check("a 12.5 m link (the Shrike's): its rod is %.1f m, and taut %.2f m of it is inside the barrel, as the 16 m link's %.2f m is; closed up 3 m it is still drawn whole (%.0f%%), every pin in its hole (worst %.6f); its mesh ends at its piston (%.2f m)" % [
		short_rod, shrike.buried, rest.buried, (s_closed.rod as Transform3D).basis.z.length() * 100.0, _fit(s_closed, s_eye + s_line * 3.0, Basis.IDENTITY, s_post, Basis.IDENTITY), TowLink.rod_mesh(short_rod).get_aabb().end.z],
		absf(float(shrike.buried) - float(rest.buried)) < 0.25 and absf((s_closed.rod as Transform3D).basis.z.length() - 1.0) < 1e-6 and absf(float(shrike.exposed) - float(s_closed.exposed) - 3.0) < 0.01
		and _fit(s_closed, s_eye + s_line * 3.0, Basis.IDENTITY, s_post, Basis.IDENTITY) < 1e-4 and absf(TowLink.rod_mesh(short_rod).get_aabb().end.z - short_rod) < 1e-3 and TowLink.rod_mesh(short_rod) != TowLink.rod_mesh())
	# the boot at the barrel's mouth: one end on the gland's face, the other gripping the rod, so it gives
	# and takes with the telescope one for one until its folds are closed solid or pulled out straight
	var boot_rest: float = rest.boot
	var gave := []
	var boots_ok: bool = boot_rest > 0.45 and boot_rest < 0.75 and absf(boot_rest - (TowLink.BOOT_SEAT - float(rest.buried))) < 1e-6 \
		and absf(float(shrike.boot) - (TowLink.BOOT_SEAT - float(shrike.buried))) < 1e-6 and boot_rest - 0.3 > TowLink.BOOT_MIN and boot_rest + 0.2 < TowLink.BOOT_MAX
	for move in [-0.2, 0.1, 0.3]:      # m closer (negative: stretched)
		var s: Dictionary = TowLink.solve(eye + line * move, Basis.IDENTITY, post, Basis.IDENTITY)
		gave.append("%.1f: %.3f" % [move, boot_rest - float(s.boot)])
		boots_ok = boots_ok and absf(boot_rest - float(s.boot) - move) < 0.01 and absf(float(s.boot) - TowLink.boot_for(s.exposed)) < 1e-6
	var boot_mesh: ArrayMesh = TowLink.boot_mesh()
	var boot_box: AABB = boot_mesh.get_aabb()
	_check("the boot: taut it stands %.2f m (the Shrike's %.2f; %.1f as made), from the gland's face to its cuff on the rod %.1f m from the piston; it gives and takes with the telescope (m closer: m shorter; %s); closed up 6 m its folds are solid (%.2f m), pulled 1.5 m past taut they are straight (%.2f m); its mesh runs from the gland's face (%.3f) to its cuff (%.3f)" % [
		boot_rest, shrike.boot, TowLink.BOOT, TowLink.BOOT_SEAT, ", ".join(gave), near.boot, far.boot, boot_box.position.z, boot_box.end.z],
		boots_ok and float(near.boot) == TowLink.BOOT_MIN and float(far.boot) == TowLink.BOOT_MAX and float(wreck.boot) == TowLink.BOOT_MIN
		and absf(boot_box.position.z) < 1e-4 and absf(boot_box.end.z - TowLink.BOOT) < 1e-4 and boot_box.size.x < 0.14)
	# the parts themselves: made once, the lit ones in two surfaces, the barrel's paint in a third
	var meshes := {"swivel": TowLink.swivel_mesh(), "barrel": TowLink.barrel_mesh(), "rod": TowLink.rod_mesh(), "yoke": TowLink.yoke_mesh(), "boot": boot_mesh}
	var tris := 0
	var sizes := []
	for key in meshes:
		var n := _triangles(meshes[key])
		tris += n
		sizes.append("%s %d" % [key, n])
	var ring := _triangles(Kit.compound(Model._bullring()))
	var bb: AABB = (meshes.barrel as ArrayMesh).get_aabb()
	var rb: AABB = (meshes.rod as ArrayMesh).get_aabb()
	# (12,000 for both links and the bullring: what the headset's frame, 1.8 ms of GPU to spare, was given for them)
	_check("the parts: %s triangles (%d a link), the bullring %d: %d for both links and the bullring; the barrel runs to its gland at %.2f m, the rod to its piston at %.2f m; the lit parts are their own surface and the barrel's paint a third; made once and shared" % [
		", ".join(sizes), tris, ring, 2 * tris + ring, bb.end.z, rb.end.z],
		tris > 3000 and 2 * tris + ring < 12000 and absf(bb.end.z - TowLink.BARREL) < 1e-3 and absf(rb.end.z - TowLink.ROD) < 1e-3 and (meshes.barrel as ArrayMesh).get_surface_count() == 3
		and (meshes.rod as ArrayMesh).get_surface_count() == 2 and (meshes.swivel as ArrayMesh).get_surface_count() == 1 and (meshes.yoke as ArrayMesh).get_surface_count() == 1
		and boot_mesh.get_surface_count() == 1 and TowLink.barrel_mesh() == meshes.barrel)
	# the stencils: lettering along the barrel on both flanks, each the right way up for someone standing on its own
	# side with the barrel lying across in front of them (the pod's end on their right from the left, +x, flank)
	var paint := (meshes.barrel as ArrayMesh).surface_get_arrays(2)
	var at: PackedVector3Array = paint[Mesh.ARRAY_VERTEX]
	var uv: PackedVector2Array = paint[Mesh.ARRAY_TEX_UV]
	var cell := Rect2((TowLink.MARK.id as Rect2).position / TowLink.MARKS_SIZE, (TowLink.MARK.id as Rect2).size / TowLink.MARKS_SIZE).grow(1e-5)
	var reads := []
	var marks_ok: bool = TowLink.dress().albedo_texture != null
	for flank in [1.0, -1.0]:
		var first := Vector3.ZERO      # where the first letter's foot is, and the last letter's head
		var last := Vector3.ZERO
		var found := 0
		for i in at.size():
			if cell.has_point(uv[i]) and at[i].x * flank > 0.0:
				found += 1
				if uv[i].distance_to(Vector2(cell.position.x, cell.end.y)) < 1e-4:
					first = at[i]
				if uv[i].distance_to(Vector2(cell.end.x, cell.position.y)) < 1e-4:
					last = at[i]
		reads.append("%s flank: from z %.2f to %.2f, feet at y %.3f and heads at %.3f" % ["left" if flank > 0.0 else "right", first.z, last.z, first.y, last.y])
		marks_ok = marks_ok and found >= 8 and last.y > first.y + 0.02 and (first.z - last.z) * flank > 0.2
	_check("the stencils read the right way up from their own side (the link's number: %s)" % "; ".join(reads), marks_ok)


static func _triangles(mesh: Mesh) -> int:
	var n := 0
	for surface in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(surface)
		var idx = arr[Mesh.ARRAY_INDEX]
		n += ((idx as PackedInt32Array).size() if idx != null and not (idx as PackedInt32Array).is_empty() else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
	return n


func _process(_delta: float) -> bool:
	var t: float = v.sim.time      # the craft's own clock, not the wall's (tests/test_cables.gd)
	# straight for 2 s, a hard left to 3.5 s, then coasting straight to 5 s
	var inp := {"thrL": 0.5, "thrR": 0.5, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": true}
	if t > 2.0 and t <= 3.5:
		inp.thrL = 0.0
		inp.brkL = 1.0
	elif t > 3.5:
		inp.thrL = 0.0
		inp.thrR = 0.0
	v.inp = inp
	if t <= 0.5:
		return false
	var c = v.craft
	var row := [t]
	for k in 2:
		var cab: Dictionary = v.sim.cables[k]
		row.append([Vector2(cab.ex - cab.px, cab.ey - cab.py).length(), c.link_span[k], c.link_exposed[k], c.link_travel[k]])
		var parts: Array = c.link_parts[k]
		for part in parts:
			parts_ok = parts_ok and (part as Node3D).visible
		var at: Dictionary = {"swivel": (parts[0] as Node3D).transform, "barrel": (parts[1] as Node3D).transform, "rod": (parts[2] as Node3D).transform, "yoke": (parts[3] as Node3D).transform}
		var pod_basis: Basis = c.pod.transform.basis.orthonormalized()
		worst_fit = maxf(worst_fit, _fit(at, c.cable_ends[k][0], c.engines[k].transform.basis.orthonormalized(), c.cable_ends[k][1], pod_basis))
		parts_ok = parts_ok and c.cable_sag[k] == 0.0
		var boot: MeshInstance3D = c.link_boots[k]      # on the barrel, at its gland's face, as long as the telescope says
		boot_fit = maxf(boot_fit, absf(boot.scale.z * TowLink.BOOT - TowLink.boot_for(c.link_exposed[k], c.link_rod)))
		boot_ok = boot_ok and boot.get_parent() == parts[1] and absf(boot.position.z - TowLink.BARREL) < 1e-6 and boot.is_visible_in_tree() \
			and absf(boot.scale.z * TowLink.BOOT - c.link_boot[k]) < 1e-5
		if closed.is_empty():
			boot_run[k] = [minf(boot_run[k][0], c.link_boot[k]), maxf(boot_run[k][1], c.link_boot[k])]
	if not closed.is_empty():      # the frame after the engines were set back
		closed.append(row)
		_flown()
		v.queue_free()
		var good: bool = fails == 0 and passed == CHECKS
		print("TOW LINKS ", "PASS" if good else "FAIL (%d failed, %d passed)" % [fails, passed])
		quit(0 if good else 1)
		return true
	rows.append(row)
	if t >= 5.0:
		# the sim closed up by hand: both engines set back 1.5 m toward the pod (flying, its stand-off never
		# lets the links close by more than half a metre). The next frame draws whatever the sim then has.
		closed.append(row)
		for e in [v.sim.eL, v.sim.eR]:
			e.x -= 1.5 * cos(v.sim.pair_th)
			e.y -= 1.5 * sin(v.sim.pair_th)
	return false


func _flown() -> void:
	_check("flown (straight, a hard left, coasting): on every frame every part of both links is shown, rigid, and every pin in its hole (worst %.5f over %d frames)" % [worst_fit, rows.size()],
		parts_ok and worst_fit < 2e-3 and rows.size() > 100)
	for k in 2:
		var side := "left" if k == 0 else "right"
		var span := [INF, -INF]
		var rod := [INF, -INF]
		var apart := [INF, -INF]           # the rod showing less the sim's span, over the whole flight ...
		var apart_straight := [INF, -INF]  # ... and over the straight at the start
		var travel_ok := true
		for row in rows:
			var r: Array = row[1 + k]
			var d: float = float(r[2]) - float(r[0])
			span = [minf(span[0], r[0]), maxf(span[1], r[0])]
			rod = [minf(rod[0], r[2]), maxf(rod[1], r[2])]
			apart = [minf(apart[0], d), maxf(apart[1], d)]
			if float(row[0]) <= 2.0:
				apart_straight = [minf(apart_straight[0], d), maxf(apart_straight[1], d)]
			travel_ok = travel_ok and absf(float(r[3]) - (float(r[0]) - float(v.sim.P.cableLen))) < 1e-4 and absf(float(r[2]) - (float(r[1]) - TowLink.BARREL)) < 1e-4
		# the rod showing is the sim's span less a fixed length (the barrel, and where the fittings are: the lug is under
		# the engine's tail, 2 m below the post). Flying straight nothing else moves; in a turn the engines lean (the view's,
		# the sim is flat), and a lug 0.95 m under its engine's roll axis swings out with the lean.
		_check("flown, the %s link: the sim's span ran %.2f to %.2f m and the rod showing %.2f to %.2f m; the two differ by a length that held within %.3f m on the straight and %.2f m through the banked turn" % [
			side, span[0], span[1], rod[0], rod[1], float(apart_straight[1]) - float(apart_straight[0]), float(apart[1]) - float(apart[0])],
			travel_ok and float(span[1]) - float(span[0]) > 0.05 and float(apart_straight[1]) - float(apart_straight[0]) < 0.03 and float(apart[1]) - float(apart[0]) < 0.35)
	var seen := []
	var close_ok := true
	for k in 2:
		var before: Array = closed[0][1 + k]
		var after: Array = closed[1][1 + k]
		var d_span: float = float(after[0]) - float(before[0])
		var d_rod: float = float(after[2]) - float(before[2])
		seen.append("%s: the span %.2f m, the rod %.2f m" % ["left" if k == 0 else "right", d_span, d_rod])
		close_ok = close_ok and d_span < -0.8 and d_rod < 0.9 * d_span and d_rod > 1.02 * d_span
	# (not quite one for one: the sim's span lies flat, and the link drawn slopes 7 degrees down to a lug 2 m below the post)
	_check("the sim closed up by hand (both engines set back 1.5 m): the next frame's rods are drawn in by what the sim's spans closed, to within the link's slope (%s)" % "; ".join(seen), close_ok)
	var c = v.craft
	_check("flown, the boots: on every frame each hangs on its barrel's gland and stands as long as its telescope says (worst %.6f m off); over the flight the left ran %.2f to %.2f m and the right %.2f to %.2f m; closed up by hand both fold solid (%.2f, %.2f m)" % [
		boot_fit, boot_run[0][0], boot_run[0][1], boot_run[1][0], boot_run[1][1], c.link_boot[0], c.link_boot[1]],
		boot_ok and boot_fit < 1e-5 and float(boot_run[0][1]) - float(boot_run[0][0]) > 0.05 and float(boot_run[1][1]) - float(boot_run[1][0]) > 0.05
		and float(boot_run[0][0]) >= TowLink.BOOT_MIN and float(boot_run[1][1]) <= TowLink.BOOT_MAX and c.link_boot[0] == TowLink.BOOT_MIN and c.link_boot[1] == TowLink.BOOT_MIN)
	# what both links cost to draw: a surface a draw, in three kinds of material (the steel's, each link's own light, the paint and rubber's)
	var surfaces := 0
	var kinds := {}
	for k in 2:
		var drawn: Array = (c.link_parts[k] as Array).duplicate()
		drawn.append(c.link_boots[k])
		for part in drawn:
			for surface in (part as MeshInstance3D).mesh.get_surface_count():
				surfaces += 1
				kinds[(part as MeshInstance3D).get_active_material(surface)] = true
	_check("both links are %d surfaces in %d materials: the steel's, each link's own light, and one for paint and rubber" % [surfaces, kinds.size()],
		surfaces == 16 and kinds.size() == 4 and kinds.has(TowLink.metal()) and kinds.has(TowLink.dress()) and kinds.has(c.cable_mats[0]) and kinds.has(c.cable_mats[1]))
