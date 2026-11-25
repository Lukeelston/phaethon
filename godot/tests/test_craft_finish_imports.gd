## Inspect what the renderer receives, including import processing/compression.
extends SceneTree
var failures := 0
func check(label: String, ok: bool) -> void:
	print("PASS " if ok else "FAIL ",label)
	failures += int(not ok)
func _initialize() -> void:
	for path in ["res://art/pilot_fleet/finish_orm.png","res://art/shrike/orm.png"]:
		var settings := ConfigFile.new()
		settings.load(path+".import")
		check(path+" keeps data-channel alpha untouched",not settings.get_value("params","process/fix_alpha_border",true))
	var texture := load("res://art/pilot_fleet/finish_orm.png") as Texture2D
	var pixels := texture.get_image()
	if pixels.is_compressed():
		pixels.decompress()
	var metal := pixels.get_pixel(533,534)
	check("imported access fastener retains conductor response",metal.b>.70 and metal.a<.15)
	var paint := pixels.get_pixel(128,128)
	check("imported enamel remains dielectric and coated",paint.b<.03 and paint.a>.97)
	var cloth := pixels.get_pixel(820,384)
	check("imported cloth remains uncoated dielectric",cloth.b<.03 and cloth.a<.03)
	var vinyl := pixels.get_pixel(950,384)
	check("imported vinyl remains dry and uncoated",vinyl.b<.03 and vinyl.a<.03 and vinyl.g>.6)
	for id in ["orrery","kiln","vesper","basilisk"]:
		var mask := (load("res://art/pilot_fleet/"+id+"_livery.png") as Texture2D).get_image()
		if mask.is_compressed():
			mask.decompress()
		check(id+" vinyl still takes the selected accent",mask.get_pixel(950,384).g>.95)
	print("CRAFT FINISH IMPORTS ","PASS" if failures==0 else "FAIL")
	quit(int(failures>0))
