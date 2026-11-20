## The windscreen's reflection of the cockpit (view/screen_reflection.gd; Luke: "add some kind of
## reflection to the windscreen, without making it white out"):
##   fitted    with the roof, in the VR cockpit, on the canopy; not without the roof
##   the sheet lies in the roof's own screen (against the roof's glass band where the two overlap),
##             faces in, and covers only the part of the pane that shows the coaming, the
##             instruments or the map to a head near the seat (a sheet over the whole pane cost a
##             headset-sized frame 5 % of its GPU time)
##   the mirror a sight line from the seat to the screen turns down into the cabin; the picture is
##             taken from outside the glass, of the cockpit's own parts and nothing else, and again
##             every few seconds
##   the view  (run windowed) the reflection is there, and it does not white the view out: it
##             changes a small share of the view, by little, and nowhere by much
## Prints SCREEN REFLECTION PASS.
## Run windowed: --xr-mode off --resolution 1280x720 -s res://tests/test_screen_reflection.gd -- --mute
extends SceneTree

const View := preload("res://view/craft_view.gd")
const Cockpit := preload("res://vr/vr_cockpit.gd")
const Mirror := preload("res://view/screen_reflection.gd")
const CanopyScript := preload("res://view/canopy.gd")
const CM := preload("res://view/craft_model.gd")
var v
var failures := 0


func _initialize() -> void:
	View.track_override = "network"
	View.job_override = "none"
	View.best_dir = OS.get_user_data_dir().path_join("test_screen_reflection_")
	Cockpit.camera = "cockpit"
	Cockpit._camera_loaded = true
	_run.call_deferred()


func _check(label: String, passed: bool) -> void:
	print(("PASS " if passed else "FAIL ") + label)
	failures += int(not passed)


