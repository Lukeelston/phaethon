## The engines' fins in a turn (Luke: "The engine fins should rotate left/right as well as up/down with
## turning"; view/fin_steering.gd, view/shrike_airframe.gd, view/craft_model.gd).
##   on paper   what the fins answer, at the pilot's own numbers (his lever splits and the loads they bring);
##              the Shrike's panel on its spindle; its rams' travel with the turn's lean on top of the speed's
##   clear      nothing the turn moves passes through anything: the Shrike's fin panel against its engine's
##              open air-brake leaf, its stub and its ram; the Phaethon's rudder against its leaves, its
##              stabiliser's panel against the pipes and covers on the engine's flank
##   flown      either craft on the Range: centred going straight, swung the right way in a left turn and
##              a right one as he flies them, inside their limits through the hardest inputs there are
##              (into a wall, if it comes to that), never moving faster than their actuators, still with the
##              battery off;
##              the Shrike's pins in their holes and its rams inside their stroke on every frame
##   the rest   the racers', the partner's and the patrol's engines keep their fins whole and fixed
## --headless --xr-mode off --audio-driver Dummy -s res://tests/test_fins_turn.gd -- --mute
## (Windowed, it reads the Phaethon's rudders and stabilisers off the two batches they are drawn as; headless
## there is no renderer to keep them, and it reads the pivots the batches are put at.)
## Prints FINS TURN PASS.
extends SceneTree

const View := preload("res://view/craft_view.gd")
const Cockpit := preload("res://vr/vr_cockpit.gd")
const Model := preload("res://view/craft_model.gd")
const Shrike := preload("res://view/shrike_airframe.gd")
const Fins := preload("res://view/fin_steering.gd")
const DT := 1.0 / 480.0
const FRAME := 1.0 / 120.0
const MPH := 0.44704
const CHECKS := 20
var fails := 0
var passed := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if ok:
		passed += 1
	else:
		fails += 1


## The swing a split and the load it brings come to, held: degrees.
static func _held(split: float, load_g: float) -> float:
	return rad_to_deg(Fins.SWING_MAX * Fins.share(Fins.ask(split, load_g)))


