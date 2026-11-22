## The Shrike's engine fins (view/shrike_airframe.gd; Luke: "find a way to animate its engine fins with
## speed - they should angle via a hydraulic arm"): that the fin turns on its hinge with the speed, and
## that the ram which moves it is a real one.
##   on paper   the law (tall at rest, as drawn at half FIN_FAST_MPH, laid out from there up); solve() across
##              the travel on both engines: the fin on its hinge line, the cylinder on the bracket's
##              pin, the rod on the lug's pin and down the cylinder's bore, its piston inside
##   the parts  the authored meshes are where those numbers say: the lug's pin in the fin, the
##              bracket's pin and the hinge's saddles on the nacelle, the cylinder and rod as long
##   flown      a Shrike on the Range, standing, then at set speeds and under its own power: the fins
##              follow the law no faster than the ram strokes, every pin in its hole on every frame,
##              the tip's lamp and strobe riding the fin; and a Phaethon has none of it
## --headless --xr-mode off --audio-driver Dummy -s res://tests/test_shrike_fins.gd -- --mute
## Prints SHRIKE FINS PASS.
extends SceneTree

const View := preload("res://view/craft_view.gd")
const Cockpit := preload("res://vr/vr_cockpit.gd")
const Shrike := preload("res://view/shrike_airframe.gd")
const DT := 1.0 / 480.0
const FRAME := 1.0 / 120.0
const MPH := 0.44704
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


## How far out of its hole the worst pin is (m, or a misalignment as a sine), for one engine's fin,
## cylinder and rod as they stand (engine-local transforms).
static func _fit(out: float, fin: Transform3D, barrel: Transform3D, rod: Transform3D) -> float:
	var hinge := Vector3(out * Shrike.FIN_HINGE.x, Shrike.FIN_HINGE.y, Shrike.FIN_HINGE.z)
	var base := Vector3(out * Shrike.RAM_BASE.x, Shrike.RAM_BASE.y, Shrike.RAM_BASE.z)
	var worst := 0.0
	worst = maxf(worst, fin.origin.distance_to(hinge))                                  # the fin is on its hinge line ...
	worst = maxf(worst, fin.basis.z.cross(Vector3.BACK).length())                       # ... and turns about it and nothing else
	worst = maxf(worst, barrel.origin.distance_to(base))                                # the cylinder's eye is on the bracket's pin ...
	worst = maxf(worst, barrel.basis.z.cross(Vector3.BACK).length())                    # ... turning about that pin's own line
	worst = maxf(worst, rod.origin.distance_to(fin * Vector3(out * Shrike.RAM_PIN.x, Shrike.RAM_PIN.y, Shrike.RAM_PIN.z)))   # the rod's eye is on the lug's pin ...
	worst = maxf(worst, rod.basis.z.cross(Vector3.BACK).length())                       # ... turning about that pin's line
	var along := barrel.basis.y.normalized()
	worst = maxf(worst, along.cross(-rod.basis.y.normalized()).length())                # the rod lies along the cylinder ...
	var off := rod.origin - barrel.origin
	worst = maxf(worst, (off - along * off.dot(along)).length())                        # ... and down the middle of its bore
	for part in [fin, barrel, rod]:                                                     # each part is a rigid thing, the right way out
		var b: Basis = (part as Transform3D).basis
		worst = maxf(worst, absf(b.determinant() - 1.0))
		worst = maxf(worst, absf(b.x.length() - 1.0) + absf(b.y.length() - 1.0) + absf(b.x.dot(b.y)))
	return worst


