## Full-size parked cabin. Its parent is the bay's pod-floor frame, with forward along -Z.
## All fittings live in the garage world, so looking through the glass reveals the same parked engines.
extends Node3D

const Pilot := preload("res://sim/pilot_craft.gd")
const Livery := preload("res://view/livery.gd")
const Model := preload("res://view/craft_model.gd")
const Fleet := preload("res://view/fleet_airframe.gd")
const Shrike := preload("res://view/shrike_airframe.gd")
const Canopy := preload("res://view/canopy.gd")
const Projector := preload("res://view/approach_projector.gd")
const Finish := preload("res://view/craft_materials.gd")
const Kit := preload("res://view/mesh_kit.gd")
const SeatLoft := preload("res://view/traffic_models.gd")
const Interior := preload("res://vr/cockpit_interior.gd")
const Console := preload("res://vr/console_switches.gd")
const FleetDeck := preload("res://vr/fleet_flight_deck.gd")
const FleetThrottle := preload("res://vr/fleet_throttle.gd")
const AuxMeter := preload("res://vr/fleet_aux_meter.gd")
const Classic := preload("res://vr/dashboard.gd")
const Gauges := preload("res://vr/gauge_cluster.gd")
const MapPanel := preload("res://vr/minimap_panel.gd")
const Overhead := preload("res://vr/overhead_panel.gd")
const ModeSwitch := preload("res://vr/mode_switch.gd")
const DriftSlider := preload("res://vr/drift_slider.gd")
const Startup := preload("res://vr/startup_sequence.gd")
const Seat := preload("res://garage/garage_seat.gd")
const Suit := preload("res://garage/pilot_model.gd")

# The garage and flight use the same dimensions and pivot; the standing camera never scales the craft.
const SEAT := Seat.SEAT
const EYE := Seat.EYE

var shell: Node3D
var vehicle := ""
var paint := Livery.FACTORY
var overhead: Overhead
var instruments: Node3D
var _interior: Interior
var _map: MapPanel
var _projector: Projector
var _aux: AuxMeter
var _tow_meter: ShaderMaterial
var _pivots: Array[Node3D] = []
var _grips: Array[Node3D] = []
var _tips: Array[StandardMaterial3D] = []
var _boots: Array[FleetThrottle] = []
var _brake_paddles: Array[MeshInstance3D] = []
var _mode: ModeSwitch
var _slide: ModeSwitch
var _gun: ModeSwitch
var _slider: DriftSlider
var _turbine_lamp := false
var _hand_samples := {}


static func pod_pose() -> Transform3D:
	return Seat.pod_pose()


func build(vehicle_id: String, checkpoint := Callable(), finish := Livery.FACTORY) -> void:
	var selected := Pilot.known(vehicle_id)
	if shell != null:
		if vehicle == selected and paint == finish:
			return
		shell.free()
		_pivots.clear()
		_grips.clear()
		_tips.clear()
		_boots.clear()
		_brake_paddles.clear()
		_tow_meter = null
		_turbine_lamp = false
		_hand_samples.clear()
		_aux = null
		_gun = null
		overhead = null
		_projector = null
	vehicle = selected
	paint = finish
	shell = Node3D.new()
	shell.name = "ParkedShell"
	shell.transform = Seat.pod_pose()
	add_child(shell)
	var fleet := Livery.build_in(paint, _fit_body) as Fleet
	var deck := FleetDeck.new(selected) if FleetDeck.has_deck(selected) else null
	if checkpoint.is_valid():
		await checkpoint.call("cabin trim")
	await _fit_interior(fleet, deck, checkpoint)
	if checkpoint.is_valid():
		await checkpoint.call("instruments")
	Livery.build_in(paint, _fit_instruments.bind(deck))
	if checkpoint.is_valid():
		await checkpoint.call("switches")
	_fit_switches(deck != null)
	if checkpoint.is_valid():
		await checkpoint.call("overhead panel")
	Livery.build_in(paint, _fit_roof.bind(fleet))


