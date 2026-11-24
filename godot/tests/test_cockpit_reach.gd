## The left hand's reach and the left lever's room, in every pilot craft's cockpit (Luke, flight 34: "I think they
## should go somewhere more reachable up front. Pressing it beside the leg is awkward - also been meaning to tell you
## the left lever collides with the map at 90-100% throttle"). For the Phaethon, the Talon, and the fleet's Shrike,
## Orrery, Kiln, Vesper and Basilisk, each in its production cockpit:
##   the sweep    both levers, idle to full in 5% steps (grip, shaft and the fleet's boot): nothing of them through
##                the map's pod, its arm or its controls, nor through the POWER switch or its button, and never nearer
##                the map than MAP_GAP or the power's controls than POWER_GAP
##   in place     the POWER switch and its button cross nothing in the cabin but the port console they are let into,
##                and the map's pod nothing at all (the fleet's own cabins included)
##   the reach    the button's cap and the switch's bat are nearer the left grip at half and at full throttle than they
##                were beside the thigh, and within reach of the left shoulder (the eye + (-0.18, -0.2, 0.05), as
##                tests/probe_pod_pitch.gd)
##   in sight     from the seat, with the levers at idle and at full, nothing stands before the button's cap, its ring,
##                the switch's ARM lamp or the map's screen, nor before its SAFE lamp at idle. (At full throttle the
##                left lever's shaft crosses the switch's lower half: it leans along the line from the eye to there,
##                and wherever the shaft would not hide it, the shaft passes too near the switch's bat.)
##   the GUN switch   in every cockpit whose craft has a weapon (sim/pilot_craft.gd armed; Raids, 2026-11-24) and in no
##                other: the Phaethon's and the Talon's on the starboard console's inboard face up front, outboard of the
##                right lever (vr_cockpit.gd gun_switch_mount); the Basilisk's on its starboard sill, where it has stood
##                since 2026-11-23. The same checks as the power's controls: the levers' sweep passes through nothing of
##                it and keeps POWER_GAP clear (and the lever on its side, again, with its bat thrown up, straight out as
##                in mid-throw, and thrown down); in place it crosses nothing but the starboard console it is let into
##                (the Basilisk's, unmoved, nothing but BASILISK_GUN_KNOWN, told); the lever on its side keeps GUN_GAP
##                off it; its bat is within GUN_REACH of the grip on its side at half and at full throttle and of that
##                shoulder (the Basilisk's, unmoved, within
##                BASILISK_GUN_REACH); and from the seat nothing hides its GUN lamp at idle or at full, nor its SAFE lamp
##                at idle
## --headless --xr-mode off --audio-driver Dummy -s res://tests/test_cockpit_reach.gd -- --mute
## Prints COCKPIT REACH PASS. tests/probe_power_reach.gd measures the same things with what-ifs.
extends SceneTree

const View := preload("res://view/craft_view.gd")
const Cockpit := preload("res://vr/vr_cockpit.gd")
const Craft := preload("res://sim/pilot_craft.gd")
const ClashKit := preload("res://tests/clash_kit.gd")
const MapPanel := preload("res://vr/minimap_panel.gd")
const Switch := preload("res://vr/mode_switch.gd")
const MAP_GAP := 0.005           # m: the levers keep at least this clear of the map's pod, arm and controls ...
const POWER_GAP := 0.012         # ... and this of the POWER switch and its button (the grips' figure in test_cockpit_clash)
# The reach (m), at most: from the left grip at half and at full throttle, and from the left shoulder. As they were
# (2026-11-24, beside the seat's bolster): the button 0.261 / 0.403 / 0.504, the switch 0.304 / 0.460 / 0.442; as
# they are (up front beside the lever, the button over the switch): 0.182 / 0.127 / 0.688 and 0.266 / 0.187 / 0.732.
# Nearer the hands on the levers, further from the shoulder (the SLIDE switch, thrown often in flight: 0.126 / 0.245
# / 0.577; the map's controls on its pod, about 0.74 from the shoulder).
const BUTTON_REACH := Vector3(0.20, 0.15, 0.71)
const SWITCH_REACH := Vector3(0.28, 0.20, 0.75)
# The GUN switch's bat (m, at most): from the grip on its side at half and at full throttle, and from that shoulder.
# The Phaethon's and the Talon's are held to the POWER switch's: the other guarded throw switch a hand reaches down to
# from its lever (0.266 / 0.187 / 0.732 above), as ruled after the review of 2026-11-24 (the POWER button's tighter
# bars left room under the MODE switch only for a half-size switch, its box 4 mm from MODE's). The Basilisk's stands
# where it has since 2026-11-23, by the right elbow on the sill (0.452 / 0.561 / 0.662): held to tests/test_turret.gd's
# 0.6 m from the right grip, and to the button's bar from the shoulder.
const GUN_REACH := Vector3(0.27, 0.19, 0.73)
const GUN_GAP := 0.014           # m: the lever on its side keeps at least this off the GUN switch, its bat up, out or down
const BASILISK_GUN_REACH := Vector3(0.60, 0.60, 0.71)
# What the Basilisk's GUN switch crosses where it has stood since 2026-11-23 (its place is not this stage's to move):
# the hull's sill it stands on, and the cabin roof's glass, through its panel's top (5 edges). Told, not failed.
const BASILISK_GUN_KNOWN := ["PodHull", "canopy/roof_glass"]
var failures := 0
var checks := 0


