## Replay a clean ramjet lap through the production Godot simulation.
extends SceneTree
const Sim := preload("res://sim/craft_sim.gd")
const UI := preload("res://release/release_config.gd")
var fails := 0
func check(label: String, ok: bool) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: fails+=1
func _initialize() -> void:
	var sim := Sim.new({"track":"carving"})
	var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/replay/carving_expected.json"))
	var inputs: Array = JSON.parse_string(FileAccess.get_file_as_string("res://tests/replay/carving_inputs.json"))
	check("menu exposes carving",UI.course_index("carving")>=0)
	check("closed circuit starts in Speedcraft",sim.course and sim.track_name=="carving" and sim.P.handling=="speed")
	print("Geometry GD ",sim.N," / ",sim.track_length,"; JS ",expected.track_samples," / ",expected.track_length)
	check("same sample count and length as JS",sim.N==int(expected.track_samples) and absf(sim.track_length-expected.track_length)<0.01)
	var valid := true
	for i in sim.N:
		valid = valid and sim.tlen[i]>0 and sim.tlen[i]<12.01 and sim.tw[i]==200.0 and sim.tmode[i]==1 and sim.tb[i]==0.0
	check("continuous 200m flat Speedcraft road, including finish seam",valid)
	sim.armed=true
	var lap := -1.0
	var hits := 0
	var ramjet := 0.0
	var top := 0.0
	for u in inputs:
		for k in 8:
			sim.step({"thrL":u[0],"thrR":u[1],"brkL":u[2],"brkR":u[3],"repair":false,"reignite":true,"handling":"speed"},1.0/480.0)
			if sim.mode=="ramjet": ramjet+=1.0/480.0
			top=maxf(top,Vector2(sim.pod.vx,sim.pod.vy).length()*2.236936)
			for e in sim.events:
				if e.type=="lap": lap=e.t
				if e.type=="hit": hits+=1
			sim.events.clear()
			if lap>0: break
		if lap>0: break
	check("all checkpoints complete a real lap",lap>0 and absf(lap-expected.lap_time)<0.1)
	check("no wall impacts or broken binder",hits==0 and not sim.binder_broken)
	check("ramjet active through the lap",ramjet>100.0 and absf(ramjet-expected.ramjet_seconds)<0.1)
	check("speed and final position match JS",absf(top-expected.top_mph)<1.0 and Vector2(sim.pod.x-expected.final_pod[0],sim.pod.y-expected.final_pod[1]).length()<1.0)
	print("CARVING %s: %.3fs, %.0fmph peak, %d hits"%["PASS" if fails==0 else "FAIL",lap,top,hits])
	quit(0 if fails==0 else 1)
