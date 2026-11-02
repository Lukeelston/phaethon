## The windscreen and forcefield (view/canopy.gd; Luke: "an oblong windscreen and forcefield that
## intensifies with speed"). They sit on the lip and outside the hull by design, so the cockpit-
## clearance gate skips them ("exterior"); this checks them instead:
##   screen   its foot runs along the lip round the front of the opening; it rises back toward the
##            pilot, tallest in the middle (oblong) and tapering to nothing at its ends; you look
##            through the glass and its frame sits well above the horizon, out of the sightline
##   field    off when still, building with speed (~150 mph on, near full by 4,000), stronger on
##            the burner; blue in SPEEDCRAFT, magenta in STARFIGHTER; it wraps the nose
##   both     built into the flat view's pod and the VR cockpit, and marked "exterior"
##   flash    a forcefield's push (traffic's bump, a wall) flares it white-blue, gone in under half a second
## Prints CANOPY PASS.
## Run: Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_canopy.gd -- --track=range --mute
extends SceneTree

const Canopy := preload("res://view/canopy.gd")
const CM := preload("res://view/craft_model.gd")
const VRScript := preload("res://vr/vr_cockpit.gd")
const EYE_Y := 0.72 - CM.POD_FRAME_UP   # the VR eye (SEAT y 0.72 above the rig floor), pod-local
var fails := 0
var passed := 0
var v
var frames := 0


func _initialize() -> void:
	v = VRScript.new()
	root.add_child(v)


func _process(_d: float) -> bool:
	frames += 1
	if frames < 3:
		return false
	# the screen's foot on the lip
	var worst_foot := 0.0
	for k in 41:
		var p: Vector3 = Canopy.screen_point(k / 40.0, 0.0)
		var best := INF
		for j in 720:
			var ph := TAU * j / 720.0
			var x := CM.OPEN_AX * cos(ph)
			var z := CM.OPEN_ZC + CM.OPEN_AZ * sin(ph)
			best = minf(best, p.distance_to(Vector3(x, CM.hull_top(x, z), z)))
		worst_foot = maxf(worst_foot, best)
	_check("the screen's foot runs along the lip (within %.3f m of the lip line; lip radius %.3f)" % [worst_foot, CM.LIP_R], worst_foot < CM.LIP_R * 1.2)
	var mid_top: Vector3 = Canopy.screen_point(0.5, 1.0)
	var mid_foot: Vector3 = Canopy.screen_point(0.5, 0.0)
	var end_h: float = (Canopy.screen_point(0.0, 1.0) - Canopy.screen_point(0.0, 0.0)).length()
	var quarter_h: float = (Canopy.screen_point(0.25, 1.0) - Canopy.screen_point(0.25, 0.0)).length()
	var raked: bool = mid_top.z > mid_foot.z and mid_top.y > mid_foot.y
	_check("oblong and raked: %.2f m tall in the middle, %.2f at a quarter, %.3f at the ends; leaning back %.2f m" % [
		(mid_top - mid_foot).length(), quarter_h, end_h, mid_top.z - mid_foot.z],
		raked and absf((mid_top - mid_foot).length() - Canopy.SCREEN_H) < 0.01 and quarter_h < Canopy.SCREEN_H and quarter_h > 0.5 * Canopy.SCREEN_H and end_h < 0.01)
	var eye := Vector3(0.0, EYE_Y, 0.6)
	var up_deg := rad_to_deg(atan2(mid_top.y - eye.y, eye.z - mid_top.z))
	_check("you look through the glass: its foot %.2f m below the eye line, its frame %.0f deg above the horizon (out of the sightline)" % [EYE_Y - mid_foot.y, up_deg],
		mid_foot.y < EYE_Y and up_deg > 7.0 and up_deg < 20.0)
	# the field
	var p0: float = Canopy.field_power(0.0, "normal")
	var p1: float = Canopy.field_power(500.0 / 2.236936, "normal")
	var p2: float = Canopy.field_power(2000.0 / 2.236936, "normal")
	var p3: float = Canopy.field_power(4000.0 / 2.236936, "normal")
	var p4: float = Canopy.field_power(4000.0 / 2.236936, "burner")
	_check("the field builds with speed: still %.2f, 500 mph %.2f, 2,000 %.2f, 4,000 %.2f, burner %.2f" % [p0, p1, p2, p3, p4],
		p0 == 0.0 and p1 > 0.0 and p1 < p2 and p2 < p3 and p3 > 1.0 and p4 > p3)
	var c: Node3D = Canopy.build()
	root.add_child(c)
	Canopy.update(c, 1500.0, 0.0, "normal", 1.0 / 72.0)
	var m := (c.get_node("field") as MeshInstance3D).material_override as ShaderMaterial
	var t_sp: Vector3 = m.get_shader_parameter("tint")
	Canopy.update(c, 1500.0, 1.0, "normal", 1.0 / 72.0)
	var t_sf: Vector3 = m.get_shader_parameter("tint")
	var f := c.get_node("field") as MeshInstance3D
	var nose_z: float = f.position.z - f.scale.z
	var hull_nose: float = CM.HULL[0][0]
	_check("its colour follows the handling (SPEEDCRAFT %s, STARFIGHTER %s); it reaches %.2f m past the nose" % [t_sp, t_sf, hull_nose - nose_z],
		t_sp.z > t_sp.x and t_sf.x > 0.9 and t_sf.y < 0.4 and nose_z < hull_nose)
	# the flash: a bump flares it, and it fades
	var p_base: float = Canopy.field_power(1500.0, "normal")
	Canopy.flash(c, 1.0)
	Canopy.update(c, 1500.0, 0.0, "normal", 1.0 / 72.0)
	var p_fl: float = m.get_shader_parameter("power")
	var t_fl: Vector3 = m.get_shader_parameter("tint")
	for k in 36:
		Canopy.update(c, 1500.0, 0.0, "normal", 1.0 / 72.0)
	var p_after: float = m.get_shader_parameter("power")
	_check("a forcefield's push flares it: power %.2f (%.2f without), tint %s; half a second on %.2f" % [p_fl, p_base, t_fl, p_after],
		p_fl > p_base + 1.0 and t_fl.x > 0.7 and absf(p_after - p_base) < 0.01)
	# built into both views
	var vr_c: Node3D = v.canopy
	var flat_c: Node3D = v.craft.canopy
	_check("built into the VR cockpit and the pod, every piece marked exterior",
		vr_c != null and flat_c != null and vr_c.is_in_group("exterior") and vr_c.get_node("windscreen").is_in_group("exterior")
		and vr_c.get_node("field").is_in_group("exterior") and flat_c.get_parent() == v.craft.pod)
	var good := fails == 0 and passed == 7
	print("CANOPY ", "PASS" if good else "FAIL (%d failed, %d passed)" % [fails, passed])
	quit(0 if good else 1)
	return true


func _check(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if ok:
		passed += 1
	else:
		fails += 1
