## Which of the cockpit's meshes pass through each other (Luke, after the flight of 22 November: "The map
## is good but is sticking through the drift switch mesh", "the mach gauge mesh collides with those on the
## sides of it"). Builds the production cockpit and casts every triangle's edges at every other mesh
## (tests/clash_kit.gd): an edge that crosses another mesh's surface is a place where the two pass through
## each other. Prints each pair with how many edges cross and the box those crossings fill (the cabin's
## frame: floor origin, forward -Z, metres), largest first.
##   --headless --xr-mode off --audio-driver Dummy -s res://tests/probe_cockpit_clash.gd -- --mute
##       [--self] [--min=0.004] [--only=name] [--gap=name,name] [--move=Node:x,y,z] [--vehicle=shrike] [--out=FILE]
## --self also lists a mesh crossing itself (a compound's parts are often sunk into each other on
## purpose: the list is long); --min is the smallest box worth a line (m); --only keeps the pairs with a
## name containing it; --gap prints the least distance between two groups of parts (it may be given
## more than once); --move tries a named fitting at another place in the cabin before looking;
## --vehicle builds another craft's cockpit (the Shrike RS has a seat, levers and coaming of its own);
## --out writes the list as JSON.
## A pair listed here is not always a defect (a flange sunk into its console is meant): look at it.
extends SceneTree

const VR := preload("res://vr/vr_cockpit.gd")
const Sim := preload("res://sim/craft_sim.gd")
const View := preload("res://view/craft_view.gd")
const ClashKit := preload("res://tests/clash_kit.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var with_self := "--self" in args
	var smallest := 0.004
	var only := ""
	var out := ""
	var gaps := []
	var vehicle := ""
	for arg in args:
		if arg.begins_with("--vehicle="):
			vehicle = arg.trim_prefix("--vehicle=")
		if arg.begins_with("--min="):
			smallest = float(arg.trim_prefix("--min="))
		if arg.begins_with("--only="):
			only = arg.trim_prefix("--only=")
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
		if arg.begins_with("--gap="):
			gaps.append(arg.trim_prefix("--gap=").split(","))
	VR._nose_loaded = true
	var cockpit = VR.new()
	cockpit.sim = Sim.new({"track": "range"} if vehicle == "" else {"track": "range", "vehicle": vehicle})
	cockpit.rig = Node3D.new()
	root.add_child(cockpit.rig)
	cockpit._build_cockpit()
	for arg in args:
		if arg.begins_with("--move="):      # what if: a fitting somewhere else (its name, then where in the cabin)
			var what := arg.trim_prefix("--move=").split(":")
			var to := what[1].split_floats(",")
			for node in cockpit.rig.find_children(what[0], "Node3D", true, false):
				(node as Node3D).position = Vector3(to[0], to[1], to[2])
				print("CLASH: %s moved to %s" % [node.name, (node as Node3D).position])
	await process_frame
	var kit := ClashKit.new()
	kit.gather(cockpit.rig)
	kit.arm(root)
	print("CLASH: %d meshes, %d triangles" % [kit.soups.size(), kit.triangles()])
	await physics_frame
	await physics_frame
	var space := root.world_3d.direct_space_state
	for pair in gaps:
		var found: Array = kit.gap(space, pair[0], pair[1])
		var at: Vector3 = found[1]
		print("CLASH GAP %s (%d parts) to %s (%d parts): %s" % [pair[0], kit.group(pair[0]).size(), pair[1], kit.group(pair[1]).size(),
			("over %.0f mm" % (ClashKit.REACH * 1000.0)) if float(found[0]) >= ClashKit.REACH else ("%.1f mm at (%.3f, %.3f, %.3f)" % [float(found[0]) * 1000.0, at.x, at.y, at.z])])
	var list := kit.crossings(space, with_self).values()
	list.sort_custom(func(x, y): return ((x.hi as Vector3) - (x.lo as Vector3)).length() > ((y.hi as Vector3) - (y.lo as Vector3)).length())
	print("CLASH: %d pairs cross" % list.size())
	var shown := 0
	var dump := []
	for rec in list:
		var size: Vector3 = (rec.hi as Vector3) - (rec.lo as Vector3)
		if size.length() < smallest:
			continue
		if only != "" and not (String(rec.a).contains(only) or String(rec.b).contains(only)):
			continue
		shown += 1
		var mid: Vector3 = ((rec.hi as Vector3) + (rec.lo as Vector3)) * 0.5
		print("CLASH %5d edges  box %4.0f x %4.0f x %4.0f mm  at (%.3f, %.3f, %.3f)  %s  ><  %s" % [rec.n, size.x * 1000.0, size.y * 1000.0, size.z * 1000.0,
			mid.x, mid.y, mid.z, rec.a, rec.b])
		dump.append({"a": rec.a, "b": rec.b, "edges": rec.n, "lo": [rec.lo.x, rec.lo.y, rec.lo.z], "hi": [rec.hi.x, rec.hi.y, rec.hi.z]})
	print("CLASH: %d pairs listed (boxes of %.0f mm and over)" % [shown, smallest * 1000.0])
	if out != "":
		var f := FileAccess.open(out, FileAccess.WRITE)
		if f:
			f.store_string(JSON.stringify(dump, "\t"))
	kit.free_bodies()
	cockpit.rig.free()
	cockpit.free()
	quit()
