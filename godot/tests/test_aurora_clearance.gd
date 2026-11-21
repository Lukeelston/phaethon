## No road's support pillar stands inside the Aurora tube's glass (Luke, after the eleventh flight: "the aurora
## tunnel has pillars sticking through it": three of K2's and K3's, whose decks pass over it at 2,500 to 3,100 m).
## Prints AURORA CLEARANCE PASS.
extends SceneTree
const View := preload("res://view/craft_view.gd")
const Sim := preload("res://sim/craft_sim.gd")
const Tube := preload("res://sim/pressure_surface.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	View.track_override = "network"
	View.job_override = "none"
	View.best_dir = OS.get_user_data_dir().path_join("aurora_clearance_")
	var v = View.new()
	root.add_child(v)
	v.set_process(false)
	var sim = v.sim
	var W = v.network_world
	var tube: int = Sim.NET_PRESSURE[0]
	var T = sim.roads[tube]
	var i0: int = Sim.NET_PRESSURE[1]
	var i1: int = Sim.NET_PRESSURE[2]
	var a := Vector2(T.px[i0], T.py[i0])
	var b := Vector2(T.px[i1], T.py[i1])
	var along := (b - a).normalized()
	var across := Vector2(-along.y, along.x)
	var keel: float = sim.net_height(tube, float((i0 + i1) / 2))
	print("PROBE tube: road %d %s, samples %d-%d, %.0f km long, keel %.0f m, radius %.0f m" % [tube, T.name, i0, i1, a.distance_to(b) / 1000.0, keel, Tube.RADIUS])
	var found := {}
	var pillars := 0
	for r in sim.roads.size():
		var R = sim.roads[r]
		for i in range(0, R.N - 1):
			if i % 4 != 0:
				continue
			for p in W.pillar_specs(r, i):
				pillars += 1
				var q := Vector2(p.x, p.y) - a
				var s := q.dot(along)
				if s < -Tube.APRON or s > a.distance_to(b) + Tube.APRON:
					continue
				var d: float = absf(q.dot(across)) - float(p.halfSize)
				if d >= Tube.RADIUS:
					continue
				var bottom: float = keel + Tube.RADIUS - sqrt(Tube.RADIUS * Tube.RADIUS - maxf(d, 0.0) * maxf(d, 0.0))
				if float(p.zMax) > bottom + 1.0:
					var key := String(R.name)
					if not found.has(key):
						found[key] = []
					found[key].append([i, snappedf(s / 1000.0, 0.1), snappedf(q.dot(across), 1.0), snappedf(p.zMax, 1.0), snappedf(bottom, 1.0)])
	print("PROBE %d pillars looked at; roads with pillars inside the glass: %d" % [pillars, found.size()])
	for key in found:
		var list: Array = found[key]
		print("PROBE   %s: %d pillars, e.g. [sample, km along the tube, m across, pillar top, glass bottom there] %s" % [key, list.size(), list.slice(0, 4)])
	print("AURORA CLEARANCE %s (%d pillars inside the glass)" % ["PASS" if found.is_empty() and pillars > 10000 else "FAIL", found.size()])
	v.free()
	quit(0 if found.is_empty() and pillars > 10000 else 1)
