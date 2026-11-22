## The pod's nose, open (the tube cage) or closed (skinned over): a spike option on the quick menu
## (Luke: "I'm curious how it would look if we enclosed the front of the pod, now that the vehicle
## tilts and i can see apex lines"). The two hulls, the menu's NOSE line, and that it is remembered.
extends SceneTree

const View := preload("res://view/craft_view.gd")
const Cockpit := preload("res://vr/vr_cockpit.gd")
const CM := preload("res://view/craft_model.gd")
var v
var failures := 0


func _initialize() -> void:
	View.track_override = "network"
	View.job_override = "none"
	View.best_dir = OS.get_user_data_dir().path_join("test_nose_option_")
	Cockpit.camera = "cockpit"
	Cockpit._camera_loaded = true
	Cockpit._nose_loaded = true        # the pilot's saved choice stays out of this
	_run.call_deferred()


func _check(label: String, passed: bool) -> void:
	print(("PASS " if passed else "FAIL ") + label)
	failures += int(not passed)


## How many pods standing under the cockpit wear this hull.
func _wearing(hull: Mesh) -> int:
	var count := 0
	for part: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		count += int(part.mesh == hull)
	return count


func _run() -> void:
	CM.nose_closed = false
	var open: ArrayMesh = CM.pod_hull()
	CM.nose_closed = true
	var closed: ArrayMesh = CM.pod_hull()
	var closed_again: ArrayMesh = CM.pod_hull()
	CM.nose_closed = false
	_check("two hulls, each built once, with the same surfaces (%d)" % open.get_surface_count(),
		open != closed and closed == closed_again and CM.pod_hull() == open and open.get_surface_count() == closed.get_surface_count())
	var skinned := [0, 0]      # triangles of skin, trim and paint along the cage's length: open, closed
	for which in 2:
		var mesh: ArrayMesh = [open, closed][which]
		for surf in [0, 1, 5]:
			var a := mesh.surface_get_arrays(surf)
			var vx: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
			for k in range(0, idx.size(), 3):
				var cz := (vx[idx[k]].z + vx[idx[k + 1]].z + vx[idx[k + 2]].z) / 3.0
				if cz > CM.CAGE_Z1 + 0.06 and cz < CM.CAGE_Z0 - 0.06:
					skinned[which] += 1
	_check("the open nose has no skin along its cage, and the closed one is skinned, trimmed and painted there: %d and %d triangles" % skinned, skinned[0] == 0 and skinned[1] > 4000)
	# the closed nose keeps the cage's bars as frames inside: none of them through the outer skin
	var frames: PackedVector3Array = closed.surface_get_arrays(4)[Mesh.ARRAY_VERTEX]
	var through := 0
	for p in frames:
		var h: Array = CM.hull_section(p.z)
		through += int(pow(absf(p.x) / float(h[0]), CM.HULL_N) + pow(absf(p.y - float(h[1])) / float(h[2]), CM.HULL_N) >= 1.0)
	_check("the closed nose's frames stand inside its skin: %d of %d vertices through it" % [through, frames.size()], through == 0 and frames.size() > 1000)

	v = Cockpit.new()
	root.add_child(v)
	await process_frame
	v.set_process(false)
	var pods := _wearing(open)
	_check("the cockpit stands in the open hull (%d pods wear it)" % pods, pods >= 1 and _wearing(closed) == 0)
	v.menu_open(true)
	for k in v.menu.items.size():      # (the line is on the quick menu's second page, OPTIONS)
		if String(v.menu.items[k].key) == "options":
			v.menu.at = k
	v.menu_choose()
	var keys := []
	for item in v.menu.items:
		keys.append(item.key)
	_check("the quick menu's OPTIONS page has a NOSE line, on OPEN: %s" % [keys], keys.has("nose") and v.menu.items[keys.find("nose")].value == "OPEN")
	v.menu.at = keys.find("nose")
	_check("choosing NOSE keeps the menu open and reads CLOSED", v.menu_choose() and v.menu.open and CM.nose_closed and v.menu.items[v.menu.at].value == "CLOSED")
	_check("every pod took the closed hull (%d)" % _wearing(closed), _wearing(closed) == pods and _wearing(open) == 0)
	_check("the choice is saved", v._load_prefs().get("nose", "") == "closed")
	_check("choosing it again opens the nose", v.menu_choose() and v.menu.open and not CM.nose_closed and v.menu.items[v.menu.at].value == "OPEN")
	_check("every pod is back in the open hull, and that is saved", _wearing(open) == pods and _wearing(closed) == 0 and v._load_prefs().get("nose", "") == "open")
	v.menu_open(false)
	v.queue_free()
	await process_frame
	print("NOSE OPTION %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)