func _on_paper() -> void:
	# his flying: the lever split's percentiles and the cornering load each brings (the eighth flight; probe_slide)
	var median := _held(0.03, 4.0)
	var three_quarters := _held(0.08, 10.0)
	var nine_tenths := _held(0.17, 21.0)
	var firm := _held(0.26, 33.0)
	var most := 0.0
	for split in [-2.0, -1.0, 0.4, 1.0, 2.0]:
		for load_g in [-150.0, -60.0, 0.0, 60.0, 150.0]:
			most = maxf(most, absf(_held(split, load_g)))
	_check("held, the rudders stand %.1f deg over in his median turn (a split of 0.03, 4 g), %.1f in three quarters of them (0.08, 10 g), %.1f in nine tenths (0.17, 21 g), %.1f at one in twenty (0.26, 33 g), and never more than %.1f whatever is asked" % [
		median, three_quarters, nine_tenths, firm, most],
		median > 2.0 and median < 6.0 and three_quarters > 8.0 and three_quarters < 14.0 and nine_tenths > 15.0 and nine_tenths < 19.6 and firm > nine_tenths and most <= 20.0 + 1e-6)
	_check("a split inside the slack and no load asks nothing (a parked craft's idling engines differ by 0.012: the title's two stand still); a split to the right and a load to the right both ask right, and the levers alone ask no more than %.0f g" % Fins.ASK_MAX,
		Fins.ask(0.012, 0.0) == 0.0 and Fins.ask(-0.02, 0.0) == 0.0 and Fins.ask(0.1, 0.0) > 0.0 and Fins.ask(0.0, 5.0) > 0.0 and Fins.ask(-0.1, 0.0) < 0.0 and Fins.ask(0.0, -5.0) < 0.0
		and is_equal_approx(Fins.ask(5.0, 0.0), Fins.LEAD * Fins.ASK_MAX) and is_equal_approx(Fins.ask(0.1, 9.6), 9.6))      # (in a steady turn the two agree: SPLIT_G * (0.1 - the slack) = 9.6)
	var eased := 0.0
	var jump := 0.0
	for frame in 240:
		var was := eased
		eased = Fins.ease(eased, 20.0, FRAME)
		jump = maxf(jump, eased - was)
	var let_go := eased
	for frame in 480:
		let_go = Fins.ease(let_go, 0.0, FRAME)
	_check("the answer is eased: a step of 20 g is %.1f g a frame at most, there in two seconds (%.2f), and let go of altogether once it has died away (%.6f)" % [jump, eased, let_go],
		jump < 1.5 and absf(eased - 20.0) < 0.01 and let_go == 0.0)
	# the Shrike's panel on its spindle
	var worst := 0.0
	var right := true
	for k in 2:
		var out := -1.0 if k == 0 else 1.0
		for cant in [Shrike.FIN_REST, Shrike.FIN_CANT, Shrike.FIN_FAST]:
			var fin: Transform3D = Shrike.fin_solve(out, cant).fin
			var line: Vector3 = fin.basis * Vector3(out * sin(Shrike.FIN_CANT), cos(Shrike.FIN_CANT), 0.0)      # the fin's own line as it stands
			var foot: Vector3 = fin * Shrike.panel_foot(out)
			var straight: Vector3 = fin * Shrike.panel_place(out, 0.0) * Shrike.panel_tip(out)
			worst = maxf(worst, straight.distance_to(fin * Shrike.fin_tip_local(out)))                      # unswung, the tip is where the whole fin's was
			for swing in [-Shrike.PANEL_SWING, Shrike.PANEL_SWING]:
				var place: Transform3D = fin * Shrike.panel_place(out, swing)
				var tip: Vector3 = place * Shrike.panel_tip(out)
				worst = maxf(worst, place.origin.distance_to(foot))                                           # the spindle's foot stays where it is ...
				worst = maxf(worst, absf((tip - foot).dot(line) - (straight - foot).dot(line)))              # ... and the panel turns about the fin's own line and nothing else
				worst = maxf(worst, absf((tip - foot).length() - (straight - foot).length()))
				right = right and signf(tip.x - straight.x) == signf(swing)                                  # + = its trailing tip to the engine's right
	_check("the Shrike's panel turns about the fin's own line through the spindle's foot at every cant, on both engines (worst %.7f), its tip to the right for a right turn" % worst, worst < 1e-5 and right)
	var showing := [INF, -INF]
	var piston := [INF, -INF]
	var cants := [INF, -INF]
	for mph in range(0, 9001, 250):
		for lean in [-1.0, -0.5, 0.0, 0.5, 1.0]:
			var cant: float = clampf(Shrike.fin_cant(float(mph)) + lean * Shrike.FIN_LEAN, Shrike.FIN_REST, Shrike.FIN_FAST)
			var s: Dictionary = Shrike.fin_solve(1.0, cant)
			showing = [minf(showing[0], s.showing), maxf(showing[1], s.showing)]
			piston = [minf(piston[0], s.piston), maxf(piston[1], s.piston)]
			cants = [minf(cants[0], cant), maxf(cants[1], cant)]
	_check("with the turn's lean (%.1f deg either way) on top of the speed's cant the fins stand %.1f to %.1f deg from upright, the rams' own travel: the rod shows %.3f to %.3f m and its piston stays %.3f to %.3f m up a %.2f m cylinder" % [
		rad_to_deg(Shrike.FIN_LEAN), rad_to_deg(cants[0]), rad_to_deg(cants[1]), showing[0], showing[1], piston[0], piston[1], Shrike.RAM_BARREL],
		is_equal_approx(cants[0], Shrike.FIN_REST) and is_equal_approx(cants[1], Shrike.FIN_FAST) and float(showing[0]) > 0.10 and float(piston[0]) > 0.08 and float(piston[1]) < Shrike.RAM_BARREL - 0.08)


## A mesh's points, with `n` more along each side of each triangle, through `xf`.
static func _points(mesh: Mesh, xf: Transform3D, n := 1) -> PackedVector3Array:
	var out := PackedVector3Array()
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var index = arrays[Mesh.ARRAY_INDEX]
		var order: PackedInt32Array = index if index != null and not (index as PackedInt32Array).is_empty() else PackedInt32Array(range(verts.size()))
		for t in order.size() / 3:
			var a: Vector3 = xf * verts[order[t * 3]]
			var b: Vector3 = xf * verts[order[t * 3 + 1]]
			var c: Vector3 = xf * verts[order[t * 3 + 2]]
			for i in n + 1:
				for j in n + 1 - i:
					out.append(a + (b - a) * (float(i) / n) + (c - a) * (float(j) / n))
	return out


