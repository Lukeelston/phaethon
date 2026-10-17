## The sprint's end of the range, as seen from up to 100 miles away:
## - a light column standing in the stop box, with a "STOP" marker that stays readable at any
##   distance (fixed-size, drawn over everything): the braking reference;
## - the citadel, an original titan megastructure in the Star Wars spirit, now a backdrop
##   18 km past the box (beyond the overrun zone) and scaled down so it doesn't read as the target.
##
## Anything farther than 6 km is drawn as a scaled impostor at a fixed 6 km along its true
## bearing (identical angular size, no depth-precision breakup at 150 km), hazed by its
## TRUE distance.
extends Node3D

const Sim := preload("res://sim/craft_sim.gd")
const SC := 0.6                       # citadel dimensions below are multiplied by this
const CIT_X := Sim.BOX_X + 18000.0 + 4600.0 * SC   # citadel base centre
const R := 6000.0                     # impostor distance
const HAZE := Color(0.78, 0.66, 0.52)
const HAZE_K := 90000.0               # 1 - exp(-d/K)

var root: Node3D        # citadel impostor transform
var body: Node3D        # citadel geometry, scaled by SC
var beacon_root: Node3D # light column impostor transform, anchored on the box
var marker: Label3D
var parts: Array = []   # [material, base colour, base emission energy]
var beacon: StandardMaterial3D
var column_mat: StandardMaterial3D


