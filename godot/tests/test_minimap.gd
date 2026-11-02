## Minimap gate (view/minimap.gd, vr/minimap_panel.gd, view/minimap_2d.gd; Luke: "a minimap
## overlay of upcoming path"):
##   heading-up   on the start straight the path runs straight up the map; before a left-hander it
##                bends left; a little shows behind the craft
##   zoom         LOOK_S seconds of track ahead: the minimum when slow, ~21 km at 4,000 mph
##   next change  the distance along the track to the next mode change matches a walk of the
##                track, in the right mode; it's marked on the map once it's in range; tracks
##                without modes have none
##   layout       every segment inside the panel's frame; the clip cuts at the edge
##   dawn         on the emergency run the dawn front's line crosses the map (here 2 mi ahead), and
##                the readout counts down to it lighting the job's next stop: DAWN m:ss; no line,
##                no countdown, without a job
##   headset      the panel is built into the cockpit on a course, 1 m from the eye, up and left of
##                the instrument panel and clear of it, facing the eye; it draws the path and the
##                readout; the flat view's map is hidden on the range
## Prints MINIMAP PASS.
## Run: Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_minimap.gd -- --mute
extends SceneTree

const Sim := preload("res://sim/craft_sim.gd")
const MiniMap := preload("res://view/minimap.gd")
const MapPanel := preload("res://vr/minimap_panel.gd")
const ViewScript := preload("res://view/craft_view.gd")
const VRScript := preload("res://vr/vr_cockpit.gd")
const CHECKS := 14
const MI := 1609.344
var fails := 0
var passed := 0
var v
var frames := 0
var stage := 0


func _initialize() -> void:
	_logic()
	ViewScript.track_override = "eridanus"
	v = VRScript.new()
	root.add_child(v)


func _place(sim, i: int, speed: float) -> float:
	sim.pod.hint = i
	sim.pod.x = sim.tpx[i]
	sim.pod.y = sim.tpy[i]
	var th := atan2(sim.tty[i], sim.ttx[i])
	sim.pod.th = th
	sim.pod.vx = cos(th) * speed
	sim.pod.vy = sin(th) * speed
	return th


