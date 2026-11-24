## Headless parity of the craft's attributes and powers: the GDScript CraftSim against the JS reference
## (tools/record_traits.js; the same runs and input schedules below), one short run a craft with its power armed:
## Slipstream, Glide (the Talon's row on the Phaethon's chassis until the Talon is merged), Kickdown, Gyro Lock,
## Ram Plate (through a vehicle), Ground Effect, the Basilisk's turret drag. Each is held to the reference's place
## every half second and to its power events (and its bumps), step for step.
## Run: --headless --xr-mode off --audio-driver Dummy -s res://tests/test_traits_parity.gd
## Prints TRAITS PARITY PASS only when every check passed.
extends SceneTree

const CraftSimScript := preload("res://sim/craft_sim.gd")
const DT := 1.0 / 480.0


static func _base() -> Dictionary:
	return {"thrL": 0.87, "thrR": 0.87, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": true, "power": true}


## The inputs of run `craft` at step i (tools/record_traits.js RUNS, mirrored).
static func _input(craft: String, i: int) -> Dictionary:
	var u := _base()
	match craft:
		"phaethon":
			if i < 7 * 480:
				u.draft = true
			if i == 3600:
				u.powerFire = true
		"talon":
			if i >= 3 * 480 and i < 5 * 480:
				u.thrL = 0.6
		"shrike":
			if i < 480 or (i >= 6 * 480 and i < 6 * 480 + 96) or (i >= 16 * 480 and i < 16 * 480 + 96):
				u.thrL = 0.0
				u.thrR = 0.0
		"orrery":
			if i >= 480:
				u.thrL = 0.4
			if i == 960:
				u.powerFire = true
		"kiln":
			if i == 240:
				u.powerFire = true
		"vesper":
			if i >= 3 * 480 and i < 3 * 480 + 240:
				u.thrL = 0.6
		"basilisk":
			if i >= 480 and i < 3 * 480:
				u.turretOut = true
	return u


# [craft, overrides, start speed m/s, seconds, obstacles [ahead, across, speed, radius]]
const RUNS := [
	["phaethon", {"vehicle": "phaethon", "track": "range", "startY": -3000.0}, 0.0, 14, []],
	["talon", {"vehicle": "phaethon", "traitsOf": "talon", "track": "range", "startX": 18000.0, "startY": 400.0}, 1341.12, 14, []],
	["shrike", {"vehicle": "shrike", "track": "range", "startY": -3000.0}, 0.0, 20, []],
	["orrery", {"vehicle": "orrery", "track": "range", "startY": -3000.0}, 447.04, 10, []],
	["kiln", {"vehicle": "kiln", "track": "range", "startY": -3000.0}, 447.04, 6, [[300.0, 0.0, 200.0, 5.2]]],
	["vesper", {"vehicle": "vesper", "track": "range", "startY": -3000.0}, 1117.6, 6, []],
	["basilisk", {"vehicle": "basilisk", "track": "range", "startY": -3000.0}, 447.04, 5, []],
]


func _initialize() -> void:
	var want: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/replay/traits_expected.json"))
	var fails := 0
	var checks := 0
	for run: Array in RUNS:
		var craft: String = run[0]
		var ref: Dictionary = want.runs[craft]
		var sim = CraftSimScript.new((run[1] as Dictionary).duplicate())
		for b in sim.bodies:
			b.vx = float(run[2])
			b.vy = 0.0
		var obs := []
		var k := 0
		for o: Array in run[4]:
			k += 1
			obs.append({"id": k, "x": sim.pod.x + float(o[0]), "y": sim.pod.y + float(o[1]), "vx": float(o[2]), "vy": 0.0, "r": float(o[3])})
		sim.obstacles = obs
		var events := []
		var worst := 0.0
		var worst_th := 0.0
		var mi := 0
		for i in int(run[3]) * 480:
			sim.step(_input(craft, i), DT)
			for e: Dictionary in sim.events:
				if e.type == "power":
					events.append([e.state, i])
				elif e.type == "bump" or e.type == "smash":
					events.append([String(e.type) + (" ram" if e.get("ram", false) else ""), i])
			sim.events.clear()
			if (i + 1) % 240 == 0:
				var m: Array = ref.marks[mi]
				worst = maxf(worst, Vector3(sim.pod.x - float(m[0]), sim.pod.y - float(m[1]), sim.pod.z - float(m[2])).length())
				worst_th = maxf(worst_th, absf(rad_to_deg(CraftSimScript.wrap_angle(sim.pod.th - float(m[3])))))
				mi += 1
		var same_events := events.size() == (ref.events as Array).size()
		if same_events:
			for j in events.size():
				same_events = same_events and events[j][0] == ref.events[j][0] and int(events[j][1]) == int(ref.events[j][1])
		fails += _check("%-9s %-10s %d marks, the farthest %.5f m and %.5f deg off; %d events %s (%s)" % [craft, sim.power, mi, worst, worst_th,
			events.size(), "as the reference's" if same_events else "NOT as the reference's %s" % [ref.events], _events_text(events)],
			sim.power == ref.power and mi == (ref.marks as Array).size() and worst <= 0.05 and worst_th <= 0.05 and same_events
			and sim.power_state == ref.end[0] and absf(sim.power_gauge - float(ref.end[1])) < 1e-9)
		checks += 1
	var good: bool = fails == 0 and checks == RUNS.size()
	print("TRAITS PARITY ", "PASS" if good else "FAIL (%d failed of %d)" % [fails, checks])
	quit(0 if good else 1)


static func _events_text(events: Array) -> String:
	var parts := []
	for e in events:
		parts.append("%s@%.2f" % [e[0], float(e[1]) * DT])
	return " ".join(parts)


func _check(label: String, ok: bool) -> int:
	print(("  ok   " if ok else "  FAIL ") + label)
	return 0 if ok else 1