func _initialize() -> void:
	View.track_override = "range"
	View.job_override = "none"
	View.best_dir = OS.get_user_data_dir().path_join("test_cockpit_reach_")
	Cockpit.camera = "cockpit"
	Cockpit._camera_loaded = true
	Cockpit._nose_loaded = true
	Cockpit._slide_loaded = true
	Cockpit._rush_loaded = true
	Cockpit._startup_loaded = true
	Cockpit._map_loaded = true
	Cockpit._school_loaded = true
	Cockpit._options_loaded = true
	Cockpit._power_loaded = true
	Cockpit.power_armed = true
	Cockpit.cold_start = false
	Cockpit.school = false
	_run.call_deferred()


func _check(label: String, passed: bool) -> void:
	checks += 1
	print(("PASS " if passed else "FAIL ") + label)
	failures += int(not passed)


func _mm(m: float) -> String:
	return ("over %.0f" % (ClashKit.REACH * 1000.0)) if m >= ClashKit.REACH else ("%.1f" % (m * 1000.0))


## Stand lever k at a throttle (the live cockpit's swing: vr_cockpit.gd _place_camera), its boot's neck with it.
func _lever(v, k: int, thr: float) -> void:
	var pivot: Node3D = v.lever_pivots[k]
	pivot.rotation.x = deg_to_rad(lerpf(30.0, -30.0, thr))
	if not v.throttle_gaiters.is_empty():
		(v.throttle_gaiters[k] as Skeleton3D).set_bone_pose_rotation(1, pivot.quaternion)


## A lever's parts for the kit: the pivot (shaft, grip) and, in a fleet cockpit, its boot (a skinned mesh's triangles
## are its rest pose: the boot's neck, 12 cm over the gate at most, is not bent with the lever here; the shaft is).
func _gather_lever(kit, rig: Node3D, v, k: int) -> void:
	kit.gather_part(rig, v.lever_pivots[k])
	if not v.throttle_gaiters.is_empty():
		kit.gather_part(rig, v.throttle_gaiters[k])