func _fit_body() -> Fleet:
	var fleet := Fleet.new(vehicle) if Fleet.supports(vehicle) else null
	var hull := MeshInstance3D.new()
	hull.name = "PodHull"
	hull.position.y = Model.POD_FRAME_UP
	shell.add_child(hull)
	if fleet:
		fleet.dress_cab(hull, Model.nose_closed)
		if Pilot.armed(vehicle):
			var turret := Model.TurretScript.new()
			hull.add_child(turret)
			turret.build(fleet)
	else:
		var shrike := vehicle == Pilot.SHRIKE
		hull.mesh = Model.pod_hull(shrike)
		if shrike:
			Shrike.dress_pod(hull)
			Shrike.fit_seat(shell)
		else:
			_fit_base_seat()
	return fleet


func _fit_interior(fleet: Fleet, deck: FleetDeck, checkpoint: Callable) -> void:
	Interior.instrument_rails = not Gauges.available()
	var interior := Interior.new()
	_interior = interior
	interior.name = "Interior"
	shell.add_child(interior)
	Livery.build_in(paint, interior.build.bind(deck != null))
	var rim := interior.get_node("SegmentedCoaming") as MeshInstance3D
	if deck:
		if checkpoint.is_valid():
			await checkpoint.call("flight deck")
		deck.fit_cabin(interior)
	if fleet:
		rim.mesh = fleet.part(&"Coaming")
		rim.set_surface_override_material(0, null)
	elif vehicle == Pilot.SHRIKE:
		_tow_meter = Shrike.dress_coaming(rim, Interior.hd_parts and ResourceLoader.exists(Interior.HD_PARTS.Coaming))
	if deck:
		if checkpoint.is_valid():
			await checkpoint.call("padded rim")
		deck.fit_stitched_rim(rim)
		if checkpoint.is_valid():
			await checkpoint.call("seat harness")
		deck.fit_harness(shell, interior)
		var aux := AuxMeter.new()
		_aux = aux
		aux.name = "AuxiliaryMeter"
		shell.add_child(aux)
		aux.build(deck, EYE)
		aux.sync(0.0, [1.0, 1.0], [0.0, 0.0], 0.0, 1.0)
	interior.set_mode("normal")
	for side: float in [-1.0, 1.0]:
		if checkpoint.is_valid():
			await checkpoint.call("throttle")
		Livery.build_in(paint, _fit_throttle.bind(side, fleet, deck))


func _fit_throttle(side: float, fleet: Fleet, deck: FleetDeck) -> void:
	var pivot := Node3D.new()
	pivot.name = "ThrottleL" if side < 0 else "ThrottleR"
	pivot.position = Vector3(0.46 * side, 0.10, 0.20)
	pivot.rotation.x = deg_to_rad(30.0)
	shell.add_child(pivot)
	_pivots.append(pivot)
	var shaft := MeshInstance3D.new()
	pivot.add_child(shaft)
	if deck:
		var finishes := FleetDeck.finishes_for(vehicle)
		var boot := FleetThrottle.new()
		boot.name = "ThrottleBootL" if side < 0 else "ThrottleBootR"
		boot.position = pivot.position
		shell.add_child(boot)
		boot.fit(Color("#373738").lerp(finishes[2], 0.18))
		boot.set_bone_pose_rotation(1, pivot.quaternion)
		_boots.append(boot)
		shaft.mesh = FleetThrottle.shaft(finishes[1])
	else:
		shaft.position.y = 0.16
		shaft.mesh = Kit.compound([
			[Kit.cyl(0.016, 0.016, 0.32, 28), Transform3D.IDENTITY, Color(0.75, 0.77, 0.8)],
			[Kit.cyl(0.021, 0.0225, 0.018, 28), Kit.at(Vector3(0, 0.132, 0)), Color(0.42, 0.44, 0.47)]])
	shaft.material_override = Finish.satin()
	var grip := MeshInstance3D.new()
	grip.name = "PilotGrip"
	grip.position.y = 0.36
	pivot.add_child(grip)
	_grips.append(grip)
	var lens := MeshInstance3D.new()
	lens.name = "GateIndicator"
	grip.add_child(lens)
	if fleet:
		grip.mesh = fleet.part(&"Grip")
		lens.mesh = FleetThrottle.lens(0.036, 0.012, 0.045)
		lens.position.y = 0.058
	elif vehicle == Pilot.SHRIKE:
		grip.mesh = Shrike.part(&"PilotGrip")
		var paddle := MeshInstance3D.new()
		paddle.name = "BrakePaddle"
		paddle.mesh = Shrike.part(&"BrakePaddle")
		paddle.position = Vector3(-side * 0.032, 0.030, -0.021)
		grip.add_child(paddle)
		_brake_paddles.append(paddle)
		lens.mesh = FleetThrottle.lens(0.030, 0.006, 0.036)
		lens.position = Vector3(0.0, 0.054, -0.003)
	else:
		grip.mesh = Interior.deck_mesh("Grip")
		Interior.Accent.dress(grip)
		lens.mesh = Kit.rounded_box(Vector3(0.036, 0.012, 0.045), 4.0, 6)
		lens.position = Vector3(-side * 0.009, 0.054, 0.004)
	var unlit := StandardMaterial3D.new()
	unlit.albedo_color = Color(0.16, 0.17, 0.19)
	unlit.roughness = 0.35
	lens.material_override = unlit
	_tips.append(unlit)


