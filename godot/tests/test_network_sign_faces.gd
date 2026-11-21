## Exercise the same builders as streaming, including co-located exit choices.
## A rendered run also samples an actual sequenced arrow twice.
extends SceneTree

const World := preload("res://view/network_world.gd")
const Sim := preload("res://sim/craft_sim.gd")
var failures := 0
var steep := 0          # boards met on a deck steep enough to lean them (Helios's face)
var checks := 0
var examples := {}
var kinds := {}
var paired := 0
var terminals := 0

func _initialize() -> void:
	_run.call_deferred()

func check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
		if failures < 20:
			print("FAIL ",label)

func _run() -> void:
	var sim := Sim.new({"track":"network"})
	var world := World.new()
	root.add_child(world)
	world.build(sim,null)
	var chunk := Node3D.new()
	root.add_child(chunk)
	for key in world._signs:
		var stations := {}
		var road = sim.roads[key.x]
		for spec in world._signs[key]:
			var i := int(spec[0])
			if not stations.has(i):
				stations[i] = Node3D.new()
				chunk.add_child(stations[i])
			var node: Node3D = stations[i]
			var previous := node.get_child_count()
			world._sign(node,road,key.x,road.px[i],road.py[i],spec)
			if spec[2]=="terminal" and spec[1]<0:
				check("reverse terminal spec reuses its peer",node.get_child_count()==previous)
				continue
			var holder := node.get_child(-1) as Node3D
			# (a board stands along the deck's own up: straight up everywhere but Helios's face, where it is
			# the deck's normal, and there it faces the approach along the deck)
			var up: Vector3 = world._deck_up(key.x,road,i)
			var outward := Vector3(-road.tx[i],0,road.ty[i])*float(spec[1])
			outward = (outward-up*outward.dot(up)).normalized()
			steep += int(up.dot(Vector3.UP)<0.99)
			_check_faces(holder,spec,outward,up)
			kinds[spec[2]] = true
			if spec[2]=="terminal": terminals += 1
			if spec[2] in ["jump","fork"] and not examples.has(spec[2]):
				examples[spec[2]] = holder.duplicate()
		for node: Node3D in stations.values():
			var spans := node.find_children("SignSpan_*","MeshInstance3D",false,false)
			check("one structural span per occupied station",spans.size()==1)
			var boards := node.find_children("Sign_*","Node3D",false,false)
			for a in boards.size():
				for b in range(a+1,boards.size()):
					var left: MeshInstance3D = boards[a].get_node("Approach/LegendPanel")
					var right: MeshInstance3D = boards[b].get_node("Approach/LegendPanel")
					var separation := absf(left.to_local(right.global_position).x)
					check("co-located faces are physically separated",separation >= (left.mesh.size.x+right.mesh.size.x)/2.0)
					paired += 1
			node.free()
	check("all nine sign families (the stunt roads' warnings are the ninth): %s" % [kinds.keys()],kinds.size()==9 and kinds.has("stunt"))
	check("five double-faced terminal signs",terminals==5)
	check("paired exit gantries were built",paired>=30)
	for key: Vector3i in world._exits:
		var info: Dictionary = world._exits[key]
		var P = sim.roads[key.x]
		var C = sim.roads[key.y]
		var i: int = info.mouth
		var lateral: float = (C.px[key.z]-P.px[i])*P.nx[i]+(C.py[key.z]-P.py[i])*P.ny[i]
		var travel: float = signf(C.tx[key.z]*P.tx[i]+C.ty[key.z]*P.ty[i])*(1 if key.z==0 else -1)
		check("plaque side agrees with physical ramp",info.side==(-1 if lateral*travel>0 else 1))
		check("exit number comes from highway mileage",int(info.number)==maxi(1,roundi(world._s[key.x][i]/world.MILE)))
	world.free()
	chunk.free()
	if DisplayServer.get_name()!="headless":
		await _render_arrows()
	for board: Node in examples.values(): board.free()
	check("some boards stand on a deck steep enough to lean them, and stand square to it (%d)" % steep,steep>=2)
	print("NETWORK SIGN FACES %s (%d checks, %d paired gantries, %d failures)" % ["PASS" if failures==0 else "FAIL",checks,paired,failures])
	quit(int(failures>0))

