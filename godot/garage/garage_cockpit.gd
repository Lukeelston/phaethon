## Full-size parked cabin. Its parent is the bay's pod-floor frame, with forward along -Z.
## All fittings live in the garage world, so looking through the glass reveals the same parked engines.
extends Node3D

const Pilot := preload("res://sim/pilot_craft.gd")
const Model := preload("res://view/craft_model.gd")
const Fleet := preload("res://view/fleet_airframe.gd")
const Shrike := preload("res://view/shrike_airframe.gd")
const Canopy := preload("res://view/canopy.gd")
const Finish := preload("res://view/craft_materials.gd")
const Kit := preload("res://view/mesh_kit.gd")
const SeatLoft := preload("res://view/traffic_models.gd")
const Interior := preload("res://vr/cockpit_interior.gd")
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

# The garage and flight use the same dimensions and pivot; the standing camera never scales the craft.
const SEAT := Seat.SEAT
const EYE := Seat.EYE

var shell: Node3D
var vehicle := ""


static func pod_pose() -> Transform3D:
	return Seat.pod_pose()


func build(vehicle_id: String, checkpoint := Callable()) -> void:
	var selected := Pilot.known(vehicle_id)
	if shell != null:
		if vehicle == selected:
			return
		shell.free()
	vehicle = selected
	shell = Node3D.new()
	shell.name = "ParkedShell"
	shell.transform = Seat.pod_pose()
	add_child(shell)
	var fleet := Fleet.new(selected) if Fleet.supports(selected) else null
	var deck := FleetDeck.new(selected) if FleetDeck.has_deck(selected) else null
	_fit_body(fleet)
	if checkpoint.is_valid():
		await checkpoint.call("cabin trim")
	await _fit_interior(fleet, deck, checkpoint)
	if checkpoint.is_valid():
		await checkpoint.call("instruments")
	_fit_instruments(deck)
	if checkpoint.is_valid():
		await checkpoint.call("switches")
	_fit_switches(deck != null)
	if checkpoint.is_valid():
		await checkpoint.call("overhead panel")
	_fit_roof(fleet)


func _fit_body(fleet: Fleet) -> void:
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


func _fit_interior(fleet: Fleet, deck: FleetDeck, checkpoint: Callable) -> void:
	Interior.instrument_rails = not Gauges.available()
	var interior := Interior.new()
	interior.name = "Interior"
	shell.add_child(interior)
	interior.build(deck != null)
	var rim := interior.get_node("SegmentedCoaming") as MeshInstance3D
	if deck:
		if checkpoint.is_valid():
			await checkpoint.call("flight deck")
		deck.fit_cabin(interior)
	if fleet:
		rim.mesh = fleet.part(&"Coaming")
		rim.set_surface_override_material(0, null)
	elif vehicle == Pilot.SHRIKE:
		Shrike.dress_coaming(rim, Interior.hd_parts and ResourceLoader.exists(Interior.HD_PARTS.Coaming))
	if deck:
		if checkpoint.is_valid():
			await checkpoint.call("padded rim")
		deck.fit_stitched_rim(rim)
		if checkpoint.is_valid():
			await checkpoint.call("seat harness")
		deck.fit_harness(shell, interior)
		var aux := AuxMeter.new()
		aux.name = "AuxiliaryMeter"
		shell.add_child(aux)
		aux.build(deck, EYE)
		aux.sync(0.0, [1.0, 1.0], [0.0, 0.0], 0.0, 1.0)
	interior.set_mode("normal")
	for side: float in [-1.0, 1.0]:
		if checkpoint.is_valid():
			await checkpoint.call("throttle")
		_fit_throttle(side, fleet, deck)


func _fit_throttle(side: float, fleet: Fleet, deck: FleetDeck) -> void:
	var pivot := Node3D.new()
	pivot.name = "ThrottleL" if side < 0 else "ThrottleR"
	pivot.position = Vector3(0.46 * side, 0.10, 0.20)
	pivot.rotation.x = deg_to_rad(30.0)
	shell.add_child(pivot)
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


func _fit_instruments(deck: FleetDeck) -> void:
	var panel = Gauges.new() if Gauges.available() else Classic.new()
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
	map.name = "MapPanel"
	shell.add_child(map)
	map.transform = MapPanel.mount(SEAT)
	map.build(deck != null)
	map.set_live(false)


func _fit_switches(bespoke: bool) -> void:
	for side: float in [1.0, -1.0]:
		var control := ModeSwitch.new()
		if side < 0.0:
			control.name = "SlideSwitch"
			control.legends = ["SLIDE", "GRIP"]
			control.colours = [Color(1.0, 0.62, 0.15), Color(0.75, 0.9, 1.0)]
			control.throws = ["slide", "grip"]
		shell.add_child(control)
		control.transform = ModeSwitch.mount(side)
		control.build(bespoke)
		control.show_state(false, 0.0, false)
	if Pilot.armed(vehicle):
		var gun := ModeSwitch.new()
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
	shell.add_child(slider)
	slider.transform = DriftSlider.mount()
	slider.build()


func _fit_roof(fleet: Fleet) -> void:
	var roof := Canopy.build(fleet)
	roof.position.y = Model.POD_FRAME_UP
	shell.add_child(roof)
	roof.get_node("field").hide()
	if Canopy.roof_available() and Overhead.fitted:
		var starter := Overhead.new()
		roof.add_child(starter)
		starter.build()
		var parked := Startup.new()
		parked.cold()
		parked.batt = true
		parked.power = 1.0
		starter.show_state(parked, 0.0)


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
