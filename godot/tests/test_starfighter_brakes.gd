## Lower-speed counterpart to Speedcraft: actual Quest grips into the real sim.
extends "res://tests/test_speed_brakes.gd"
var failures := 0
var checks := 0
func check(label: String, ok: bool) -> void:
	checks += 1
	failures += int(not ok)
	print(("PASS " if ok else "FAIL ")+label)
func _initialize() -> void:
	for mph in [400.0,600.0,800.0,1000.0]:
		var ov := {"handling":"starfighter"}
		var full := trial(mph,0,["held",1.0,1.0,1.0,0.0,true],ov)
		var right := trial(mph,0,["right",1.0,1.0,0.0,1.0,true],ov)
		var half := trial(mph,0,["half",1.0,1.0,0.5,0.0,true],ov)
		var feather := trial(mph,0,["feather",1.0,1.0,0.2,0.0,true],ov)
		var dual := trial(mph,0,["dual",1.0,1.0,1.0,1.0,true],ov)
		var coast := trial(mph,0,["coast_brake",0.0,0.0,1.0,0.0],ov)
		check("%.0fmph: unpowered braking cannot create kinetic energy"%mph,coast.energy_rises==0 and not coast.broken)
		var m: Dictionary = full.marks[2]
		check("%.0fmph: full grip gives useful tight-course radius %.1fm"%[mph,m.radius_m],m.radius_m<(400.0 if mph<=600.0 else (650.0 if mph==800.0 else 1000.0)))
		check("%.0fmph: held turn builds without spinning (%.1fdeg in3s)"%[mph,m.path_deg],m.path_deg>40.0 and m.path_deg<140.0)
		if mph>=600.0:
			check("%.0fmph: one grip sheds speed with both triggers held (%.1fmph)"%[mph,m.mph],m.mph<mph*0.85)
		check("%.0fmph: both grips slow harder and stay straight"%mph,dual.marks[2].mph<m.mph and absf(dual.marks[2].path_deg)<0.01)
		check("%.0fmph: partial grips offer progressively gentler curves"%mph,feather.marks[2].path_deg>0.0 and feather.marks[2].path_deg<half.marks[2].path_deg and half.marks[2].path_deg<m.path_deg and feather.marks[2].mph>half.marks[2].mph and half.marks[2].mph>m.mph)
		check("%.0fmph: left/right grips mirror"%mph,absf(right.marks[2].path_deg+m.path_deg)<0.01 and absf(right.marks[2].mph-m.mph)<0.01)
		for r in [full,right,half,feather,dual]:
			# In a tight turn the towed pod's velocity trails the nose by several
			# degrees (24m behind the engines). Release should settle along the
			# visible nose heading, not preserve that pre-release sideslip.
			var settle_error := absf(wrapf(deg_to_rad(r.marks[3].path_deg-r.marks[2].pod_nose_deg),-PI,PI))
			# Since 0.3.6 (32e7924) the tow bar sets the pod just outside a loaded turn on purpose (tow_swing, up
			# to 3 degrees; tests/test_tow_swing.gd allows the pod 4.5 out). The sway that must stay under 2
			# degrees is the pod's about that rest pose: the full-grip turn at 400 mph reads 2.04 in all.
			check("%.0fmph %s: stable craft (the pod %.2fdeg out, %.2f about its rest pose); release settles within2deg of nose (%.3fdeg)"%[mph,r.case,r.sway,r.sway_free,rad_to_deg(settle_error)],not r.broken and r.sway<4.5 and r.sway_free<2.0 and r.overrun<0.7 and absf(r.marks[3].yaw_dps)<0.5 and settle_error<deg_to_rad(2.0))
		print("MEASURE ",JSON.stringify({"mph":mph,"end_mph":m.mph,"turn_degrees":m.path_deg,"radius":m.radius_m}))
	_alternating()
	print("STARFIGHTER BRAKES %s (%d checks)"%["PASS" if failures==0 else "FAIL",checks])
	quit(0 if failures==0 else 1)

func _alternating() -> void:
	var sim := S.new({"track":"range","handling":"starfighter","startY":-3000.0})
	for b in sim.bodies: b.vx = 600.0/MPH
	var q := QC.new()
	q.sync_handling(1.0,true)
	q.set_gear(0)
	var out := {}
	var peak := 0.0
	var lo := 0.0
	var hi := 0.0
	var broken := false
	for i in 8*480:
		if i%8==0:
			var left := int(i/120)%2==0
			out = q.update({"lt":1.0,"rt":1.0,"lg":0.8 if left else 0.0,"rg":0.0 if left else 0.8,
				"ls":Vector2.ZERO,"rs":Vector2.ZERO,"lz":0.0,"rz":0.0,"speed":hypot(sim.pod.vx,sim.pod.vy),"yaw":(sim.eL.w+sim.eR.w)/2.0,"sf":sim.hblend},1.0/60.0)
		var inp := {"thrL":out.thrL,"thrR":out.thrR,"brkL":out.brkL,"brkR":out.brkR,"thrMul":out.mul,"gearOverdrive":out.overdrive,"burner":false,"repair":false,"reignite":true}
		sim.step(inp,DT)
		sim.events.clear()
		var yaw: float = rad_to_deg(sim.pod.w)
		lo = minf(lo,yaw)
		hi = maxf(hi,yaw)
		peak = maxf(peak,absf(yaw))
		broken = broken or sim.binder_broken
	check("rapid alternate grips produce controlled left/right steering: %.2f..%.2fdeg/s"%[lo,hi],lo < -3.0 and hi > 3.0 and peak < 65.0)
	check("rapid alternate grips keep the craft intact",not broken and is_finite(sim.pod.x) and is_finite(sim.pod.y))
	check("Starfighter retains one non-overdrive gear",q.gear==0 and not out.overdrive)
