## Real road geometry: the partner stays inboard in either direction and rolls with shade branches.
extends SceneTree
const View := preload("res://view/craft_view.gd")
var failures := 0
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(label: String, ok: bool) -> void:
	checks += 1
	failures += int(not ok)
	print(("PASS " if ok else "FAIL ") + label)

func _run() -> void:
	View.track_override = "network"
	View.job_override = "none"
	var v = View.new()
	root.add_child(v)
	v.set_process(false)
	v.set_partner(true)
	var sim = v.sim
	var road := -1
	for i in sim.roads.size():
		if sim.roads[i].name == "E2":
			road = i
	check("E2 exists", road >= 0)
	if road >= 0:
		var R = sim.roads[road]
		var i: int = R.N / 3
		for direction in [-1, 1]:
			for edge in [-1.0, 1.0]:
				sim.respawn_on(road, i, direction)
				var lateral: float = edge * (R.w[i] / 2.0 - 70.0)
				sim.pod.x = R.px[i] + R.nx[i] * lateral
				sim.pod.y = R.py[i] + R.ny[i] * lateral
				sim.pair_th = atan2(R.ty[i] * direction, R.tx[i] * direction)
				# Start on the wall side; the station must switch to the roomier side.
				v.partner.side = edge * direction
				var station: Vector2 = v.partner._station()
				var station_lat: float = (station.x - R.px[i]) * R.nx[i] + (station.y - R.py[i]) * R.ny[i]
				check("partner chooses inside at edge %s direction %s" % [edge, direction], absf(station_lat) < absf(lateral))
	v.free()
	View.track_override = "eridanus"
	v = View.new()
	root.add_child(v)
	v.set_process(false)
	v.set_partner(true)
	sim = v.sim
	var inverted := -1
	if not sim.branches.is_empty():
		var B = sim.branches[0]
		for i in B.N:
			if cos(sim.roll_at(1, float(i))) < -0.98:
				inverted = i
				break
	check("shade branch has an inverted stretch", inverted >= 0)
	if inverted >= 0:
		v._place_on_branch(inverted)
		v._follow_origin()
		v.partner.placed = false
		v.partner.update(0.0)
		check("partner rolls upside down with the shade branch", v.partner._pod.basis.y.y < -0.9)
		check("shade branch partner remains finite", v.partner._pod.transform.origin.is_finite() and v.partner._pod.transform.basis.is_finite())
	v.free()
	View.track_override = ""
	View.job_override = ""
	print("PARTNER PLACEMENT %s (%d checks, %d failures)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(int(failures > 0))
