## Exercise the production VR camera with the real craft banking response.
## A held turn, rapid alternate air-brake loads, opposite turn and release.
extends SceneTree
const CM := preload("res://view/craft_model.gd")
const Sim := preload("res://sim/craft_sim.gd")
class Seat extends "res://vr/vr_cockpit.gd":
	var carry := Basis.IDENTITY
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass
	func _exit_tree() -> void: pass
	func shaft_carry_at(_x: float, _y: float) -> Basis: return carry
var seat: Seat
var t := 0.0
var lat := 0.0
var previous := 0.0
var rate_before := 0.0
var angle_peak := 0.0
var rate_peak := 0.0
var accel_peak := 0.0
var accel_at := 0.0
var head_drift := 0.0
var reversal_angle := 0.0
var fails := 0
var checks := 0
func _initialize() -> void:
	seat = Seat.new()
	seat.sim = Sim.new({"track":"range"})
	seat.craft = CM.new()
	seat.add_child(seat.craft)
	seat.rig = Node3D.new()
	seat.add_child(seat.rig)
	seat.origin = XROrigin3D.new()
	seat.origin.position = seat.SEAT
	seat.rig.add_child(seat.origin)
	seat.cam = Camera3D.new()
	seat.cam.position = Vector3(0.2,0.15,0.1)
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
	print(("PASS " if ok else "FAIL ")+label)
func _process(delta: float) -> bool:
	if not seat.is_inside_tree(): return false
	# SceneTree runs before Node callbacks; use the same engine-smoothed interval
	# as the production camera, not SceneTree's fixed test-clock interval.
	delta = seat.get_process_delta_time()
	if delta <= 0.0: return false
	t += delta
	var demand := 120.0 if t < 3.0 else (120.0 if int((t-3.0)/0.2)%2 == 0 else -120.0)
	if t >= 9.0: demand = -120.0
	if t >= 12.0: demand = 0.0
	var bank: Array = CM.ease_bank(seat.craft.bank[2],lat,demand,delta)
	seat.craft.bank[2] = bank[0]
	lat = bank[1]
	seat._place_camera(0.5)
	var angle := seat.rig.basis.get_euler().z
	var rate := (angle-previous)/delta
	angle_peak = maxf(angle_peak,absf(angle))
	rate_peak = maxf(rate_peak,absf(rate))
	# (not the engine's first frames: their smoothed interval is not the one the camera integrated over,
	# and a difference of differences over it read thousands of deg/s2 at 0.14 s, before any lean)
	if t > 0.3 and absf(rate-rate_before)/delta > accel_peak:
		accel_peak = absf(rate-rate_before)/delta
		accel_at = t
	if t > 11.8 and t < 12.0: reversal_angle = angle
	var head: Vector3 = seat.origin.position+seat.cam.position
	var yaw: float = seat.sim.pod.th-PI/2.0
	var expected: Vector3 = seat.wz(seat.sim.pod.x,seat.sim.pod.y,seat.sim.pod.z-0.8+CM.POD_LIFT)+Basis(Vector3.UP,yaw)*head
	head_drift = maxf(head_drift,(seat.rig.transform*head).distance_to(expected))
	previous = angle
	rate_before = rate
	if t < 17.0: return false
	check("cockpit lean <=30deg: %.3f"%rad_to_deg(angle_peak),rad_to_deg(angle_peak)<=30.01)
	check("roll speed <=30deg/s: %.3f"%rad_to_deg(rate_peak),rad_to_deg(rate_peak)<=30.02)
	check("reversal acceleration <=100deg/s2: %.3f at %.3fs"%[rad_to_deg(accel_peak),accel_at],rad_to_deg(accel_peak)<=100.0)
	check("held opposite turn still visibly banks",rad_to_deg(reversal_angle)<-15.0)
	check("release settles level without residual oscillation",absf(angle)<deg_to_rad(0.05))
	check("tracked eye does not swing sideways while banking: %.6fm"%head_drift,head_drift<0.001)
	seat.carry = Basis(Vector3.FORWARD,PI)
	seat._place_camera(0.5)
	check("road barrel roll still carries cockpit upside down",seat.rig.basis.y.dot(Vector3.UP)<-0.999)
	var settled := 0.0
	for i in 1200: settled = seat._ease_cockpit_roll(deg_to_rad(120.0),1.0/120.0)
	check("combined road bank and turn lean caps at30deg",absf(rad_to_deg(settled)-30.0)<0.01)
	var held: float = seat._ease_cockpit_roll(-PI,0.0)
	check("zero elapsed time cannot move cockpit",held==settled)
	var stalled: float = seat._ease_cockpit_roll(-PI,0.5)
	check("long frame cannot produce a roll jump",absf(stalled-held)<=deg_to_rad(1.5))
	print("COCKPIT ROLL %s (%d checks)"%["PASS" if fails==0 else "FAIL",checks])
	seat.queue_free()
	quit(0 if fails==0 else 1)
	return true
