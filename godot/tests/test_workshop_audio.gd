## Run with --headless --xr-mode off --audio-driver Dummy. Repeat with -- --mute.
extends SceneTree

const Garage := preload("res://garage/garage.gd")
const Walker := preload("res://garage/garage_walker.gd")
const Audio := preload("res://garage/workshop_audio.gd")
const DT := 1.0 / 60.0
var checks := 0
var failures := 0
var walker: Walker
var contacts: Array = []
var motions: Array[bool] = []
var stops: Array[bool] = []


func _initialize() -> void:
	_run.call_deferred()


func check(passed: bool, label: String) -> void:
	checks += 1
	if not passed:
		failures += 1
		push_error(label)


func _walk(input: Vector2, frames: int) -> void:
	for i in frames:
		await physics_frame
		walker.step_locomotion(input,DT)


func _run() -> void:
	var garage := Garage.new()
	root.add_child(garage)
	current_scene = garage
	walker = garage.walker
	if walker == null or garage.environment == null:
		check(false,"The garage must finish constructing before testing its sound")
		garage.free()
		_finish()
		return
	walker.set_physics_process(false)
	var sound := garage.get_node_or_null("ShopAudio") as Audio
	if OS.get_cmdline_user_args().has("--mute"):
		check(sound == null, "Muted garage creates no room, shoe or door voices")
		garage.free()
		_finish()
		return
	if sound == null:
		check(false, "A normal garage creates its shop audio")
		_finish()
		return
	for name in ["RoomTone", "HallSupply", "AnnexReturn", "DoorDrive", "SpindleBearing"]:
		var source = sound.get_node(name)
		check(source.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD, "Continuous loop: " + name)
		check(source.stream.loop_end - source.stream.loop_begin > source.stream.mix_rate, "Whole recorded loop: " + name)
	for clip: AudioStreamWAV in Audio.Soles:
		check(clip.loop_mode == AudioStreamWAV.LOOP_DISABLED and not clip.stereo, "One-shot spatial shoe: " + clip.resource_path)
	var door := garage.environment.get_node("ServiceEntry")
	door.motion_started.connect(func(opening: bool): motions.append(opening))
	door.motion_finished.connect(func(opened: bool): stops.append(opened))
	walker.boot_planted.connect(func(side: int, at: Vector3, speed: float):
		contacts.append([side, at, speed, sound._boots[side].stream]))

	await _walk(Vector2.ZERO, 15)
	walker.rotate_y(.8)
	walker.rotate_y(-.8)
	await _walk(Vector2.ZERO, 15)
	check(contacts.is_empty(), "Remaining or turning in place produces no shoe contact")
	check(sound._exhaust.volume_db < -23.9 and sound._supply.volume_db > -15.1,
		"The closed door attenuates the interior return for a listener in the hall")
	await _walk(Vector2.UP, 115)
	await _walk(Vector2.ZERO, 20)
	check(contacts.size() >= 6 and contacts.size() <= 8, "Walking 4.5 m gives an anatomically plausible count")
	for i in contacts.size():
		var hit: Array = contacts[i]
		check(hit[0] == (i+1)%2 and absf(hit[1].y) < .10, "Sole alternates at floor height")
		check(hit[2] <= Walker.WALK_SPEED+.01 and hit[2] > 0, "Impact strength follows measured speed")
		if i > 0:
			check(hit[3] != contacts[i-1][3], "Adjacent impacts use different recordings")
			var along := absf(float(hit[1].z) - float(contacts[i-1][1].z))
			check(absf(along - Walker.Pilot.STRIDE*.5) < .08, "Sound originates at the planted foot")

	walker.set_seated(false,Transform3D(Basis.IDENTITY,Vector3(0,.01,23.14)))
	await _walk(Vector2.DOWN, 25)
	var held_count := contacts.size()
	await _walk(Vector2.DOWN, 60)
	check(held_count == contacts.size(), "Walking against a wall cannot make footsteps")
	walker.set_seated(true,garage.environment.seat_transform(Garage.Fleet.STANDARD))
	await _walk(Vector2.UP, 20)
	walker.set_seated(false,Transform3D(Basis.IDENTITY,Vector3(0,0,-19.65)))
	await _walk(Vector2.ZERO, 15)
	check(held_count == contacts.size(), "Boarding, dismounting and relocating are silent")

	await _walk(Vector2.UP, 205)
	await _walk(Vector2.ZERO, 125)
	check(walker.position.z < -26.8 and motions == [true,false] and stops == [true,false],
		"The pilot crosses the working portal and the drive follows one full cycle")
	check(not sound._motor.playing and sound._stop.volume_db > -15.0, "Sealing the closed door stops the drive")
	check(sound._exhaust.volume_db > -16.1 and sound._supply.volume_db < -21.9,
		"After entering, the closed door attenuates the exterior grille")
	var power := StartupSequence.new()
	power.hot()
	var hot_bay := garage._runup_for(Garage.Fleet.BASILISK, power)
	await _walk(Vector2.ZERO, 12)
	check(hot_bay._outside.size() == 2, "A hot parked Basilisk has independent exterior engines")
	for emitter in hot_bay._outside:
		check(emitter.playing and emitter.unit_size < 3.0 and emitter.attenuation_filter_cutoff_hz < 800.0,
			"A newly restored engine reaches the sealed room through its window")
	# Reverse part of a close without launching a second motor or leaving its old fade active.
	door.motion_started.emit(false)
	await _walk(Vector2.ZERO, 5)
	door.motion_started.emit(true)
	await _walk(Vector2.ZERO, 18)
	check(sound._motor.playing and sound._motor.pitch_scale > 1, "Reversing the door changes the existing drive")
	for emitter in hot_bay._outside:
		check(emitter.unit_size > 3.0 and emitter.unit_size < 4.0, "The outside engine sound opens up gradually")
	door.motion_finished.emit(true)
	await _walk(Vector2.ZERO, 12)
	check(not sound._motor.playing, "Opening endpoint releases the drive")
	await _walk(Vector2.ZERO, 55)
	for emitter in hot_bay._outside:
		check(is_equal_approx(emitter.unit_size, 4) and is_equal_approx(emitter.attenuation_filter_cutoff_hz, 5000),
			"Open doors restore the exterior player's original spatial settings")
	var station := garage.environment.inspection
	var bearing := sound._bearing
	check(not bearing.playing and bearing.global_position.is_equal_approx(station.rotor_contact_point()),
		"A parked wheel has a silent source at the spindle")
	station.spin_rotor(-1.0)
	await _walk(Vector2.ZERO, 1)
	var pushed_db := bearing.volume_db
	var pushed_pitch := bearing.pitch_scale
	check(bearing.playing and station.rotor_speed < 0, "A backward push starts the bearing")
	await _walk(Vector2.ZERO, 45)
	check(bearing.playing and bearing.volume_db < pushed_db and bearing.pitch_scale < pushed_pitch,
		"The bearing grows quieter and slower while coasting")
	await _walk(Vector2.ZERO, 160)
	check(not bearing.playing and is_zero_approx(station.rotor_speed), "The wheel stops silently")
	# A bay door's own drive, at its hood, and its seal on the sill (garage/bay_doors.gd).
	var doors = garage.environment.doors
	doors.set_open("kiln", true)
	await _walk(Vector2.ZERO, 3)
	var roller: Array = sound._rollers.get("kiln", [])
	var hood: Vector3 = garage.environment.door_transform("kiln") * Vector3(0, 5.05, .20)
	check(roller.size() == 2 and roller[0].playing and roller[0].global_position.distance_to(hood) < .01,
		"A rising bay door runs its own drive, at its hood")
	check(roller.size() == 2 and roller[0].max_distance > 40.0, "... heard from the seat at the far end of its bay")
	check(sound._rollers.size() == 1, "... and only that door's")
	doors.set_open("kiln", false)
	await _walk(Vector2.ZERO, 30)
	check(roller.size() == 2 and roller[0].pitch_scale < .8, "Reversed, the same drive runs on, lower")
	var landed := 0
	while doors.phase("kiln") != "shut" and landed < 600:
		await _walk(Vector2.ZERO, 1)
		landed += 1
	await _walk(Vector2.ZERO, 1)
	check(roller.size() == 2 and roller[1].playing, "Landing on the sill sounds the seal (shut after %d frames)" % landed)
	await _walk(Vector2.ZERO, 20)
	check(roller.size() == 2 and not roller[0].playing, "... and the drive stops")
	await _tracked_steps()
	var handles: Array[WeakRef] = []
	for child in sound.get_children():
		handles.append(weakref(child))
	for emitter in hot_bay._outside:
		handles.append(weakref(emitter))
	garage.free()
	await process_frame
	check(handles.all(func(handle: WeakRef): return handle.get_ref() == null), "Leaving the garage releases every source")
	# A fixed-FPS headless run can end sooner than one real device callback.
	# Give the dummy mixer a chance to drain its native PCM playbacks, too.
	var mix_ms := clampi(ceili(1000 * (AudioServer.get_time_since_last_mix() + AudioServer.get_time_to_next_mix())), 20, 120)
	for i in 3:
		OS.delay_msec(mix_ms)
		await process_frame
	_finish()