## A flat part as a slab that holds all of it: `flat` takes the part's own points to (across its
## thickness, along, along). {flat, half: the slab's half-thickness, hull: its outline}.
static func _slab(mesh: Mesh, flat: Basis) -> Dictionary:
	var half := 0.0
	var plan := PackedVector2Array()
	for p in _points(mesh, Transform3D(flat, Vector3.ZERO)):
		half = maxf(half, absf(p.x))
		plan.append(Vector2(p.y, p.z))
	return {"flat": flat, "half": half, "hull": Geometry2D.convex_hull(plan)}


## How near `points` (in the frame `place` puts the slab's part in) come to the slab: no nearer to the part itself.
static func _clear(slab: Dictionary, place: Transform3D, points: PackedVector3Array) -> float:
	var into := Transform3D(slab.flat as Basis, Vector3.ZERO) * place.affine_inverse()
	var hull: PackedVector2Array = slab.hull
	var nearest := INF
	for p in points:
		var q: Vector3 = into * p
		var off := maxf(absf(q.x) - float(slab.half), 0.0)
		if off >= nearest:
			continue
		var at := Vector2(q.y, q.z)
		var away := 0.0
		if not Geometry2D.is_point_in_polygon(at, hull):
			away = INF
			for i in hull.size():
				away = minf(away, at.distance_to(Geometry2D.get_closest_point_to_segment(at, hull[i], hull[(i + 1) % hull.size()])))
		nearest = minf(nearest, Vector2(off, away).length())
	return nearest


## A leaf's place in its engine's own frame, opened `opening` of its travel (and its flutter with it).
static func _leaf_place(craft, k: int, i: int, opening: float) -> Transform3D:
	var hinge: Node3D = craft.flaps[k][i]
	hinge.rotation.x = -Model.FLAP_OPEN * opening - deg_to_rad(1.85)
	var leaf: Node3D = hinge.get_child(0)
	return (hinge.get_parent() as Node3D).transform * hinge.transform * leaf.transform


func _clear_shrike(craft) -> void:
	var nearest := INF
	var where := ""
	var above := INF
	var below := -INF
	for k in 2:
		var out := -1.0 if k == 0 else 1.0
		var panel: MeshInstance3D = craft.fin_parts[k][3]
		var line := Vector3(out * sin(Shrike.FIN_CANT), cos(Shrike.FIN_CANT), 0.0)      # the fin's own line, in the fin's frame
		var slab := _slab(panel.mesh, Basis(line.cross(Vector3.BACK), line, Vector3.BACK).transposed())
		# the leaf beside the fin: the upper one on the fin's side of the engine
		var beside := 0
		for i in craft.flaps[k].size():
			var ring: Node3D = (craft.flaps[k][i] as Node3D).get_parent()
			if signf(ring.position.x) == out and absf(ring.rotation.z) < 0.1:
				beside = i
		var leaf_mesh: Mesh = ((craft.flaps[k][beside] as Node3D).get_child(0) as MeshInstance3D).mesh
		for cant in [Shrike.FIN_REST, 0.62, Shrike.FIN_CANT, 0.9, Shrike.FIN_FAST]:
			for swing in [-Shrike.PANEL_SWING, -0.5 * Shrike.PANEL_SWING, 0.0, 0.5 * Shrike.PANEL_SWING, Shrike.PANEL_SWING]:
				craft._place_fin(k, cant, swing)
				var fin: Transform3D = (craft.fin_parts[k][0] as Node3D).transform
				var place: Transform3D = fin * panel.transform
				for opening in [0.0, 0.35, 0.7, 1.0]:
					var gap := _clear(slab, place, _points(leaf_mesh, _leaf_place(craft, k, beside, opening), 4))
					if gap < nearest:
						nearest = gap
						where = "%s engine, %.0f deg from upright, swung %.0f deg, the leaf %.0f %% open" % ["port" if k == 0 else "starboard", rad_to_deg(cant), rad_to_deg(swing), opening * 100.0]
				# the panel is all above the cut; the stub, the ram's cylinder and its rod all below it
				var foot: Vector3 = fin * Shrike.panel_foot(out)
				var up: Vector3 = fin.basis * line
				for p in _points(panel.mesh, place):
					above = minf(above, (p - foot).dot(up))
				for part in 3:
					var node: MeshInstance3D = craft.fin_parts[k][part]
					for p in _points(node.mesh, node.transform):
						below = maxf(below, (p - foot).dot(up))
		(craft.flaps[k][beside] as Node3D).rotation.x = 0.0
		craft._place_fin(k, craft.fin_cant, 0.0)
	_check("the Shrike's fin panel, swung either way at every cant, comes no nearer its engine's air-brake leaf than %.3f m, shut or open (%s)" % [nearest, where], nearest > 0.05)
	_check("the panel is all above the cut (%.4f m over it at the least), and the stub, the ram's cylinder and its rod all below (%.4f m under at the most): none of them can meet it" % [above, -below], above > 0.0 and below < 0.0)