func _on_paper() -> void:
	var half: float = Shrike.fin_cant(0.5 * Shrike.FIN_FAST_MPH)
	var rising := true
	var last := -1.0
	for mph in range(0, 9001, 250):
		var c: float = Shrike.fin_cant(float(mph))
		rising = rising and c >= last - 1e-9
		last = c
	_check("the law: %.1f deg from upright standing, %.1f at %d mph (as the fin was drawn: %.1f), %.1f from %d mph up, and never back the other way; %.1f at 1,000 and %.1f at 3,000" % [
		rad_to_deg(Shrike.fin_cant(0.0)), rad_to_deg(half), int(0.5 * Shrike.FIN_FAST_MPH), rad_to_deg(Shrike.FIN_CANT), rad_to_deg(Shrike.fin_cant(Shrike.FIN_FAST_MPH)), int(Shrike.FIN_FAST_MPH),
		rad_to_deg(Shrike.fin_cant(1000.0)), rad_to_deg(Shrike.fin_cant(3000.0))],
		is_equal_approx(Shrike.fin_cant(0.0), Shrike.FIN_REST) and absf(half - Shrike.FIN_CANT) < 1e-6 and is_equal_approx(Shrike.fin_cant(Shrike.FIN_FAST_MPH), Shrike.FIN_FAST)
		and is_equal_approx(Shrike.fin_cant(9000.0), Shrike.FIN_FAST) and rising and Shrike.FIN_REST < Shrike.FIN_CANT and Shrike.FIN_CANT < Shrike.FIN_FAST)
	var worst := 0.0
	var showing := [INF, -INF]
	var piston := [INF, -INF]
	var grows := true
	var mirrored := 0.0
	var from_inboard := true
	var before := -INF
	for step in 57:
		var cant: float = lerpf(Shrike.FIN_REST, Shrike.FIN_FAST, step / 56.0)
		var s: Dictionary = Shrike.fin_solve(1.0, cant)
		var p: Dictionary = Shrike.fin_solve(-1.0, cant)
		worst = maxf(worst, maxf(_fit(1.0, s.fin, s.barrel, s.rod), _fit(-1.0, p.fin, p.barrel, p.rod)))
		showing = [minf(showing[0], s.showing), maxf(showing[1], s.showing)]
		piston = [minf(piston[0], s.piston), maxf(piston[1], s.piston)]
		grows = grows and float(s.span) > before
		before = s.span
		mirrored = maxf(mirrored, (Vector3(-p.pin.x, p.pin.y, p.pin.z) - s.pin).length() + absf(float(p.span) - float(s.span)))
		# the rod comes at the fin from its inboard side: along the ram, bracket to lug, is into the fin's inboard face
		var inboard: Vector3 = (s.fin as Transform3D).basis * Vector3(-cos(Shrike.FIN_CANT), sin(Shrike.FIN_CANT), 0.0)
		from_inboard = from_inboard and (s.barrel as Transform3D).basis.y.dot(inboard) < -0.2
	_check("across the travel on both engines every pin is in its hole (worst %.7f): the fin on its hinge line, the cylinder on the bracket's pin, the rod on the lug's pin and down the bore" % worst, worst < 1e-5)
	_check("the ram strokes %.3f m to lay the fin out: the rod shows %.3f to %.3f m, its piston stays %.3f to %.3f m up a %.2f m cylinder, and the ram only ever lengthens as the fin lays out" % [
		float(showing[1]) - float(showing[0]), showing[0], showing[1], piston[0], piston[1], Shrike.RAM_BARREL],
		float(showing[0]) > 0.10 and float(piston[0]) > 0.08 and float(piston[1]) < Shrike.RAM_BARREL - 0.08 and grows and float(showing[1]) - float(showing[0]) > 0.12)
	_check("the port engine's is the starboard's in a mirror (%.7f), and the ram reaches the fin from its inboard side at every angle" % mirrored, mirrored < 1e-5 and from_inboard)


## The mesh's points (its first surface).
static func _points(mesh: Mesh) -> PackedVector3Array:
	return mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]


## The middle of the mesh's points that lie within `r` of the line through `at` along z, between z0 and z1,
## and how many there are.
static func _round_pin(mesh: Mesh, at: Vector3, r: float, z0: float, z1: float) -> Array:
	var sum := Vector2.ZERO
	var n := 0
	for p in _points(mesh):
		if p.z >= z0 and p.z <= z1 and Vector2(p.x - at.x, p.y - at.y).length() <= r:
			sum += Vector2(p.x, p.y)
			n += 1
	return [sum / maxf(1.0, n), n]


