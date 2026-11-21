## The rear stepping out, as the seat shows it (vr_cockpit.gd's SLIDE_*): the production VR camera,
## with the engines turning under a known cornering load. A hard left turn (30 g), let go, a hard
## right turn, let go; then what a pilot holding a lane does (4 g, swinging side to side), a gentle
## turn (10 g) and a firm one (20 g): the loads the eighth flight's air-brake steering makes.
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
var lane := 0.0
var gentle := 0.0
var firm := 0.0
const SPEED := 1500.0      # m/s along the engines' heading (about 3,350 mph)


## Turn the engines at the rate that makes this cornering load, g (+ a left turn).
func _load(g: float) -> void:
	var sim = seat.sim
	sim.pod.vx = SPEED * cos(sim.pair_th)
	sim.pod.vy = SPEED * sin(sim.pair_th)
	sim.eL.w = g * 9.81 / SPEED
	sim.eR.w = sim.eL.w

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
	# a hard left turn for 2 s, nothing for 2 s, a hard right turn for 2 s, nothing; then a lane held,
	# a gentle turn and a firm one
	var g := 30.0 if t < 2.0 else (0.0 if t < 4.0 else (-30.0 if t < 6.0 else 0.0))
	if t >= 8.0:
		g = 4.0 * sin(TAU * 0.4 * t) if t < 12.0 else (10.0 if t < 14.0 else (20.0 if t < 16.0 else 0.0))
	_load(g)
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
	if t > 8.5 and t < 12.0:
		lane = maxf(lane, absf(slide))
	if t > 13.8 and t < 14.0:
		gentle = slide
	if t > 15.8 and t < 16.0:
		firm = slide
	if t < 16.5:
		return false
	_load(0.0)
	var full := rad_to_deg(seat.SLIDE_MAX)
	check("a left turn turns the cockpit further left: held at %.2f of %.1f deg" % [rad_to_deg(held), full], absf(rad_to_deg(held) - full) < 0.15)
	check("it steps out past that and catches: peak %.2f deg (under a quarter over)" % rad_to_deg(peak), peak > seat.SLIDE_MAX * 1.01 and peak <= seat.SLIDE_MAX * 1.25)
	check("the seat swings outward (to the right in a left turn): %.3f m held, %.3f m at most" % [head_out, head_peak], head_out > 0.22 and head_out < 0.32 and head_peak < 0.40)
	check("never faster than %.0f deg/s: %.1f" % [rad_to_deg(seat.SLIDE_RATE), rad_to_deg(rate_peak)], rate_peak <= seat.SLIDE_RATE * 1.02)
	check("let go, it swings back a little past straight (%.2f deg) and is still by 2 s (%.3f deg)" % [rad_to_deg(counter), rad_to_deg(settled)], counter < deg_to_rad(-0.05) and counter > deg_to_rad(-2.0) and absf(settled) < deg_to_rad(0.05))
	check("a right turn is its mirror: %.2f deg" % rad_to_deg(other), absf(rad_to_deg(other) + full) < 0.15)
	check("holding a lane (4 g, side to side) it stays put: %.3f deg at most" % rad_to_deg(lane), lane < deg_to_rad(0.1))
	check("a gentle turn (10 g) shows a little of it, a firm one (20 g) most of it: %.2f and %.2f deg" % [rad_to_deg(gentle), rad_to_deg(firm)],
		gentle > deg_to_rad(0.5) and gentle < deg_to_rad(2.5) and firm > seat.SLIDE_MAX * 0.7 and firm < seat.SLIDE_MAX)
	check("the hands scrub while it moves, the outside hand more (%.2f against %.2f), and not at rest (%.3f)" % [scrub_moving, scrub_inside, scrub_rest], scrub_moving > 0.5 and scrub_inside < scrub_moving * 0.7 and scrub_inside > 0.1 and scrub_rest < 0.01)
	# an outside camera keeps the sim's heading while the pod turns under it
	seat.camera = "chase"
	_load(30.0)
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
	check("switched off (GRIP), the cockpit keeps the sim's heading exactly in the same hard turn", absf(angle_difference(yaw, seat.rig.basis.get_euler().y)) < 1e-5)
	seat.slide_feel = true
	print("SLIDE FEEL %s (%d checks)" % ["PASS" if fails == 0 else "FAIL", checks])
	seat.queue_free()
	quit(0 if fails == 0 else 1)
	return true