func _logic() -> void:
	var sim = Sim.new({"track": "eridanus"})
	var mm := MiniMap.new()
	mm.setup(sim)
	# heading-up on the start straight (3.4 km)
	var th := _place(sim, 0, 0.0)
	var f: Dictionary = mm.update(th, 30.0)
	var worst := 0.0
	var behind := 0
	for p in f.pts:
		if p.y > 0.0 and p.y < 1500.0:
			worst = maxf(worst, absf(p.x))
		if p.y < -10.0:
			behind += 1
	_check("heading-up: on the start straight the path runs up the map (off-centre at most %.1f m in 1.5 km), %d points behind the craft" % [worst, behind],
		worst < 15.0 and behind > 0 and f.pts.size() > 60)
	# a left-hander 1 km ahead (the first corner starts at 3.4 km): its far end bends left
	th = _place(sim, 200, 0.0)
	f = mm.update(th, 30.0)
	var top: Vector2 = f.pts[0]
	for p in f.pts:
		if p.y > top.y:
			top = p
	_check("before the first corner (a left) the path bends left: its far end %.0f m left of the nose line" % -top.x, top.x < -200.0)
	# the zoom
	th = _place(sim, 3000, 4000.0 / 2.236936)
	f = mm.update(th, 30.0)
	var fast: float = f.ahead
	th = _place(sim, 3000, 30.0)
	f = mm.update(th, 30.0)
	_check("the zoom: %.1f km ahead at 4,000 mph (wanted %.1f), %.1f km when slow" % [fast / 1000.0, 4000.0 / 2.236936 * MiniMap.LOOK_S / 1000.0, f.ahead / 1000.0],
		absf(fast - 4000.0 / 2.236936 * MiniMap.LOOK_S) < 50.0 and absf(f.ahead - MiniMap.MIN_AHEAD) < 1.0)
	# the next change, against a walk along the track
	var ok := true
	var said := []
	for at in [0, 3000, 6800, 12000]:
		th = _place(sim, at, 0.0)
		f = mm.update(th, 30.0)
		var walk := 0.0
		var k: int = at
		while sim.tmode[(k + 1) % sim.N] == sim.tmode[k % sim.N] or k == at - 1:
			walk += sim.tlen[k % sim.N]
			k += 1
		walk += sim.tlen[k % sim.N]
		var want: int = sim.tmode[(k + 1) % sim.N]
		ok = ok and absf(float(f.next.dist) - walk) < 13.0 and int(f.next.mode) == want
		said.append("%s from %d" % [MiniMap.readout(f), at])
	_check("the next change matches a walk along the track: %s" % ", ".join(said), ok)
	# marked on the map in range, not out of it
	th = _place(sim, 700, 0.0)
	f = mm.update(th, 30.0)
	var near_zone = MiniMap.layout(f, 1.0, 1.0, 0.0, 0.0).zone
	th = _place(sim, 0, 0.0)
	f = mm.update(th, 30.0)
	var far_zone = MiniMap.layout(f, 1.0, 1.0, 0.0, 0.0).zone
	_check("the change is marked once it's on the map (%s at 560 m) and not before (%s at 9 km)" % [near_zone, far_zone],
		near_zone != null and far_zone == null)
	# layout: everything inside the frame, at speed in a sweeper
	th = _place(sim, 9000, 3000.0 / 2.236936)
	f = mm.update(th + 0.3, 30.0)   # turned off the line: the path leaves the map's side
	var l := MiniMap.layout(f, 0.22, 0.22, 0.007, 0.026)
	var inside := true
	for seg in l.segs:
		for p in [seg[0], seg[1]]:
			inside = inside and absf(p.x) <= 0.11 - 0.007 + 1e-6 and p.y >= -0.11 + 0.007 - 1e-6 and p.y <= 0.11 - 0.007 - 0.026 + 1e-6
	_check("layout: %d segments, every one inside the panel's frame; the craft %.0f%% up it" % [l.segs.size(), (l.craft.y + 0.11) / 0.22 * 100.0],
		inside and l.segs.size() > 20 and absf((l.craft.y + 0.11) / 0.22 - MiniMap.CRAFT_Y) < 1e-4)
	var cut := MiniMap.clip(Vector2(0, 0), Vector2(0, 2), 1.0, -1.0, 1.0)
	var miss := MiniMap.clip(Vector2(2, 0), Vector2(3, 1), 1.0, -1.0, 1.0)
	var across := MiniMap.clip(Vector2(-2, 0.5), Vector2(2, 0.5), 1.0, -1.0, 1.0)
	_check("clip: cut at the top edge %s, a miss %s, straight across %s" % [cut, miss, across],
		cut.size() == 2 and cut[1].is_equal_approx(Vector2(0, 1)) and miss.is_empty()
		and across.size() == 2 and across[0].is_equal_approx(Vector2(-1, 0.5)) and across[1].is_equal_approx(Vector2(1, 0.5)))
	# the dawn: a job, the clock running, the front 2 mi ahead of the craft
	var js = Sim.new({"track": "eridanus", "job": "emergency"})
	var mj := MiniMap.new()
	mj.setup(js)
	th = _place(js, 3000, 1000.0 / 2.236936)
	var ax: float = js.pod.x + cos(th) * 2.0 * MI
	var ay: float = js.pod.y + sin(th) * 2.0 * MI
	js.job.t0 = 0.0
	js.time = js.t_lit(ax, ay)   # the front is passing the point 2 mi ahead now
	f = mj.update(th, 30.0)
	var dawn: Dictionary = f.get("dawn", {})
	var lj := MiniMap.layout(f, 0.22, 0.22, 0.007, 0.026)
	var off := INF
	var eta_err := INF
	if not dawn.is_empty():
		var a: Vector2 = dawn.a
		var b: Vector2 = dawn.b
		off = absf((b - a).normalized().cross(Vector2(0.0, 2.0 * MI) - a))   # the point 2 mi up the map, off the chord
		eta_err = absf(float(dawn.eta) - (js.t_lit(js.tpx[js.pad], js.tpy[js.pad]) - (js.time - js.job.t0)))
	var eta: float = dawn.get("eta", 0.0)
	var want_txt := "DAWN %d:%02d" % [int(eta) / 60, int(eta) % 60]
	var fn: Dictionary = mm.update(th, 30.0)
	_check("dawn: the front's chord crosses the map (%s), through the point 2 mi ahead (%.2f m off); %.1f s until it lights the pad (off by %.3f s); readout '%s'; none without a job (%s)" % [
			lj.get("dawn") != null, off, eta, eta_err, MiniMap.readout(f), fn.get("dawn", {}).is_empty()],
		lj.get("dawn") != null and off < 1.0 and eta_err < 0.1 and MiniMap.readout(f).contains(want_txt) and fn.get("dawn", {}).is_empty()
		and not MiniMap.readout(fn).contains("DAWN"))
	# the pad marked on the map on the way out, 3 km ahead
	th = _place(js, posmod(js.pad - 250, js.N), 300.0)
	js.job.stage = "out"
	f = mj.update(th, 30.0)
	var lp := MiniMap.layout(f, 0.22, 0.22, 0.007, 0.026)
	var pd: Vector2 = f.get("pad", Vector2.INF)
	_check("the pad marked on the map on the way out: %s m ahead (about 3 km), on the panel (%s)" % [pd, lp.get("pad") != null],
		f.has("pad") and pd.y > 2500.0 and pd.y < 3200.0 and absf(pd.x) < 400.0 and lp.get("pad") != null)
	# no modes, no readout
	var gp = Sim.new({"track": "gp"})
	var mg := MiniMap.new()
	mg.setup(gp)
	th = _place(gp, 0, 0.0)
	var fg: Dictionary = mg.update(th, 30.0)
	_check("the grand prix has no mode changes: no readout ('%s'), the path all STARFIGHTER" % MiniMap.readout(fg),
		(fg.next as Dictionary).is_empty() and MiniMap.readout(fg) == "" and not (fg.modes as PackedByteArray).has(1))


