extends "res://tests/test_partner_maneuvers.gd"
const Distances := preload("res://view/skill_score.gd")
func _run() -> void:
	View.track_override = "network"
	View.job_override = "none"
	view = View.new()
	root.add_child(view)
	view.set_process(false)
	for r in view.sim.roads.size():
		if view.sim.roads[r].name == "E2": road = r
	view.set_partner(false)
	pose(6000.0, 1)
	view.traffic_net.cars.clear()
	view.set_partner(true)
	var p = view.partner
	var c = Traffic.Car.new()
	c.road = road
	c.v = 1000.0
	c.lat = 67.5
	var closest := INF
	for frame in 180:
		var f := 6000.0 + frame * DT * 1000.0 / 24.0
		pose(f, 1)
		var s = view.sim
		var R = s.roads[road]
		var shift := minf(14.0, frame * DT * 28.0)
		for b in s.bodies:
			b.x += R.nx[int(f)] * shift
			b.y += R.ny[int(f)] * shift
			if frame < 30:
				b.vx += R.nx[int(f)] * 28.0
				b.vy += R.ny[int(f)] * 28.0
		c.f = f + 14.0 / 24.0
		view.traffic_net._place(c)
		view.traffic_net.cars.assign([c])
		p.update(DT)
		var fw := Vector2(cos(p.th), sin(p.th))
		var lf := Vector2(-fw.y, fw.x)
		var lat: float = s.P.engineGap / 2.0 - s.P.podAnchorW * s.P.podWidth / 2.0
		var ahead: float = sqrt(s.P.cableLen*s.P.cableLen-lat*lat)+s.P.podLen/2.0+s.P.engineLen/2.0
		var points := [Vector2(p.x,p.y), Vector2(p.x,p.y)+fw*ahead+lf*s.P.engineGap/2.0, Vector2(p.x,p.y)+fw*ahead-lf*s.P.engineGap/2.0]
		var traffic_pos := Vector2(c.x,c.y)
		var traffic_fw := Vector2(c.hx,c.hy)
		for k in 3:
			var length: float = s.P.podLen if k == 0 else s.P.engineLen
			var half_length := maxf(0.0,length/2.0-1.2)
			closest = minf(closest, Distances._segment_distance(points[k]-fw*half_length,points[k]+fw*half_length,traffic_pos-traffic_fw*7.0,traffic_pos+traffic_fw*7.0)-5.2-1.2)
	check("player avoidance does not push partner through adjacent car (%.3f m)" % closest, closest > 0.0)
	view.free()
	print("PARTNER ADJACENT TRAFFIC %s" % ["PASS" if failures == 0 else "FAIL"])
	quit(int(failures > 0))
