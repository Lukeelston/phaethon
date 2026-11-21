## The rear stepping out, as the seat shows it (vr_cockpit.gd's SLIDE_*): the production VR camera,
## the sim's tow swing held at its full three degrees one way, let go, then the other way.
extends SceneTree
const CM := preload("res://view/craft_model.gd")
const Sim := preload("res://sim/craft_sim.gd")
class Seat extends "res://vr/vr_cockpit.gd":
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass
	func _exit_tree() -> void: pass
	func shaft_carry_at(_x: float, _y: float) -> Basis: return Basis.IDENTITY
var seat: Seat
var t := 0.0
var fails := 0
var checks := 0
var previous := 0.0
var peak := 0.0
var rate_peak := 0.0
var held := 0.0
var head_out := 0.0
var head_peak := 0.0
var counter := 0.0
var settled := 0.0
var other := 0.0
var scrub_moving := 0.0
var scrub_inside := 0.0
var scrub_rest := 1.0
var chase_turned := 0.0

func _initialize() -> void:
	seat = Seat.new()
	seat.sim = Sim.new({"track": "range"})
	seat.craft = CM.new()
	seat.add_child(seat.craft)
	seat.rig = Node3D.new()
	seat.add_child(seat.rig)
	seat.origin = XROrigin3D.new()
	seat.origin.position = seat.SEAT
	seat.rig.add_child(seat.origin)
	seat.cam = Camera3D.new()
	seat.origin.add_child(seat.cam)
	for k in 2:
		var lever := Node3D.new()
		seat.rig.add_child(lever)
		seat.lever_pivots.append(lever)
		seat.lever_tips.append(StandardMaterial3D.new())
	root.add_child.call_deferred(seat)

func check(label: String, ok: bool) -> void:
	checks += 1
	fails += int(not ok)
	print(("PASS " if ok else "FAIL ") + label)

func _process(_delta: float) -> bool:
	if not seat.is_inside_tree():
		return false
	var delta := seat.get_process_delta_time()
	if delta <= 0.0:
		return false
	t += delta
	# a left turn's swing for 2 s, nothing for 2 s, a right turn's for 2 s, nothing
	seat.sim.tow_swing = seat.TOW_SWING_MAX if t < 2.0 else (0.0 if t < 4.0 else (-seat.TOW_SWING_MAX if t < 6.0 else 0.0))
	seat._place_camera(0.5)
	var yaw: float = seat.sim.pod.th - PI / 2.0
	var slide := angle_difference(yaw, seat.rig.basis.get_euler().y)
	var head: Vector3 = seat.origin.position + seat.cam.position
	var plain: Vector3 = seat.wz(seat.sim.pod.x, seat.sim.pod.y, seat.sim.pod.z - 0.8 + CM.POD_LIFT) + Basis(Vector3.UP, yaw) * head
	var moved: Vector3 = seat.rig.transform * head - plain
	var right := (Basis(Vector3.UP, yaw) * Vector3.RIGHT).dot(moved)    # how far the head has gone to the pod's right
	rate_peak = maxf(rate_peak, absf(slide - previous) / delta)
	previous = slide
	if t < 2.0:
		peak = maxf(peak, slide)
		head_peak = maxf(head_peak, right)
		scrub_moving = maxf(scrub_moving, seat.slide_scrub(true))
		scrub_inside = maxf(scrub_inside, seat.slide_scrub(false))
	if t > 1.8 and t < 2.0:
		held = slide
		head_out = right
	if t > 2.0 and t < 4.0:
		counter = minf(counter, slide)
	if t > 3.8 and t < 4.0:
		settled = slide
		scrub_rest = minf(scrub_rest, seat.slide_scrub(true))
	if t > 5.8 and t < 6.0:
		other = slide
	if t < 8.0:
		return false
	var full := rad_to_deg(seat.SLIDE_MAX)
	check("a left turn turns the cockpit further left: held at %.2f of %.1f deg" % [rad_to_deg(held), full], absf(rad_to_deg(held) - full) < 0.15)
	check("it steps out past that and catches: peak %.2f deg (under a quarter over)" % rad_to_deg(peak), peak > seat.SLIDE_MAX * 1.03 and peak <= seat.SLIDE_MAX * 1.25)
	check("the seat swings outward (to the right in a left turn): %.3f m held, %.3f m at most" % [head_out, head_peak], head_out > 0.18 and head_out < 0.28 and head_peak < 0.34)
	check("never faster than %.0f deg/s: %.1f" % [rad_to_deg(seat.SLIDE_RATE), rad_to_deg(rate_peak)], rate_peak <= seat.SLIDE_RATE * 1.02)
	check("let go, it swings back a little past straight (%.2f deg) and is still by 2 s (%.3f deg)" % [rad_to_deg(counter), rad_to_deg(settled)], counter < deg_to_rad(-0.2) and counter > deg_to_rad(-2.0) and absf(settled) < deg_to_rad(0.05))
	check("a right turn is its mirror: %.2f deg" % rad_to_deg(other), absf(rad_to_deg(other) + full) < 0.15)
	check("the hands scrub while it moves, the outside hand more (%.2f against %.2f), and not at rest (%.3f)" % [scrub_moving, scrub_inside, scrub_rest], scrub_moving > 0.5 and scrub_inside < scrub_moving * 0.7 and scrub_inside > 0.1 and scrub_rest < 0.01)
	# an outside camera keeps the sim's heading while the pod turns under it
	seat.camera = "chase"
	seat.sim.tow_swing = seat.TOW_SWING_MAX
	for i in 240:
		seat._slide = seat.SLIDE_MAX
		seat._slide_rate = 0.0
		seat._place_camera(0.5)
	chase_turned = absf(angle_difference(yaw, seat.origin.global_transform.basis.get_euler().y))
	check("the chase camera keeps the sim's heading while the pod slides: %.3f deg" % rad_to_deg(chase_turned), chase_turned < deg_to_rad(0.05))
	seat.camera = "cockpit"
	seat.slide_feel = false
	seat._slide = 0.0
	seat._slide_rate = 0.0
	for i in 60:
		seat._place_camera(0.5)
	check("switched off, the cockpit keeps the sim's heading exactly", absf(angle_difference(yaw, seat.rig.basis.get_euler().y)) < 1e-5)
	seat.slide_feel = true
	print("SLIDE FEEL %s (%d checks)" % ["PASS" if fails == 0 else "FAIL", checks])
	seat.queue_free()
	quit(0 if fails == 0 else 1)
	return true
