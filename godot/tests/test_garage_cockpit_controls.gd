## Parked controls use the real run-up, and suited hands meet the same moving grip meshes.
extends SceneTree

const Cab := preload("res://garage/garage_cockpit.gd")
const Catalog := preload("res://sim/pilot_craft.gd")
const Pilot := preload("res://garage/pilot_model.gd")
const Startup := preload("res://vr/startup_sequence.gd")
var checks := 0
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, why: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(why)


func _tip_at(hand: Node3D, world_point: Vector3) -> void:
	hand.global_position = world_point - hand.global_basis * Pilot.index_tip(hand)


func _switch_gesture(cab: Cab, hand: Node3D, switch: Node3D, action: Array) -> void:
	forget_and_prime(cab, hand, switch.to_global(Vector3(0, .025, .075)))
	_tip_at(hand, switch.to_global(Vector3(0, -.025, .075)))
	_check(cab.poll_overhead(hand, .025).has(action), cab.vehicle + " throws " + str(action[0]))


func forget_and_prime(cab: Cab, hand: Node3D, at: Vector3) -> void:
	cab.forget_overhead_hand(hand)
	_tip_at(hand, at)
	_check(cab.poll_overhead(hand, .025).is_empty(), "Acquiring a hand only records its current position")


func _run() -> void:
	var cab := Cab.new()
	root.add_child(cab)
	var pilot := Pilot.new()
	root.add_child(pilot)
	pilot.set_seated(true)
	cab.transform = Transform3D(Basis(Vector3.UP, .6), Vector3(-8.0, .72, 11.0))
	pilot.global_transform = cab.global_transform * Transform3D(Basis.IDENTITY, Cab.EYE - Pilot.SEATED_EYE)
	var hand := Node3D.new()
	hand.name = "LeftHand"
	root.add_child(hand)
	for id: String in Catalog.GARAGE_BAYS:
		cab.build(id)
		pilot.set_seat_vehicle(id)
		var start := Startup.new()
		start.cold()
		cab.sync_runup(start, {}, {}, 0.0, pilot)
		_check(cab.instruments._power == 0.0 and cab._projector.message.is_empty(), id + " powers down the display")
		var panel := cab.overhead
		var battery_pod: Node3D = panel.pods[-1.0]
		var x: float = panel.CONTROLS["batt"][1]
		forget_and_prime(cab, hand, battery_pod.to_global(Vector3(x, -.025, .04)))
		_tip_at(hand, battery_pod.to_global(Vector3(x, .025, .04)))
		_check(cab.poll_overhead(hand, .025).has(["batt", 1]), id + " battery responds at the glove's index pad")
		start.flick("batt", 1)
		start.step(.25, [0, 0])
		cab.sync_runup(start, {}, {}, .25, pilot)
		_check(cab.instruments._testing, id + " starts the native needle sweep")
		start.hot()
		start.park = true
		var grips := cab.throttle_grips()
		for setting: Array in [[0.0, .5], [1.0, .15], [.6, 1.0], [1.0, 1.0]]:
			var raw := {"thrL": setting[0], "thrR": setting[1], "brkL": .0, "brkR": .7}
			cab.sync_runup(start, raw, {}, .016, pilot)
			for side in 2:
				var value: float = setting[side]
				var channel := "thrL" if side == 0 else "thrR"
				_check(absf(cab.instruments.values[channel] - value) < .001, id + " displays each running engine's thrust")
				var palm := pilot._gloves[side].to_global(Vector3(0, -.081, 0))
				_check(palm.distance_to(grips[side].global_position) < .001, id + " palm stays on the throttle throughout its throw")
				_check(absf(cab._pivots[side].rotation.x - deg_to_rad(lerpf(30.0, -30.0, value))) < .001, id + " uses its flight lever travel")
		_check(cab._projector.message.contains("BOTH ENGINES RUNNING"), id + " confirms the stable run-up")
		_switch_gesture(cab, hand, cab._mode, ["handling", 1])
		_switch_gesture(cab, hand, cab._slide, ["slide", -1])
		cab.sync_runup(start, {}, {"handling": "starfighter", "slide": false}, .016, pilot)
		_check(cab._mode.down and cab._slide.down, id + " restores the bay's switches from telemetry")
		cab.reset_overhead_hands()
		_tip_at(hand, cab._mode.to_global(Vector3(0, .035, .075)))
		_check(cab.poll_overhead(hand, .025).is_empty(), id + " ignores a stale crossing after focus returns")
	pilot.set_first_person(true)
	pilot.set_tracked_hands(true)
	cab.sync_runup(Startup.new(), {"thrL": 1.0}, {}, .016, pilot)
	_check(pilot._grip_targets.is_empty() and not pilot._arms[0].visible, "Tracked hands keep the XR controller poses")
	pilot.set_tracked_hands(false)
	pilot.set_seated(false)
	_check(pilot._grip_targets.is_empty() and pilot._arms[0].position.is_equal_approx(pilot._shoulders[0]), "Standing restores the shoulder sockets")
	hand.free()
	pilot.free()
	cab.free()
	print("GARAGE COCKPIT CONTROLS %s (%d checks, %d failures)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(int(failures > 0))
