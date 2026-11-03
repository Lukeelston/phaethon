## The Network's parity (track "network", tools/design_network.py): GDScript CraftSim builds the same
## roads as sim-core.js (every 97th sample and both ends of every junction zone within 1e-6 m) and
## replays tools/record_network.js's drive from Eridanus to Glacier (replay/network_*.json: Eridanus'
## bypass, highways, quadrant ramps, Glacier's bypass), which must come out the same: every road
## change on the same frame to the same road and sample, the arrival at Glacier on the same frame
## (its time within 0.01 s), the same wall contacts, the pod within 1 m at the end. And the traffic's
## forcefields: a scripted run past moving obstacles (a glancing catch-up, a head-on smash) gives the
## same bumps and smash on the same steps, closing speeds within 1 mm/s, the pod within 1 m. And phase
## 3: the roads' heights (within 1e-6 m), and scripted runs (a jump caught at 4,000 mph, one missed at
## 2,500, the open ground into an on-ramp): the same airborne / catch / onroad / ground events on the
## same steps, the pod within 1 m at the end, on the same road, off the roads or not the same.
## Prints NETWORK PARITY PASS.
## Run: Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_network_parity.gd
extends SceneTree

const CraftSimScript := preload("res://sim/craft_sim.gd")
const DT := 1.0 / 480.0
const SUB := 8
const ASK := ["", "speed", "starfighter"]