func _clear_phaethon(craft) -> void:
	var rudder: Node3D = craft.rudders[1]      # (where it stands; what is drawn there is the batch's mesh)
	var rudder_mesh: Mesh = craft.fin_batches[0].mesh
	var slab := _slab(rudder_mesh, Basis.IDENTITY)
	var nearest := INF
	var post := INF
	for swing in [-Fins.SWING_MAX, 0.0, Fins.SWING_MAX]:
		rudder.rotation.y = swing
		for i in craft.flaps[1].size():
			if absf(((craft.flaps[1][i] as Node3D).get_parent() as Node3D).rotation.z) > 0.1:
				continue      # (the lower leaves)
			var leaf_mesh: Mesh = ((craft.flaps[1][i] as Node3D).get_child(0) as MeshInstance3D).mesh
			for opening in [0.0, 0.5, 1.0]:
				nearest = minf(nearest, _clear(slab, rudder.transform, _points(leaf_mesh, _leaf_place(craft, 1, i, opening), 4)))
			(craft.flaps[1][i] as Node3D).rotation.x = 0.0
		# its foot over the deck and over the band round the engine there
		for p in _points(rudder_mesh, rudder.transform):
			if Vector2(p.x, p.z - Fins.RUDDER_Z).length() > Fins.POST + 0.001:      # (the post itself stands in its collar)
				post = minf(post, p.y - Model.ENG_H / 2.0)
	rudder.rotation.y = 0.0
	_check("the Phaethon's rudder, swung either way, comes no nearer the air-brake leaves behind it than %.3f m, shut or open, and its foot rides %.3f m over the deck (the band round the engine stands 0.020)" % [nearest, post], nearest > 0.05 and post > 0.025)
	# the stabiliser's panel against what stands on the flank: the engine's shell and its fixed mesh
	var flank := PackedVector3Array()
	for part in ["NacelleShell/NacelleHardware", "PhaethonFairing"]:
		var node: MeshInstance3D = craft.engines[1].get_node(part)
		var xf := node.transform if part == "PhaethonFairing" else (craft.engines[1].get_node("NacelleShell") as Node3D).transform * node.transform
		for p in _points(node.mesh, xf, 3):
			if p.x > Model.ENG_W / 2.0 - 0.05 and p.z > -1.2 and p.z < 2.2 and p.x < Model.ENG_W / 2.0 + Fins.GLOVE + 0.001:
				flank.append(p)
	var plate := _slab(craft.fin_batches[1].mesh, Basis(Vector3.UP, Vector3.RIGHT, Vector3.BACK).transposed())
	var gap := INF
	var lamp := 0.0
	var tip := Vector3(Model.ENG_W / 2.0 + Fins.LAMP.x, Fins.STAB_Y, Fins.LAMP.y)      # the nav lamp, in the engine's fixed lights
	for pitch in [-Fins.PITCH_MAX, 0.0, Fins.PITCH_MAX]:
		var place: Transform3D = Fins.stabiliser_place(1.0, Model.ENG_W / 2.0, pitch)
		gap = minf(gap, _clear(plate, place, flank))
		var foot: Vector3 = place.origin
		var line: Vector3 = place.basis * Fins.stab_axis()
		lamp = maxf(lamp, ((tip - foot) - line * (tip - foot).dot(line)).length())      # the lamp is on the spindle's own line
	_check("the Phaethon's stabiliser panel, pitched either way, comes no nearer the pipes, the covers and the root glove on its engine's flank than %.3f m (%d points of them), and the nav lamp at its tip is on the spindle's own line (%.5f m off): it need not move" % [gap, flank.size(), lamp],
		gap > 0.01 and flank.size() > 200 and lamp < 1e-4)


