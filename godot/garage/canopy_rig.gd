## How each craft's canopy opens in the garage, so the pilot can climb in (Luke, 2026-11-25: "an animation for the
## cockpit glass to rise up, slide or otherwise move so that the pilot may enter"). Moves a roof node (view/canopy.gd's
## "canopy": the roof, its glass and, in the occupied cab, the start panel and projector on its header) in the pod's
## frame, the frame both the display pod's roof and the cab's are built in. One mechanism per craft:
##   phaethon  rear-hinged clamshell: unlatches, the front lifts on a hinge behind the hood
##   talon     jacks up on its rails, clear of the crown behind it, and rolls aft
##   shrike    side-hinged: swings up and over to the side away from the pilot
##   orrery    front-hinged: the cage tilts forward over the nose
##   kiln      parallel arms: lifts up and back, staying level, on two steel arms a side, clear behind the cockpit
##   vesper    rises on its rear strut, then tilts back about its tail, the front high (a swivel aside swept its tail
##             across the cockpit: tests/probe_climb_clipping.gd)
##   basilisk  rises straight up on four rams, high enough to crawl in under
## `amount` is how far through its travel it is, 0 shut to 1 open, linear in time (garage/boarding.gd drives it); each
## mechanism shapes its own motion from it. `gate_side` is the side the pilot boards from (+1 the pod's +X): the side
## hinge and the swivel open away from him.
##   var rig := CanopyRig.new("kiln", cab_roof, -1.0); rig.apply(0.5)
extends RefCounted

const Pilot := preload("res://sim/pilot_craft.gd")
const Kit := preload("res://view/mesh_kit.gd")

# Pod-local metres (forward -Z, the pod mesh's centre at 0). Hinges and pivots on "the far side" are given with x > 0
# and put on the side away from the gate. Seconds: to open, to shut.
const MECHANISMS := {
	Pilot.STANDARD: {"kind": "rear_hinge", "hinge": Vector3(0.0, 0.02, 1.30), "angle": 52.0, "open_s": 1.5, "close_s": 1.35},
	Pilot.TALON: {"kind": "rail_aft", "lift": 0.30, "travel": 1.0, "open_s": 2.0, "close_s": 1.8},
	Pilot.SHRIKE: {"kind": "side_hinge", "hinge": Vector3(0.64, 0.02, 0.0), "angle": 118.0, "open_s": 1.4, "close_s": 1.3},
	Pilot.ORRERY: {"kind": "front_hinge", "hinge": Vector3(0.0, 0.05, -0.86), "angle": 56.0, "open_s": 1.7, "close_s": 1.5},
	Pilot.KILN: {"kind": "parallel_arms", "radius": 1.10, "sweep": 125.0, "arms": [Vector3(0.99, 0.10, 1.35), Vector3(0.99, 0.10, 0.95)],
			"open_s": 2.3, "close_s": 2.1},
	Pilot.VESPER: {"kind": "lift_tilt", "lift": 0.32, "hinge": Vector3(0.0, 0.0, 2.10), "angle": 40.0, "open_s": 1.9, "close_s": 1.7},
	Pilot.BASILISK: {"kind": "rams", "lift": 0.95, "rams": [Vector3(0.90, 0.05, -0.55), Vector3(0.90, 0.05, 1.25)],
			"open_s": 2.5, "close_s": 2.2},
}

var craft := ""
var kind := ""
var spec: Dictionary
var gate_side := 1.0
var roof: Node3D
var amount := 0.0
var _rest: Transform3D
var _links: Array[MeshInstance3D] = []      # the Kiln's arms, the Basilisk's rams: drawn only while it is off its seals


static func mechanism(id: String) -> Dictionary:
	return MECHANISMS.get(id, MECHANISMS[Pilot.STANDARD])


static func open_seconds(id: String) -> float:
	return float(mechanism(id).open_s)


static func close_seconds(id: String) -> float:
	return float(mechanism(id).close_s)


func _init(id: String, canopy_root: Node3D, side: float) -> void:
	craft = id
	spec = mechanism(id)
	kind = spec.kind
	roof = canopy_root
	gate_side = 1.0 if side >= 0.0 else -1.0
	_rest = roof.transform
	if kind == "parallel_arms":
		var reach: float = spec.radius
		var bar := Kit.compound([[Kit.box(Vector3(0.045, 0.05, reach)), Kit.at(Vector3(0, 0, -reach * 0.5)), Color("#b9bec4")],
				[Kit.cyl(0.042, 0.042, 0.07, 16), Kit.at(Vector3.ZERO, Vector3(0, 0, PI / 2.0)), Color("#3b3f44")],
				[Kit.cyl(0.036, 0.036, 0.07, 16), Kit.at(Vector3(0, 0, -reach), Vector3(0, 0, PI / 2.0)), Color("#3b3f44")]])
		for pivot: Vector3 in spec.arms:
			for s: float in [-1.0, 1.0]:
				_links.append(_link(bar, "CanopyArm", Kit.polished(0.9, 0.3)))
	elif kind == "rams":
		var tube := Kit.compound([[Kit.cyl(0.05, 0.05, 1.0, 18), Kit.at(Vector3(0, 0.5, 0)), Color("#2f3336")],
				[Kit.cyl(0.062, 0.062, 0.05, 18), Kit.at(Vector3(0, 0.025, 0)), Color("#e59a2c")]])
		var rod := Kit.compound([[Kit.cyl(0.028, 0.028, 1.0, 14), Kit.at(Vector3(0, 0.5, 0)), Color("#d7dbe0")],
				[Kit.cyl(0.045, 0.045, 0.04, 14), Kit.at(Vector3(0, 0.98, 0)), Color("#2f3336")]])
		for ram: Vector3 in spec.rams:
			for s: float in [-1.0, 1.0]:
				_links.append(_link(tube, "CanopyRam", Kit.polished(0.6, 0.45)))
				_links.append(_link(rod, "CanopyRamRod", Kit.polished(1.0, 0.18)))
	apply(0.0)