func _initialize() -> void:
	var X: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/replay/network_expected.json"))
	var inputs: Array = JSON.parse_string(FileAccess.get_file_as_string("res://tests/replay/network_inputs.json"))
	var fails := 0
	var sim = CraftSimScript.new({"track": "network", "handling": "speed"})
	var nroads: int = sim.roads.size() if "roads" in sim else 0
	fails += _check("the network: kind %s, %d roads (js %d), %d junctions (js %d), %d cities" % [sim.kind, nroads, X.roads.size(), sim.junctions.size() if "junctions" in sim else 0, X.junctions.size(), sim.cities.size() if "cities" in sim else 0],
		sim.kind == "network" and nroads == X.roads.size() and sim.junctions.size() == X.junctions.size() and sim.cities.size() == X.cities.size())
	if sim.kind != "network":
		print("NETWORK PARITY FAIL (%d)" % fails)
		quit(1)
		return
	var err := 0.0
	var nbad := 0
	for r in nroads:
		var R = sim.roads[r]
		var xr: Dictionary = X.roads[r]
		if R.N != int(xr.N) or R.name != xr.name:
			nbad += 1
			continue
		err = maxf(err, absf(R.length - float(xr.length)) * 1e-3)
		for smp in xr.samples:
			var i := int(smp[0])
			for pair in [[R.px[i], smp[1]], [R.py[i], smp[2]], [R.tx[i], smp[3]], [R.ty[i], smp[4]], [R.len[i], smp[5]], [R.w[i], smp[6]], [sim.net_height(r, float(i)), smp[8]]]:
				err = maxf(err, absf(float(pair[0]) - float(pair[1])))
			if int(R.mode[i]) != int(smp[7]):
				nbad += 1
	var jok := true
	for k in X.junctions.size():
		var a: Array = sim.junctions[k]
		var b: Array = X.junctions[k]
		for q in 7:
			jok = jok and int(a[q]) == int(b[q])
	fails += _check("the same roads: %d mismatched (names, counts, modes), worst difference %.9f m; the same junctions (%s)" % [nbad, err, jok],
		nbad == 0 and err < 1e-6 and jok)

	# the drive
	var st: Array = X.start
	sim.respawn_on(int(st[0]), int(st[1]), int(st[2]))
	var prev := []
	for b in sim.bodies:
		prev.append(b.path)
	var switches := []
	var arrivals := []
	var hits := 0
	var scrapes := 0
	for f in inputs.size():
		var u: Array = inputs[f]
		var inp := {"thrL": float(u[0]), "thrR": float(u[1]), "brkL": float(u[2]), "brkR": float(u[3]), "repair": false, "reignite": true}
		if int(u[4]) > 0:
			inp["handling"] = ASK[int(u[4])]
		for k in SUB:
			sim.step(inp, DT)
			for bi in 3:
				var b = sim.bodies[bi]
				if b.path != prev[bi]:
					switches.append([f, bi, b.path, b.hint])
					prev[bi] = b.path
			for e in sim.events:
				if e.type == "hit":
					hits += 1
				elif e.type == "scrape":
					scrapes += 1
				elif e.type == "arrive":
					arrivals.append([f, e.city, e.from, e.t])
			sim.events.clear()
	var sw_ok: bool = switches.size() == X.switches.size()
	if sw_ok:
		for k in switches.size():
			for q in 4:
				sw_ok = sw_ok and int(switches[k][q]) == int(X.switches[k][q])
	if not sw_ok:
		print("  gd switches %s\n  js switches %s" % [switches, X.switches])
	fails += _check("the drive: %d road changes (js %d), all the same frame, body, road, sample: %s" % [switches.size(), X.switches.size(), sw_ok], sw_ok)
	var a_ok: bool = arrivals.size() == X.arrivals.size() and arrivals.size() == 1
	if a_ok:
		var a: Array = arrivals[0]
		var b: Array = X.arrivals[0]
		a_ok = int(a[0]) == int(b[0]) and int(a[1]) == int(b[1]) and int(a[2]) == int(b[2]) and absf(float(a[3]) - float(b[3])) < 0.01
	fails += _check("the arrival: %s (js %s)" % [arrivals, X.arrivals], a_ok)
	var dp := Vector2(sim.pod.x - float(X.final_pod[0]), sim.pod.y - float(X.final_pod[1])).length()
	fails += _check("the end: %d hits / %d scrapes (js %d / %d), the pod %.4f m from js's, on road %d (js %d)" % [hits, scrapes, int(X.hits), int(X.scrapes), dp, sim.pod.path, int(X.final_path)],
		hits == int(X.hits) and scrapes == int(X.scrapes) and dp < 1.0 and sim.pod.path == int(X.final_path))
	# traffic: moving obstacles
	var TX: Dictionary = X.traffic
	var ts = CraftSimScript.new({"track": "network", "handling": "speed"})
	ts.respawn_on(int(TX.start[0]), int(TX.start[1]), int(TX.start[2]))
	var p0: Dictionary = {"x": ts.roads[int(TX.start[0])].tx[int(TX.start[1])], "y": ts.roads[int(TX.start[0])].ty[int(TX.start[1])]}
	for b in ts.bodies:
		b.vx = float(TX.speed) * p0.x
		b.vy = float(TX.speed) * p0.y
	var tev := []
	for k in 6 * 480:
		for o in TX.obstacles:
			if int(o[0]) == k:
				ts.obstacles.append({"id": int(o[1]), "r": float(o[2]), "x": float(o[3]), "y": float(o[4]), "vx": float(o[5]), "vy": float(o[6])})
		ts.step({"thrL": 0.5, "thrR": 0.5, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": true}, DT)
		for e in ts.events:
			if e.type == "bump" or e.type == "smash":
				tev.append([k, e.type, int(e.id), snappedf(float(e.v), 0.001)])
		ts.events.clear()
	var t_ok: bool = tev.size() == TX.events.size()
	if t_ok:
		for k in tev.size():
			var a: Array = tev[k]
			var b: Array = TX.events[k]
			t_ok = t_ok and int(a[0]) == int(b[0]) and a[1] == b[1] and int(a[2]) == int(b[2]) and absf(float(a[3]) - float(b[3])) < 0.002
	var tdp := Vector2(ts.pod.x - float(TX.final_pod[0]), ts.pod.y - float(TX.final_pod[1])).length()
	fails += _check("traffic: %s (js %s); the pod %.4f m from js's, on road %d (js %d)" % [tev, TX.events, tdp, ts.pod.path, int(TX.final_path)],
		t_ok and tdp < 1.0 and ts.pod.path == int(TX.final_path) and tev.any(func(e): return e[1] == "smash"))
	# phase 3: jumps and the open ground
	for J: Dictionary in X.jumps:
		var js = CraftSimScript.new({"track": "network", "handling": "speed"})
		js.respawn_on(int(J.start[0]), int(J.start[1]), int(J.start[2]))
		if J.has("bodies0"):
			for bi in 3:
				var b = js.bodies[bi]
				var q: Array = J.bodies0[bi]
				b.x = float(q[0])
				b.y = float(q[1])
				b.th = float(q[2])
				b.vx = float(q[3])
				b.vy = float(q[4])
				b.z = float(q[5])
				b.w = 0.0
				b.vz = 0.0
				b.off_road = true
				b.lock = false
		else:
			var R0 = js.roads[int(J.start[0])]
			for b in js.bodies:
				b.vx = float(J.speed) * R0.tx[int(J.start[1])]
				b.vy = float(J.speed) * R0.ty[int(J.start[1])]
		var jev := []
		var lev: float = J.lev
		for k in int(float(J.secs) * 480.0):
			js.step({"thrL": lev, "thrR": lev, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": true}, DT)
			for e in js.events:
				if e.type in ["airborne", "catch", "onroad", "ground"]:
					jev.append([k, e.type, int(e.get("road", -1)), snappedf(float(e.get("v", 0.0)), 0.001)])
			js.events.clear()
		var j_ok: bool = jev.size() == J.events.size()
		if j_ok:
			for k in jev.size():
				var a: Array = jev[k]
				var b: Array = J.events[k]
				j_ok = j_ok and int(a[0]) == int(b[0]) and a[1] == b[1] and int(a[2]) == int(b[2]) and absf(float(a[3]) - float(b[3])) < 0.002
		var jdp := Vector3(js.pod.x - float(J.final_pod[0]), js.pod.y - float(J.final_pod[1]), js.pod.z - float(J.final_pod[2])).length()
		fails += _check("jumps: %s (js %s); the pod %.4f m from js's, on road %d (js %d), off the roads %s (js %s)" % [jev, J.events, jdp, js.pod.path, int(J.final_path), js.pod.off_road, J.off_road],
			j_ok and jdp < 1.0 and js.pod.path == int(J.final_path) and js.pod.off_road == bool(J.off_road))
	# the burner as the headset lights it: inp.burner, the levers under the gate and split
	var B: Dictionary = X.burner
	var bs = CraftSimScript.new({"track": "network", "handling": "speed"})
	bs.respawn_on(int(B.start[0]), int(B.start[1]), int(B.start[2]))
	var RB = bs.roads[int(B.start[0])]
	for b in bs.bodies:
		b.vx = float(B.speed) * RB.tx[int(B.start[1])]
		b.vy = float(B.speed) * RB.ty[int(B.start[1])]
	var bmodes := []
	for k in 5 * 480:
		var on := k < 4 * 480
		var swap := k >= 2 * 480
		bs.step({"thrL": (0.6 if swap else 0.87) if on else 0.87, "thrR": (0.87 if swap else 0.6) if on else 0.87, "brkL": 0.0, "brkR": 0.0,
			"repair": false, "reignite": true, "burner": on}, DT)
		if k % 480 == 479:
			bmodes.append(bs.mode)
	var bdp := Vector2(bs.pod.x - float(B.final_pod[0]), bs.pod.y - float(B.final_pod[1])).length()
	var bdt := absf(bs.pod.th - float(B.final_pod[2]))
	fails += _check("burner: modes by the second %s (js %s): flagged on with the levers under the gate it's lit, off without; the pod %.6f m and %.9f rad from js's, battery %.6f (js %.6f)" % [bmodes, B.modes, bdp, bdt, bs.battery, float(B.battery)],
		bmodes == B.modes and bmodes[0] == "burner" and bmodes[4] == "normal" and bdp < 0.001 and bdt < 1e-6 and absf(bs.battery - float(B.battery)) < 1e-9)
	# a highway's dead end: braking into N1's far end (a wall across the road), the binder holds
	var D: Dictionary = X.dead_end
	var ds = CraftSimScript.new({"track": "network", "handling": "starfighter"})
	ds.respawn_on(int(D.start[0]), int(D.start[1]), int(D.start[2]))
	var RD = ds.roads[int(D.start[0])]
	for b in ds.bodies:
		b.vx = float(D.speed) * RD.tx[int(D.start[1])]
		b.vy = float(D.speed) * RD.ty[int(D.start[1])]
	var devents := []
	for k in 5 * 480:
		ds.step({"thrL": 0.0, "thrR": 0.0, "brkL": 1.0, "brkR": 1.0, "repair": false, "reignite": true, "handling": "starfighter"}, DT)
		for e in ds.events:
			if e.type == "binder" or e.type == "hit":
				devents.append([k, e.type, e.get("who", "")])
		ds.events.clear()
	devents = devents.slice(0, 12)
	var d_ok: bool = devents.size() == D.events.size()
	for k in mini(devents.size(), D.events.size()):
		d_ok = d_ok and int(devents[k][0]) == int(D.events[k][0]) and devents[k][1] == D.events[k][1] and devents[k][2] == D.events[k][2]
	var ddp := 0.0
	var dbodies := [ds.eL, ds.eR, ds.pod]
	for k in 3:
		var jb: Array = D.bodies[k]
		ddp = maxf(ddp, Vector2(dbodies[k].x - float(jb[0]), dbodies[k].y - float(jb[1])).length())
	fails += _check("dead end: braking into N1's end, the binder %s (js %s); hits %s (js %s); the bodies within %.6f m of js's" % [
		"torn" if ds.binder_broken else "holds", "torn" if bool(D.binder) else "holds", devents, D.events, ddp],
		d_ok and not ds.binder_broken and not bool(D.binder) and ddp < 0.001)
	print("NETWORK PARITY ", "PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(1 if fails > 0 else 0)


func _check(label: String, ok: bool) -> int:
	print(("  ok   " if ok else "  FAIL ") + label)
	return 0 if ok else 1