func _check_faces(holder: Node3D,spec: Array,outward: Vector3,up: Vector3) -> void:
	var kind := str(spec[2])
	var info: Dictionary = spec[4]
	for reverse in [false,true]:
		var root_face: Node3D = holder.get_node("Reverse" if reverse else "Approach")
		var panel: MeshInstance3D = root_face.get_node("LegendPanel")
		var normal := root_face.global_basis.z
		var mat: ShaderMaterial = panel.material_override
		check("panel faces approach upright",normal.dot(-outward if reverse else outward)>0.99 and root_face.global_basis.y.dot(up)>0.99)
		var labels := root_face.find_children("*","Label3D",true,false)
		var words := []
		for label: Label3D in labels:
			words.append(label.text)
			var face := label.get_parent() as MeshInstance3D
			var width: float = label.font.get_string_size(label.text,HORIZONTAL_ALIGNMENT_LEFT,-1,label.font_size).x*label.pixel_size
			var start := label.position.x
			if label.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER: start -= width/2.0
			elif label.horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT: start -= width
			check("legend stays inside its own panel",start >= -face.mesh.size.x/2.0 and start+width <= face.mesh.size.x/2.0)
			check("type is on the outward surface",label.position.z>0 and label.global_basis.z.dot(normal)>0.99 and not label.double_sided)
		# Check the actual frame surface between the pilot and the middle of every legend.
		# The truss and all carrier parts must be behind the sign's visible plane.
		var mount: MeshInstance3D = holder.get_node("Mount")
		var local_front := mount.to_local(panel.global_position)
		var extent := mount.mesh.get_aabb()
		check("printed face clears solid carrier",local_front.z<extent.position.z if reverse else local_front.z>extent.end.z)
		var arrow := int(mat.get_shader_parameter("arrow_side"))
		if reverse:
			check("reverse face never directs into a ramp",arrow==0 and not root_face.has_node("ExitPlaque"))
			var front: MeshInstance3D = holder.get_node("Approach/LegendPanel")
			if kind == "terminal" or info.has("reverse_lines"):
				check("both valid approaches receive a full-size sign", panel.mesh.size == front.mesh.size)
			else:
				check("opposing traffic sees exposed hardware and an identification plate", panel.mesh.size == front.mesh.size * World.Signs.Gantry.ID_SCALE and mat.get_shader_parameter("field") == World.Signs.ID_SILVER)
		var shield := panel.get_node_or_null("RouteMarker") as MeshInstance3D
		if shield:
			var stock: ShaderMaterial = shield.material_override
			check("shield uses the receiving road class", stock.get_shader_parameter("expressway") == not str(info.route).begins_with("S"))
			check("route number and shield receive the craft light", (shield.layers & shield.get_child(0).layers & World.Signs.SHEETING_LAYER) != 0)
		if kind in ["jump","fork"]:
			check("jump keeps its name and minimum",str(spec[3][0]).replace("ASCENT ","Ascent ") in words and spec[3][1] in words)
			var entry := World.Signs._entry_text(spec[3][2])
			check("jump keeps directional instructions on valid side",( "OPPOSITE APPROACH" if reverse else entry ) in words)
			check("only front arrow has working lamps",bool(mat.get_shader_parameter("beacons"))==not reverse)
			if not reverse:
				check("jump arrow angle",is_equal_approx(mat.get_shader_parameter("arrow_angle"),PI/4 if kind=="jump" else PI/2))
		elif kind=="terminal":
			check("both terminal faces name city",str(spec[3][0]).capitalize() in words)
		elif reverse:
			check("opposing guidance only on a real reverse corner", "OPPOSITE APPROACH" in words or info.has("reverse_lines"))
		if not reverse and info.has("number"):
			var tab: MeshInstance3D = root_face.get_node("ExitPlaque")
			check("correct mile-based exit number","EXIT "+str(info.number) in words)
			check("tab and arrow at signed edge",signf(tab.position.x)==info.side and (arrow==0 or arrow==info.side))
			check("left exit patch only on left",("LEFT" in words)==(info.side<0))
			if info.has("decision"): check("direction sign has an arrow",arrow==info.side)
		if not reverse and kind=="exit" and spec[3][0]=="EXIT":
			for row in spec[3].slice(1):
				var fields := str(row).split("  ",false)
				check("city and mileage survive layout",fields[0].capitalize() in words and fields[1].trim_suffix(" MI") in words)

func _render_arrows() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#384752")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 0.85
	var camera := Camera3D.new()
	camera.environment = env
	camera.fov = 52
	root.add_child(camera)
	for kind in examples:
		var board: Node3D = examples[kind]
		root.add_child(board)
		var face: MeshInstance3D = board.get_node("Approach/LegendPanel")
		var size: Vector2 = face.mesh.size
		camera.position = face.to_global(Vector3(0,0,size.x*0.82))
		camera.look_at(face.global_position)
		for f in 5: await process_frame
		await RenderingServer.frame_post_draw
		var first := root.get_texture().get_image()
		var side := float(face.material_override.get_shader_parameter("arrow_side"))
		var center := Vector3(side*(size.x/2.0-size.y*0.48),size.y*0.245/2.0,0)
		# The projected points use logical viewport units. The readback uses
		# framebuffer pixels, which differ under canvas_items window stretching.
		var pixels := Vector2(first.get_size()) / root.get_visible_rect().size
		var a := pixels * camera.unproject_position(face.to_global(center+Vector3(-0.35,0.35,0)*size.y))
		var b := pixels * camera.unproject_position(face.to_global(center+Vector3(0.35,-0.35,0)*size.y))
		await create_timer(0.4).timeout
		await RenderingServer.frame_post_draw
		var second := root.get_texture().get_image()
		var changed := 0
		for y in range(maxi(0,int(a.y)),mini(second.get_height(),int(b.y))):
			for x in range(maxi(0,int(a.x)),mini(second.get_width(),int(b.x))):
				if absf(first.get_pixel(x,y).r-second.get_pixel(x,y).r)>0.07: changed += 1
		check(kind+" arrow sequencer visible across two real frames",changed>=10)
		root.remove_child(board)
	camera.free()