func _link(mesh: Mesh, label: String, finish: Material) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = label
	part.mesh = mesh
	part.material_override = finish
	part.visible = false
	roof.get_parent().add_child(part)
	return part


## Put the roof `a` of the way through its travel (0 shut, 1 open), its linkage with it.
func apply(a: float) -> void:
	amount = clampf(a, 0.0, 1.0)
	roof.transform = _rest * motion(amount)      # (the motion is in the pod's frame, the roof's own at rest)
	_place_links()


## The roof's move off its rest, in the pod's frame, `a` of the way through its travel.
func motion(a: float) -> Transform3D:
	var s := gate_side
	match kind:
		"rear_hinge":
			# a breath of lift as the latches let go, then the swing, settling on its struts
			var unlatch := smoothstep(0.0, 0.12, a)
			var swing := _settle(smoothstep(0.08, 1.0, a))
			return _turn(spec.hinge + Vector3.UP * 0.006 * unlatch, Vector3.RIGHT, deg_to_rad(spec.angle) * swing + deg_to_rad(0.6) * unlatch)
		"front_hinge":
			var unlatch := smoothstep(0.0, 0.10, a)
			var swing := _settle(smoothstep(0.06, 1.0, a))
			return _turn(spec.hinge, Vector3.RIGHT, -deg_to_rad(spec.angle) * swing - deg_to_rad(0.5) * unlatch)
		"side_hinge":
			var hinge: Vector3 = spec.hinge * Vector3(-s, 1, 1)
			return _turn(hinge, Vector3.BACK, s * deg_to_rad(spec.angle) * _settle(smoothstep(0.0, 1.0, a)))
		"rail_aft":
			var up := smoothstep(0.0, 0.34, a)
			var back := smoothstep(0.28, 1.0, a)
			return Transform3D(Basis.IDENTITY, Vector3(0.0, spec.lift * up, spec.travel * back))
		"parallel_arms":
			var phi := deg_to_rad(spec.sweep) * smoothstep(0.0, 1.0, a)
			return Transform3D(Basis.IDENTITY, Vector3(0.0, sin(phi), 1.0 - cos(phi)) * spec.radius)
		"lift_tilt":
			var up := smoothstep(0.0, 0.40, a)
			var tilt := _settle(smoothstep(0.30, 1.0, a))
			return Transform3D(Basis.IDENTITY, Vector3.UP * spec.lift * up) * _turn(spec.hinge, Vector3.RIGHT, deg_to_rad(spec.angle) * tilt)
		"rams":
			# a beat while the pressure builds, then up, easing onto its stops
			var rise := smoothstep(0.08, 1.0, a)
			return Transform3D(Basis.IDENTITY, Vector3.UP * spec.lift * rise)
	return Transform3D.IDENTITY


## A turn of `angle` about `axis` through `point`.
static func _turn(point: Vector3, axis: Vector3, angle: float) -> Transform3D:
	var b := Basis(axis, angle)
	return Transform3D(b, point - b * point)


## A swing that runs a hair past and settles back, as a gas strut does (0 and 1 stay put).
static func _settle(x: float) -> float:
	return x + 0.035 * sin(PI * x) * smoothstep(0.55, 1.0, x)


func _place_links() -> void:
	var shown := amount > 0.002
	if kind == "parallel_arms":
		var phi := deg_to_rad(spec.sweep) * smoothstep(0.0, 1.0, amount)
		var arm: Vector3 = Vector3(0.0, sin(phi), -cos(phi)) * float(spec.radius)
		var k := 0
		for pivot: Vector3 in spec.arms:
			for s: float in [-1.0, 1.0]:
				var base: Vector3 = _rest * (pivot * Vector3(s, 1, 1))
				var link := _links[k]
				link.visible = shown
				link.transform = Transform3D(_bar_basis(arm), base)
				k += 1
	elif kind == "rams":
		var lift: float = spec.lift * smoothstep(0.08, 1.0, amount)
		var k := 0
		for ram: Vector3 in spec.rams:
			for s: float in [-1.0, 1.0]:
				var foot: Vector3 = _rest * (ram * Vector3(s, 1, 1))
				var tube := _links[k]
				var rod := _links[k + 1]
				tube.visible = shown
				rod.visible = shown
				# the tube stands on the sill, never longer than the stroke; the rod reaches the roof
				tube.transform = Transform3D(Basis.from_scale(Vector3(1, maxf(0.001, minf(lift, 0.38)), 1)), foot)
				rod.transform = Transform3D(Basis.from_scale(Vector3(1, maxf(0.001, lift), 1)), foot)
				k += 2


## A bar built along its -Z: turned to lie along `arm` (it swings in the pod's YZ plane).
static func _bar_basis(arm: Vector3) -> Basis:
	var along := arm.normalized()
	var up := Vector3.RIGHT.cross(-along).normalized()
	return Basis(up.cross(-along).normalized(), up, -along)


## Take the linkage away (the cab or the display pod it was put on is going).
func free_links() -> void:
	for link in _links:
		if is_instance_valid(link):
			link.queue_free()
	_links.clear()
