## Headless regression for the garage's hand-operated radial runout fixture.
extends SceneTree

const Garage := preload("res://garage/garage.gd")
const Station := preload("res://garage/inspection_station.gd")
var failures := 0
var checks := 0
var speeds: Array[float] = []


func _initialize() -> void:
	_run.call_deferred()


func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)


func _run() -> void:
	var garage := Garage.new()
	root.add_child(garage)
	var station := garage.environment.get_node("FleetInspection") as Station
	var rotor := station.find_child("RotatingAssembly", true, false) as MeshInstance3D
	var needle := station.find_child("IndicatorNeedle", true, false) as MeshInstance3D
	var bench := station.find_child("InspectionBench", true, false) as MeshInstance3D
	check(rotor != null and needle != null and bench != null, "The fixture imports its three physical assemblies")
	if not (rotor and needle and bench):
		garage.free()
		quit(1)
		return
	var needle_origin := needle.global_position
	var shaft_origin := rotor.global_position
	var fixed_bench := bench.global_transform
	var handwheel := station.rotor_contact_point()
	check(not station.is_processing() and station.rotor_speed == 0.0, "A new station is motionless and dormant")
	check(is_zero_approx(station.rotor_contact_distance(handwheel)), "Wheel center is an accessible target")
	check(station.rotor_contact_distance(handwheel + Vector3(0, 0, .91)) > .80, "A distant hand misses the fixture")
	check((handwheel - shaft_origin).is_equal_approx(station.global_basis.z * .408), "Wheel and rotating spindle line up")
	station.rotor_speed_changed.connect(func(speed: float): speeds.append(speed))

	for i in 6:
		station.spin_rotor()
	check(is_equal_approx(station.rotor_speed, Station.MAX_SPEED), "Repeated pushes have a bounded speed")
	station.turn_rotor(0.0, 1.0/60)
	check(station.rotor_speed == 0.0 and not station.is_processing(), "Holding the rim stops a coasting rotor")
	station.spin_rotor()
	check(station.rotor_speed == 0.0, "An external push cannot pull the rim through a holding glove")
	for i in 30:
		station.turn_rotor(PI/60, 1.0/60)
	check(is_equal_approx(station.rotor_angle, PI/2), "The spindle directly tracks a quarter hand turn")
	check(is_equal_approx(rotor.rotation.z, PI/2), "The actual rotor mesh follows the hand")
	check(is_equal_approx(needle.rotation.z, -TAU*.080/.50), "The dial reads the authored 0.08 mm radial high spot")
	check(needle.global_position.is_equal_approx(needle_origin) and rotor.global_position.is_equal_approx(shaft_origin),
		"The indicator and spindle rotate about their physical bearings")
	check(bench.global_transform.is_equal_approx(fixed_bench), "The clamp, gauge body and stand stay put")
	station.release_rotor()
	check(station.is_processing() and is_equal_approx(station.rotor_speed, PI), "Release retains the measured hand speed")
	var distance := PI*PI/(2*Station.BEARING_DRAG)
	station._process(10)
	check(not station.is_processing() and station.rotor_speed == 0.0, "Coast stops and suspends the station")
	check(is_equal_approx(station.rotor_angle, wrapf(PI/2+distance,-PI,PI)), "A slow frame cannot run past the measured stopping distance")
	var angle_at_rest := station.rotor_angle
	station.spin_rotor(-1.0)
	check(station.rotor_speed < 0.0, "The fixture can turn backward")
	for i in 240:
		if station.is_processing():
			station._process(1.0/120)
	station.spin_rotor(1.0)
	for i in 48:
		if station.is_processing():
			station._process(1.0/24)
	check(is_equal_approx(station.rotor_angle, angle_at_rest), "Opposite pushes cancel at different frame rates")
	station.turn_rotor(2.9, .001)
	check(station.rotor_speed <= Station.MAX_SPEED+.00001, "Tracking jumps cannot inject unbounded momentum")
	station.turn_rotor(0.0, 1.0/60)
	station.release_rotor()
	check(not station.is_processing() and speeds.back() == 0.0, "A stationary release silences listeners and stays dormant")
	var peak := 0.0
	for speed in speeds:
		peak = maxf(peak, absf(speed))
	check(peak <= Station.MAX_SPEED+.00001, "Audio listeners never receive unbounded speed")
	garage.free()
	print("Inspection rotor: ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)
