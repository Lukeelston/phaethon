extends SceneTree

var fails := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		fails += 1
		push_error(message)

func packet(x: float, seq := 1.0, epoch := 0.0) -> PackedFloat64Array:
	var p := PackedFloat64Array([seq, epoch])
	for i in 3:
		p.append_array(PackedFloat64Array([x + i, 3.0, -240000.125, 0, 0, 0, 1]))
	p.append_array(PackedFloat64Array([0.7, 0.8, 0]))
	return p

func _initialize() -> void:
	if not ResourceLoader.exists("res://online/pose_buffer.gd"):
		check(false, "Online pose protocol has not been implemented")
		quit(1)
		return
	var script = load("res://online/pose_buffer.gd")
	var a := packet(100000.125)
	check(script.valid_packet(a), "Real-world double precision pose accepted")
	check(not script.valid_packet({"body": a}), "Dictionary payload rejected")
	check(not script.valid_packet(PackedFloat64Array([1, 2])), "Truncated pose rejected")
	var bad := a.duplicate()
	bad[2] = NAN
	check(not script.valid_packet(bad), "Non-finite coordinates rejected")
	bad = a.duplicate()
	bad[2] = 1e20
	check(not script.valid_packet(bad), "Unbounded coordinates rejected")
	bad = a.duplicate()
	bad[8] = 0.0
	check(not script.valid_packet(bad), "Zero quaternion rejected")
	var buffer = script.new()
	check(buffer.push(a, 1000), "First packet accepted")
	check(buffer.push(packet(100010.125, 2), 1100), "Next packet accepted")
	check(not buffer.push(a, 1200), "Reordered packet rejected")
	var middle: PackedFloat64Array = buffer.sample(1150)
	check(absf(middle[2] - 100005.125) < 0.00001, "100ms interpolation preserves absolute precision")
	check(buffer.sample(3201).is_empty(), "Stale racer disappears after two seconds")
	check(buffer.push(packet(900000.125, 3, 1), 3300), "Respawn packet accepted")
	check(absf(buffer.sample(3300)[2] - 900000.125) < 0.00001, "Respawn snaps without crossing the world")
	var turn := packet(900010.125, 4, 1)
	for i in 3:
		turn[2 + i * 7 + 4] = 1.0
		turn[2 + i * 7 + 6] = 0.0
	buffer.push(turn, 3400)
	var turned: PackedFloat64Array = buffer.sample(3450)
	check(absf(turned[6] - sqrt(0.5)) < 0.001, "Orientation uses quaternion interpolation")
	print("ONLINE PROTOCOL %s" % ("PASS" if fails == 0 else "FAIL"))
	quit(0 if fails == 0 else 1)