## How far out of its hole the Shrike's worst pin is (tests/test_shrike_fins.gd's own measure).
static func _fit(out: float, fin: Transform3D, barrel: Transform3D, rod: Transform3D) -> float:
	var hinge := Vector3(out * Shrike.FIN_HINGE.x, Shrike.FIN_HINGE.y, Shrike.FIN_HINGE.z)
	var base := Vector3(out * Shrike.RAM_BASE.x, Shrike.RAM_BASE.y, Shrike.RAM_BASE.z)
	var worst := 0.0
	worst = maxf(worst, fin.origin.distance_to(hinge))
	worst = maxf(worst, fin.basis.z.cross(Vector3.BACK).length())
	worst = maxf(worst, barrel.origin.distance_to(base))
	worst = maxf(worst, rod.origin.distance_to(fin * Vector3(out * Shrike.RAM_PIN.x, Shrike.RAM_PIN.y, Shrike.RAM_PIN.z)))
	var along := barrel.basis.y.normalized()
	worst = maxf(worst, along.cross(-rod.basis.y.normalized()).length())
	var off := rod.origin - barrel.origin
	worst = maxf(worst, (off - along * off.dot(along)).length())
	return worst


## What a view's fins are doing, read off the parts themselves (not the model's own numbers):
## {swing: [rad, rad] each engine's rudder or panel, + = trailing edge right; up: [rad, rad] each engine's
## fin from upright (the Shrike) or its stabiliser turned on its spindle, + = trailing edge up (the Phaethon);
## fit; showing: [m, m]}.
func _read(v) -> Dictionary:
	var craft = v.craft
	var swing := [0.0, 0.0]
	var up := [0.0, 0.0]
	var fit := 0.0
	var showing := [0.0, 0.0]
	for k in 2:
		var out := -1.0 if k == 0 else 1.0
		if not craft.fin_parts.is_empty():
			var fin: Transform3D = (craft.fin_parts[k][0] as Node3D).transform
			var panel: Transform3D = (craft.fin_parts[k][3] as Node3D).transform
			var line := Vector3(out * sin(Shrike.FIN_CANT), cos(Shrike.FIN_CANT), 0.0)
			var aft: Vector3 = panel.basis * Vector3.BACK      # the panel's own chord line, in the fin's frame
			swing[k] = atan2(aft.dot(line.cross(Vector3.BACK)), aft.dot(Vector3.BACK))
			up[k] = Shrike.FIN_CANT - out * fin.basis.get_euler().z
			fit = maxf(fit, _fit(out, fin, (craft.fin_parts[k][1] as Node3D).transform, (craft.fin_parts[k][2] as Node3D).transform))
			showing[k] = (fin * Vector3(out * Shrike.RAM_PIN.x, Shrike.RAM_PIN.y, Shrike.RAM_PIN.z)).distance_to(Vector3(out * Shrike.RAM_BASE.x, Shrike.RAM_BASE.y, Shrike.RAM_BASE.z)) - Shrike.RAM_BARREL
		else:
			var rudder: Transform3D = (craft.rudders[k] as Node3D).transform
			var panel: Transform3D = (craft.stabilisers[k] as Node3D).transform
			if drawn:      # (read off what is drawn: the batches' own two, against the engine each is on)
				var on_engine: Transform3D = (craft.engines[k] as Node3D).transform.affine_inverse()
				rudder = on_engine * (craft.fin_batches[0] as MultiMesh).get_instance_transform(k)
				panel = on_engine * (craft.fin_batches[1] as MultiMesh).get_instance_transform(k)
				fit = maxf(fit, rudder.basis.x.distance_to((craft.rudders[k] as Node3D).transform.basis.x) + panel.basis.z.distance_to((craft.stabilisers[k] as Node3D).transform.basis.z))      # ... and where the model's own pivots are
			fit = maxf(fit, rudder.origin.distance_to(Vector3(0.0, Model.ENG_H / 2.0, Fins.RUDDER_Z)) + panel.origin.distance_to(Vector3(out * (Model.ENG_W / 2.0 + Fins.STAB_FROM), Fins.STAB_Y, Fins.STAB_AXIS_Z)))
			var aft: Vector3 = rudder.basis * Vector3.BACK
			swing[k] = atan2(aft.x, aft.z)
			var stand := Basis.IDENTITY if out > 0.0 else Basis(Vector3.BACK, PI)      # (the port engine's is the same part turned half round)
			var line := Fins.stab_axis()
			var across := line.cross(Vector3.UP).normalized()
			var turned: Vector3 = stand.inverse() * panel.basis * across      # a line across the spindle, as the panel carries it
			up[k] = -out * atan2(turned.dot(line.cross(across)), turned.dot(across))      # (about the spindle; the starboard panel's trailing edge rises as it turns back)
	return {"swing": swing, "up": up, "fit": fit, "showing": showing}


