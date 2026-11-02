## Headless: which joypads LeverInput may treat as levers or a gamepad.
## Run: Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_lever_input.gd
## Regression 2026-10-17: a Keychron K10 HE (Hall-effect keyboard with an analog-joystick
## interface, axes resting at 0.0) was read as both levers parked at 50%, overwriting
## the Touch thumbsticks every frame.
extends SceneTree

const LeverInputScript := preload("res://input/lever_input.gd")


func _initialize() -> void:
	var cases := [
		["Keychron K10 HE", false, "ignore"],
		["Phaethon Levers", false, "levers"],
		["Raspberry Pi Pico", false, "levers"],
		["Pico", false, "levers"],
		["Xbox Series Controller", true, "gamepad"],
		["Fanatec CSL Pedals", false, "ignore"],
	]
	var fails := 0
	for c in cases:
		var got: String = LeverInputScript.classify_pad(c[0], c[1])
		var ok: bool = got == c[2]
		fails += 0 if ok else 1
		print(("  ok   " if ok else "  FAIL ") + "%s (known=%s) -> %s, want %s" % [c[0], c[1], got, c[2]])
	# Both grips: level both levers to the lower of the two (corner exit, sway recovery).
	for c in [[0.8, 0.3, 0.3], [0.2, 0.9, 0.2], [0.5, 0.5, 0.5], [1.0, 0.0, 0.0]]:
		var li = LeverInputScript.new()
		li.thr_l = c[0]
		li.thr_r = c[1]
		li.level_to_lower()
		var ok: bool = is_equal_approx(li.thr_l, c[2]) and is_equal_approx(li.thr_r, c[2])
		fails += 0 if ok else 1
		print(("  ok   " if ok else "  FAIL ") + "level %.1f/%.1f -> %.1f/%.1f, want %.1f" % [c[0], c[1], li.thr_l, li.thr_r, c[2]])
	print("LEVER INPUT ", "PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(1 if fails > 0 else 0)
