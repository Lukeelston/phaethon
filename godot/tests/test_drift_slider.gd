## The drift slider (vr/drift_slider.gd, vr/vr_cockpit.gd; Luke, 2026-11-23, from the seat: "add a physical
## slider or knob in the cockpit to adjust the amount of drift in real time"): how far the cockpit steps
## out in a turn, set by hand in flight, from none to two and a half times what it did before the slider.
##   where        a rail on the left console's inboard shoulder, behind the SLIDE / GRIP switch: its slot
##                fore and aft, forward for more; from the seat it reads left to right, OFF .. DRIFT .. MAX,
##                upright and turned toward the eye, under a ramp that grows toward MAX; an arm's reach
##                from the left shoulder.
##   by hand      a tip rested on the knob takes hold of it, and then it goes with the hand: more forward,
##                less aft, stopped at both ends, falling into the notch at the amount the cockpit had
##                before the slider; lifted off the rail it is let go, and what it was left at is saved.
##   by accident  a hand going by takes nothing, nor a second hand while the first has it, nor a tracking
##                jump; a hand at the knob anywhere along the slot is outside the box where the SLIDE
##                switch is thrown, a hand throwing that switch does not move the slider, and a hand
##                working the slider does not throw the switch.
##   the amount   the cockpit's slide in a hard turn is the amount times what it was (none at OFF); in the
##                notch it is, to the last bit, what the cockpit did before there was a slider, through a
##                hard left, a release and a hard right; at GRIP there is none whatever the slider says;
##                turned down in mid-slide the cockpit comes back no faster than a slide moves.
##   saved        with the other settings, and a cockpit built afterwards stands its knob there.
## --headless --xr-mode off --audio-driver Dummy -s res://tests/test_drift_slider.gd -- --mute
## Prints DRIFT SLIDER PASS. (tests/test_cockpit_clash.gd holds the rail clear of the levers, the switch
## and the map, and in sight from the seat.)
extends SceneTree

const View := preload("res://view/craft_view.gd")
const Cockpit := preload("res://vr/vr_cockpit.gd")
const Drift := preload("res://vr/drift_slider.gd")
const Switch := preload("res://vr/mode_switch.gd")
const Model := preload("res://view/craft_model.gd")
const FRAME := 1.0 / 90.0
const SPEED := 1500.0      # m/s along the engines' heading, for a cornering load (tests/test_slide_feel.gd's)
var v
var failures := 0
var checks := 0
var hand: Node3D
var second: Node3D


func _initialize() -> void:
	View.track_override = "range"
	View.job_override = "none"
	View.best_dir = OS.get_user_data_dir().path_join("test_drift_slider_")
	Cockpit.camera = "cockpit"
	Cockpit._camera_loaded = true      # the pilot's saved choices stay out of this (the slide's own is read: there is none)
	Cockpit._nose_loaded = true
	Cockpit._startup_loaded = true
	Cockpit._map_loaded = true
	Cockpit._school_loaded = true
	Cockpit.cold_start = false
	Cockpit.school = false
	_run.call_deferred()


func _check(label: String, passed: bool) -> void:
	checks += 1
	print(("PASS " if passed else "FAIL ") + label)
	failures += int(not passed)


func _saved() -> Dictionary:
	var d = JSON.parse_string(FileAccess.get_file_as_string(Cockpit.PREFS)) if FileAccess.file_exists(Cockpit.PREFS) else {}
	return d if d is Dictionary else {}


## A frame of a hand at the slider, its tip at `at` (panel metres), through the cockpit's own handling of
## what that did. -> what it did.
func _poke(h: Node3D, at: Vector3, dt := FRAME) -> String:
	h.global_position = (v.drift_slider as Node3D).global_transform * at - h.global_basis * Drift.TIP
	var did: String = v.drift_slider.poke(h, dt)
	v._work_slider(did)
	return did


