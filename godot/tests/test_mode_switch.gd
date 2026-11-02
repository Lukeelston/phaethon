## The MODE switch gate (vr/mode_switch.gd; Luke: "physically flipping a switch on the virtual
## dashboard [which also changes interior and cable lighting mode]"). A fake controller drives it:
##   throw     a tip pushed down through the lever's zone at 0.6 m/s throws it to STARFIGHTER, once;
##             pushed back up, to SPEEDCRAFT
##   no throw  the same move too slowly, or beside the zone, or straight back within the 1 s
##             cooldown, does nothing (Luke: "a 1 second cool down between flips"); the view's
##             own gate holds the Y hold and the M key to it too
##   lamps     the lit lamp and the blink follow the state; the lever swings down for STARFIGHTER
##   lighting  the cables' thrust glow and the cockpit rim light turn from blue to magenta with the
##             sim's live blend; the burner still goes white-hot, the strain still amber/red
## Prints MODE SWITCH PASS.
## Run: Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_mode_switch.gd
extends SceneTree

const SW := preload("res://vr/mode_switch.gd")
const CM := preload("res://view/craft_model.gd")
const Interior := preload("res://vr/cockpit_interior.gd")
var fails := 0
var passed := 0


var frames := 0


func _process(_d: float) -> bool:
	frames += 1
	if frames < 2:
		return false
	_run()
	return true


func _initialize() -> void:
	pass


func _run() -> void:
	var rig := Node3D.new()
	root.add_child(rig)
	var sw = SW.new()
	rig.add_child(sw)
	sw.transform = SW.mount()
	sw.build()
	var hand := Node3D.new()
	rig.add_child(hand)
	var dt := 1.0 / 72.0
	# a sweep in the panel's own frame, mapped back to where the controller would be
	var sweep := func(x: float, y0: float, y1: float, speed: float, rest := 80) -> Array:
		var got := []
		hand.global_transform = Transform3D(Basis(), sw.global_transform * Vector3(0.4, y0, 0.3) - SW.TIP)   # come in from outside the zone
		sw.poke(hand, dt)
		var n := int(absf(y1 - y0) / speed / dt) + 1
		for i in n + 1:
			var y := lerpf(y0, y1, float(i) / n)
			var tip_world: Vector3 = sw.global_transform * Vector3(x, y, 0.05)
			hand.global_transform = Transform3D(Basis(), tip_world - SW.TIP)
			var a: String = sw.poke(hand, dt)
			if a != "":
				got.append(a)
		for i in rest:   # rest: the cooldown runs out
			sw.poke(hand, dt)
		return got
	var down_fast: Array = sweep.call(0.0, 0.09, -0.09, 0.6)
	_check("a fast push down through the lever throws it to STARFIGHTER once (%s)" % [down_fast], down_fast == ["starfighter"] and sw.down)
	var down_again: Array = sweep.call(0.0, 0.09, -0.09, 0.6)
	var up_fast: Array = sweep.call(0.0, -0.09, 0.09, 0.6)
	_check("pushing it down again does nothing (%s); a fast push up throws it back to SPEEDCRAFT (%s)" % [down_again, up_fast],
		down_again.is_empty() and up_fast == ["speed"] and not sw.down)
	var slow: Array = sweep.call(0.0, 0.09, -0.09, 0.12)
	var beside: Array = sweep.call(0.2, 0.09, -0.09, 0.6)
	_check("a slow drift through it (%s) or a fast pass beside it (%s) doesn't throw it" % [slow, beside], slow.is_empty() and beside.is_empty() and not sw.down)
	# the cooldown: down, then straight back up inside the second does nothing; a second later it throws
	var first: Array = sweep.call(0.0, 0.09, -0.09, 0.6, 0)
	var quick: Array = sweep.call(0.0, -0.09, 0.09, 0.6, 80)
	var later: Array = sweep.call(0.0, -0.09, 0.09, 0.6, 80)
	var View := load("res://view/craft_view.gd")
	var v = View.new()
	var a1: bool = v.ask_handling("starfighter")
	var a2: bool = v.ask_handling("speed")
	OS.delay_msec(1050)
	var a3: bool = v.ask_handling("speed")
	v.free()
	_check("a 1 s cooldown between flips: down %s, straight back up inside it %s, a second later %s; the view's gate (Y hold, M) %s / %s / %s" % [
		first, quick, later, a1, a2, a3], first == ["starfighter"] and quick.is_empty() and later == ["speed"] and a1 and not a2 and a3)
	# lamps and lever
	for i in 20:
		sw.show_state(true, 1.0, false)
	var sf_lit: float = sw.lamp_sf.albedo_color.v
	var sp_dim: float = sw.lamp_sp.albedo_color.v
	var swing_down: float = sw.lever.rotation.x
	var blinks := {}
	for i in 60:
		sw.show_state(true, 0.0, true)
		blinks[snappedf(sw.lamp_sf.albedo_color.v, 0.05)] = true
		OS.delay_msec(10)
	_check("lamps: STARFIGHTER lit (%.2f vs SPEED %.2f), the lever down (%.1f deg), the lamp blinking while it waits (%d levels)" % [
		sf_lit, sp_dim, rad_to_deg(swing_down), blinks.size()], sf_lit > sp_dim * 2.0 and swing_down > deg_to_rad(25.0) and blinks.size() >= 4)
	# lighting
	var g_sp: Color = CM.cable_glow(0.6, 0.0)[1]
	var g_sf: Color = CM.cable_glow(0.6, 1.0)[1]
	var g_burn: Color = CM.cable_glow(1.4, 1.0)[1]
	var inner = Interior.new()
	rig.add_child(inner)
	inner.build()
	inner.set_mode("normal", 0.0)
	var rim_sp: Color = inner.rim_mat.albedo_color
	inner.set_mode("normal", 1.0)
	var rim_sf: Color = inner.rim_mat.albedo_color
	inner.set_mode("burner", 1.0)
	var rim_burn: Color = inner.rim_mat.albedo_color
	_check("lighting: cables %s -> %s (burner %s), rim light %s -> %s (burner %s)" % [g_sp.to_html(false), g_sf.to_html(false), g_burn.to_html(false),
		rim_sp.to_html(false), rim_sf.to_html(false), rim_burn.to_html(false)],
		g_sp.b > g_sp.r and g_sf.r > g_sf.g and g_sf.b > g_sf.g and g_burn.g > 0.8 and rim_sp.b > rim_sp.r and rim_sf.r > 0.9 and rim_sf.g < 0.4 and rim_burn.r > 0.9 and rim_burn.b < 0.3)
	var good := fails == 0 and passed == 6
	print("MODE SWITCH ", "PASS" if good else "FAIL (%d failed, %d passed)" % [fails, passed])
	quit(0 if good else 1)


func _check(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if ok:
		passed += 1
	else:
		fails += 1
