## Actual GPU A/B test: fixed real cockpit eye, distant dark/light targets, real canopy.
extends SceneTree
const CanopyScript := preload("res://view/canopy.gd")
var failed := 0
var baseline := false
var out := ""
var cam: Camera3D
var canopy: Node3D
var results := []
func _initialize() -> void:
	_run.call_deferred()
func _capture() -> Image:
	for k in 4: await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()
func _difference(a: Image,b: Image,rect: Rect2i) -> float:
	var delta := 0.0
	var n := 0
	for y in range(rect.position.y,rect.end.y,2):
		for x in range(rect.position.x,rect.end.x,2):
			var ca := a.get_pixel(x,y)
			var cb := b.get_pixel(x,y)
			delta += (absf(ca.r-cb.r)+absf(ca.g-cb.g)+absf(ca.b-cb.b))/3.0
			n+=1
	return delta/maxi(n,1)
func _run() -> void:
	baseline = "--baseline" in OS.get_cmdline_user_args()
	out=ProjectSettings.globalize_path("res://../evidence/v026-contrast"+("-before" if baseline else "-after"))
	DirAccess.make_dir_recursive_absolute(out)
	root.msaa_3d=Viewport.MSAA_4X
	var env := WorldEnvironment.new()
	env.environment=Environment.new()
	var e := env.environment
	e.background_mode=Environment.BG_COLOR
	e.background_color=Color(0.58,0.68,0.80)
	e.tonemap_mode=Environment.TONE_MAPPER_ACES
	e.tonemap_exposure=1.05
	e.glow_enabled=true
	e.glow_intensity=0.55
	e.glow_blend_mode=Environment.GLOW_BLEND_MODE_SOFTLIGHT
	e.fog_enabled=true
	e.fog_density=0.00011
	root.add_child(env)
	# 10-km target wall spans the full view. Dark/light columns reveal additive veiling.
	for i in range(-12,13):
		var target := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size=Vector2(2000,40000)
		target.mesh=quad
		target.position=Vector3(i*2000,0,-10000)
		var mat := StandardMaterial3D.new()
		mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color=Color(0.035,0.045,0.055) if i%2==0 else Color(0.7,0.72,0.75)
		target.material_override=mat
		root.add_child(target)
	canopy=CanopyScript.build()
	root.add_child(canopy)
	cam=Camera3D.new()
	cam.fov=100
	cam.far=120000
	root.add_child(cam)
	var field: MeshInstance3D=canopy.get_node("field")
	for eye in [Vector3(0,0.12,0.6),Vector3(-0.22,0.26,0.5),Vector3(0.22,0.12,0.8)]:
		cam.position=eye
		field.hide()
		var clear := await _capture()
		clear.save_png(out.path_join("eye%d-clear.png"%results.size()))
		field.show()
		for mph in [0.0,2000.0,6000.0,10000.0]:
			for mode in ["normal","burner"]:
				CanopyScript.update(canopy,mph/2.236936,0.0,mode,0.0)
				var im := await _capture()
				var size := im.get_size()
				var central := Rect2i(Vector2i(size.x*0.34,size.y*0.35),Vector2i(size.x*0.32,size.y*0.30))
				var centre := _difference(im,clear,central)
				var full := _difference(im,clear,Rect2i(Vector2i.ZERO,size))
				results.append({"eye":str(eye),"mph":mph,"mode":mode,"central_delta":centre,"full_delta":full})
				if mph>0 and (centre>0.008 or full<0.0001): failed+=1
				if mph in [0.0,6000.0] and mode=="normal": im.save_png(out.path_join("capture%d-%d.png"%[results.size(),int(mph)]))
		# A visible peripheral impact flash at rest and speed, then exact decay.
		for mph in [0.0,6000.0]:
			canopy.set_meta("flash",0.0)
			CanopyScript.update(canopy,mph/2.236936,0.0,"normal",0.0)
			var before := await _capture()
			CanopyScript.flash(canopy,1.0)
			CanopyScript.update(canopy,mph/2.236936,0.0,"normal",0.0)
			var flashed := await _capture()
			var size := flashed.get_size()
			var centre := _difference(flashed,clear,Rect2i(Vector2i(size.x*0.34,size.y*0.35),Vector2i(size.x*0.32,size.y*0.30)))
			var change := _difference(flashed,before,Rect2i(Vector2i.ZERO,size))
			CanopyScript.update(canopy,mph/2.236936,0.0,"normal",CanopyScript.FLASH_T+0.01)
			# Freeze flow to the unflashed sample so decay compares identical streaks.
			(field.material_override as ShaderMaterial).set_shader_parameter("flow",0.0)
			canopy.set_meta("flow",0.0)
			var after := await _capture()
			var decay := _difference(before,after,Rect2i(Vector2i.ZERO,size))
			results.append({"eye":str(eye),"mph":mph,"flash_delta":change,"flash_central":centre,"decayed_delta":decay})
			if change < 0.0005 or centre > 0.008 or decay > 0.002: failed+=1
			flashed.save_png(out.path_join("flash%d-%d.png"%[results.size(),int(mph)]))
	var file := FileAccess.open(out.path_join("measurements.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(results,"  "))
	file.close()
	print("CANOPY CONTRAST ","PASS" if failed==0 else "FAIL"," conditions=",results.size()," failed=",failed," baseline=",baseline)
	canopy.free()
	quit(0 if baseline or failed==0 else 1)