func _fit_instruments(deck: FleetDeck) -> void:
	var panel = Gauges.new() if Gauges.available() else Classic.new()
	instruments = panel
	panel.name = "Instruments"
	if panel is Gauges:
		panel.flight_deck = deck
		panel.ivory_thrust_dials = vehicle == Pilot.SHRIKE
	shell.add_child(panel)
	panel.transform = Classic.mount()
	panel.build()
	panel.show_state({"mph": 0.0, "mach_line": "MACH 0.00", "progress": "", "footer": "PARK",
			"thr": [0.0, 0.0], "brk": [1.0, 1.0], "heat": [0.0, 0.0], "health": [1.0, 1.0],
			"flameout": [false, false], "burner": false, "ramjet": false, "armed": false,
			"battery": 1.0, "power": 1.0, "blink": false})
	var map := MapPanel.new()
	_map = map
	map.name = "MapPanel"
	shell.add_child(map)
	map.transform = MapPanel.mount(SEAT)
	map.build(deck != null)
	map.set_live(false)


func _fit_switches(bespoke: bool) -> void:
	for side: float in [1.0, -1.0]:
		var control := ModeSwitch.new()
		if side < 0.0:
			_slide = control
			control.name = "SlideSwitch"
			control.legends = ["SLIDE", "GRIP"]
			control.colours = [Color(1.0, 0.62, 0.15), Color(0.75, 0.9, 1.0)]
			control.throws = ["slide", "grip"]
		else:
			_mode = control
		shell.add_child(control)
		control.transform = ModeSwitch.mount(side)
		control.build(bespoke)
		control.show_state(false, 0.0, false)
	if Pilot.armed(vehicle):
		var gun := ModeSwitch.new()
		_gun = gun
		gun.name = "GunSwitch"
		gun.legends = ["GUN", "SAFE"]
		gun.colours = [Color(1.0, 0.22, 0.08), Color(0.35, 0.9, 0.45)]
		gun.throws = ["gun", "safe"]
		var at := Vector3(0.80, 0.755, 0.30)
		var eye := EYE - at
		gun.transform = Transform3D(Basis(Vector3.UP, atan2(eye.x, eye.z)) * Basis(Vector3.RIGHT, -0.55), at)
		shell.add_child(gun)
		gun.build(bespoke)
		gun.show_state(true, 1.0, false)
	var slider := DriftSlider.new()
	_slider = slider
	shell.add_child(slider)
	slider.transform = DriftSlider.mount()
	slider.build()
	var console: Console = _interior.switches
	console.slider = slider
	for control: ModeSwitch in [_mode, _slide]:
		for direction: float in [-1.0, 1.0]:
			for tip: Vector3 in [Vector3(0.0, .045 * direction, .08), Vector3(0.0, .025 * direction, .045)]:
				console.keep_out.append([console.to_local(control.to_global(tip)), console.KEEP_OUT_R])


func _fit_roof(fleet: Fleet) -> void:
	var roof := Canopy.build(fleet)
	roof.position.y = Model.POD_FRAME_UP
	shell.add_child(roof)
	roof.get_node("field").hide()
	if Canopy.roof_available():
		_projector = Projector.new()
		_projector.build(roof)
	if Canopy.roof_available() and Overhead.fitted:
		var starter := Overhead.new()
		overhead = starter
		roof.add_child(starter)
		starter.build()
		var parked := Startup.new()
		parked.cold()
		parked.batt = true
		parked.power = 1.0
		starter.show_state(parked, 0.0)


## The first grip is on the pilot's left. Their world transforms follow the shafts and boots.
func throttle_grips() -> Array[Node3D]:
	return _grips