func _run() -> void:
	CanopyScript.roofed = false
	_check("no roof, no reflection", not Mirror.available())
	CanopyScript.roofed = true
	v = Cockpit.new()
	root.add_child(v)
	await process_frame
	v.set_process(false)
	var sim = v.sim
	sim.respawn_on(2, 9000, 1)
	await _settle()
	var mirror = v.screen_reflection
	_check("fitted on the canopy with the roof", mirror != null and mirror.get_parent() == v.canopy and mirror.is_in_group("exterior"))
	if mirror == null:
		quit(1)
		return
	# the sheet against the roof's own glass
	var sheet: MeshInstance3D = mirror.sheet
	var points: PackedVector3Array = sheet.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = sheet.mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
	var band := v.canopy.get_node("roof_glass") as MeshInstance3D
	var glass: PackedVector3Array = band.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	# (the sheet is cut to what it shows, so the roof's glass is measured against the screen's own surface, the one the sheet is cut from)
	var surface := PackedVector3Array()
	for j in 61:
		for i in 121:
			surface.append(Mirror.screen(i / 120.0, lerpf(0.7, 1.0, j / 60.0)))
	var worst := 0.0
	var near := 0
	for g in glass:
		var at: Vector3 = band.position + g        # the roof is drawn in the rig's frame, POD_FRAME_UP under the canopy's
		if absf(at.x) > 0.36 or at.z > 0.3:         # the windscreen's band, clear of the corners and the side windows
			continue
		var best := INF
		for p in surface:
			best = minf(best, at.distance_to(p))
		worst = maxf(worst, best)
		near += 1
	_check("the mirror's screen is the roof's: %d points of the roof's glass band, the furthest %.3f m off it" % [near, worst], near > 20 and worst < 0.02)
	var whole := PackedVector3Array()       # the whole screen, a point every centimetre or two
	for j in 81:
		for i in 101:
			whole.append(Mirror.screen(i / 100.0, lerpf(0.05, 1.0, j / 80.0)))
	var on_it := true
	for k in range(0, points.size(), 11):
		var best := INF
		for q in whole:
			best = minf(best, points[k].distance_squared_to(q))
		on_it = on_it and best < 0.0004
	_check("the sheet lies in that screen and covers %.0f %% of it: the coaming's, the instruments' and the map's share" % (mirror.share * 100.0),
		on_it and mirror.share > 0.25 and mirror.share < 0.7 and mirror.sights.size() == 2)
	var facing := true
	for i in points.size():
		facing = facing and normals[i].dot(Mirror.EYE - points[i]) > 0.0
	_check("the sheet faces in, toward the seat", facing)
	# the mirror's geometry, from the seated eye through the screen's middle
	var middle: Vector3 = Mirror.screen(0.5, 0.55)
	var n := (Mirror.screen(0.51, 0.55) - Mirror.screen(0.49, 0.55)).cross(Mirror.screen(0.5, 0.56) - Mirror.screen(0.5, 0.54)).normalized()
	if n.dot(Mirror.EYE - middle) < 0.0:
		n = -n
	var off := (middle - Mirror.EYE).normalized().bounce(n)
	var lands: Vector3 = middle + off * ((Mirror.LIES_AT - middle.y) / off.y)
	var inside := pow(lands.x / CM.OPEN_AX, 2.0) + pow((lands.z - CM.OPEN_ZC) / CM.OPEN_AZ, 2.0)
	_check("a sight line to the screen turns down into the cabin: lands %.2f m ahead of the seat, inside the opening (%.2f)" % [Mirror.EYE.z - lands.z, inside],
		off.y < -0.3 and inside < 1.0 and lands.z < Mirror.EYE.z)
	var lens: Transform3D = mirror.looks_from
	_check("the picture is taken from outside the glass, looking down in: %.2f m over the eye, %.0f deg down" % [lens.origin.y - Mirror.EYE.y, rad_to_deg(asin(lens.basis.z.y))],
		lens.origin.y > middle.y + 0.2 and lens.basis.z.y > 0.5)
	# what the picture is of
	var layered := 0
	var total := 0
	var missed := []
	for part: VisualInstance3D in v.shell.find_children("*", "VisualInstance3D", true, false):
		if v.canopy.is_ancestor_of(part):
			continue
		total += 1
		layered += int((part.layers & Mirror.LAYER) != 0)
		if (part.layers & Mirror.LAYER) == 0:
			missed.append(str(v.shell.get_path_to(part)))
	var roof := v.canopy.get_node("roof") as MeshInstance3D
	_check("the picture is of the cockpit's own parts (%d of %d; missed %s) and not the canopy over them" % [layered, total, missed],
		total > 20 and layered == total and (roof.layers & Mirror.LAYER) == 0 and mirror.lens.cull_mask == Mirror.LAYER and (sheet.layers & Mirror.LAYER) == 0)
	var before: int = mirror.pictures
	mirror._process(Mirror.EVERY + 0.1)
	_check("pictures: %d by now, and another after %.0f s" % [before, Mirror.EVERY], before >= 1 and mirror.pictures == before + 1)
	# the view with and without it
	if DisplayServer.get_name() != "headless":
		v.cam.rotation_degrees = Vector3(14.0, 0.0, 0.0)
		for i in 4:
			await process_frame
		await RenderingServer.frame_post_draw
		var with_it := root.get_texture().get_image()
		sheet.visible = false
		for i in 2:
			await process_frame
		await RenderingServer.frame_post_draw
		var without := root.get_texture().get_image()
		sheet.visible = true
		var changed := 0
		var most := 0.0
		var sum := 0.0
		var count := 0
		for y in range(0, with_it.get_height(), 2):
			for x in range(0, with_it.get_width(), 2):
				var a := with_it.get_pixel(x, y)
				var b := without.get_pixel(x, y)
				var d := maxf(a.r - b.r, maxf(a.g - b.g, a.b - b.b))
				count += 1
				sum += maxf(d, 0.0)
				most = maxf(most, d)
				changed += int(d > 0.012)
		var share := float(changed) / count
		_check("the reflection is in the view: %.1f %% of it changed" % (share * 100.0), share > 0.004)
		_check("and does not white it out: under a fifth of the view touched, %.3f brighter on average, %.2f at the most" % [sum / count, most],
			share < 0.2 and sum / count < 0.012 and most < 0.4)
	else:
		print("SKIP the rendered checks (headless)")
	v.queue_free()
	await process_frame
	print("SCREEN REFLECTION %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)


func _settle() -> void:
	v._ride.clear()
	for i in 40:
		v._follow_origin()
		v._sync_craft(1.0 / 60.0)
		v._place_camera(1.0)
		v._sync_world()
		v._update_hud()
		for hand in v.hands.values():
			hand.get_child(0).visible = false
		await process_frame