var drawn := DisplayServer.get_name() != "headless"      # a real renderer keeps the Phaethon's batches: read what is drawn. Headless there is none: the model's own pivots.
var _was := {}      # the last frame's reading, for the steps between frames
var _step := {"swing": 0.0, "up": 0.0}      # the largest steps seen, rad a second
var _most := {"swing": 0.0, "up_lo": INF, "up_hi": -INF, "fit": 0.0, "show_lo": INF, "show_hi": -INF}


## A frame: four steps of the sim on `inp`, the craft posed, the fins read and their steps and reach kept.
func _fly(v, inp: Dictionary) -> Dictionary:
	for sub in 4:
		v.sim.step(inp, DT)
	v.sim.events.clear()
	v.inp = inp
	v._follow_origin()      # (as a frame does: the craft is posed about the pod, wherever the flight has taken it)
	v._sync_craft(FRAME)
	var now := _read(v)
	for k in 2:
		if not _was.is_empty():
			_step.swing = maxf(_step.swing, absf(float(now.swing[k]) - float(_was.swing[k])) / FRAME)
			_step.up = maxf(_step.up, absf(float(now.up[k]) - float(_was.up[k])) / FRAME)
		_most.swing = maxf(_most.swing, absf(float(now.swing[k])))
		_most.up_lo = minf(_most.up_lo, now.up[k])
		_most.up_hi = maxf(_most.up_hi, now.up[k])
		_most.show_lo = minf(_most.show_lo, now.showing[k])
		_most.show_hi = maxf(_most.show_hi, now.showing[k])
	_most.fit = maxf(_most.fit, now.fit)
	_was = now
	return now


static func _input(thr_l: float, thr_r: float, brk_l: float, brk_r: float) -> Dictionary:
	return {"thrL": thr_l, "thrR": thr_r, "brkL": brk_l, "brkR": brk_r, "repair": false, "reignite": true}