func _material(c: Color, emit := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.disable_fog = true   # haze is applied by true distance below; engine fog would erase it
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emit
	parts.append([m, c, emit])
	return m


func _part(mesh: Mesh, pos: Vector3, mat: Material, parent: Node3D = null) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(parent if parent else body).add_child(mi)


func _box(size: Vector3, pos: Vector3, mat: Material) -> void:
	var b := BoxMesh.new()
	b.size = size
	_part(b, pos, mat)


func _cyl(bottom: float, top: float, height: float, y0: float, xz: Vector2, mat: Material) -> void:
	var c := CylinderMesh.new()
	c.bottom_radius = bottom
	c.top_radius = top
	c.height = height
	c.radial_segments = 48
	_part(c, Vector3(xz.x, y0 + height / 2.0, xz.y), mat)


func build(_view) -> void:
	_build_beacon()
	root = Node3D.new()
	add_child(root)
	body = Node3D.new()
	body.scale = Vector3(SC, SC, SC)
	root.add_child(body)
	var hull := _material(Color(0.20, 0.21, 0.24))
	var dark := _material(Color(0.12, 0.12, 0.14))
	var lit := _material(Color(1.0, 0.70, 0.34), 2.5)
	var halo := _material(Color(0.45, 0.85, 1.0), 3.0)
	var seam := _material(Color(0.55, 0.85, 1.0), 1.6)
	beacon = _material(Color(1.0, 0.12, 0.08), 8.0)

	# stepped base: five tiers, each banded with lit floors
	var widths := [9200.0, 7600.0, 6000.0, 4500.0, 3200.0]
	var tier_h := 360.0
	for i in widths.size():
		var w: float = widths[i]
		var y0 := i * tier_h
		_box(Vector3(w, tier_h, w), Vector3(0, y0 + tier_h / 2.0, 0), hull)
		for band in [0.25, 0.5, 0.75]:
			_box(Vector3(w + 4.0, 6.0, w + 4.0), Vector3(0, y0 + tier_h * band, 0), lit)
	var top_y := widths.size() * tier_h

	# hangar gate on the approach face (-X): a dark door with lit seams
	var front: float = -widths[0] / 2.0
	for s in [-1.0, 1.0]:
		_box(Vector3(260.0, 1100.0, 260.0), Vector3(front - 130.0, 550.0, s * 480.0), dark)
	_box(Vector3(260.0, 200.0, 1220.0), Vector3(front - 130.0, 1100.0, 0), dark)
	_box(Vector3(20.0, 900.0, 700.0), Vector3(front - 10.0, 450.0, 0), dark)
	for z in [-280.0, -140.0, 0.0, 140.0, 280.0]:
		_box(Vector3(24.0, 860.0, 12.0), Vector3(front - 22.0, 450.0, z), seam)
	for y in [300.0, 600.0, 860.0]:
		_box(Vector3(24.0, 10.0, 680.0), Vector3(front - 22.0, y, 0), seam)

	# four flanking towers with lit crowns and spikes
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var p := Vector2(sx * 3000.0, sz * 3000.0)
			_cyl(320.0, 230.0, 2700.0, 0.0, p, hull)
			_cyl(242.0, 242.0, 50.0, 2450.0, p, lit)
			_cyl(230.0, 0.0, 900.0, 2700.0, p, dark)

	# central spire, halo rings, needle, beacon
	_cyl(600.0, 160.0, 2800.0, top_y, Vector2.ZERO, hull)
	for ring in [[2600.0, 1050.0], [3300.0, 840.0], [3900.0, 620.0]]:
		var t := TorusMesh.new()
		t.inner_radius = ring[1] - 32.0
		t.outer_radius = ring[1] + 32.0
		t.rings = 96
		_part(t, Vector3(0, ring[0], 0), halo)
	_cyl(160.0, 8.0, 1000.0, top_y + 2800.0, Vector2.ZERO, dark)
	var s := SphereMesh.new()
	s.radius = 70.0
	s.height = 140.0
	_part(s, Vector3(0, top_y + 3840.0, 0), beacon)


## Light column standing in the stop box, plus a fixed-size STOP marker over it.
func _build_beacon() -> void:
	beacon_root = Node3D.new()
	add_child(beacon_root)
	column_mat = StandardMaterial3D.new()
	column_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	column_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	column_mat.albedo_color = Color(0.55, 0.9, 1.0, 0.55)
	column_mat.disable_fog = true
	column_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var col := CylinderMesh.new()
	col.top_radius = 10.0
	col.bottom_radius = 10.0
	col.height = 3000.0
	_part(col, Vector3(0, 1500.0, 0), column_mat, beacon_root)
	marker = Label3D.new()
	marker.text = "▼\nSTOP"
	marker.fixed_size = true
	marker.pixel_size = 0.0012
	marker.font_size = 48
	marker.outline_size = 10
	marker.modulate = Color(1.0, 0.25, 0.12)
	marker.outline_modulate = Color(1.0, 0.97, 0.9)
	marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	marker.no_depth_test = true
	marker.render_priority = 100
	add_child(marker)


## Place an anchored object: true position within R, else a scaled impostor at R.
static func _impostor(node: Node3D, dx: float, dz: float) -> float:
	var dist := sqrt(dx * dx + dz * dz)
	var s := 1.0 if dist <= R else R / dist
	node.position = Vector3(dx * s, 0.0, dz * s)
	node.scale = Vector3(s, s, s)
	return dist


func sync(ox: float, oy: float, t: float) -> void:
	# both anchors sit on sim y = 0; render z = -(0 - oy)
	var bdist := _impostor(beacon_root, Sim.BOX_X - ox, oy)
	var bs := 1.0 if bdist <= 4000.0 else 4000.0 / bdist
	marker.position = Vector3((Sim.BOX_X - ox) * bs, 90.0, oy * bs)
	marker.visible = bdist > 120.0   # hide it once you're on top of the box
	var dist := _impostor(root, CIT_X - ox, oy)
	var f := clampf(1.0 - exp(-dist / HAZE_K), 0.0, 1.0)
	for p in parts:
		var m: StandardMaterial3D = p[0]
		m.albedo_color = (p[1] as Color).lerp(HAZE, f)
		if p[2] > 0.0:
			m.emission_energy_multiplier = p[2] * (1.0 - 0.8 * f)
	# citadel beacon: a red blink every 1.2 s that cuts through the haze
	beacon.emission_energy_multiplier = (14.0 if fmod(t, 1.2) < 0.3 else 1.0) * (1.0 - 0.4 * f)
