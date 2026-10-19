## The pod's windscreen and forcefield (Luke: "add an oblong windscreen and forcefield that
## intensifies with speed"), shared by the flat view's pod and the VR cockpit.
##   windscreen  an oblong, raked-back glass screen standing on the lip along the front of the
##               cockpit opening, tall enough that you look through it, with a dark frame on top
##   forcefield  an ellipsoid round the front of the pod (view/forcefield.gdshader): clear where you
##               look through it, glowing edge-on; with speed a bow ring round the nose and streaks
##               flowing back; the handling's colour, whiter on the burner
## Both are built in pod-local coordinates (the hull's: forward -Z) and joined to the "exterior"
## group: they sit on the lip and outside the hull by design, so the cockpit-clearance gate leaves
## them out (tests/test_canopy.gd checks them instead).
##   var c := Canopy.build(); pod.add_child(c)                (VR: at POD_FRAME_UP in the shell)
##   Canopy.update(c, speed_ms, sim.hblend, sim.mode, delta)  each frame
class_name Canopy
extends RefCounted

const CM := preload("res://view/craft_model.gd")
const Kit := preload("res://view/mesh_kit.gd")
const PH0 := deg_to_rad(-152.0)    # the screen's arc round the front of the opening ...
const PH1 := deg_to_rad(-28.0)
const SCREEN_H := 0.5              # ... and its height at the middle (an ellipse in outline): you look through the glass, the frame well above the horizon
const RAKE := deg_to_rad(48.0)     # leaning back toward the pilot from vertical
const FIELD_C := Vector3(0.0, 0.1, -0.85)   # the field's centre and radii, pod-local
const FIELD_R := Vector3(1.55, 0.95, 2.7)
const SPEED_COL := Color(0.25, 0.65, 1.0)
const SF_COL := Color(1.0, 0.3, 0.75)
const MPH := 2.236936


static func build() -> Node3D:
	var root := Node3D.new()
	root.name = "canopy"
	root.add_to_group("exterior")
	var glass := MeshInstance3D.new()
	glass.name = "windscreen"
	glass.mesh = windscreen_mesh()
	var gm := StandardMaterial3D.new()
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gm.albedo_color = Color(0.72, 0.86, 1.0, 0.1)
	gm.metallic = 0.0
	gm.roughness = 0.03
	gm.metallic_specular = 0.9
	gm.cull_mode = BaseMaterial3D.CULL_DISABLED
	gm.rim_enabled = true
	gm.rim = 0.35
	gm.rim_tint = 0.2
	glass.material_override = gm
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(glass)
	var frame := MeshInstance3D.new()
	frame.name = "frame"
	frame.mesh = frame_mesh()
	frame.material_override = Kit.polished(0.6, 0.35)
	root.add_child(frame)
	var field := MeshInstance3D.new()
	field.name = "field"
	var s := SphereMesh.new()
	s.radius = 1.0
	s.height = 2.0
	s.radial_segments = 48
	s.rings = 24
	field.mesh = s
	field.position = FIELD_C
	field.scale = FIELD_R
	var fm := ShaderMaterial.new()
	fm.shader = preload("res://view/forcefield.gdshader")
	field.material_override = fm
	field.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(field)
	for n in [glass, frame, field]:
		n.add_to_group("exterior")
	return root


## A point on the screen: arc position u (0..1 across) and v (0 on the lip .. 1 at the top edge).
static func screen_point(u: float, v: float) -> Vector3:
	var ph := lerpf(PH0, PH1, u)
	var x := CM.OPEN_AX * cos(ph)
	var z := CM.OPEN_ZC + CM.OPEN_AZ * sin(ph)
	var base := Vector3(x, CM.hull_top(x, z) + CM.LIP_R * 0.7, z)
	var w := 2.0 * u - 1.0
	var h := SCREEN_H * sqrt(maxf(0.0, 1.0 - w * w))       # an oblong: tallest in the middle
	var inward := Vector3(-x, 0.0, CM.OPEN_ZC - z).normalized()   # toward the opening's centre
	return base + (Vector3.UP * cos(RAKE) + inward * sin(RAKE)) * h * v


static func windscreen_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cols := 40
	var rows := 8
	for i in cols:
		for j in rows:
			var a := screen_point(float(i) / cols, float(j) / rows)
			var b := screen_point(float(i + 1) / cols, float(j) / rows)
			var c := screen_point(float(i + 1) / cols, float(j + 1) / rows)
			var d := screen_point(float(i) / cols, float(j + 1) / rows)
			for p in [a, c, b, a, d, c]:
				st.add_vertex(p)
	st.generate_normals()
	return st.commit()


## The frame: a slim rounded bar along the screen's top edge.
static func frame_mesh() -> ArrayMesh:
	var parts := []
	var cols := 40
	for i in cols:
		var a := screen_point(float(i) / cols, 1.0)
		var b := screen_point(float(i + 1) / cols, 1.0)
		var mid := (a + b) / 2.0
		var dir := b - a
		if dir.length() < 1e-4:
			continue
		parts.append([Kit.cyl(0.007, 0.007, dir.length() + 0.004, 8), Transform3D(Basis(_perp(dir.normalized()), dir.normalized(), _perp(dir.normalized()).cross(dir.normalized())), mid), Color(0.62, 0.64, 0.68)])
	return Kit.compound(parts)


static func _perp(v: Vector3) -> Vector3:
	var p := v.cross(Vector3.UP)
	if p.length() < 1e-3:
		p = v.cross(Vector3.RIGHT)
	return p.normalized()


## How hard the field works at this speed: from ~150 mph, rising to full near 4,000 mph, more on
## the burner.
static func field_power(speed_ms: float, mode: String) -> float:
	var mph := speed_ms * MPH
	var p := 0.55 * smoothstep(150.0, 1500.0, mph) + 0.75 * smoothstep(1500.0, 4500.0, mph)
	return p * (1.25 if mode != "normal" else 1.0)


static func update(canopy: Node3D, speed_ms: float, sf: float, mode: String, delta: float) -> void:
	var field := canopy.get_node_or_null("field") as MeshInstance3D
	if field == null:
		return
	var m := field.material_override as ShaderMaterial
	var tint := SPEED_COL.lerp(SF_COL, clampf(sf, 0.0, 1.0))
	if mode != "normal":
		tint = tint.lerp(Color(1.0, 0.95, 0.9), 0.4)
	var flow: float = canopy.get_meta("flow", 0.0) + speed_ms * delta * 0.004
	canopy.set_meta("flow", fposmod(flow, 1000.0))
	m.set_shader_parameter("power", field_power(speed_ms, mode))
	m.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
	m.set_shader_parameter("flow", flow)
