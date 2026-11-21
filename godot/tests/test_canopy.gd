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
##   roof     the closed canopy (tools/art_roof_hd.py): fitted in both views; clear of the head; open
##            over it from the header back to the hood, with no glass drawn there; the road ahead all
##            glass; the patrol's light bar standing on the hood, out of the pilot's sight
## Prints CANOPY PASS.
## Run: Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_canopy.gd -- --track=range --mute
extends SceneTree

const Canopy := preload("res://view/canopy.gd")
const CM := preload("res://view/craft_model.gd")
const VRScript := preload("res://vr/vr_cockpit.gd")
const LightBar := preload("res://view/light_bar.gd")
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
			var x: float = CM.open_edge(ph).x
			var z: float = CM.open_edge(ph).y
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
	# the roof (Luke: "the vehicle needs to have a roof ... it's necessary to the immersion")
	var roof := vr_c.get_node_or_null("roof") as MeshInstance3D
	var pane := vr_c.get_node_or_null("roof_glass") as MeshInstance3D
	_check("a closed canopy is fitted in the VR cockpit and on the pod: roof and glass, both exterior, the oblong screen and its frame put away",
		roof != null and pane != null and roof.is_in_group("exterior") and pane.is_in_group("exterior")
		and not (vr_c.get_node("windscreen") as MeshInstance3D).visible and not (vr_c.get_node("frame") as MeshInstance3D).visible
		and flat_c.get_node_or_null("roof") != null)
	if roof != null and pane != null:
		# the roof is authored in the rig's frame: the seated eye is SEAT y 0.72 above the rig floor
		var head := Vector3(0.0, 0.72, 0.6)
		var solid := roof.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array
		var near := INF          # the nearest any of the roof's structure comes to the head
		var cone := 180.0        # looking up: the least angle off straight up at which anything solid stands ...
		var up_ahead := 180.0    # ... on the centre line ahead of it (the header) ...
		var up_behind := 180.0   # ... and behind it (the hood) ...
		var up_abeam := 180.0    # ... and straight out to either side (the cant rails)
		var ahead_lo := -90.0    # looking forward: the highest structure under the eye line (the rim) ...
		var ahead_hi := 90.0     # ... and the lowest above it (the header)
		for p in solid:
			near = minf(near, p.distance_to(head))
			var d := p - head
			if d.y > 0.05:
				cone = minf(cone, rad_to_deg(atan2(Vector2(d.x, d.z).length(), d.y)))
				if absf(d.x) < 0.03 and d.z < 0.0:
					up_ahead = minf(up_ahead, rad_to_deg(atan2(-d.z, d.y)))
				elif absf(d.x) < 0.03:
					up_behind = minf(up_behind, rad_to_deg(atan2(d.z, d.y)))
				if absf(d.z) < 0.03:
					up_abeam = minf(up_abeam, rad_to_deg(atan2(absf(d.x), d.y)))
			var fwd := head.z - p.z
			if fwd > 0.05 and absf(atan2(p.x - head.x, fwd)) < deg_to_rad(20.0):
				var el := rad_to_deg(atan2(p.y - head.y, Vector2(p.x - head.x, fwd).length()))
				if el < 0.0:
					ahead_lo = maxf(ahead_lo, el)
				else:
					ahead_hi = minf(ahead_hi, el)
		_check("headroom: nothing of the roof nearer the head than %.2f m" % near, near > 0.3)
		# (Luke: "the ceiling should sweep back even further so that you can see above during inverted flight")
		_check("open over the head: nothing solid within %.0f deg of straight up; on the centre line from %.0f deg ahead of it (the header) to %.0f behind (the hood), and %.0f either side (the cant rails)" % [cone, up_ahead, up_behind, up_abeam],
			cone > 33.0 and up_ahead > 35.0 and up_ahead < 45.0 and up_behind > 33.0 and up_behind < 60.0 and up_abeam > 45.0 and up_abeam < 70.0)
		var under := "no structure under the eye line at all" if ahead_lo <= -90.0 else "the rim %.0f deg under the eye line" % -ahead_lo
		_check("the road ahead is all glass: %s, the header %.0f deg over it" % [under, ahead_hi], ahead_lo < -8.0 and ahead_hi > 14.0)
		var clear := pane.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array
		var box := AABB(clear[0], Vector3.ZERO)
		var glazed := 180.0      # the least angle off straight up at which any of the glass is drawn
		for p in clear:
			box = box.expand(p)
			glazed = minf(glazed, rad_to_deg(atan2(Vector2(p.x - head.x, p.z - head.z).length(), p.y - head.y)))
		# (only the shade band is glass: the rest of each pane is open to the forcefield, and costs the frame nothing.
		# Over the head there is none at all: a blended surface there would be the whole view of a pilot looking up)
		_check("a shade band along the top of the screen and both windows: %.2f m wide, from %.2f to %.2f m over the eye line (out of the view ahead), none of it within %.0f deg of straight up" % [box.size.x, box.position.y - head.y, box.end.y - head.y, glazed],
			box.size.x > 0.8 and box.position.y > head.y + 0.15 and box.end.y > head.y + 0.3 and box.position.x < -0.4 and box.end.x > 0.4 and glazed > 33.0)
		# the patrol's light bar stands on the hood: over solid roof from end to end, down on its crown, and
		# behind the hood's bow as the seated eye sees it (its lamps do not flash in the pilot's own sky)
		var bar_at: Vector3 = LightBar.ON_ROOF - roof.position      # (the roof is drawn in the rig's frame, POD_FRAME_UP under the canopy's)
		var covered := true
		var seat_mid := -INF     # the hood's top under the bar's middle ...
		var seat_end := -INF     # ... and under its ends
		for step_x in 7:
			for step_z in 3:
				var spot := Vector2(lerpf(-0.33, 0.33, step_x / 6.0), bar_at.z + lerpf(-0.07, 0.07, step_z / 2.0))
				var top := -INF
				for p in solid:
					if p.y > head.y + 0.2 and Vector2(p.x, p.z).distance_to(spot) < 0.035:
						top = maxf(top, p.y)
				covered = covered and top > -INF
				if step_x == 3 and step_z == 1:
					seat_mid = top
				elif (step_x == 0 or step_x == 6) and step_z == 1:
					seat_end = maxf(seat_end, top)
		var under_bar := bar_at.y - 0.0225                      # the housing's underside
		var lamp_top := Vector3(0.0, bar_at.y + 0.07, bar_at.z - 0.065) - head
		var lamp_deg := rad_to_deg(atan2(lamp_top.z, lamp_top.y))
		_check("the patrol's light bar stands on the hood: solid roof under all of it, its underside %.0f mm off the crown under its middle and %.0f mm over the roof at its ends; its lamps %.0f deg behind straight up, behind the hood's bow (%.0f)" % [(under_bar - seat_mid) * 1000.0, (under_bar - seat_end) * 1000.0, lamp_deg, up_behind],
			covered and absf(under_bar - seat_mid) < 0.015 and under_bar - seat_end > -0.005 and under_bar - seat_end < 0.045 and lamp_deg > up_behind + 2.0)
	var good := fails == 0 and passed == 13
	print("CANOPY ", "PASS" if good else "FAIL (%d failed, %d passed)" % [fails, passed])
	quit(0 if good else 1)
	return true


func _check(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if ok:
		passed += 1
	else:
		fails += 1