## Rest a hand's tip on the knob for up to `seconds`. -> how long until it had it, s (-1: it never did).
func _rest_on(h: Node3D, seconds := 0.6) -> float:
	var at: Vector3 = v.drift_slider.cap_at()
	for k in int(seconds / FRAME):
		if _poke(h, at) == "held":
			return (k + 1) * FRAME
	return -1.0


## Carry a tip from one place to another (panel metres) at `speed` m/s. -> everything that happened on the way.
func _carry(h: Node3D, from: Vector3, to: Vector3, speed := 0.2) -> Array:
	var did := []
	var steps := maxi(1, int(ceil(from.distance_to(to) / (speed * FRAME))))
	for k in range(1, steps + 1):
		var what := _poke(h, from.lerp(to, float(k) / steps))
		if what != "":
			did.append(what)
	return did


## Turn the engines at the rate that makes this cornering load, g (+ a left turn).
func _load(g: float) -> void:
	var sim = v.sim
	for b in sim.bodies:
		b.vx = SPEED * cos(sim.pair_th)
		b.vy = SPEED * sin(sim.pair_th)
	sim.eL.w = g * 9.81 / SPEED
	sim.eR.w = sim.eL.w


func _still() -> void:
	_load(0.0)
	v._slide = 0.0
	v._slide_rate = 0.0
	v._slide_load = 0.0
	v._slide_lean = 0.0
	v._slide_ask = 0.0
	v._slide_stop = 0.0


## The cockpit's slide held in a hard left turn (30 g for 2 s), degrees, and the fastest it moved, degrees a second.
func _held_slide() -> Vector2:
	_still()
	_load(30.0)
	var fastest := 0.0
	var was := 0.0
	for k in int(2.0 / FRAME):
		var now: float = v._ease_slide(FRAME)
		fastest = maxf(fastest, absf(now - was) / FRAME)
		was = now
	return Vector2(rad_to_deg(was), rad_to_deg(fastest))


# The slide by its own rule with no amount in it, written out again here to compare with: the cornering load
# through the engines' lean (CraftModel.ease_bank), the share of its way that lean covers each frame, and the spring.
# (Until push 42 it read the load through 0.18 s of smoothing; that led the engines, and he said so.)
var _was_lean := 0.0
var _was_lat := 0.0
var _was_ask := 0.0
var _was_slide := 0.0
var _was_rate := 0.0
func _slide_as_it_was(delta: float, load: float, on: bool) -> float:
	var lean_was := _was_lean
	var leaned: Array = Model.ease_bank(_was_lean, _was_lat, load, clampf(delta, 0.0, 0.05))
	_was_lean = leaned[0]
	_was_lat = leaned[1]
	var way: float = Model.BANK_MAX * tanh(_was_lat / Model.BANK_G) - lean_was
	var covered: float = clampf((_was_lean - lean_was) / way, 0.0, 1.0) if absf(way) > 0.00001 else 1.0
	_was_ask += (signf(_was_lat) * smoothstep(Cockpit.SLIDE_LOAD.x, Cockpit.SLIDE_LOAD.y, absf(_was_lat)) - _was_ask) * covered
	var asked := _was_ask
	var target := asked * Cockpit.SLIDE_MAX if on else 0.0
	var w := TAU * Cockpit.SLIDE_HZ
	var remaining := clampf(delta, 0.0, 0.05)
	while remaining > 0.000001:
		var step := minf(remaining, 1.0 / 240.0)
		_was_rate = clampf(_was_rate + (w * w * (target - _was_slide) - 2.0 * Cockpit.SLIDE_ZETA * w * _was_rate) * step, -Cockpit.SLIDE_RATE, Cockpit.SLIDE_RATE)
		_was_slide = clampf(_was_slide + _was_rate * step, -Cockpit.SLIDE_MAX * 1.25, Cockpit.SLIDE_MAX * 1.25)
		remaining -= step
	return _was_slide


func _cockpit() -> void:
	v = Cockpit.new()
	root.add_child(v)
	await process_frame
	v.set_process(false)