func _flown(vehicle: String) -> void:
	View.vehicle_override = vehicle
	var v = View.new()
	root.add_child(v)
	await process_frame
	v.set_process(false)
	var craft = v.craft
	var shrike: bool = not craft.fin_parts.is_empty()
	var name := "the Shrike" if shrike else "the Phaethon"
	if shrike:
		_clear_shrike(craft)
	else:
		_clear_phaethon(craft)
	_was = {}
	_step = {"swing": 0.0, "up": 0.0}
	_most = {"swing": 0.0, "up_lo": INF, "up_hi": -INF, "fit": 0.0, "show_lo": INF, "show_hi": -INF}
	var swing_slew: float = Shrike.PANEL_SLEW if shrike else Fins.SWING_SLEW
	var up_slew: float = Shrike.FIN_SLEW if shrike else Fins.PITCH_SLEW
	# standing, then flat out for three seconds: centred
	var off := 0.0
	var apart := 0.0
	var now := {}
	for frame in 480:
		now = _fly(v, _input(0.0, 0.0, 0.0, 0.0) if frame < 120 else _input(1.0, 1.0, 0.0, 0.0))
		off = maxf(off, maxf(absf(float(now.swing[0])), absf(float(now.swing[1]))))
		apart = maxf(apart, absf(float(now.up[0]) - float(now.up[1])) if shrike else maxf(absf(float(now.up[0])), absf(float(now.up[1]))))
	var mph: float = Vector2(v.sim.pod.vx, v.sim.pod.vy).length() / MPH
	_check("%s standing and then flat out for three seconds (to %d mph): its fins centred throughout (%.4f deg off at the most; %s %.4f deg)" % [name, int(mph), rad_to_deg(off),
		"the two fins' cants apart by" if shrike else "the stabilisers off level by", rad_to_deg(apart)], mph > 400.0 and off < deg_to_rad(0.05) and apart < deg_to_rad(0.05))
	# a turn each way as he flies one: a grip a third in, both levers up (the eighth flight's log)
	var said := []
	var ways := true
	for turn in [-1.0, 1.0]:
		for frame in 96:
			now = _fly(v, _input(0.74, 1.0, 0.16, 0.10) if turn < 0.0 else _input(1.0, 0.74, 0.10, 0.16))
		var inside := 0 if turn < 0.0 else 1
		var both: bool = signf(now.swing[0]) == turn and signf(now.swing[1]) == turn and absf(float(now.swing[0]) - float(now.swing[1])) < 1e-4 and absf(float(now.swing[0])) > deg_to_rad(8.0)
		var answer: bool
		if shrike:      # the inside engine's fin laid out further than the outside engine's
			answer = float(now.up[inside]) > float(now.up[1 - inside]) + deg_to_rad(4.0)
		else:           # the inside engine's stabiliser trailing edge up, the outside engine's down
			answer = float(now.up[inside]) > deg_to_rad(4.0) and float(now.up[1 - inside]) < -deg_to_rad(4.0)
		ways = ways and both and answer
		said.append("%s: both %s swung %.1f deg, %s %.1f deg inside and %.1f outside" % ["left" if turn < 0.0 else "right", "panels" if shrike else "rudders", rad_to_deg(now.swing[0]),
			"the fins" if shrike else "the stabilisers' trailing edges up", rad_to_deg(now.up[inside]), rad_to_deg(now.up[1 - inside])])
		for frame in 150:      # out of it
			now = _fly(v, _input(1.0, 1.0, 0.0, 0.0))
	_check("%s in a turn each way as he flies one, 0.8 s into it (%s): trailing edges into the turn, the inside and the outside engines' answering differently" % [name, "; ".join(said)], ways)
	# the hardest there is: a lever right back and that engine's brake thrown, one side then the other with
	# nothing between, then both brakes, into whatever it hits
	var crashed := false
	for leg in [[0.0, 1.0, 1.0, 0.0, 70], [1.0, 0.0, 0.0, 1.0, 70], [0.0, 1.0, 1.0, 0.0, 50], [1.0, 0.0, 0.0, 1.0, 240], [1.0, 1.0, 1.0, 1.0, 120], [0.0, 0.0, 0.0, 0.0, 240]]:
		for frame in int(leg[4]):
			now = _fly(v, _input(leg[0], leg[1], leg[2], leg[3]))
			crashed = crashed or v.sim.crash_t > 0.0
	var top_swing: float = Shrike.PANEL_SWING if shrike else Fins.SWING_MAX
	var stroke := [float(Shrike.fin_solve(1.0, Shrike.FIN_REST).showing), float(Shrike.fin_solve(1.0, Shrike.FIN_FAST).showing)]
	if shrike:
		_check("through the hardest inputs there are (%s): the panels never past %.1f deg (%.2f), the fins never outside the rams' travel (%.1f to %.1f deg from upright; the rods show %.3f to %.3f m), every pin in its hole on every frame (%.7f)" % [
			"a crash among them" if crashed else "no crash came of them", rad_to_deg(top_swing), rad_to_deg(_most.swing), rad_to_deg(_most.up_lo), rad_to_deg(_most.up_hi), _most.show_lo, _most.show_hi, _most.fit],
			float(_most.swing) <= top_swing + 1e-5 and float(_most.swing) > 0.85 * top_swing and float(_most.up_lo) >= Shrike.FIN_REST - 1e-5 and float(_most.up_hi) <= Shrike.FIN_FAST + 1e-5
			and float(_most.show_lo) >= float(stroke[0]) - 1e-5 and float(_most.show_hi) <= float(stroke[1]) + 1e-5 and float(_most.fit) < 1e-5)
	else:
		_check("through the hardest inputs there are (%s): the rudders never past %.1f deg (%.2f), the stabilisers never past %.1f (%.2f down, %.2f up), each on its post or its spindle on every frame (%.6f off at the most; %s)" % [
			"a crash among them" if crashed else "no crash came of them", rad_to_deg(top_swing), rad_to_deg(_most.swing), rad_to_deg(Fins.PITCH_MAX), rad_to_deg(-float(_most.up_lo)), rad_to_deg(_most.up_hi), _most.fit,
			"read off the two batches as they are drawn" if drawn else "the model's pivots: run windowed to read the batches as drawn"],
			float(_most.fit) < 2e-3 and float(_most.swing) <= top_swing + 1e-5 and float(_most.swing) > 0.85 * top_swing and float(_most.up_lo) >= -Fins.PITCH_MAX - 1e-4 and float(_most.up_hi) <= Fins.PITCH_MAX + 1e-4 and float(_most.up_hi) > 0.85 * Fins.PITCH_MAX)
	_check("... and never faster than their actuators: %.1f deg/s left and right (of %.0f), %.1f deg/s up and down (of %.1f), so %.2f and %.2f deg between frames at the most" % [
		rad_to_deg(_step.swing), rad_to_deg(swing_slew), rad_to_deg(_step.up), rad_to_deg(up_slew), rad_to_deg(float(_step.swing) * FRAME), rad_to_deg(float(_step.up) * FRAME)],
		float(_step.swing) <= swing_slew * 1.001 + 1e-4 and float(_step.swing) > 0.5 * swing_slew and float(_step.up) <= up_slew * 1.001 + 1e-4 and float(_step.up) > 0.5 * up_slew)
	# the battery off: nothing answers, and what was over comes back
	for frame in 300:
		now = _fly(v, _input(1.0, 1.0, 0.0, 0.0))
	craft.lights_on = false
	for frame in 240:
		now = _fly(v, _input(0.0, 0.0, 1.0, 0.0))
	var dead: float = maxf(absf(float(now.swing[0])), absf(float(now.swing[1])))
	craft.lights_on = true
	for frame in 60:
		now = _fly(v, _input(0.0, 0.0, 1.0, 0.0))
	_check("%s with the battery off and a brake held on for two seconds: nothing answers (the fins stand %.4f deg off centre); switched on, they do (%.1f deg in half a second)" % [name, rad_to_deg(dead), rad_to_deg(now.swing[0])],
		dead < deg_to_rad(0.05) and absf(float(now.swing[0])) > deg_to_rad(5.0))
	v.queue_free()
	await process_frame


