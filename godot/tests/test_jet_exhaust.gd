## Exhaust gate (view/jet_exhaust.gd): the vanes answer the turn as it is flown, at a real
## actuator's rate; the jet turns less than the metal; the nozzle opens before the burner lights
## and the burner lights by zones; the shock cells are Tam's; a vectored jet runs straight in still
## air and is carried round at speed; hot metal glows only when it is hot enough, and cools slowly.
## Prints JET EXHAUST PASS when every check passes.
## Run: Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_jet_exhaust.gd -- --mute
extends SceneTree

const Jets := preload("res://view/jet_exhaust.gd")
const CHECKS := 9

var fails := 0
var passed := 0   # a script error aborts a check without failing it, so PASS needs every one


func _initialize() -> void:
	_vanes_as_flown()
	_actuator()
	_turning()
	_nozzle_and_light()
	_cells()
	_bend()
	_metal()
	_ramjet()
	_reach()
	var good := fails == 0 and passed == CHECKS
	print("JET EXHAUST ", "PASS" if good else "FAIL (%d failed, %d of %d ran)" % [fails, passed + fails, CHECKS])
	quit(0 if good else 1)


func _check(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	passed += 1 if ok else 0
	fails += 0 if ok else 1


## His flights' steering (memory of the eighth: split median 0.03 at 4 g, 0.17 at 21 g, 0.26 at
## 33 g, both levers up on the burner). On the split alone these were 0.9, 5 and 8 degrees.
func _vanes_as_flown() -> void:
	var median := rad_to_deg(Jets.command(0.03, 4.0, 1.45))
	var firm := rad_to_deg(Jets.command(0.17, 21.0, 1.45))
	var hard := rad_to_deg(Jets.command(0.26, 33.0, 1.45))
	var left := rad_to_deg(Jets.command(-0.17, -21.0, 1.45))
	var most := rad_to_deg(Jets.command(1.0, 80.0, 1.0))
	var dry := rad_to_deg(Jets.command(0.0, 10.0, 0.6))
	var lit := rad_to_deg(Jets.command(0.0, 10.0, 1.45))
	_check("vanes as he flies: %.1f deg in his median turn, %.1f in a firm one, %.1f in a hard one (%.1f to the left); never past %.0f (%.1f); the same 10 g wants %.1f deg dry and %.1f on the burner" % [
		median, firm, hard, left, rad_to_deg(Jets.VANE_MAX), most, dry, lit],
		median > 2.0 and median < 8.0 and firm > 12.0 and hard > 18.0 and is_equal_approx(left, -firm)
		and most <= rad_to_deg(Jets.VANE_MAX) + 1e-4 and absf(rad_to_deg(Jets.VANE_MAX) - 25.0) < 0.01 and dry > lit)


func _actuator() -> void:
	var dt := 1.0 / 120.0
	var a := 0.0
	var fastest := 0.0
	var t_full := -1.0
	for i in 120:
		var was := a
		a = Jets.slew(a, Jets.VANE_MAX, dt)
		fastest = maxf(fastest, (a - was) / dt)
		if t_full < 0.0 and a > 0.98 * Jets.VANE_MAX:
			t_full = (i + 1) * dt
	_check("actuators: straight to hard over in %.2f s, never faster than %.0f deg/s (limit %.0f)" % [t_full, rad_to_deg(fastest), rad_to_deg(Jets.VANE_SLEW)],
		t_full >= Jets.VANE_MAX / Jets.VANE_SLEW - 1e-3 and t_full < 0.5 and fastest <= Jets.VANE_SLEW + 1e-6)


func _turning() -> void:
	_check("the jet turns %.0f %% of the vanes' angle dry, %.0f %% on the full burner" % [Jets.turning(0.0) * 100.0, Jets.turning(1.0) * 100.0],
		is_equal_approx(Jets.turning(0.0), 0.70) and is_equal_approx(Jets.turning(1.0), 0.50) and Jets.turning(0.5) < 0.70)


func _nozzle_and_light() -> void:
	var dt := 1.0 / 120.0
	var jet = Jets.new()
	for i in 240:      # idling
		jet.step(dt, true, "normal", 0.03, 0.3, 0.0)
	var idle: float = jet.exit
	for i in 240:      # full dry thrust
		jet.step(dt, true, "normal", 1.0, 0.3, 300.0)
	var mil: float = jet.exit
	# the burner asked for: the flaps move first, the flame comes by zones
	var opening_dark := false
	var first_light := -1.0
	var all_lit := -1.0
	var lights := 0
	var was_flash := 0.0
	for i in 240:
		jet.step(dt, true, "burner", 1.45, 0.3, 300.0)
		var t := (i + 1) * dt
		if t < 0.25 and jet.lit == 0.0 and jet.exit > mil + 0.01:
			opening_dark = true
		if first_light < 0.0 and jet.lit > 0.0:
			first_light = t
		if all_lit < 0.0 and jet.lit > 0.98:
			all_lit = t
		if jet.flash > was_flash:
			lights += 1
		was_flash = jet.flash
	var wide: float = jet.exit
	var out := -1.0
	for i in 120:
		jet.step(dt, true, "normal", 1.0, 0.3, 300.0)
		if out < 0.0 and jet.lit < 0.02:
			out = (i + 1) * dt
	_check("nozzle: exit %.2f m tall at idle, %.2f at full dry thrust, %.2f on the burner; it opens before the flame (%s), the first zone lights at %.2f s, %d zones, all alight by %.2f s; shut, the flame is out in %.2f s" % [
		idle * 2.0, mil * 2.0, wide * 2.0, "yes" if opening_dark else "no", first_light, lights, all_lit, out],
		idle > mil + 0.03 and absf(mil - Jets.EXIT_MIL) < 0.005 and absf(wide - Jets.EXIT_MAX) < 0.005 and wide / mil > 1.5 and opening_dark
		and first_light >= 0.3 and first_light < 0.45 and lights == Jets.ZONES and all_lit > first_light + 0.3 and all_lit < 1.3 and out > 0.0 and out < 0.35)


func _cells() -> void:
	var tam: float = Jets.cell_length(0.54, 1.84, 1.5)
	var dt := 1.0 / 120.0
	var dry = Jets.new()
	var hot = Jets.new()
	var fast = Jets.new()
	for i in 360:
		dry.step(dt, true, "normal", 1.0, 0.3, 300.0)
		hot.step(dt, true, "burner", 1.45, 0.3, 300.0)
		fast.step(dt, true, "burner", 1.45, 0.3, 1300.0)
	_check("shock cells: Tam's %.2f m for a 0.54 by 1.84 m jet at Mach 1.5; here %.2f m dry, %.2f on the burner (the exit is wider), %.2f at 2,900 mph (jet Mach %.2f); none off a matched jet (%.2f)" % [
		tam, dry.cell, hot.cell, fast.cell, fast.mach, Jets.cell_length(0.54, 1.84, 1.0)],
		absf(tam - 1.158) < 0.01 and hot.cell > dry.cell and fast.cell > hot.cell and fast.cell < 3.5 and dry.cell > 0.5 and Jets.cell_length(0.54, 1.84, 1.0) == 0.0
		and hot.shock > 0.3 and hot.shock <= 1.0)


## Margason's line. In still air a vectored jet is a straight line; in a stream its slope has halved
## about 2.4 diameters times root J out (for 20 degrees); a faster stream bends it sooner.
func _bend() -> void:
	var d := deg_to_rad(20.0)
	var still: float = Jets.across(8.0, d, INF)
	var j := 1.5
	var x_half := 2.39 * Jets.D_EQ * sqrt(j)
	var slope: float = (Jets.across(x_half + 0.01, d, j) - Jets.across(x_half - 0.01, d, j)) / 0.02
	var slow: float = Jets.across(8.0, d, 26.0)
	var quick: float = Jets.across(8.0, d, 0.3)
	_check("the bend: in still air 8 m out the jet is %.2f m across (a straight line: %.2f); at J 1.5 its slope is %.0f %% of the first %.1f m out; 8 m out it is %.2f m across at Mach 0.3 and %.2f at speed; mirrored to the left %.2f" % [
		still, 8.0 * tan(d), slope / tan(d) * 100.0, x_half, slow, quick, Jets.across(8.0, -d, 0.3)],
		absf(still - 8.0 * tan(d)) < 1e-3 and absf(slope / tan(d) - 0.5) < 0.03 and slow < still and quick < 0.5 * slow and quick > 0.2
		and is_equal_approx(Jets.across(8.0, -d, 0.3), -quick) and Jets.across(8.0, 0.0, 1.0) == 0.0)


func _metal() -> void:
	var dt := 1.0 / 60.0
	var jet = Jets.new()
	for i in 600:
		jet.step(dt, true, "normal", 1.0, 0.3, 500.0)
	var dry_k: float = jet.metal
	var dry_glow: Color = Jets.metal_glow(dry_k)
	for i in 360:
		jet.step(dt, true, "burner", 1.45, 0.3, 500.0)
	var hot_k: float = jet.metal
	var hot_glow: Color = Jets.metal_glow(hot_k)
	for i in 300:      # five seconds after the burner is shut
		jet.step(dt, true, "normal", 1.0, 0.3, 500.0)
	var after_k: float = jet.metal
	var after_glow: Color = Jets.metal_glow(after_k)
	_check("hot metal: nothing under the Draper point (%.2f at 790 K); %.0f K on dry thrust (glow %.2f), %.0f K after 6 s of burner (glow %.2f, red %.2f over green %.2f), %.0f K five seconds after it is shut (glow %.2f)" % [
		Jets.metal_glow(790.0).r, dry_k, dry_glow.r, hot_k, hot_glow.r, hot_glow.r, hot_glow.g, after_k, after_glow.r],
		Jets.metal_glow(790.0) == Color.BLACK and dry_glow.r < 0.05 and hot_k > 1350.0 and hot_glow.r > 0.6 and hot_glow.g < 0.5 * hot_glow.r
		and after_k < hot_k - 150.0 and after_glow.r > dry_glow.r + 0.02 and after_glow.r < 0.9 * hot_glow.r)


func _ramjet() -> void:
	var dt := 1.0 / 120.0
	var jet = Jets.new()
	for i in 240:
		jet.step(dt, true, "burner", 1.45, 0.3, 2000.0)
	var before: float = jet.teb
	jet.step(dt, true, "ramjet", 1.45, 0.3, 2300.0)
	var lit: float = jet.teb
	for i in 120:
		jet.step(dt, true, "ramjet", 1.45, 0.3, 2300.0)
	_check("ramjet: lights on a chemical shot (%.2f before, %.2f at the light, %.3f a second on); its share then %.2f" % [before, lit, jet.teb, jet.ram],
		before == 0.0 and lit > 0.9 and jet.teb < 0.01 and jet.ram > 0.95)


func _reach() -> void:
	var dt := 1.0 / 120.0
	var dry = Jets.new()
	var hot = Jets.new()
	var out = Jets.new()
	for i in 360:
		dry.step(dt, true, "normal", 0.8, 0.3, 300.0)
		hot.step(dt, true, "burner", 1.45, 0.3, 1300.0)
		out.step(dt, false, "normal", 0.0, 0.3, 300.0)
	_check("how far it glows: %.1f m dry, %.1f m on the burner at speed (never past %.1f, short of the pod's nose), nothing from an engine that is out (%.1f); the jet still outruns the air it is in (%.0f m/s over 1,300)" % [
		dry.reach, hot.reach, Jets.REACH_MAX, out.reach, hot.gas],
		dry.reach > 0.5 and hot.reach > 2.0 * dry.reach and hot.reach <= Jets.REACH_MAX and out.reach == 0.0 and hot.gas > 1300.0 and hot.j < 3.0 and hot.j > 0.05)
