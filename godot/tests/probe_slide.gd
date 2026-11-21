## How far does the pod step out in a turn, and at what cornering load? Not a test: a table.
## For each speed and each way of turning (ease one lever, one brake half out, one brake full out),
## fly straight, hold the turn for 2.5 s, and print the peak cornering load, the pod's sideways
## angle behind the engines, its nose's angle off theirs, and its slip (heading against its travel).
##   --headless -s res://tests/probe_slide.gd [-- --track=range]
extends SceneTree
const Model := preload("res://sim/craft_sim.gd")
const DT := 1.0 / 480.0

func _initialize() -> void:
	print("mph    turn                 peak g   swing set  pod out   nose in   slip    yaw rate")
	for mph: float in [600.0, 1200.0, 2000.0, 3000.0]:
		for turn in [["ease a lever to 60%", 0.6, 0.0], ["ease a lever to 25%", 0.25, 0.0], ["half brake", 1.0, 0.5], ["full brake", 1.0, 1.0], ["lever 25% + full brake", 0.25, 1.0]]:
			var sim := Model.new({"track": "range", "startY": -3000.0})
			for body in sim.bodies:
				body.vx = mph / 2.23694
			var inp := {"thrL": 0.8, "thrR": 0.8, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": true}
			var peak_g := 0.0
			var peak_set := 0.0
			var peak_out := 0.0
			var peak_nose := 0.0
			var peak_slip := 0.0
			var peak_w := 0.0
			for i in 1680:
				var on := i > 240 and i < 1440
				inp.thrR = 0.8 * float(turn[1]) if on else 0.8
				inp.brkR = float(turn[2]) if on else 0.0
				sim.step(inp, DT)
				var pf := cos(sim.pair_th)
				var ps := sin(sim.pair_th)
				var wpair: float = (sim.eL.w + sim.eR.w) * 0.5
				var g: float = absf(wpair * maxf(0.0, sim.pod.vx * pf + sim.pod.vy * ps) / 9.81)
				var dx: float = (sim.eL.x + sim.eR.x) * 0.5 - sim.pod.x
				var dy: float = (sim.eL.y + sim.eR.y) * 0.5 - sim.pod.y
				var out := absf(rad_to_deg(Model.wrap_angle(atan2(dy, dx) - sim.pair_th)))
				var nose := absf(rad_to_deg(Model.wrap_angle(sim.pod.th - sim.pair_th)))
				var slip := absf(rad_to_deg(Model.wrap_angle(sim.pod.th - atan2(sim.pod.vy, sim.pod.vx))))
				if on:
					peak_g = maxf(peak_g, g)
					peak_set = maxf(peak_set, absf(rad_to_deg(sim.tow_swing)))
					peak_out = maxf(peak_out, out)
					peak_nose = maxf(peak_nose, nose)
					peak_slip = maxf(peak_slip, slip)
					peak_w = maxf(peak_w, absf(rad_to_deg(wpair)))
			print("%-6.0f %-22s %5.1f    %5.2f     %5.2f    %5.2f    %5.2f   %5.1f deg/s" % [mph, turn[0], peak_g, peak_set, peak_out, peak_nose, peak_slip, peak_w])
	quit()
