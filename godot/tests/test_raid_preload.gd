## What Raids make at load, so a first frame in flight is not a hitch (Raids stage 2, task 11; Ruling D). Measured
## windowed (tests/probe_raid_firsts.gd), cold: the Kiln's first arming was 15 to 22 ms over the frames before it, the
## Vesper's 15, the third raid's arrival (the gunship's) 18 to 20: each the first frame of a drawing whose pipeline was
## compiled then (the lance's beam, the pulse's ring, the gunship's glow), made in that frame. Made at load instead, with
## Raids on only. In the VR seat on the Network (XR off), before any raid:
##   Raids off   (first, so the resource cache is the flight's own) the Kiln, the Vesper: no director, no flyers node, no
##               fire control, the mount's drawing not made (beam, ring null), no Arms node, the gunship's model not in
##               the resource cache
##   Raids on    the Phaethon, the Shrike, the Kiln, the Vesper, the Orrery, 60 frames flown: the flyers' gunship model
##               made and hidden, its shots' batch empty, none of it a flyer (all() empty, gunship() null), the drones'
##               batch not made (its first arrival measured under the line); the fire control made at load and
##               dormant; the Kiln's beam and its glow, the Vesper's ring, made under it and not drawn; the Shrike's and
##               the Orrery's drawing not made (their first frames measured under the line)
## --headless --xr-mode off --fixed-fps 120 --audio-driver Dummy -s res://tests/test_raid_preload.gd -- --mute
## Prints RAID PRELOAD PASS.
extends SceneTree

const Seat := preload("res://vr/vr_cockpit.gd")
const Pilot := preload("res://sim/pilot_craft.gd")
const Raids := preload("res://view/network_raids.gd")
const Chase := preload("res://view/network_chase.gd")
const GUNSHIP_PATH := "res://art/traffic/raid_gunship.glb"
const PREFS := "user://vr_prefs.json"
const DT := 1.0 / 120.0
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(label: String, passed: bool) -> void:
	print(("PASS " if passed else "FAIL ") + label)
	failures += int(not passed)


func _seat(id: String, raids_on: bool):
	Raids.pinned = true
	Raids.enabled = raids_on
	Chase.pinned = true
	Chase.enabled = false
	Seat.track_override = "network"
	Seat.job_override = "none"
	Seat.camera = "cockpit"
	Seat._camera_loaded = true
	Seat._nose_loaded = true
	Seat._slide_loaded = true
	Seat._startup_loaded = true
	Seat.cold_start = false
	Seat._map_loaded = true
	Seat._school_loaded = true
	Seat.vehicle_override = id
	Seat.best_dir = OS.get_user_data_dir().path_join("test_raid_preload_")
	var v = Seat.new()
	root.add_child(v)
	await process_frame
	v.set_process(false)
	for i in 60:
		v._process(DT)
		await process_frame
	return v


func _run() -> void:
	var prefs_existed := FileAccess.file_exists(PREFS)
	var prefs := FileAccess.get_file_as_bytes(PREFS) if prefs_existed else PackedByteArray()
	for id in [Pilot.KILN, Pilot.VESPER]:
		var v = await _seat(id, false)
		var m = v.craft.weapon
		var arms: Array = v.find_children("Arms", "", true, false)
		_check("Raids off, %s: no director (%s), no flyers node (%s), no fire control (%s), its drawing not made (%s), no Arms node (%d), the gunship's model not in the cache (%s)" % [
				id, v.raids, v.find_child("raid_flyers", true, false), v.gunnery, m.get("beam") if id == Pilot.KILN else m.get("ring"), arms.size(), ResourceLoader.has_cached(GUNSHIP_PATH)],
			v.raids == null and v.find_child("raid_flyers", true, false) == null and v.gunnery == null and arms.is_empty() and not ResourceLoader.has_cached(GUNSHIP_PATH)
				and (m.get("beam") if id == Pilot.KILN else m.get("ring")) == null)
		v.queue_free()
		await process_frame
	for id in [Pilot.STANDARD, Pilot.SHRIKE, Pilot.KILN, Pilot.VESPER, Pilot.ORRERY]:
		var v = await _seat(id, true)
		var R = v.raids
		var F = R.flyers if R != null else null
		if F == null:
			_check("Raids on, %s: a director and its flyers (%s)" % [id, R], false)
			v.queue_free()
			await process_frame
			continue
		var g = v.gunnery
		var m = v.craft.weapon
		var ship_fine: bool = F.ship != null and not F.ship.visible and F._glow != null and F._glow.multimesh.visible_instance_count == 0 and F.all().is_empty() and F.gunship() == null
		_check("Raids on, %s, before any raid: the gunship's model made (%s), hidden (%s), its shots' batch empty (%s), no flyer (%d, gunship %s), the drones' batch not made (%s), the model in the cache (%s)" % [
				id, F.ship, F.ship.visible if F.ship else "-", F._glow.multimesh.visible_instance_count if F._glow else -1, F.all().size(), F.gunship(), F.batch, ResourceLoader.has_cached(GUNSHIP_PATH)],
			ship_fine and F.batch == null and ResourceLoader.has_cached(GUNSHIP_PATH) and R.state == "")
		var dormant: bool = g != null and g.dormant
		if id == Pilot.KILN:
			_check("Raids on, the Kiln: its fire control dormant (%s), the beam made under it (%s) and hidden (%s), its glow empty (%s)" % [dormant, m.beam,
					m.beam.visible if m.beam else "-", m.glow.visible_instance_count if m.glow else -1],
				dormant and m.beam != null and m.beam.get_parent() == g and not m.beam.visible and m.glow != null and m.glow.visible_instance_count == 0 and not m.burning)
		elif id == Pilot.VESPER:
			_check("Raids on, the Vesper: its fire control dormant (%s), the ring made under it (%s) and hidden (%s), none released (%d)" % [dormant, m.ring,
					m.ring.visible if m.ring else "-", m.released],
				dormant and m.ring != null and m.ring.get_parent() == g and not m.ring.visible and m.released == 0 and m.drawn_r < 0.0)
		elif id == Pilot.SHRIKE:
			_check("Raids on, the Shrike: its fire control dormant (%s), its batches not made (darts %s): its first frames measured under the line" % [dormant, m.dart_batch],
				dormant and m.dart_batch == null)
		elif id == Pilot.ORRERY:
			_check("Raids on, the Orrery: its fire control dormant (%s), its streaks not made (%s): its first frames measured under the line" % [dormant, m.streaks],
				dormant and m.streaks == null)
		v.queue_free()
		await process_frame
	Seat.vehicle_override = ""
	Raids.pinned = false
	Raids.enabled = false
	if prefs_existed:
		var file := FileAccess.open(PREFS, FileAccess.WRITE)
		file.store_buffer(prefs)
		file.close()
	elif FileAccess.file_exists(PREFS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	print("RAID PRELOAD %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)
