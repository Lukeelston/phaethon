## What the seated eye sees ahead and to the left through the roof's screen, a degree at a time, and
## where the map lies in it when the HUD switch is up (view/minimap_glass.gd). Builds the production
## cockpit and casts the eye's lines at its fittings (tests/clash_kit.gd).
##   --headless --xr-mode off --audio-driver Dummy -s res://tests/probe_map_glass.gd -- --mute
## The chart: across, degrees left of dead ahead (the left column is 46 left); down, degrees from eye
## level (the top row is 18 up).
##   .  clear glass          P  the approach readout's page       M  the map (# its corners)
##   r  the roof's frame     h  the pod's hull (the nose)         c  the coaming and the cabin's trim
##   m  the map's pod        g  the instruments                   o  another fitting
##   (blank: the line leaves through no glass)
## Then the map's own numbers: its box at the eye, how far off it lies, how far it is from the page, how
## much of it has the pod's nose beyond the glass (it is drawn over that) or a fitting in front (hidden).
extends SceneTree

const VR := preload("res://vr/vr_cockpit.gd")
const Sim := preload("res://sim/craft_sim.gd")
const ClashKit := preload("res://tests/clash_kit.gd")
const MapGlass := preload("res://view/minimap_glass.gd")
const CM := preload("res://view/craft_model.gd")
const Projector := preload("res://view/approach_projector.gd")


func _initialize() -> void:
	_run.call_deferred()


func _angles(dir: Vector3) -> Vector2:
	return Vector2(rad_to_deg(atan2(dir.x, -dir.z)), rad_to_deg(asin(dir.normalized().y)))


func _run() -> void:
	VR._nose_loaded = true
	var cockpit = VR.new()
	cockpit.sim = Sim.new({"track": "range"})
	cockpit.rig = Node3D.new()
	root.add_child(cockpit.rig)
	cockpit._build_cockpit()
	await process_frame
	var kit := ClashKit.new()
	kit.gather(cockpit.rig)
	kit.arm(root)
	await physics_frame
	await physics_frame
	var space := root.world_3d.direct_space_state
	var up := Vector3(0.0, CM.POD_FRAME_UP, 0.0)      # the canopy's space in the rig's
	var eye: Vector3 = MapGlass.EYE
	# the approach readout's page, as the eye has it
	var page := {}
	var page_box := [INF, -INF, INF, -INF]
	if cockpit.approach_display != null and cockpit.approach_display.image != null:
		for i in 121:
			for j in 41:
				var a := _angles(Projector.image_point(i / 120.0, j / 40.0) - eye)
				page[Vector2i(roundi(a.x), roundi(a.y))] = true
				page_box = [minf(page_box[0], a.x), maxf(page_box[1], a.x), minf(page_box[2], a.y), maxf(page_box[3], a.y)]
	# the map
	var map := {}
	var map_box := [INF, -INF, INF, -INF]
	var off := [INF, -INF]
	var half: Vector2 = MapGlass.PANEL * 0.5
	for i in 81:
		for j in 81:
			var at: Vector3 = MapGlass.lies_at(lerpf(-half.x, half.x, i / 80.0), lerpf(-half.y, half.y, j / 80.0))
			var a := _angles(at - eye)
			var edge := (i == 0 or i == 80) and (j == 0 or j == 80)
			var cell := Vector2i(roundi(a.x), roundi(a.y))
			map[cell] = "#" if edge or map.get(cell, "") == "#" else "M"
			map_box = [minf(map_box[0], a.x), maxf(map_box[1], a.x), minf(map_box[2], a.y), maxf(map_box[3], a.y)]
			off = [minf(off[0], at.distance_to(eye)), maxf(off[1], at.distance_to(eye))]
	var last := Vector2(0.3, 0.3)
	print("        " + "".join(range(-46, 7).map(func(a): return str(absi(a) / 10) if a % 10 == 0 else " ")))
	print("        " + "".join(range(-46, 7).map(func(a): return str(absi(a) % 10) if a % 5 == 0 else " ")))
	var hidden_map := {}
	for el in range(18, -15, -1):
		var row := ""
		for az in range(-46, 7):
			var dir := Vector3(sin(deg_to_rad(az)) * cos(deg_to_rad(el)), sin(deg_to_rad(el)), -cos(deg_to_rad(az)) * cos(deg_to_rad(el)))
			var hit: Vector3 = MapGlass.meet(dir, last)
			var mark := " "
			if hit.z > 0.5:
				last = Vector2(hit.x, hit.y)
				mark = "."
			var seen := kit.sight(space, eye + up, eye + up + dir * 6.0)
			for part in seen:
				if part.contains("roof_glass") or part.contains("field") or part.contains("screen_reflection") or part.contains("windscreen") or part.contains("MapGlass"):
					continue
				mark = "r" if part.contains("canopy/roof") else "h" if part.contains("PodHull") else "m" if part.contains("minimap_panel") else "g" if part.contains("gauge") \
					else "c" if part.contains("cockpit_interior") else "o"
				break
			var cell := Vector2i(az, el)
			if mark == ".":
				mark = map.get(cell, "P" if page.has(cell) else ".")
			elif map.has(cell):
				hidden_map[mark] = int(hidden_map.get(mark, 0)) + 1
			row += mark
		print("  %+3d   %s" % [el, row])
	print("MAP GLASS: the map from %.1f to %.1f degrees left of ahead, %.1f to %.1f from eye level; it lies %.2f to %.2f m from the eye; all of it on the glass: %s" % [
		-map_box[1], -map_box[0], map_box[2], map_box[3], off[0], off[1], MapGlass.on_glass()])
	print("MAP GLASS: the approach page from %.1f left to %.1f right, %.1f to %.1f up; clear glass between the map's top and the page's foot: %.1f degrees" % [
		-page_box[0], page_box[1], page_box[2], page_box[3], page_box[2] - map_box[3]])
	var over_nose := int(hidden_map.get("h", 0))      # (the hull's nose is beyond the glass: the map is drawn over it)
	hidden_map.erase("h")
	print("MAP GLASS: square degrees of the map with the pod's nose beyond them: %d; with a fitting in front of them, which hides them (which, how many): %s" % [over_nose, hidden_map])
	kit.free_bodies()
	cockpit.rig.free()
	cockpit.free()
	quit(0)