func _the_parts() -> void:
	var ram: Mesh = Shrike.part(&"FinRam")
	var rod: Mesh = Shrike.part(&"FinRamRod")
	var rb: AABB = ram.get_aabb()
	var db: AABB = rod.get_aabb()
	_check("the cylinder runs %.3f m from its pin to its gland and the rod %.3f m from its pin to its piston, each about its own pin (the cylinder %.3f m across, the rod's piston %.3f)" % [rb.end.y, db.end.y, rb.size.z, db.size.z],
		absf(rb.end.y - Shrike.RAM_BARREL) < 1e-3 and absf(db.end.y - Shrike.RAM_ROD) < 1e-3 and absf(rb.position.z + rb.end.z) < 1e-3 and rb.position.y > -0.06 and db.position.y > -0.06)
	var seen := []
	var ok := true
	for k in 2:
		var out := -1.0 if k == 0 else 1.0
		var fin: Mesh = Shrike.part(&"PortFin" if k == 0 else &"StarboardFin")
		var body: Mesh = Shrike.part(&"Port" if k == 0 else &"Starboard")
		var z: float = Shrike.RAM_PIN.z
		var lug: Array = _round_pin(fin, Vector3(out * Shrike.RAM_PIN.x, Shrike.RAM_PIN.y, 0.0), 0.029, z - 0.09, z + 0.09)      # (the pins are 26 mm in radius; their washers, 38 mm, are left out)
		var bracket: Array = _round_pin(body, Vector3(out * Shrike.RAM_BASE.x, Shrike.RAM_BASE.y, 0.0), 0.029, z - 0.09, z + 0.09)
		var saddle: Array = _round_pin(body, Vector3(out * Shrike.FIN_HINGE.x, Shrike.FIN_HINGE.y, 0.0), 0.092, -0.6, 1.5)
		var tube: Array = _round_pin(fin, Vector3.ZERO, 0.06, -0.6, 1.5)
		var off_lug: float = (lug[0] as Vector2).distance_to(Vector2(out * Shrike.RAM_PIN.x, Shrike.RAM_PIN.y))
		var off_bracket: float = (bracket[0] as Vector2).distance_to(Vector2(out * Shrike.RAM_BASE.x, Shrike.RAM_BASE.y))
		var tip: Vector3 = Shrike.fin_tip_local(out)
		var fb: AABB = fin.get_aabb().grow(0.3)
		seen.append("%s: lug's pin %.4f m off, bracket's %.4f m off, %d points of hinge tube and %d of saddle, the engine now %.2f m tall" % ["port" if k == 0 else "starboard", off_lug, off_bracket, tube[1], saddle[1], body.get_aabb().end.y])
		ok = ok and int(lug[1]) >= 12 and off_lug < 0.002 and int(bracket[1]) >= 12 and off_bracket < 0.002 and int(tube[1]) >= 14 and int(saddle[1]) >= 32
		ok = ok and body.get_aabb().end.y < 0.75 and fb.has_point(tip) and fin.get_aabb().end.y > 0.9
	_check("the authored parts are where the numbers say (%s)" % "; ".join(seen), ok)


## A view's fins as they stand: [worst fit, cant read off the starboard fin's own turn].
func _standing(craft) -> Array:
	var worst := 0.0
	for k in 2:
		var parts: Array = craft.fin_parts[k]
		worst = maxf(worst, _fit(-1.0 if k == 0 else 1.0, (parts[0] as Node3D).transform, (parts[1] as Node3D).transform, (parts[2] as Node3D).transform))
	var turned: float = Shrike.FIN_CANT - (craft.fin_parts[1][0] as Node3D).transform.basis.get_euler().z
	return [worst, turned]


func _set_speed(sim, mph: float) -> void:
	for body in [sim.eL, sim.eR, sim.pod]:
		body.vx = mph * MPH * cos(sim.pod.th)
		body.vy = mph * MPH * sin(sim.pod.th)