func _process(_d: float) -> bool:
	frames += 1
	if stage == 0:
		if frames < 4:
			return false
		_headset()
		v.queue_free()
		ViewScript.track_override = "range"
		v = ViewScript.new()
		root.add_child(v)
		stage = 1
		frames = 0
		return false
	if frames < 3:
		return false
	ViewScript.track_override = ""
	_check("the flat view's map is hidden on the range (%s), the headset's is shown on a course" % ("hidden" if not v.minimap_2d.visible else "shown"),
		not v.minimap_2d.visible)
	var good: bool = fails == 0 and passed == CHECKS
	print("MINIMAP ", "PASS" if good else "FAIL (%d failed, %d of %d passed)" % [fails, passed, CHECKS])
	quit(0 if good else 1)
	return true


func _headset() -> void:
	var p: Node3D = v.minimap_panel
	var shell: Node3D = p.get_parent()
	var eye: Vector3 = VRScript.SEAT
	var c: Vector3 = p.position
	var d := c - eye
	var yaw := rad_to_deg(atan2(-d.x, -d.z))
	var pitch := rad_to_deg(atan2(d.y, Vector2(d.x, d.z).length()))
	var facing: float = p.transform.basis.z.normalized().dot(-d.normalized())
	# as seen from the eye: the panel's right edge against the instrument panel's left end
	var dash: Node3D = v.dashboard
	var dash_left := INF
	var dash_top := -INF
	for n in dash.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var box := mi.get_aabb()
		for k in 8:
			var q: Vector3 = shell.global_transform.affine_inverse() * (mi.global_transform * box.get_endpoint(k)) - eye
			dash_left = minf(dash_left, rad_to_deg(atan2(q.x, -q.z)))
			dash_top = maxf(dash_top, rad_to_deg(atan2(q.y, Vector2(q.x, q.z).length())))
	var right := -INF
	var bottom := INF
	for corner in [Vector3(MapPanel.W / 2, MapPanel.H / 2, 0), Vector3(MapPanel.W / 2, -MapPanel.H / 2, 0), Vector3(-MapPanel.W / 2, -MapPanel.H / 2, 0)]:
		var q: Vector3 = p.transform * corner - eye
		right = maxf(right, rad_to_deg(atan2(q.x, -q.z)))
		bottom = minf(bottom, rad_to_deg(atan2(q.y, Vector2(q.x, q.z).length())))
	print("  (panel %.2f m from the eye; the instrument panel's centre %.2f m)" % [d.length(), (shell.global_transform.affine_inverse() * dash.global_position - eye).length()])
	_check("headset: the panel is %.2f m from the eye, %.0f deg left and %.0f deg down, facing it (%.3f)" % [d.length(), yaw, -pitch, facing],
		p.visible and absf(d.length() - MapPanel.DIST) < 0.01 and yaw > 18.0 and yaw < 40.0 and pitch < -3.0 and pitch > -25.0 and facing > 0.999)
	_check("clear of the instrument panel: its right edge at %.1f deg, the instrument panel's left end at %.1f deg (or above its top: %.1f vs %.1f)" % [right, dash_left, bottom, dash_top],
		right < dash_left - 1.0 or bottom > dash_top + 1.0)
	var lines: Mesh = p.lines
	var verts := 0
	for k in lines.get_surface_count():
		verts += (lines.surface_get_arrays(k)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	_check("it draws the path (%d vertices) and the readout ('%s')" % [verts, p.label.text],
		verts > 200 and p.label.text.begins_with("SPEEDCRAFT"))


func _check(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if ok:
		passed += 1
	else:
		fails += 1