func _run() -> void:
	var prefs_before := FileAccess.get_file_as_string(Cockpit.PREFS) if FileAccess.file_exists(Cockpit.PREFS) else ""
	if prefs_before != "":      # a pilot with nothing saved: what he gets
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Cockpit.PREFS))
	Cockpit._slide_loaded = false
	Cockpit.slide_feel = true
	Cockpit.slide_amount = 1.0
	await _cockpit()
	var s = v.drift_slider
	_check("the cockpit has its drift slider, and with nothing saved it stands in the notch: the amount the cockpit had before the slider (%.2f), the SLIDE switch up" % Cockpit.slide_amount,
		s != null and s.get_script() == Drift and s.get_parent() == v.shell and Cockpit.slide_amount == Drift.STANDARD and s.amount == Drift.STANDARD and Cockpit.slide_feel
		and Drift.STANDARD == 1.0 and Drift.AMOUNT_MAX == 2.5)
	if s == null:
		print("DRIFT SLIDER FAIL (no slider)")
		quit(1)
		return
	v.drift_slider.show_state(true, 1.0)
	hand = Node3D.new()
	root.add_child(hand)
	second = Node3D.new()
	root.add_child(second)

	# ---- where it is, and which way is more
	var cabin: Transform3D = v.shell.global_transform      # the cabin's own frame: EYE and the furniture are in it
	var to_cabin := cabin.affine_inverse()
	var sw: Node3D = v.slide_switch
	var off_end: Vector3 = to_cabin * (s.global_transform * Vector3(Drift.place(0.0), 0.0, 0.0))
	var max_end: Vector3 = to_cabin * (s.global_transform * Vector3(Drift.place(Drift.AMOUNT_MAX), 0.0, 0.0))
	var notch: Vector3 = to_cabin * (s.global_transform * Vector3(Drift.place(Drift.STANDARD), 0.0, 0.0))
	var along: Vector3 = (max_end - off_end).normalized()
	_check("it is on the left console's inboard shoulder behind the SLIDE switch (its slot from %.3f m to %.3f m aft of the switch, %.3f m inboard of it, %.0f mm of travel), fore and aft, and forward is more (the slot's line is %.1f degrees off the cockpit's nose)" % [
			off_end.z - (to_cabin * sw.global_position).z, max_end.z - (to_cabin * sw.global_position).z, off_end.x - (to_cabin * sw.global_position).x, off_end.distance_to(max_end) * 1000.0, rad_to_deg(along.angle_to(Vector3.FORWARD))],
		off_end.x < -0.5 and off_end.x > -0.6 and max_end.z > (to_cabin * sw.global_position).z + 0.2 and off_end.z > max_end.z and along.angle_to(Vector3.FORWARD) < deg_to_rad(0.5)
		and is_equal_approx(off_end.distance_to(max_end), Drift.TRAVEL) and notch.z < off_end.z and notch.z > max_end.z)
	var eye: Vector3 = Cockpit.EYE      # (cabin metres: where the pilot's eyes are)
	var shoulder := eye + Vector3(-0.18, -0.2, 0.05)
	var words := []
	var upright := true
	var facing := 90.0
	var legends := {}
	for label: Label3D in s.find_children("*", "Label3D", true, false):
		words.append(label.text)
		var at: Vector3 = to_cabin * label.global_position
		legends[label.text] = at
		var look := (at - eye).normalized()
		var right := look.cross(Vector3.UP).normalized()       # the pilot's right as he looks at it, his head level
		var up := right.cross(look).normalized()
		var b: Basis = (to_cabin * label.global_transform).basis.orthonormalized()
		upright = upright and b.x.dot(right) > 0.7 and b.y.dot(up) > 0.5
		facing = minf(facing, 90.0 - rad_to_deg(b.z.angle_to(-look)))
	var ramp := (s.get_node("ramp") as MeshInstance3D).mesh.get_aabb()
	var faces: PackedVector3Array = (s.get_node("ramp") as MeshInstance3D).mesh.get_faces()
	var tall := [0.0, 0.0]      # the ramp's height at its OFF end and at its MAX end
	for p in faces:
		if p.x < Drift.place(0.0) + 0.001:
			tall[0] = maxf(tall[0], p.y - ramp.position.y)
		if p.x > Drift.place(Drift.AMOUNT_MAX) - 0.001:
			tall[1] = maxf(tall[1], p.y - ramp.position.y)
	var look_mid := ((off_end + max_end) * 0.5 - eye).normalized()
	var reads: float = (max_end - off_end).dot(look_mid.cross(Vector3.UP).normalized())
	_check("its legends say which way is more: %s from the aft end to the forward one, under a ramp that grows from %.1f mm at OFF to %.1f mm at MAX; from the seat the slot runs left to right (%.0f mm of it across his view), the words upright and turned toward him (their faces %.0f degrees or more from edge-on)" % [
			words, tall[0] * 1000.0, tall[1] * 1000.0, reads * 1000.0, facing],
		words == ["OFF", "DRIFT", "MAX"] and (legends["OFF"] as Vector3).z > (legends["DRIFT"] as Vector3).z and (legends["DRIFT"] as Vector3).z > (legends["MAX"] as Vector3).z
		and absf((legends["OFF"] as Vector3).z - off_end.z) < 0.004 and absf((legends["MAX"] as Vector3).z - max_end.z) < 0.004
		and tall[1] > tall[0] * 4.0 and tall[1] > 0.006 and reads > 0.1 and upright and facing > 55.0)
	var cap: Vector3 = to_cabin * (s.global_transform * (s.cap_at() as Vector3))
	var seen := cap - eye
	_check("it is an arm's reach from the left shoulder (%.2f m to the knob in its notch, %.2f m to the OFF end, %.2f m to MAX), %.2f m from the eye, %.0f degrees left of ahead and %.0f degrees down in the cabin" % [
			shoulder.distance_to(cap), shoulder.distance_to(off_end), shoulder.distance_to(max_end), seen.length(), rad_to_deg(atan2(-seen.x, -seen.z)), rad_to_deg(asin(-seen.y / seen.length()))],
		shoulder.distance_to(cap) < 0.6 and shoulder.distance_to(off_end) < 0.6 and shoulder.distance_to(max_end) < 0.6 and seen.length() > 0.5)

	# ---- by accident: a hand going by, and the SLIDE switch's box
	var by := _carry(hand, s.cap_at() + Vector3(-0.2, 0.0, 0.01), s.cap_at() + Vector3(0.2, 0.0, 0.01), 0.6)
	var by_across := _carry(hand, s.cap_at() + Vector3(0.0, -0.2, 0.0), s.cap_at() + Vector3(0.0, 0.2, 0.0), 0.6)
	var by_slowly := _carry(hand, s.cap_at() + Vector3(-0.2, 0.0, 0.01), s.cap_at() + Vector3(0.2, 0.0, 0.01), 0.25)      # (a hand reaching past it for the SLIDE switch)
	_check("a hand going by through the knob takes nothing, along the slot or across it, nor one reaching slowly past it at 0.25 m/s (%s, %s, %s): it stays in its notch" % [by, by_across, by_slowly],
		by.is_empty() and by_across.is_empty() and by_slowly.is_empty() and s.held_by == null and s.amount == Drift.STANDARD)
	var into_switch: Transform3D = sw.global_transform.affine_inverse() * s.global_transform
	var in_box := 0
	var nearest := INF
	for a in [0.0, 0.5, 1.0, 1.25, 1.5, 2.0, Drift.AMOUNT_MAX]:
		var middle := Vector3(Drift.place(a), 0.0, Drift.CAP_Z)
		for i in 13:
			for j in 24:
				var lat := -PI / 2.0 + PI * i / 12.0
				var lon := TAU * j / 24.0
				var q: Vector3 = into_switch * (middle + Drift.HOLD_R * Vector3(cos(lat) * cos(lon), cos(lat) * sin(lon), sin(lat)))
				in_box += int(absf(q.x) < Switch.ZONE.x and absf(q.y) < Switch.ZONE.y and q.z > -0.01 and q.z < Switch.ZONE.z)
				# how far outside the box this place is (0 inside)
				var outside := Vector3(maxf(absf(q.x) - Switch.ZONE.x, 0.0), maxf(absf(q.y) - Switch.ZONE.y, 0.0), maxf(maxf(-0.01 - q.z, q.z - Switch.ZONE.z), 0.0)).length()
				nearest = minf(nearest, outside)
	_check("a tip that can take the knob, anywhere along the slot, is outside the box where the SLIDE switch is thrown (%d of the places it could be are in it; the nearest %.0f mm from it)" % [in_box, nearest * 1000.0], in_box == 0 and nearest > 0.01)
	# a hand throws the SLIDE switch (down, a rest, up again) with the slider looking on
	var thrown := []
	var slid := []
	for push in [[0.03, 0.0], [0.0, 0.0], [0.0, 0.03]]:
		for y: float in push:
			hand.global_position = sw.global_transform * Vector3(0.0, y, 0.05) - hand.global_basis * Switch.TIP
			var answer: String = sw.poke(hand, 1.0 / 60.0 if push[0] != push[1] else 1.1)
			if answer != "":
				thrown.append(answer)
			var did: String = s.poke(hand, 1.0 / 60.0)
			if did != "":
				slid.append(did)
	_check("a hand throwing the SLIDE switch (%s) does not move the slider (%s)" % [thrown, slid], thrown == ["grip", "slide"] and slid.is_empty() and s.amount == Drift.STANDARD and s.held_by == null)
	sw.down = false
	sw.poke(hand, 1.1)

	# ---- by hand
	var took := _rest_on(hand)
	_check("a tip rested on the knob has taken hold of it in %.2f s" % took, took > 0.1 and took < 0.3 and s.held_by == hand)
	_check("a second hand cannot take it while the first has it", _rest_on(second, 0.4) < 0.0 and s.held_by == hand)
	var start: Vector3 = s.cap_at()
	var did := _carry(hand, start, start + Vector3(0.03, 0.0, 0.0))
	_check("pushed 30 mm forward it goes with the hand: %.3f, and the cockpit's amount with it (%.3f), the hand ticked as it crossed each detent (%s)" % [s.amount, Cockpit.slide_amount, did],
		absf(s.amount - (Drift.STANDARD + 0.03 / Drift.TRAVEL * Drift.AMOUNT_MAX)) < 0.01 and Cockpit.slide_amount == s.amount and did.count("tick") >= 2 and not did.has("let_go"))
	var past: float = Drift.place(Drift.AMOUNT_MAX) - Drift.place(Drift.STANDARD) + 0.035      # (35 mm past the slot's forward end, wherever the notch is along it)
	did = _carry(hand, start + Vector3(0.03, 0.0, 0.0), start + Vector3(past, 0.0, 0.0))
	_check("pushed on past the end of the slot it stops at the most, %.2f times what it was (%s)" % [s.amount, did], s.amount == Drift.AMOUNT_MAX and Cockpit.slide_amount == Drift.AMOUNT_MAX and did.has("end") and s.held_by == hand)
	var before_jump: float = s.amount
	_poke(hand, start + Vector3(past - 0.06, 0.0, 0.0))      # (0.06 m in a frame: 5.4 m/s, no hand)
	_check("a tracking jump does not move it (%.2f)" % s.amount, s.amount == before_jump and s.held_by == hand)
	# (it is held now from where the tip jumped to: the knob at the slot's forward end, the tip 60 mm short of where it was)
	var here := start + Vector3(past - 0.06, 0.0, 0.0)
	var to_notch: float = Drift.place(Drift.STANDARD) - Drift.place(Drift.AMOUNT_MAX)
	did = _carry(hand, here, here + Vector3(to_notch + 0.002, 0.0, 0.0))
	_check("pulled back to within %.0f mm of the notch it falls in: exactly %.3f (%s)" % [Drift.NOTCH / Drift.AMOUNT_MAX * Drift.TRAVEL * 1000.0, s.amount, did],
		s.amount == Drift.STANDARD and Cockpit.slide_amount == 1.0 and did.has("notch"))
	did = _carry(hand, here + Vector3(to_notch + 0.002, 0.0, 0.0), here + Vector3(-Drift.TRAVEL - 0.02, 0.0, 0.0))
	_check("pulled all the way aft it stops at none (%.2f; %s)" % [s.amount, did], s.amount == 0.0 and Cockpit.slide_amount == 0.0 and did.has("end") and did.has("tick"))
	var half: float = Drift.place(0.5) - Drift.place(0.0)
	here = here + Vector3(-Drift.TRAVEL - 0.02, 0.0, 0.0)
	_carry(hand, here, here + Vector3(0.02 + half, 0.0, 0.0))
	var left_at: float = s.amount
	var unsaved: bool = not _saved().has("slide_amount")
	did = _carry(hand, here + Vector3(0.02 + half, 0.0, 0.0), here + Vector3(0.02 + half, 0.0, 0.12))
	_check("lifted off the rail it is let go (%s), where it was left (%.3f), and that is saved with the other settings (\"slide_amount\": %s; it was not written while the hand had it: %s)" % [did, s.amount, _saved().get("slide_amount", "nothing"), unsaved],
		did == ["let_go"] and s.held_by == null and s.amount == left_at and absf(left_at - 0.5) < 0.02 and unsaved and absf(float(_saved().get("slide_amount", -1.0)) - left_at) < 0.001)

	# ---- the amount: what the cockpit does with it
	var held := {}
	for a in [0.0, 0.5, 1.0, Drift.AMOUNT_MAX]:
		Cockpit.slide_amount = a
		held[a] = _held_slide()
	var full := rad_to_deg(Cockpit.SLIDE_MAX)
	_check("in a hard left turn (30 g) the cockpit steps out by the amount: %.2f degrees at OFF, %.2f at a half, %.2f in the notch (as it was: %.1f), %.2f at the most; never faster than %.0f degrees a second (%.1f)" % [
			(held[0.0] as Vector2).x, (held[0.5] as Vector2).x, (held[1.0] as Vector2).x, full, (held[Drift.AMOUNT_MAX] as Vector2).x, rad_to_deg(Cockpit.SLIDE_RATE), (held[Drift.AMOUNT_MAX] as Vector2).y],
		(held[0.0] as Vector2).x == 0.0 and absf((held[0.5] as Vector2).x - 0.5 * full) < 0.15 and absf((held[1.0] as Vector2).x - full) < 0.15 and absf((held[Drift.AMOUNT_MAX] as Vector2).x - Drift.AMOUNT_MAX * full) < 0.2
		and (held[Drift.AMOUNT_MAX] as Vector2).y <= rad_to_deg(Cockpit.SLIDE_RATE) * 1.02)
	# in the notch: the same as before there was a slider, to the last bit
	Cockpit.slide_amount = 1.0
	_still()
	_was_lean = 0.0
	_was_lat = 0.0
	_was_ask = 0.0
	_was_slide = 0.0
	_was_rate = 0.0
	var differ := 0
	var frames := 0
	var most := 0.0
	var t := 0.0
	while t < 10.0:
		var g := 30.0 if t < 2.0 else (0.0 if t < 3.0 else (-30.0 if t < 5.0 else (30.0 if t < 5.6 else (12.0 * sin(TAU * 0.7 * t) if t < 8.0 else 0.0))))
		_load(g)
		var load: float = v.turn_load()
		var now: float = v._ease_slide(FRAME)
		var then := _slide_as_it_was(FRAME, load, true)
		differ += int(now != then)
		most = maxf(most, absf(now))
		frames += 1
		t += FRAME
	_check("in the notch the cockpit slides exactly by the slide's own rule, with no amount in it: through a hard left, a release, a hard right, a flick back and a weave, %d frames, %d in which it differed by a bit (the most it stepped out: %.2f degrees, into the overshoot's stop at %.2f)" % [
			frames, differ, rad_to_deg(most), full * 1.25], differ == 0 and frames > 800 and most > Cockpit.SLIDE_MAX * 1.02)      # (it overshoots less now that it goes out with the engines' lean: 4% where it was 14%)
	# at GRIP: none, whatever the slider says
	Cockpit.slide_amount = Drift.AMOUNT_MAX
	Cockpit.slide_feel = false
	var gripped := _held_slide()
	Cockpit.slide_feel = true
	_check("with the switch at GRIP there is none of it, whatever the slider says (%.4f degrees at the most)" % gripped.x, gripped.x == 0.0 and gripped.y == 0.0)
	# turned down in mid-slide
	Cockpit.slide_amount = Drift.AMOUNT_MAX
	_held_slide()
	var out_at: float = v._slide
	Cockpit.slide_amount = 0.5
	var fastest := 0.0
	var was: float = v._slide
	for k in int(1.5 / FRAME):
		var now: float = v._ease_slide(FRAME)
		fastest = maxf(fastest, absf(now - was) / FRAME)
		was = now
	_check("turned down from the most to a half in the middle of that turn, the cockpit comes back from %.2f to %.2f degrees no faster than a slide moves (%.1f degrees a second at the most; %.0f allowed)" % [
			rad_to_deg(out_at), rad_to_deg(was), rad_to_deg(fastest), rad_to_deg(Cockpit.SLIDE_RATE)],
		out_at > Cockpit.SLIDE_MAX * 1.4 and absf(rad_to_deg(was) - 0.5 * full) < 0.15 and fastest <= Cockpit.SLIDE_RATE * 1.02)
	_still()

	# ---- behind the engines, not ahead of them (Luke, 2026-11-23: "I think the cockpit lists before the engines
	# do. It feels like the pilot leads the engines."), and nose-down into the corner ("the nose needs to tilt
	# down more in a drift - The pilot should be able to still see the corner they're drifting into")
	Cockpit.slide_amount = Drift.AMOUNT_MAX
	_still()
	_load(30.0)
	var lean := 0.0
	var lean_lat := 0.0
	var lean_end: float = Model.BANK_MAX * tanh(30.0 / Model.BANK_G)
	var slide_end: float = Cockpit.SLIDE_MAX * Drift.AMOUNT_MAX
	var lean_half := -1.0
	var slide_half := -1.0
	var slide_at_lean_half := 0.0
	var ahead := 0
	for k in int(2.0 / FRAME):
		var e: Array = Model.ease_bank(lean, lean_lat, 30.0, FRAME)
		lean = e[0]
		lean_lat = e[1]
		var out: float = v._ease_slide(FRAME)
		ahead += int(out / slide_end > lean / lean_end + 0.001 and lean / lean_end < 0.95)      # (settling, both are at their ends)
		if lean_half < 0.0 and lean >= 0.5 * lean_end:
			lean_half = (k + 1) * FRAME
			slide_at_lean_half = out / slide_end
		if slide_half < 0.0 and out >= 0.5 * slide_end:
			slide_half = (k + 1) * FRAME
	_check("into a hard left turn (30 g, the slider at its stop) the engines lean first: they are half over at %.2f s, when the cockpit is %.0f%% of the way out; it is half out at %.2f s; frames in which it was further along than they were: %d" % [
			lean_half, 100.0 * slide_at_lean_half, slide_half, ahead],
		lean_half > 0.0 and slide_half > lean_half + 0.05 and slide_half < lean_half + 0.35 and slide_at_lean_half < 0.4 and ahead == 0)
	var pose_none: Transform3D = Cockpit.pod_pose(Cockpit.drift_pitch_for(0.0))
	var pose_full: Transform3D = Cockpit.pod_pose(Cockpit.drift_pitch_for(Cockpit.SLIDE_MAX))
	var pose_most: Transform3D = Cockpit.pod_pose(Cockpit.drift_pitch_for(slide_end))
	var down := func(pose: Transform3D) -> float: return rad_to_deg(asin(clampf((pose.basis * Vector3.FORWARD).y, -1.0, 1.0))) * -1.0
	v._drift_pitch = Cockpit.drift_pitch_for(slide_end)
	v._place_shell()
	var hooked: bool = v.craft != null and v.craft.pod_frame_pose.is_equal_approx(pose_most) and (v.shell.transform.basis as Basis).is_equal_approx(pose_most.basis)
	v._drift_pitch = 0.0
	v._place_shell()
	_check("the pod's nose goes down with the slide, about the pilot's eye: %.1f degrees with none (as it stood), %.1f at the notch's full slide, %.1f at the stop's (no further than %.0f more); the shell and the tow links' hooks go with it (%s), and it is back with the slide" % [
			down.call(pose_none), down.call(pose_full), down.call(pose_most), rad_to_deg(Cockpit.DRIFT_PITCH_MAX), hooked],
		pose_none.is_equal_approx(Cockpit.pod_pose()) and absf(down.call(pose_full) - rad_to_deg(Cockpit.POD_PITCH + Cockpit.SLIDE_MAX * Cockpit.DRIFT_PITCH)) < 0.01
		and absf(down.call(pose_most) - rad_to_deg(Cockpit.POD_PITCH + Cockpit.DRIFT_PITCH_MAX)) < 0.01 and (pose_most * eye).is_equal_approx(eye) and hooked
		and (v.shell.transform.basis as Basis).is_equal_approx(Cockpit.pod_pose().basis))
	Cockpit.slide_amount = 1.0
	_still()

	# ---- shown, and saved
	s.amount = 0.75
	s.show_state(true, 1.0)
	var lit: float = s.ramp.get_shader_parameter("glow")
	var level: float = s.ramp.get_shader_parameter("level")
	var knob_at: float = (s.knob as Node3D).position.x
	s.show_state(false, 1.0)
	var unlit: float = s.ramp.get_shader_parameter("glow")
	s.show_state(true, 0.0)
	var dead: float = s.ramp.get_shader_parameter("glow")
	_check("the knob stands where the amount is (%.1f mm along the slot for 0.75) and the ramp is lit that far (%.2f of it); dark with the switch at GRIP (%.1f) and with the battery dead (%.1f)" % [(knob_at - Drift.place(0.0)) * 1000.0, level, unlit, dead],
		is_equal_approx(knob_at, Drift.place(0.75)) and is_equal_approx(level, 0.75 / Drift.AMOUNT_MAX) and lit == 1.0 and unlit == 0.0 and dead == 0.0)
	v.set_slide_amount(1.25)
	_check("set from outside (a test, a menu) the knob goes there and it is saved: %.2f, \"slide_amount\": %s" % [s.amount, _saved().get("slide_amount", "nothing")],
		s.amount == 1.25 and Cockpit.slide_amount == 1.25 and absf(float(_saved().get("slide_amount", -1.0)) - 1.25) < 0.001 and _saved().get("slide", "") == "on")
	hand.queue_free()
	second.queue_free()
	v.queue_free()
	await process_frame
	# a cockpit built afterwards (the next flight): what was saved is read, and its knob stands there
	Cockpit._slide_loaded = false
	Cockpit.slide_amount = 1.0
	await _cockpit()
	_check("the next cockpit reads it: the amount %.2f, its knob there (%.2f)" % [Cockpit.slide_amount, v.drift_slider.amount if v.drift_slider else -1.0],
		Cockpit.slide_amount == 1.25 and v.drift_slider != null and v.drift_slider.amount == 1.25)
	v.queue_free()
	await process_frame
	if prefs_before == "":
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Cockpit.PREFS))
	else:
		var out := FileAccess.open(Cockpit.PREFS, FileAccess.WRITE)
		out.store_string(prefs_before)
		out.close()
	Cockpit.slide_amount = 1.0
	Cockpit.slide_feel = true
	print("DRIFT SLIDER %s (%d checks, %d failures)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)
