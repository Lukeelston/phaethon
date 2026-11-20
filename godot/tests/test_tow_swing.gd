## Measure actual trailer displacement relative to the two engine centres on the open range.
extends SceneTree
const Model := preload("res://sim/craft_sim.gd")
const DT := 1.0 / 480.0

func _initialize() -> void:
	var failures := 0
	for side: float in [-1.0,1.0]:
		var sim := Model.new({"track":"range","startY":-3000.0})
		for body in sim.bodies: body.vx = 1350.0
		var input := {"thrL":0.6,"thrR":0.6,"brkL":0.0,"brkR":0.0,"repair":false,"reignite":true}
		var straight := 0.0
		var loaded := 0.0
		var peak := 0.0
		var released := 0.0
		for i in 1680:
			var brake := 1.0 if i > 240 and i < 960 else 0.0
			input.brkL = brake if side > 0 else 0.0
			input.brkR = brake if side < 0 else 0.0
			sim.step(input,DT)
			var dx: float = (sim.eL.x+sim.eR.x)*0.5-sim.pod.x
			var dy: float = (sim.eL.y+sim.eR.y)*0.5-sim.pod.y
			var angle := side*rad_to_deg(Model.wrap_angle(atan2(dy,dx)-sim.pair_th))
			if i < 240: straight = maxf(straight,absf(angle))
			if i == 959: loaded = angle
			peak = maxf(peak,absf(rad_to_deg(sim.tow_swing)))
			if i > 1450: released = maxf(released,absf(angle))
		var ok := straight < 0.05 and loaded > 2.0 and loaded < 4.5 and peak <= 3.0001 and released < 0.12
		print("%s turn %.0f: straight %.3f, loaded outward %.3f, released %.3f deg" % ["PASS" if ok else "FAIL",side,straight,loaded,released])
		failures += int(not ok)
		sim.respawn()
		failures += int(sim.tow_swing != 0.0)
	print("TOW SWING ", "PASS" if failures==0 else "FAIL")
	quit(int(failures>0))