func _run() -> void:
	var only := ""
	for arg in OS.get_cmdline_user_args():      # (--vehicle=<id>: that craft's cockpit alone)
		if arg.begins_with("--vehicle="):
			only = arg.trim_prefix("--vehicle=")
	for id: String in Craft.ORDER:
		if only != "" and id != only:
			continue
		View.vehicle_override = id
		var v = Cockpit.new()
		root.add_child(v)
		await process_frame
		v.set_process(false)
		var rig: Node3D = v.rig
		var to_rig: Transform3D = rig.global_transform.affine_inverse()
		for k in 2:
			v.lever_pivots[k].name = "LeverL" if k == 0 else "LeverR"
		var map: Node3D = v.minimap_panel
		map.name = "MapPod"
		var gun: Node3D = v.gun_switch
		_check("%s: a GUN switch in its cockpit (%s) if and only if it carries a weapon (\"%s\")" % [id, gun != null, Craft.weapon_of(id)],
			(gun != null) == Craft.armed(id) and Craft.armed(id) == (Craft.weapon_of(id) != ""))

		# ---- the sweep: both levers, idle to full, against the map and the power's controls
		var least := {"MapPod": ClashKit.REACH, "PowerSwitch": ClashKit.REACH, "PowerButton": ClashKit.REACH}
		if gun:
			least["GunSwitch"] = ClashKit.REACH
		var where := {}
		var through := {}
		for k in 2:
			var lever := "LeverL" if k == 0 else "LeverR"
			var boot := "ThrottleBootL" if k == 0 else "ThrottleBootR"
			for step in 21:
				var thr := step / 20.0
				_lever(v, k, thr)
				var kit := ClashKit.new()
				_gather_lever(kit, rig, v, k)
				for part: Node3D in [map, v.power_switch, v.power_button] + ([gun] if gun else []):
					kit.gather_part(rig, part)
				kit.arm(root)
				await physics_frame
				await physics_frame
				var space := root.world_3d.direct_space_state
				for fitting: String in least:
					for word in [lever, boot]:
						if kit.group(word).is_empty():
							continue
						var n: int = kit.crossing_edges(space, word, fitting)
						if n > 0:
							through["%s %s through %s" % [word, "at %.0f%%" % (thr * 100.0), fitting]] = n
						var g: Array = kit.gap(space, word, fitting)
						if float(g[0]) < float(least[fitting]):
							least[fitting] = float(g[0])
							var p: Vector3 = g[1]
							where[fitting] = "%s at %.0f%%, at (%.3f, %.3f, %.3f)" % [word, thr * 100.0, p.x, p.y, p.z]
				kit.free_bodies()
				await physics_frame
			_lever(v, k, 0.5)
		_check("%s: the levers, idle to full, pass through nothing of the map or the power's controls (%s)" % [id, through], through.is_empty())
		_check("%s: and keep clear of the map's pod by %s mm (%s; %s wanted), of the POWER switch by %s mm (%s) and its button by %s mm (%s wanted)" % [
			id, _mm(least.MapPod), where.get("MapPod", "-"), _mm(MAP_GAP), _mm(least.PowerSwitch), where.get("PowerSwitch", "-"), _mm(least.PowerButton), _mm(POWER_GAP)],
			least.MapPod >= MAP_GAP and least.PowerSwitch >= POWER_GAP and least.PowerButton >= POWER_GAP)
		if gun:
			# ... and the lever on its side against its bat wherever the bat stands: thrown up, straight out (mid-throw:
			# nearest the lever) and thrown down
			var k := 1 if gun.position.x > 0.0 else 0
			var lever := "LeverL" if k == 0 else "LeverR"
			var boot := "ThrottleBootL" if k == 0 else "ThrottleBootR"
			var lean_was: float = (gun.lever as Node3D).rotation.x
			var gun_through := {}
			for lean in [-Switch.THROW_ANGLE, 0.0, Switch.THROW_ANGLE]:
				(gun.lever as Node3D).rotation.x = lean
				for step in 21:
					var thr := step / 20.0
					_lever(v, k, thr)
					var kit := ClashKit.new()
					_gather_lever(kit, rig, v, k)
					kit.gather_part(rig, gun)
					kit.arm(root)
					await physics_frame
					await physics_frame
					var space := root.world_3d.direct_space_state
					for word in [lever, boot]:
						if kit.group(word).is_empty():
							continue
						var n: int = kit.crossing_edges(space, word, "GunSwitch")
						if n > 0:
							gun_through["%s at %.0f%% through the GUN switch, its bat at %.0f deg" % [word, thr * 100.0, rad_to_deg(lean)]] = n
						var g: Array = kit.gap(space, word, "GunSwitch")
						if float(g[0]) < float(least.GunSwitch):
							least.GunSwitch = float(g[0])
							var p: Vector3 = g[1]
							where.GunSwitch = "%s at %.0f%%, its bat at %.0f deg, at (%.3f, %.3f, %.3f)" % [word, thr * 100.0, rad_to_deg(lean), p.x, p.y, p.z]
					kit.free_bodies()
					await physics_frame
				_lever(v, k, 0.5)
			(gun.lever as Node3D).rotation.x = lean_was
			_check("%s: and of the GUN switch by %s mm, its bat up, out or down (%s; %s wanted), passing through none of it (%s)" % [id, _mm(least.GunSwitch), where.get("GunSwitch", "-"), _mm(GUN_GAP), gun_through],
				least.GunSwitch >= GUN_GAP and gun_through.is_empty())

		# ---- in place: the whole cabin, the levers at idle
		for k in 2:
			_lever(v, k, 0.0)
		var all := ClashKit.new()
		all.gather(rig)
		all.arm(root)
		await physics_frame
		await physics_frame
		var space := root.world_3d.direct_space_state
		var mine: Array[int] = []
		mine.append_array(all.group("PowerSwitch"))
		mine.append_array(all.group("PowerButton"))
		var map_parts := all.group("MapPod")
		mine.append_array(map_parts)
		mine.append_array(all.group("GunSwitch"))
		var strangers := []
		var found := all.crossings(space, false, mine)
		for key: String in found:
			var rec: Dictionary = found[key]
			var a := String(rec.a).trim_prefix("shell/")
			var b := String(rec.b).trim_prefix("shell/")
			var power_a := a.begins_with("PowerSwitch") or a.begins_with("PowerButton")
			var power_b := b.begins_with("PowerSwitch") or b.begins_with("PowerButton")
			if (power_a and power_b) or (a.begins_with("MapPod") and b.begins_with("MapPod")):
				continue
			if (power_a or power_b) and (a.begins_with("cockpit_interior/ConsoleL") or b.begins_with("cockpit_interior/ConsoleL")):
				continue      # (the switch's panel and plinth and the button's bezel are let into the port console)
			var gun_a := a.begins_with("GunSwitch")
			var gun_b := b.begins_with("GunSwitch")
			if gun_a and gun_b:
				continue
			if (gun_a or gun_b) and Craft.phaethon_based(id) and (a.begins_with("cockpit_interior/ConsoleR") or b.begins_with("cockpit_interior/ConsoleR")):
				continue      # (the Phaethons' GUN switch's panel is let into the starboard console's inboard face)
			if (gun_a or gun_b) and id == Craft.BASILISK and BASILISK_GUN_KNOWN.any(func(w: String) -> bool: return (b if gun_a else a).begins_with(w)):
				print("NOTE %s: its GUN switch, where it has stood since 2026-11-23, crosses %s >< %s (%d edges)" % [id, a, b, rec.n])
				continue
			strangers.append("%s >< %s (%d edges)" % [a, b, rec.n])
		_check("%s: the POWER switch and its button cross nothing but the port console, the GUN switch nothing but the starboard console, and the map's pod nothing at all (%s)" % [id, strangers], strangers.is_empty())

		# ---- the reach
		var eye: Vector3 = Cockpit.EYE
		var shoulder := eye + Vector3(-0.18, -0.2, 0.05)
		var cap: Vector3 = to_rig * (v.power_button.global_transform * v.power_button.face_at())
		var bat: Vector3 = to_rig * (v.power_switch.global_transform * Vector3(0.0, 0.0, 0.07))
		var grips := []
		for thr in [0.5, 1.0]:
			_lever(v, 0, thr)
			grips.append(to_rig * (v.lever_pivots[0].global_transform * Vector3(0.0, 0.36, 0.0)))
		var to_cap := Vector3(cap.distance_to(grips[0]), cap.distance_to(grips[1]), cap.distance_to(shoulder))
		var to_bat := Vector3(bat.distance_to(grips[0]), bat.distance_to(grips[1]), bat.distance_to(shoulder))
		_check("%s: the button's cap is %.3f m from the left grip at half throttle, %.3f at full, %.3f from the shoulder (at most %.2f, %.2f, %.2f)" % [
			id, to_cap.x, to_cap.y, to_cap.z, BUTTON_REACH.x, BUTTON_REACH.y, BUTTON_REACH.z],
			to_cap.x <= BUTTON_REACH.x and to_cap.y <= BUTTON_REACH.y and to_cap.z <= BUTTON_REACH.z)
		_check("%s: the switch's bat is %.3f m from it at half throttle, %.3f at full, %.3f from the shoulder (at most %.2f, %.2f, %.2f)" % [
			id, to_bat.x, to_bat.y, to_bat.z, SWITCH_REACH.x, SWITCH_REACH.y, SWITCH_REACH.z],
			to_bat.x <= SWITCH_REACH.x and to_bat.y <= SWITCH_REACH.y and to_bat.z <= SWITCH_REACH.z)
		var to_gun := Vector3.ZERO
		if gun:
			var gun_bat: Vector3 = to_rig * (gun.global_transform * Vector3(0.0, 0.0, 0.07))
			var side := signf(gun_bat.x)
			var k := 1 if side > 0.0 else 0      # (the lever, and the shoulder, on its side)
			var gun_grips := []
			for thr in [0.5, 1.0]:
				_lever(v, k, thr)
				gun_grips.append(to_rig * (v.lever_pivots[k].global_transform * Vector3(0.0, 0.36, 0.0)))
			_lever(v, k, 0.5)
			to_gun = Vector3(gun_bat.distance_to(gun_grips[0]), gun_bat.distance_to(gun_grips[1]), gun_bat.distance_to(eye + Vector3(0.18 * side, -0.2, 0.05)))
			var bar: Vector3 = BASILISK_GUN_REACH if id == Craft.BASILISK else GUN_REACH
			_check("%s: the GUN switch's bat is %.3f m from the %s grip at half throttle, %.3f at full, %.3f from that shoulder (at most %.2f, %.2f, %.2f)" % [
				id, to_gun.x, "right" if side > 0.0 else "left", to_gun.y, to_gun.z, bar.x, bar.y, bar.z],
				to_gun.x <= bar.x and to_gun.y <= bar.y and to_gun.z <= bar.z)

		# ---- in sight from the seat, the levers at idle and at full
		var looks := {"the button's cap": [cap, "PowerButton"],
			"its ring's top": [to_rig * (v.power_button.global_transform * Vector3(0.0, 0.008 + 0.0137, 0.002)), "PowerButton"],
			"the ARM lamp": [to_rig * (v.power_switch.global_transform * Vector3(0.0, 0.05, 0.009)), "PowerSwitch"],
			"the SAFE lamp": [to_rig * (v.power_switch.global_transform * Vector3(0.0, -0.05, 0.009)), "PowerSwitch"]}
		for sx in [-1.0, 0.0, 1.0]:
			for sy in [-1.0, 0.0, 1.0]:
				looks["the map's screen at (%+.0f, %+.0f)" % [sx, sy]] = [to_rig * (map.global_transform * Vector3(sx * (MapPanel.W / 2.0 - 0.006), sy * (MapPanel.H / 2.0 - 0.006), 0.002)), "MapPod"]
		if gun:
			looks["the GUN lamp"] = [to_rig * (gun.global_transform * Vector3(0.0, 0.05, 0.009)), "GunSwitch"]
			looks["the GUN switch's SAFE lamp"] = [to_rig * (gun.global_transform * Vector3(0.0, -0.05, 0.009)), "GunSwitch"]
		var hidden := []
		for thr in [0.0, 1.0]:
			all.free_bodies()
			for k in 2:
				_lever(v, k, thr)
			all = ClashKit.new()
			all.gather(rig)
			all.arm(root)
			await physics_frame
			await physics_frame
			space = root.world_3d.direct_space_state
			for what: String in looks:
				if (what == "the SAFE lamp" or what == "the GUN switch's SAFE lamp") and thr > 0.0:
					continue      # (the shaft at full throttle: see the header)
				var at: Vector3 = looks[what][0]
				for part in all.sight(space, eye, eye + (at - eye) * 0.995):
					if not part.contains(String(looks[what][1])) and not part.contains("XROrigin3D"):
						hidden.append("%s behind %s, levers at %.0f%%" % [what, part.trim_prefix("shell/"), thr * 100.0])
						break
		all.free_bodies()
		_check("%s: from the seat nothing hides the button, its ring, the switch's ARM lamp, the GUN lamp or the map's screen with the levers at idle or full, nor the SAFE lamps at idle (%s)" % [id, hidden], hidden.is_empty())
		print("REACH %s: button %.3f / %.3f / %.3f m, switch %.3f / %.3f / %.3f m, GUN switch %s (grip at half, at full, shoulder)" % [id, to_cap.x, to_cap.y, to_cap.z, to_bat.x, to_bat.y, to_bat.z,
			("%.3f / %.3f / %.3f m" % [to_gun.x, to_gun.y, to_gun.z]) if gun else "none"])
		v.free()
		await process_frame
	View.vehicle_override = ""
	print("COCKPIT REACH %s (%d checks, %d failures)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)