func poll_overhead(controller: Node3D, delta: float) -> Array:
	if not controller or not _mode or not _slide or not is_visible_in_tree():
		return []
	var offset := Suit.index_tip(controller)
	var point := controller.global_transform * offset
	var now := Time.get_ticks_msec()
	var last: Dictionary = _hand_samples.get(controller, {})
	var fresh := last.is_empty() or now - int(last.time) > 180 or delta > 0.12
	if not fresh:
		fresh = point.distance_to(last.point) > maxf(0.08, delta * 4.0)
	_hand_samples[controller] = {"time": now, "point": point}
	var elapsed := 0.0 if fresh else delta
	var hits := overhead.poke(controller, elapsed, offset) if overhead else []
	var console: Console = _interior.switches
	var blocked := console.over_bats(console.to_local(point))
	var handling := _mode.poke(controller, elapsed, blocked, offset)
	var slide := _slide.poke(controller, elapsed, blocked, offset)
	if handling != "":
		hits.append(["handling", 1 if handling == "starfighter" else -1])
	if slide != "":
		hits.append(["slide", 1 if slide == "slide" else -1])
	return hits


func forget_overhead_hand(controller: Node3D) -> void:
	_hand_samples.erase(controller)
	if _mode:
		_mode._prev.erase(controller)
	if _slide:
		_slide._prev.erase(controller)
	if overhead:
		overhead._prev.erase(controller)
		overhead._pressed.erase(controller)


func reset_overhead_hands() -> void:
	_hand_samples.clear()
	if _mode:
		_mode._prev.clear()
	if _slide:
		_slide._prev.clear()
	if overhead:
		overhead._prev.clear()
		overhead._pressed.clear()
		overhead._press_t = 0.0


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and is_inside_tree() and _projector:
		var occupied := is_visible_in_tree()
		_projector.process_mode = Node.PROCESS_MODE_INHERIT if occupied else Node.PROCESS_MODE_DISABLED
		if _projector.port:
			_projector.port.render_target_update_mode = SubViewport.UPDATE_ONCE if occupied else SubViewport.UPDATE_DISABLED


func sync_runup(startup: Startup, controls: Dictionary, telemetry: Dictionary, delta: float, pilot: Suit = null) -> void:
	if not instruments or _grips.size() != 2:
		return
	var levers := [clampf(controls.get("thrL", 0.0), 0.0, 1.0), clampf(controls.get("thrR", 0.0), 0.0, 1.0)]
	var brakes := [clampf(controls.get("brkL", 0.0), 0.0, 1.0), clampf(controls.get("brkR", 0.0), 0.0, 1.0)]
	for i in 2:
		_pivots[i].rotation.x = deg_to_rad(lerpf(30.0, -30.0, levers[i]))
		if not _boots.is_empty():
			_boots[i].set_bone_pose_rotation(1, _pivots[i].quaternion)
		if not _brake_paddles.is_empty():
			_brake_paddles[i].rotation.x = deg_to_rad(-18.0) * brakes[i]
		var light := startup.power if levers[i] >= float(telemetry.get("gate", 0.88)) else 0.0
		_tips[i].albedo_color = Color(0.16, 0.17, 0.19).lerp(Color(1.0, 0.55, 0.15), light)
	if pilot:
		pilot.set_grip_targets(_grips[0].global_position, _grips[1].global_position)
	if startup.park and startup.lesson() not in ["right", "left", "brake"]:
		brakes = [1.0, 1.0]
	var strain: Array = telemetry.get("strain", [0.0, 0.0])
	if _aux:
		_aux.sync(0.0, brakes, strain, 0.0, startup.power)
	if _tow_meter:
		_tow_meter.set_shader_parameter("loads", Vector2(strain[0], strain[1]))
	if overhead:
		overhead.show_state(startup, delta)
	_sync_displays(startup, telemetry, levers, brakes, delta)


