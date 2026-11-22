## What the craft's fore-and-aft load is through a run as it is flown (not a test: a table, to set the
## speed rush's parallax by; vr/speed_rush.gd). The trigger scheme's own gearbox, both triggers fully in
## from a standstill, a shift up at nine tenths of each gear's revs, the burner lit in top; then both
## grips squeezed as the fourteenth flight's log has them (the harder side's median, three quarters and
## nine tenths: 0.25, 0.42, 0.65 of brake reach the sim), the triggers still in; then the triggers let
## go and both brakes full.
##   --headless -s res://tests/probe_rush.gd [-- --no-burner]
extends SceneTree
const Model := preload("res://sim/craft_sim.gd")
const Quest := preload("res://input/quest_controls.gd")
const Rush := preload("res://vr/speed_rush.gd")
const DT := 1.0 / 480.0
const FRAME := 1.0 / 90.0


func _initialize() -> void:
	var sim := Model.new({"track": "range", "startY": -3000.0})
	var quest := Quest.new()
	quest.set_gear(0)
	var burner_wanted := "--no-burner" not in OS.get_cmdline_user_args()
	var rush := Rush.new()
	var t := 0.0
	var acc := 0.0
	var g := 0.0
	var last_v := 0.0
	var flick := 0.0
	# seconds, both triggers, both grips (the brake that reaches the sim is about 0.6 of a grip's squeeze)
	var legs := [[45.0, 1.0, 0.0], [4.0, 1.0, 0.42], [3.0, 1.0, 0.0], [4.0, 1.0, 0.70], [3.0, 1.0, 0.0], [4.0, 1.0, 1.0], [3.0, 1.0, 0.0], [12.0, 0.0, 1.0]]
	print("   t     mph   mach   g along  gear  brk    shift mm (load, speed)")
	var frame := 0
	for leg in legs:
		for k in int(float(leg[0]) / FRAME):
			var v: float = sqrt(sim.pod.vx * sim.pod.vx + sim.pod.vy * sim.pod.vy)
			var c := {"lt": leg[1], "rt": leg[1], "lg": leg[2], "rg": leg[2], "ls": Vector2.ZERO, "rs": Vector2.ZERO,
				"speed": v, "airspeed": v, "yaw": (sim.eL.w + sim.eR.w) / 2.0, "sf": sim.hblend}
			flick = maxf(0.0, flick - FRAME)
			if quest.gear < Quest.GEARS.size() - 1 and quest.rpm >= 0.9 and flick <= 0.0 and float(leg[1]) > 0.5:
				c.rs = Vector2(0.0, 1.0)      # the right stick flicked up: the next gear
				flick = 0.3
			if burner_wanted and quest.gear == Quest.GEARS.size() - 1 and not quest.burner and flick <= 0.0 and float(leg[1]) > 0.5:
				c.ls = Vector2(0.0, 1.0)      # the left stick flicked up: the burner
				flick = 0.3
			var q: Dictionary = quest.update(c, FRAME)
			var inp := {"thrL": q.thrL, "thrR": q.thrR, "brkL": q.brkL, "brkR": q.brkR, "repair": false, "reignite": true,
				"burner": bool(q.get("burner", false)), "thrMul": q.get("mul", 1.0)}
			acc += FRAME
			while acc >= DT:
				sim.step(inp, DT)
				acc -= DT
			t += FRAME
			var now: float = sqrt(sim.pod.vx * sim.pod.vx + sim.pod.vy * sim.pod.vy)
			g += ((now - last_v) / FRAME / 9.81 - g) * (1.0 - exp(-FRAME / 0.15))      # (smoothed as the g-meter's is)
			last_v = now
			var mph := now * 2.236936
			rush.ease_surge(FRAME, g, mph, true)
			frame += 1
			if frame % 45 == 0:
				print("%5.1f  %6.0f  %5.2f  %7.2f   %d    %.2f   %6.1f  (%5.1f, %4.1f)%s" % [t, mph, now / 343.0, g, quest.gear, q.brkL,
					rush.surge * 1000.0, Rush.load_part(rush.load_g) * 1000.0, Rush.speed_part(mph) * 1000.0, "  burner" if inp.burner else ""])
	quit()
