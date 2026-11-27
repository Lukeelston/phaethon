## What the Shrike's first arming costs, in parts (Ruling D, Raids stage 2 Task 5): in the VR seat on the Network (XR
## off, Raids off), cold (the first Shrike arms of the run): Codex's arms fitted on the seat's hull (Shrike.ensure_arms),
## their first deploy (set_deploy past 0: the hull is cut for the cassettes, view/arms/shrike_arms.gd fit_pod), the next,
## and the fire control's own build (view/gunnery.gd make). Headless: no GPU upload or pipeline compile is in it.
## With --raids=on: Raids on (the fire control made at load, dormant, and the arms fitted then, stowed: prepare), the
## view's whole frame before the GUN is thrown, the frame it is thrown and the next three, cold.
## --headless --xr-mode off --fixed-fps 120 --audio-driver Dummy -s res://tests/probe_missile_arming.gd -- --mute [--raids=on]
extends SceneTree

const Seat := preload("res://vr/vr_cockpit.gd")
const Shrike := preload("res://view/shrike_airframe.gd")
const GunneryScript := preload("res://view/gunnery.gd")
const Raids := preload("res://view/network_raids.gd")
const Chase := preload("res://view/network_chase.gd")
const DT := 1.0 / 120.0


func _initialize() -> void:
	_run.call_deferred()


func _ms(t0: int) -> float:
	return (Time.get_ticks_usec() - t0) / 1000.0


func _run() -> void:
	var raids_on := OS.get_cmdline_user_args().has("--raids=on")
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
	Seat.vehicle_override = "shrike"
	var v = Seat.new()
	root.add_child(v)
	await process_frame
	v.set_process(false)
	for i in 10:
		v._process(DT)
	if raids_on:
		var frames := []
		for i in 5:
			v.gun_wanted = i >= 1
			var t := Time.get_ticks_usec()
			v._process(DT)
			frames.append(snappedf(_ms(t), 0.01))
		print("PROBE MISSILE ARMING (Raids on): the view's whole frame before the GUN %.2f ms, the frame it is thrown %.2f ms, the next three %s; arms built at load %s" % [
			frames[0], frames[1], frames.slice(2), v.shell.get_node("PodHull").get_node_or_null("Arms") != null])
		Seat.vehicle_override = ""
		v.queue_free()
		await process_frame
		quit(0)
		return
	var hull: Node3D = v.shell.get_node("PodHull")
	var t0 := Time.get_ticks_usec()
	var arms = Shrike.ensure_arms(hull)
	var fit := _ms(t0)
	t0 = Time.get_ticks_usec()
	arms.set_deploy(DT)
	var first := _ms(t0)
	t0 = Time.get_ticks_usec()
	arms.set_deploy(2.0 * DT)
	var second := _ms(t0)
	t0 = Time.get_ticks_usec()
	arms.set_deploy(0.0)
	var stowed := _ms(t0)
	t0 = Time.get_ticks_usec()
	var g = GunneryScript.make(v)
	var gun := _ms(t0)
	print("PROBE MISSILE ARMING: the arms fitted %.2f ms, their first deploy %.2f ms, the next %.2f ms, stowed again %.2f ms; the fire control's build %.2f ms (its own figure %.2f)" % [
		fit, first, second, stowed, gun, g.build_ms])
	Seat.vehicle_override = ""
	v.queue_free()
	await process_frame
	quit(0)
