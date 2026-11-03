## The wag meter (vr/wag_meter.gd) on yaw rates with known answers, 120 frames a second:
##   steady      a held 2 deg/s turn at 1,000 mph for 20 s: no swings
##   wag         the same turn with a 0.7 Hz, 3 deg/s wag on it: ~14 swings / 10 s, ~2.1 deg/s RMS
##   slow        the wag under 300 mph: nothing counted
##   gears       time in each gear adds up
## Prints WAG METER PASS.
## Run: Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_wag_meter.gd
extends SceneTree

const WM := preload("res://vr/wag_meter.gd")
const DT := 1.0 / 120.0
var fails := 0


func _initialize() -> void:
	var m = WM.new()
	for f in int(20.0 / DT):
		m.add(DT, deg_to_rad(2.0), 447.0, 4)
	_check("steady: a held 2 deg/s turn: %d swings, %.2f deg/s RMS" % [m.swings, m.rms()], m.swings == 0 and m.rms() < 0.3)
	m = WM.new()
	for f in int(20.0 / DT):
		m.add(DT, deg_to_rad(2.0 + 3.0 * sin(TAU * 0.7 * f * DT)), 447.0, 3 if f * DT < 5.0 else 4)
	_check("wag: a 0.7 Hz, 3 deg/s wag on the turn: %.1f swings / 10 s, %.2f deg/s RMS" % [m.per10(), m.rms()],
		absf(m.per10() - 14.0) < 1.5 and absf(m.rms() - 2.12) < 0.4)
	_check("gears: %s" % m.report(), absf(m.gear_t.get(3, 0.0) - 5.0) < 0.05 and absf(m.gear_t.get(4, 0.0) - 15.0) < 0.05)
	m = WM.new()
	for f in int(20.0 / DT):
		m.add(DT, deg_to_rad(3.0 * sin(TAU * 0.7 * f * DT)), 100.0, 1)
	_check("slow: the wag at 224 mph: %d swings over %.0f s" % [m.swings, m.t], m.swings == 0 and m.t == 0.0)
	print("WAG METER ", "PASS" if fails == 0 else "FAIL (%d failed)" % fails)
	quit(0 if fails == 0 else 1)


func _check(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if not ok:
		fails += 1