func _the_rest() -> void:
	var whole: ArrayMesh = Model._engine_body(1.0)
	var bare: ArrayMesh = Model._engine_body(1.0, false)
	var a: AABB = whole.get_aabb()
	var b: AABB = bare.get_aabb()
	_check("the engine's fixed mesh as the racers, the partner and the patrol draw it keeps its fins whole (up to %.2f m over the deck, out to %.2f m); the pilot's own is without the parts that move (%.2f, %.2f)" % [
		a.end.y - Model.ENG_H / 2.0, a.end.x, b.end.y - Model.ENG_H / 2.0, b.end.x],
		a.end.y > Model.ENG_H / 2.0 + 0.6 and a.end.x > Model.ENG_W / 2.0 + 1.0 and b.end.y < Model.ENG_H / 2.0 + 0.5 and b.end.x < Model.ENG_W / 2.0 + Fins.GLOVE + 0.2)


func _run() -> void:
	var prefs_before := FileAccess.get_file_as_string(Cockpit.PREFS) if FileAccess.file_exists(Cockpit.PREFS) else ""
	var had_prefs := FileAccess.file_exists(Cockpit.PREFS)
	View.track_override = "range"
	View.job_override = "none"
	View.best_dir = OS.get_user_data_dir().path_join("test_fins_turn_")
	_on_paper()
	await _flown("shrike")
	await _flown("phaethon")
	_the_rest()
	View.vehicle_override = ""
	if had_prefs:
		var out := FileAccess.open(Cockpit.PREFS, FileAccess.WRITE)
		out.store_string(prefs_before)
		out.close()
	elif FileAccess.file_exists(Cockpit.PREFS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Cockpit.PREFS))
	var good: bool = fails == 0 and passed == CHECKS
	print("FINS TURN ", "PASS" if good else "FAIL (%d failed, %d passed of %d)" % [fails, passed, CHECKS])
	quit(0 if good else 1)