func _run() -> void:
	_on_paper()
	_the_parts()
	var prefs_before := FileAccess.get_file_as_string(Cockpit.PREFS) if FileAccess.file_exists(Cockpit.PREFS) else ""
	var had_prefs := FileAccess.file_exists(Cockpit.PREFS)
	View.track_override = "range"
	View.job_override = "none"
	View.vehicle_override = "shrike"
	View.best_dir = OS.get_user_data_dir().path_join("test_shrike_fins_")
	var v = View.new()
	root.add_child(v)
	await process_frame
	v.set_process(false)
	var craft = v.craft
	var idle := {"thrL": 0.0, "thrR": 0.0, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": true}
	v.inp = idle
	v._sync_craft(FRAME)
	var at: Array = _standing(craft)
	var lamp: Node3D = (craft.fin_parts[1][0] as Node3D).get_node_or_null("FinLamp")
	var strobe: Node3D = craft.strobes[1]
	var tip_now: Vector3 = (craft.fin_parts[1][0] as Node3D).transform * Shrike.fin_tip_local(1.0)
	_check("a Shrike standing on the Range (%s): two fins on their hinges, standing tall at %.1f deg from upright, every pin in its hole (%.7f); the tip's nav lamp and strobe are the fin's own (the strobe %.3f m from the tip)" % [
		v.sim.P.vehicle, rad_to_deg(at[1]), at[0], strobe.position.distance_to(Shrike.fin_tip_local(1.0))],
		v.sim.P.vehicle == "shrike" and craft.fin_parts.size() == 2 and absf(float(at[1]) - Shrike.FIN_REST) < 1e-4 and float(at[0]) < 1e-5 and lamp != null
		and strobe.get_parent() == craft.fin_parts[1][0] and strobe.position.distance_to(Shrike.fin_tip_local(1.0)) < 1e-4 and craft.light_meshes.has(lamp)
		and tip_now.y > Shrike.fin_tip(1.0).y + 0.15 and tip_now.x < Shrike.fin_tip(1.0).x - 0.2)
	# held at each speed in turn: the fins go to the law's angle, no faster than the ram strokes
	var worst := 0.0
	var fastest := 0.0
	var reads := []
	var settled := true
	var rods := []
	for mph in [1000.0, 2500.0, 3500.0, 5000.0, 7500.0, 2500.0, 0.0]:
		_set_speed(v.sim, mph)
		for frame in 300:
			var was: float = craft.fin_cant
			v._sync_craft(FRAME)
			fastest = maxf(fastest, absf(float(craft.fin_cant) - was) / FRAME)
			worst = maxf(worst, _standing(craft)[0])
		at = _standing(craft)
		settled = settled and absf(float(at[1]) - Shrike.fin_cant(mph)) < 1e-4 and absf(float(craft.fin_cant) - Shrike.fin_cant(mph)) < 1e-6
		reads.append("%d: %.1f" % [int(mph), rad_to_deg(at[1])])
		rods.append("%.3f" % craft.fin_ram[1])
	_check("held at each speed the fins go to the law's angle (mph: deg from upright; %s; the rod showing %s m), every pin in its hole on every frame (%.7f), never faster than the ram strokes (%.3f of %.2f rad/s)" % [
		", ".join(reads), ", ".join(rods), worst, fastest, Shrike.FIN_SLEW], settled and worst < 1e-5 and fastest <= Shrike.FIN_SLEW + 1e-4 and fastest > 0.5 * Shrike.FIN_SLEW)
	# under her own power: flat out from rest, the fins start to lay out as she gathers speed, both the same
	_set_speed(v.sim, 0.0)
	for frame in 300:
		v._sync_craft(FRAME)
	var began: float = craft.fin_cant
	var never_back := true
	var together := true
	var flown_worst := 0.0
	var gas := {"thrL": 1.0, "thrR": 1.0, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": true}
	v.inp = gas
	for frame in 600:
		for sub in 4:
			v.sim.step(gas, DT)
		v.sim.events.clear()
		var was: float = craft.fin_cant
		v._sync_craft(FRAME)
		never_back = never_back and float(craft.fin_cant) >= was - 1e-9
		together = together and absf(float(craft.fin_ram[0]) - float(craft.fin_ram[1])) < 1e-6
		flown_worst = maxf(flown_worst, _standing(craft)[0])
	var mph_now: float = Vector2(v.sim.pod.vx, v.sim.pod.vy).length() / MPH
	_check("flown flat out for five seconds from rest (to %d mph): the fins lay out from %.1f to %.1f deg and never back, the two rams stroke together, every pin in its hole (%.7f)" % [
		int(mph_now), rad_to_deg(began), rad_to_deg(craft.fin_cant), flown_worst],
		mph_now > 400.0 and float(craft.fin_cant) > began + 0.01 and never_back and together and flown_worst < 1e-5)
	v.queue_free()
	await process_frame
	# the Phaethon has none of it
	View.vehicle_override = "phaethon"
	var p = View.new()
	root.add_child(p)
	await process_frame
	p.set_process(false)
	p.inp = idle
	p._sync_craft(FRAME)
	_check("a Phaethon has no such fins: no hinged parts, its strobes on its engines as they were",
		p.sim.P.vehicle == "phaethon" and p.craft.fin_parts.is_empty() and p.craft.strobes[0].get_parent() == p.craft.engines[0] and not p.craft.engines[0].has_node("ShrikeFin"))
	p.queue_free()
	await process_frame
	View.vehicle_override = ""
	if had_prefs:
		var out := FileAccess.open(Cockpit.PREFS, FileAccess.WRITE)
		out.store_string(prefs_before)
		out.close()
	elif FileAccess.file_exists(Cockpit.PREFS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Cockpit.PREFS))
	var good: bool = fails == 0 and passed == 10
	print("SHRIKE FINS ", "PASS" if good else "FAIL (%d failed, %d passed)" % [fails, passed])
	quit(0 if good else 1)
