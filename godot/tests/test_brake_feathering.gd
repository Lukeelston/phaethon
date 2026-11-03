## Brake onset through the real Quest input path: tiny toe, short blend, full authority,
## time-step independence, symmetry, and immediate neutralization in every control scheme.
extends SceneTree
const QC := preload("res://input/quest_controls.gd")
const Cockpit := preload("res://vr/vr_cockpit.gd")
var checks := 0
var fails := 0

func snap(grip: float, scheme := "triggers") -> Dictionary:
	return {"lt": 0.0 if scheme == "triggers" else grip, "rt": 0.0,
		"lg": grip if scheme == "triggers" else 0.0, "rg": 0.0,
		"ls": Vector2.ZERO, "rs": Vector2.ZERO, "lz": 0.0, "rz": 0.0,
		"speed": 4000.0 / 2.2369362920544, "sf": 0.0, "yaw": 0.0}

func check(label: String, ok: bool) -> void:
	checks += 1
	if not ok: fails += 1
	print(("PASS " if ok else "FAIL ") + label)

func _initialize() -> void:
	var toe := QC._grip_brake(QC.GRIP_DZ + (1.0 - QC.GRIP_DZ) * 0.01)
	check("first 1%% above grip deadzone has a soft toe: %.6f" % toe, toe > 0.0 and toe < 0.008)
	check("after the first 3%, steady grip mapping keeps authority", absf(QC._grip_brake(QC.GRIP_DZ + (1.0 - QC.GRIP_DZ) * 0.1) - 0.1) < 1e-9 and QC._grip_brake(1.0) == 1.0)
	for scheme in QC.SCHEMES:
		var q = QC.new()
		q.scheme = scheme
		var c := snap(1.0, scheme)
		var first: Dictionary = q.update(c, 1.0 / 60.0)
		var previous: float = first.brkL
		var monotonic := true
		var after: Dictionary
		for i in 8:
			after = q.update(c, 1.0 / 60.0)
			monotonic = monotonic and after.brkL >= previous
			previous = after.brkL
		check("%s: first frame %.4f eases toward %.4f without overshoot" % [scheme, first.brkL, after.brkL], first.brkL > 0.0 and first.brkL < after.brkL * 0.6 and monotonic)
		var settled: Dictionary
		for i in 60: settled = q.update(c, 1.0 / 60.0)
		check("%s: 150 ms retains over 99%% of full demand" % scheme, after.brkL >= settled.brkL * 0.99)
		var off: Dictionary = q.update(snap(0.0, scheme), 1.0 / 60.0)
		check("%s: release/focus-loss neutralizes both brakes immediately" % scheme, off.brkL == 0.0 and off.brkR == 0.0)
	var rates := []
	for hz in [30, 60, 90, 120]:
		var q = QC.new()
		var o: Dictionary
		for frame in hz / 10: o = q.update(snap(0.5), 1.0 / hz)
		rates.append(o.brkL)
	check("100 ms engagement independent of 30/60/90/120 Hz: %s" % [rates], rates.max() - rates.min() < 1e-8)
	var ql = QC.new()
	var qr = QC.new()
	var right := snap(0.0)
	right.rg = 0.5
	var symmetric := true
	for frame in 60:
		var l: Dictionary = ql.update(snap(0.5), 1.0 / 60.0)
		var r: Dictionary = qr.update(right, 1.0 / 60.0)
		symmetric = symmetric and absf(l.brkL - r.brkR) < 1e-9 and absf(l.brkR - r.brkL) < 1e-9
	check("left/right onset remains mirrored", symmetric)
	ql.next_scheme()
	var reengage: Dictionary = ql.update(snap(1.0, ql.scheme), 1.0 / 60.0)
	check("new scheme re-engages from zero pressure even with its brake held", reengage.brkL > 0.0 and reengage.brkL < 0.5)
	var reset: Dictionary = ql.update(snap(0.0, ql.scheme), 1.0 / 60.0)
	check("changing scheme cannot retain brake pressure", reset.brkL == 0.0 and reset.brkR == 0.0)
	var h0 := Cockpit.brake_haptic_strength(0.03)
	var h1 := Cockpit.brake_haptic_strength(0.031)
	var h2 := Cockpit.brake_haptic_strength(0.06)
	check("rumble has no minimum kick at first contact", h0 == 0.0 and h1 > 0.0 and h1 < 0.001 and h2 > h1 and h2 < 0.03)
	check("full shudder retains its original rumble strength", is_equal_approx(Cockpit.brake_haptic_strength(1.0), 0.8))
	print("BRAKE FEATHERING %s (%d checks, %d failures)" % ["PASS" if fails == 0 else "FAIL", checks, fails])
	quit(int(fails > 0))