func _tracked_steps() -> void:
	walker.set_seated(false, Transform3D(Basis.IDENTITY,Vector3(0,0,8)))
	walker.set_process(false)
	walker.xr_live = true
	walker._xr_focused = true
	walker._align_tracking = false
	var baseline := contacts.size()
	# Move the head relative to tracking space, as the runtime does. Subtle
	# headset sway repeats enough to cross a stride if integrated as walking.
	for i in 240:
		await physics_frame
		walker._eye.position.x = .0028 if i % 2 == 0 else -.0028
		walker.step_locomotion(Vector2.ZERO, DT)
	check(contacts.size() == baseline, "Stationary headset jitter never clocks the pilot's gait")
	baseline = contacts.size()
	for i in 80:
		await physics_frame
		walker._eye.position.z -= .020
		walker.step_locomotion(Vector2.ZERO, DT)
	check(contacts.size() - baseline in [2,3], "Physically walking 1.6 metres without a thumbstick plants real feet")
	baseline = contacts.size()
	walker._eye.position.x += 1.7
	await _walk(Vector2.ZERO, 1)
	for i in 100:
		await physics_frame
		walker._turn_xr(.85,DT)
		walker.step_locomotion(Vector2.ZERO,DT)
	check(contacts.size() == baseline, "Tracking reacquisition and smooth turning cannot create footsteps")
	walker.xr_live = false


func _finish() -> void:
	print("WORKSHOP AUDIO %s (%d checks, %d failures)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)
