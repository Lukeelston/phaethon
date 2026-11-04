## User's recorded 0.2.2 run, replayed through actual partner updates at 60 Hz.
extends "res://tests/test_partner_maneuvers.gd"

func _run() -> void:
	View.track_override = "network"
	View.job_override = "none"
	view = View.new()
	root.add_child(view)
	view.set_process(false)
	view.traffic_net.cars.clear()
	var s = view.sim
	var roads := {}
	for i in s.roads.size():
		roads[s.roads[i].name] = i
	var rows: Array = JSON.parse_string(FileAccess.get_file_as_string("res://tests/replay/partner_player_run.json"))
	view.set_partner(false)
	var p
	var worst := INF
	var hits := 0
	var frames := 0
	var examples := []
	var max_step := 0.0
	var step_at := 0.0
	var previous := Vector2.ZERO
	var previous_pod := Vector2.ZERO
	for i in range(1, rows.size()):
		var a: Dictionary = rows[i-1]
		var b: Dictionary = rows[i]
		var span: float = b.t - a.t
		var steps := maxi(1, ceili(span * 60.0))
		var warped := Vector3(a.b[2].p[0], a.b[2].p[1], a.b[2].p[2]).distance_to(Vector3(b.b[2].p[0], b.b[2].p[1], b.b[2].p[2])) > 3000.0
		for frame in steps:
			var u := float(frame + 1) / steps
			for k in 3:
				var body = s.bodies[k]
				var old: Dictionary = a.b[k]
				var now: Dictionary = b.b[k]
				body.x = lerpf(old.p[0], now.p[0], u)
				body.y = lerpf(old.p[1], now.p[1], u)
				body.z = lerpf(old.p[2], now.p[2], u)
				body.vx = lerpf(old.v[0], now.v[0], u)
				body.vy = lerpf(old.v[1], now.v[1], u)
				body.vz = lerpf(old.v[2], now.v[2], u)
				body.th = lerp_angle(old.th, now.th, u)
				body.path = roads[now.road if u > 0.5 else old.road]
				body.hint = now.hint if u > 0.5 else old.hint
				body.off_road = now.off
			s.pair_th = lerp_angle(a.th, b.th, u)
			if p == null:
				view.set_partner(true)
				p = view.partner
			if warped:
				p.placed = false
			p.update(span / steps)
			var clearance := whole_clearance(p)
			var pos := Vector2(p.x, p.y)
			var pod := Vector2(s.pod.x, s.pod.y)
			if frames > 0 and not warped:
				var relative_step := (pos - previous - pod + previous_pod).length()
				if relative_step > max_step:
					max_step = relative_step
					step_at = lerpf(a.t, b.t, u)
			previous = pos
			previous_pod = pod
			worst = minf(worst, clearance)
			frames += 1
			if clearance < 0.0:
				hits += 1
				if examples.size() < 8:
					examples.append({"t":lerpf(a.t,b.t,u),"road":s.roads[s.pod.path].name,"gap":clearance,"ahead":p._ahead,"offset":p._offset,"phase":p.maneuver})
	print(JSON.stringify({"frames":frames,"overlaps":hits,"worst":worst,"examples":examples,"max_relative_step":max_step,"step_at":step_at}))
	check("recorded steering and road transitions keep complete partner clear", hits == 0 and worst > 5.0)
	check("recorded maneuvers stay continuous relative to player", max_step < 3.0)
	view.free()
	print("PARTNER PLAYER REPLAY %s" % ["PASS" if failures == 0 else "FAIL"])
	quit(int(failures > 0))