func _sync_displays(startup: Startup, telemetry: Dictionary, levers: Array, brakes: Array, delta: float) -> void:
	var mode: String = telemetry.get("mode", "normal")
	var starfighter: bool = telemetry.get("handling", "speed") == "starfighter"
	var sliding := bool(telemetry.get("slide", true))
	_interior.set_power(startup.power)
	_interior.set_mode(mode, float(starfighter))
	_mode.power = startup.power
	_mode.show_state(starfighter, float(starfighter), false)
	_slide.power = startup.power
	_slide.show_state(not sliding, float(not sliding), false)
	if _gun:
		_gun.power = startup.power
		_gun.show_state(true, 1.0, false)
	_slider.show_state(sliding, startup.power)
	_interior.switches.show_state({}, startup.power, delta)
	_map.show_controls(false, startup.power)
	_turbine_lamp = startup.held() and (startup.turbine >= 0.97 or (_turbine_lamp and startup.turbine > 0.60))
	var checklist := startup.display()
	var power_on := startup.power > 0.5
	var running := startup.all_running()
	if _projector:
		_projector.set_checklist(checklist if power_on and not running else {})
		var message := startup.message() if not running else "ENGINE TEST\nBOTH ENGINES RUNNING\nSERVICE STAND"
		_projector.set_message(message if power_on else "")
	instruments.show_state({"mph": 0.0, "mach_line": "MACH 0.00", "progress": startup.line() if power_on and not running else "",
			"footer": "%s   /   %s" % ["STARFIGHTER" if starfighter else "SPEEDCRAFT", "PARK" if startup.park else "SERVICE STAND"],
			"thr": [levers[0] * startup.engine_k(0), levers[1] * startup.engine_k(1)], "brk": brakes,
			"heat": telemetry.get("heat", [0.0, 0.0]), "health": telemetry.get("health", [1.0, 1.0]),
			"flameout": telemetry.get("flameout", [false, false]), "battery": telemetry.get("battery", 1.0),
			"burner": mode == "burner", "armed": telemetry.get("armed", false), "ramjet": mode == "ramjet",
			"turbines": _turbine_lamp, "power": startup.power, "steps": checklist if not running else {},
			"sweep": startup.selftest / Startup.SELFTEST_S if startup.selftest >= 0.0 else -1.0,
			"gear": telemetry.get("gear", 0), "overdrive": telemetry.get("overdrive", false),
			"blink": int(Time.get_ticks_msec() / 250) % 2 == 0})


func _fit_base_seat() -> void:
	var colour := Color(0.13, 0.12, 0.12)
	var white := Color.WHITE
	var cushion := [[SeatLoft.loft([[0.60, 0.27, 0.10, 0.19, 3.0], [0.66, 0.30, 0.085, 0.215, 3.5], [0.80, 0.30, 0.085, 0.205, 4.0],
		[1.0, 0.30, 0.09, 0.20, 4.0], [1.08, 0.28, 0.115, 0.195, 3.4], [1.12, 0.23, 0.14, 0.185, 3.0]], 28), Transform3D.IDENTITY, white]]   # the tail lifts clear of the hull floor, which rises aft (test_cables)
	var upright := Transform3D(Basis(Vector3.RIGHT, -0.12) * Basis(Vector3.RIGHT, -PI / 2.0), Vector3(0, 0.54, 1.1))
	var back := [[SeatLoft.loft([[-0.39, 0.28, -0.06, 0.06, 3.5], [-0.25, 0.31, -0.065, 0.065, 4.0], [0.15, 0.30, -0.065, 0.065, 4.0],
		[0.30, 0.24, -0.06, 0.06, 3.5], [0.39, 0.17, -0.05, 0.05, 3.0]], 28), upright, white]]
	for s in [-1.0, 1.0]:
		cushion.append([SeatLoft.loft([[0.64, 0.045, 0.14, 0.235, 2.5], [0.75, 0.055, 0.13, 0.26, 2.6], [1.0, 0.055, 0.13, 0.265, 2.6],
			[1.1, 0.045, 0.14, 0.24, 2.5]], 16), Kit.at(Vector3(0.265 * s, 0, 0)), white])
		back.append([SeatLoft.loft([[-0.3, 0.04, 0.02, 0.11, 2.5], [0.0, 0.05, 0.02, 0.13, 2.6], [0.2, 0.04, 0.02, 0.11, 2.5]], 16),
			upright * Kit.at(Vector3(0.27 * s, 0, 0)), white])
	for piece in [["seat_back", back], ["seat_cushion", cushion]]:
		var m := MeshInstance3D.new()
		m.name = piece[0]
		m.mesh = Kit.compound(piece[1])
		m.material_override = Finish.tinted("leather", colour)
		shell.add_child(m)
